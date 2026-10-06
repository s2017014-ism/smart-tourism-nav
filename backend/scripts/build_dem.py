"""從 SRTM HGT 產生平滑後的 DEM，降低 30m 網格在短邊上的坡度雜訊。

輸出：data/raw/dem/macau_dem_smooth.tif
用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\build_dem.py
"""

from __future__ import annotations

import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np  # noqa: E402
import rasterio  # noqa: E402
from scipy.ndimage import uniform_filter  # noqa: E402

from app.config import settings  # noqa: E402

SRC = settings.data_dir / "dem" / "N22E113.hgt"
DST = settings.data_dir / "dem" / "macau_dem_smooth.tif"
SIZE = 5  # 5x5 像素 ≈ 150m 移動平均


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"找不到來源 DEM：{SRC}")

    with rasterio.open(SRC) as src:
        arr = src.read(1).astype("float32")
        profile = src.profile.copy()

    void = arr < -1000            # SRTM 無效值
    land = np.where(void, 0.0, arr)
    smoothed = uniform_filter(land, size=SIZE, mode="nearest")
    smoothed = np.where(void, arr, smoothed)   # 無效值維持原樣

    profile.update(driver="GTiff", dtype="float32", count=1, compress="lzw")
    DST.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(DST, "w", **profile) as dst:
        dst.write(smoothed, 1)

    print(f"已輸出平滑 DEM：{DST}")
    print(f"  原始範圍 {float(arr.min()):.0f}~{float(arr.max()):.0f} m，"
          f"平滑後 {float(smoothed.min()):.0f}~{float(smoothed.max()):.0f} m")


if __name__ == "__main__":
    main()
