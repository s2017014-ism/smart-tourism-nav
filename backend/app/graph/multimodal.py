"""Phase 3：走 + 公車多模態路網。

節點模型（三層）
----------------
* 步行節點  ：沿用 OSMnx 步行圖節點（int id）        kind="walk"
* 站點節點  ：("S", pole_id) 每個實體巴士站          kind="station"
* 路線站節點：("RS", route, dir, idx) 某路線在某站停靠 kind="route_stop"

邊模型（mode，成本單位為秒）
---------------------------
* walk   ：步行圖的邊                cost = 長度 / 步行速度
* access ：步行節點 -> 站點           cost = 長度 / 步行速度
* egress ：站點 -> 步行節點           cost = 長度 / 步行速度
* board  ：站點 -> 路線站節點         cost = 候車時間 + 換乘懲罰
* alight ：路線站節點 -> 站點         cost = 0
* bus    ：路線站節點 -> 下一站節點   cost = 距離 × 繞行係數 / 公車速度

為何要「路線站節點」而不共用站點？因為這樣才能正確處理轉乘：
在同一站換路線時，路徑必經 alight(→站點) → board(→另一路線)，
因而付出一次換乘懲罰；若直接共用站點，換路線會變成免費。
"""

from __future__ import annotations

import heapq
import logging
import threading
from datetime import datetime, timedelta, timezone
from typing import Any

import networkx as nx
import osmnx as ox

from ..config import settings
from ..schemas import RoutePreferences
from ..optimize.slope import slope_factor

log = logging.getLogger(__name__)

# 成本參數（秒 / 公尺）
WAIT_TIME_S = 120.0          # 平均候車 2 分鐘（調降，避免等待時間過長）
TRANSFER_PENALTY_S = 0.0     # 不計轉乘成本（改以「最多轉乘次數」限制）
BUS_SPEED_MPS = 8.0          # 公車平均速度
BUS_DETOUR = 1.0             # 已採用實際道路線形，故不再額外加成

# 服務時間：N 系列（通宵線）只在 00:00–06:00 行駛，其餘路線 06:00–24:00。
NIGHT_PREFIXES = ("N",)
NIGHT_START_S = 0
NIGHT_END_S = 6 * 3600
_MACAU_TZ = timezone(timedelta(hours=8))

# 同一路口常有多個站位（不同 pole_id），彼此相距很近。為了讓轉乘可靠，
# 直接為相距 TRANSFER_WALK_M 以內的站點建立雙向步行邊（走直線，避免繞遠路）。
TRANSFER_WALK_M = 150.0
_WALK_MODES = ("walk", "access", "egress", "transfer")


def _parse_hhmm(s: str) -> int:
    h, m = s.strip().split(":")
    return (int(h) * 3600 + int(m) * 60) % 86400


def _fmt_hhmm(sec: int) -> str:
    sec %= 86400
    return f"{sec // 3600:02d}:{(sec % 3600) // 60:02d}"


def now_seconds() -> int:
    n = datetime.now(_MACAU_TZ)
    return n.hour * 3600 + n.minute * 60


def _route_runs(route: str, t: int | None) -> bool:
    """依出發時間判斷該路線是否營運。"""
    if t is None:
        return True
    if route.upper().startswith(NIGHT_PREFIXES):      # 通宵線
        return NIGHT_START_S <= t < NIGHT_END_S
    return NIGHT_END_S <= t < 24 * 3600               # 日間線

_H: nx.MultiDiGraph | None = None
_lock = threading.Lock()


