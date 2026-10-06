"""路線規劃 API。"""

from __future__ import annotations

import logging

import networkx as nx
from fastapi import APIRouter, HTTPException

from ..graph.loader import get_graph
from ..optimize import pathfinding
from ..schemas import RouteRequest, RouteResponse

log = logging.getLogger(__name__)

router = APIRouter(tags=["route"])


@router.post("/route", response_model=RouteResponse, summary="點對點步行路線規劃")
def plan_route(req: RouteRequest) -> RouteResponse:
    G = get_graph()

    try:
        result = pathfinding.plan(G, req.origin, req.destination, req.preferences)
    except nx.NetworkXNoPath as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except nx.NodeNotFound as exc:
        raise HTTPException(status_code=400, detail=f"找不到對應節點：{exc}") from exc

    return RouteResponse(**result)
