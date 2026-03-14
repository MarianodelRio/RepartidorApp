"""
Tests puros del servicio map_editor.
No requieren osmium, ficheros PBF ni servicios externos.
Cubren las funciones internas que operan sobre estructuras de datos.
"""

import xml.etree.ElementTree as ET

import pytest

from app.services.map_editor import (
    _barrier_type,
    _build_patched_tags,
    _find_restriction_relation,
    _make_sub_way,
    _next_available_id,
)


# ═══════════════════════════════════════════
#  _build_patched_tags
# ═══════════════════════════════════════════

class TestBuildPatchedTags:
    _orig = [("highway", "residential"), ("name", "Calle Mayor"), ("maxspeed", "30")]

    def test_highway_cambiado(self) -> None:
        result = dict(_build_patched_tags(self._orig, {"highway": "tertiary"}))
        assert result["highway"] == "tertiary"

    def test_otros_tags_intactos_tras_cambio_highway(self) -> None:
        result = dict(_build_patched_tags(self._orig, {"highway": "tertiary"}))
        assert result["name"] == "Calle Mayor"
        assert result["maxspeed"] == "30"

    def test_oneway_anadido(self) -> None:
        result = dict(_build_patched_tags(self._orig, {"highway": "residential", "oneway": "yes"}))
        assert result["oneway"] == "yes"

    def test_oneway_eliminado_con_none(self) -> None:
        orig = [("highway", "residential"), ("oneway", "yes")]
        result = dict(_build_patched_tags(orig, {"highway": "residential", "oneway": None}))
        assert "oneway" not in result

    def test_oneway_invertido(self) -> None:
        orig = [("highway", "residential"), ("oneway", "yes")]
        result = dict(_build_patched_tags(orig, {"highway": "residential", "oneway": "-1"}))
        assert result["oneway"] == "-1"

    def test_name_cambiado(self) -> None:
        result = dict(_build_patched_tags(self._orig, {"highway": "residential", "name": "Calle Nueva"}))
        assert result["name"] == "Calle Nueva"

    def test_name_eliminado_con_none(self) -> None:
        result = dict(_build_patched_tags(self._orig, {"highway": "residential", "name": None}))
        assert "name" not in result

    def test_name_no_cambia_si_key_ausente(self) -> None:
        """Si 'name' no está en el change dict, el nombre original no se toca."""
        result = dict(_build_patched_tags(self._orig, {"highway": "residential"}))
        assert result["name"] == "Calle Mayor"

    def test_tags_extra_preservados(self) -> None:
        """Tags distintos de highway/oneway/name se preservan siempre."""
        result = dict(_build_patched_tags(self._orig, {"highway": "residential"}))
        assert result["maxspeed"] == "30"

    def test_change_vacio_devuelve_copia(self) -> None:
        result = _build_patched_tags(self._orig, {})
        assert dict(result) == dict(self._orig)


# ═══════════════════════════════════════════
#  _barrier_type
# ═══════════════════════════════════════════

class TestBarrierType:
    # — tipo bollard —
    def test_bollard(self) -> None:
        assert _barrier_type({"barrier": "bollard"}) == "bollard"

    def test_block(self) -> None:
        assert _barrier_type({"barrier": "block"}) == "bollard"

    def test_jersey_barrier(self) -> None:
        assert _barrier_type({"barrier": "jersey_barrier"}) == "bollard"

    def test_log(self) -> None:
        assert _barrier_type({"barrier": "log"}) == "bollard"

    def test_planter(self) -> None:
        assert _barrier_type({"barrier": "planter"}) == "bollard"

    # — tipo gate —
    def test_gate(self) -> None:
        assert _barrier_type({"barrier": "gate"}) == "gate"

    def test_lift_gate(self) -> None:
        assert _barrier_type({"barrier": "lift_gate"}) == "gate"

    def test_swing_gate(self) -> None:
        assert _barrier_type({"barrier": "swing_gate"}) == "gate"

    # — tipo noaccess —
    def test_access_no(self) -> None:
        assert _barrier_type({"access": "no"}) == "noaccess"

    def test_access_no_con_barrier_desconocida(self) -> None:
        assert _barrier_type({"barrier": "fence", "access": "no"}) == "noaccess"

    # — sin barrera —
    def test_dict_vacio(self) -> None:
        assert _barrier_type({}) is None

    def test_barrier_desconocida(self) -> None:
        assert _barrier_type({"barrier": "fence"}) is None

    def test_tags_irrelevantes(self) -> None:
        assert _barrier_type({"name": "algo", "highway": "footway"}) is None


# ═══════════════════════════════════════════
#  _next_available_id
# ═══════════════════════════════════════════

