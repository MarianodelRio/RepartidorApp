"""
Utilidad offline — descarga nombres de vías OSM para Posadas.

No se usa en runtime. Ejecutar manualmente para regenerar streets.json:

    python -c "
    from app.adapters.overpass import fetch_streets_from_overpass
    import json, pathlib
    streets = fetch_streets_from_overpass()
    pathlib.Path('app/data/streets.json').write_text(
        json.dumps({'streets': streets}, ensure_ascii=False, indent=2)
    )
    print(len(streets), 'calles')
    "
"""

import requests

_OVERPASS_URL = "https://overpass-api.de/api/interpreter"
_OVERPASS_BBOX = "37.75,-5.18,37.86,-5.03"   # municipio de Posadas completo
_OVERPASS_USER_AGENT = "posadas-route-planner/1.4.0 (local)"


def fetch_streets_from_overpass() -> list[str]:
    """Obtiene todos los nombres de vías de OSM en el área de trabajo."""
    query = f"""
    [out:json][timeout:30];
    way["highway"]["name"]({_OVERPASS_BBOX});
    out tags;
    """
    r = requests.post(
        _OVERPASS_URL,
        data={"data": query},
        headers={"User-Agent": _OVERPASS_USER_AGENT},
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
