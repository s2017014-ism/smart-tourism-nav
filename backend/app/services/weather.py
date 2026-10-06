"""Phase 6：即時天氣（Open-Meteo，免 API 金鑰）。

Open-Meteo：https://open-meteo.com/（非商業用途免費、無需註冊）。
用於「即時重排」：下雨時提高戶外步行路段的成本。
"""

from __future__ import annotations

import logging
import time

import httpx

from ..config import settings

log = logging.getLogger(__name__)

_URL = "https://api.open-meteo.com/v1/forecast"

# WMO weather code → 中文描述
_CODES: dict[int, str] = {
    0: "晴朗", 1: "大致晴朗", 2: "多雲", 3: "陰",
    45: "有霧", 48: "霧凇",
    51: "毛毛雨", 53: "毛毛雨", 55: "毛毛雨",
    56: "凍毛毛雨", 57: "凍毛毛雨",
    61: "小雨", 63: "中雨", 65: "大雨",
    66: "凍雨", 67: "凍雨",
    71: "小雪", 73: "中雪", 75: "大雪", 77: "雪粒",
    80: "陣雨", 81: "陣雨", 82: "強陣雨",
    85: "陣雪", 86: "強陣雪",
    95: "雷雨", 96: "雷雨伴冰雹", 99: "強雷雨伴冰雹",
}
_RAINY_CODES = {51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99}

_cache: dict = {"t": 0.0, "data": None}
_TTL_S = 600  # 快取 10 分鐘


def current(lat: float | None = None, lon: float | None = None) -> dict:
    now = time.time()
    if _cache["data"] is not None and now - _cache["t"] < _TTL_S:
        return _cache["data"]

    params = {
        "latitude": settings.weather_lat if lat is None else lat,
        "longitude": settings.weather_lon if lon is None else lon,
        "current": "temperature_2m,apparent_temperature,precipitation,rain,weather_code,wind_speed_10m,uv_index",
        "timezone": "Asia/Macau",
    }
    resp = httpx.get(_URL, params=params, timeout=15)
    resp.raise_for_status()
    cur = resp.json().get("current", {})

    code = int(cur.get("weather_code") or 0)
    precip = float(cur.get("precipitation") or 0.0)
    rain = float(cur.get("rain") or 0.0)

    data = {
        "temperature_c": cur.get("temperature_2m"),
        "apparent_c": cur.get("apparent_temperature"),
        "precipitation_mm": precip,
        "rain_mm": rain,
        "weather_code": code,
        "description": _CODES.get(code, "未知"),
        "wind_speed_kmh": cur.get("wind_speed_10m"),
        "uv_index": cur.get("uv_index"),
        "is_raining": precip > 0.1 or code in _RAINY_CODES,
        "source": "open-meteo",
    }
    _cache["t"] = now
    _cache["data"] = data
    return data
