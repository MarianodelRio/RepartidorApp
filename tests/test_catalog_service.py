"""
Tests del servicio catalog.py: get_combined_catalog(), save_learned_street().
Los ficheros de datos se redirigen a tmp_path para no tocar el disco real.
"""

import json
import time

import pytest
from unittest.mock import patch

import app.services.catalog as cat


# ── Fixture: estado limpio y ficheros en tmp ──────────────────────────────────

@pytest.fixture(autouse=True)
def reset_catalog(tmp_path, monkeypatch):
    cat._combined = None
    monkeypatch.setattr(cat, "_DATA_DIR", tmp_path)
    monkeypatch.setattr(cat, "_CATASTRO_FILE", tmp_path / "catastro.json")
    monkeypatch.setattr(cat, "_LEARNED_FILE",  tmp_path / "learned.json")
    monkeypatch.setattr(cat, "_STREETS_FILE",  tmp_path / "osm.json")
    yield
    cat._combined = None


def _write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False), "utf-8")


# ── get_combined_catalog ──────────────────────────────────────────────────────

def test_catalogo_vacio_sin_ninguna_fuente(tmp_path):
    with patch.object(cat, "_fetch_catastro_streets", return_value=[]):
        result = cat.get_combined_catalog()
    assert result == []


def test_catalogo_incluye_calles_osm(tmp_path):
    _write_json(tmp_path / "osm.json", {
        "timestamp": time.time(),
        "streets": ["Calle Mayor", "Calle Gaitán"],
    })
    with patch.object(cat, "_fetch_catastro_streets", return_value=[]):
        result = cat.get_combined_catalog()
    assert "Calle Mayor" in result
    assert "Calle Gaitán" in result


def test_catalogo_incluye_calles_catastro(tmp_path):
    with patch.object(cat, "_fetch_catastro_streets", return_value=["Avenida Blas Infante"]):
        result = cat.get_combined_catalog()
    assert "Avenida Blas Infante" in result


def test_catalogo_incluye_calles_aprendidas(tmp_path):
    _write_json(tmp_path / "learned.json", {"streets": ["Calle Aprendida"]})
    with patch.object(cat, "_fetch_catastro_streets", return_value=[]):
        result = cat.get_combined_catalog()
    assert "Calle Aprendida" in result


def test_catalogo_combina_todas_las_fuentes(tmp_path):
    _write_json(tmp_path / "osm.json", {"timestamp": time.time(), "streets": ["Calle OSM"]})
    _write_json(tmp_path / "learned.json", {"streets": ["Calle Aprendida"]})
    with patch.object(cat, "_fetch_catastro_streets", return_value=["Calle Catastro"]):
        result = cat.get_combined_catalog()
    assert "Calle OSM" in result
    assert "Calle Catastro" in result
    assert "Calle Aprendida" in result


def test_catalogo_sin_duplicados(tmp_path):
    _write_json(tmp_path / "osm.json", {"timestamp": time.time(), "streets": ["Calle Mayor"]})
    _write_json(tmp_path / "learned.json", {"streets": ["Calle Mayor"]})
    with patch.object(cat, "_fetch_catastro_streets", return_value=["Calle Mayor"]):
        result = cat.get_combined_catalog()
    assert result.count("Calle Mayor") == 1


def test_catalogo_ordenado(tmp_path):
    _write_json(tmp_path / "osm.json", {
        "timestamp": time.time(),
        "streets": ["Calle Zorro", "Calle Ámbar", "Calle Blas"],
    })
    with patch.object(cat, "_fetch_catastro_streets", return_value=[]):
        result = cat.get_combined_catalog()
    assert result == sorted(result)


def test_catalogo_se_cachea_en_memoria(tmp_path):
    """Segunda llamada no vuelve a leer disco ni llamar a _fetch_catastro_streets."""
    with patch.object(cat, "_fetch_catastro_streets", return_value=["Calle X"]) as mock_fetch:
        cat.get_combined_catalog()
        cat.get_combined_catalog()
    mock_fetch.assert_called_once()


def test_catastro_disco_evita_descarga(tmp_path):
    """Si catastro.json está en disco y no ha expirado, no descarga."""
    _write_json(tmp_path / "catastro.json", {
        "timestamp": time.time(),
        "streets": ["Calle del Catastro"],
    })
    with patch.object(cat, "_fetch_catastro_streets") as mock_fetch:
        result = cat.get_combined_catalog()
    mock_fetch.assert_not_called()
    assert "Calle del Catastro" in result


def test_catastro_expirado_descarga_de_nuevo(tmp_path):
    """Si catastro.json ha expirado (timestamp antiguo), lo descarga de nuevo."""
    _write_json(tmp_path / "catastro.json", {
        "timestamp": 0,            # timestamp en epoch = expirado
        "streets": ["Calle Vieja"],
    })
    with patch.object(cat, "_fetch_catastro_streets", return_value=["Calle Nueva"]) as mock_fetch:
        result = cat.get_combined_catalog()
    mock_fetch.assert_called_once()
    assert "Calle Nueva" in result


def test_osm_expirado_no_se_incluye(tmp_path):
    """Si osm_streets.json ha expirado, no se usa."""
    _write_json(tmp_path / "osm.json", {
        "timestamp": 0,            # expirado
        "streets": ["Calle OSM Vieja"],
    })
    with patch.object(cat, "_fetch_catastro_streets", return_value=[]):
        result = cat.get_combined_catalog()
    assert "Calle OSM Vieja" not in result


# ── save_learned_street ───────────────────────────────────────────────────────

def test_save_learned_street_crea_fichero(tmp_path):
    cat.save_learned_street("Calle Nueva")
    assert (tmp_path / "learned.json").exists()


def test_save_learned_street_persiste(tmp_path):
    cat.save_learned_street("Calle Nueva")
    data = json.loads((tmp_path / "learned.json").read_text())
    assert "Calle Nueva" in data["streets"]


def test_save_learned_street_no_duplica(tmp_path):
    cat.save_learned_street("Calle Nueva")
    cat.save_learned_street("Calle Nueva")
    data = json.loads((tmp_path / "learned.json").read_text())
    assert data["streets"].count("Calle Nueva") == 1


def test_save_learned_street_acumula_varias(tmp_path):
    cat.save_learned_street("Calle A")
    cat.save_learned_street("Calle B")
    data = json.loads((tmp_path / "learned.json").read_text())
    assert "Calle A" in data["streets"]
    assert "Calle B" in data["streets"]


def test_save_learned_street_invalida_cache_en_memoria():
    cat._combined = ["Calle Vieja"]
    cat.save_learned_street("Calle Nueva")
    assert cat._combined is None
