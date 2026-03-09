"""Router de sistema: health check, estado de servicios Docker, segmento de ruta GPS."""

import requests
from fastapi import APIRouter, Request

from app.core.config import OSRM_BASE_URL, OSRM_TIMEOUT
from app.core.logging import get_logger

router = APIRouter()
logger = get_logger(__name__)


@router.get("/health", tags=["system"])
async def health(request: Request):
    """Estado del servidor."""
    return {"status": "ok", "version": request.app.version}


@router.get("/api/services/status", tags=["system"])
async def services_status():
    """Estado del servicio OSRM."""
    osrm_ok = False

    try:
        r = requests.get(
            f"{OSRM_BASE_URL}/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false",
            timeout=5,
        )
        osrm_ok = r.status_code == 200
    except Exception:
        pass

    return {
        "osrm": {"url": OSRM_BASE_URL, "status": "ok" if osrm_ok else "down"},
        "all_ok": osrm_ok,
    }


@router.get("/api/route-segment", tags=["routing"])
async def route_segment(
    origin_lat: float,
    origin_lon: float,
    dest_lat: float,
    dest_lon: float,
):
    """Geometría GeoJSON del camino entre dos puntos (OSRM).

    Usado por la app en modo reparto para dibujar el tramo GPS → siguiente parada.
    """
    coords_str = f"{origin_lon},{origin_lat};{dest_lon},{dest_lat}"
    url = f"{OSRM_BASE_URL}/route/v1/driving/{coords_str}"

    try:
        r = requests.get(
            url,
            params={"overview": "full", "geometries": "geojson"},
            timeout=OSRM_TIMEOUT,
        )
        r.raise_for_status()
        data = r.json()
        if data.get("code") != "Ok" or not data.get("routes"):
            return {"geometry": None, "distance_m": 0}
        route = data["routes"][0]
        return {
            "geometry": route["geometry"],
            "distance_m": round(route.get("distance", 0)),
        }
    except Exception as e:
        return {"geometry": None, "distance_m": 0, "error": str(e)}
