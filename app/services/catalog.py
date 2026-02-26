"""
Catálogo de calles de Posadas.

Combina tres fuentes para disponer del mejor catálogo posible de calles:
  1. OSM Overpass — vías con nombre en el bbox de Posadas (TTL: 7 días).
  2. Catastro CNIG — callejero oficial del municipio 14055 (TTL: 30 días).
  3. Calles aprendidas — guardadas cuando un fuzzy match lleva a geocodificación
     exitosa; permanentes hasta que se borren manualmente.

El catálogo combinado se usa en geocoding.py para el paso de fuzzy matching.
"""

import json
import time
from pathlib import Path

import requests

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_CATASTRO_FILE = _DATA_DIR / "catastro_streets.json"
_LEARNED_FILE = _DATA_DIR / "learned_streets.json"
_STREETS_FILE = _DATA_DIR / "osm_streets.json"

CATASTRO_TTL_DAYS = 30
OSM_TTL_DAYS = 7

# Endpoint JSON del callejero Catastro para Posadas, Córdoba
_CATASTRO_URL = (
    "https://ovc.catastro.meh.es/OVCServWeb/OVCWcfCallejero/"
    "COVCCallejero.svc/json/ConsultaVia"
)
_POSADAS_MUNICIPIO = "14055"
_POSADAS_PROVINCIA = "14"

# Catálogo combinado en memoria (invalidar con _combined = None)
_combined: list[str] | None = None

# Preposiciones y artículos que van en minúscula dentro de un nombre
_LOWERCASE_WORDS = {'de', 'del', 'la', 'las', 'los', 'el', 'y', 'e', 'a', 'en', 'con', 'al'}


def _to_title_case(name: str) -> str:
    """Convierte 'GARCIA LORCA' → 'Garcia Lorca' respetando artículos/preposiciones."""
    words = name.lower().split()
    return ' '.join(
        w if (i > 0 and w in _LOWERCASE_WORDS) else w.capitalize()
        for i, w in enumerate(words)
    )


# ─── Catastro CNIG ─────────────────────────────────────────────────────────────

def _fetch_catastro_streets() -> list[str]:
    """Descarga el callejero oficial de Posadas desde Catastro (CNIG)."""
    try:
        r = requests.get(
            _CATASTRO_URL,
            params={"Municipio": _POSADAS_MUNICIPIO, "Provincia": _POSADAS_PROVINCIA},
            timeout=30,
            headers={"Accept": "application/json"},
        )
        r.raise_for_status()
        data = r.json()
        vias = (
            data.get("ConsultaViaResult", {})
            .get("lsVias", {})
            .get("ViaCallejero", [])
        )
        _type_map = {
            "CL": "Calle", "AV": "Avenida", "PZ": "Plaza", "PJ": "Pasaje",
            "CM": "Camino", "TR": "Travesía", "RD": "Ronda", "CR": "Carretera",
            "GL": "Glorieta", "UR": "Urbanización", "PS": "Paseo",
        }
        streets: set[str] = set()
        for via in vias:
            tip = via.get("tip_via", "")
            name = via.get("via", "").strip()
            if name:
                name_tc = _to_title_case(name)
                prefix = _type_map.get(tip, tip)
                streets.add(f"{prefix} {name_tc}".strip() if prefix else name_tc)
        result = sorted(streets)
        print(f"[catalog] Catastro: {len(result)} calles descargadas")
        return result
    except Exception as e:
        print(f"[catalog] Error descargando Catastro: {e}")
        return []


def _load_catastro_from_disk() -> list[str] | None:
    if not _CATASTRO_FILE.exists():
        return None
    try:
        raw = json.loads(_CATASTRO_FILE.read_text("utf-8"))
        age_days = (time.time() - raw.get("timestamp", 0)) / 86400
        if age_days > CATASTRO_TTL_DAYS:
            return None
        return raw.get("streets", [])
    except Exception:
        return None


def _save_catastro_to_disk(streets: list[str]) -> None:
    try:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        _CATASTRO_FILE.write_text(
            json.dumps({"timestamp": time.time(), "streets": streets},
                       ensure_ascii=False, indent=2),
            "utf-8",
        )
    except Exception as e:
        print(f"[catalog] Error guardando Catastro: {e}")


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


# ─── Catálogo combinado ────────────────────────────────────────────────────────

def get_combined_catalog() -> list[str]:
    """
    Devuelve la lista completa de calles de Posadas (OSM + Catastro + aprendidas).
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

    # 2. Catastro CNIG
    catastro = _load_catastro_from_disk()
    if catastro is None:
        print("[catalog] Descargando callejero de Catastro...")
        catastro = _fetch_catastro_streets()
        if catastro:
            _save_catastro_to_disk(catastro)
    if catastro:
        all_streets.update(catastro)

    # 3. Calles aprendidas
    learned = _load_learned_streets()
    if learned:
        all_streets.update(learned)

    _combined = sorted(all_streets)
    print(f"[catalog] Catálogo combinado: {len(_combined)} calles (OSM={len(osm)}, "
          f"Catastro={len(catastro or [])}, Aprendidas={len(learned)})")
    return _combined
