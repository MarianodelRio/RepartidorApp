"""
Configuración centralizada del proyecto.
Todas las constantes y parámetros se definen aquí.
"""

from pathlib import Path

# ── Rutas del proyecto ────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent          # app/
PROJECT_DIR = BASE_DIR.parent                               # app_repartir/

# ── Servicios externos (Docker locales) ───────────────────────
OSRM_BASE_URL = "http://localhost:5000"
VROOM_BASE_URL = "http://localhost:3000"

# ── Geocodificación (Nominatim) ───────────────────────────────
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_USER_AGENT = "posadas-route-planner/2.0 (local)"

# ── Zona de trabajo: Posadas, Córdoba ─────────────────────────
START_ADDRESS = "Calle Callejon de Jesús 1, Posadas, Córdoba, España"
POSADAS_CENTER = (37.802, -5.105)          # lat, lon
POSADAS_VIEWBOX = "-5.15,37.78,-5.06,37.83"  # lon1,lat1,lon2,lat2

# ── Límites de la API ────────────────────────────────────────
MAX_STOPS = 200         # máximo de paradas por petición
GEOCODE_DELAY = 0.5     # segundos entre direcciones (mínimo para Nominatim)
GEOCODE_RETRY_DELAY = 0.3  # segundos entre estrategias internas
GEOCODE_TIMEOUT = 30    # timeout por llamada a Nominatim
OSRM_TIMEOUT = 60       # timeout para llamadas a OSRM
VROOM_TIMEOUT = 120     # timeout para llamadas a VROOM
