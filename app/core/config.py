"""
Configuración centralizada del proyecto.
Todas las constantes y parámetros se definen aquí.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# ── Rutas del proyecto ────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent          # app/
PROJECT_DIR = BASE_DIR.parent                               # app_repartir/

# ── Servicios externos (Docker locales) ───────────────────────
OSRM_BASE_URL = "http://localhost:5000"
VROOM_BASE_URL = "http://localhost:3000"

# ── Google APIs ───────────────────────────────────────────────
GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")
GOOGLE_GEOCODING_URL = "https://maps.googleapis.com/maps/api/geocode/json"
GOOGLE_PLACES_URL = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
GOOGLE_CACHE_TTL_DAYS = 30      # días antes de expirar entradas de Google/Places

# ── Nominatim (solo para catálogo Overpass de calles) ─────────
NOMINATIM_USER_AGENT = "posadas-route-planner/1.4.0 (local)"

# ── Zona de trabajo: Posadas, Córdoba ─────────────────────────
# Depósito/taller de salida: Avenida de Andalucía, Posadas
DEPOT_LAT = 37.805503
DEPOT_LON = -5.099805
START_ADDRESS = "Avenida de Andalucía, Posadas"
POSADAS_CENTER = (DEPOT_LAT, DEPOT_LON)    # lat, lon

# ── Límites de la API ────────────────────────────────────────
MAX_STOPS = 200         # máximo de paradas por petición
GEOCODE_TIMEOUT = 30    # timeout por llamada a APIs externas
OSRM_TIMEOUT = 60       # timeout para llamadas a OSRM
VROOM_TIMEOUT = 120     # timeout para llamadas a VROOM

# ── Bounding box del área de reparto ─────────────────────────
# Cubre Posadas, Palma del Río, Córdoba, Écija y zonas rurales
# de la comarca (incluye cortijos como Rivero, radio ~60 km).
# Coords fuera de este rectángulo se rechazan antes de llamar a VROOM.
BBOX_LAT_MIN = 37.3
BBOX_LAT_MAX = 38.2
BBOX_LON_MIN = -5.6
BBOX_LON_MAX = -4.4
