"""
Servicio de optimización de rutas con LKH3 + OSRM.
Resuelve el TSP (Problema del Viajante) y devuelve detalles de ruta.

Flujo:
  snap_to_street()    — ajusta coords a la red viaria (OSRM /nearest)
  get_osrm_matrix()   — calcula matriz NxN de duración/distancia (OSRM /table)
  optimize_route()    — ordena paradas con LKH3
  get_route_details() — obtiene geometría GeoJSON de la ruta (OSRM /route)

Solver: LKH3 — determinista, óptimo para el tamaño de problema típico (~50 paradas).
"""

import json
import os
import shutil
import time
from pathlib import Path

import requests

from app.core.config import OSRM_BASE_URL, OSRM_TIMEOUT
from app.core.logging import get_logger

logger = get_logger(__name__)


# ── Localización del binario LKH3 ─────────────────────────────────────────────

def _find_lkh() -> str | None:
    """Devuelve la ruta al binario LKH3, o None si no está disponible."""
    p = shutil.which("LKH")
    if p:
        return p
    home_bin = os.path.expanduser("~/bin/LKH")
    if os.path.isfile(home_bin) and os.access(home_bin, os.X_OK):
        return home_bin
    return None

_LKH_BIN: str | None = _find_lkh()


def _format_distance(meters: float) -> str:
    """Formatea metros a texto legible."""
    if meters < 1000:
        return f"{int(meters)} m"
    return f"{meters / 1000:.1f} km"


# ═══════════════════════════════════════════
#  OSRM: Snap a red viaria con filtro de nombre
# ═══════════════════════════════════════════

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
    from app.services.geocoding import _normalize
    words = _normalize(name).split()
    return frozenset(w for w in words if w not in _SKIP_WORDS and len(w) >= 3)


# ── Caché de snap ──────────────────────────────────────────────────────────
# Persiste resultados de OSRM /nearest en disco. Sin TTL: solo se invalida
# al reconstruir el mapa (rebuild-map borra snap_cache.json).

_SNAP_CACHE_FILE = Path(__file__).resolve().parent.parent / "data" / "snap_cache.json"
_snap_cache: dict[str, list[float]] = {}


def _snap_key(lat: float, lon: float, hint: str) -> str:
    """Clave canónica: coordenada redondeada a 5 decimales + hint normalizado."""
    from app.services.geocoding import _normalize
    return f"{lat:.5f},{lon:.5f}>{_normalize(hint) if hint else ''}"


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


# ═══════════════════════════════════════════
#  OSRM: Matriz de distancias/duraciones
# ═══════════════════════════════════════════

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


# ═══════════════════════════════════════════
#  LKH3: Optimización TSP
# ═══════════════════════════════════════════

def _build_stop_details(
    ordered_ids: list[int],
    dur_matrix: list[list[int]],
    dist_matrix: list[list[int]],
) -> tuple[list[dict], float, float]:
    """Calcula distancias/duraciones acumuladas para la lista ordenada de paradas."""
    stop_details = []
    prev_idx = 0
    cumulative_dist = 0.0
    cumulative_dur  = 0.0
    for job_id in ordered_ids[1:]:
        cumulative_dist += dist_matrix[prev_idx][job_id]
        cumulative_dur  += dur_matrix[prev_idx][job_id]
        stop_details.append({
            "original_index": job_id,
            "arrival_distance": cumulative_dist,
            "arrival_duration": cumulative_dur,
        })
        prev_idx = job_id
    return stop_details, cumulative_dist, cumulative_dur


# ═══════════════════════════════════════════
#  Post-proceso: reagrupación por calle
# ═══════════════════════════════════════════

_REORDER_THRESHOLD_M = 20  # desvío máximo (metros) para considerar "de paso"


