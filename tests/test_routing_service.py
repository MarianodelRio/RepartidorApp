"""
Tests del servicio routing.py: snap_to_street, get_osrm_matrix,
optimize_route, _reorder_no_backtrack.
Se mockean las llamadas HTTP a OSRM; LKH3 resuelve con matrices reales pequeñas.
"""

from unittest.mock import patch, Mock

import app.services.routing as routing_module
from app.services.routing import (
    snap_to_street,
    get_osrm_matrix,
    optimize_route,
    _reorder_no_backtrack,
    _snap_key,
)

COORDS_2 = [(37.805, -5.099), (37.806, -5.100)]
COORDS_3 = [(37.805, -5.099), (37.806, -5.100), (37.807, -5.101)]

# Matrices mock: índice 0 = depósito, 1+ = paradas
# _MATRIX_2: depósito + 1 parada (única solución posible: [0,1])
_MATRIX_2 = (
    [[0, 300], [300, 0]],           # durations (s)
    [[0, 1500], [1500, 0]],         # distances (m)
)

# _MATRIX_3: depósito + 2 paradas
# Óptimo 0→1→2 (dur=100+90=190 < 0→2→1=200+90=290)
# dist[0][1]=800, dist[1][2]=700 → arrivals acumuladas: 800, 1500
_MATRIX_3 = (
    [[0, 100, 200], [100, 0, 90], [200, 90, 0]],
    [[0, 800, 1500], [800, 0, 700], [1500, 700, 0]],
)

