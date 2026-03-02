"""
Tests unitarios — normalización y deduplicación de direcciones.

Cubre:
  - _normalize_for_dedup  (app/routers/validation.py y app/routers/optimize.py)
  - _group_duplicate_addresses  (app/routers/optimize.py)

Nota: _normalize_for_dedup está duplicada en ambos routers con código idéntico.
      Se testea contra las dos implementaciones para detectar divergencias futuras.
"""

import pytest

from app.routers.validation import _normalize_for_dedup as _norm_val
from app.routers.optimize import _normalize_for_dedup as _norm_opt, _group_duplicate_addresses
from app.models import Package


# ══════════════════════════════════════════════════════════════════════
#  Fixture: ejecuta cada test contra las dos copias de la función
# ══════════════════════════════════════════════════════════════════════

@pytest.fixture(params=[_norm_val, _norm_opt], ids=["validation", "optimize"])
def normalize(request):
    """Parametriza los tests para ejecutarse con ambas implementaciones."""
    return request.param


# ══════════════════════════════════════════════════════════════════════
#  _normalize_for_dedup
# ══════════════════════════════════════════════════════════════════════

class TestNormalizeForDedup:

    def test_pasa_a_minusculas(self, normalize):
        assert normalize("CALLE GAITÁN 24") == normalize("calle gaitán 24")

    def test_elimina_acento_a(self, normalize):
        assert normalize("Calle Gaitán 24") == normalize("Calle Gaitan 24")

    def test_elimina_acento_e(self, normalize):
        assert normalize("Calle José 5") == normalize("Calle Jose 5")

    def test_elimina_acento_i(self, normalize):
        assert normalize("Calle Ramón y Cajal 1") == normalize("Calle Ramon y Cajal 1")

    def test_elimina_eñe(self, normalize):
        # La ñ también se descompone con NFD
        assert normalize("Calle España 3") == normalize("Calle Espana 3")

    def test_colapsa_espacios_multiples(self, normalize):
        assert normalize("Calle  Gaitán   24") == normalize("Calle Gaitán 24")

    def test_elimina_espacios_extremos(self, normalize):
        assert normalize("  Calle Gaitán 24  ") == normalize("Calle Gaitán 24")

    def test_elimina_coma(self, normalize):
        assert normalize("Calle Gaitán, 24") == normalize("Calle Gaitán 24")

    def test_elimina_punto(self, normalize):
        assert normalize("Av. Andalucía 1") == normalize("Av Andalucía 1")

    def test_cadena_vacia(self, normalize):
        assert normalize("") == ""

    def test_solo_espacios(self, normalize):
        assert normalize("   ") == ""

    def test_misma_direccion_distinta_escritura(self, normalize):
        """El caso de uso principal: dos formas distintas de la misma dirección."""
        assert normalize("Calle Gaitán 24") == normalize("CALLE GAITAN  24,")

    def test_direcciones_distintas_no_coinciden(self, normalize):
        assert normalize("Calle Gaitán 24") != normalize("Calle Gaitán 25")

    def test_calles_distintas_no_coinciden(self, normalize):
        assert normalize("Calle Gaitán 24") != normalize("Calle Mayor 24")

    def test_ambas_implementaciones_producen_lo_mismo(self):
        """Las dos copias de la función deben ser siempre equivalentes."""
        casos = [
            "Calle Gaitán 24",
            "Avenida de Andalucía 1",
            "C/ Mayor, 5",
            "PLAZA ESPAÑA 3",
            "",
            "  CALLE  REAL  37  ",
            "Calle José María 12",
        ]
        for caso in casos:
            assert _norm_val(caso) == _norm_opt(caso), (
                f"Las dos implementaciones difieren para: {caso!r}\n"
                f"  validation → {_norm_val(caso)!r}\n"
                f"  optimize   → {_norm_opt(caso)!r}"
            )


