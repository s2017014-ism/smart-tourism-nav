"""景點 POI 資料存取。

讀取 `scripts/fetch_pois.py` 產生的 `data/poi_macau.geojson`。
第一次讀取後快取在記憶體（lru_cache）。
"""

from __future__ import annotations

import json
import logging
from functools import lru_cache

from ..config import settings

log = logging.getLogger(__name__)

POI_PATH = settings.data_dir.parent / "poi_macau.geojson"


@lru_cache(maxsize=1)
def _load() -> dict:
    if not POI_PATH.exists():
        log.warning("找不到 POI 檔：%s（請先執行 scripts/fetch_pois.py）", POI_PATH)
        return {"type": "FeatureCollection", "features": []}
    with open(POI_PATH, encoding="utf-8") as f:
        return json.load(f)


def all_features() -> list[dict]:
    return _load().get("features", [])


def query(category: str | None = None, limit: int | None = None) -> list[dict]:
    feats = all_features()
    if category:
        feats = [f for f in feats if f["properties"].get("category") == category]
    if limit is not None:
        feats = feats[:limit]
    return feats


def categories() -> list[str]:
    seen: list[str] = []
    for f in all_features():
        c = f["properties"].get("category")
        if c and c not in seen:
            seen.append(c)
    return seen
