"""Phase 2：多景點行程規劃 API。"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException

from ..optimize import ttdp
from ..schemas import ItineraryRequest, ItineraryResponse

log = logging.getLogger(__name__)

router = APIRouter(tags=["itinerary"])


@router.post("/itinerary", response_model=ItineraryResponse, summary="多景點行程規劃（TTDP / OPTW）")
def plan_itinerary(req: ItineraryRequest) -> ItineraryResponse:
    try:
        result = ttdp.solve(req)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return ItineraryResponse(**result)
