"""Phase 2：多景點行程排序（Tourist Trip Design Problem / OPTW）。

作法
----
1. 依類別 / 半徑 / 必訪條件，從 POI 資料挑出候選景點。
2. 用 Phase 1 的求路引擎，對候選景點做 n 次「單源最短路」，
   得到景點兩兩之間的旅行時間矩陣（秒）。這比 n² 次 A* 快得多。
3. 建立 OR-Tools RoutingModel：
     - 時間維度 + 各景點營業時間窗（opening_hours）
     - 停留時間（服務時間）
     - AddDisjunction：低價值景點可放棄、必訪景點給極大懲罰
     - 出發時間與總時數限制
4. 取出造訪順序，逐段用 A* 串接實際路線，輸出 GeoJSON。

成本單位一律是「秒」。
"""

from __future__ import annotations

import logging

import networkx as nx
import osmnx as ox
from ortools.constraint_solver import routing_enums_pb2, pywrapcp

from ..config import settings
from ..schemas import ItineraryRequest, LatLng
from ..services import poi as poi_service
from ..services.opening_hours import parse_opening_hours
from . import pathfinding

log = logging.getLogger(__name__)

BIG = 10 ** 7                 # OR-Tools 用的大數（近似無限）
BASE_REWARD_S = 1800          # 造訪一個景點的基礎價值（秒）
MUST_REWARD_S = 10 ** 9       # 必訪景點的懲罰（極大 → 不會被放棄）
HORIZON_S = 2 * 86400

# 各類別建議停留時間（分鐘）
DWELL_BY_CATEGORY = {
    "tourism": 40,
    "historic": 30,
    "natural": 30,
    "leisure": 25,
    "place": 15,
    "man_made": 20,
    "curated": 25,
    "heritage": 30,
    "amenity": 20,
    "food": 45,
}


def _parse_hhmm(s: str) -> int:
    h, m = s.strip().split(":")
    return int(h) * 3600 + int(m) * 60


def _fmt_hhmm(sec: int) -> str:
    sec = int(sec) % 86400
    return f"{sec // 3600:02d}:{(sec % 3600) // 60:02d}"


def _dwell_minutes(category: str, default: int) -> int:
    return DWELL_BY_CATEGORY.get(category, default)


def _effective_window(oh: str | None, departure: int, budget: int) -> tuple[int, int] | None:
    """把營業時間換算成與本趟行程重疊的時間窗；不重疊回 None。"""
    end = departure + budget
    win = parse_opening_hours(oh)
    if win is None:                       # 無法解析 → 視為全天
        return (departure, end)
    o = max(win[0], departure)
    c = min(win[1], end)
    return (o, c) if o < c else None


def _select_candidates(req: ItineraryRequest) -> list[dict]:
    cats = set(req.categories) if req.categories else None
    must_kw = [k.strip() for k in req.must_visit if k and k.strip()]

    pool: list[dict] = []
    for f in poi_service.query(limit=5000):
        p = f["properties"]
        name = p.get("name") or ""
        if not name:
            continue
        pool.append({
            "name": name,
            "name_zh": p.get("name_zh") or name,
            "lat": float(p["lat"]),
            "lng": float(p["lng"]),
            "category": p.get("category", "other"),
            "category_label": p.get("category_label", "其他"),
            "opening_hours": p.get("opening_hours"),
            "must": False,
        })

    # 必訪：每個關鍵字只挑「名稱最接近」的一筆，避免子字串誤抓一串同系列景點
    must: list[dict] = []
    chosen_names: set[str] = set()
    for kw in must_kw:
        matches = [it for it in pool if kw in it["name"]]
        if not matches:
            continue
        matches.sort(key=lambda it: len(it["name_zh"]))
        best = matches[0]
        best["must"] = True
        must.append(best)
        chosen_names.add(best["name"])

    # 其餘候選
    others: list[dict] = []
    for it in pool:
        if it["name"] in chosen_names:
            continue
        if cats is not None and it["category"] not in cats:
            continue
        d = ox.distance.great_circle(req.start.lat, req.start.lng, it["lat"], it["lng"])
        if d <= req.radius_m:
            it["dist_from_start"] = d
            others.append(it)

    others.sort(key=lambda x: x["dist_from_start"])
    room = max(req.max_candidates - len(must), 0)

    # 空間稀疏化：彼此太近的景點只留一個，避免「走 0 公尺就多一站」
    selected: list[dict] = []
    occupied = [(m["lat"], m["lng"]) for m in must]
    occupied.append((req.start.lat, req.start.lng))
    for item in others:
        if any(
            ox.distance.great_circle(item["lat"], item["lng"], la, lo) < req.min_spacing_m
            for la, lo in occupied
        ):
            continue
        occupied.append((item["lat"], item["lng"]))
        selected.append(item)
        if len(selected) >= room:
            break

    return must + selected