def _reorder_no_backtrack(
    ordered_ids: list[int],
    dist_matrix: list[list[int]],
    threshold_m: int = _REORDER_THRESHOLD_M,
) -> tuple[list[int], int]:
    """Post-proceso: recoloca paradas que están literalmente 'de paso'.

    Para cada parada j en posición i, busca el primer tramo anterior (a → b)
    donde el desvío para visitarla sea ≤ threshold_m metros:

        desvío = dist[a][j] + dist[j][b] − dist[a][b]

    Si lo encuentra, mueve j a esa posición (justo después de a).
    Usa el primer match (más temprano en la ruta) para que la parada se
    atienda la primera vez que el vehículo pasa por allí.

    Complejidad: O(N²) comparaciones de enteros en tabla ya calculada.
    Para N=50: < 1 ms, sin llamadas externas.

    Returns:
        (nuevo_orden, cantidad_paradas_movidas)
    """
    ordered = list(ordered_ids)
    n_moved = 0
    i = 1  # índice 0 = depósito, nunca se mueve
    moved_ids: set[int] = set()  # evita re-evaluar stops ya movidos (previene ciclos)

    while i < len(ordered):
        j = ordered[i]

        if j in moved_ids:
            i += 1
            continue

        insert_at = -1

        for k in range(i - 1):  # todos los tramos anteriores al actual
            a = ordered[k]
            b = ordered[k + 1]
            if dist_matrix[a][j] + dist_matrix[j][b] - dist_matrix[a][b] <= threshold_m:
                insert_at = k + 1
                break  # primer match = posición más temprana en la ruta

        if insert_at >= 0:
            ordered.pop(i)
            ordered.insert(insert_at, j)
            n_moved += 1
            moved_ids.add(j)
            # No incrementar i: re-evaluar la posición con el siguiente elemento
        else:
            i += 1

    return ordered, n_moved


def _solve_with_lkh(
    dur_matrix: list[list[int]],
    dist_matrix: list[list[int]],
) -> list[int] | None:
    """Resuelve TSP abierto con LKH3 vía subprocess.

    Devuelve lista de índices ordenados (incluyendo depósito en posición 0),
    o None si LKH no está disponible o falla.

    Usa el truco ATSP+nodo_fantasma para modelar el viaje abierto:
      cost(i → fantasma) = 0  →  cualquier nodo puede ser el último
      cost(fantasma → 0)  = 0  →  retorno gratuito al depósito
    """
    if _LKH_BIN is None:
        return None

    import subprocess
    import tempfile

    n = len(dur_matrix)
    BIG = 999_999
    n_ext = n + 1  # nodo fantasma = índice n

    mat = [[BIG] * n_ext for _ in range(n_ext)]
    for i in range(n):
        for j in range(n):
            mat[i][j] = dur_matrix[i][j]
    for i in range(n):
        mat[i][n] = 0     # cualquier nodo → fantasma = gratis
    mat[n][0] = 0         # fantasma → depósito = gratis

    try:
        tmpdir = tempfile.mkdtemp(prefix="lkh_")
        prob_file = os.path.join(tmpdir, "route.atsp")
        par_file  = os.path.join(tmpdir, "route.par")
        tour_file = os.path.join(tmpdir, "route.tour")

        with open(prob_file, "w") as f:
            f.write(f"NAME: route\nTYPE: ATSP\nDIMENSION: {n_ext}\n")
            f.write("EDGE_WEIGHT_TYPE: EXPLICIT\nEDGE_WEIGHT_FORMAT: FULL_MATRIX\n")
            f.write("EDGE_WEIGHT_SECTION\n")
            for row in mat:
                f.write(" ".join(map(str, row)) + "\n")
            f.write("EOF\n")

        with open(par_file, "w") as f:
            f.write(f"PROBLEM_FILE = {prob_file}\n")
            f.write(f"TOUR_FILE = {tour_file}\n")
            f.write("RUNS = 10\nSEED = 1\n")

        proc = subprocess.run(
            [_LKH_BIN, par_file],
            capture_output=True, text=True, timeout=60,
        )

        if proc.returncode != 0 or not os.path.exists(tour_file):
            logger.error("LKH3 falló (rc=%d)", proc.returncode)
            return None

        with open(tour_file) as f:
            tour_lines = f.read().strip().split("\n")

        tour: list[int] = []
        in_tour = False
        for line in tour_lines:
            s = line.strip()
            if s == "TOUR_SECTION":
                in_tour = True
                continue
            if in_tour:
                v = int(s)
                if v == -1:
                    break
                tour.append(v - 1)   # LKH usa índices 1-based → 0-based

        if 0 not in tour:
            logger.error("LKH3: depósito no encontrado en el tour")
            return None

        start = tour.index(0)
        ordered: list[int] = []
        for i in range(n_ext):
            node = tour[(start + i) % n_ext]
            if node == n:   # nodo fantasma → fin del recorrido
                break
            ordered.append(node)

        if len(ordered) != n:
            logger.error("LKH3 devolvió %d nodos, esperados %d", len(ordered), n)
            return None

        return ordered

    except Exception as e:
        logger.error("LKH3 excepción: %s", e)
        return None


