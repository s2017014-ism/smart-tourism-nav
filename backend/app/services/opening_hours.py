"""OSM `opening_hours` 的輕量解析。

完整語法非常複雜（例：`Mo-Fr 09:00-12:00,13:00-17:00; PH off`），
本專案只處理最常見的簡單情況，其餘一律視為「全天開放」，
避免因解析錯誤而誤刪景點。

回傳 (open_sec, close_sec)，皆為「當日 0 點起算的秒數」；
無法解析或代表全天開放時回傳 None（呼叫端視為不受時間窗限制）。
"""

from __future__ import annotations

import re

_RANGE = re.compile(r"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})")
_ALWAYS = {"24/7", "24h", "open", "00:00-24:00", "00:00-00:00"}


def parse_opening_hours(value: str | None) -> tuple[int, int] | None:
    if not value:
        return None

    s = value.strip().lower()
    if s in _ALWAYS:
        return (0, 86400)

    m = _RANGE.search(s)
    if not m:
        return None

    oh, om, ch, cm = (int(x) for x in m.groups())
    if not (0 <= oh <= 24 and 0 <= ch <= 24 and om < 60 and cm < 60):
        return None

    open_s = oh * 3600 + om * 60
    close_s = ch * 3600 + cm * 60
    if close_s == 0:          # 例如 22:00-00:00 → 視為到午夜
        close_s = 86400
    if close_s <= open_s:     # 跨午夜或異常，交給呼叫端視為全天
        return None
    return (open_s, close_s)