def solve(req: ItineraryRequest) -> dict:
    from ..graph.loader import get_graph

    G = get_graph()
    prefs = req.preferences
    speed = prefs.walking_speed_mps or settings.walking_speed_mps

    departure = _parse_hhmm(req.departure_time)
    budget = int(req.duration_hours * 3600)

    raw = _select_candidates(req)
    if not raw:
        raise ValueError("找不到符合條件的候選景點，請放寬類別或半徑")

    # 營業時間過濾 + 停留時間
    candidates: list[dict] = []
    skipped: list[str] = []
    for c in raw:
        window = _effective_window(c.get("opening_hours"), departure, budget)
        if window is None:
            skipped.append(c["name"] + ("（營業時間外）" if c["must"] else ""))
            continue
        c["window"] = window
        c["dwell_s"] = _dwell_minutes(c["category"], req.dwell_minutes) * 60
        candidates.append(c)

    if not candidates:
        raise ValueError("所有候選景點都在營業時間外，請調整出發時間或時數")

    n = len(candidates)
    end_index = n + 1                      # model node：0=起點, 1..n=景點, n+1=終點
    num_nodes = n + 2

    open_route = not req.round_trip and req.end is None
    end_point = req.start if req.round_trip else req.end

    # 圖節點
    start_g = pathfinding.nearest_node(G, req.start.lat, req.start.lng)
    graph_nodes: list[int] = [start_g] + [
        pathfinding.nearest_node(G, c["lat"], c["lng"]) for c in candidates
    ]
    if not open_route:
        graph_nodes.append(pathfinding.nearest_node(G, end_point.lat, end_point.lng))

    # 旅行時間矩陣（單源最短路 × 唯一節點數）
    D = pathfinding.build_cost_graph(G, prefs)
    real_count = len(graph_nodes)
    dist_by_node: dict[int, dict] = {}
    for src in dict.fromkeys(graph_nodes):
        dist_by_node[src] = (
            nx.single_source_dijkstra_path_length(D, src, weight="cost") if src in D else {}
        )

    mat = [[BIG] * num_nodes for _ in range(num_nodes)]
    for i in range(real_count):
        di = dist_by_node[graph_nodes[i]]
        for j in range(real_count):
            if i == j:
                mat[i][j] = 0
            else:
                v = di.get(graph_nodes[j])
                mat[i][j] = int(v) if v is not None else BIG
    if open_route:
        for i in range(real_count):
            mat[i][end_index] = 0
        for j in range(num_nodes):
            mat[end_index][j] = 0

    # ---- OR-Tools 模型 ----
    manager = pywrapcp.RoutingIndexManager(num_nodes, 1, [0], [end_index])
    routing = pywrapcp.RoutingModel(manager)

    def transit(fi: int, ti: int) -> int:
        return mat[manager.IndexToNode(fi)][manager.IndexToNode(ti)]

    routing.SetArcCostEvaluatorOfAllVehicles(routing.RegisterTransitCallback(transit))

    def time_transit(fi: int, ti: int) -> int:
        f = manager.IndexToNode(fi)
        t = manager.IndexToNode(ti)
        service = candidates[f - 1]["dwell_s"] if 1 <= f <= n else 0
        return mat[f][t] + service

    routing.AddDimension(
        routing.RegisterTransitCallback(time_transit), 1800, HORIZON_S, False, "Time"
    )
    time_dim = routing.GetDimensionOrDie("Time")

    # 注意：以 list 形式建立 RoutingIndexManager 時，對「終點」呼叫
    # manager.NodeToIndex(end_index) 會回傳 -1，若拿去 CumulVar() 會導致
    # access violation。務必用 routing.Start(0) / routing.End(0) 取得索引。
    time_dim.CumulVar(routing.Start(0)).SetRange(departure, departure)
    time_dim.CumulVar(routing.End(0)).SetRange(departure, departure + budget)

    for i, c in enumerate(candidates, start=1):
        o, cl = c["window"]
        time_dim.CumulVar(manager.NodeToIndex(i)).SetRange(o, cl)

    # 美食站數上限：美食點密集又便宜，若不限制會佔滿整趟行程。
    def food_count(fi: int, _ti: int) -> int:
        f = manager.IndexToNode(fi)
        return 1 if (1 <= f <= n and candidates[f - 1]["category"] == "food") else 0

    routing.AddDimension(
        routing.RegisterTransitCallback(food_count), 0, req.max_food_stops, True, "FoodCount"
    )

    for i, c in enumerate(candidates, start=1):
        penalty = MUST_REWARD_S if c["must"] else BASE_REWARD_S
        routing.AddDisjunction([manager.NodeToIndex(i)], penalty)

    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
    params.local_search_metaheuristic = (
        routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    )
    params.time_limit.FromSeconds(5)

    solution = routing.SolveWithParameters(params)
    if solution is None:
        raise ValueError("在此時間與範圍限制下找不到可行行程，請放寬條件")

    # ---- 取出順序 ----
    order: list[tuple[int, int]] = []
    idx = routing.Start(0)
    while not routing.IsEnd(idx):
        order.append((manager.IndexToNode(idx), solution.Value(time_dim.CumulVar(idx))))
        idx = solution.Value(routing.NextVar(idx))
    order.append((manager.IndexToNode(idx), solution.Value(time_dim.CumulVar(idx))))

    visited = {m for m, _ in order if 1 <= m <= n}
    for i, c in enumerate(candidates, start=1):
        if i not in visited:
            skipped.append(c["name"])

    if not visited:
        raise ValueError("時間不足以造訪任何景點，請增加時數或縮小範圍")

    def graph_of(model_node: int) -> int | None:
        if model_node == end_index:
            return None if open_route else graph_nodes[end_index]
        return graph_nodes[model_node]

    # ---- 串接實際路線 ----
    stops: list[dict] = []
    coords: list[list[float]] = []
    total_dist = 0.0
    prev_m = 0.0
    prev_s = 0.0
    order_no = 0

    for k, (mnode, t_arr) in enumerate(order):
        gn = graph_of(mnode)
        if k > 0:
            pgn = graph_of(order[k - 1][0])
            if pgn is not None and gn is not None:
                leg = pathfinding.path_between(G, D, pgn, gn, speed)
                total_dist += leg["distance_m"]
                seg = leg["geometry"]["coordinates"]
                if coords and seg and coords[-1] == seg[0]:
                    seg = seg[1:]
                coords.extend(seg)
                prev_m, prev_s = leg["distance_m"], leg["duration_s"]

        if 1 <= mnode <= n:
            c = candidates[mnode - 1]
            order_no += 1
            stops.append({
                "order": order_no,
                "name": c["name"],
                "category": c["category"],
                "category_label": c["category_label"],
                "lat": c["lat"],
                "lng": c["lng"],
                "arrival": _fmt_hhmm(t_arr),
                "departure": _fmt_hhmm(t_arr + c["dwell_s"]),
                "dwell_min": c["dwell_s"] // 60,
                "travel_from_prev_m": round(prev_m, 1),
                "travel_from_prev_s": round(prev_s, 1),
            })

    end_time = order[-1][1]
    return {
        "stops": stops,
        "num_visited": len(stops),
        "total_distance_m": round(total_dist, 1),
        "total_duration_min": round((end_time - departure) / 60, 1),
        "geometry": {"type": "LineString", "coordinates": coords},
        "skipped": skipped,
    }
