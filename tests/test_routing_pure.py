"""
Tests unitarios — funciones puras de app/services/routing.py.

Cubre (sin red, sin Docker):
  - format_distance  → formatea metros a texto legible ("500 m" / "1.5 km")
"""

import pytest

from app.services.routing import format_distance


# ══════════════════════════════════════════════════════════════════════
#  format_distance
# ══════════════════════════════════════════════════════════════════════

class TestFormatDistance:

    # ── Metros (< 1000) ────────────────────────────────────────────

    def test_cero_metros(self):
        assert format_distance(0) == "0 m"

    def test_metros_enteros(self):
        assert format_distance(500) == "500 m"

    def test_metros_maximos_antes_de_km(self):
        assert format_distance(999) == "999 m"

    def test_metros_con_decimales_trunca(self):
        """Los metros se muestran como entero, sin decimales."""
        assert format_distance(450.9) == "450 m"

    def test_metros_uno(self):
        assert format_distance(1) == "1 m"

    # ── Kilómetros (>= 1000) ───────────────────────────────────────

    def test_exactamente_un_km(self):
        assert format_distance(1000) == "1.0 km"

    def test_km_con_decimales(self):
        assert format_distance(1500) == "1.5 km"

    def test_km_redondea_un_decimal(self):
        assert format_distance(2345) == "2.3 km"

    def test_km_grandes(self):
        assert format_distance(10000) == "10.0 km"

    def test_km_muy_grande(self):
        assert format_distance(100000) == "100.0 km"

    # ── Invariantes ────────────────────────────────────────────────

    def test_siempre_devuelve_string(self):
        """format_distance siempre devuelve str, nunca None ni int."""
        for metros in [0, 1, 999, 1000, 5000]:
            result = format_distance(metros)
            assert isinstance(result, str), f"Devolvió {type(result)} para {metros} m"

    def test_metros_contiene_m(self):
        assert "m" in format_distance(100)

    def test_km_contiene_km(self):
        assert "km" in format_distance(2000)