# ══════════════════════════════════════════════════════════════════════
#  _group_duplicate_addresses
# ══════════════════════════════════════════════════════════════════════

class TestGroupDuplicateAddresses:

    def _pkg(self, name: str) -> Package:
        return Package(client_name=name)

    def test_lista_vacia(self):
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses([], [])
        assert addrs == []
        assert counts == []

    def test_una_direccion(self):
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24"],
            [self._pkg("Juan")],
        )
        assert addrs == ["Calle Gaitán 24"]
        assert names == ["Juan"]
        assert counts == [1]

    def test_dos_direcciones_distintas(self):
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24", "Calle Mayor 5"],
            [self._pkg("Juan"), self._pkg("María")],
        )
        assert len(addrs) == 2
        assert counts == [1, 1]

    def test_dos_direcciones_identicas_se_fusionan(self):
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24", "Calle Gaitán 24"],
            [self._pkg("Juan"), self._pkg("María")],
        )
        assert len(addrs) == 1
        assert counts == [2]

    def test_duplicado_por_diferencia_de_mayusculas(self):
        """'calle gaitán 24' y 'CALLE GAITAN 24' deben fusionarse."""
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24", "CALLE GAITAN 24"],
            [self._pkg("Juan"), self._pkg("María")],
        )
        assert len(addrs) == 1
        assert counts == [2]

    def test_duplicado_por_coma_extra(self):
        """'Calle Gaitán, 24' y 'Calle Gaitán 24' deben fusionarse."""
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán, 24", "Calle Gaitán 24"],
            [self._pkg("Juan"), self._pkg("María")],
        )
        assert len(addrs) == 1
        assert counts == [2]

    def test_nombre_primario_es_el_primero_no_vacio(self):
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24", "Calle Gaitán 24"],
            [self._pkg("Juan"), self._pkg("María")],
        )
        assert names[0] == "Juan"

    def test_nombre_primario_salta_vacios(self):
        """Si el primero no tiene nombre, usa el siguiente que sí tenga."""
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24", "Calle Gaitán 24"],
            [self._pkg(""), self._pkg("María")],
        )
        assert names[0] == "María"

    def test_all_client_names_contiene_todos(self):
        addrs, names, all_names, pkgs, counts = _group_duplicate_addresses(
            ["Calle Gaitán 24", "Calle Gaitán 24"],
            [self._pkg("Juan"), self._pkg("María")],
        )
        assert set(all_names[0]) == {"Juan", "María"}

    def test_no_se_pierden_paquetes(self):
        """El total de paquetes de salida debe ser igual al de entrada."""
        addresses = ["Calle A 1", "Calle A 1", "Calle B 2", "Calle C 3", "Calle C 3"]
        packages = [self._pkg(f"Cliente {i}") for i in range(5)]
        _, _, _, pkgs_out, counts = _group_duplicate_addresses(addresses, packages)
        assert sum(counts) == len(addresses)

    def test_preserva_orden_de_aparicion(self):
        """Las direcciones únicas deben aparecer en el orden en que se vieron."""
        addrs, _, _, _, _ = _group_duplicate_addresses(
            ["Calle Z 1", "Calle A 2", "Calle M 3"],
            [self._pkg("a"), self._pkg("b"), self._pkg("c")],
        )
        assert addrs == ["Calle Z 1", "Calle A 2", "Calle M 3"]

    def test_tres_grupos_con_duplicados(self):
        """Verifica counts correctos con tres grupos de distintos tamaños."""
        addresses = [
            "Calle A 1", "Calle A 1",          # grupo 1: 2
            "Calle B 2",                         # grupo 2: 1
            "Calle C 3", "Calle C 3", "Calle C 3",  # grupo 3: 3
        ]
        packages = [self._pkg(f"P{i}") for i in range(6)]
        addrs, _, _, _, counts = _group_duplicate_addresses(addresses, packages)
        assert len(addrs) == 3
        assert counts == [2, 1, 3]