def _build() -> nx.MultiDiGraph:
    from .loader import get_graph
    from ..services import bus_data

    G = get_graph()
    stops = bus_data.stops()
    routes = bus_data.routes()

    # 複製步行圖（比逐邊重建快得多），並標上 mode="walk"
    H = G.copy()
    for _, _, _, d in H.edges(keys=True, data=True):
        d["mode"] = "walk"

    # 2) 站點節點 + 與最近步行節點的接駁邊
    #    nearest_nodes 一次傳入所有座標（向量化）遠比逐一呼叫快。
    pids = list(stops.keys())
    nearest = ox.distance.nearest_nodes(
        G,
        X=[stops[p]["lng"] for p in pids],
        Y=[stops[p]["lat"] for p in pids],
    )
    for pid, wn in zip(pids, nearest):
        s = stops[pid]
        wn = int(wn)
        snode = ("S", pid)
        H.add_node(snode, x=s["lng"], y=s["lat"], kind="station", name=s["name"], pole_id=pid)
        wnode = G.nodes[wn]
        dist = float(ox.distance.great_circle(wnode["y"], wnode["x"], s["lat"], s["lng"]))
        H.add_edge(wn, snode, mode="access", length=dist)
        H.add_edge(snode, wn, mode="egress", length=dist)

    # 2b) 鄰近站點之間的轉乘步行邊（同一路口不同站位）
    keys = list(stops.keys())
    for ii in range(len(keys)):
        a = stops[keys[ii]]
        for jj in range(ii + 1, len(keys)):
            b = stops[keys[jj]]
            if abs(a["lat"] - b["lat"]) > 0.002 or abs(a["lng"] - b["lng"]) > 0.002:
                continue
            d = float(ox.distance.great_circle(a["lat"], a["lng"], b["lat"], b["lng"]))
            if d <= TRANSFER_WALK_M:
                sa, sb = ("S", keys[ii]), ("S", keys[jj])
                H.add_edge(sa, sb, mode="transfer", length=d)
                H.add_edge(sb, sa, mode="transfer", length=d)

    # 3) 路線站節點 + 乘車邊（線形沿實際道路）
    for rno, dirs in routes.items():
        for direction, info in dirs.items():
            seq = info["stops"]
            prev_rs = None
            prev_pid = None
            for i, pid in enumerate(seq):
                if pid not in stops:
                    prev_rs, prev_pid = None, None
                    continue
                rs = ("RS", rno, direction, i)
                H.add_node(
                    rs, x=stops[pid]["lng"], y=stops[pid]["lat"],
                    kind="route_stop", pole_id=pid, route=rno,
                )
                snode = ("S", pid)
                H.add_edge(snode, rs, mode="board", length=0.0, route=rno)
                H.add_edge(rs, snode, mode="alight", length=0.0, route=rno)

                if prev_rs is not None:
                    coords = bus_data.gap_coords(rno, direction, i - 1)
                    if coords and len(coords) >= 2:
                        length = _polyline_len(coords)
                    else:
                        a, b = stops[prev_pid], stops[pid]
                        length = float(
                            ox.distance.great_circle(a["lat"], a["lng"], b["lat"], b["lng"])
                        )
                        coords = [[a["lng"], a["lat"]], [b["lng"], b["lat"]]]
                    H.add_edge(
                        prev_rs, rs, mode="bus", length=length,
                        route=rno, direction=direction, coords=coords,
                    )
                prev_rs, prev_pid = rs, pid

    log.info(
        "多模態路網：%d 步行 / %d 站點 / %d 路線站，共 %d 節點、%d 邊",
        G.number_of_nodes(), len(stops),
        sum(len(v["stops"]) for dirs in routes.values() for v in dirs.values()),
        H.number_of_nodes(), H.number_of_edges(),
    )
    return H


def get_multimodal() -> nx.MultiDiGraph:
    global _H
    if _H is not None:
        return _H
    with _lock:
        if _H is None:
            _H = _build()
        return _H


def _edge_cost(data: dict, prefs: RoutePreferences, walk_speed: float) -> float | None:
    mode = data.get("mode")
    if mode in _WALK_MODES:
        if prefs.avoid_stairs and data.get("is_stairs"):
            return None
        try:
            length = float(data.get("length", 0.0))
        except (TypeError, ValueError):
            length = 0.0
        return (length / walk_speed) * slope_factor(data, prefs.max_slope_pct)
    if mode == "board":
        return WAIT_TIME_S + TRANSFER_PENALTY_S
    if mode == "alight":
        return 0.0
    if mode == "bus":
        return float(data.get("length", 0.0)) * BUS_DETOUR / BUS_SPEED_MPS
    return None


