"""
Catálogo de calles de Posadas.

Combina dos fuentes para disponer del mejor catálogo posible de calles:
  1. OSM Overpass — vías con nombre en el bbox de Posadas (TTL: 7 días).
  2. Calles aprendidas — guardadas cuando un fuzzy match lleva a geocodificación
     exitosa; permanentes hasta que se borren manualmente.

El catálogo combinado se usa en geocoding.py para el paso de fuzzy matching.
"""

import json
import time
from pathlib import Path

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_LEARNED_FILE = _DATA_DIR / "learned_streets.json"
_STREETS_FILE = _DATA_DIR / "osm_streets.json"

OSM_TTL_DAYS = 7

# Catálogo combinado en memoria (invalidar con _combined = None)
_combined: list[str] | None = None


# ─── OSM (lectura desde disco — la descarga la hace geocoding.py) ──────────────

def _load_osm_from_disk() -> list[str]:
    if not _STREETS_FILE.exists():
        return []
    try:
        raw = json.loads(_STREETS_FILE.read_text("utf-8"))
        age_days = (time.time() - raw.get("timestamp", 0)) / 86400
        if age_days > OSM_TTL_DAYS:
            return []
        return raw.get("streets", [])
    except Exception:
        return []


# ─── Calles aprendidas ─────────────────────────────────────────────────────────

def _load_learned_streets() -> list[str]:
    """Carga calles aprendidas de repartos anteriores."""
    if not _LEARNED_FILE.exists():
        return []
    try:
        return json.loads(_LEARNED_FILE.read_text("utf-8")).get("streets", [])
    except Exception:
        return []


def save_learned_street(street_name: str) -> None:
    """
    Guarda una calle aprendida (confirmada por geocodificación exitosa
    tras un fuzzy match). Permanente hasta borrado manual.
    Invalida el catálogo combinado en memoria.
    """
    global _combined
    learned = _load_learned_streets()
    if street_name not in learned:
        learned.append(street_name)
        try:
            _DATA_DIR.mkdir(parents=True, exist_ok=True)
            _LEARNED_FILE.write_text(
                json.dumps({"streets": sorted(learned)},
                           ensure_ascii=False, indent=2),
                "utf-8",
            )
        except Exception as e:
            print(f"[catalog] Error guardando learned_streets: {e}")
        _combined = None  # Invalidar caché en memoria
        # Invalidar también el catálogo en memoria de geocoding.py para que
        # el fuzzy matching use la nueva calle en la misma sesión
        try:
            from app.services import geocoding
            geocoding._osm_streets = None
            geocoding._osm_streets_norm = None
            geocoding._osm_streets_norm_set = None
        except Exception:
            pass


# ─── Catálogo combinado ────────────────────────────────────────────────────────

def get_combined_catalog() -> list[str]:
    """
    Devuelve la lista completa de calles de Posadas (OSM + aprendidas).
    Se cachea en memoria y se recarga si alguna fuente ha expirado.
    """
    global _combined
    if _combined is not None:
        return _combined

    all_streets: set[str] = set()

    # 1. OSM Overpass (cargado desde disco; la descarga la hace geocoding.py)
    osm = _load_osm_from_disk()
    if osm:
        all_streets.update(osm)

    # 2. Calles aprendidas
    learned = _load_learned_streets()
    if learned:
        all_streets.update(learned)

    _combined = sorted(all_streets)
    print(f"[catalog] Catálogo combinado: {len(_combined)} calles (OSM={len(osm)}, "
          f"Aprendidas={len(learned)})")
    return _combined
