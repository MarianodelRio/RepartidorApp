"""
Tests unitarios — funciones puras de app/services/geocoding.py y app/utils/validation.py.

Cubre (sin red, sin caché, sin API key):
  - _normalize        → minúsculas, sin acentos, espacios simples
  - _parse_address    → extrae (calle, número) de texto libre
  - _portal_display   → extrae número primario de un rango "96-98" → "96"
  - _cache_key        → clave canónica para la caché en disco
  - in_work_bbox      → valida que una coordenada cae en el área de trabajo (comarca)
"""

import pytest

from app.services.geocoding import (
    _normalize,
    _parse_address,
    _portal_display,
    _cache_key,
)
from app.utils.validation import in_work_bbox


# ══════════════════════════════════════════════════════════════════════
#  _normalize
# ══════════════════════════════════════════════════════════════════════

class TestNormalize:

    def test_pasa_a_minusculas(self):
        assert _normalize("CALLE MAYOR") == "calle mayor"

    def test_elimina_acento_a(self):
        assert _normalize("Gaitán") == "gaitan"

    def test_elimina_acento_e(self):
        assert _normalize("José") == "jose"

    def test_elimina_acento_o(self):
        assert _normalize("Córdoba") == "cordoba"

    def test_elimina_acento_u(self):
        assert _normalize("Múnich") == "munich"

    def test_colapsa_espacios_multiples(self):
        assert _normalize("Calle  Mayor   1") == "calle mayor 1"

    def test_elimina_espacios_extremos(self):
        assert _normalize("  Calle Mayor  ") == "calle mayor"

    def test_cadena_vacia(self):
        assert _normalize("") == ""

    def test_numero_sin_texto(self):
        assert _normalize("24") == "24"

    def test_ya_normalizada_no_cambia(self):
        s = "calle gaitan 24"
        assert _normalize(s) == s


# ══════════════════════════════════════════════════════════════════════
#  _parse_address
# ══════════════════════════════════════════════════════════════════════

class TestParseAddress:

    # ── Casos básicos ──────────────────────────────────────────────

    def test_calle_con_numero(self):
        street, num = _parse_address("Calle Gaitán 24")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_avenida_con_numero(self):
        street, num = _parse_address("Avenida de Andalucía 1")
        assert street == "Avenida de Andalucía"
        assert num == "1"

    def test_plaza_con_numero(self):
        street, num = _parse_address("Plaza España 3")
        assert street == "Plaza España"
        assert num == "3"

    def test_sin_numero(self):
        street, num = _parse_address("Calle Mayor")
        assert street == "Calle Mayor"
        assert num == ""

    # ── Abreviaturas de tipo de vía ────────────────────────────────

    def test_abbrev_c_barra(self):
        """C/ debe expandirse a Calle."""
        street, num = _parse_address("C/ Gaitán 24")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_abbrev_av_punto(self):
        """Av. debe expandirse a Avenida."""
        street, num = _parse_address("Av. de Andalucía 5")
        assert street == "Avenida de Andalucía"
        assert num == "5"

    def test_abbrev_avda_sin_punto(self):
        """Avda (sin punto) se expande correctamente a Avenida."""
        street, num = _parse_address("Avda Blas Infante 10")
        assert street == "Avenida Blas Infante"
        assert num == "10"

    def test_abbrev_avda_con_punto(self):
        """Avda. (con punto) se expande correctamente a Avenida."""
        street, num = _parse_address("Avda. Blas Infante 10")
        assert street == "Avenida Blas Infante"
        assert num == "10"

    # ── Sufijo de ciudad ───────────────────────────────────────────

    def test_elimina_sufijo_posadas(self):
        street, num = _parse_address("Calle Gaitán 24, Posadas")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_sufijo_cordoba(self):
        street, num = _parse_address("Calle Gaitán 24, Córdoba")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_sufijo_ciudad_y_provincia(self):
        street, num = _parse_address("Calle Gaitán 24, Posadas, Córdoba")
        assert street == "Calle Gaitán"
        assert num == "24"

    # ── Números especiales ─────────────────────────────────────────

    def test_numero_con_letra(self):
        """Portal 24b debe conservar la letra."""
        street, num = _parse_address("Calle Gaitán 24B")
        assert street == "Calle Gaitán"
        assert num == "24b"  # se normaliza a minúscula

    def test_numero_rango(self):
        """Rango 96-98 debe mantenerse como rango."""
        street, num = _parse_address("Calle García Lorca 96-98")
        assert street == "Calle García Lorca"
        assert num == "96-98"

    def test_sin_numero_s_n(self):
        """s/n debe devolver 'sn' como número."""
        street, num = _parse_address("Calle Mayor s/n")
        assert street == "Calle Mayor"
        assert num == "sn"

    # ── Eliminación de información de piso/acceso ──────────────────

    def test_elimina_bajo(self):
        street, num = _parse_address("Calle Gaitán 24 bajo")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_piso(self):
        street, num = _parse_address("Calle Gaitán 24 2º piso")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_izda(self):
        street, num = _parse_address("Calle Gaitán 24 2º izda")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_bloque(self):
        """Información de bloque tras el número debe eliminarse."""
        street, num = _parse_address("Calle Gaitán 24, bloque 3")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_portal(self):
        street, num = _parse_address("Calle Gaitán 24, portal 2")
        assert street == "Calle Gaitán"
        assert num == "24"

    def test_elimina_escalera(self):
        street, num = _parse_address("Calle Gaitán 24 escalera B")
        assert street == "Calle Gaitán"
        assert num == "24"

    # ── Contenido entre paréntesis ─────────────────────────────────

    def test_elimina_parentesis(self):
        street, num = _parse_address("Calle Gaitán 24 (antiguo 22)")
        assert street == "Calle Gaitán"
        assert num == "24"


