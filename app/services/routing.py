"""
Servicio de optimización de rutas con LKH3 + OSRM.
Resuelve el TSP (Problema del Viajante) y devuelve detalles de ruta.

Flujo:
  snap_to_street()  — ajusta coords a la red viaria (OSRM /nearest)
  get_osrm_matrix() — calcula matriz NxN de duración/distancia (OSRM /table)
  optimize_route()  — ordena paradas con LKH3

Solver: LKH3 — determinista, óptimo para el tamaño de problema típico (~50 paradas).
"""

import time

from app.core.logging import get_logger
from app.services.ports import MatrixProvider, RouteSolver
from app.adapters.osrm import (
    snap_to_street,
    get_osrm_matrix,
    _snap_cache,
    _snap_key,
    _save_snap_cache,
)
from app.adapters.lkh3 import _solve_with_lkh

logger = get_logger(__name__)


def format_distance(meters: float) -> str:
    """Formatea metros a texto legible."""
    if meters < 1000:
        return f"{int(meters)} m"
    return f"{meters / 1000:.1f} km"


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


def optimize_route(
    coords: list[tuple[float, float]],
    *,
    matrix_fn: MatrixProvider | None = None,
    solver_fn: RouteSolver | None = None,
) -> dict | None:
    """Optimiza el orden de visita con LKH3.

    Obtiene la matriz NxN de distancias vía OSRM /table y la usa como
    función de coste del TSP abierto (sin retorno al depósito).

    LKH3 es determinista: la misma matriz siempre produce el mismo orden óptimo.

    Args:
        coords:     Lista de (lat, lon). El primer elemento es el depósito (fijo).
                    Todas las coords deben estar ya snapeadas a la red viaria.
        matrix_fn:  Proveedor de matriz (MatrixProvider). Por defecto: OSRM.
        solver_fn:  Solver TSP (RouteSolver). Por defecto: LKH3.

    Returns:
        dict con waypoint_order, stop_details, total_distance, total_duration,
        computing_time_ms; o None si falla.
    """
    if len(coords) < 2:
        return None

    # Resolución dinámica: permite sustituir implementaciones vía parámetro
    # y mantiene compatibilidad con patches de test sobre el nombre del módulo.
    _matrix_fn = matrix_fn if matrix_fn is not None else get_osrm_matrix
    _solver_fn = solver_fn if solver_fn is not None else _solve_with_lkh

    # 1. Matriz de distancias
    matrix = _matrix_fn(coords)
    if matrix is None:
        logger.error("No se pudo obtener la matriz OSRM — abortando optimización")
        return None
    dur_matrix, dist_matrix = matrix

    t_start = time.perf_counter()

    # 2. Orden óptimo
    # dist_matrix se pasa como coste (parámetro dur_matrix): produce rutas
    # geográficamente coherentes minimizando metros, no segundos.
    ordered_ids = _solver_fn(dist_matrix, dur_matrix)
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
