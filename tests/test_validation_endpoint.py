"""
Tests del endpoint POST /api/validation/start y POST /api/validation/override.

La función geocode() se mockea para no necesitar clave de Google API.
"""

from unittest.mock import patch, call

COORD_OK = (37.805, -5.099)
GEOCODE_OK = (COORD_OK, "EXACT_ADDRESS")
GEOCODE_FAIL = (None, "FAILED")

URL_START = "/api/validation/start"
URL_OVERRIDE = "/api/validation/override"


def _rows(*direcciones, clientes=None, alias=None, agencia=None):
    """Helper: construye la lista rows para el body de la petición."""
    clientes = clientes or [""] * len(direcciones)
    alias = alias or [""] * len(direcciones)
    agencia = agencia or [""] * len(direcciones)
    return [
        {"cliente": c, "direccion": d, "ciudad": "Posadas", "alias": a, "agencia": ag}
        for c, d, a, ag in zip(clientes, direcciones, alias, agencia)
    ]


# ── Casos básicos ─────────────────────────────────────────────────────────────

def test_una_parada_geocodificada(client):
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK):
        r = client.post(URL_START, json={"rows": _rows("Calle Mayor 1", clientes=["Ana"])})
    assert r.status_code == 200
    data = r.json()
    assert len(data["geocoded"]) == 1
    assert len(data["failed"]) == 0
    stop = data["geocoded"][0]
    assert stop["address"] == "Calle Mayor 1"
    assert stop["confidence"] == "EXACT_ADDRESS"
    assert stop["lat"] == COORD_OK[0]
    assert stop["lon"] == COORD_OK[1]
    assert stop["client_name"] == "Ana"
    assert data["total_packages"] == 1
    assert data["unique_addresses"] == 1


def test_parada_no_geocodificada_va_a_failed(client):
    with patch("app.routers.validation.geocode", return_value=GEOCODE_FAIL):
        r = client.post(URL_START, json={"rows": _rows("Calle Inexistente 999")})
    assert r.status_code == 200
    data = r.json()
    assert len(data["geocoded"]) == 0
    assert len(data["failed"]) == 1
    assert data["failed"][0]["address"] == "Calle Inexistente 999"


def test_lista_vacia_devuelve_cero_paradas(client):
    r = client.post(URL_START, json={"rows": []})
    assert r.status_code == 200
    data = r.json()
    assert data["total_packages"] == 0
    assert data["unique_addresses"] == 0
    assert data["geocoded"] == []
    assert data["failed"] == []


# ── Deduplicación ─────────────────────────────────────────────────────────────

def test_dedup_misma_direccion_exacta(client):
    """Dos filas idénticas → 1 parada con 2 paquetes."""
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK) as mock_geo:
        r = client.post(URL_START, json={"rows": _rows(
            "Calle Mayor 1", "Calle Mayor 1",
            clientes=["Ana", "Luis"],
        )})
    assert r.status_code == 200
    data = r.json()
    assert data["total_packages"] == 2
    assert data["unique_addresses"] == 1
    assert len(data["geocoded"]) == 1
    assert data["geocoded"][0]["package_count"] == 2
    # geocode solo se llama UNA vez (dirección única)
    mock_geo.assert_called_once()


def test_dedup_misma_direccion_diferente_mayusculas(client):
    """'calle mayor 1' y 'Calle Mayor 1' son la misma parada."""
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK) as mock_geo:
        r = client.post(URL_START, json={"rows": _rows("calle mayor 1", "Calle Mayor 1")})
    assert r.status_code == 200
    data = r.json()
    assert data["unique_addresses"] == 1
    mock_geo.assert_called_once()


def test_dedup_dos_direcciones_distintas(client):
    """Dos direcciones diferentes → 2 paradas."""
    def mock_geocode(addr, alias=""):
        return GEOCODE_OK

    with patch("app.routers.validation.geocode", side_effect=mock_geocode) as mock_geo:
        r = client.post(URL_START, json={"rows": _rows("Calle Mayor 1", "Calle Gaitán 5")})
    assert r.status_code == 200
    assert r.json()["unique_addresses"] == 2
    assert mock_geo.call_count == 2


# ── Mezcla geocodificado / fallido ────────────────────────────────────────────

