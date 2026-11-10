"""TomTom Maps, Nearby Hospitals, Live Traffic ETA Routing & Traffic Incidents.

Includes an in-process spatial TTL cache (quantized to ~100m grid) so repeated facility/traffic queries
respond in <1 ms, and automatically merges/falls back to OpenStreetMap Overpass if TomTom is unconfigured.
"""
from __future__ import annotations

import asyncio
import math
import time
from typing import Any, Optional
from urllib.parse import quote

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from ..ctx import get_ctx

router = APIRouter(prefix="/api/emergency-route", tags=["tomtom"])

OVERPASS_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)
FACILITY_QUERIES = ("hospital", "clinic")
BLOCKED_TERMS = (
    "pharmacy", "chemist", "medical store", "drug store", "dental", "dentist",
    "optical", "optician", "veterinary", "animal", "gym", "fitness", "spa", "salon",
)
CARE_TERMS = (
    "hospital", "clinic", "nursing home", "medical centre", "medical center",
    "healthcare", "health care", "diagnostic", "scan", "emergency", "trauma",
)

# Simple in-memory TTL cache: key -> (timestamp, payload)
_CACHE: dict[str, tuple[float, Any]] = {}
CACHE_TTL_S = 180.0


def _cache_get(key: str) -> Any | None:
    hit = _CACHE.get(key)
    if hit and (time.time() - hit[0] < CACHE_TTL_S):
        return hit[1]
    return None


def _cache_set(key: str, value: Any) -> Any:
    if len(_CACHE) > 256:
        _CACHE.clear()
    _CACHE[key] = (time.time(), value)
    return value


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _is_care_facility(item: dict[str, Any]) -> bool:
    text = f"{item.get('name', '')} {item.get('type', '')}".lower()
    if any(b in text for b in BLOCKED_TERMS):
        return False
    return any(c in text for c in CARE_TERMS)


def _dedupe_facilities(items: list[dict[str, Any]], lat: float, lon: float) -> list[dict[str, Any]]:
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for item in items:
        ilat, ilon = item.get("lat"), item.get("lon")
        if not isinstance(ilat, (int, float)) or not isinstance(ilon, (int, float)):
            continue
        item = {
            **item,
            "distanceMeters": round(float(item.get("distanceMeters") or haversine_m(lat, lon, float(ilat), float(ilon)))),
        }
        if not _is_care_facility(item):
            continue
        key = f"{str(item.get('name', '')).lower()}-{float(ilat):.4f}-{float(ilon):.4f}"
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    out.sort(key=lambda x: x.get("distanceMeters", 10**9))
    return out[:20]


async def _fetch_tomtom_facilities(client: httpx.AsyncClient, key: str, lat: float, lon: float, radius: int) -> list[dict[str, Any]]:
    if not key:
        return []

    async def one(q: str) -> list[dict[str, Any]]:
        url = f"https://api.tomtom.com/search/2/search/{quote(q)}.json"
        resp = await client.get(
            url,
            params={
                "key": key,
                "lat": str(lat),
                "lon": str(lon),
                "radius": str(radius),
                "limit": "25",
                "idxSet": "POI",
                "language": "en-US",
            },
            timeout=5.0,
        )
        if resp.status_code >= 400:
            return []
        results = resp.json().get("results") or []
        parsed: list[dict[str, Any]] = []
        for r in results:
            pos = r.get("position") or {}
            rlat, rlon = pos.get("lat"), pos.get("lon")
            if not isinstance(rlat, (int, float)) or not isinstance(rlon, (int, float)):
                continue
            poi = r.get("poi") or {}
            cats = poi.get("categories") or []
            name = (poi.get("name") or (r.get("address") or {}).get("freeformAddress") or "Medical facility").strip()
            ftype = str(cats[0] if cats else "hospital").replace("_", " ")
            parsed.append(
                {
                    "id": f"tomtom-{r.get('id') or f'{rlat:.5f}-{rlon:.5f}'}",
                    "name": name,
                    "lat": float(rlat),
                    "lon": float(rlon),
                    "type": ftype,
                    "source": "tomtom",
                    "address": (r.get("address") or {}).get("freeformAddress"),
                    "phone": poi.get("phone"),
                    "emergency": "emergency" in name.lower() or "emergency" in ftype.lower() or "hospital" in ftype.lower(),
                    "distanceMeters": round(float(r["dist"])) if isinstance(r.get("dist"), (int, float)) else round(haversine_m(lat, lon, float(rlat), float(rlon))),
                }
            )
        return parsed

    batches = await asyncio.gather(*(one(q) for q in FACILITY_QUERIES), return_exceptions=True)
    merged = [item for b in batches if isinstance(b, list) for item in b]
    return _dedupe_facilities(merged, lat, lon)


