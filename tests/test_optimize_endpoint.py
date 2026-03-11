"""
Tests del endpoint POST /api/optimize.

Se mockean: snap_to_street, optimize_route.
No se necesitan Docker ni clave de Google para ejecutar estos tests.
"""

from unittest.mock import patch

from app.core.config import DEPOT_LAT, DEPOT_LON

URL = "/api/optimize"

# ── Datos de mock reutilizables ───────────────────────────────────────────────

STOP_COORD = [37.806, -5.100]  # [lat, lon]

SOLVER_OK = {
    "waypoint_order": [0, 1],
    "stop_details": [
        {"original_index": 1, "arrival_distance": 1500.0, "arrival_duration": 300.0}
    ],
    "total_distance": 1500,
    "total_duration": 300,
    "computing_time_ms": 10,
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
    """Contexto con todos los mocks externos devolviendo éxito.

    snap_to_street se llama ahora también para el origen: devuelve las coords
    del depósito cuando recibe las coords del depósito, y (37.806, -5.100) para
    las paradas, para que los tests que comprueban stops[0]["lat"] sigan pasando.
    """
    def _snap(lat: float, lon: float, hint: str = "") -> tuple[float, float]:
        if lat == DEPOT_LAT and lon == DEPOT_LON:
            return (DEPOT_LAT, DEPOT_LON)
        return (37.806, -5.100)

    return [
        patch("app.routers.optimize.snap_to_street", side_effect=_snap),
        patch("app.routers.optimize.optimize_route", return_value=SOLVER_OK),
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

def test_solver_falla_devuelve_503(client):
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)), \
         patch("app.routers.optimize.optimize_route", return_value=None):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 503


def test_todas_las_coords_fuera_de_mapa_devuelve_400(client):
    with patch("app.routers.optimize.snap_to_street", return_value=None):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 400


# ── Ruta exitosa con coords pre-resueltas ─────────────────────────────────────

def test_ruta_simple_devuelve_200(client):
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)), \
         patch("app.routers.optimize.optimize_route", return_value=SOLVER_OK):
        r = client.post(URL, json=_req_con_coords())
    assert r.status_code == 200
    assert r.json()["success"] is True


def test_ruta_simple_contiene_origen_y_parada(client):
    mocks = _mocks_ok()
    with mocks[0], mocks[1], mocks[2]:
        r = client.post(URL, json=_req_con_coords())
    stops = r.json()["stops"]
    assert len(stops) == 2
    assert stops[0]["type"] == "origin"
    assert stops[0]["lat"] == DEPOT_LAT
    assert stops[1]["type"] == "stop"
    assert stops[1]["address"] == "Calle Mayor 1"


def test_ruta_simple_summary_correcto(client):
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)), \
         patch("app.routers.optimize.optimize_route", return_value=SOLVER_OK):
        r = client.post(URL, json=_req_con_coords())
    summary = r.json()["summary"]
    assert summary["total_stops"] == 1
    assert summary["total_packages"] == 1
    assert summary["total_distance_m"] == 1500
    assert summary["total_distance_display"] == "1.5 km"


# ── Validación de coordenadas (_validate_coord) ───────────────────────────────

from app.routers.optimize import _validate_coord  # noqa: E402


def test_validate_coord_nan_rechazado():
    import math
    assert _validate_coord(math.nan, -5.1) is not None
    assert _validate_coord(37.8, math.nan) is not None


def test_validate_coord_inf_rechazado():
    import math
    assert _validate_coord(math.inf, -5.1) is not None
    assert _validate_coord(37.8, -math.inf) is not None


def test_validate_coord_lat_fuera_rango_global():
    assert _validate_coord(200.0, -5.1) is not None
    assert _validate_coord(-91.0, -5.1) is not None


def test_validate_coord_lon_fuera_rango_global():
    assert _validate_coord(37.8, 200.0) is not None
    assert _validate_coord(37.8, -181.0) is not None


def test_validate_coord_lon_positiva_en_espana():
    # lon > 0 en zona española implica lat/lon invertidos
    err = _validate_coord(37.8, 5.1)
    assert err is not None
    assert "invertidos" in err


def test_validate_coord_lat_fuera_bbox():
    err = _validate_coord(36.0, -5.1)  # al sur del área de trabajo
    assert err is not None
    assert "área de trabajo" in err


def test_validate_coord_lon_fuera_bbox():
    err = _validate_coord(37.8, -6.0)  # al oeste del área de trabajo
    assert err is not None
    assert "área de trabajo" in err


def test_validate_coord_valida_posadas():
    assert _validate_coord(37.805503, -5.099805) is None  # depósito Posadas


def test_validate_coord_valida_rivero():
    # Cortijo Rivero, ~55 km al sur-este — debe estar dentro del bbox
    assert _validate_coord(37.55, -4.5) is None


# ── Tests HTTP con coords inválidas ───────────────────────────────────────────

def test_coord_lat_invalida_devuelve_400(client):
    """Una parada con lat=200 → todas deben tener coords válidas → 400."""
    req = {
        "addresses": ["Calle Mayor 1", "Calle Menor 2"],
        "coords": [[200.0, -5.100], [37.806, -5.100]],
        "package_counts": [1, 1],
        "client_names": ["Ana", "Luis"],
    }
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)):
        r = client.post(URL, json=req)
    assert r.status_code == 400


def test_coord_lon_positiva_devuelve_400(client):
    """lon > 0 en España (lat/lon invertidos) → 400."""
    req = {
        "addresses": ["Calle Mayor 1", "Calle Menor 2"],
        "coords": [[37.806, 5.100], [37.806, -5.100]],
        "package_counts": [1, 1],
        "client_names": ["Ana", "Luis"],
    }
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)):
        r = client.post(URL, json=req)
    assert r.status_code == 400


def test_coord_fuera_bbox_madrid_devuelve_400(client):
    """Coordenadas de Madrid (fuera del bbox de Posadas) → 400."""
    req = {
        "addresses": ["Gran Vía Madrid", "Calle Local 1"],
        "coords": [[40.4168, -3.7038], [37.806, -5.100]],
        "package_counts": [1, 1],
        "client_names": ["Externo", "Local"],
    }
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)):
        r = client.post(URL, json=req)
    assert r.status_code == 400


def test_todas_coords_invalidas_devuelve_400(client):
    """Si todas las coords son inválidas → 400."""
    req = {
        "addresses": ["Calle Mayor 1", "Calle Menor 2"],
        "coords": [[200.0, -5.1], [37.8, 5.1]],
        "package_counts": [1, 1],
        "client_names": ["Ana", "Luis"],
    }
    with patch("app.routers.optimize.snap_to_street", return_value=(37.806, -5.100)):
        r = client.post(URL, json=req)
    assert r.status_code == 400
