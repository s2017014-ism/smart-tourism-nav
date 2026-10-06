"""驗證 Phase 3：走 + 公車多模態路線。

用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\smoke_transit.py
"""

from __future__ import annotations

import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.graph import multimodal  # noqa: E402
from app.schemas import LatLng, RoutePreferences  # noqa: E402


def run(title: str, o: LatLng, d: LatLng) -> None:
    r = multimodal.plan(o, d, RoutePreferences())
    print(f"\n=== {title} ===")
    print(
        f"  總計：{r['mode']}  {r['total_distance_m']} m  "
        f"{r['total_duration_s'] / 60:.1f} 分鐘  轉乘 {r['num_transfers']} 次"
    )
    for leg in r["legs"]:
        pts = len(leg["geometry"]["coordinates"])
        if leg["mode"] == "walk":
            print(f"    步行 {leg['distance_m']} m / {leg['duration_s'] / 60:.1f} 分（{pts} 點）")
        else:
            print(
                f"    公車 {leg['route']}：在「{leg['from_name']}」上車 → 在「{leg['to_name']}」下車"
                f"（{leg['num_stops']} 站, {leg['duration_s'] / 60:.1f} 分, {pts} 點）"
            )


def main() -> None:
    print("建立多模態路網（首次需數秒）...")
    H = multimodal.get_multimodal()
    print(f"路網：{H.number_of_nodes()} 節點 / {H.number_of_edges()} 邊")

    run("關閘 → 澳門旅遊塔（長程，應搭車）",
        LatLng(lat=22.215939, lng=113.549205), LatLng(lat=22.17960, lng=113.53644))
    run("關閘 → 媽閣廟",
        LatLng(lat=22.215939, lng=113.549205), LatLng(lat=22.18615, lng=113.53098))
    run("大三巴 → 議事亭前地（短程，應走路）",
        LatLng(lat=22.19745, lng=113.54077), LatLng(lat=22.19356, lng=113.53963))

    print("\n[OK] Phase 3 多模態路由運作正常。")


if __name__ == "__main__":
    main()
