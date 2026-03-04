"""
Tests del servicio catalog.py: get_combined_catalog(), save_learned_street().
Los ficheros de datos se redirigen a tmp_path para no tocar el disco real.
"""

import json
import time

import pytest

import app.services.catalog as cat


# ── Fixture: estado limpio y ficheros en tmp ──────────────────────────────────

@pytest.fixture(autouse=True)
def reset_catalog(tmp_path, monkeypatch):
    cat._combined = None
    monkeypatch.setattr(cat, "_DATA_DIR", tmp_path)
    monkeypatch.setattr(cat, "_LEARNED_FILE",  tmp_path / "learned.json")
    monkeypatch.setattr(cat, "_STREETS_FILE",  tmp_path / "osm.json")
    yield
    cat._combined = None


def _write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False), "utf-8")


# ── get_combined_catalog ──────────────────────────────────────────────────────

def test_catalogo_vacio_sin_ninguna_fuente(tmp_path):
    result = cat.get_combined_catalog()
    assert result == []


def test_catalogo_incluye_calles_osm(tmp_path):
    _write_json(tmp_path / "osm.json", {
        "timestamp": time.time(),
        "streets": ["Calle Mayor", "Calle Gaitán"],
    })
    result = cat.get_combined_catalog()
    assert "Calle Mayor" in result
    assert "Calle Gaitán" in result


def test_catalogo_incluye_calles_aprendidas(tmp_path):
    _write_json(tmp_path / "learned.json", {"streets": ["Calle Aprendida"]})
    result = cat.get_combined_catalog()
    assert "Calle Aprendida" in result


def test_catalogo_combina_osm_y_aprendidas(tmp_path):
    _write_json(tmp_path / "osm.json", {"timestamp": time.time(), "streets": ["Calle OSM"]})
    _write_json(tmp_path / "learned.json", {"streets": ["Calle Aprendida"]})
    result = cat.get_combined_catalog()
    assert "Calle OSM" in result
    assert "Calle Aprendida" in result


def test_catalogo_sin_duplicados(tmp_path):
    _write_json(tmp_path / "osm.json", {"timestamp": time.time(), "streets": ["Calle Mayor"]})
    _write_json(tmp_path / "learned.json", {"streets": ["Calle Mayor"]})
    result = cat.get_combined_catalog()
    assert result.count("Calle Mayor") == 1


def test_catalogo_ordenado(tmp_path):
    _write_json(tmp_path / "osm.json", {
        "timestamp": time.time(),
        "streets": ["Calle Zorro", "Calle Ámbar", "Calle Blas"],
    })
    result = cat.get_combined_catalog()
    assert result == sorted(result)


def test_catalogo_se_cachea_en_memoria(tmp_path):
    """Segunda llamada no vuelve a leer disco."""
    _write_json(tmp_path / "osm.json", {"timestamp": time.time(), "streets": ["Calle X"]})
    cat.get_combined_catalog()
    # Borrar el fichero: si se vuelve a leer el disco daría []
    (tmp_path / "osm.json").unlink()
    result = cat.get_combined_catalog()
    assert "Calle X" in result


def test_osm_expirado_no_se_incluye(tmp_path):
    """Si osm_streets.json ha expirado, no se usa."""
    _write_json(tmp_path / "osm.json", {
        "timestamp": 0,            # expirado
        "streets": ["Calle OSM Vieja"],
    })
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
