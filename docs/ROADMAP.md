# 開發路線圖（Roadmap）

本文件把專案拆成可獨立驗收的階段。**每一階段都要能跑出成果**，不要等到最後才整合。

---

## Phase 1 ✅ 走路導航（已完成）

| 項目 | 檔案 |
|---|---|
| 路網下載 / 快取 | `backend/app/graph/loader.py` |
| 成本函數與 A* | `backend/app/optimize/pathfinding.py` |
| GeoJSON 產生 | `backend/app/geo/geojson.py` |
| API | `backend/app/api/route.py` |
| 前端地圖與繪線 | `frontend/lib/screens/map_screen.dart` |

**成本函數**：`cost = length / walking_speed`，`avoid_stairs` 時階梯邊直接移除。

**驗收**：在地圖點兩點 → 畫出貼合街道的路線 + 距離/時間。

---

## Phase 2 ✅ 多景點行程排序（TTDP / OPTW）（已完成）

**目標**：給一批候選景點（含營業時間、停留時間），在使用者時間預算下決定
「去哪些、什麼順序」，讓價值最大、移動成本最小。

**做法**：用 Google OR-Tools `RoutingModel`
1. 用 Phase 1 的求路引擎算景點兩兩的**旅行時間矩陣**。
2. Time 維度 + 各景點 `(start, end)` 時間窗 + 停留時間（服務時間）。
3. `AddDisjunction` 讓低價值景點可放棄、必訪景點給極大懲罰。
4. 搜尋策略：`PATH_CHEAPEST_ARC` + `GUIDED_LOCAL_SEARCH`。

