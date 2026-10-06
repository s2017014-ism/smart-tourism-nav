"""路徑尋優引擎（點對點最短路徑）。

核心概念：
  1. 先依使用者偏好，把原始 MultiDiGraph 轉成一張「帶 cost 的 DiGraph」。
     cost 的單位是「秒」，而階梯／超陡坡會被直接略過（不是給大權重，是移除）。
  2. 在 cost 圖上用 A* 找最短路，heuristic 用大圓距離 / 步行速度，
     保證 admissible（不會高估），所以結果仍是最優解。

Phase 3 會把這裡擴充成走 + 公車的多模態圖；Phase 4 會把 DEM 坡度納入 cost。
"""

from __future__ import annotations

import math
from typing import Any

import networkx as nx
import osmnx as ox

from ..config import settings
from ..schemas import LatLng, RoutePreferences, RouteStep
from .costs import rain_factor
from .slope import slope_factor

INF = math.inf


def nearest_node(G: nx.MultiDiGraph, lat: float, lng: float) -> int:
    """找出最接近的圖節點。注意 OSMnx 的參數是 (X=經度, Y=緯度)。"""
    return int(ox.distance.nearest_nodes(G, X=lng, Y=lat))


def _edge_cost(data: dict, prefs: RoutePreferences, speed: float) -> float:
    if prefs.avoid_stairs and data.get("is_stairs"):
        return INF

    try:
        length = float(data.get("length", 0.0))
    except (TypeError, ValueError):
        length = 0.0

    # Phase 4：坡度（DEM）。以懲罰引導走平緩路，但不封鎖（保證可達）。
    # Phase 6：雨天模式提高步行成本。
    return (length / speed) * slope_factor(data, prefs.max_slope_pct) * rain_factor(prefs)


def build_cost_graph(G: nx.MultiDiGraph, prefs: RoutePreferences) -> nx.DiGraph:
    """依偏好產生本請求專用的 cost 圖（執行緒安全，不修改原始圖）。"""
    speed = prefs.walking_speed_mps or settings.walking_speed_mps
    D = nx.DiGraph()

    for u, v, _k, data in G.edges(keys=True, data=True):
        c = _edge_cost(data, prefs, speed)
        if c == INF:
            continue  # 封鎖：直接不加入邊
        existing = D.get_edge_data(u, v)
        if existing is None or c < existing["cost"]:
            D.add_edge(u, v, cost=c, data=data)

    return D


def _heuristic(G: nx.MultiDiGraph, target: int, speed: float):
    tx, ty = float(G.nodes[target]["x"]), float(G.nodes[target]["y"])

    def h(u: int, _v: int) -> float:
        ux, uy = float(G.nodes[u]["x"]), float(G.nodes[u]["y"])
        return ox.distance.great_circle(uy, ux, ty, tx) / speed

    return h


def _flatten_name(value: Any) -> str:
    if isinstance(value, (list, tuple)) and value:
        return str(value[0])
    if value:
        return str(value)
    return "步道"


def _build_steps(G: nx.MultiDiGraph, D: nx.DiGraph, path: list, speed: float) -> list[RouteStep]:
    """把連續同名的邊合併成一步，產生簡易的逐段指示。"""
    steps: list[RouteStep] = []
    cur_name: str | None = None
    cur_dist = 0.0
    cur_dur = 0.0

    def flush():
        if cur_name is not None and cur_dist > 0:
            steps.append(
                RouteStep(
                    instruction=f"沿 {cur_name} 前行",
                    distance_m=round(cur_dist, 1),
                    duration_s=round(cur_dur, 1),
                )
            )

    for i in range(1, len(path)):
        u, v = path[i - 1], path[i]
        data = D[u][v]["data"]
        name = _flatten_name(data.get("name") or data.get("highway"))
        try:
            length = float(data.get("length", 0.0))
        except (TypeError, ValueError):
            length = 0.0

        if cur_name is None:
            cur_name = name
        if name != cur_name:
            flush()
            cur_name, cur_dist, cur_dur = name, 0.0, 0.0

        cur_dist += length
        cur_dur += length / speed

    flush()
    return steps


def plan(
    G: nx.MultiDiGraph,
    origin: LatLng,
    destination: LatLng,
    prefs: RoutePreferences,
) -> dict:
    """回傳可直接轉成 RouteResponse 的 dict。"""
    o_node = nearest_node(G, origin.lat, origin.lng)
    d_node = nearest_node(G, destination.lat, destination.lng)

    speed = prefs.walking_speed_mps or settings.walking_speed_mps
    D = build_cost_graph(G, prefs)

    if o_node not in D or d_node not in D:
        raise nx.NetworkXNoPath("起點或終點在可用路網之外（可能被偏好條件完全封鎖）")

    path = nx.astar_path(D, o_node, d_node, heuristic=_heuristic(G, d_node, speed), weight="cost")
    return _assemble(G, D, path, speed)


def path_between(
    G: nx.MultiDiGraph, D: nx.DiGraph, source: int, target: int, speed: float
) -> dict:
    """計算兩個圖節點之間的最短路徑並組裝結果（供 Phase 2 串接各段使用）。"""
    path = nx.astar_path(D, source, target, heuristic=_heuristic(G, target, speed), weight="cost")
    return _assemble(G, D, path, speed)


def _assemble(G: nx.MultiDiGraph, D: nx.DiGraph, path: list, speed: float) -> dict:
    total_dist = 0.0
    for i in range(1, len(path)):
        data = D[path[i - 1]][path[i]]["data"]
        try:
            total_dist += float(data.get("length", 0.0))
        except (TypeError, ValueError):
            pass

    # 避免循環 import
    from ..geo.geojson import path_to_linestring

    start = G.nodes[path[0]]
    end = G.nodes[path[-1]]

    return {
        "distance_m": round(total_dist, 1),
        "duration_s": round(total_dist / speed, 1),
        "geometry": path_to_linestring(G, D, path),
        "nodes": len(path),
        "origin_snapped": {"lat": float(start["y"]), "lng": float(start["x"])},
        "destination_snapped": {"lat": float(end["y"]), "lng": float(end["x"])},
        "steps": _build_steps(G, D, path, speed),
    }
