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

# ── Mapa OSM (PBF editado, leído directamente por OSRM) ──────
OSRM_DIR = PROJECT_DIR / "osrm"
PBF_PATH  = OSRM_DIR / "posadas_editado.osm.pbf"

# ── Servicios externos (Docker locales) ───────────────────────
OSRM_BASE_URL = "http://localhost:5000"

# ── Google APIs ───────────────────────────────────────────────
GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")
GOOGLE_GEOCODING_URL = "https://maps.googleapis.com/maps/api/geocode/json"
GOOGLE_PLACES_URL = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
GOOGLE_CACHE_TTL_DAYS = 30      # días antes de expirar entradas de Google/Places

# ── Overpass API (catálogo de calles OSM) ─────────────────────
OVERPASS_USER_AGENT = "posadas-route-planner/1.4.0 (local)"
# Bbox del casco urbano de Posadas (más pequeño que BBOX_LAT/LON del área de reparto).
# Limita la descarga a las calles del pueblo; evita calles de municipios cercanos.
OVERPASS_BBOX = "37.78,-5.15,37.83,-5.06"

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

# ── Bounding box del área de reparto ─────────────────────────
# Cubre Posadas, Rivero de Posadas, Palma del Río y carreteras
# de acceso (~25 km radio). Excluye Córdoba capital y Montilla
# para evitar geocodificaciones erróneas en calles homónimas.
BBOX_LAT_MIN = 37.65
BBOX_LAT_MAX = 37.95
BBOX_LON_MIN = -5.35
BBOX_LON_MAX = -4.90
