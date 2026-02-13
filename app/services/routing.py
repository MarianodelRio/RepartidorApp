"""
Servicio de optimización de rutas con VROOM + OSRM.
Resuelve el TSP (Problema del Viajante) como Open Trip.

Cambios v2.1:
  - Para 2 vehículos: VROOM equilibra por número de paradas (no por tiempo)
    usando restricciones de capacidad en vehículos y "amount" en jobs.
  - Se elimina el campo duration_s de los RouteStep.
"""

import math
import requests

from app.core.config import VROOM_BASE_URL, OSRM_BASE_URL, VROOM_TIMEOUT, OSRM_TIMEOUT


# ═══════════════════════════════════════════
#  Traducciones para instrucciones OSRM
# ═══════════════════════════════════════════

MANEUVER_ES = {
    "depart": "Salir",
    "arrive": "Llegar al destino",
    "continue": "Continuar",
    "new name": "Continuar",
    "roundabout": "Entrar en la rotonda",
    "exit roundabout": "Salir de la rotonda",
    "rotary": "Entrar en la glorieta",
    "merge": "Incorporarse",
    "on ramp": "Tomar la rampa de acceso",
    "off ramp": "Tomar la salida",
    "notification": "",
}

MODIFIER_ES = {
    "left": "a la izquierda",
    "right": "a la derecha",
    "slight left": "ligeramente a la izquierda",
    "slight right": "ligeramente a la derecha",
    "sharp left": "fuerte a la izquierda",
    "sharp right": "fuerte a la derecha",
    "straight": "de frente",
    "uturn": "giro en U",
}


def _step_text(mtype: str, modifier: str, name: str) -> str:
    """Genera texto legible en español para un step de OSRM."""
    if mtype in MANEUVER_ES:
        text = MANEUVER_ES[mtype]
    elif mtype == "turn":
        text = "Girar " + MODIFIER_ES.get(modifier, modifier)
    elif mtype == "end of road":
        text = "Final de calle, girar " + MODIFIER_ES.get(modifier, modifier)
    elif mtype == "fork":
        text = "Desvío " + MODIFIER_ES.get(modifier, modifier)
    else:
        text = mtype.replace("_", " ").capitalize()
        if modifier:
            text += " " + MODIFIER_ES.get(modifier, modifier)
    if name:
        text += f" por {name}"
    return text.strip() or "Continuar"


def _format_duration(seconds: float) -> str:
    """Formatea segundos a texto legible."""
    mins = math.ceil(seconds / 60)
    if mins < 60:
        return f"{mins} min"
    hours = mins // 60
    remaining = mins % 60
    if remaining == 0:
        return f"{hours} h"
    return f"{hours} h {remaining} min"


def _format_distance(meters: float) -> str:
    """Formatea metros a texto legible."""
    if meters < 1000:
        return f"{int(meters)} m"
    return f"{meters / 1000:.1f} km"


# ═══════════════════════════════════════════
#  VROOM: Optimización TSP (Open Trip)
# ═══════════════════════════════════════════

