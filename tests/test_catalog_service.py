"""
Tests del servicio catalog.py: get_catalog().
Los ficheros de datos se redirigen a tmp_path para no tocar el disco real.
"""

import json

import app.services.catalog as cat


# ── Fixture: estado limpio y fichero en tmp ───────────────────────────────────

import pytest

@pytest.fixture(autouse=True)
def reset_catalog(tmp_path, monkeypatch):
    cat._catalog = None
    monkeypatch.setattr(cat, "_STREETS_FILE", tmp_path / "streets.json")
    yield
    cat._catalog = None


def _write_streets(path, streets: list[str]) -> None:
    path.write_text(json.dumps({"streets": streets}, ensure_ascii=False), "utf-8")


# ── get_catalog ───────────────────────────────────────────────────────────────

def test_catalogo_vacio_sin_fichero(tmp_path):
    result = cat.get_catalog()
    assert result == []


def test_catalogo_incluye_calles(tmp_path):
    _write_streets(tmp_path / "streets.json", ["Calle Mayor", "Calle Gaitán"])
    result = cat.get_catalog()
    assert "Calle Mayor" in result
    assert "Calle Gaitán" in result


def test_catalogo_devuelve_lista_completa(tmp_path):
    streets = ["Calle Hornos", "Avenida de Blas Infante", "Calle Villa"]
    _write_streets(tmp_path / "streets.json", streets)
    result = cat.get_catalog()
    assert len(result) == 3


def test_catalogo_se_cachea_en_memoria(tmp_path):
    """Segunda llamada no vuelve a leer disco."""
    _write_streets(tmp_path / "streets.json", ["Calle X"])
    cat.get_catalog()
    (tmp_path / "streets.json").unlink()
    result = cat.get_catalog()
    assert "Calle X" in result


def test_catalogo_fichero_malformado_devuelve_vacio(tmp_path):
    (tmp_path / "streets.json").write_text("no es json válido", "utf-8")
    result = cat.get_catalog()
    assert result == []