**檔案**：`backend/app/optimize/ttdp.py`、`backend/app/api/itinerary.py`
**POI 資料**：`backend/scripts/fetch_pois.py` 從 OSM 抓取，含觀光/歷史/自然/休閒/設施/
廣場/地標/必訪/**美食** 共 9 類、約 1038 筆；已用澳門行政邊界（MultiPolygon）過濾掉
珠海等範圍外的景點。
**前端**：`frontend/lib/screens/itinerary_screen.dart`，地圖標示編號景點與路線。

**已實作的額外機制**：
* **空間稀疏化**（`min_spacing_m`）：彼此太近的景點只留一個，避免「走 0 公尺就多一站」。
* **美食站數上限**（`max_food_stops`，OR-Tools 計數維度）：避免密集的美食點塞滿整趟行程。
* **必訪精準比對**：`must_visit` 每個關鍵字只挑名稱最接近的一筆，避免子字串誤抓同系列景點。

> ⚠️ 踩過的坑：以 list 形式建立 `RoutingIndexManager(num_nodes, 1, [start], [end])` 時，
> 對**終點**呼叫 `manager.NodeToIndex(end)` 會回傳 `-1`，拿去 `CumulVar().SetRange()`
> 會造成 access violation 崩潰。務必改用 `routing.Start(0)` / `routing.End(0)` 取得索引。

---

## Phase 3 ✅ 走 + 公車多模態（已完成）

**目標**：把步行網路與公車網路合併成一張 MultiDiGraph，並正確處理轉乘。

**實作**
* 三層節點：步行節點（OSMnx）／站點節點 `("S", pole_id)`／路線站節點 `("RS", route, dir, idx)`。
* 邊：`walk` / `access` / `egress`（步行時間）、`board`（候車＋換乘懲罰）、
  `alight`、`bus`（距離 × 繞行係數 / 車速）。
* **為何要路線站節點**：同站換路線必經 `alight → station → board`，才會付出換乘懲罰；
  若共用站點，換路線會變成免費。
* 成本：候車 5 分 + 換乘 3 分；車速 8 m/s、繞行係數 1.3。短程自然選步行。

**資料**：官方 DSAT「巴士路線資料」（data.gov.mo，`BUS_POLE.shp` + `BUS_ROUTE_SEQ.xls`）
→ 613 站（Macau Grid 轉 WGS84）、101 路線、12,804 乘車邊。

**檔案**：`backend/scripts/build_bus_data.py`、`backend/app/services/bus_data.py`、
`backend/app/graph/multimodal.py`、`backend/app/api/transit.py`、`backend/scripts/smoke_transit.py`

**前端**：地圖主畫面切換「大眾運輸（走 + 公車）」，紫色路線 + 各段運具摘要。

**待延伸**：即時到站（GTFS-Realtime 未開放，可用 DSAT 報站 API）、班次時刻表。

---

## Phase 4 ✅ 微觀地形與階梯避讓（已完成）

**實作**
* DEM：SRTM 30m（AWS 公開 skadi 圖磚 `N22E113.hgt`），以 `scripts/build_dem.py`
  做 5×5 移動平均平滑後存成 `data/raw/dem/macau_dem_smooth.tif`。
* 高程：`loader._decorate` 於載入時以 `ox.elevation.add_node_elevations_raster(G, dem, cpus=1)`
  + `ox.elevation.add_edge_grades(G)` 加入 `elevation` / `grade` / `grade_abs`，
  並回存 GraphML；用 `data/cache/dem_used.txt` 記錄所用 DEM，換 DEM 會自動重算。
  （`cpus=1` 是為了避開 Windows multiprocessing 重新匯入 `__main__` 的遞迴問題。）
* **階梯**：`highway=steps` → `edge['is_stairs']`，`avoid_stairs` 時硬性封鎖。
* **坡度**：`app/optimize/slope.py`。因 SRTM 30m 在短邊上雜訊大、且硬封鎖會讓
  山頂／死巷節點無法連通，改採**懲罰**：
  `cost ×= (1 + 4·grade)`，長度 ≥ 25m 且超過 `max_slope_pct` 的邊再 ×50；
  grade 上限截斷 35%。
* 前端：導航頁與行程規劃頁皆加入「避開階梯」「避免陡坡」開關。

**檔案**：`scripts/build_dem.py`、`app/optimize/slope.py`、`app/graph/loader.py`

**驗證**：海域 ≈ 0m；峰頂與 OSM `ele` 平均差 −6m；`avoid_stairs` 可將含階梯路線
改道（例：509m→1473m 且 0 階梯）；`max_slope_pct` 使長陡邊被強力避開仍可達。

---

## Phase 5 ✅ LLM 意圖解析（已完成）

**目標**：把「我想看特殊岩石或歷史地質線路，但不想走太累」轉成行程條件並直接排程。

**實作**
* 新增 `TripIntent`（`schemas.py`）：categories / must_visit / avoid_stairs /
  avoid_steep / duration_hours / departure_time / max_food_stops / start_name / summary。
* LLM：呼叫任何 OpenAI 相容 API 的 **Function Calling**，工具參數即
  `TripIntent.model_json_schema()`，強制結構化輸出；金鑰/模型由 `.env`
  （`STN_LLM_BASE_URL` / `STN_LLM_API_KEY` / `STN_LLM_MODEL`）設定，不本地部署。
* **規則式備援**：未設定金鑰或呼叫失敗時，以關鍵詞比對（類別、避階梯/陡坡、時數、
  必訪 POI、起點）解析，離線也能 demo；回應以 `source` 標示 `llm` / `rules`。
* 端點：`POST /api/v1/plan-from-text`（解析＋排程）、`POST /api/v1/parse-intent`（僅解析）。
* 起點解析：`start_name` 以名稱比對 POI 取得座標，否則用預設點（議事亭前地）。

**檔案**：`backend/app/services/llm.py`、`backend/app/api/intent.py`

**前端**：行程規劃頁「用一句話描述…」＋「AI 規劃」，顯示「已理解」摘要並套用參數。

---

## Phase 6 動態重排 ⏭️ 略過（未實作）

**目標**：事件驅動的即時重排（**不要每秒重算**）。

**觸發條件**（觸發才從當前位置重跑排序 + 路由）：
* GPS 偏離原路線 > 100 m
* 氣象發布暴雨警告（SMG / OpenWeatherMap）
* 下一景點預測擁擠度超過門檻

**人潮**：官方無即時資料 → 用「時空歷史查表模型」`(poi, weekday, hour, season) → 0~1`。
報告中需誠實標明為推估值。

**檔案（預留骨架）**：`backend/app/services/weather.py`、`crowd.py`

> 本專案經決議**跳過 P6**，直接進行 P7。

---

## Phase 7 ✅ 整合與 Demo（已完成）

* UI 打磨：導航頁上下介面收合、起／終點獨立選擇、無障礙單一開關；
  AI 規劃與行程求解皆有載入遮罩提示。
* 功能整合：走路導航、走＋公車、智慧行程、自然語言規劃、儲存行程、
  景點搜尋、我的位置。
* 文件：`docs/DEMO.md`（Demo 腳本）、`docs/REPORT.md`（專案報告）、`README.md`。
* 端到端驗證：`dart analyze` 無誤、`python compileall` 通過、
  API（route / transit-route / itinerary / plan-from-text）皆 200。
