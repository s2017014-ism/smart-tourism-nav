# 適應型智慧旅遊導航與路徑調配系統

> Adaptive Smart Tourism Navigation & Route Allocation System

以澳門為場域的下一代自適應旅遊導航系統：結合 **多模態路網權重**、**微觀地形避讓**、
**即時重排** 與 **LLM 意圖解析**，把使用者的自然語言需求轉成可執行的高品質旅遊路線。

---

## 目前進度

| 階段 | 內容 | 狀態 |
|---|---|---|
| **P0** | 環境 + 專案骨架（FastAPI / Flutter） | ✅ 完成 |
| **P1** | **走路導航端到端**：OSMnx 路網 + A* + GeoJSON + Flutter 畫線 | ✅ 完成 |
| P2 | **多景點行程排序（TTDP / OPTW，OR-Tools）** | ✅ 完成 |
| P3 | **走 + 公車多模態路網（含轉乘懲罰）** | ✅ 完成 |
| P4 | **DEM 坡度與階梯避讓** | ✅ 完成 |
| P5 | **LLM 意圖解析（自然語言→行程）** | ✅ 完成 |
| P6 | 天氣 / 人潮 / 偏離偵測與即時重排 | ⏭️ 略過（未實作） |
| P7 | **UI 打磨、Demo、報告** | ✅ 完成 |

---

## 系統架構

```
Flutter App (flutter_map)
      │  POST /api/v1/route  (JSON)
      ▼
FastAPI  ──►  意圖解析 (P5) ──►  行程排序引擎 (P2, TTDP)  ──►  逐段路由引擎 (P1)
                                                                    │
                                        OSMnx / NetworkX 路網 ◄──────┘
                                                                    │
                                        GeoJSON 回傳 ◄──────────────┘
```

**關鍵設計**：把「景點排序」（NP-hard 的 TTDP）與「兩點最短路徑」（Dijkstra/A*）
拆成兩個引擎。前者用 OR-Tools，後者用 NetworkX + 自訂成本函數。

---

## 目錄結構

```
.
├─ backend/                     # Python FastAPI 後端
│  ├─ app/
│  │  ├─ main.py                # 進入點（含 CORS、lifespan 暖機）
│  │  ├─ config.py              # 設定（.env 前綴 STN_）
│  │  ├─ schemas.py             # Pydantic 模型（含 Intent）
│  │  ├─ api/                   # route / itinerary / intent
│  │  ├─ graph/                 # loader（P1）、multimodal（P3）、terrain（P4）
│  │  ├─ optimize/              # pathfinding（P1）、ttdp（P2）
│  │  ├─ services/              # llm（P5）、weather / crowd（P6）
│  │  └─ geo/                   # GeoJSON 輔助
│  ├─ data/                     # raw（原始資料）、cache（graphml 快取）
│  ├─ requirements.txt
│  └─ .env.example
├─ frontend/                    # Flutter App
│  └─ lib/
│     ├─ main.dart
│     ├─ config.dart            # API 位址、澳門中心點
│     ├─ models/route_plan.dart
│     ├─ services/api_client.dart
│     ├─ screens/map_screen.dart
│     └─ widgets/numbered_marker.dart
└─ docs/ROADMAP.md
```

---

## 快速開始

### 後端

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

uvicorn app.main:app --reload --port 8000
```

* 第一次啟動會用 OSMnx 下載澳門路網（約 30~90 秒），並存成
  `backend/data/cache/macau_walk.graphml`，之後啟動秒開、也可離線。
* API 文件：<http://127.0.0.1:8000/docs>
* 健康檢查：<http://127.0.0.1:8000/health>
* 路網資訊：<http://127.0.0.1:8000/api/v1/meta>

測試一段路線（大三巴 → 媽閣廟）：

```powershell
curl -X POST http://127.0.0.1:8000/api/v1/route `
  -H "Content-Type: application/json" `
  -d '{"origin":{"lat":22.19745,"lng":113.54077},"destination":{"lat":22.18615,"lng":113.53098},"preferences":{"avoid_stairs":true}}'
```

### 前端

```powershell
cd frontend
flutter pub get
flutter run -d chrome     # 或 -d windows / -d <android 裝置>
```

App 操作：
* **設定起點 / 設定終點**：面板中此切換鈕位於「定位為起點／終點」上方；選好後點地圖
  即可設定該端點（修改終點不會動到起點）。
* **我的位置**：面板上的「定位為起點 / 定位為終點」按鈕（需定位權限）以 GPS 設定端點。
* **搜尋景點**：右上角 🔍 開啟搜尋，將景點設為起點或終點。
* **收合介面**：下方介面的 ▼ 可向下收起、上方 AppBar 的 ▲ 可向上收起；
  收起後會出現方向鈕可展開。
* 開關「無障礙路線（避開階梯與陡坡）」、「大眾運輸（走 + 公車）」；按「規劃路線」
  在地圖上畫出藍色（步行）／紫色（公車）路線。
* 右上角 ✨ 進入「智慧行程規劃」、🔖 進入「我的行程」。

---

## API 合約（Phase 1）

