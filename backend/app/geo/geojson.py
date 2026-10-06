"""GeoJSON 與座標輔助函式。"""

from __future__ import annotations

from typing import Any

import networkx as nx

try:  # shapely 為 OSMnx 依賴，一定存在
    from shapely import wkt as _wkt
except Exception:  # pragma: no cover
    _wkt = None


def node_lnglat(G: nx.MultiDiGraph, node: Any) -> tuple[float, float]:
    """回傳節點的 (經度, 緯度)。"""
    d = G.nodes[node]
    return float(d["x"]), float(d["y"])


def _as_geometry(g: Any) -> Any:
    """兼容 OSMnx 從 GraphML 讀回時 geometry 可能是 WKT 字串的情況。"""
    if g is None:
        return None
    if isinstance(g, str):
        if _wkt is None:
            return None
        try:
            return _wkt.loads(g)
        except Exception:
            return None
    return g


def _edge_coords(data: dict | None) -> list[tuple[float, float]]:
    """取出一條邊的折線座標；沒有 geometry 時回傳空串列，由呼叫端補節點座標。"""
    if not data:
        return []
    geom = _as_geometry(data.get("geometry"))
    if geom is None or not hasattr(geom, "coords"):
        return []
    return [(float(x), float(y)) for x, y in geom.coords]


def path_to_linestring(G: nx.MultiDiGraph, D: nx.DiGraph, path: list) -> dict:
    """把節點序列轉成盡量貼合真實道路的 GeoJSON LineString。"""
    coords: list[tuple[float, float]] = []

    for i, u in enumerate(path):
        if i == 0:
            coords.append(node_lnglat(G, u))
            continue

        v = path[i - 1]
        edge = D.get_edge_data(v, u) or {}
        seg = _edge_coords(edge.get("data"))

        if len(seg) >= 2:
            # 確認方向為 v -> u
            vx, vy = node_lnglat(G, v)
            fx, fy = seg[0]
            if abs(fx - vx) > 1e-9 or abs(fy - vy) > 1e-9:
                seg = list(reversed(seg))
            coords.extend(seg[1:])
        else:
            coords.append(node_lnglat(G, u))

    return {
        "type": "LineString",
        "coordinates": [[x, y] for x, y in coords],
    }


def point_feature(lng: float, lat: float, properties: dict | None = None) -> dict:
    return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lng, lat]},
        "properties": properties or {},
    }
