"""
Tests del servicio geocoding.py: pipeline geocode(), add_override(), geocode_batch().

Se mockean las llamadas HTTP a Google y se aísla el estado global entre tests:
  - _cache y _persisted se limpian en cada test
  - _CACHE_FILE se redirige a tmp_path (no toca el disco real)
  - _osm_streets = [] para evitar carga del catálogo de calles
  - GOOGLE_API_KEY se fija a "TEST_KEY" para que las llamadas Google no se salten
"""

import pytest
from unittest.mock import patch, Mock

import app.services.geocoding as geo


# ── Fixture: estado limpio en cada test ───────────────────────────────────────

@pytest.fixture(autouse=True)
def reset_geo(tmp_path, monkeypatch):
    geo._cache.clear()
    geo._persisted.clear()
    # Catálogo vacío → _find_closest_street devuelve None sin llamadas HTTP
    monkeypatch.setattr(geo, "_osm_streets", [])
    monkeypatch.setattr(geo, "_osm_streets_norm", [])
    monkeypatch.setattr(geo, "_osm_streets_norm_set", set())
    # Ficheros de caché en directorio temporal
    monkeypatch.setattr(geo, "_CACHE_FILE", tmp_path / "cache.json")
    monkeypatch.setattr(geo, "_STREETS_FILE", tmp_path / "streets.json")
    # API key válida por defecto (tests individuales pueden sobrescribirla)
    monkeypatch.setattr(geo, "GOOGLE_API_KEY", "TEST_KEY")
    yield
    geo._cache.clear()
    geo._persisted.clear()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _google_resp(location_type: str, lat: float = 37.805, lng: float = -5.099):
    """Mock de una respuesta exitosa de Google Geocoding."""
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {
        "status": "OK",
        "results": [{"geometry": {
            "location": {"lat": lat, "lng": lng},
            "location_type": location_type,
        }}],
    }
    return m


def _places_resp(lat: float = 37.805, lng: float = -5.099):
    """Mock de una respuesta exitosa de Google Places."""
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {
        "status": "OK",
        "candidates": [{"geometry": {"location": {"lat": lat, "lng": lng}}}],
    }
    return m


def _zero_results():
    """Mock de Google sin resultados."""
    m = Mock()
    m.raise_for_status.return_value = None
    m.json.return_value = {"status": "ZERO_RESULTS", "results": []}
    return m


# ── Casos básicos ─────────────────────────────────────────────────────────────

def test_direccion_vacia_devuelve_failed():
    coord, conf = geo.geocode("")
    assert coord is None
    assert conf == "FAILED"


def test_direccion_solo_espacios_devuelve_failed():
    coord, conf = geo.geocode("   ")
    assert coord is None
    assert conf == "FAILED"


def test_formato_latlon_devuelve_override():
    coord, conf = geo.geocode("37.805,-5.099")
    assert coord == (37.805, -5.099)
    assert conf == "OVERRIDE"


def test_formato_latlon_con_espacios():
    coord, conf = geo.geocode(" 37.805 , -5.099 ")
    assert coord == (37.805, -5.099)
    assert conf == "OVERRIDE"


# ── Caché y add_override ──────────────────────────────────────────────────────

def test_add_override_persiste_en_cache():
    geo.add_override("Calle Mayor 1", 37.805, -5.099)
    coord, conf = geo.geocode("Calle Mayor 1")
    assert coord == (37.805, -5.099)
    assert conf == "OVERRIDE"


def test_override_no_llama_google():
    geo.add_override("Calle Mayor 1", 37.805, -5.099)
    with patch("app.services.geocoding.requests.get") as mock_get:
        geo.geocode("Calle Mayor 1")
        mock_get.assert_not_called()


def test_cache_hit_no_llama_google():
    """Si la dirección ya está en caché (google), no vuelve a llamar."""
    street, number = geo._parse_address("Calle Gaitán 5")
    key = geo._cache_key(street, number)
    import time
    geo._cache[key] = (37.806, -5.100)
    geo._persisted[key] = {
        "source": "google", "confidence": "EXACT_ADDRESS",
        "cached_at": time.time(),
    }
    with patch("app.services.geocoding.requests.get") as mock_get:
        coord, conf = geo.geocode("Calle Gaitán 5")
        mock_get.assert_not_called()
    assert coord == (37.806, -5.100)
    assert conf == "EXACT_ADDRESS"


