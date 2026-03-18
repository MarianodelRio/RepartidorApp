"""
Tests unitarios — normalización y clave canónica de direcciones.

Cubre:
  - normalize_for_dedup  (utilidad pura en app/utils/normalization.py)
  - address_key          (clave canónica de deduplicación en geocoding.py)
  - canonical_address    (forma limpia para mostrar al usuario)
"""

from app.utils.normalization import normalize_for_dedup
from app.services.geocoding import address_key, canonical_address


# ══════════════════════════════════════════════════════════════════════
#  normalize_for_dedup
# ══════════════════════════════════════════════════════════════════════

class TestNormalizeForDedup:

    def test_pasa_a_minusculas(self):
        assert normalize_for_dedup("CALLE GAITÁN 24") == normalize_for_dedup("calle gaitán 24")

    def test_elimina_acento_a(self):
        assert normalize_for_dedup("Calle Gaitán 24") == normalize_for_dedup("Calle Gaitan 24")

    def test_elimina_acento_e(self):
        assert normalize_for_dedup("Calle José 5") == normalize_for_dedup("Calle Jose 5")

    def test_elimina_acento_i(self):
        assert normalize_for_dedup("Calle Ramón y Cajal 1") == normalize_for_dedup("Calle Ramon y Cajal 1")

    def test_elimina_eñe(self):
        assert normalize_for_dedup("Calle España 3") == normalize_for_dedup("Calle Espana 3")

    def test_colapsa_espacios_multiples(self):
        assert normalize_for_dedup("Calle  Gaitán   24") == normalize_for_dedup("Calle Gaitán 24")

    def test_elimina_espacios_extremos(self):
        assert normalize_for_dedup("  Calle Gaitán 24  ") == normalize_for_dedup("Calle Gaitán 24")

    def test_elimina_coma(self):
        assert normalize_for_dedup("Calle Gaitán, 24") == normalize_for_dedup("Calle Gaitán 24")

    def test_elimina_punto(self):
        assert normalize_for_dedup("Av. Andalucía 1") == normalize_for_dedup("Av Andalucía 1")

    def test_cadena_vacia(self):
        assert normalize_for_dedup("") == ""

    def test_solo_espacios(self):
        assert normalize_for_dedup("   ") == ""

    def test_misma_direccion_distinta_escritura(self):
        assert normalize_for_dedup("Calle Gaitán 24") == normalize_for_dedup("CALLE GAITAN  24,")

    def test_direcciones_distintas_no_coinciden(self):
        assert normalize_for_dedup("Calle Gaitán 24") != normalize_for_dedup("Calle Gaitán 25")

    def test_calles_distintas_no_coinciden(self):
        assert normalize_for_dedup("Calle Gaitán 24") != normalize_for_dedup("Calle Mayor 24")


# ══════════════════════════════════════════════════════════════════════
#  address_key — clave canónica de deduplicación
# ══════════════════════════════════════════════════════════════════════

class TestAddressKey:

    def test_misma_clave_con_y_sin_acentos(self):
        assert address_key("Calle Gaitán 24") == address_key("Calle Gaitan 24")

    def test_misma_clave_mayusculas_minusculas(self):
        assert address_key("CALLE MAYOR 1") == address_key("calle mayor 1")

    def test_misma_clave_con_coma(self):
        assert address_key("Calle Gaitán, 24") == address_key("Calle Gaitán 24")

    def test_expande_abreviatura_c_barra(self):
        """C/ y Calle producen la misma clave."""
        assert address_key("C/ Gaitán 24") == address_key("Calle Gaitán 24")

    def test_expande_abreviatura_avda(self):
        """Avda. y Avenida producen la misma clave."""
        assert address_key("Avda. Blas Infante 5") == address_key("Avenida Blas Infante 5")

    def test_elimina_sufijo_posadas(self):
        """Con y sin 'Posadas' producen la misma clave."""
        assert address_key("Calle Mayor 1, Posadas") == address_key("Calle Mayor 1")

    def test_elimina_sufijo_cordoba(self):
        assert address_key("Calle Mayor 1, Córdoba") == address_key("Calle Mayor 1")

    def test_elimina_sufijo_ciudad_y_provincia(self):
        assert address_key("Calle Mayor 1, Posadas, Córdoba") == address_key("Calle Mayor 1")

    def test_calles_distintas_dan_claves_distintas(self):
        assert address_key("Calle Mayor 1") != address_key("Calle Gaitán 1")

    def test_numeros_distintos_dan_claves_distintas(self):
        assert address_key("Calle Mayor 1") != address_key("Calle Mayor 2")


# ══════════════════════════════════════════════════════════════════════
#  canonical_address — forma canónica para mostrar al usuario
# ══════════════════════════════════════════════════════════════════════

class TestCanonicalAddress:

    def test_expande_c_barra(self):
        assert canonical_address("C/ Gaitán 24") == "Calle Gaitán 24"

    def test_expande_avda(self):
        assert canonical_address("Avda. Blas Infante 5") == "Avenida Blas Infante 5"

    def test_elimina_sufijo_posadas(self):
        assert canonical_address("Calle Mayor 1, Posadas") == "Calle Mayor 1"

    def test_elimina_sufijo_ciudad_y_provincia(self):
        assert canonical_address("Calle Gaitán 24, Posadas, Córdoba") == "Calle Gaitán 24"

    def test_sin_numero_devuelve_solo_calle(self):
        assert canonical_address("Calle Mayor") == "Calle Mayor"

    def test_direccion_ya_limpia_no_cambia(self):
        assert canonical_address("Calle Gaitán 24") == "Calle Gaitán 24"

    def test_elimina_piso_y_bloque(self):
        assert canonical_address("Calle Gaitán 24, bloque 3") == "Calle Gaitán 24"

    def test_elimina_paréntesis(self):
        assert canonical_address("Calle Gaitán 24 (antiguo 22)") == "Calle Gaitán 24"

    def test_minusculas_se_capitalizan(self):
        assert canonical_address("calle mayor 1") == "Calle Mayor 1"

    def test_mayusculas_se_normalizan(self):
        assert canonical_address("CALLE MAYOR 1") == "Calle Mayor 1"

    def test_preposicion_queda_en_minuscula(self):
        assert canonical_address("calle de la paz 3") == "Calle de la Paz 3"

    def test_avenida_con_preposicion(self):
        assert canonical_address("AVENIDA DE ANDALUCIA 5") == "Avenida de Andalucia 5"
