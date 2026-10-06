"""全域設定。可用 .env（前綴 STN_）覆寫。"""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/ 目錄
BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BASE_DIR / ".env",
        env_prefix="STN_",
        extra="ignore",
    )

    app_name: str = "Adaptive Smart Tourism Navigation API"
    api_prefix: str = "/api/v1"

    # 澳門 bounding box：(left=西, bottom=南, right=東, top=北)，EPSG:4326
    bbox_w: float = 113.528
    bbox_s: float = 22.105
    bbox_e: float = 113.600
    bbox_n: float = 22.225

    network_type: str = "walk"

    data_dir: Path = BASE_DIR / "data" / "raw"
    cache_dir: Path = BASE_DIR / "data" / "cache"
    graph_filename: str = "macau_walk.graphml"
    dem_filename: str = "dem/macau_dem_smooth.tif"   # SRTM 30m 平滑後（Phase 4）

    # 一般成人步行速度（公尺/秒）
    walking_speed_mps: float = 1.35

    cors_origins: list[str] = ["*"]

    # ---- LLM 意圖解析（Phase 5；任何 OpenAI 相容 API）----
    llm_base_url: str | None = None
    llm_api_key: str | None = None
    llm_model: str = "qwen-plus"

    # ---- 天氣（Phase 6；Open-Meteo，免金鑰）----
    weather_lat: float = 22.1987
    weather_lon: float = 113.5439

    @property
    def bbox(self) -> tuple[float, float, float, float]:
        """OSMnx graph_from_bbox 需要的 (left, bottom, right, top)。"""
        return (self.bbox_w, self.bbox_s, self.bbox_e, self.bbox_n)

    @property
    def graph_path(self) -> Path:
        return self.cache_dir / self.graph_filename

    @property
    def dem_path(self) -> Path:
        return self.data_dir / self.dem_filename


settings = Settings()
