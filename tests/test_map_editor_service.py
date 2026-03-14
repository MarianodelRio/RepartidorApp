"""
Tests de integración del servicio map_editor.
Mockean _run_osmium para no necesitar el binario osmium ni un PBF real.
La estrategia: se usa un XML OSM mínimo como "PBF" de prueba;
el mock de _run_osmium simplemente copia el archivo origen al destino.
"""

import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

import pytest

import app.services.map_editor as svc

# ── XML OSM mínimo de prueba ──────────────────────────────────────────────────
# Nodo 2 es compartido por las dos vías → es intersección de way 1000.
_OSM_XML = """\
<?xml version='1.0' encoding='utf-8'?>
<osm version="0.6">
  <node id="1" lat="37.800" lon="-5.100"/>
  <node id="2" lat="37.801" lon="-5.101"/>
  <node id="3" lat="37.802" lon="-5.102"/>
  <node id="4" lat="37.803" lon="-5.103" >
    <tag k="barrier" v="bollard"/>
  </node>
  <way id="1000">
    <nd ref="1"/>
    <nd ref="2"/>
    <nd ref="3"/>
    <tag k="highway" v="residential"/>
    <tag k="name"    v="Calle Mayor"/>
  </way>
  <way id="1001">
    <nd ref="2"/>
    <nd ref="3"/>
    <nd ref="4"/>
    <tag k="highway" v="footway"/>
  </way>
</osm>"""


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def _reset_svc_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Antes de cada test:
      - crea un PBF falso (XML) en tmp_path
      - apunta PBF_PATH del módulo a ese fichero
      - limpia la caché en memoria
    """
    pbf = tmp_path / "posadas_editado.osm.pbf"
    pbf.write_text(_OSM_XML, encoding="utf-8")
    monkeypatch.setattr(svc, "PBF_PATH", pbf)
    monkeypatch.setattr(svc, "_cache", None)


def _osmium_copy(args: list[str]) -> None:
    """Mock de _run_osmium que copia src → dst en lugar de llamar al binario."""
    try:
        src = Path(args[1])
        dst = Path(args[args.index("-o") + 1])
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
    except (ValueError, IndexError):
        pass


# ── get_geojson ───────────────────────────────────────────────────────────────

class TestGetGeojson:
    def test_devuelve_feature_collection(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            result = svc.get_geojson()
        assert result["type"] == "FeatureCollection"

    def test_contiene_features(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            result = svc.get_geojson()
        assert len(result["features"]) == 2

    def test_properties_vía_residencial(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            result = svc.get_geojson()
        way = next(f for f in result["features"] if f["properties"]["id"] == 1000)
        props = way["properties"]
        assert props["highway"] == "residential"
        assert props["name"] == "Calle Mayor"
        assert props["oneway"] is None

    def test_coordenadas_en_orden_lon_lat(self) -> None:
        """GeoJSON usa [lon, lat]; la conversión desde OSM debe respetarlo."""
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            result = svc.get_geojson()
        way = next(f for f in result["features"] if f["properties"]["id"] == 1000)
        first_coord = way["geometry"]["coordinates"][0]
        assert first_coord[0] == pytest.approx(-5.100)  # lon
        assert first_coord[1] == pytest.approx(37.800)  # lat

    def test_junction_indices_detectados(self) -> None:
        """Nodo 2 (ref="2") es compartido → debe aparecer en junction_indices de way 1000."""
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            result = svc.get_geojson()
        way = next(f for f in result["features"] if f["properties"]["id"] == 1000)
        # way 1000 tiene nodos [1,2,3]; nodo 2 está en índice 1 y es compartido
        assert 1 in way["properties"]["junction_indices"]

    def test_barrier_node_detectado(self) -> None:
        """Nodo 4 tiene barrier=bollard y pertenece a way 1001."""
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            result = svc.get_geojson()
        barrier_refs = [b["ref"] for b in result["barrier_nodes"]]
        assert "4" in barrier_refs

    def test_cache_evita_segunda_llamada_a_osmium(self) -> None:
        call_count = 0

        def _counting_copy(args: list[str]) -> None:
            nonlocal call_count
            call_count += 1
            _osmium_copy(args)

        with patch.object(svc, "_run_osmium", side_effect=_counting_copy):
            svc.get_geojson()
            svc.get_geojson()

        # Solo debe haber una llamada real a osmium (la segunda usa caché)
        assert call_count == 1

    def test_cache_se_invalida_al_cambiar_mtime(self, tmp_path: Path) -> None:
        """Si el PBF cambia en disco, la caché se invalida."""
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.get_geojson()
            # Sobreescribir el PBF para cambiar mtime
            svc.PBF_PATH.write_text(_OSM_XML, encoding="utf-8")
            call_count = [0]

            def _counting(args: list[str]) -> None:
                call_count[0] += 1
                _osmium_copy(args)

            with patch.object(svc, "_run_osmium", side_effect=_counting):
                svc.get_geojson()

        assert call_count[0] == 1  # se volvió a llamar osmium


# ── apply_and_save — cambio de vía completa ───────────────────────────────────

class TestApplyAndSaveWholeWay:
    def test_cambia_highway_tag(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.apply_and_save([{"id": 1000, "highway": "tertiary", "oneway": None, "name": "Calle Mayor"}])
        tree = ET.parse(svc.PBF_PATH)
        tags = {t.get("k"): t.get("v") for t in tree.find(".//way[@id='1000']").findall("tag")}  # type: ignore[union-attr]
        assert tags["highway"] == "tertiary"

    def test_anade_oneway(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.apply_and_save([{"id": 1000, "highway": "residential", "oneway": "yes", "name": None}])
        tree = ET.parse(svc.PBF_PATH)
        tags = {t.get("k"): t.get("v") for t in tree.find(".//way[@id='1000']").findall("tag")}  # type: ignore[union-attr]
        assert tags["oneway"] == "yes"

    def test_elimina_oneway_con_none(self) -> None:
        # Primero añadimos oneway
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.apply_and_save([{"id": 1000, "highway": "residential", "oneway": "yes", "name": None}])
            # Luego lo eliminamos
            svc.apply_and_save([{"id": 1000, "highway": "residential", "oneway": None, "name": None}])
        tree = ET.parse(svc.PBF_PATH)
        tags = {t.get("k"): t.get("v") for t in tree.find(".//way[@id='1000']").findall("tag")}  # type: ignore[union-attr]
        assert "oneway" not in tags

    def test_cambia_nombre(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.apply_and_save([{"id": 1000, "highway": "residential", "oneway": None, "name": "Avenida Nueva"}])
        tree = ET.parse(svc.PBF_PATH)
        tags = {t.get("k"): t.get("v") for t in tree.find(".//way[@id='1000']").findall("tag")}  # type: ignore[union-attr]
        assert tags["name"] == "Avenida Nueva"

    def test_invalida_cache(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.get_geojson()
            assert svc._cache is not None
            svc.apply_and_save([{"id": 1000, "highway": "tertiary", "oneway": None, "name": None}])
        assert svc._cache is None

    def test_sin_cambios_no_llama_osmium(self) -> None:
        call_count = [0]

        def _counting(args: list[str]) -> None:
            call_count[0] += 1

        with patch.object(svc, "_run_osmium", side_effect=_counting):
            svc.apply_and_save([])

        assert call_count[0] == 0


# ── apply_and_save — cambio de nodo ──────────────────────────────────────────

class TestApplyAndSaveNodeChange:
    def test_anade_barrera_en_nodo(self) -> None:
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.apply_and_save(
                changes=[],
                node_changes=[{"node_ref": "1", "barrier": "bollard", "access": None}],
            )
        tree = ET.parse(svc.PBF_PATH)
        tags = {t.get("k"): t.get("v") for t in tree.find(".//node[@id='1']").findall("tag")}  # type: ignore[union-attr]
        assert tags["barrier"] == "bollard"

    def test_elimina_barrera_con_none(self) -> None:
        """Nodo 4 ya tiene barrier=bollard en el XML de prueba; lo eliminamos."""
        with patch.object(svc, "_run_osmium", side_effect=_osmium_copy):
            svc.apply_and_save(
                changes=[],
                node_changes=[{"node_ref": "4", "barrier": None, "access": None}],
            )
        tree = ET.parse(svc.PBF_PATH)
        tags = {t.get("k"): t.get("v") for t in tree.find(".//node[@id='4']").findall("tag")}  # type: ignore[union-attr]
        assert "barrier" not in tags
