"""景點 POI API。"""

from __future__ import annotations

from fastapi import APIRouter, Query

from ..services import poi as poi_service

router = APIRouter(tags=["poi"])


@router.get("/pois", summary="取得景點 POI（GeoJSON FeatureCollection）")
def list_pois(
    category: str | None = Query(None, description="依類別過濾，如 tourism / historic / natural"),
    limit: int = Query(1000, ge=1, le=5000, description="回傳上限"),
) -> dict:
    feats = poi_service.query(category=category, limit=limit)
    return {"type": "FeatureCollection", "count": len(feats), "features": feats}


@router.get("/pois/categories", summary="取得所有 POI 類別")
def poi_categories() -> dict:
    return {"categories": poi_service.categories()}
