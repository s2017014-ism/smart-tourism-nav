# 專案報告：適應型智慧旅遊導航與路徑調配系統

## 1. 專案簡介與動機

自由行旅客面對網路上大量「必去景點／攻略」，卻難以解決「**怎麼走最順、公車怎麼轉**」的實際問題；行前排行程耗時，現場又常遇繞路、迷路。從資訊科學角度，這是一個**多條件限制下的路徑尋優問題**：要同時考慮景點營業時間、步行與公車換乘、坡度與階梯、即時環境變化。

本專案以**澳門**為場域，打造「下一代自適應旅遊導航系統」：在傳統導航地圖上加入一個會隨機應變的智慧大腦，讓使用者「出發前免帶大腦規劃、一路上精準跟著走」。

---

## 2. 系統總體架構

```
┌──────────────────────── Flutter App（flutter_map）────────────────────────┐
│  地圖顯示 / 起終點選擇 / 景點搜尋 / 我的位置 / 介面收合                       │
└───────────────┬───────────────────────────────────────────────────────────┘
                │  REST（JSON / GeoJSON）
┌───────────────▼──────────────── FastAPI 後端 ─────────────────────────────┐
│  /route          走路導航（A*＋坡度/階梯）                                  │
│  /transit-route  走＋公車多模態（真實線形、轉乘、服務時間）                   │
│  /itinerary      多景點行程排序（OR-Tools TTDP/OPTW）                       │
│  /plan-from-text 自然語言 → 行程（LLM 意圖解析）                            │
│  /pois           景點資料                                                  │
│                                                                            │
│  路徑優化引擎 ── 多模態路網（NetworkX）── OSMnx 步行路網 + DSAT 公車資料      │
│  外掛：SRTM DEM（坡度）、LLM API（意圖解析）                                 │
└────────────────────────────────────────────────────────────────────────────┘
```

**關鍵設計**：把「景點排序」（NP-hard 的 TTDP）與「兩點最短路徑」（A*）拆成兩個引擎；前者用 OR-Tools，後者用 NetworkX 自訂成本函數。

---

## 3. 技術棧

| 層 | 技術 |
|---|---|
| 前端 | Flutter 3.47、flutter_map 8、latlong2、geolocator、shared_preferences |
| 後端 | Python、FastAPI、Uvicorn、Pydantic v2 |
| 地理/路網 | OSMnx 2、NetworkX、GeoPandas、Shapely、pyproj、rasterio |
| 演算法 | Dijkstra / A*、Google OR-Tools（RoutingModel）、SRTM 高程 |
| LLM | DeepSeek（OpenAI 相容 Function Calling；未設定時規則式備援） |
| 資料 | OpenStreetMap、澳門交通事務局 DSAT（data.gov.mo）、SRTM 30m |

---

## 4. 系統功能（依階段）

| 階段 | 功能 | 狀態 |
|---|---|---|
| P1 | 走路導航：OSMnx 路網 + A* + GeoJSON | ✅ |
| P2 | 多景點行程排序（TTDP/OPTW，OR-Tools） | ✅ |
| P3 | 走＋公車多模態（真實線形、轉乘、服務時間） | ✅ |
| P4 | DEM 坡度與階梯避讓 | ✅ |
| P5 | LLM 自然語言意圖解析 | ✅ |
| — | 額外：1038 景點 POI、儲存行程、景點搜尋、我的位置、介面收合 | ✅ |

**資料規模**
* 步行路網：14,328 節點 / 40,326 邊
* 巴士：613 站、101 路線、12,804 乘車邊、2,879 路段線形
* 景點 POI：1,038 筆（9 類別，含美食）
* 多模態路網：17,868 節點 / 52,402 邊

---

## 5. 資料來源與前處理

* **步行路網**：OSMnx 下載 OpenStreetMap（澳門 bbox），以 `highway=steps` 標記階梯。
* **景點 POI**：OSM（`tourism` / `historic` / `natural` / `food` 等標籤），再用**澳門行政邊界多邊形**過濾掉範圍外的珠海景點（排除 43 筆）。
* **公車**：官方 DSAT「巴士路線資料」（`BUS_POLE.shp` / `BUS_ROUTE_SEQ.xls` / `ROUTE_NETWORK.shp`）。
  * **座標基準校正**：DSAT 使用澳門格網（Macau Grid，International 1924），轉 WGS84 少了基準轉換，會有約 **306 m 系統偏移**。以 128 組同名巴士站配對求得平移量（經度 +0.00297845、緯度 −0.00119120），校正後殘差平均 **8.6 m**。
  * 以 `ROUTE_NETWORK` 的路段線形串接出**沿實際道路**的公車段（非直線）。
