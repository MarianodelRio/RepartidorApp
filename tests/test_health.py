"""
Tests de endpoints de sistema: /health, /api/services/status, /api/route-segment
"""

from unittest.mock import patch, Mock


def test_health_devuelve_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_health_incluye_version(client):
    r = client.get("/health")
    assert "version" in r.json()


# ── /api/services/status ──────────────────────────────────────────────────────

def test_services_status_osrm_caido(client):
    with patch("requests.get", side_effect=ConnectionError("down")):
        r = client.get("/api/services/status")
    assert r.status_code == 200
    data = r.json()
    assert data["osrm"]["status"] == "down"
    assert data["all_ok"] is False


def test_services_status_osrm_ok(client):
    mock_resp = Mock(status_code=200)
    with patch("requests.get", return_value=mock_resp):
        r = client.get("/api/services/status")
    assert r.status_code == 200
    assert r.json()["all_ok"] is True


def test_services_status_incluye_url_osrm(client):
    with patch("requests.get", side_effect=ConnectionError("down")):
        r = client.get("/api/services/status")
    data = r.json()
    assert "url" in data["osrm"]


# ── /api/route-segment ────────────────────────────────────────────────────────

def test_route_segment_devuelve_geometria(client):
    mock_resp = Mock()
    mock_resp.raise_for_status.return_value = None
    mock_resp.json.return_value = {
        "code": "Ok",
        "routes": [{"geometry": {"type": "LineString", "coordinates": []}, "distance": 800}],
    }
    with patch("requests.get", return_value=mock_resp):
        r = client.get("/api/route-segment", params={
            "origin_lat": 37.805, "origin_lon": -5.099,
            "dest_lat": 37.806, "dest_lon": -5.100,
        })
    assert r.status_code == 200
    assert r.json()["distance_m"] == 800


def test_route_segment_osrm_caido_devuelve_none(client):
    with patch("requests.get", side_effect=Exception("timeout")):
        r = client.get("/api/route-segment", params={
            "origin_lat": 37.805, "origin_lon": -5.099,
            "dest_lat": 37.806, "dest_lon": -5.100,
        })
    assert r.status_code == 200
    assert r.json()["geometry"] is None
