"""把官方 DSAT 巴士資料整理成專案用的格式（Phase 3）。

來源（backend/data/raw/bus/，由 data.gov.mo「巴士路線資料」下載）：
  BUS_POLE.shp        巴士站點（座標為澳門格網 Macau Grid）
  BUS_ROUTE_SEQ.xls   路線站序：交錯排列「站（POLE_ID）」與「路段（NETWORK_ID）」
  ROUTE_NETWORK.shp   路線路段線形（NETWORK_ID -> LineString）

輸出（backend/data/）：
  bus_stops.geojson    站點（WGS84）
  bus_routes.json      { "1": { "A": { "stops": [...], "seg_ids": [[nid,...], ...] } } }
                       seg_ids[i] = 第 i 站到第 i+1 站之間經過的路段 id
  bus_segments.json    { "11658": [[lng,lat], ...] }  路段線形（WGS84）

用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\build_bus_data.py
"""

from __future__ import annotations

import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import geopandas as gpd  # noqa: E402
import pandas as pd  # noqa: E402

from app.config import settings  # noqa: E402

BUS_DIR = settings.data_dir / "bus"
OUT_DIR = settings.data_dir.parent  # backend/data

# Macau Grid -> WGS84 的基準（datum）偏移校正。
# DSAT 的 shapefile 使用澳門格網（International 1924 基準），轉到 WGS84 時
# 少了基準轉換，會產生約 300m 的系統性偏移。此平移量以 128 組
# 「同名巴士站（OSM ref 對應 DSAT 站碼）」配對求得，殘差 rms 約 8.5m。
#   dlon = +0.00297845（東向 +306m）、dlat = -0.00119120（北向 -132m）
DATUM_DLON = 0.00297845
DATUM_DLAT = -0.00119120


def _clean(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    s = str(v).strip()
    return s or None


def _key(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    try:
        return str(int(float(v)))
    except (TypeError, ValueError):
        return _clean(v)


def main() -> None:
    # ---- 站點（Macau Grid -> WGS84，含基準偏移校正）----
    pole = gpd.read_file(BUS_DIR / "BUS_POLE.shp", encoding="utf-8").to_crs(4326)
    pole.geometry = pole.geometry.translate(DATUM_DLON, DATUM_DLAT)
    stops: list[dict] = []
    stop_index: dict[str, dict] = {}
    for _, r in pole.iterrows():
        pid = _key(r.get("POLE_ID"))
        if pid is None:
            continue
        s = {
            "pole_id": pid,
            "sta_code": _clean(r.get("ALIAS")),
            "name": _clean(r.get("NAME")) or _clean(r.get("P_NAME")),
            "name_en": _clean(r.get("NAME_EN")),
            "name_por": _clean(r.get("NAME_POR")),
            "routes": _clean(r.get("ROUTE_NOS")),
            "lat": round(float(r.geometry.y), 6),
            "lng": round(float(r.geometry.x), 6),
        }
        stops.append(s)
        stop_index[pid] = s

    # ---- 路段線形（Macau Grid -> WGS84，含基準偏移校正）----
    net = gpd.read_file(BUS_DIR / "ROUTE_NETWORK.shp", encoding="utf-8").to_crs(4326)
    net.geometry = net.geometry.translate(DATUM_DLON, DATUM_DLAT)
    segments: dict[str, list[list[float]]] = {}
    for _, r in net.iterrows():
        nid = _key(r.get("NETWORK_ID"))
        if nid is None:
            continue
        segments[nid] = [[round(float(x), 6), round(float(y), 6)] for x, y in r.geometry.coords]

    # ---- 路線站序 + 區間路段 ----
    seq = pd.read_excel(BUS_DIR / "BUS_ROUTE_SEQ.xls")
    routes: dict[str, dict[str, dict]] = {}
    missing_pole: set[str] = set()
    missing_seg: set[str] = set()

    for (route_no, direction), g in seq.groupby(["ROUTE_NO", "DIRECTION"]):
        g = g.sort_values("SEQ")
        stops_seq: list[str] = []
        gap_segs: list[list[str]] = []
        cur: list[str] | None = None

        for _, row in g.iterrows():
            pid = _key(row.get("POLE_ID"))
            nid = _key(row.get("NETWORK_ID"))
            if pid is not None:
                if pid not in stop_index:
                    missing_pole.add(pid)
                    continue
                stops_seq.append(pid)
                if len(stops_seq) > 1:
                    gap_segs.append(cur or [])
                cur = []
            elif nid is not None:
                if nid in segments:
                    if cur is not None:
                        cur.append(nid)
                else:
                    missing_seg.add(nid)

        if len(stops_seq) >= 2:
            routes.setdefault(str(route_no), {})[str(direction)] = {
                "stops": stops_seq,
                "seg_ids": gap_segs,
            }

    # ---- 輸出 ----
    features = [
        {
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [s["lng"], s["lat"]]},
            "properties": {k: v for k, v in s.items() if k not in ("lat", "lng")}
            | {"lat": s["lat"], "lng": s["lng"]},
        }
        for s in stops
    ]
    with open(OUT_DIR / "bus_stops.geojson", "w", encoding="utf-8") as f:
        json.dump({"type": "FeatureCollection", "features": features}, f, ensure_ascii=False)
    with open(OUT_DIR / "bus_routes.json", "w", encoding="utf-8") as f:
        json.dump(routes, f, ensure_ascii=False)
    with open(OUT_DIR / "bus_segments.json", "w", encoding="utf-8") as f:
        json.dump(segments, f, ensure_ascii=False)

    n_gap = sum(len(v["seg_ids"]) for d in routes.values() for v in d.values())
    n_gap_with = sum(1 for d in routes.values() for v in d.values() for g in v["seg_ids"] if g)
    print(f"站點：{len(stops)}　路線：{len(routes)}　方向組合：{sum(len(d) for d in routes.values())}")
    print(f"區間：{n_gap}（有路段線形 {n_gap_with}，{n_gap_with / max(n_gap, 1) * 100:.1f}%）")
    print(f"路段數：{len(segments)}　找不到的站碼：{len(missing_pole)}　找不到的路段：{len(missing_seg)}")
    print("輸出：bus_stops.geojson / bus_routes.json / bus_segments.json")


if __name__ == "__main__":
    main()