# _MATRIX_3_REV: depósito + 2 paradas
# Óptimo 0→2→1 (dur=50+60=110 < 0→1→2=200+60=260)
_MATRIX_3_REV = (
    [[0, 200, 50], [200, 0, 60], [50, 60, 0]],
    [[0, 1500, 400], [1500, 0, 600], [400, 600, 0]],
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _candidate(name: str, lat: float, lon: float, dist: float) -> dict:
    return {"name": name, "location": [lon, lat], "distance": dist}


def _mock_osrm_table(durations: list[list[int]], distances: list[list[int]]):
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {
        "code": "Ok",
        "durations": durations,
        "distances": distances,
    }
    return m


def _mock_osrm_route(code="Ok", distance=1500, duration=300):
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {
        "code": code,
        "routes": [{
            "geometry": {"type": "LineString", "coordinates": [[-5.099, 37.805]]},
            "distance": distance,
            "duration": duration,
        }],
    }
    return m


# ── Helpers snap cache ────────────────────────────────────────────────────────

def _clear_snap_cache():
    """Limpia el caché de snap en memoria entre tests."""
    routing_module._snap_cache.clear()


# ── snap_to_street ────────────────────────────────────────────────────────────

def _mock_nearest(candidates: list[dict], code: str = "Ok"):
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {"code": code, "waypoints": candidates}
    return m


def test_snap_encuentra_candidato_por_nombre():
    candidates = [
        _candidate("Calle Mayor", 37.805, -5.099, 50),
        _candidate("Calle Gaitán", 37.806, -5.100, 80),
    ]
    with patch("app.adapters.osrm.requests.get", return_value=_mock_nearest(candidates)):
        result = snap_to_street(37.806, -5.100, "Calle Gaitán")
    assert result == (37.806, -5.100)


def test_snap_fallback_al_mas_cercano_si_no_hay_coincidencia():
    candidates = [
        _candidate("Calle Mayor", 37.805, -5.099, 30),
        _candidate("Avenida Sur", 37.806, -5.100, 60),
    ]
    with patch("app.adapters.osrm.requests.get", return_value=_mock_nearest(candidates)):
        result = snap_to_street(37.805, -5.099, "Calle Inexistente")
    # Fallback: candidato más cercano (índice 0)
    assert result == (37.805, -5.099)


def test_snap_fuera_de_150m_devuelve_none():
    candidates = [_candidate("Calle Mayor", 37.805, -5.099, 200)]
    with patch("app.adapters.osrm.requests.get", return_value=_mock_nearest(candidates)):
        result = snap_to_street(37.805, -5.099, "Calle Mayor")
    assert result is None


def test_snap_sin_hint_usa_mas_cercano():
    candidates = [
        _candidate("Calle Mayor", 37.805, -5.099, 20),
        _candidate("Avenida Sur", 37.806, -5.100, 50),
    ]
    with patch("app.adapters.osrm.requests.get", return_value=_mock_nearest(candidates)):
        result = snap_to_street(37.805, -5.099, "")
    assert result == (37.805, -5.099)


def test_snap_osrm_caido_devuelve_none():
    with patch("app.adapters.osrm.requests.get", side_effect=Exception("timeout")):
        result = snap_to_street(37.805, -5.099, "Calle Mayor")
    assert result is None


def test_snap_respuesta_code_error_devuelve_none():
    with patch("app.adapters.osrm.requests.get",
               return_value=_mock_nearest([], code="Error")):
        result = snap_to_street(37.805, -5.099, "Calle Mayor")
    assert result is None


def test_snap_cache_hit_no_llama_osrm():
    _clear_snap_cache()
    key = _snap_key(37.806, -5.100, "Calle Gaitán")
    routing_module._snap_cache[key] = [37.806, -5.100]
    with patch("app.adapters.osrm.requests.get") as mock_get:
        result = snap_to_street(37.806, -5.100, "Calle Gaitán")
    mock_get.assert_not_called()
    assert result == (37.806, -5.100)


def test_snap_cache_miss_llama_osrm_y_guarda():
    _clear_snap_cache()
    candidates = [_candidate("Calle Gaitán", 37.806, -5.100, 30)]
    with patch("app.adapters.osrm.requests.get", return_value=_mock_nearest(candidates)), \
         patch("app.adapters.osrm._save_snap_cache"):  # no escribir disco en tests
        result = snap_to_street(37.806, -5.100, "Calle Gaitán")
    assert result == (37.806, -5.100)
    key = _snap_key(37.806, -5.100, "Calle Gaitán")
    assert key in routing_module._snap_cache
    assert routing_module._snap_cache[key] == [37.806, -5.100]


def test_snap_cache_none_no_se_guarda():
    """Los fallos de OSRM (None) no se cachean — se reintentará en el siguiente optimize."""
    _clear_snap_cache()
    candidates = [_candidate("Calle Mayor", 37.805, -5.099, 200)]  # > 150m → None
    with patch("app.adapters.osrm.requests.get", return_value=_mock_nearest(candidates)), \
         patch("app.adapters.osrm._save_snap_cache") as mock_save:
        result = snap_to_street(37.805, -5.099, "Calle Mayor")
    assert result is None
    mock_save.assert_not_called()
    assert len(routing_module._snap_cache) == 0


def test_snap_cache_clave_distingue_hint():
    """Mismas coords con hints distintos producen claves distintas."""
    key1 = _snap_key(37.806, -5.100, "Calle Gaitán")
    key2 = _snap_key(37.806, -5.100, "Calle Mayor")
    key3 = _snap_key(37.806, -5.100, "")
    assert key1 != key2
    assert key1 != key3
    assert key2 != key3


# ── get_osrm_matrix ───────────────────────────────────────────────────────────

def test_osrm_matrix_menos_de_2_coords_devuelve_none():
    assert get_osrm_matrix([(37.805, -5.099)]) is None


def test_osrm_matrix_devuelve_matrices_NxN():
    dur  = [[0, 24], [18, 0]]
    dist = [[0, 107], [107, 0]]
    with patch("app.adapters.osrm.requests.get",
               return_value=_mock_osrm_table(dur, dist)):
        result = get_osrm_matrix(COORDS_2)
    assert result is not None
    dur_out, dist_out = result
    assert dur_out  == [[0, 24], [18, 0]]
    assert dist_out == [[0, 107], [107, 0]]


def test_osrm_matrix_redondea_floats_a_enteros():
    dur  = [[0.0, 24.6], [18.1, 0.0]]
    dist = [[0.0, 107.9], [107.9, 0.0]]
    with patch("app.adapters.osrm.requests.get",
               return_value=_mock_osrm_table(dur, dist)):
        dur_out, dist_out = get_osrm_matrix(COORDS_2)
    assert dur_out[0][1]  == 25   # round(24.6)
    assert dist_out[0][1] == 108  # round(107.9)


def test_osrm_matrix_error_code_devuelve_none():
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {"code": "Error", "message": "unreachable"}
    with patch("app.adapters.osrm.requests.get", return_value=m):
        assert get_osrm_matrix(COORDS_2) is None


def test_osrm_matrix_osrm_caido_devuelve_none():
    with patch("app.adapters.osrm.requests.get", side_effect=Exception("timeout")):
        assert get_osrm_matrix(COORDS_2) is None


# ── optimize_route ────────────────────────────────────────────────────────────
# LKH3 resuelve con matrices pequeñas (2-3 nodos) en < 1ms.

def test_optimize_menos_de_2_coords_devuelve_none():
    assert optimize_route([(37.805, -5.099)]) is None


def test_optimize_devuelve_orden_correcto():
    # _MATRIX_2: única solución posible [0, 1]
    with patch("app.services.routing.get_osrm_matrix", return_value=_MATRIX_2):
        result = optimize_route(COORDS_2)
    assert result is not None
    assert result["waypoint_order"] == [0, 1]


def test_optimize_3_paradas_orden_optimo_1_antes_que_2():
    # _MATRIX_3: 0→1→2 = 800+700=1500m  <  0→2→1 = 1500+700=2200m  →  orden óptimo [0,1,2]
    with patch("app.services.routing.get_osrm_matrix", return_value=_MATRIX_3):
        result = optimize_route(COORDS_3)
    assert result["waypoint_order"] == [0, 1, 2]


def test_optimize_3_paradas_orden_optimo_2_antes_que_1():
    # _MATRIX_3_REV: 0→2→1 = 400+600=1000m  <  0→1→2 = 1500+600=2100m  →  orden óptimo [0,2,1]
    with patch("app.services.routing.get_osrm_matrix", return_value=_MATRIX_3_REV):
        result = optimize_route(COORDS_3)
    assert result["waypoint_order"] == [0, 2, 1]


def test_optimize_devuelve_distancia_total():
    # _MATRIX_2: dist[0][1] = 1500 → total_distance = 1500
    with patch("app.services.routing.get_osrm_matrix", return_value=_MATRIX_2):
        result = optimize_route(COORDS_2)
    assert result["total_distance"] == 1500


def test_optimize_stop_details_arrival_distance_acumulada():
    # _MATRIX_3: orden óptimo [0,1,2]; dist[0][1]=800, dist[1][2]=700
    with patch("app.services.routing.get_osrm_matrix", return_value=_MATRIX_3):
        result = optimize_route(COORDS_3)
    details = result["stop_details"]
    assert details[0]["arrival_distance"] == 800
    assert details[1]["arrival_distance"] == 1500   # acumulada: 800 + 700


def test_optimize_matrix_falla_devuelve_none():
    with patch("app.services.routing.get_osrm_matrix", return_value=None):
        assert optimize_route(COORDS_2) is None


def test_optimize_lkh_falla_devuelve_none():
    with patch("app.services.routing.get_osrm_matrix", return_value=_MATRIX_2), \
         patch("app.services.routing._solve_with_lkh", return_value=None):
        assert optimize_route(COORDS_2) is None


# ── _reorder_no_backtrack ─────────────────────────────────────────────────────
#
# Matrices de test:
#   0 = depósito
#   1 = Gaitán A (ej. Gaitán 47)
#   2 = Gaitán B (ej. Gaitán 24) — misma calle que 1
#   3 = OtraCalle
#   4 = Gaitán C (ej. Gaitán 78) — misma calle que 1 y 2
#   5 = Gaitán D (ej. Gaitán 52) — misma calle que 1, 2 y 4
#
# dist[1][2]=80, dist[2][4]=50, dist[4][5]=20, dist[1][5]=60, dist[2][5]=30
# Paradas de OtraCalle están lejos (dist ≥ 140) de las de Gaitán.

_DIST_4 = [
    #    0     1     2     3
    [    0,  300,  500,  700],   # 0 depósito
    [  300,    0,   80,  400],   # 1 Gaitán A
    [  500,   80,    0,  200],   # 2 Gaitán B
    [  700,  400,  200,    0],   # 3 OtraCalle
]

_DIST_5 = [
    #    0     1     2     3     4
    [    0,  300,  500,  700,  650],   # 0 depósito
    [  300,    0,   80,  400,  120],   # 1 Gaitán A
    [  500,   80,    0,  200,   50],   # 2 Gaitán B
    [  700,  400,  200,    0,  150],   # 3 OtraCalle
    [  650,  120,   50,  150,    0],   # 4 Gaitán C
]

_DIST_6 = [
    #    0     1     2     3     4     5
    [    0,  300,  500,  700,  650,  620],   # 0 depósito
    [  300,    0,   80,  400,  120,   60],   # 1 Gaitán A
    [  500,   80,    0,  200,   50,   30],   # 2 Gaitán B
    [  700,  400,  200,    0,  150,  170],   # 3 OtraCalle
    [  650,  120,   50,  150,    0,   20],   # 4 Gaitán C
    [  620,   60,   30,  170,   20,    0],   # 5 Gaitán D
]


def test_reorder_sin_movimiento_cuando_desvio_grande():
    # Todas las distancias son grandes, ningún desvío ≤ 20 m → sin cambios
    result, n = _reorder_no_backtrack([0, 1, 2, 3], _DIST_4)
    assert result == [0, 1, 2, 3]
    assert n == 0


def test_reorder_mueve_parada_de_paso():
    # Orden LKH: [0, 1, 3, 2] — stop 2 (Gaitán B) llega después de OtraCalle
    # Tramo (1→3): dist[1][2]+dist[2][3]-dist[1][3] = 80+200-400 = -120 ≤ 20 ✓
    # → stop 2 se mueve a posición 2 (entre 1 y 3)
    result, n = _reorder_no_backtrack([0, 1, 3, 2], _DIST_4)
    assert result == [0, 1, 2, 3]
    assert n == 1


def test_reorder_mueve_parada_de_paso_5_stops():
    # Orden LKH: [0, 1, 2, 3, 4] — stop 4 (Gaitán C) al final
    # Tramo (2→3): dist[2][4]+dist[4][3]-dist[2][3] = 50+150-200 = 0 ≤ 20 ✓
    # → stop 4 se mueve a posición 3 (entre Gaitán B y OtraCalle)
    result, n = _reorder_no_backtrack([0, 1, 2, 3, 4], _DIST_5)
    assert result == [0, 1, 2, 4, 3]
    assert n == 1


def test_reorder_cascading_dos_paradas_agrupadas():
    # Orden LKH: [0, 1, 2, 3, 4, 5]
    # 1ª iteración: stop 4 se mueve entre 2 y 3 → [0,1,2,4,3,5]
    # 2ª iteración: stop 5 se mueve entre 1 y 2 (detour dist[1][5]+dist[5][2]-dist[1][2]=60+30-80=10 ✓)
    #   → [0,1,5,2,4,3] — todos los Gaitán agrupados antes de OtraCalle
    result, n = _reorder_no_backtrack([0, 1, 2, 3, 4, 5], _DIST_6)
    assert n == 2
    # El depósito siempre en posición 0
    assert result[0] == 0
    # OtraCalle (stop 3) debe ser el último
    assert result[-1] == 3
    # Todos los Gaitán (1,2,4,5) deben aparecer juntos antes de OtraCalle
    gaitan = set(result[1:-1])
    assert gaitan == {1, 2, 4, 5}


def test_reorder_threshold_exacto_mueve():
    # Desvío exactamente igual al umbral (20 m) → se mueve (condición ≤)
    # Tramo (1→3) con orden [0,1,3,2]:
    # dist[1][2]+dist[2][3]-dist[1][3] = 70+100-150 = 20 ≤ 20 ✓ → mueve
    dist_exact = [
        [  0, 100, 200, 300],
        [100,   0,  70, 150],
        [200,  70,   0, 100],
        [300, 150, 100,   0],
    ]
    result, n = _reorder_no_backtrack([0, 1, 3, 2], dist_exact)
    assert result == [0, 1, 2, 3]
    assert n == 1


def test_reorder_threshold_superado_no_mueve():
    # dist[1][2]+dist[2][3]-dist[1][3] = 70+101-150 = 21 > 20 → no mueve
    dist_over = [
        [  0, 100, 200, 300],
        [100,   0,  70, 150],
        [200,  70,   0, 101],
        [300, 150, 101,   0],
    ]
    result, n = _reorder_no_backtrack([0, 1, 3, 2], dist_over)
    assert result == [0, 1, 3, 2]
    assert n == 0


def test_reorder_depot_siempre_en_posicion_0():
    result, _ = _reorder_no_backtrack([0, 1, 2, 3, 4, 5], _DIST_6)
    assert result[0] == 0


def test_reorder_2_stops_sin_transiciones_previas():
    # Solo depósito + 1 parada: i=1 no tiene tramos anteriores (range(0)=[])
    dist = [[0, 500], [500, 0]]
    result, n = _reorder_no_backtrack([0, 1], dist)
    assert result == [0, 1]
    assert n == 0


def test_reorder_no_modifica_lista_original():
    original = [0, 1, 2, 3, 4]
    _reorder_no_backtrack(original, _DIST_5)
    assert original == [0, 1, 2, 3, 4]  # no muta el argumento


def test_optimize_aplica_reagrupacion(monkeypatch):
    # Orden: [0, 1, 3, 2] — stop 2 llega después de OtraCalle (stop 3)
    # Con _DIST_4 el desvío para insertar 2 entre 1 y 3 es -120 ≤ 20 → se mueve
    # Resultado esperado en waypoint_order: [0, 1, 2, 3]
    monkeypatch.setattr("app.services.routing._solve_with_lkh", lambda *_: [0, 1, 3, 2])
    with patch("app.services.routing.get_osrm_matrix", return_value=(_DIST_4, _DIST_4)):
        result = optimize_route([(37.8, -5.1)] * 4)
    assert result is not None
    assert result["waypoint_order"] == [0, 1, 2, 3]