* **高程 DEM**：SRTM 30m（AWS 公開圖磚），以 5×5 移動平均平滑，降低短邊坡度雜訊。

---

## 6. 核心演算法與技術亮點

### 6.1 多模態路網（三層節點模型）
* 節點：步行節點 ／ 站點節點 `("S", pole_id)` ／ 路線站節點 `("RS", route, dir, idx)`。
* 邊：`walk / access / egress / transfer`（步行）、`board`（候車＋換乘）、`alight`、`bus`（行車）。
* **為何要路線站節點**：同一站換不同路線時必經 `alight → board`，才能正確計入換乘；若共用站點，換路線會變免費而低估成本。

### 6.2 行程排序 TTDP（OR-Tools）
* 以候選景點兩兩旅行時間矩陣建立 `RoutingModel`。
* 時間維度 + 營業時間窗 + 停留時間；`AddDisjunction` 讓低價值景點可放棄、必訪給極大懲罰。
* 額外機制：**空間稀疏化**（避免「走 0 公尺多一站」）、**美食站數上限**（計數維度）、**最多轉乘次數**（分層搜尋）。

### 6.3 服務時間與通宵線
* N 系列（N1A/N1B/N2/N3/N5/N6）只在 **00:00–06:00** 行駛，其餘 06:00–24:00；依出發時間排除不營運路線。

### 6.4 坡度與階梯避讓
* 階梯：OSM `highway=steps` 硬性封鎖。
* 坡度：採**懲罰而非封鎖**（`cost ×= 1 + 4·grade`；長陡邊再 ×50），避免山頂/死巷節點被切斷而無法到達。

### 6.5 LLM 意圖解析
* 以 Function Calling 強制輸出 `TripIntent`（schema 即 Pydantic 模型）。
* 不支援 tools 的供應商自動退回「要求輸出 JSON」；再不行則用本機規則式，確保離線可用。

---

## 7. 工程挑戰與解法（摘要）

| 挑戰 | 解法 |
|---|---|
| Python 3.14 地理套件相容性 | 實測所有套件皆有 `cp314` wheel，可直接用 |
| 專案路徑含中文使 `flutter analyze` 崩潰 | 改用 `dart analyze lib`（build/run 不受影響） |
| OR-Tools 對終點 `NodeToIndex()` 回傳 −1 → 崩潰 | 改用 `routing.Start(0)` / `routing.End(0)` |
| `must_visit` 子字串誤抓同系列景點 | 每個關鍵字只取名稱最接近者 |
| 美食點密集塞滿行程 | 美食站數上限 + 空間稀疏化 |
| 首次規劃等 14 秒 | `nearest_nodes` 向量化（快 20 倍）+ 啟動暖機 → 0.4 秒 |
| 公車段穿過大樓 | 改用 `ROUTE_NETWORK` 真實道路線形 |
| 路線與底圖對不上 306 m | 座標基準平移校正（以同名站配對） |
| SRTM 短邊坡度雜訊 | DEM 平滑 + 坡度上限截斷 + 懲罰式設計 |

---

## 8. 已知限制

* **人潮／即時到站**：官方未開放標準 GTFS-Realtime，目前以靜態班次＋期望候車時間近似（P6 未實作）。
* **DEM 精度**：SRTM 30m 對街道級坡度仍有誤差，故坡度採軟性引導而非硬性封鎖。
* **公車乘車時間**：以實際道路長度 ÷ 平均車速估算，未含個別路線班距。
* **LLM 依賴外部 API**：需要網路與金鑰；已提供規則式備援。

---

## 9. 未來展望

* **P6 即時重排**：接天氣 API、時空人潮模型、GPS 偏離偵測，觸發即時重新規劃。
* 公車**班次時刻表**與即時到站（銜接 DSAT 報站 API）。
* 以 `ROUTE_NETWORK` 強化公車段繪製、加入**無障礙電梯**節點。
* 「多模態交通路網權重優化」與「實時環境重路由」技術可延伸至**智慧城市物流配送、醫療接駁、防災疏散**。

---

## 10. 專案結構與執行

```
backend/   FastAPI + OSMnx + OR-Tools + LLM
  app/{api,graph,optimize,services,geo}
  scripts/{fetch_pois,build_bus_data,build_dem,smoke_*}
  data/{raw,cache}  (+ bus_stops.geojson / bus_routes.json / bus_segments.json / poi_macau.geojson)
frontend/  Flutter App
  lib/{screens,models,services,widgets}
docs/      ROADMAP / DEMO / REPORT
```

**執行**
```powershell
cd backend  ; .\run_server.ps1        # http://127.0.0.1:8000/docs
cd frontend ; flutter run -d chrome
```

詳細操作見 `docs/DEMO.md`；階段規劃見 `docs/ROADMAP.md`。
