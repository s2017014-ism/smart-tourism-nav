"""Phase 6：天氣（雨天）成本係數，供步行與多模態引擎共用。

雨天時提高步行路段的成本，使路徑偏好「少走路」（例如多搭公車）。
"""

from __future__ import annotations

from ..schemas import RoutePreferences

RAIN_WALK_FACTOR = 2.0


def rain_factor(prefs: RoutePreferences) -> float:
    """雨天模式時回傳放大倍率，否則 1.0。"""
    return RAIN_WALK_FACTOR if getattr(prefs, "avoid_rain", False) else 1.0