def optimize_route(
    coords: list[tuple[float, float]],
    num_vehicles: int = 1,
) -> dict | None:
    """
    Optimiza el orden de visita usando VROOM.

    Args:
        coords: Lista de (lat, lon). El primer elemento es el origen fijo.
        num_vehicles: Número de vehículos (1 o 2).

    Returns:
        dict con:
          - waypoint_order: lista de índices originales en orden óptimo
          - total_distance: metros totales
          - total_duration: segundos totales
          - computing_time_ms: ms de cómputo
          - steps_per_stop: info de arrivalDistance/duration por cada stop
          - routes: (solo si num_vehicles > 1) lista de rutas individuales
        o None si falla.
    """
    if len(coords) < 2:
        return None

    # Construir request VROOM
    start_lon, start_lat = coords[0][1], coords[0][0]

    num_jobs = len(coords) - 1  # paradas (sin contar el origen)

    vehicles = []
    for v in range(num_vehicles):
        vehicle_def: dict = {
            "id": v,
            "profile": "car",
            "start": [start_lon, start_lat],
            # Sin "end" → Open Trip
        }
        # ── Equilibrio por carga (número de paradas) ──────────
        # Para 2 vehículos: limitar la capacidad de cada uno a
        # ceil(N/2) para forzar un reparto equitativo en volumen.
        if num_vehicles > 1:
            max_per_vehicle = math.ceil(num_jobs / num_vehicles)
            vehicle_def["capacity"] = [max_per_vehicle]
        vehicles.append(vehicle_def)

    # Jobs: todas las paradas excepto el origen
    jobs = []
    for i, (lat, lon) in enumerate(coords[1:], start=1):
        job_def: dict = {
            "id": i,
            "location": [lon, lat],
        }
        # Cada job "pesa" 1 unidad de carga (1 bulto / 1 parada)
        if num_vehicles > 1:
            job_def["amount"] = [1]
        jobs.append(job_def)

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

        # Si hay múltiples vehículos, devolver info por ruta
        if num_vehicles > 1:
            routes_out = []
            for route in data.get("routes", []):
                ordered_ids = [0]
                stop_details = []
                cum_dist = 0.0
                cum_dur = 0.0
                for step in route.get("steps", []):
                    if step["type"] == "job":
                        ordered_ids.append(step["id"])
                        cum_dist += step.get("distance", 0)
                        cum_dur += step.get("duration", 0)
                        stop_details.append({
                            "original_index": step["id"],
                            "arrival_distance": cum_dist,
                            "arrival_duration": cum_dur,
                        })
                routes_out.append({
                    "waypoint_order": ordered_ids,
                    "stop_details": stop_details,
                    "total_distance": route.get("distance", 0),
                    "total_duration": route.get("duration", 0),
                    "vehicle_id": route.get("vehicle", 0),
                })
            return {
                "multi": True,
                "routes": routes_out,
                "computing_time_ms": data.get("summary", {}).get("computing_times", {}).get("solving", 0),
            }

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
    Dado un orden de coordenadas ya optimizado, obtiene la ruta detallada
    de OSRM con geometría GeoJSON e instrucciones paso a paso.

    Args:
        coords_ordered: Lista de (lat, lon) en el orden de visita.

    Returns:
        dict con geometry (GeoJSON), steps, total_distance, total_duration
        o None si falla.
    """
    if len(coords_ordered) < 2:
        return None

    coords_str = ";".join(f"{lon},{lat}" for lat, lon in coords_ordered)
    url = f"{OSRM_BASE_URL}/route/v1/driving/{coords_str}"
    params = {
        "overview": "full",
        "geometries": "geojson",
        "steps": "true",
    }

    try:
        r = requests.get(url, params=params, timeout=OSRM_TIMEOUT)
        r.raise_for_status()
        data = r.json()

        if data.get("code") != "Ok":
            print(f"[osrm] Error: {data.get('code')} — {data.get('message', '')}")
            return None

        route = data["routes"][0]

        # Extraer instrucciones (sin duration_s — no es fiable por paradas físicas)
        steps_out = []
        for leg in route.get("legs", []):
            for step in leg.get("steps", []):
                man = step.get("maneuver", {})
                mtype = man.get("type", "")
                modifier = man.get("modifier", "")
                name = step.get("name", "")
                dist = step.get("distance", 0)
                man_loc = man.get("location")

                text = _step_text(mtype, modifier, name)

                item = {
                    "text": text,
                    "distance_m": round(dist),
                }
                if man_loc and len(man_loc) >= 2:
                    item["location"] = {"lat": man_loc[1], "lon": man_loc[0]}

                if dist > 0 or mtype == "arrive":
                    steps_out.append(item)

        return {
            "geometry": route["geometry"],
            "steps": steps_out,
            "total_distance": round(route.get("distance", 0)),
            "total_duration": round(route.get("duration", 0)),
        }

    except Exception as e:
        print(f"[osrm] Error: {e}")
        return None
