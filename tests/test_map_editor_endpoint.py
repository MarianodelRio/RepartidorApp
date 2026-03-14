"""
Tests de los endpoints del router map_editor.

Se mockean: get_geojson, apply_and_save (en app.routers.map_editor).
No se necesita osmium, OSRM ni fichero PBF para ejecutar estos tests.
"""

from unittest.mock import patch

import pytest

import app.routers.map_editor as router_mod

URL_GEOJSON        = "/api/editor/geojson"
URL_SAVE           = "/api/editor/save"
URL_REBUILD        = "/api/editor/rebuild"
URL_REBUILD_STATUS = "/api/editor/rebuild/status"

# ── GeoJSON de prueba ─────────────────────────────────────────────────────────

_GEOJSON_OK = {
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": [[-5.100, 37.800], [-5.101, 37.801]]},
            "properties": {
                "id": 1000, "highway": "residential", "name": "Calle Mayor",
                "oneway": None, "junction_indices": [],
            },
        }
    ],
    "barrier_nodes": [],
}


# ── Fixture: resetea el estado del rebuild antes de cada test ─────────────────

@pytest.fixture(autouse=True)
def _reset_rebuild(monkeypatch: pytest.MonkeyPatch) -> None:
    """Devuelve el dict _rebuild a su estado inicial para evitar contaminación entre tests."""
    monkeypatch.setitem(router_mod._rebuild, "running", False)
    monkeypatch.setitem(router_mod._rebuild, "status",  "idle")
    monkeypatch.setitem(router_mod._rebuild, "message", "")


# ═══════════════════════════════════════════
#  GET /api/editor/geojson
# ═══════════════════════════════════════════

class TestGetGeojsonEndpoint:
    def test_devuelve_200(self, client) -> None:
        with patch("app.routers.map_editor.get_geojson", return_value=_GEOJSON_OK):
            r = client.get(URL_GEOJSON)
        assert r.status_code == 200

    def test_body_es_feature_collection(self, client) -> None:
        with patch("app.routers.map_editor.get_geojson", return_value=_GEOJSON_OK):
            r = client.get(URL_GEOJSON)
        assert r.json()["type"] == "FeatureCollection"

    def test_error_interno_devuelve_500(self, client) -> None:
        with patch("app.routers.map_editor.get_geojson", side_effect=RuntimeError("fallo")):
            r = client.get(URL_GEOJSON)
        assert r.status_code == 500

    def test_error_detail_incluye_mensaje(self, client) -> None:
        with patch("app.routers.map_editor.get_geojson", side_effect=RuntimeError("fallo test")):
            r = client.get(URL_GEOJSON)
        assert "fallo test" in r.json()["detail"]


# ═══════════════════════════════════════════
#  POST /api/editor/save
# ═══════════════════════════════════════════