def build_cost_graph(
    H: nx.MultiDiGraph, prefs: RoutePreferences, walk_speed: float, now_s: int | None = None
) -> nx.DiGraph:
    D = nx.DiGraph()
    for u, v, _k, data in H.edges(keys=True, data=True):
        route = data.get("route")
        if route is not None and not _route_runs(route, now_s):
            continue  # 該路線在出發時間不營運
        c = _edge_cost(data, prefs, walk_speed)
        if c is None:
            continue
        existing = D.get_edge_data(u, v)
        if existing is None or c < existing["cost"]:
            D.add_edge(
                u, v, cost=c, mode=data.get("mode"), route=route,
                length=float(data.get("length", 0.0)), data=data,
            )
    return D


def _polyline_len(coords: list[list[float]]) -> float:
    total = 0.0
    for i in range(1, len(coords)):
        a, b = coords[i - 1], coords[i]
        total += float(ox.distance.great_circle(a[1], a[0], b[1], b[0]))
    return total


def _layered_search(
    D: nx.DiGraph, H: nx.MultiDiGraph, source: Any, target: Any, max_boards: int
) -> list | None:
    """A* 搜尋，狀態為 (節點, 已上車次數)。

    `board` 邊代表上車；限制總上車次數（= 轉乘次數 + 1），
    因此能硬性限制轉乘次數。轉乘成本已設為 0，避免搜尋無限換乘。
    """
    if source == target:
        return [source]

    tx, ty = float(H.nodes[target]["x"]), float(H.nodes[target]["y"])

    def hx(u: Any) -> float:
        ux, uy = float(H.nodes[u]["x"]), float(H.nodes[u]["y"])
        return ox.distance.great_circle(uy, ux, ty, tx) / BUS_SPEED_MPS

    best: dict[tuple[Any, int], float] = {(source, 0): 0.0}
    prev: dict[tuple[Any, int], tuple[Any, int]] = {}
    pq: list[tuple[float, float, Any, int]] = [(hx(source), 0.0, source, 0)]

    while pq:
        _f, g, u, b = heapq.heappop(pq)
        if g > best.get((u, b), float("inf")):
            continue
        if u == target:
            path = [u]
            state = (u, b)
            while state in prev:
                state = prev[state]
                path.append(state[0])
            path.reverse()
            return path
        for v, ed in D.adj[u].items():
            nb = b + 1 if ed.get("mode") == "board" else b
            if nb > max_boards:
                continue
            ng = g + ed["cost"]
            if ng < best.get((v, nb), float("inf")):
                best[(v, nb)] = ng
                prev[(v, nb)] = (u, b)
                heapq.heappush(pq, (ng + hx(v), ng, v, nb))
    return None


def _walk_legs(H, D, sub, walk_speed):
    from ..geo.geojson import path_to_linestring

    subpath = [sub[0][0]] + [e[1] for e in sub]
    dist = sum(e[2]["length"] for e in sub)
    return {
        "mode": "walk",
        "route": None,
        "from_name": None,
        "to_name": None,
        "num_stops": 0,
        "stops": [],
        "distance_m": round(dist, 1),
        "duration_s": round(dist / walk_speed, 1),
        "geometry": path_to_linestring(H, D, subpath),
    }


