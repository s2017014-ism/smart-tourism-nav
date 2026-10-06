"""Phase 5：LLM 意圖解析。

優先使用線上 LLM（OpenAI 相容 API 的 Function Calling）把自然語言轉成
`TripIntent`；若未設定金鑰或呼叫失敗，退回「規則式」解析，確保離線也能 demo。
"""

from __future__ import annotations

import logging
import re

import httpx

from ..config import settings
from ..schemas import LatLng, TripIntent
from . import poi as poi_service

log = logging.getLogger(__name__)

DEFAULT_START = LatLng(lat=22.19356, lng=113.53963)  # 議事亭前地

SYSTEM_PROMPT = (
    "你是澳門旅遊行程助理。把使用者的一句話轉成結構化行程條件，並以 JSON 物件輸出。"
    "欄位：categories（只能從 tourism/historic/natural/leisure/amenity/place/man_made/curated/food 挑）、"
    "must_visit、avoid_stairs（布林）、avoid_steep（布林）、duration_hours（數字或 null）、"
    "departure_time（HH:MM 或 null）、max_food_stops（整數或 null）、start_name（或 null）、summary（一句話）。"
    "若使用者表示『不想走太累／輕鬆／長者』→ avoid_steep=true；"
    "提到『嬰兒車／輪椅／行李／樓梯』→ avoid_stairs=true。只輸出 JSON，不要多餘文字。"
)

# ---- 規則式備援用的關鍵詞 ----
_CAT_KEYWORDS: dict[str, list[str]] = {
    "historic": ["歷史", "古蹟", "遺產", "文化", "古廟", "教堂", "廟", "世遺", "文物"],
    "natural": ["自然", "地質", "岩石", "山", "海", "沙灘", "生態", "行山", "郊野", "水庫", "濕地"],
    "tourism": ["觀光", "景點", "博物館", "名勝", "遊覽", "打卡", "展館", "藝術"],
    "leisure": ["公園", "花園", "休閒", "野餐", "草地"],
    "food": ["美食", "吃", "餐廳", "小食", "甜品", "咖啡", "茶餐廳", "餅", "粥", "麵", "蛋撻"],
    "curated": ["必去", "必訪", "著名", "地標"],
    "man_made": ["燈塔", "瞭望台", "眺望台"],
    "place": ["廣場", "前地"],
    "amenity": ["寺", "廟", "教堂"],
}
_STEEP_KW = ["不想走太累", "不想太累", "不想走", "輕鬆", "長者", "老人", "少走", "平坦", "緩", "不想爬", "不爬"]
_STAIRS_KW = ["嬰兒車", "輪椅", "行李", "大件", "階梯", "樓梯", "bb車", "手推車"]


def llm_configured() -> bool:
    return bool(settings.llm_base_url and settings.llm_api_key)


def model_name() -> str:
    return settings.llm_model


def status() -> dict:
    """回報 LLM 設定狀態，方便除錯。"""
    configured = llm_configured()
    return {
        "configured": configured,
        "model": settings.llm_model if configured else None,
        "base_url_set": bool(settings.llm_base_url),
        "api_key_set": bool(settings.llm_api_key),
        "hint": ""
        if configured
        else "請在 backend/.env 設定 STN_LLM_BASE_URL 與 STN_LLM_API_KEY（行首不能有 #），存檔後需重新啟動後端。",
    }


def _post_chat(messages: list[dict], *, tools=None, tool_choice=None, temperature: float = 0.2) -> dict:
    url = settings.llm_base_url.rstrip("/") + "/chat/completions"
    body: dict = {"model": settings.llm_model, "messages": messages, "temperature": temperature}
    if tools:
        body["tools"] = tools
        body["tool_choice"] = tool_choice
    headers = {
        "Authorization": f"Bearer {settings.llm_api_key}",
        "Content-Type": "application/json",
    }
    resp = httpx.post(url, json=body, headers=headers, timeout=60)
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]


def _extract_json(text: str | None) -> str | None:
    """從模型回覆中擷取 JSON 物件（容忍 ```json 圍欄與前後文字）。"""
    if not text:
        return None
    t = text.strip()
    if t.startswith("```"):
        t = t.strip("`")
        if t[:4].lower() == "json":
            t = t[4:]
    i, j = t.find("{"), t.rfind("}")
    return t[i : j + 1] if 0 <= i < j else None


