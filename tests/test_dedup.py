"""
Tests unitarios — normalización de direcciones.

Cubre:
  - normalize_for_dedup  (implementación canónica en app/utils/normalization.py)

Se verifica también el re-export desde validation.py para detectar
regresiones si el alias dejara de apuntar a la misma función.
"""

import pytest

from app.utils.normalization import normalize_for_dedup
from app.routers.validation import _normalize_for_dedup as _norm_val


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
        # La ñ también se descompone con NFD
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
        """El caso de uso principal: dos formas distintas de la misma dirección."""
        assert normalize_for_dedup("Calle Gaitán 24") == normalize_for_dedup("CALLE GAITAN  24,")

    def test_direcciones_distintas_no_coinciden(self):
        assert normalize_for_dedup("Calle Gaitán 24") != normalize_for_dedup("Calle Gaitán 25")

    def test_calles_distintas_no_coinciden(self):
        assert normalize_for_dedup("Calle Gaitán 24") != normalize_for_dedup("Calle Mayor 24")

    def test_reexport_validation_equivalente(self):
        """El re-export desde validation.py debe producir el mismo resultado."""
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
            assert _norm_val(caso) == normalize_for_dedup(caso), (
                f"El re-export de validation difiere para: {caso!r}\n"
                f"  normalization → {normalize_for_dedup(caso)!r}\n"
                f"  validation    → {_norm_val(caso)!r}"
            )
