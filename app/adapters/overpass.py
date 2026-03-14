"""
Adaptador Overpass API — descarga nombres de vías OSM.
"""

import requests

from app.core.config import OVERPASS_BBOX, OVERPASS_USER_AGENT

_OVERPASS_URL = "https://overpass-api.de/api/interpreter"


def fetch_streets_from_overpass() -> list[str]:
    """Obtiene todos los nombres de vías de OSM en el área de trabajo."""
    query = f"""
    [out:json][timeout:30];
    way["highway"]["name"]({OVERPASS_BBOX});
    out tags;
    """
    r = requests.post(
        _OVERPASS_URL,
        data={"data": query},
        headers={"User-Agent": OVERPASS_USER_AGENT},
        timeout=40,
    )
    r.raise_for_status()
    data = r.json()
    names: set[str] = set()
    for elem in data.get("elements", []):
        name = elem.get("tags", {}).get("name", "").strip()
        if name:
            names.add(name)
    return sorted(names)
