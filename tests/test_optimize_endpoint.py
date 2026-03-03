"""
Tests del endpoint POST /api/optimize.

Se mockean: geocode, geocode_batch, can_osrm_snap, optimize_route, get_route_details.
No se necesitan Docker ni clave de Google para ejecutar estos tests.
"""

from unittest.mock import patch

from app.core.config import DEPOT_LAT, DEPOT_LON

URL = "/api/optimize"

# ── Datos de mock reutilizables ───────────────────────────────────────────────

STOP_COORD = [37.806, -5.100]  # [lat, lon]

VROOM_OK = {
    "waypoint_order": [0, 1],
    "stop_details": [
        {"original_index": 1, "arrival_distance": 1500.0, "arrival_duration": 300.0}
    ],
    "total_distance": 1500,
    "total_duration": 300,
    "computing_time_ms": 10,
}

OSRM_OK = {
    "geometry": {"type": "LineString", "coordinates": [[-5.099805, 37.805503], [-5.100, 37.806]]},
    "total_distance": 1500,
    "total_duration": 300,
}

# Petición mínima con coords pre-resueltas (evita geocodificación)
def _req_con_coords(addresses=None, coords=None, clientes=None):
    addresses = addresses or ["Calle Mayor 1"]
    coords = coords or [STOP_COORD]
    clientes = clientes or ["Ana"]
    return {
        "addresses": addresses,
        "coords": coords,
        "package_counts": [1] * len(addresses),
        "client_names": clientes,
    }


def _mocks_ok():
    """Contexto con todos los mocks externos devolviendo éxito."""
    return [
        patch("app.routers.optimize.can_osrm_snap", return_value=True),
        patch("app.routers.optimize.optimize_route", return_value=VROOM_OK),
        patch("app.routers.optimize.get_route_details", return_value=OSRM_OK),
    ]


# ── Validaciones de entrada ────────────────────────────────────────────────────

def test_lista_vacia_devuelve_400(client):
    r = client.post(URL, json={"addresses": []})
    # FastAPI valida min_length=1 antes de llegar al handler
    assert r.status_code == 422


def test_demasiadas_paradas_devuelve_400(client):
    addresses = [f"Calle {i}" for i in range(201)]
    coords = [[37.805, -5.099]] * 201
    counts = [1] * 201
    r = client.post(URL, json={
        "addresses": addresses,
        "coords": coords,
        "package_counts": counts,
    })
    assert r.status_code == 400


# ── Errores de servicios externos ─────────────────────────────────────────────

def test_vroom_caido_devuelve_503(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=None), \
         patch("app.routers.optimize.get_route_details", return_value=OSRM_OK):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 503


def test_osrm_caido_devuelve_503(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=VROOM_OK), \
         patch("app.routers.optimize.get_route_details", return_value=None):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 503


def test_todas_las_coords_fuera_de_mapa_devuelve_400(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=False):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 400


# ── Ruta exitosa con coords pre-resueltas ─────────────────────────────────────

def test_ruta_simple_devuelve_200(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=VROOM_OK), \
         patch("app.routers.optimize.get_route_details", return_value=OSRM_OK):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 200
    assert r.json()["success"] is True


def test_ruta_simple_contiene_origen_y_parada(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=VROOM_OK), \
         patch("app.routers.optimize.get_route_details", return_value=OSRM_OK):
        r = client.post(URL, json=_req_con_coords())
    stops = r.json()["stops"]
    assert len(stops) == 2
    assert stops[0]["type"] == "origin"
    assert stops[0]["lat"] == DEPOT_LAT
    assert stops[1]["type"] == "stop"
    assert stops[1]["address"] == "Calle Mayor 1"


def test_ruta_simple_summary_correcto(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=VROOM_OK), \
         patch("app.routers.optimize.get_route_details", return_value=OSRM_OK):
        r = client.post(URL, json=_req_con_coords())
    summary = r.json()["summary"]
    assert summary["total_stops"] == 1
    assert summary["total_packages"] == 1
    assert summary["total_distance_m"] == 1500
    assert summary["total_distance_display"] == "1.5 km"


def test_ruta_simple_incluye_geometry(client):
    with patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=VROOM_OK), \
         patch("app.routers.optimize.get_route_details", return_value=OSRM_OK):
        r = client.post(URL, json=_req_con_coords())
    assert r.json()["geometry"]["type"] == "LineString"


# ── Ruta con geocodificación (sin coords pre-resueltas) ───────────────────────

def test_ruta_sin_coords_usa_geocode_batch(client):
    batch_result = [("Calle Mayor 1", (37.806, -5.100))]
    with patch("app.routers.optimize.geocode_batch", return_value=batch_result), \
         patch("app.routers.optimize.can_osrm_snap", return_value=True), \
         patch("app.routers.optimize.optimize_route", return_value=VROOM_OK), \
         patch("app.routers.optimize.get_route_details", return_value=OSRM_OK):
        r = client.post(URL, json={"addresses": ["Calle Mayor 1"]})
    assert r.status_code == 200


def test_geocode_batch_falla_todo_devuelve_400(client):
    batch_result = [("Calle Mayor 1", None)]
    with patch("app.routers.optimize.geocode_batch", return_value=batch_result):
        r = client.post(URL, json={"addresses": ["Calle Mayor 1"]})
    assert r.status_code == 400
