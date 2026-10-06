"""驗證 Phase 2：多景點行程排序。

用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\smoke_itinerary.py
"""

from __future__ import annotations

import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.optimize import ttdp  # noqa: E402
from app.schemas import ItineraryRequest, LatLng  # noqa: E402


def main() -> None:
    req = ItineraryRequest(
        start=LatLng(lat=22.19356, lng=113.53963),   # 議事亭前地
        departure_time="09:00",
        duration_hours=6,
        categories=["tourism", "historic", "natural", "curated", "food"],
        must_visit=["大三巴"],
        max_candidates=25,
        radius_m=4000,
        dwell_minutes=30,
    )

    print("求解中（OR-Tools）...")
    r = ttdp.solve(req)

    print(f"\n造訪 {r['num_visited']} 個景點　總步行 {r['total_distance_m']} m　"
          f"行程長度 {r['total_duration_min']} 分鐘\n")
    for s in r["stops"]:
        print(f"  {s['order']:2d}. {s['arrival']}-{s['departure']}  "
              f"{s['name']}  [{s['category_label']}]  (+{s['travel_from_prev_m']}m)")

    print(f"\n未排入 {len(r['skipped'])} 個候選景點")
    print(f"GeoJSON 折線點數：{len(r['geometry']['coordinates'])}")
    print("\n[OK] Phase 2 行程排序運作正常。")


if __name__ == "__main__":
    main()