def optimize_route(
    coords: list[tuple[float, float]],
) -> dict | None:
    """Optimiza el orden de visita con LKH3.

    Obtiene la matriz NxN de distancias vía OSRM /table y la usa como
    función de coste del TSP abierto (sin retorno al depósito).

    LKH3 es determinista: la misma matriz siempre produce el mismo orden óptimo.

    Args:
        coords: Lista de (lat, lon). El primer elemento es el depósito (fijo).
                Todas las coords deben estar ya snapeadas a la red viaria.

    Returns:
        dict con waypoint_order, stop_details, total_distance, total_duration,
        computing_time_ms; o None si falla.
    """
    if len(coords) < 2:
        return None

    # 1. Matriz de distancias desde OSRM /table
    matrix = get_osrm_matrix(coords)
    if matrix is None:
        logger.error("No se pudo obtener la matriz OSRM — abortando optimización")
        return None
    dur_matrix, dist_matrix = matrix

    t_start = time.perf_counter()

    # 2. Orden óptimo (LKH3)
    # dist_matrix se pasa como coste (parámetro dur_matrix): produce rutas
    # geográficamente coherentes minimizando metros, no segundos.
    ordered_ids = _solve_with_lkh(dist_matrix, dur_matrix)
    if ordered_ids is None:
        logger.error("LKH3 no pudo calcular la ruta")
        return None

    # 3. Post-proceso: reagrupar paradas de paso (evita dobles pasadas por la misma calle)
    ordered_ids, n_reordered = _reorder_no_backtrack(ordered_ids, dist_matrix)
    if n_reordered:
        logger.info(
            "Reagrupación por calle: %d parada(s) movida(s) (umbral %d m)",
            n_reordered, _REORDER_THRESHOLD_M,
        )

    computing_ms = (time.perf_counter() - t_start) * 1000

    # 4. Calcular distancias/duraciones acumuladas
    stop_details, cumulative_dist, cumulative_dur = _build_stop_details(
        ordered_ids, dur_matrix, dist_matrix
    )

    logger.info(
        "LKH3 resultado: %d paradas, distancia=%.0f m, duración=%.0f s, "
        "cómputo=%.0f ms, orden=%s",
        len(ordered_ids) - 1, cumulative_dist, cumulative_dur,
        computing_ms, ordered_ids[1:],
    )

    return {
        "waypoint_order": ordered_ids,
        "stop_details": stop_details,
        "total_distance": cumulative_dist,
        "total_duration": cumulative_dur,
        "computing_time_ms": computing_ms,
    }


# ═══════════════════════════════════════════
#  OSRM: Ruta detallada con geometría GeoJSON
# ═══════════════════════════════════════════

def get_route_details(
    coords_ordered: list[tuple[float, float]],
) -> dict | None:
    """Dado un orden de coordenadas ya optimizado, obtiene la geometría GeoJSON
    de la ruta completa desde OSRM /route.

    Args:
        coords_ordered: Lista de (lat, lon) en el orden de visita.

    Returns:
        dict con geometry (GeoJSON), total_distance, total_duration; o None si falla.
    """
    if len(coords_ordered) < 2:
        return None

    coords_str = ";".join(f"{lon},{lat}" for lat, lon in coords_ordered)
    url = f"{OSRM_BASE_URL}/route/v1/driving/{coords_str}"
    params = {
        "overview": "full",
        "geometries": "geojson",
    }

    try:
        r = requests.get(url, params=params, timeout=OSRM_TIMEOUT)
        r.raise_for_status()
        data = r.json()

        if data.get("code") != "Ok":
            logger.error("OSRM error: %s — %s", data.get("code"), data.get("message", ""))
            return None

        route = data["routes"][0]

        return {
            "geometry": route["geometry"],
            "total_distance": round(route.get("distance", 0)),
            "total_duration": round(route.get("duration", 0)),
        }

    except Exception as e:
        logger.error("OSRM error: %s", e)
        return None


# Cargar caché de snap al importar el módulo
_load_snap_cache()