`POST /api/v1/route`

```jsonc
// Request
{
  "origin":      { "lat": 22.19745, "lng": 113.54077 },
  "destination": { "lat": 22.18615, "lng": 113.53098 },
  "preferences": { "avoid_stairs": false, "max_slope_pct": null, "pace": "normal" }
}

// Response
{
  "distance_m": 1832.4,
  "duration_s": 1357.3,
  "geometry": { "type": "LineString", "coordinates": [[113.54,22.19], ...] },
  "nodes": 120,
  "origin_snapped":      { "lat": 22.1974, "lng": 113.5408 },
  "destination_snapped": { "lat": 22.1861, "lng": 113.5309 },
  "steps": [ { "instruction": "沿 大三巴街 前行", "distance_m": 320.1, "duration_s": 237.1 } ]
}
```

---

### 景點 POI

```
GET /api/v1/pois?category=<類別>&limit=<n>   → GeoJSON FeatureCollection（含 count）
GET /api/v1/pois/categories                   → { "categories": [...] }
```

* 資料由 `backend/scripts/fetch_pois.py` 從 OpenStreetMap 抓取後存成
  `backend/data/poi_macau.geojson`（目前 1038 筆，9 個類別；已用澳門行政邊界過濾掉範圍外的珠海景點）。
* 更新資料：`cd backend` → `.venv\Scripts\python.exe scripts\fetch_pois.py`
* 類別：`tourism` / `historic` / `natural` / `leisure` / `amenity` / `man_made` / `place` / `curated` / `food`（美食）
* 前端地圖會依類別上色顯示這些景點，點擊標記可查看名稱並「設為起點／終點」。

### 智慧行程規劃（Phase 2）

`POST /api/v1/itinerary` → 多景點行程排序（OR-Tools TTDP / OPTW）

```jsonc
// Request
{
  "start": { "lat": 22.19356, "lng": 113.53963 },
  "departure_time": "09:00",
  "duration_hours": 6,
  "categories": ["tourism", "historic", "natural", "curated", "food"],
  "must_visit": ["大三巴"],
  "max_candidates": 25,
  "max_food_stops": 2,
  "radius_m": 4000,
  "min_spacing_m": 120,
  "dwell_minutes": 30
}
// Response：stops[]（順序 / 到達 / 離開 / 停留 / 步行距離）+ 串接的 GeoJSON LineString
```

* 用 OR-Tools `RoutingModel`：時間維度 + 營業時間窗 + 停留時間 +
  可放棄景點（disjunction penalty）+ 美食站數上限 + 空間稀疏化。
* 前端：主畫面右上角 ✨ 進入「智慧行程規劃」，地圖標示編號景點與路線。
* 儲存行程：產生後按「儲存行程」可命名保存；右上角 🔖「我的行程」可載入 / 刪除
  （用 `shared_preferences` 存在裝置本機）。
* 驗證：`backend/scripts/smoke_itinerary.py`（需先安裝 `ortools`）。

### 多模態路線（Phase 3）

`POST /api/v1/transit-route` → 走 + 公車路線（含轉乘）

```jsonc
// Request：同 /route（origin / destination / preferences）
// Response：
{
  "mode": "mixed",                 // walk / bus / mixed
  "total_distance_m": 5556.6,
  "total_duration_s": 2034.0,
  "num_transfers": 0,
  "legs": [
    { "mode": "walk", "distance_m": 429.8, "duration_s": 318.0, "geometry": {...} },
    { "mode": "bus", "route": "18", "from_name": "祐漢街市", "to_name": "澳門旅遊塔",
      "num_stops": 12, "duration_s": 1200.0, "geometry": {...} },
    { "mode": "walk", "distance_m": 694.8, "duration_s": 516.0, "geometry": {...} }
  ],
  "geometry": { "type": "LineString", "coordinates": [...] }
}
```

* **座標校正（重要）**：DSAT 的 shapefile 用澳門格網（Macau Grid，International 1924
  基準），轉到 WGS84 時少了基準轉換，會產生約 300m 的系統性偏移，導致路線與
  底圖對不上。以 128 組「同名巴士站（OSM `ref` ↔ DSAT 站碼）」配對求得平移量
  （經度 `+0.00297845`、緯度 `-0.00119120`），校正後殘差平均約 8.6m。
  常數定義於 `scripts/build_bus_data.py`。
* **服務時間（通宵線）**：N 系列（N1A / N1B / N2 / N3 / N5 / N6）只在 **00:00–06:00**
  行駛，其餘路線 06:00–24:00。`/transit-route` 可帶 `departure_time`（HH:MM），
  未提供時使用伺服器目前時間（澳門時區 UTC+8）；引擎會依時間排除不營運的路線。
  前端導航頁「大眾運輸」模式下可選擇出發時間（預設「現在」）。
* **公車段線形**：使用官方 `ROUTE_NETWORK.shp` 的真實道路線形（2,879 條路段），
  依站序串接，因此路線會沿著道路走，不會穿過建築物。
