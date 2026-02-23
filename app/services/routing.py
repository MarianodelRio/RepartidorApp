"""
Servicio de optimización de rutas con VROOM + OSRM.
Resuelve el TSP (Problema del Viajante) y devuelve detalles de ruta.
"""

import requests

from app.core.config import VROOM_BASE_URL, OSRM_BASE_URL, VROOM_TIMEOUT, OSRM_TIMEOUT



def _format_distance(meters: float) -> str:
    """Formatea metros a texto legible."""
    if meters < 1000:
        return f"{int(meters)} m"
    return f"{meters / 1000:.1f} km"


# ═══════════════════════════════════════════
#  OSRM: Validación de coordenadas
# ═══════════════════════════════════════════

_MAX_SNAP_DISTANCE_M = 2000  # máx. 2 km entre coordenada y nodo de red viaria


def can_osrm_snap(lat: float, lon: float) -> bool:
    """Comprueba si OSRM puede mapear esta coordenada a un nodo de la red viaria
    a menos de _MAX_SNAP_DISTANCE_M metros.

    OSRM siempre devuelve el nodo más cercano (aunque esté a miles de km),
    por eso validamos la distancia de snapping. Si supera el umbral la
    coordenada se considera fuera del mapa de rutas.
    """
    try:
        r = requests.get(
            f"{OSRM_BASE_URL}/nearest/v1/driving/{lon},{lat}",
            params={"number": 1},
            timeout=5,
        )
        data = r.json()
        if data.get("code") != "Ok" or not data.get("waypoints"):
            return False
        distance_m = data["waypoints"][0].get("distance", float("inf"))
        return distance_m <= _MAX_SNAP_DISTANCE_M
    except Exception as e:
        print(f"[osrm] Error en nearest para ({lat},{lon}): {e}")
        return False


# ═══════════════════════════════════════════
#  VROOM: Optimización TSP (Open Trip)
# ═══════════════════════════════════════════

def optimize_route(
    coords: list[tuple[float, float]],
) -> dict | None:
    """
    Optimiza el orden de visita usando VROOM.

    Args:
        coords: Lista de (lat, lon). El primer elemento es el origen fijo.

    Returns:
        dict con:
          - waypoint_order: lista de índices originales en orden óptimo
          - total_distance: metros totales
          - total_duration: segundos totales
          - computing_time_ms: ms de cómputo
          - steps_per_stop: info de arrivalDistance/duration por cada stop
        o None si falla.
    """
    if len(coords) < 2:
        return None

    # Construir request VROOM
    start_lon, start_lat = coords[0][1], coords[0][0]

    vehicles = [
        {
            "id": 0,
            "profile": "car",
            "start": [start_lon, start_lat],
            # Sin "end" → Open Trip
        }
    ]

    # Jobs: todas las paradas excepto el origen
    jobs = []
    for i, (lat, lon) in enumerate(coords[1:], start=1):
        jobs.append({
            "id": i,
            "location": [lon, lat],
        })

    payload = {
        "vehicles": vehicles,
        "jobs": jobs,
        "options": {
            "g": True,    # incluir geometría
        },
    }

    try:
        r = requests.post(
            VROOM_BASE_URL,
            json=payload,
            timeout=VROOM_TIMEOUT,
        )
        r.raise_for_status()
        data = r.json()

        if data.get("code") != 0:
            print(f"[vroom] Error code {data.get('code')}: {data.get('error', '')}")
            return None

        route = data["routes"][0]

        # Extraer orden optimizado:
        # Los steps tipo "job" tienen el id original (que es el índice en coords[1:])
        ordered_ids = [0]  # el origen siempre es primero
        stop_details = []
        cumulative_distance = 0.0
        cumulative_duration = 0.0

        for step in route.get("steps", []):
            if step["type"] == "job":
                ordered_ids.append(step["id"])
                cumulative_distance += step.get("distance", 0)
                cumulative_duration += step.get("duration", 0)
                stop_details.append({
                    "original_index": step["id"],
                    "arrival_distance": cumulative_distance,
                    "arrival_duration": cumulative_duration,
                })

        return {
            "waypoint_order": ordered_ids,
            "stop_details": stop_details,
            "total_distance": route.get("distance", 0),
            "total_duration": route.get("duration", 0),
            "geometry": route.get("geometry", ""),
            "computing_time_ms": data.get("summary", {}).get("computing_times", {}).get("solving", 0),
        }

    except requests.exceptions.HTTPError as e:
        print(f"[vroom] Error HTTP: {e.response.status_code} — {e.response.text[:300]}")
        return None
    except Exception as e:
        print(f"[vroom] Error: {e}")
        return None


# ═══════════════════════════════════════════
#  OSRM: Ruta detallada con instrucciones
# ═══════════════════════════════════════════

def get_route_details(
    coords_ordered: list[tuple[float, float]],
) -> dict | None:
    """
    Dado un orden de coordenadas ya optimizado, obtiene la geometría GeoJSON
    de la ruta completa desde OSRM.

    Args:
        coords_ordered: Lista de (lat, lon) en el orden de visita.

    Returns:
        dict con geometry (GeoJSON), total_distance, total_duration
        o None si falla.
    """
    if len(coords_ordered) < 2:
        return None

    coords_str = ";".join(f"{lon},{lat}" for lat, lon in coords_ordered)
    url = f"{OSRM_BASE_URL}/route/v1/driving/{coords_str}"
    params = {
        "overview": "full",
        "geometries": "geojson",
    }

    try:
        r = requests.get(url, params=params, timeout=OSRM_TIMEOUT)
        r.raise_for_status()
        data = r.json()

        if data.get("code") != "Ok":
            print(f"[osrm] Error: {data.get('code')} — {data.get('message', '')}")
            return None

        route = data["routes"][0]

        return {
            "geometry": route["geometry"],
            "total_distance": round(route.get("distance", 0)),
            "total_duration": round(route.get("duration", 0)),
        }

    except Exception as e:
        print(f"[osrm] Error: {e}")
        return None
