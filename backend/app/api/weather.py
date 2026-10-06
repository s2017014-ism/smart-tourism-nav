"""Phase 6：天氣 API（Open-Meteo）。"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from ..services import weather as weather_service

router = APIRouter(tags=["weather"])


@router.get("/weather", summary="目前天氣（Open-Meteo，免金鑰）")
def current_weather(lat: float | None = None, lon: float | None = None) -> dict:
    try:
        return weather_service.current(lat, lon)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"無法取得天氣：{exc}") from exc