def test_mezcla_geocodificado_y_fallido(client):
    def mock_geocode(addr, alias=""):
        return GEOCODE_OK if "Mayor" in addr else GEOCODE_FAIL

    with patch("app.routers.validation.geocode", side_effect=mock_geocode):
        r = client.post(URL_START, json={"rows": _rows("Calle Mayor 1", "Calle Inexistente 99")})
    assert r.status_code == 200
    data = r.json()
    assert len(data["geocoded"]) == 1
    assert len(data["failed"]) == 1
    assert data["total_packages"] == 2


# ── Agencia ───────────────────────────────────────────────────────────────────

def test_agencia_se_incluye_en_paquete(client):
    """El campo agencia del CSV viaja en el Package de la parada geocodificada."""
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK):
        r = client.post(URL_START, json={"rows": _rows(
            "Calle Mayor 1", clientes=["Ana"], agencia=["MRW"],
        )})
    assert r.status_code == 200
    packages = r.json()["geocoded"][0]["packages"]
    assert packages[0]["agencia"] == "MRW"


def test_agencia_vacia_cuando_no_se_provee(client):
    """Si el CSV no tiene agencia, el campo llega vacío en el Package."""
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK):
        r = client.post(URL_START, json={"rows": _rows("Calle Mayor 1")})
    assert r.status_code == 200
    packages = r.json()["geocoded"][0]["packages"]
    assert packages[0]["agencia"] == ""


def test_agencia_distintas_en_mismo_destino(client):
    """Dos paquetes en la misma dirección pueden tener agencias distintas."""
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK):
        r = client.post(URL_START, json={"rows": [
            {"cliente": "Ana", "direccion": "Calle Mayor 1", "ciudad": "Posadas",
             "agencia": "MRW", "alias": ""},
            {"cliente": "Luis", "direccion": "Calle Mayor 1", "ciudad": "Posadas",
             "agencia": "SEUR", "alias": ""},
        ]})
    assert r.status_code == 200
    packages = r.json()["geocoded"][0]["packages"]
    assert len(packages) == 2
    agencias = {p["agencia"] for p in packages}
    assert agencias == {"MRW", "SEUR"}


# ── Alias ─────────────────────────────────────────────────────────────────────

def test_alias_se_pasa_a_geocode(client):
    captured = {}

    def mock_geocode(addr, alias=""):
        captured["alias"] = alias
        return (COORD_OK, "EXACT_PLACE")

    with patch("app.routers.validation.geocode", side_effect=mock_geocode):
        r = client.post(URL_START, json={"rows": _rows(
            "Calle Mayor 1", clientes=["Ana"], alias=["Bar El Sol"],
        )})
    assert r.status_code == 200
    assert captured["alias"] == "Bar El Sol"
    assert r.json()["geocoded"][0]["confidence"] == "EXACT_PLACE"


def test_primer_alias_no_vacio_gana_en_grupo(client):
    """En un grupo deduplicado, el primer alias no vacío se usa para todo el grupo."""
    with patch("app.routers.validation.geocode", return_value=GEOCODE_OK) as mock_geo:
        r = client.post(URL_START, json={"rows": [
            {"cliente": "Ana", "direccion": "Calle Mayor 1", "ciudad": "Posadas", "alias": ""},
            {"cliente": "Luis", "direccion": "Calle Mayor 1", "ciudad": "Posadas", "alias": "Bar El Sol"},
        ]})
    data = r.json()
    assert data["geocoded"][0]["alias"] == "Bar El Sol"
    # geocode recibe el alias del grupo
    _, kwargs = mock_geo.call_args
    assert kwargs.get("alias", mock_geo.call_args[0][1] if len(mock_geo.call_args[0]) > 1 else "") == "Bar El Sol"


# ── Override ──────────────────────────────────────────────────────────────────

def test_override_guarda_coordenadas(client):
    with patch("app.routers.validation.add_override") as mock_override:
        r = client.post(URL_OVERRIDE, json={
            "address": "Calle Mayor 1",
            "lat": 37.805,
            "lon": -5.099,
        })
    assert r.status_code == 200
    assert r.json()["ok"] is True
    mock_override.assert_called_once_with("Calle Mayor 1", 37.805, -5.099)


def test_override_devuelve_la_direccion(client):
    with patch("app.routers.validation.add_override"):
        r = client.post(URL_OVERRIDE, json={
            "address": "Calle Gaitán 3",
            "lat": 37.806,
            "lon": -5.100,
        })
    assert r.json()["address"] == "Calle Gaitán 3"