def test_cache_alias_devuelve_exact_place():
    """Si el alias está en caché, lo devuelve sin Google."""
    geo._cache["@bar el sol"] = (37.806, -5.100)
    with patch("app.services.geocoding.requests.get") as mock_get:
        coord, conf = geo.geocode("Calle Mayor 1", alias="Bar El Sol")
        mock_get.assert_not_called()
    assert coord == (37.806, -5.100)
    assert conf == "EXACT_PLACE"


# ── Google Geocoding ──────────────────────────────────────────────────────────

def test_google_rooftop_devuelve_exact_address():
    with patch("app.services.geocoding.requests.get", return_value=_google_resp("ROOFTOP")):
        coord, conf = geo.geocode("Calle Mayor 1")
    assert coord is not None
    assert conf == "EXACT_ADDRESS"


def test_google_range_interpolated_devuelve_good():
    with patch("app.services.geocoding.requests.get", return_value=_google_resp("RANGE_INTERPOLATED")):
        coord, conf = geo.geocode("Calle Mayor 1")
    assert coord is not None
    assert conf == "GOOD"


def test_google_geometric_center_no_guarda_ni_devuelve_coord():
    """GEOMETRIC_CENTER no es suficientemente preciso → no se guarda, cae a FAILED."""
    with patch("app.services.geocoding.requests.get", return_value=_google_resp("GEOMETRIC_CENTER")):
        coord, conf = geo.geocode("Calle Mayor 1")
    # Sin alias → cae a FAILED
    assert coord is None
    assert conf == "FAILED"


def test_google_fuera_de_bbox_devuelve_failed():
    # Madrid: fuera del bbox de Posadas
    with patch("app.services.geocoding.requests.get",
               return_value=_google_resp("ROOFTOP", lat=40.4, lng=-3.7)):
        coord, conf = geo.geocode("Calle Mayor 1")
    assert coord is None
    assert conf == "FAILED"


def test_google_zero_results_devuelve_failed():
    with patch("app.services.geocoding.requests.get", return_value=_zero_results()):
        coord, conf = geo.geocode("Calle Inexistente 999")
    assert coord is None
    assert conf == "FAILED"


def test_google_sin_api_key_no_llama_y_devuelve_failed(monkeypatch):
    monkeypatch.setattr(geo, "GOOGLE_API_KEY", "")
    with patch("app.services.geocoding.requests.get") as mock_get:
        coord, conf = geo.geocode("Calle Mayor 1")
        mock_get.assert_not_called()
    assert coord is None
    assert conf == "FAILED"


def test_google_error_de_red_devuelve_failed():
    with patch("app.services.geocoding.requests.get", side_effect=Exception("timeout")):
        coord, conf = geo.geocode("Calle Mayor 1")
    assert coord is None
    assert conf == "FAILED"


def test_resultado_exitoso_se_guarda_en_cache():
    """Después de geocodificar con éxito, la siguiente llamada no va a Google."""
    with patch("app.services.geocoding.requests.get", return_value=_google_resp("ROOFTOP")):
        geo.geocode("Calle Mayor 1")

    with patch("app.services.geocoding.requests.get") as mock_get:
        geo.geocode("Calle Mayor 1")
        mock_get.assert_not_called()


# ── Google Places ─────────────────────────────────────────────────────────────

def test_places_con_alias_cuando_google_impreciso():
    """Con alias y Google GEOMETRIC_CENTER (impreciso), debe usar Places."""
    with patch("app.services.geocoding.requests.get") as mock_get:
        mock_get.side_effect = [
            _google_resp("GEOMETRIC_CENTER"),   # 1ª llamada: Geocoding
            _places_resp(),                     # 2ª llamada: Places
        ]
        coord, conf = geo.geocode("Calle Mayor 1", alias="Bar El Sol")
    assert coord is not None
    assert conf == "EXACT_PLACE"


