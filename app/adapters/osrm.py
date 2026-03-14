"""
Adaptador OSRM — snap a red viaria y matriz de distancias.
"""

import json
from pathlib import Path

import requests

from app.core.config import OSRM_BASE_URL, OSRM_TIMEOUT
from app.core.logging import get_logger
from app.utils.normalization import normalize_text

logger = get_logger(__name__)


_SNAP_MAX_DIST_M = 150   # umbral de snap_to_street
_SNAP_CANDIDATES = 15    # candidatos OSRM nearest a evaluar

# Palabras que no aportan al matching de nombre de calle.
_SKIP_WORDS = frozenset({
    # Tipos de vía
    "calle", "avenida", "plaza", "camino", "carretera", "paseo", "pasaje",
    "travesia", "ronda", "glorieta", "urbanizacion", "poligono", "barrio",
    "via", "callejon", "calzada", "autovia", "autopista",
    # Artículos y preposiciones
    "de", "del", "la", "las", "los", "el", "y", "e", "a", "en", "al", "con",
})


def _significant_words(name: str) -> frozenset[str]:
    """Palabras significativas de un nombre de calle, normalizadas."""
    words = normalize_text(name).split()
    return frozenset(w for w in words if w not in _SKIP_WORDS and len(w) >= 3)


# ── Caché de snap ──────────────────────────────────────────────────────────
# Persiste resultados de OSRM /nearest en disco. Sin TTL: solo se invalida
# al reconstruir el mapa (rebuild-map borra snap_cache.json).

_SNAP_CACHE_FILE = Path(__file__).resolve().parent.parent / "data" / "snap_cache.json"
_snap_cache: dict[str, list[float]] = {}


def _snap_key(lat: float, lon: float, hint: str) -> str:
    """Clave canónica: coordenada redondeada a 5 decimales + hint normalizado."""
    return f"{lat:.5f},{lon:.5f}>{normalize_text(hint) if hint else ''}"


def _load_snap_cache() -> None:
    """Carga el caché de snap desde disco al arrancar el módulo."""
    global _snap_cache
    if not _SNAP_CACHE_FILE.exists():
        _snap_cache = {}
        return
    try:
        _snap_cache = json.loads(_SNAP_CACHE_FILE.read_text("utf-8"))
        logger.info("Snap cache cargado: %d entradas", len(_snap_cache))
    except Exception as e:
        logger.error("Error cargando snap_cache: %s", e)
        _snap_cache = {}


def _save_snap_cache() -> None:
    """Persiste el caché de snap en disco."""
    try:
        _SNAP_CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        _SNAP_CACHE_FILE.write_text(
            json.dumps(_snap_cache, ensure_ascii=False, indent=2), "utf-8"
        )
    except Exception as e:
        logger.error("Error guardando snap_cache: %s", e)


def clear_snap_cache() -> None:
    """Limpia el caché de snap en memoria y en disco.

    Llamar tras rebuild-map: el nuevo mapa OSRM puede reubicar nodos,
    así que las coordenadas snapeadas anteriores quedan obsoletas.
    """
    global _snap_cache
    _snap_cache = {}
    try:
        if _SNAP_CACHE_FILE.exists():
            _SNAP_CACHE_FILE.unlink()
            logger.info("Snap cache eliminado tras rebuild")
    except Exception as e:
        logger.error("Error eliminando snap_cache: %s", e)


def snap_to_street(
    lat: float,
    lon: float,
    street_hint: str,
    n_candidates: int = _SNAP_CANDIDATES,
    max_dist_m: float = _SNAP_MAX_DIST_M,
) -> tuple[float, float] | None:
    """Snappea (lat, lon) al nodo de red viaria más cercano cuyo nombre
    de calle coincida con street_hint.

    Estrategia:
      1. Pide n_candidates a OSRM /nearest.
      2. Si el más cercano supera max_dist_m → fuera del mapa → None.
      3. Busca el candidato cuyas palabras clave incluyen las del hint.
      4. Si no hay coincidencia → fallback al más cercano (dentro de max_dist_m).
      5. Si no hay hint → usa el más cercano directamente.

    Returns:
        (snap_lat, snap_lon) del nodo en la red viaria, o None si fuera del mapa.
    """
    key = _snap_key(lat, lon, street_hint)
    if key in _snap_cache:
        cached = _snap_cache[key]
        return cached[0], cached[1]

    try:
        r = requests.get(
            f"{OSRM_BASE_URL}/nearest/v1/driving/{lon},{lat}",
            params={"number": n_candidates},
            timeout=5,
        )
        r.raise_for_status()
        data = r.json()
        if data.get("code") != "Ok" or not data.get("waypoints"):
            return None

        candidates = data["waypoints"]
        nearest_dist = candidates[0].get("distance", float("inf"))
        if nearest_dist > max_dist_m:
            return None

        hint_words = _significant_words(street_hint)
        best: dict | None = None
        best_dist = float("inf")

        if hint_words:
            for wp in candidates:
                cand_name = wp.get("name", "")
                if not cand_name:
                    continue
                if hint_words.issubset(_significant_words(cand_name)):
                    dist = wp.get("distance", float("inf"))
                    if dist < best_dist:
                        best = wp
                        best_dist = dist

        if best is None and hint_words:
            nearest_name = candidates[0].get("name", "")
            logger.debug(
                "snap fallback '%s' → '%s' (%.0f m) — ningún candidato con nombre coincidente",
                street_hint, nearest_name, nearest_dist,
            )
            best = candidates[0]

        chosen = best if best is not None else candidates[0]
        snap_lon, snap_lat = chosen["location"]

        _snap_cache[key] = [snap_lat, snap_lon]
        _save_snap_cache()

        return snap_lat, snap_lon

    except Exception as e:
        logger.error("Error en snap_to_street (%.4f, %.4f): %s", lat, lon, e)
        return None


def get_osrm_matrix(
    coords: list[tuple[float, float]],
) -> tuple[list[list[int]], list[list[int]]] | None:
    """Calcula la matriz NxN de duración y distancia entre todas las coordenadas.

    Llama a OSRM /table y redondea los valores a enteros.
    Los índices de la matriz corresponden al orden de `coords` (índice 0 = depósito).

    Returns:
        (dur_matrix, dist_matrix) como listas de listas de int, o None si falla.
    """
    if len(coords) < 2:
        return None

    coords_str = ";".join(f"{lon},{lat}" for lat, lon in coords)
    try:
        r = requests.get(
            f"{OSRM_BASE_URL}/table/v1/driving/{coords_str}",
            params={"annotations": "duration,distance"},
            timeout=OSRM_TIMEOUT,
        )
        r.raise_for_status()
        data = r.json()

        if data.get("code") != "Ok":
            logger.error("OSRM /table error: %s", data.get("message", ""))
            return None

        dur_matrix  = [[round(v) for v in row] for row in data["durations"]]
        dist_matrix = [[round(v) for v in row] for row in data["distances"]]
        return dur_matrix, dist_matrix

    except Exception as e:
        logger.error("Error en OSRM /table: %s", e)
        return None


# Cargar caché de snap al importar el módulo
_load_snap_cache()