class TestSaveEndpoint:
    _way_payload = {
        "changes": [{"id": 1000, "highway": "tertiary", "oneway": None, "name": "Calle Mayor"}],
        "node_changes": [],
        "restriction_changes": [],
    }
    _node_payload = {
        "changes": [],
        "node_changes": [{"node_ref": "1", "barrier": "bollard", "access": None}],
        "restriction_changes": [],
    }
    _restriction_payload = {
        "changes": [],
        "node_changes": [],
        "restriction_changes": [
            {"from_way_id": 1000, "via_node_ref": "2", "to_way_id": 1001, "restrict": True}
        ],
    }

    def test_save_way_devuelve_200(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._way_payload)
        assert r.status_code == 200

    def test_save_way_campo_saved(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._way_payload)
        assert r.json()["saved"] == 1

    def test_save_node_devuelve_200(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._node_payload)
        assert r.status_code == 200

    def test_save_node_campo_saved(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._node_payload)
        assert r.json()["saved"] == 1

    def test_save_restriction_devuelve_200(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._restriction_payload)
        assert r.status_code == 200

    def test_save_restriction_campo_saved(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._restriction_payload)
        assert r.json()["saved"] == 1

    def test_saved_suma_los_tres_tipos(self, client) -> None:
        payload = {
            "changes":             [{"id": 1000, "highway": "tertiary", "oneway": None, "name": None}],
            "node_changes":        [{"node_ref": "1", "barrier": "bollard", "access": None}],
            "restriction_changes": [{"from_way_id": 1000, "via_node_ref": "2", "to_way_id": 1001, "restrict": True}],
        }
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=payload)
        assert r.json()["saved"] == 3

    def test_sin_cambios_devuelve_400(self, client) -> None:
        payload = {"changes": [], "node_changes": [], "restriction_changes": []}
        r = client.post(URL_SAVE, json=payload)
        assert r.status_code == 400

    def test_oneway_invalido_devuelve_422(self, client) -> None:
        payload = {
            "changes": [{"id": 1000, "highway": "residential", "oneway": "invalid", "name": None}],
            "node_changes": [],
            "restriction_changes": [],
        }
        r = client.post(URL_SAVE, json=payload)
        assert r.status_code == 422

    def test_error_en_service_devuelve_500(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save", side_effect=OSError("disco lleno")):
            r = client.post(URL_SAVE, json=self._way_payload)
        assert r.status_code == 500

    def test_ok_true_en_respuesta(self, client) -> None:
        with patch("app.routers.map_editor.apply_and_save"):
            r = client.post(URL_SAVE, json=self._way_payload)
        assert r.json()["ok"] is True


# ═══════════════════════════════════════════
#  POST /api/editor/rebuild
# ═══════════════════════════════════════════

class TestRebuildEndpoint:
    def test_devuelve_200_cuando_idle(self, client, tmp_path, monkeypatch) -> None:
        fake_pbf = tmp_path / "posadas_editado.osm.pbf"
        fake_pbf.write_bytes(b"")
        monkeypatch.setattr(router_mod, "PBF_PATH", fake_pbf)
        with patch("app.routers.map_editor.asyncio.create_task"):
            r = client.post(URL_REBUILD)
        assert r.status_code == 200

    def test_body_status_started(self, client, tmp_path, monkeypatch) -> None:
        fake_pbf = tmp_path / "posadas_editado.osm.pbf"
        fake_pbf.write_bytes(b"")
        monkeypatch.setattr(router_mod, "PBF_PATH", fake_pbf)
        with patch("app.routers.map_editor.asyncio.create_task"):
            r = client.post(URL_REBUILD)
        assert r.json()["status"] == "started"

    def test_devuelve_409_si_ya_hay_rebuild_en_curso(self, client, monkeypatch) -> None:
        monkeypatch.setitem(router_mod._rebuild, "running", True)
        r = client.post(URL_REBUILD)
        assert r.status_code == 409

    def test_devuelve_404_si_pbf_no_existe(self, client, tmp_path, monkeypatch) -> None:
        monkeypatch.setattr(router_mod, "PBF_PATH", tmp_path / "no_existe.osm.pbf")
        r = client.post(URL_REBUILD)
        assert r.status_code == 404


# ═══════════════════════════════════════════
#  GET /api/editor/rebuild/status
# ═══════════════════════════════════════════

class TestRebuildStatusEndpoint:
    def test_devuelve_200(self, client) -> None:
        r = client.get(URL_REBUILD_STATUS)
        assert r.status_code == 200

    def test_estado_inicial_idle(self, client) -> None:
        r = client.get(URL_REBUILD_STATUS)
        body = r.json()
        assert body["status"] == "idle"
        assert body["running"] is False
        assert body["message"] == ""

    def test_refleja_estado_running(self, client, monkeypatch) -> None:
        monkeypatch.setitem(router_mod._rebuild, "running", True)
        monkeypatch.setitem(router_mod._rebuild, "status",  "running")
        monkeypatch.setitem(router_mod._rebuild, "message", "Iniciando rebuild…")
        r = client.get(URL_REBUILD_STATUS)
        body = r.json()
        assert body["running"] is True
        assert body["status"] == "running"

    def test_refleja_estado_ok(self, client, monkeypatch) -> None:
        monkeypatch.setitem(router_mod._rebuild, "running", False)
        monkeypatch.setitem(router_mod._rebuild, "status",  "ok")
        monkeypatch.setitem(router_mod._rebuild, "message", "Rebuild completado.")
        r = client.get(URL_REBUILD_STATUS)
        body = r.json()
        assert body["status"] == "ok"
        assert "completado" in body["message"]

    def test_refleja_estado_error(self, client, monkeypatch) -> None:
        monkeypatch.setitem(router_mod._rebuild, "running", False)
        monkeypatch.setitem(router_mod._rebuild, "status",  "error")
        monkeypatch.setitem(router_mod._rebuild, "message", "código 1")
        r = client.get(URL_REBUILD_STATUS)
        assert r.json()["status"] == "error"
