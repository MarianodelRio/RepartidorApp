"""
Tests del servicio routing.py: can_osrm_snap, optimize_route, get_route_details.
Se mockean las llamadas HTTP a OSRM y VROOM.
"""

from unittest.mock import patch, Mock

from app.services.routing import can_osrm_snap, optimize_route, get_route_details

COORDS_2 = [(37.805, -5.099), (37.806, -5.100)]
COORDS_3 = [(37.805, -5.099), (37.806, -5.100), (37.807, -5.101)]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _mock_nearest(distance_m: float):
    m = Mock()
    m.json.return_value = {"code": "Ok", "waypoints": [{"distance": distance_m}]}
    return m


def _mock_vroom(steps=None, code=0, distance=1500, duration=300):
    if steps is None:
        steps = [
            {"type": "start"},
            {"type": "job", "id": 1, "distance": distance, "duration": duration},
            {"type": "end"},
        ]
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {
        "code": code,
        "routes": [{"distance": distance, "duration": duration, "steps": steps}],
        "summary": {"computing_times": {"solving": 10}},
    }
    return m


def _mock_osrm(code="Ok", distance=1500, duration=300):
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


# ── can_osrm_snap ─────────────────────────────────────────────────────────────

def test_snap_dentro_de_rango():
    with patch("app.services.routing.requests.get", return_value=_mock_nearest(100)):
        assert can_osrm_snap(37.805, -5.099) is True


def test_snap_fuera_de_rango():
    with patch("app.services.routing.requests.get", return_value=_mock_nearest(600)):
        assert can_osrm_snap(37.805, -5.099) is False


def test_snap_en_limite_exacto():
    # 500 m es el límite → True
    with patch("app.services.routing.requests.get", return_value=_mock_nearest(500)):
        assert can_osrm_snap(37.805, -5.099) is True


def test_snap_justo_por_encima_del_limite():
    with patch("app.services.routing.requests.get", return_value=_mock_nearest(501)):
        assert can_osrm_snap(37.805, -5.099) is False


def test_snap_osrm_caido():
    with patch("app.services.routing.requests.get", side_effect=Exception("timeout")):
        assert can_osrm_snap(37.805, -5.099) is False


def test_snap_respuesta_sin_waypoints():
    m = Mock()
    m.json.return_value = {"code": "Ok", "waypoints": []}
    with patch("app.services.routing.requests.get", return_value=m):
        assert can_osrm_snap(37.805, -5.099) is False


def test_snap_respuesta_error_code():
    m = Mock()
    m.json.return_value = {"code": "Error"}
    with patch("app.services.routing.requests.get", return_value=m):
        assert can_osrm_snap(37.805, -5.099) is False


# ── optimize_route ────────────────────────────────────────────────────────────

def test_optimize_menos_de_2_coords_devuelve_none():
    assert optimize_route([(37.805, -5.099)]) is None


def test_optimize_devuelve_orden_correcto():
    with patch("app.services.routing.requests.post", return_value=_mock_vroom()):
        result = optimize_route(COORDS_2)
    assert result is not None
    assert result["waypoint_order"] == [0, 1]


def test_optimize_3_paradas_orden_correcto():
    steps = [
        {"type": "start"},
        {"type": "job", "id": 2, "distance": 800, "duration": 120},
        {"type": "job", "id": 1, "distance": 700, "duration": 110},
        {"type": "end"},
    ]
    with patch("app.services.routing.requests.post", return_value=_mock_vroom(steps=steps)):
        result = optimize_route(COORDS_3)
    assert result["waypoint_order"] == [0, 2, 1]


def test_optimize_devuelve_distancia_total():
    with patch("app.services.routing.requests.post", return_value=_mock_vroom(distance=2500)):
        result = optimize_route(COORDS_2)
    assert result["total_distance"] == 2500


def test_optimize_stop_details_arrival_distance_acumulada():
    steps = [
        {"type": "start"},
        {"type": "job", "id": 1, "distance": 800, "duration": 100},
        {"type": "job", "id": 2, "distance": 700, "duration": 90},
        {"type": "end"},
    ]
    with patch("app.services.routing.requests.post", return_value=_mock_vroom(steps=steps)):
        result = optimize_route(COORDS_3)
    details = result["stop_details"]
    assert details[0]["arrival_distance"] == 800
    assert details[1]["arrival_distance"] == 1500   # acumulada: 800 + 700


def test_optimize_vroom_error_code_devuelve_none():
    with patch("app.services.routing.requests.post", return_value=_mock_vroom(code=1)):
        assert optimize_route(COORDS_2) is None


def test_optimize_vroom_caido_devuelve_none():
    with patch("app.services.routing.requests.post", side_effect=Exception("connection refused")):
        assert optimize_route(COORDS_2) is None


def test_optimize_vroom_http_error_devuelve_none():
    from requests.exceptions import HTTPError
    m = Mock()
    resp = Mock(status_code=500, text="Internal Server Error")
    m.raise_for_status.side_effect = HTTPError(response=resp)
    with patch("app.services.routing.requests.post", return_value=m):
        assert optimize_route(COORDS_2) is None


# ── get_route_details ─────────────────────────────────────────────────────────

def test_route_details_menos_de_2_coords_devuelve_none():
    assert get_route_details([(37.805, -5.099)]) is None


def test_route_details_devuelve_geometry():
    with patch("app.services.routing.requests.get", return_value=_mock_osrm()):
        result = get_route_details(COORDS_2)
    assert result is not None
    assert result["geometry"]["type"] == "LineString"


def test_route_details_devuelve_distancia():
    with patch("app.services.routing.requests.get", return_value=_mock_osrm(distance=3200)):
        result = get_route_details(COORDS_2)
    assert result["total_distance"] == 3200


def test_route_details_osrm_error_code_devuelve_none():
    with patch("app.services.routing.requests.get", return_value=_mock_osrm(code="Error")):
        assert get_route_details(COORDS_2) is None


def test_route_details_osrm_caido_devuelve_none():
    with patch("app.services.routing.requests.get", side_effect=Exception("timeout")):
        assert get_route_details(COORDS_2) is None


def test_route_details_3_puntos():
    with patch("app.services.routing.requests.get", return_value=_mock_osrm()):
        result = get_route_details(COORDS_3)
    assert result is not None
