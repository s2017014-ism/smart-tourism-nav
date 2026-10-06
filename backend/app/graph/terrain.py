"""Phase 4：微觀地形與階梯避讓。

OSMnx 已內建相關工具，實際落地比想像中簡單：
  * 階梯：OSM 標籤 highway=steps（loader 已標成 edge['is_stairs']）。
  * 坡度：
        1) 取得 DEM 高程柵格（SRTM 30m / ALOS World 3D），
        2) ox.elevation.add_node_elevations_raster(G, dem_path)
        3) ox.elevation.add_edge_grades(G)   # 產生 edge['grade'] 與 ['grade_abs']
        4) 把 grade_abs 交給 pathfinding._edge_cost 判斷是否超過 max_slope_pct。

注意：add_node_elevations_raster 需要 rasterio，且圖與柵格 CRS 要一致。
"""

from __future__ import annotations

import networkx as nx


def add_elevation(G: nx.MultiDiGraph, dem_path: str) -> nx.MultiDiGraph:
    """從本地 DEM 柵格加入節點高程與邊坡度。"""
    # import osmnx as ox
    # ox.elevation.add_node_elevations_raster(G, dem_path)
    # ox.elevation.add_edge_grades(G)
    raise NotImplementedError("Phase 4：DEM 坡度尚未實作")
