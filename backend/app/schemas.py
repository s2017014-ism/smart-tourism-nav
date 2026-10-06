"""API 請求解與回應的資料模型（Pydantic v2）。"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class LatLng(BaseModel):
    lat: float = Field(..., ge=-90, le=90, description="緯度")
    lng: float = Field(..., ge=-180, le=180, description="經度")


class RoutePreferences(BaseModel):
    """使用者對路線的偏好。Phase 1 只用得到 avoid_stairs 與步行速度。"""

    avoid_stairs: bool = Field(False, description="避開階梯（推嬰兒車／帶大件行李）")
    max_slope_pct: float | None = Field(
        None, description="可接受最大坡度（%）。超過則封鎖該路段，需 DEM 資料（Phase 4）"
    )
    pace: Literal["relaxed", "normal", "packed"] = "normal"
    walking_speed_mps: float | None = Field(
        None, gt=0, le=5, description="覆寫步行速度；未指定則用系統預設"
    )


class RouteRequest(BaseModel):
    origin: LatLng
    destination: LatLng
    preferences: RoutePreferences = Field(default_factory=RoutePreferences)


class RouteStep(BaseModel):
    instruction: str
    distance_m: float
    duration_s: float


class RouteResponse(BaseModel):
    distance_m: float
    duration_s: float
    geometry: dict = Field(..., description="GeoJSON LineString")
    nodes: int
    origin_snapped: LatLng
    destination_snapped: LatLng
    steps: list[RouteStep] = Field(default_factory=list)


# ------------------------------------------------------------------
#  Phase 5：LLM 意圖解析的輸出結構（先定義好，方便前端與 API 對接）
# ------------------------------------------------------------------
class Intent(BaseModel):
    """把使用者的一句自然語言，轉譯成結構化的路徑約束。"""

    geographic_tags: list[str] = Field(default_factory=list, description="地理／主題標籤，如 地質、岩石、歷史")
    interests: list[str] = Field(default_factory=list)
    max_slope_pct: float | None = None
    max_walk_meters: int | None = None
    avoid_stairs: bool = False
    duration_hours: float | None = None
    pace: Literal["relaxed", "normal", "packed"] = "normal"
    must_visit: list[str] = Field(default_factory=list)
    time_of_day: Literal["morning", "afternoon", "evening"] | None = None


# ------------------------------------------------------------------
#  Phase 2：多景點行程排序（TTDP / OPTW）
# ------------------------------------------------------------------
class ItineraryRequest(BaseModel):
    start: LatLng
    end: LatLng | None = Field(None, description="終點；未提供且非 round_trip 時為開放式行程")
    round_trip: bool = Field(False, description="是否回到起點")
    departure_time: str = Field("09:00", description="出發時間 HH:MM")
    duration_hours: float = Field(8.0, gt=0, le=24, description="可用總時數")
    categories: list[str] = Field(
        default_factory=lambda: ["tourism", "historic", "natural", "leisure", "curated"],
        description="候選景點類別；可加入 food（美食）",
    )
    must_visit: list[str] = Field(default_factory=list, description="必訪景點名稱關鍵字")
    max_candidates: int = Field(30, ge=2, le=80, description="候選景點上限（影響運算時間）")
    radius_m: float = Field(4000, gt=0, description="候選景點距起點的最大距離（公尺）")
    min_spacing_m: float = Field(
        120, gt=0, description="候選景點彼此最小間距（公尺），避免行程過度集中在同一區"
    )
    dwell_minutes: int = Field(30, ge=0, le=240, description="預設每站停留分鐘數")
    max_food_stops: int = Field(
        2, ge=0, le=20, description="美食站數上限（美食點密集，不限制會塞滿行程）"
    )
    preferences: RoutePreferences = Field(default_factory=RoutePreferences)


class ItineraryStop(BaseModel):
    order: int
    name: str
    category: str
    category_label: str
    lat: float
    lng: float
    arrival: str
    departure: str
    dwell_min: int
    travel_from_prev_m: float
    travel_from_prev_s: float


class ItineraryResponse(BaseModel):
    stops: list[ItineraryStop]
    num_visited: int
    total_distance_m: float
    total_duration_min: float
    geometry: dict = Field(..., description="GeoJSON LineString（串接所有路段）")
    skipped: list[str] = Field(default_factory=list, description="未被排入的候選景點")


# ------------------------------------------------------------------
#  Phase 3：走 + 公車多模態路線
# ------------------------------------------------------------------
class TransitRequest(RouteRequest):
    departure_time: str | None = Field(
        None, description="出發時間 HH:MM（決定哪些路線營運）；未提供時用伺服器目前時間"
    )
    max_transfers: int = Field(3, ge=0, le=10, description="最多轉乘次數")


class TransitLeg(BaseModel):
    mode: Literal["walk", "bus"]
    route: str | None = None
    from_name: str | None = None
    to_name: str | None = None
    num_stops: int = 0
    stops: list[str] = Field(default_factory=list)
    stop_coords: list[list[float]] = Field(default_factory=list, description="各站座標 [lng,lat]")
    distance_m: float
    duration_s: float
    geometry: dict


class TransitResponse(BaseModel):
    mode: Literal["walk", "bus", "mixed"]
    total_distance_m: float
    total_duration_s: float
    num_transfers: int
    departure_time: str = Field("", description="本路線採用的出發時間 HH:MM")
    legs: list[TransitLeg]
    geometry: dict = Field(..., description="GeoJSON LineString（整條路線）")


# ------------------------------------------------------------------
#  Phase 5：LLM 意圖解析
# ------------------------------------------------------------------
CategoryKey = Literal[
    "tourism", "historic", "natural", "leisure",
    "amenity", "place", "man_made", "curated", "food",
]
CATEGORY_KEYS: list[str] = [
    "tourism", "historic", "natural", "leisure",
    "amenity", "place", "man_made", "curated", "food",
]


class TripIntent(BaseModel):
    """把一句自然語言轉成行程條件。"""

    categories: list[CategoryKey] = Field(default_factory=list, description="想包含的景點類別")
    must_visit: list[str] = Field(default_factory=list, description="必訪景點名稱")
    avoid_stairs: bool = Field(False, description="是否避開階梯")
    avoid_steep: bool = Field(False, description="是否避開陡坡／不想走太累")
    duration_hours: float | None = Field(None, description="可用時數")
    departure_time: str | None = Field(None, description="出發時間 HH:MM")
    max_food_stops: int | None = Field(None, description="美食站數上限")
    start_name: str | None = Field(None, description="起點名稱（若使用者有提到）")
    summary: str = Field("", description="一句話覆述使用者需求")


class PlanFromTextRequest(BaseModel):
    text: str = Field(..., min_length=1, description="使用者的自然語言需求")
    start: LatLng | None = Field(None, description="明確的起點；未提供時用 start_name 或預設點")


class PlanFromTextResponse(BaseModel):
    source: Literal["llm", "rules"] = Field(..., description="解析方式")
    model: str = Field("", description="實際使用的模型（若為 LLM）")
    intent: TripIntent
    resolved_start: LatLng
    itinerary: ItineraryResponse | None = None
    note: str = ""
