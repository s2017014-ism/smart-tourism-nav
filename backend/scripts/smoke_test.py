"""快速驗證：直接呼叫求路引擎，印出一條澳門路線，不需要啟動伺服器。

用法（在 backend/ 目錄下）：
    .venv\\Scripts\\python.exe scripts\\smoke_test.py
"""

from __future__ import annotations

import os
import sys

# Windows 命令列預設可能是 cp950，強制用 utf-8 輸出避免亂碼／崩潰
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.graph.loader import get_graph, graph_info  # noqa: E402
from app.optimize import pathfinding  # noqa: E402
from app.schemas import LatLng, RoutePreferences  # noqa: E402


def main() -> None:
    print("載入澳門路網（首次會下載，約 30~90 秒）...")
    G = get_graph()
    info = graph_info()
    print(f"路網就緒：{info['nodes']} 節點 / {info['edges']} 邊（{info['network_type']}）")

    origin = LatLng(lat=22.19745, lng=113.54077)  # 大三巴牌坊
    dest = LatLng(lat=22.18615, lng=113.53098)    # 媽閣廟

    for avoid in (False, True):
        prefs = RoutePreferences(avoid_stairs=avoid)
        r = pathfinding.plan(G, origin, dest, prefs)
        print(f"\n=== avoid_stairs={avoid} ===")
        print(f"  距離 {r['distance_m']} m ／ 時間 {r['duration_s']} s ／ 路徑節點 {r['nodes']}")
        print(f"  GeoJSON 座標點數：{len(r['geometry']['coordinates'])}")
        for step in r["steps"][:5]:
            print(f"    - {step.instruction}（{step.distance_m} m）")

    print("\n[OK] 後端路線引擎運作正常。")


if __name__ == "__main__":
    main()
