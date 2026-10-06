"""Phase 5：LLM 意圖解析 API。"""

from __future__ import annotations

import logging

from fastapi import APIRouter

from ..optimize import ttdp
from ..schemas import (
    ItineraryRequest,
    ItineraryResponse,
    PlanFromTextRequest,
    PlanFromTextResponse,
    RoutePreferences,
    TripIntent,
)
from ..services import llm as llm_service

log = logging.getLogger(__name__)

router = APIRouter(tags=["intent"])

DEFAULT_CATEGORIES = ["tourism", "historic", "natural", "curated"]


@router.post("/parse-intent", response_model=TripIntent, summary="自然語言 → 結構化意圖（僅解析，不排程）")
def parse_intent(req: PlanFromTextRequest) -> TripIntent:
    intent, _source = llm_service.parse(req.text)
    return intent


@router.post(
    "/plan-from-text",
    response_model=PlanFromTextResponse,
    summary="自然語言 → 直接規劃行程",
)
def plan_from_text(req: PlanFromTextRequest) -> PlanFromTextResponse:
    intent, source = llm_service.parse(req.text)
    start = llm_service.resolve_start(intent, req.start)

    prefs = RoutePreferences(
        avoid_stairs=intent.avoid_stairs,
        max_slope_pct=12 if intent.avoid_steep else None,
    )
    it_req = ItineraryRequest(
        start=start,
        departure_time=intent.departure_time or "09:00",
        duration_hours=intent.duration_hours or 6,
        categories=intent.categories or DEFAULT_CATEGORIES,
        must_visit=intent.must_visit,
        max_food_stops=intent.max_food_stops if intent.max_food_stops is not None else 2,
        preferences=prefs,
    )

    itinerary: ItineraryResponse | None = None
    note = ""
    try:
        itinerary = ItineraryResponse(**ttdp.solve(it_req))
    except ValueError as exc:
        note = str(exc)
        log.info("依意圖排程失敗：%s", exc)

    return PlanFromTextResponse(
        source=source,
        model=llm_service.model_name() if source == "llm" else "",
        intent=intent,
        resolved_start=start,
        itinerary=itinerary,
        note=note,
    )
