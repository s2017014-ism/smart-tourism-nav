"""Phase 6：景點人潮推估。

官方沒有即時人潮資料，因此採用「時空歷史查表模型」：
    key = (poi_id, weekday, hour, season)  ->  預測擁擠度 0~1
可用 OSM 的 popularity / 網路搜尋量等弱訊號當代理，於報告中誠實標明為推估值。
"""

from __future__ import annotations


def crowd_level(*_args, **_kwargs) -> float:
    raise NotImplementedError("Phase 6：人潮模型尚未實作")
