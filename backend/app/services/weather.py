"""Phase 6：即時天氣。

資料來源：澳門地球物理暨氣象局（SMG）或 OpenWeatherMap。
用途：下雨時調高戶外步行路段的 cost，觸發即時重排。
"""

from __future__ import annotations


def get_weather(*_args, **_kwargs) -> dict:
    raise NotImplementedError("Phase 6：天氣服務尚未實作")
