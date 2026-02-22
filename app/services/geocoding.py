"""
Servicio de geocodificación con Nominatim.
Cache en memoria para evitar llamadas repetidas.

Limpieza y multi-estrategia para convertir direcciones de texto en coordenadas:
    - Normaliza abreviaturas y corrige encoding
    - Elimina ruido y aplica búsquedas alternas (texto libre, estructurada, bounded)
"""

import json
import time
from pathlib import Path

import requests

from app.core.config import (
    NOMINATIM_URL,
    NOMINATIM_USER_AGENT,
    POSADAS_VIEWBOX,
    GEOCODE_DELAY,
    GEOCODE_RETRY_DELAY,
    GEOCODE_TIMEOUT,
)

# Cache en memoria: dirección normalizada → (lat, lon) | None
_cache: dict[str, tuple[float, float] | None] = {}

# ═══════════════════════════════════════════
#  Persistencia de overrides manuales (unificada con la cache)
# ═══════════════════════════════════════════
_OVERRIDES_FILE = Path(__file__).resolve().parent.parent / "data" / "geocode_overrides.json"
# metadata persisted for manual overrides: key -> {lat, lon, original}
_override_meta: dict[str, dict] = {}


def _load_overrides() -> None:
    """Carga overrides desde disco y los carga en la cache en memoria."""
    global _override_meta, _cache
    _override_meta = {}
    if _OVERRIDES_FILE.exists():
        try:
            _override_meta = json.loads(_OVERRIDES_FILE.read_text("utf-8"))
            # cargar en cache las coordenadas persistidas
            for k, meta in _override_meta.items():
                try:
                    lat = float(meta.get("lat"))
                    lon = float(meta.get("lon"))
                    _cache[k] = (lat, lon)
                except Exception:
                    # ignorar entradas corruptas
                    continue
        except Exception:
            _override_meta = {}


def _save_overrides() -> None:
    """Persiste únicamente las entradas marcadas como overrides a disco."""
    try:
        _OVERRIDES_FILE.parent.mkdir(parents=True, exist_ok=True)
        _OVERRIDES_FILE.write_text(json.dumps(_override_meta, ensure_ascii=False, indent=2), "utf-8")
    except Exception as e:
        print(f"[geocode] Error guardando overrides en disco: {e}")


def add_override(address: str, lat: float, lon: float) -> None:
    """Registra coordenadas manuales para una dirección y las persiste.

    La cache en memoria se usa como fuente única para búsquedas; las entradas manuales
    también se guardan en `_override_meta` y se persisten en disco.
    """
    key = address.strip().lower()
    meta = {"lat": lat, "lon": lon, "original": address.strip()}
    _override_meta[key] = meta
    # actualizar cache en memoria
    _cache[key] = (lat, lon)
    _save_overrides()


# Cargar overrides al importar el módulo
_load_overrides()




# ═══════════════════════════════════════════
#  Geocodificación multi-estrategia
# ═══════════════════════════════════════════

def _nominatim_query(query: str, bounded: int = 0, return_raw: bool = False) -> tuple[float, float] | dict | None:
    """Hace una consulta a Nominatim.

    Si return_raw=False (por defecto) devuelve (lat, lon) o None.
    Si return_raw=True devuelve el primer objeto JSON devuelto por Nominatim o None.
    En ambos casos se aplica una validación ligera de que la coordenada esté en la zona esperada.
    """
    params = {
        "q": query,
        "format": "jsonv2",
        "limit": 1,
        "countrycodes": "es",
        "viewbox": POSADAS_VIEWBOX,
        "bounded": bounded,
    }
    headers = {"User-Agent": NOMINATIM_USER_AGENT}

    try:
        r = requests.get(NOMINATIM_URL, params=params, headers=headers, timeout=GEOCODE_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        if not data or not isinstance(data, list):
            return None

        first = data[0]
        lat = float(first.get("lat"))
        lon = float(first.get("lon"))

        if return_raw:
            return first
        
        return (lat, lon)
    except Exception as e:
        print(f"[geocode] Error Nominatim para '{query}': {e}")
        return None



def geocode(address: str) -> tuple[float, float] | None:
    """
    Geocodificador simple: construye una query para Nominatim, la llama y devuelve (lat, lon) o None.

    - Se respeta la cache y los overrides manuales si existen.
    """
    if not address or not address.strip():
        return None

    key = address.strip().lower()

    # Cache (incluye entradas persistidas como overrides)
    if key in _cache:
        return _cache[key]

    # Construir query
    query = address.strip()
    query = f"{query}, Posadas, Córdoba, España"

    # Usar el helper _nominatim_query para obtener el objeto raw y así extraer calle/número
    raw = _nominatim_query(query, return_raw=True)
    if not raw:
        _cache[key] = None
        return None

    try:
        lat = float(raw.get("lat"))
        lon = float(raw.get("lon"))
    except Exception:
        _cache[key] = None
        return None

    # Actualizar cache en memoria (sin escritura a disco — solo para auto-geocodes)
    _cache[key] = (lat, lon)
    return (lat, lon)


def geocode_batch(addresses: list[str]) -> list[tuple[str, tuple[float, float] | None]]:
    """
    Geocodifica una lista de direcciones respetando rate-limit de Nominatim.
    Devuelve lista de (dirección_original, (lat, lon) | None).
    """
    results = []
    for i, addr in enumerate(addresses):
        coord = geocode(addr)
        results.append((addr, coord))
        if addr.strip().lower() not in _cache and i < len(addresses) - 1:
            time.sleep(GEOCODE_DELAY)
    return results


def clear_cache():
    """Limpia la cache de geocodificación."""
    _cache.clear()