class TestNextAvailableId:
    def test_devuelve_max_mas_uno(self) -> None:
        root = ET.Element("osm")
        for i in (100, 200, 50):
            ET.SubElement(root, "way").set("id", str(i))
        assert _next_available_id(root) == 201

    def test_sin_elementos_devuelve_default(self) -> None:
        root = ET.Element("osm")
        assert _next_available_id(root) == 1_000_001

    def test_cuenta_nodos_y_relaciones(self) -> None:
        root = ET.Element("osm")
        ET.SubElement(root, "node").set("id", "500")
        ET.SubElement(root, "way").set("id", "300")
        ET.SubElement(root, "relation").set("id", "700")
        assert _next_available_id(root) == 701

    def test_elemento_unico(self) -> None:
        root = ET.Element("osm")
        ET.SubElement(root, "way").set("id", "42")
        assert _next_available_id(root) == 43


# ═══════════════════════════════════════════
#  _make_sub_way
# ═══════════════════════════════════════════

class TestMakeSubWay:
    def _original_way(self) -> ET.Element:
        w = ET.Element("way", id="1000", version="3", timestamp="2024-01-01T00:00:00Z")
        for ref in ("1", "2", "3"):
            ET.SubElement(w, "nd", ref=ref)
        ET.SubElement(w, "tag", k="highway", v="residential")
        ET.SubElement(w, "tag", k="name",    v="Calle Mayor")
        return w

    def test_nuevo_id_asignado(self) -> None:
        sub = _make_sub_way(self._original_way(), "9999", ["1", "2"], [("highway", "residential")])
        assert sub.get("id") == "9999"

    def test_atributos_originales_preservados(self) -> None:
        sub = _make_sub_way(self._original_way(), "9999", ["1", "2"], [])
        assert sub.get("version") == "3"
        assert sub.get("timestamp") == "2024-01-01T00:00:00Z"

    def test_id_original_no_copiado(self) -> None:
        """El id del original no debe aparecer como atributo extra."""
        sub = _make_sub_way(self._original_way(), "9999", ["1", "2"], [])
        assert sub.get("id") == "9999"

    def test_nd_refs_correctos(self) -> None:
        sub = _make_sub_way(self._original_way(), "9999", ["2", "3"], [("highway", "residential")])
        refs = [nd.get("ref") for nd in sub.findall("nd")]
        assert refs == ["2", "3"]

    def test_tags_asignados(self) -> None:
        tags = [("highway", "tertiary"), ("oneway", "yes")]
        sub = _make_sub_way(self._original_way(), "9999", ["1", "2"], tags)
        tag_dict = {t.get("k"): t.get("v") for t in sub.findall("tag")}
        assert tag_dict == {"highway": "tertiary", "oneway": "yes"}

    def test_sin_tags(self) -> None:
        sub = _make_sub_way(self._original_way(), "9999", ["1", "2"], [])
        assert sub.findall("tag") == []


# ═══════════════════════════════════════════
#  _find_restriction_relation
# ═══════════════════════════════════════════

class TestFindRestrictionRelation:
    def _root_with_restriction(
        self, from_id: str, via_ref: str, to_id: str
    ) -> ET.Element:
        root = ET.Element("osm")
        rel = ET.SubElement(root, "relation", id="9001")
        ET.SubElement(rel, "member", type="way",  ref=from_id, role="from")
        ET.SubElement(rel, "member", type="node", ref=via_ref, role="via")
        ET.SubElement(rel, "member", type="way",  ref=to_id,   role="to")
        ET.SubElement(rel, "tag", k="type",        v="restriction")
        ET.SubElement(rel, "tag", k="restriction", v="no_straight_on")
        return root

    def test_encuentra_restriccion_existente(self) -> None:
        root = self._root_with_restriction("100", "50", "200")
        result = _find_restriction_relation(root, "100", "50", "200")
        assert result is not None
        assert result.get("id") == "9001"

    def test_devuelve_none_si_no_existe(self) -> None:
        root = self._root_with_restriction("100", "50", "200")
        assert _find_restriction_relation(root, "100", "50", "999") is None

    def test_ignora_relaciones_no_restriction(self) -> None:
        root = ET.Element("osm")
        rel = ET.SubElement(root, "relation", id="1")
        ET.SubElement(rel, "member", type="way", ref="100", role="from")
        ET.SubElement(rel, "tag", k="type", v="route")  # no es restriction
        assert _find_restriction_relation(root, "100", "50", "200") is None

    def test_root_vacio(self) -> None:
        root = ET.Element("osm")
        assert _find_restriction_relation(root, "1", "2", "3") is None