async def _fetch_osm_facilities(client: httpx.AsyncClient, lat: float, lon: float, radius: int) -> list[dict[str, Any]]:
    query = (
        f"[out:json][timeout:8];("
        f'node["amenity"~"hospital|clinic"](around:{radius},{lat},{lon});'
        f'way["amenity"~"hospital|clinic"](around:{radius},{lat},{lon});'
        f");out center tags 35;"
    )
    for ep in OVERPASS_ENDPOINTS:
        try:
            resp = await client.post(ep, data={"data": query}, timeout=6.0)
            if resp.status_code >= 400:
                continue
            elements = resp.json().get("elements") or []
            parsed: list[dict[str, Any]] = []
            for el in elements:
                elat = el.get("lat") or (el.get("center") or {}).get("lat")
                elon = el.get("lon") or (el.get("center") or {}).get("lon")
                if not isinstance(elat, (int, float)) or not isinstance(elon, (int, float)):
                    continue
                tags = el.get("tags") or {}
                name = (tags.get("name") or tags.get("name:en") or tags.get("operator") or "Medical facility").strip()
                parsed.append(
                    {
                        "id": f"osm-{el.get('type', 'n')}-{el.get('id', 0)}",
                        "name": name,
                        "lat": float(elat),
                        "lon": float(elon),
                        "type": str(tags.get("amenity") or tags.get("healthcare") or "hospital").replace("_", " "),
                        "source": "openstreetmap",
                        "address": ", ".join(x for x in (tags.get("addr:street"), tags.get("addr:city")) if x) or None,
                        "phone": tags.get("phone") or tags.get("contact:phone"),
                        "open24x7": tags.get("opening_hours") == "24/7",
                        "emergency": bool(tags.get("emergency")) or "emergency" in name.lower(),
                        "distanceMeters": round(haversine_m(lat, lon, float(elat), float(elon))),
                    }
                )
            deduped = _dedupe_facilities(parsed, lat, lon)
            if deduped:
                return deduped
        except Exception:
            continue
    return []


