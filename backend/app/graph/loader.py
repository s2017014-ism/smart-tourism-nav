"""路網下載、快取與預處理。

設計重點：
  * 啟動時只載入一次，常駐記憶體（OSMnx 圖載入很慢，不要每次請求重讀）。
  * 下載後存成 GraphML 快取，之後離線也能跑。
"""

from __future__ import annotations

import logging
import threading

import networkx as nx
import osmnx as ox

from ..config import settings

log = logging.getLogger(__name__)

_graph: nx.MultiDiGraph | None = None
_lock = threading.Lock()


def _is_stairs(data: dict) -> bool:
    hw = data.get("highway")
    if isinstance(hw, (list, tuple)):
        return "steps" in hw
    return hw == "steps"


def _decorate(G: nx.MultiDiGraph) -> bool:
    """加上步行時間與階梯標記；若尚無高程且 DEM 存在，則加入高程與坡度。

    回傳是否有「新增高程」，供呼叫端決定是否回存快取。
    """
    speed = settings.walking_speed_mps
    for _, _, _, data in G.edges(keys=True, data=True):
        try:
            length = float(data.get("length", 0.0))
        except (TypeError, ValueError):
            length = 0.0
        data["walk_time_s"] = length / speed if speed > 0 else length
        data["is_stairs"] = _is_stairs(data)

    added = False
    if settings.dem_path.exists():
        marker = settings.cache_dir / "dem_used.txt"
        current = settings.dem_filename
        used = marker.read_text(encoding="utf-8").strip() if marker.exists() else None
        if used != current:      # DEM 更換或尚未套用 → 重新計算高程與坡度
            try:
                for _, d in G.nodes(data=True):
                    d.pop("elevation", None)
                for _, _, _, d in G.edges(keys=True, data=True):
                    d.pop("grade", None)
                    d.pop("grade_abs", None)
                # cpus=1：Windows 上 multiprocessing 會重新匯入 __main__ 造成遞迴卡死
                ox.elevation.add_node_elevations_raster(G, str(settings.dem_path), cpus=1)
                ox.elevation.add_edge_grades(G)
                settings.cache_dir.mkdir(parents=True, exist_ok=True)
                marker.write_text(current, encoding="utf-8")
                added = True
                log.info("已由 DEM 加入高程與坡度：%s", current)
            except Exception as exc:  # noqa: BLE001
                log.warning("加入高程失敗（將略過坡度功能）：%s", exc)
    return added


def _download() -> nx.MultiDiGraph:
    log.info("下載 OSM %s 路網 bbox=%s ...", settings.network_type, settings.bbox)
    G = ox.graph_from_bbox(settings.bbox, network_type=settings.network_type)
    log.info("下載完成：%d 節點 / %d 邊", G.number_of_nodes(), G.number_of_edges())
    _decorate(G)
    return G


def get_graph(force: bool = False) -> nx.MultiDiGraph:
    """取得（並快取）澳門路網。執行緒安全。"""
    global _graph

    if _graph is not None and not force:
        return _graph

    with _lock:
        if _graph is not None and not force:
            return _graph

        path = settings.graph_path
        if path.exists() and not force:
            log.info("載入快取路網：%s", path)
            G = ox.load_graphml(path)
            if _decorate(G):        # 快取缺高程 → 補上後回存，之後就不必再算
                ox.save_graphml(G, path)
                log.info("已更新快取（加入高程與坡度）：%s", path)
        else:
            G = _download()
            path.parent.mkdir(parents=True, exist_ok=True)
            ox.save_graphml(G, path)
            log.info("已寫入快取：%s", path)

        _graph = G
        return _graph


def graph_info() -> dict:
    G = get_graph()
    return {
        "nodes": G.number_of_nodes(),
        "edges": G.number_of_edges(),
        "bbox": settings.bbox,
        "network_type": settings.network_type,
    }