* 回應會明確標示**在哪一站上車、哪一站下車**（`from_name` / `to_name` / `stops`）。
* 資料來源：官方 DSAT「巴士路線資料」（data.gov.mo）→ 613 站 + 101 路線 + 12,804 乘車邊。
* 建資料：`cd backend` → `.venv\Scripts\python.exe scripts\build_bus_data.py`
* 成本模型：每次上車＝候車 2 分（**不計轉乘成本**），行車＝實際道路長度 / 8 m·s⁻¹；
  以「分層搜尋」硬性限制**最多轉乘 3 次**（`max_transfers`，預設 3）。
  短程仍自然選擇步行。
* **關鍵設計**：以「路線站節點」建模，同一站換不同路線時必經
  alight→station→board；每一次 board 都算一次「上車」，用來限制轉乘次數。
* **轉乘**：當單一路線到不了目的地時會自動換路線（例：關閘→旅遊塔 = 3 → 26）。
  除同一站轉乘外，另為相距 150m 內的鄰近站位建立直接轉乘步行邊，
  避免繞遠路；前端以「轉乘」字樣標示。
* **效能**：多模態路網於伺服器啟動時暖機（建圖約 0.7 秒），單次查詢約 0.4 秒，
  不會再出現「首次規劃要等很久」。
  （關鍵：`nearest_nodes` 一次向量化傳入所有站點座標，比逐一呼叫快約 20 倍。）

### 地形與階梯避讓（Phase 4）

* **DEM**：SRTM 30m（`data/raw/dem/macau_dem_smooth.tif`，以 5×5 移動平均平滑，
  降低 30m 網格在短邊上的坡度雜訊）。建檔：`scripts/build_dem.py`。
* **避開階梯** `preferences.avoid_stairs=true`：硬性封鎖 OSM `highway=steps`
  路段（澳門共 1,446 條）。
* **避免陡坡** `preferences.max_slope_pct=<n>`：坡度採**懲罰而非封鎖** ——
  一般邊 `cost ×= 1 + 4·grade`；長度 ≥ 25m 且超過門檻的邊再乘 50 倍
  （強力避開但仍可通行，**保證可達、不會斷路**）；grade 上限截斷於 35% 以抑制雜訊。
* **前端**：導航頁與行程規劃頁皆有單一「無障礙路線（避開階梯與陡坡）」開關。
* 高程正確性：海域 ≈ 0m、峰頂（疊石塘山 166m、大潭山 159m）與 OSM `ele` 平均差 −6m。

### 自然語言行程（Phase 5）

* `POST /api/v1/plan-from-text`：一句話 → 結構化意圖 → 直接排出行程。
* `POST /api/v1/parse-intent`：只回傳解析後的意圖（輕量，方便測試）。

```jsonc
// plan-from-text request
{ "text": "我想看歷史地質路線但不想走太累，6小時" }
// response
{
  "source": "rules",              // llm（有設定金鑰）或 rules（備援）
  "intent": { "categories": ["historic","natural"], "avoid_stairs": true,
              "avoid_steep": true, "duration_hours": 6, "summary": "..." },
  "resolved_start": { "lat": 22.1936, "lng": 113.5396 },
  "itinerary": { /* 同 /itinerary */ }
}
```

* **LLM**：任何 OpenAI 相容 API 的 Function Calling；於 `.env` 設定
  `STN_LLM_BASE_URL` / `STN_LLM_API_KEY` / `STN_LLM_MODEL`（例：Qwen `qwen-plus`）。
* **規則式備援**：未設定金鑰或呼叫失敗時，自動以關鍵詞規則解析，離線也能 demo
  （回應 `source` 會標示 `rules`）。
* 前端：行程規劃頁最上方「用一句話描述…」＋「AI 規劃」按鈕，會顯示「已理解」摘要並套用參數。

---

## 已知環境問題（重要）

| 問題 | 說明 | 解法 |
|---|---|---|
| `flutter analyze` 崩潰 | 專案路徑含中文字元，Dart 分析伺服器在 Windows 有 JSON 解析 bug | 改用 `dart analyze lib`（`flutter build/run` 不受影響） |
| Windows 桌面執行需 **開發者模式** | flutter_map 依賴 path_provider 等原生外掛，建置需符號連結權限 | 設定 → 系統 → 開發人員選項 → 開啟「開發人員模式」 |
| OSMnx 首次下載需連網 | 需連到 OpenStreetMap Overpass API | 下載一次後即有 GraphML 快取，之後可離線 |

---

## 授權與資料來源

* 路網資料：© OpenStreetMap contributors（ODbL）
* 公車資料（P3）：澳門交通事務局 DSAT，data.gov.mo「巴士路線資料」
  （`BUS_POLE.shp` / `BUS_ROUTE_SEQ.xls` / `ROUTE_NETWORK.shp`）
* DEM 高程（P4）：SRTM 30m（AWS 公開 skadi 圖磚）

---

## 文件

* `docs/DEMO.md` — **成果 Demo 腳本**（逐步操作與示範輸入）
* `docs/REPORT.md` — **專案報告**（架構、技術、挑戰、限制、展望）
* `docs/ROADMAP.md` — 各階段開發規劃