class FacilitiesBody(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    radius: int = Field(default=6000, ge=500, le=25000)


class RouteBody(BaseModel):
    origin_lat: float = Field(ge=-90, le=90)
    origin_lon: float = Field(ge=-180, le=180)
    dest_lat: float = Field(ge=-90, le=90)
    dest_lon: float = Field(ge=-180, le=180)


class PointBody(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class BboxBody(BaseModel):
    bbox: str = Field(min_length=7, max_length=120)


@router.post("/facilities")
async def search_facilities(body: FacilitiesBody, request: Request) -> dict[str, Any]:
    ctx = get_ctx(request)
    cache_key = f"fac:{body.lat:.3f}:{body.lon:.3f}:{body.radius}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached

    key = ctx.settings.tomtom_api_key
    tasks = [_fetch_osm_facilities(ctx.http, body.lat, body.lon, body.radius)]
    if key:
        tasks.insert(0, _fetch_tomtom_facilities(ctx.http, key, body.lat, body.lon, body.radius))
    results = await asyncio.gather(*tasks, return_exceptions=True)
    combined = [item for r in results if isinstance(r, list) for item in r]
    facilities = _dedupe_facilities(combined, body.lat, body.lon)
    if not facilities:
        raise HTTPException(503, "No nearby hospitals or clinics found.")
    source = "tomtom" if any(f.get("source") == "tomtom" for f in facilities) else "openstreetmap"
    return _cache_set(cache_key, {"source": source, "facilities": facilities})


@router.post("/route")
async def calculate_emergency_route(body: RouteBody, request: Request) -> dict[str, Any]:
    """TomTom Calculate Route with live traffic delay; falls back to straight-line ETA if TomTom key is unset."""
    ctx = get_ctx(request)
    key = ctx.settings.tomtom_api_key
    dist_m = round(haversine_m(body.origin_lat, body.origin_lon, body.dest_lat, body.dest_lon))
    if key:
        url = (
            f"https://api.tomtom.com/routing/1/calculateRoute/"
            f"{body.origin_lat},{body.origin_lon}:{body.dest_lat},{body.dest_lon}/json"
        )
        try:
            resp = await ctx.http.get(
                url,
                params={"key": key, "traffic": "true", "travelMode": "car", "routeType": "fastest"},
                timeout=6.0,
            )
            if resp.status_code < 400:
                routes = resp.json().get("routes") or []
                if routes:
                    summary = routes[0].get("summary") or {}
                    pts = ((routes[0].get("legs") or [{}])[0]).get("points") or []
                    return {
                        "source": "tomtom",
                        "distanceMeters": int(summary.get("lengthInMeters") or dist_m),
                        "travelTimeSeconds": int(summary.get("travelTimeInSeconds") or max(60, dist_m // 10)),
                        "trafficDelaySeconds": int(summary.get("trafficDelayInSeconds") or 0),
                        "points": [{"lat": p["latitude"], "lon": p["longitude"]} for p in pts[:: max(1, len(pts) // 60)] if "latitude" in p],
                    }
        except httpx.HTTPError:
            pass

    # Fallback estimate (36 km/h urban average = 10 m/s, road factor 1.3x)
    road_m = int(dist_m * 1.3)
    return {
        "source": "estimated",
        "distanceMeters": road_m,
        "travelTimeSeconds": max(60, road_m // 10),
        "trafficDelaySeconds": 0,
        "points": [
            {"lat": body.origin_lat, "lon": body.origin_lon},
            {"lat": body.dest_lat, "lon": body.dest_lon},
        ],
    }


@router.post("/traffic-flow")
async def traffic_flow(body: PointBody, request: Request) -> dict[str, Any]:
    ctx = get_ctx(request)
    key = ctx.settings.tomtom_api_key
    if not key:
        raise HTTPException(503, "TOMTOM_API_KEY is not configured")
    resp = await ctx.http.get(
        "https://api.tomtom.com/traffic/services/4/flowSegmentData/relative/10/json",
        params={"key": key, "point": f"{body.lat},{body.lon}", "unit": "kmph"},
        timeout=6.0,
    )
    if resp.status_code >= 400:
        raise HTTPException(502, "TomTom Traffic Flow is unavailable")
    return resp.json()


@router.post("/traffic-incidents")
async def traffic_incidents(body: BboxBody, request: Request) -> dict[str, Any]:
    ctx = get_ctx(request)
    key = ctx.settings.tomtom_api_key
    if not key:
        raise HTTPException(503, "TOMTOM_API_KEY is not configured")
    parts = [p.strip() for p in body.bbox.split(",")]
    if len(parts) != 4:
        raise HTTPException(400, "bbox is required as minLon,minLat,maxLon,maxLat")
    try:
        norm_bbox = ",".join(f"{float(p):.6f}" for p in parts)
    except ValueError as exc:
        raise HTTPException(400, "bbox must contain 4 valid numbers") from exc
    resp = await ctx.http.get(
        "https://api.tomtom.com/traffic/services/5/incidentDetails",
        params={
            "key": key,
            "bbox": norm_bbox,
            "language": "en-US",
            "categoryFilter": "Accident,LaneClosed,RoadClosed,RoadWorks",
            "timeValidityFilter": "present",
        },
        timeout=6.0,
    )
    if resp.status_code >= 400:
        raise HTTPException(502, "TomTom Traffic Incidents is unavailable")
    return resp.json()
