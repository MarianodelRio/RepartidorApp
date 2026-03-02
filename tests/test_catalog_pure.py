"""
Tests unitarios — funciones puras de app/services/catalog.py.

Cubre (sin red, sin ficheros de disco):
  - _to_title_case  → convierte nombres de calles de mayúsculas a Title Case
                      respetando artículos y preposiciones (de, del, la, los…)
"""

import pytest

from app.services.catalog import _to_title_case


# ══════════════════════════════════════════════════════════════════════
#  _to_title_case
# ══════════════════════════════════════════════════════════════════════

class TestToTitleCase:

    # ── Capitalización básica ──────────────────────────────────────

    def test_una_palabra(self):
        assert _to_title_case("POSADAS") == "Posadas"

    def test_dos_palabras(self):
        assert _to_title_case("GARCIA LORCA") == "Garcia Lorca"

    def test_tres_palabras(self):
        assert _to_title_case("BLAS INFANTE PEREZ") == "Blas Infante Perez"

    def test_ya_en_minusculas(self):
        assert _to_title_case("garcia lorca") == "Garcia Lorca"

    def test_ya_en_title_case(self):
        assert _to_title_case("Garcia Lorca") == "Garcia Lorca"

    # ── Artículos y preposiciones en minúscula ─────────────────────

    def test_preposicion_de(self):
        """'de' en posición interior va en minúscula."""
        assert _to_title_case("AVENIDA DE ANDALUCIA") == "Avenida de Andalucia"

    def test_preposicion_del(self):
        assert _to_title_case("CALLE DEL RIO") == "Calle del Rio"

    def test_articulo_la(self):
        assert _to_title_case("CALLE DE LA PAZ") == "Calle de la Paz"

    def test_articulo_las(self):
        assert _to_title_case("AVENIDA DE LAS FLORES") == "Avenida de las Flores"

    def test_articulo_los(self):
        assert _to_title_case("CAMINO DE LOS PINOS") == "Camino de los Pinos"

    def test_articulo_el(self):
        assert _to_title_case("CALLE DEL EL OLIVO") == "Calle del el Olivo"

    def test_conjuncion_y(self):
        assert _to_title_case("CALLE PEDRO Y JUAN") == "Calle Pedro y Juan"

    # ── La primera palabra SIEMPRE va en mayúscula ─────────────────

    def test_primera_palabra_capitalizada_aunque_sea_articulo(self):
        """
        Aunque 'de' normalmente va en minúscula, si es la primera palabra
        del nombre debe ir en mayúscula.
        """
        result = _to_title_case("DE LA FUENTE")
        assert result[0].isupper(), f"La primera letra debe ser mayúscula, got: {result}"

    # ── Casos reales del callejero de Posadas ─────────────────────

    def test_real_garcia_lorca(self):
        assert _to_title_case("GARCIA LORCA") == "Garcia Lorca"

    def test_real_blas_infante(self):
        assert _to_title_case("BLAS INFANTE") == "Blas Infante"

    def test_real_andalucia(self):
        assert _to_title_case("ANDALUCIA") == "Andalucia"

    def test_real_calle_con_preposicion(self):
        assert _to_title_case("JOSE DE LA CALLE") == "Jose de la Calle"

    # ── Invariantes ────────────────────────────────────────────────

    def test_siempre_devuelve_string(self):
        for entrada in ["", "A", "CALLE MAYOR", "DE LA PAZ"]:
            result = _to_title_case(entrada)
            assert isinstance(result, str)

    def test_cadena_vacia(self):
        assert _to_title_case("") == ""
