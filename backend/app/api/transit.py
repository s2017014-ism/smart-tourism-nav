"""Phase 3：走 + 公車多模態路線 API。"""

from __future__ import annotations

import logging

import networkx as nx
from fastapi import APIRouter, HTTPException

from ..graph import multimodal
from ..schemas import TransitRequest, TransitResponse

log = logging.getLogger(__name__)

router = APIRouter(tags=["transit"])


@router.post("/transit-route", response_model=TransitResponse, summary="走 + 公車多模態路線規劃")
def transit_route(req: TransitRequest) -> TransitResponse:
    try:
        result = multimodal.plan(
            req.origin, req.destination, req.preferences, req.departure_time, req.max_transfers
        )
    except nx.NetworkXNoPath as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return TransitResponse(**result)