def test_places_solo_se_llama_con_alias():
    """Sin alias, Places NO debe invocarse aunque Google falle."""
    with patch("app.services.geocoding.requests.get", return_value=_zero_results()) as mock_get:
        geo.geocode("Calle Inexistente 999")  # sin alias
    # Solo una llamada: Google Geocoding; Places no se invoca
    assert mock_get.call_count == 1


def test_places_fuera_de_bbox_devuelve_failed():
    with patch("app.services.geocoding.requests.get") as mock_get:
        mock_get.side_effect = [
            _google_resp("GEOMETRIC_CENTER"),
            _places_resp(lat=40.4, lng=-3.7),  # Madrid → fuera de bbox
        ]
        coord, conf = geo.geocode("Calle Mayor 1", alias="Lugar Lejano")
    assert coord is None
    assert conf == "FAILED"


def test_places_sin_api_key_no_se_llama(monkeypatch):
    monkeypatch.setattr(geo, "GOOGLE_API_KEY", "")
    with patch("app.services.geocoding.requests.get") as mock_get:
        geo.geocode("Calle Mayor 1", alias="Bar El Sol")
        mock_get.assert_not_called()


# ── Fuzzy matching ────────────────────────────────────────────────────────────

def test_fuzzy_matching_corrige_typo(monkeypatch):
    """Un typo en el nombre de calle se corrige antes de llamar a Google."""
    monkeypatch.setattr(geo, "_osm_streets", ["Calle Hornos"])
    monkeypatch.setattr(geo, "_osm_streets_norm", ["calle hornos"])
    monkeypatch.setattr(geo, "_osm_streets_norm_set", {"calle hornos"})

    with patch("app.services.geocoding.requests.get",
               return_value=_google_resp("ROOFTOP")) as mock_get:
        geo.geocode("Calle Hornoss 5")  # typo: doble 's'

    # Google debe haber sido llamado con la dirección corregida
    call_params = mock_get.call_args[1]["params"]
    assert "Calle Hornos" in call_params["address"]
    assert "Hornoss" not in call_params["address"]


def test_fuzzy_matching_no_actua_si_calle_ya_esta_en_catalogo(monkeypatch):
    """Si la calle ya está normalizada en el catálogo, no hay corrección."""
    monkeypatch.setattr(geo, "_osm_streets", ["Calle Mayor"])
    monkeypatch.setattr(geo, "_osm_streets_norm", ["calle mayor"])
    monkeypatch.setattr(geo, "_osm_streets_norm_set", {"calle mayor"})

    with patch("app.services.geocoding.requests.get",
               return_value=_google_resp("ROOFTOP")) as mock_get:
        geo.geocode("Calle Mayor 5")

    # Google llamado con "Calle Mayor" directamente (sin corrección)
    call_params = mock_get.call_args[1]["params"]
    assert "Calle Mayor" in call_params["address"]


# ── geocode_batch ─────────────────────────────────────────────────────────────

def test_geocode_batch_lista_vacia():
    assert geo.geocode_batch([]) == []


def test_geocode_batch_preserva_orden():
    geo.add_override("Calle A", 37.805, -5.099)
    geo.add_override("Calle B", 37.806, -5.100)
    result = geo.geocode_batch(["Calle A", "Calle B"])
    assert result[0] == ("Calle A", (37.805, -5.099))
    assert result[1] == ("Calle B", (37.806, -5.100))


def test_geocode_batch_fallo_devuelve_none_en_esa_posicion():
    geo.add_override("Calle A", 37.805, -5.099)
    with patch("app.services.geocoding.requests.get", return_value=_zero_results()):
        result = geo.geocode_batch(["Calle A", "Calle Inexistente 999"])
    assert result[0][1] == (37.805, -5.099)
    assert result[1][1] is None


def test_geocode_batch_todos_exitosos():
    with patch("app.services.geocoding.requests.get", return_value=_google_resp("ROOFTOP")):
        result = geo.geocode_batch(["Calle Mayor 1", "Calle Gaitán 5"])
    assert len(result) == 2
    assert all(coord is not None for _, coord in result)
