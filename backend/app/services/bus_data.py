"""巴士站點、路線與路段線形資料存取（Phase 3）。

讀取 `scripts/build_bus_data.py` 產生的：
  data/bus_stops.geojson     站點
  data/bus_routes.json       路線站序 + 每段區間的路段 id
  data/bus_segments.json     路段線形（NETWORK_ID -> 座標）
"""

from __future__ import annotations

import json
import logging
from functools import lru_cache

from ..config import settings

log = logging.getLogger(__name__)

DATA_DIR = settings.data_dir.parent  # backend/data


def _load_json(name: str, default):
    path = DATA_DIR / name
    if not path.exists():
        log.warning("找不到 %s（請先執行 scripts/build_bus_data.py）", path)
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


@lru_cache(maxsize=1)
def stops() -> dict[str, dict]:
    """{ pole_id: {name, sta_code, lat, lng, routes} }。"""
    fc = _load_json("bus_stops.geojson", {"features": []})
    out: dict[str, dict] = {}
    for feat in fc.get("features", []):
        p = feat["properties"]
        lon, lat = feat["geometry"]["coordinates"]
        out[str(p["pole_id"])] = {
            "name": p.get("name") or p.get("sta_code") or p["pole_id"],
            "sta_code": p.get("sta_code"),
            "lat": float(lat),
            "lng": float(lon),
            "routes": p.get("routes"),
        }
    return out


@lru_cache(maxsize=1)
def routes() -> dict[str, dict[str, dict]]:
    """{ route_no: { direction: {stops: [...], seg_ids: [[...]]} } }。"""
    return _load_json("bus_routes.json", {})


@lru_cache(maxsize=1)
def segments() -> dict[str, list[list[float]]]:
    """{ network_id: [[lng, lat], ...] }。"""
    return _load_json("bus_segments.json", {})


def stop_lnglat(pole_id: str) -> list[float] | None:
    s = stops().get(str(pole_id))
    return [s["lng"], s["lat"]] if s else None


def _d2(a: list[float], b: list[float]) -> float:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def gap_coords(route_no: str, direction: str, i: int) -> list[list[float]]:
    """第 i 站到第 i+1 站之間、沿實際道路的線形（已合併並定向）。"""
    info = routes().get(str(route_no), {}).get(str(direction))
    if not info:
        return []
    gaps = info["seg_ids"]
    if i < 0 or i >= len(gaps):
        return []

    segs = segments()
    pole_ids = info["stops"]
    merged: list[list[float]] = []
    prev = stop_lnglat(pole_ids[i]) if i < len(pole_ids) else None

    for sid in gaps[i]:
        seg = segs.get(str(sid))
        if not seg or len(seg) < 2:
            continue
        if prev is not None and _d2(seg[-1], prev) < _d2(seg[0], prev):
            seg = list(reversed(seg))
        if merged and merged[-1] == seg[0]:
            merged.extend(seg[1:])
        else:
            merged.extend(seg)
        prev = merged[-1]

    if not merged and i + 1 < len(pole_ids):
        a, b = stop_lnglat(pole_ids[i]), stop_lnglat(pole_ids[i + 1])
        if a and b:
            merged = [a, b]
    return merged
