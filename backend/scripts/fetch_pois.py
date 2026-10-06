"""抓取澳門景點 POI，輸出成 GeoJSON（Phase 2 行程排序的資料基礎）。

資料來源：OpenStreetMap（Overpass API）© OpenStreetMap contributors, ODbL。
輸出正規化後的點資料：每個 POI 一個 Point（面狀地物取其代表點）。

用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\fetch_pois.py
輸出：
    data/poi_macau.geojson
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

import osmnx as ox  # noqa: E402
from shapely.geometry import Point  # noqa: E402

from app.config import settings  # noqa: E402

# 想抓的 OSM 標籤（union：符合任一即納入）
TAGS: dict[str, object] = {
    "tourism": [
        "attraction", "museum", "viewpoint", "artwork", "gallery",
        "theme_park", "zoo", "aquarium",
    ],
    "historic": True,
    "natural": ["peak", "rock", "cave_entrance", "spring", "beach", "bay", "cape", "cliff"],
    "leisure": ["park", "garden", "nature_reserve"],
    "amenity": [
        "place_of_worship", "theatre", "arts_centre", "marketplace", "fountain",
        # 美食
        "restaurant", "cafe", "fast_food", "food_court", "bar", "pub", "ice_cream", "biergarten",
    ],
    "shop": [
        "bakery", "confectionery", "pastry", "seafood", "deli",
        "coffee", "tea", "chocolate", "ice_cream", "beverages",
    ],
    "man_made": ["lighthouse", "tower", "observatory"],
    "place": ["square"],
    "heritage": True,
}

# 餐飲類：amenity / shop 屬於這些值時，歸類為「美食」
FOOD_AMENITIES = {
    "restaurant", "cafe", "fast_food", "food_court",
    "bar", "pub", "ice_cream", "biergarten",
}
FOOD_SHOPS = {
    "bakery", "confectionery", "pastry", "seafood", "deli",
    "coffee", "tea", "chocolate", "ice_cream", "beverages",
}

# OSM 沒用 POI 標籤標註、但實際上必訪的地標，用人工清單補齊。
# 會以名稱去重：若 OSM 已抓到同名者則略過。
CURATED: list[dict] = [
    {"name": "議事亭前地", "name_en": "Senado Square", "lat": 22.19356, "lng": 113.53963, "type": "square"},
    {"name": "官也街", "name_en": "Rua do Cunha", "lat": 22.15328, "lng": 113.55643, "type": "street"},
    {"name": "東望洋燈塔", "name_en": "Guia Lighthouse", "lat": 22.19924, "lng": 113.54946, "type": "lighthouse"},
    {"name": "大三巴牌坊", "name_en": "Ruins of St. Paul's", "lat": 22.19745, "lng": 113.54077, "type": "ruins"},
    {"name": "媽閣廟", "name_en": "A-Ma Temple", "lat": 22.18615, "lng": 113.53098, "type": "temple"},
    {"name": "澳門旅遊塔", "name_en": "Macau Tower", "lat": 22.17960, "lng": 113.53644, "type": "tower"},
    {"name": "大炮台", "name_en": "Fortaleza do Monte", "lat": 22.19780, "lng": 113.54160, "type": "fort"},
    {"name": "玫瑰聖母堂", "name_en": "St. Dominic's Church", "lat": 22.19390, "lng": 113.53990, "type": "church"},
    {"name": "白鴿巢公園", "name_en": "Camões Garden", "lat": 22.19960, "lng": 113.54100, "type": "park"},
    {"name": "塔石廣場", "name_en": "Tap Seac Square", "lat": 22.19900, "lng": 113.54400, "type": "square"},
    {"name": "澳門漁人碼頭", "name_en": "Macau Fisherman's Wharf", "lat": 22.19320, "lng": 113.55500, "type": "attraction"},
    {"name": "黑沙海灘", "name_en": "Hac Sa Beach", "lat": 22.11700, "lng": 113.56600, "type": "beach"},
    {"name": "龍環葡韻", "name_en": "Taipa Houses-Museum", "lat": 22.15440, "lng": 113.55600, "type": "museum"},
    {"name": "聖方濟各聖堂", "name_en": "St. Francis Xavier Church", "lat": 22.11330, "lng": 113.55330, "type": "church"},
    {"name": "觀音蓮花苑", "name_en": "Kun Iam Statue", "lat": 22.18820, "lng": 113.55220, "type": "attraction"},
]

# 這些 historic 值多半是零散的小物件，過濾掉以維持 POI 品質
HISTORIC_BLOCKLIST = {"yes", "no", "memorial:stone"}

CATEGORY_LABELS = {
    "tourism": "觀光",
    "historic": "歷史",
    "natural": "自然",
    "leisure": "休閒",
    "amenity": "設施",
    "man_made": "地標",
    "place": "廣場",
    "heritage": "文化遺產",
    "curated": "必訪",
    "food": "美食",
}


_NA_STRINGS = {"nan", "none", "<na>", "nat", ""}


def _scalar(value):
    """OSM 屬性可能是 list；回傳第一個非空值的純量。"""
    if isinstance(value, (list, tuple, set)):
        for v in value:
            s = _scalar(v)
            if s is not None:
                return s
        return None
    return value


def _str(value) -> str | None:
    v = _scalar(value)
    if v is None:
        return None
    s = str(v).strip()
    # NaN / pandas NA / NaT 都會變成這些字串，一律視為缺值
    if s.lower() in _NA_STRINGS:
        return None
    return s


def _macau_boundary():
    """取得澳門特別行政區的行政邊界多邊形，用來排除範圍外的景點。

    bbox 是矩形，北邊會延伸到珠海（關閘以北）、西邊跨過內港，
    因此必須用真正的行政區邊界做點在多邊形內的過濾。
    """
    try:
        gdf = ox.geocode_to_gdf("Macau")
        if len(gdf) == 0:
            return None
        geom = (
            gdf.geometry.union_all()
            if hasattr(gdf.geometry, "union_all")
            else gdf.geometry.unary_union
        )
        return geom
    except Exception as exc:  # noqa: BLE001
        print(f"警告：無法取得澳門邊界（{exc}），本次不做範圍過濾")
        return None


def _pick_category(row: dict) -> tuple[str, str]:
    """回傳 (category_key, category_value)，依優先序 美食 > tourism > historic > ..."""
    # 美食優先：餐飲類的 amenity / shop
    am = _str(row.get("amenity"))
    if am in FOOD_AMENITIES:
        return "food", am
    sh = _str(row.get("shop"))
    if sh in FOOD_SHOPS:
        return "food", f"shop={sh}"

    for key in ("tourism", "historic", "natural", "leisure", "amenity", "man_made", "place", "heritage"):
        val = _str(row.get(key))
        if val:
            return key, val
    return "other", "other"


def main() -> None:
    print(f"向 Overpass 查詢澳門 POI，bbox={settings.bbox} ...")
    gdf = ox.features_from_bbox(settings.bbox, TAGS)
    print(f"原始抓取：{len(gdf)} 筆地物")

    features: list[dict] = []
    seen: set[tuple[str, str]] = set()
    skipped_no_name = 0
    skipped_dup = 0

    for (osm_type, osm_id), row in gdf.iterrows():
        rowd = row.to_dict()

        name = _str(rowd.get("name")) or _str(rowd.get("name:zh")) or _str(rowd.get("name:en"))
        if not name:
            skipped_no_name += 1
            continue

        cat_key, cat_val = _pick_category(rowd)
        if cat_key == "historic" and cat_val in HISTORIC_BLOCKLIST:
            skipped_no_name += 1
            continue

        # 去重：同名同類只留一筆
        dedup_key = (name, cat_key)
        if dedup_key in seen:
            skipped_dup += 1
            continue
        seen.add(dedup_key)

        geom = row.geometry
        pt = geom if geom.geom_type == "Point" else geom.representative_point()

        features.append({
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [round(pt.x, 6), round(pt.y, 6)],
            },
            "properties": {
                "osm_id": f"{osm_type}/{osm_id}",
                "name": name,
                "name_zh": _str(rowd.get("name:zh")) or _str(rowd.get("name")),
                "name_en": _str(rowd.get("name:en")),
                "name_pt": _str(rowd.get("name:pt")),
                "category": cat_key,
                "category_value": cat_val,
                "category_label": CATEGORY_LABELS.get(cat_key, "其他"),
                "opening_hours": _str(rowd.get("opening_hours")),
                "cuisine": _str(rowd.get("cuisine")),
                "wikidata": _str(rowd.get("wikidata")),
                "website": _str(rowd.get("website")) or _str(rowd.get("contact:website")),
                "ele": _str(rowd.get("ele")),
                "lat": round(pt.y, 6),
                "lng": round(pt.x, 6),
                "source": "osm",
            },
        })

    # 併入人工必訪清單（OSM 沒標成 POI 的地標）
    existing = {f["properties"]["name"] for f in features}
    existing |= {f["properties"]["name_zh"] for f in features if f["properties"].get("name_zh")}
    curated_added = 0
    for c in CURATED:
        if c["name"] in existing:
            continue
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [c["lng"], c["lat"]]},
            "properties": {
                "osm_id": None,
                "name": c["name"],
                "name_zh": c["name"],
                "name_en": c.get("name_en"),
                "name_pt": None,
                "category": "curated",
                "category_value": c.get("type", "attraction"),
                "category_label": CATEGORY_LABELS["curated"],
                "opening_hours": None,
                "wikidata": None,
                "website": None,
                "ele": None,
                "lat": c["lat"],
                "lng": c["lng"],
                "source": "curated",
            },
        })
        existing.add(c["name"])
        curated_added += 1

    # 只保留在澳門行政區範圍內的景點（排除珠海／內地）
    boundary = _macau_boundary()
    removed_outside = 0
    if boundary is not None:
        kept = []
        for f in features:
            lon, lat = f["geometry"]["coordinates"]
            if boundary.covers(Point(lon, lat)):
                kept.append(f)
            else:
                removed_outside += 1
        features = kept
        print(f"排除澳門範圍外：{removed_outside} 筆")

    fc = {"type": "FeatureCollection", "features": features}

    out = settings.data_dir.parent / "poi_macau.geojson"
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False, indent=2)

    print(f"過濾（無名稱/雜項）：{skipped_no_name} 筆；去重：{skipped_dup} 筆")
    print(f"輸出 {len(features)} 個景點 → {out}")

    # 各類別統計
    from collections import Counter
    print("\n類別分布：")
    for k, v in Counter(f["properties"]["category"] for f in features).most_common():
        print(f"  {CATEGORY_LABELS.get(k, k):8s} {v:4d}")

    print("\n範例（前 15 筆）：")
    for f in features[:15]:
        p = f["properties"]
        print(f"  [{p['category_label']}] {p['name']}  ({p['lat']}, {p['lng']})")


if __name__ == "__main__":
    main()