# ══════════════════════════════════════════════════════════════════════
#  _portal_display
# ══════════════════════════════════════════════════════════════════════

class TestPortalDisplay:

    def test_numero_simple(self):
        assert _portal_display("24") == "24"

    def test_numero_con_letra(self):
        """Para APIs externas se usa solo la parte numérica."""
        assert _portal_display("2b") == "2"

    def test_rango_devuelve_primero(self):
        """El rango 96-98 debe reducirse a 96 para consultas externas."""
        assert _portal_display("96-98") == "96"

    def test_sin_numero_devuelve_vacio(self):
        assert _portal_display("") == ""

    def test_sn_devuelve_vacio(self):
        assert _portal_display("sn") == ""

    def test_numero_grande(self):
        assert _portal_display("123") == "123"


# ══════════════════════════════════════════════════════════════════════
#  _cache_key
# ══════════════════════════════════════════════════════════════════════

class TestCacheKey:

    def test_formato_calle_hash_numero(self):
        key = _cache_key("Calle Gaitán", "24")
        assert "#" in key
        partes = key.split("#")
        assert len(partes) == 2

    def test_insensible_a_acentos(self):
        """La clave debe ser la misma con y sin acentos."""
        assert _cache_key("Calle Gaitán", "24") == _cache_key("Calle Gaitan", "24")

    def test_insensible_a_mayusculas(self):
        assert _cache_key("CALLE MAYOR", "5") == _cache_key("calle mayor", "5")

    def test_numero_vacio(self):
        key = _cache_key("Calle Mayor", "")
        assert key.endswith("#")

    def test_misma_calle_distinto_numero_son_distintas(self):
        assert _cache_key("Calle Gaitán", "24") != _cache_key("Calle Gaitán", "25")

    def test_distinta_calle_mismo_numero_son_distintas(self):
        assert _cache_key("Calle Gaitán", "24") != _cache_key("Calle Mayor", "24")


# ══════════════════════════════════════════════════════════════════════
#  in_work_bbox
# Límites comarca: lat [37.65, 37.95]  lon [-5.35, -4.90]
# ══════════════════════════════════════════════════════════════════════

class TestInWorkBbox:

    def test_centro_de_posadas(self):
        """El depósito central debe estar dentro del bbox."""
        assert in_work_bbox(37.805503, -5.099805) is True

    def test_coordenada_tipica_de_reparto(self):
        assert in_work_bbox(37.80, -5.10) is True

    def test_comarca_palma_del_rio(self):
        """Palma del Río (dentro de la comarca) debe estar dentro."""
        assert in_work_bbox(37.70, -5.28) is True

    def test_madrid_fuera(self):
        assert in_work_bbox(40.4168, -3.7038) is False

    def test_sevilla_fuera(self):
        """Sevilla: longitud demasiado oeste."""
        assert in_work_bbox(37.3886, -5.9823) is False

    def test_latitud_demasiado_alta(self):
        assert in_work_bbox(38.3, -5.10) is False

    def test_latitud_demasiado_baja(self):
        assert in_work_bbox(37.2, -5.10) is False

    def test_longitud_demasiado_este(self):
        assert in_work_bbox(37.80, -4.3) is False

    def test_longitud_demasiado_oeste(self):
        assert in_work_bbox(37.80, -5.7) is False

    def test_en_el_borde_incluido(self):
        """Los límites son inclusivos."""
        assert in_work_bbox(37.65, -5.35) is True
        assert in_work_bbox(37.95, -4.90) is True

    def test_justo_fuera_del_borde(self):
        assert in_work_bbox(37.64, -5.1) is False
        assert in_work_bbox(37.96, -5.1) is False
