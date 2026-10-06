"""下載 SRTM 30m 高程並產生平滑後的 DEM（啟用坡度避讓功能）。

下載來源：AWS 公開 SRTM 圖磚（elevation-tiles-prod, skadi）。
輸出：
  data/raw/dem/N22E113.hgt            原始高程
  data/raw/dem/macau_dem_smooth.tif   平滑後（後端實際使用）

用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\download_dem.py
"""

from __future__ import annotations

import gzip
import os
import shutil
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np  # noqa: E402
import rasterio  # noqa: E402
import requests  # noqa: E402
from scipy.ndimage import uniform_filter  # noqa: E402

from app.config import settings  # noqa: E402

URL = "https://s3.amazonaws.com/elevation-tiles-prod/skadi/N22/N22E113.hgt.gz"
HGT = settings.data_dir / "dem" / "N22E113.hgt"
SMOOTH = settings.data_dir / "dem" / "macau_dem_smooth.tif"
SIZE = 5  # 5x5 像素 ≈ 150m 移動平均


def main() -> None:
    HGT.parent.mkdir(parents=True, exist_ok=True)

    if not HGT.exists():
        gz = HGT.with_suffix(".hgt.gz")
        print(f"下載 SRTM 高程：{URL}")
        with requests.get(URL, timeout=300, stream=True) as r:
            r.raise_for_status()
            with open(gz, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
        print("解壓縮 ...")
        with gzip.open(gz, "rb") as fi, open(HGT, "wb") as fo:
            shutil.copyfileobj(fi, fo)
        gz.unlink(missing_ok=True)
        print(f"完成：{HGT}")
    else:
        print(f"已存在，略過下載：{HGT}")

    print("產生平滑 DEM ...")
    with rasterio.open(HGT) as src:
        arr = src.read(1).astype("float32")
        profile = src.profile.copy()
    void = arr < -1000
    land = np.where(void, 0.0, arr)
    smoothed = uniform_filter(land, size=SIZE, mode="nearest")
    smoothed = np.where(void, arr, smoothed)
    profile.update(driver="GTiff", dtype="float32", count=1, compress="lzw")
    with rasterio.open(SMOOTH, "w", **profile) as dst:
        dst.write(smoothed, 1)

    print(f"完成：{SMOOTH}")
    print("請重新啟動後端，坡度／階梯避讓功能即會生效。")


if __name__ == "__main__":
    main()
