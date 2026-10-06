"""Phase 4：坡度（DEM）成本計算，供步行與多模態引擎共用。

考量：
  * SRTM 30m 在短邊上坡度雜訊大。
  * 若直接「封鎖」陡邊，山頂／死巷節點可能整條路都被切斷而無法到達。

因此坡度一律採「懲罰」而非封鎖：
  * 一般：cost *= (1 + SLOPE_WEIGHT * grade)  → 偏好平緩
  * 長邊且超過使用者門檻：再乘 STEEP_FACTOR → 強力避開，但仍可通行（保證可達）
"""

from __future__ import annotations

MIN_SLOPE_EDGE_M = 25.0   # 短於此長度的邊不套用「強力避開」門檻（DEM 雜訊保護）
SLOPE_WEIGHT = 4.0        # 軟性坡度懲罰
STEEP_FACTOR = 50.0       # 超過門檻的長陡邊額外倍率
GRADE_CAP = 0.35          # 坡度上限（截斷 DEM 雜訊造成的假陡坡）


def _grade(data: dict) -> float | None:
    g = data.get("grade_abs")
    if g is None:
        return None
    try:
        return float(g)
    except (TypeError, ValueError):
        return None


def _length(data: dict) -> float:
    try:
        return float(data.get("length", 0.0) or 0.0)
    except (TypeError, ValueError):
        return 0.0


def slope_factor(data: dict, max_slope_pct: float | None) -> float:
    """坡度成本倍率；未設定 max_slope_pct 時回傳 1.0（不考慮坡度）。"""
    if max_slope_pct is None:
        return 1.0
    grade = _grade(data)
    if grade is None:
        return 1.0
    grade = min(grade, GRADE_CAP)   # 截斷雜訊

    factor = 1.0 + SLOPE_WEIGHT * grade
    if _length(data) >= MIN_SLOPE_EDGE_M and grade * 100.0 > max_slope_pct:
        factor *= STEEP_FACTOR
    return factor
