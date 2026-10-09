"""FastAPI 進入點。

啟動：  uvicorn app.main:app --reload --port 8000
文件：  http://127.0.0.1:8000/docs
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import intent as intent_api
from .api import itinerary as itinerary_api
from .api import poi as poi_api
from .api import route as route_api
from .api import transit as transit_api
from .api import weather as weather_api
from .config import settings
from .graph import multimodal
from .graph.loader import get_graph, graph_info, terrain_info
from .services import llm as llm_service

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("smartnav")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # 暖機：啟動時先載入路網與多模態路網，避免第一次請求才臨時建圖。
    # 若離線或下載失敗，不讓 API 崩潰，等第一次請求時再試。
    try:
        G = get_graph()
        log.info("路網就緒：%d 節點 / %d 邊", G.number_of_nodes(), G.number_of_edges())
    except Exception as exc:  # noqa: BLE001
        log.warning("路網暖機失敗（可稍後重試）：%s", exc)
    try:
        H = multimodal.get_multimodal()
        log.info("多模態路網就緒：%d 節點 / %d 邊", H.number_of_nodes(), H.number_of_edges())
    except Exception as exc:  # noqa: BLE001
        log.warning("多模態路網暖機失敗（可稍後重試）：%s", exc)
    t = terrain_info()
    if t.get("slope_data"):
        log.info(
            "地形資料：坡度 %d/%d 條邊、階梯 %d 條（無障礙／坡度避讓可用）",
            t["grade_edges"], t["edges"], t["stairs_edges"],
        )
    else:
        log.warning(
            "地形資料：缺少坡度（不會避開陡坡）。請確認 backend/data/cache/ 內含附高程的路網快取，"
            "或已下載 DEM（scripts/download_dem.py）。階梯 %s 條。",
            t.get("stairs_edges", 0),
        )
    if llm_service.llm_configured():
        log.info("LLM 已設定：%s（自然語言規劃可用）", settings.llm_model)
    else:
        log.warning(
            "LLM 未設定（將使用規則式解析）。請於 backend/.env 設定 "
            "STN_LLM_BASE_URL 與 STN_LLM_API_KEY，存檔後重新啟動後端。"
        )
    try:
        # 預先算好「有／無階梯封鎖」兩種最大連通分量，供端點吸附使用。
        from .optimize import pathfinding

        Gr = get_graph()
        for flag in (False, True):
            log.info(
                "最大連通分量（avoid_stairs=%s）：%d 節點",
                flag, len(pathfinding.main_component(Gr, flag)),
            )
    except Exception as exc:  # noqa: BLE001
        log.warning("連通分量暖機失敗（可稍後重試）：%s", exc)
    yield


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(route_api.router, prefix=settings.api_prefix)
app.include_router(poi_api.router, prefix=settings.api_prefix)
app.include_router(itinerary_api.router, prefix=settings.api_prefix)
app.include_router(transit_api.router, prefix=settings.api_prefix)
app.include_router(intent_api.router, prefix=settings.api_prefix)
app.include_router(weather_api.router, prefix=settings.api_prefix)


@app.get("/health", tags=["meta"])
def health() -> dict:
    return {"ok": True, "app": settings.app_name, "version": "0.1.0"}


@app.get(f"{settings.api_prefix}/meta", tags=["meta"])
def meta() -> dict:
    return graph_info()