def _assemble(H, D, path, walk_speed, origin, destination):
    from ..geo.geojson import path_to_linestring

    edges = [(path[i - 1], path[i], D[path[i - 1]][path[i]]) for i in range(1, len(path))]
    legs: list[dict] = []
    combined: list[list[float]] = []
    i = 0

    while i < len(edges):
        mode = edges[i][2]["mode"]

        if mode in _WALK_MODES:
            j = i
            sub = []
            while j < len(edges) and edges[j][2]["mode"] in _WALK_MODES:
                sub.append(edges[j])
                j += 1
            leg = _walk_legs(H, D, sub, walk_speed)
            legs.append(leg)
            _extend(combined, leg["geometry"]["coordinates"])
            i = j
            continue

        if mode == "board":
            route = edges[i][2]["route"]
            board_station = edges[i][0]
            stop_ids = []
            bus_coords: list[list[float]] = []
            if isinstance(board_station, tuple) and board_station[0] == "S":
                stop_ids.append(board_station[1])
                bus_coords = [[H.nodes[board_station]["x"], H.nodes[board_station]["y"]]]

            k = i + 1
            ride_len = 0.0
            while k < len(edges) and edges[k][2]["mode"] == "bus":
                rs = edges[k][1]
                if isinstance(rs, tuple) and rs[0] == "RS":
                    pid = H.nodes[rs].get("pole_id")
                    if pid and (not stop_ids or stop_ids[-1] != pid):
                        stop_ids.append(pid)
                ride_len += edges[k][2]["length"]
                seg = (edges[k][2].get("data") or {}).get("coords")
                if seg:
                    _extend(bus_coords, seg)
                k += 1

            if k < len(edges) and edges[k][2]["mode"] == "alight":
                st = edges[k][0]
                if isinstance(st, tuple) and st[0] == "S":
                    if not stop_ids or stop_ids[-1] != st[1]:
                        stop_ids.append(st[1])
                    _extend(bus_coords, [[H.nodes[st]["x"], H.nodes[st]["y"]]])
                k += 1

            names = [H.nodes[("S", p)]["name"] if ("S", p) in H else p for p in stop_ids]
            stop_coords = [
                [H.nodes[("S", p)]["x"], H.nodes[("S", p)]["y"]]
                for p in stop_ids
                if ("S", p) in H
            ]
            dur = WAIT_TIME_S + TRANSFER_PENALTY_S + ride_len * BUS_DETOUR / BUS_SPEED_MPS
            legs.append({
                "mode": "bus",
                "route": route,
                "from_name": names[0] if names else None,
                "to_name": names[-1] if names else None,
                "num_stops": max(len(stop_ids) - 1, 0),
                "stops": names,
                "stop_coords": stop_coords,
                "distance_m": round(ride_len, 1),
                "duration_s": round(dur, 1),
                "geometry": {"type": "LineString", "coordinates": bus_coords},
            })
            _extend(combined, bus_coords)
            i = k
            continue

        # 其他（不應出現）
        i += 1

    total_dist = sum(l["distance_m"] for l in legs)
    total_dur = sum(l["duration_s"] for l in legs)
    bus_legs = sum(1 for l in legs if l["mode"] == "bus")
    if bus_legs == 0:
        mode = "walk"
    elif any(l["mode"] == "walk" for l in legs):
        mode = "mixed"
    else:
        mode = "bus"

    return {
        "mode": mode,
        "total_distance_m": round(total_dist, 1),
        "total_duration_s": round(total_dur, 1),
        "num_transfers": max(bus_legs - 1, 0),
        "legs": legs,
        "geometry": {"type": "LineString", "coordinates": combined},
    }


def _extend(dst: list, src: list) -> None:
    if dst and src and dst[-1] == src[0]:
        dst.extend(src[1:])
    else:
        dst.extend(src)


def plan(
    origin,
    destination,
    prefs: RoutePreferences,
    departure_time: str | None = None,
    max_transfers: int = 3,
) -> dict:
    from .loader import get_graph
    from ..optimize import pathfinding

    H = get_multimodal()
    G = get_graph()
    walk_speed = prefs.walking_speed_mps or settings.walking_speed_mps

    now_s = _parse_hhmm(departure_time) if departure_time else now_seconds()
    D = build_cost_graph(H, prefs, walk_speed, now_s)
    o = pathfinding.nearest_node(G, origin.lat, origin.lng)
    d = pathfinding.nearest_node(G, destination.lat, destination.lng)

    if o not in D or d not in D:
        raise nx.NetworkXNoPath("起點或終點不在可用路網內")

    # 最多轉乘次數 = 上車次數上限 - 1
    max_boards = max(int(max_transfers), 0) + 1
    path = _layered_search(D, H, o, d, max_boards)
    if path is None:
        raise nx.NetworkXNoPath("在轉乘次數限制內找不到路線")

    result = _assemble(H, D, path, walk_speed, origin, destination)
    result["departure_time"] = _fmt_hhmm(now_s)
    return result
