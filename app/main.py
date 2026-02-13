"""
Posadas Route Planner — Backend FastAPI v2.2
=============================================
API REST profesional para optimización de rutas de reparto.

Arquitectura:
  • core/config.py    → Configuración centralizada
  • models/           → Modelos Pydantic (request/response)
  • services/         → Lógica de negocio (geocoding, routing, stop_geocoder)
  • routers/          → Endpoints de la API

Servicios Docker requeridos:
  • OSRM  → localhost:5000  (motor de rutas)
  • VROOM → localhost:3000  (optimizador TSP/VRP)
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import BASE_DIR
from app.routers import optimize, validation

# ── App ───────────────────────────────────────────────────────
app = FastAPI(
    title="Posadas Route Planner",
    description="API de optimización de rutas de reparto para Posadas (Córdoba)",
    version="2.3.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ── CORS (permitir acceso desde cualquier frontend/app móvil) ─
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Archivos estáticos ────────────────────────────────────────
STATIC_DIR = BASE_DIR / "static"
STATIC_DIR.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

# ── Routers ───────────────────────────────────────────────────
app.include_router(optimize.router, prefix="/api")
app.include_router(validation.router, prefix="/api")


# ── Health check ──────────────────────────────────────────────
@app.get("/health", tags=["system"])
async def health():
    """Verifica que el servidor está vivo."""
    return {"status": "ok", "version": app.version}


@app.get("/api/services/status", tags=["system"])
async def services_status():
    """Verifica el estado de los servicios Docker (OSRM + VROOM)."""
    import requests
    from app.core.config import OSRM_BASE_URL, VROOM_BASE_URL

    osrm_ok = False
    vroom_ok = False

    try:
        r = requests.get(f"{OSRM_BASE_URL}/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false", timeout=5)
        osrm_ok = r.status_code == 200
    except Exception:
        pass

    try:
        r = requests.get(f"{VROOM_BASE_URL}/health", timeout=5)
        vroom_ok = r.status_code == 200
    except Exception:
        pass

    return {
        "osrm": {"url": OSRM_BASE_URL, "status": "ok" if osrm_ok else "down"},
        "vroom": {"url": VROOM_BASE_URL, "status": "ok" if vroom_ok else "down"},
        "all_ok": osrm_ok and vroom_ok,
    }


@app.get("/api/route-segment", tags=["routing"])
async def route_segment(
    origin_lat: float,
    origin_lon: float,
    dest_lat: float,
    dest_lon: float,
):
    """
    Devuelve la geometría GeoJSON del camino entre dos puntos (OSRM).
    Usado por la app en modo reparto para dibujar el tramo GPS → siguiente parada.
    """
    import requests as req
    from app.core.config import OSRM_BASE_URL, OSRM_TIMEOUT

    coords_str = f"{origin_lon},{origin_lat};{dest_lon},{dest_lat}"
    url = f"{OSRM_BASE_URL}/route/v1/driving/{coords_str}"
    params = {"overview": "full", "geometries": "geojson"}

    try:
        r = req.get(url, params=params, timeout=OSRM_TIMEOUT)
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