def _call_llm(text: str) -> TripIntent:
    """呼叫 OpenAI 相容 API。先試 Function Calling，失敗則退回純 JSON 輸出。"""
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": text}]

    # 1) 首選：Function Calling（結構最穩）
    try:
        msg = _post_chat(
            messages,
            tools=[{
                "type": "function",
                "function": {
                    "name": "set_trip_intent",
                    "description": "設定此趟澳門行程的條件",
                    "parameters": TripIntent.model_json_schema(),
                },
            }],
            tool_choice={"type": "function", "function": {"name": "set_trip_intent"}},
        )
        tool_calls = msg.get("tool_calls")
        if tool_calls:
            return TripIntent.model_validate_json(tool_calls[0]["function"]["arguments"])
        raw = _extract_json(msg.get("content"))  # 有些供應商把 JSON 放在 content
        if raw:
            return TripIntent.model_validate_json(raw)
    except Exception as exc:  # noqa: BLE001
        log.warning("Function Calling 失敗，改用純 JSON 提示：%s", exc)

    # 2) 備援：不支援 tools 的供應商 → 要求輸出 JSON
    msg = _post_chat(messages, temperature=0)
    raw = _extract_json(msg.get("content"))
    if not raw:
        raise ValueError("LLM 未回傳可解析的 JSON")
    return TripIntent.model_validate_json(raw)


def _poi_names() -> list[tuple[str, float, float]]:
    out = []
    for f in poi_service.all_features():
        p = f["properties"]
        zh = p.get("name_zh") or p.get("name") or ""
        if zh:
            out.append((str(zh), float(p["lat"]), float(p["lng"])))
    return out


def _rule_based(text: str) -> TripIntent:
    cats = [k for k, kws in _CAT_KEYWORDS.items() if any(w in text for w in kws)]

    avoid_steep = any(w in text for w in _STEEP_KW)
    avoid_stairs = any(w in text for w in _STAIRS_KW) or avoid_steep

    duration = None
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:個)?\s*小時", text)
    if m:
        duration = float(m.group(1))
    elif "半天" in text:
        duration = 4.0
    elif any(w in text for w in ["一天", "整天", "全日", "一整天"]):
        duration = 8.0

    # 必訪：比對 POI 中文名稱（全名優先；前 3 字命中時每個詞只取名稱最短者）
    matched: dict[str, str] = {}
    for zh, _lat, _lng in _poi_names():
        if len(zh) >= 2 and zh in text:
            matched.setdefault(zh, zh)
        elif len(zh) >= 3 and zh[:3] in text:
            key = zh[:3]
            if key not in matched or len(zh) < len(matched[key]):
                matched[key] = zh
    must = list(matched.values())[:5]

    # 起點：從「從 X 出發 / 由 X 開始」
    start_name = None
    m = re.search(r"(?:從|由|在)\s*([\u4e00-\u9fffA-Za-z0-9]{2,10}?)\s*(?:出發|開始|集合|前往)", text)
    if m:
        start_name = m.group(1)

    parts = []
    if cats:
        parts.append("類別：" + "、".join(cats))
    if duration:
        parts.append(f"約 {duration:g} 小時")
    if avoid_stairs:
        parts.append("避開階梯")
    if avoid_steep:
        parts.append("避開陡坡")
    summary = "、".join(parts) or "一般觀光行程"

    return TripIntent(
        categories=cats,
        must_visit=must,
        avoid_stairs=avoid_stairs,
        avoid_steep=avoid_steep,
        duration_hours=duration,
        departure_time=None,
        max_food_stops=2 if "food" in cats else None,
        start_name=start_name,
        summary=summary,
    )


def parse(text: str) -> tuple[TripIntent, str]:
    """回傳 (intent, source)，source 為 'llm' 或 'rules'。"""
    if llm_configured():
        try:
            return _call_llm(text), "llm"
        except Exception as exc:  # noqa: BLE001
            log.warning("LLM 解析失敗，改用規則式：%s", exc)
    return _rule_based(text), "rules"


def find_poi(name: str | None) -> tuple[float, float] | None:
    if not name:
        return None
    best = None
    for zh, lat, lng in _poi_names():
        if name in zh or zh in name:
            # 偏好名稱較接近者
            if best is None or abs(len(zh) - len(name)) < abs(len(best[2]) - len(name)):
                best = (lat, lng, zh)
    return (best[0], best[1]) if best else None


def resolve_start(intent: TripIntent, explicit: LatLng | None) -> LatLng:
    if explicit is not None:
        return explicit
    hit = find_poi(intent.start_name)
    if hit:
        return LatLng(lat=hit[0], lng=hit[1])
    return DEFAULT_START
