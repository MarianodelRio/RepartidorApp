"""
Router de optimización de rutas.

POST /optimize
  Recibe paradas pre-agrupadas y validadas (con coords) desde el flujo de
  validación, calcula el orden óptimo de visita (TSP via LKH3 + OSRM)
  y devuelve la ruta completa con geometría y lista de paradas.
"""

import time

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.config import START_ADDRESS, MAX_STOPS, DEPOT_LAT, DEPOT_LON
from app.core.logging import get_logger
from app.models import (
    OptimizeRequest,
    OptimizeResponse,
    ErrorResponse,
    Package,
    StopInfo,
    RouteSummary,
)
from app.services.geocoding import geocode, parse_address
from app.services.routing import optimize_route, snap_to_street, format_distance, get_osrm_matrix
from app.utils.validation import validate_coord as _validate_coord


class RouteEvaluateRequest(BaseModel):
    """Petición al endpoint /route-evaluate."""
    coords: list[list[float]]


class RouteEvaluateResponse(BaseModel):
    """Respuesta del endpoint /route-evaluate."""
    total_distance_m: float
    total_distance_display: str
    total_stops: int

router = APIRouter(tags=["optimize"])
logger = get_logger(__name__)


# ── Resolución de coordenadas desde el request ────────────────────────────────

def _resolve_coords_from_request(
    req: OptimizeRequest,
    unique_addresses: list[str],
) -> tuple[list[tuple[str, tuple[float, float], int]], list[tuple[str, int]]]:
    """Extrae y valida las coordenadas pre-resueltas del request.

    Devuelve (geocoded_ok, geocoded_fail).
    """
    geocoded_ok: list[tuple[str, tuple[float, float], int]] = []
    geocoded_fail: list[tuple[str, int]] = []

    if req.coords and len(req.coords) == len(unique_addresses):
        for i, (addr, raw_coord) in enumerate(zip(unique_addresses, req.coords)):
            if raw_coord and len(raw_coord) == 2:
                lat, lon = raw_coord[0], raw_coord[1]
                err = _validate_coord(lat, lon)
                if err:
                    logger.warning("Coordenada inválida para '%s': %s", addr, err)
                    geocoded_fail.append((addr, i))
                else:
                    geocoded_ok.append((addr, (lat, lon), i))
            else:
                geocoded_fail.append((addr, i))
        if geocoded_ok:
            logger.info("%d coords pre-resueltas (validación)", len(geocoded_ok))

    return geocoded_ok, geocoded_fail


# ── Construcción de la lista de paradas ───────────────────────────────────────

def _build_stops(
    wp_order: list[int],
    all_coords: list[tuple[float, float]],
    all_addresses: list[str],
    all_primary_names: list[str],
    all_names_lists: list[list[str]],
    all_packages_per_stop: list[list[Package]],
    all_pkg_counts: list[int],
    all_aliases_list: list[str],
    stop_details_map: dict[int, dict],
) -> list[StopInfo]:
    """Construye la lista ordenada de StopInfo a partir del orden del solver."""
    stops: list[StopInfo] = []
    for seq, orig_idx in enumerate(wp_order):
        lat, lon = all_coords[orig_idx]
        addr = all_addresses[orig_idx]
        cname = all_primary_names[orig_idx] if orig_idx < len(all_primary_names) else ""
        names_list = all_names_lists[orig_idx] if orig_idx < len(all_names_lists) else []
        pkgs = all_packages_per_stop[orig_idx] if orig_idx < len(all_packages_per_stop) else []
        pkg_count = all_pkg_counts[orig_idx] if orig_idx < len(all_pkg_counts) else 1

        if orig_idx == 0:
            label = "🏠 Origen"
            stop_type = "origin"
            dist_m = 0.0
            pkg_count = 0
            names_list = []
            pkgs = []
        else:
            label = f"📍 {cname}" if cname else f"📍 {addr[:30]}{'…' if len(addr) > 30 else ''}"
            stop_type = "stop"
            dist_m = stop_details_map.get(orig_idx, {}).get("arrival_distance", 0)

        stop_alias = all_aliases_list[orig_idx] if orig_idx < len(all_aliases_list) else ""
        stops.append(StopInfo(
            order=seq,
            address=addr,
            alias=stop_alias,
            label=label,
            client_name=cname,
            client_names=[n for n in names_list if n],
            packages=pkgs,
            type=stop_type,
            lat=lat,
            lon=lon,
            distance_meters=round(dist_m),
            package_count=pkg_count,
        ))
    return stops


# ── Endpoint principal ────────────────────────────────────────────────────────

@router.post(
    "/optimize",
    response_model=OptimizeResponse,
    responses={
        400: {"model": ErrorResponse},
        500: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
    },
    summary="Optimizar ruta desde lista de direcciones",
)
def optimize(req: OptimizeRequest):
    t_start = time.perf_counter()

    addresses = [a.strip() for a in req.addresses if a.strip()]
    if not addresses:
        raise HTTPException(400, detail="La lista de direcciones está vacía")
    if len(addresses) > MAX_STOPS:
        raise HTTPException(400, detail=f"Máximo {MAX_STOPS} paradas permitidas")

    client_names_raw = req.client_names or []
    client_names = [
        client_names_raw[i].strip() if i < len(client_names_raw) else ""
        for i in range(len(addresses))
    ]

    # 1. Paradas pre-agrupadas (siempre requerido: viene del flujo de validación)
    if req.package_counts is None or len(req.package_counts) != len(addresses):
        raise HTTPException(
            400,
            detail="Se requiere package_counts con un valor por dirección (usa el flujo de validación).",
        )

    unique_addresses = addresses
    package_counts = req.package_counts
    unique_primary_names = client_names
    aliases_raw = req.aliases or []
    unique_aliases = [
        aliases_raw[i] if i < len(aliases_raw) else ""
        for i in range(len(addresses))
    ]
    if req.packages_per_stop and len(req.packages_per_stop) == len(addresses):
        all_packages_lists: list[list[Package]] = req.packages_per_stop
        all_client_names_lists = [[p.client_name for p in pkgs] for pkgs in all_packages_lists]
    elif req.all_client_names and len(req.all_client_names) == len(addresses):
        all_client_names_lists = req.all_client_names
        all_packages_lists = [
            [Package(client_name=n) for n in names]
            for names in all_client_names_lists
        ]
    else:
        all_client_names_lists = [[cn] if cn else [] for cn in client_names]
        all_packages_lists = [[Package(client_name=cn)] if cn else [] for cn in client_names]

    total_packages = sum(package_counts)
    logger.info("%d paradas pre-agrupadas (%d paquetes totales)", len(unique_addresses), total_packages)

    # 2. Origen — geocodificar si es custom, luego snap a red viaria
    origin_addr = req.start_address or START_ADDRESS
    if req.start_address:
        origin_coord, _ = geocode(origin_addr)
        if origin_coord is None:
            raise HTTPException(400, detail=f"No se pudo geocodificar el origen: {origin_addr}")
        origin_hint, _ = parse_address(origin_addr)
    else:
        origin_coord = (DEPOT_LAT, DEPOT_LON)
        origin_hint = START_ADDRESS

    origin_snapped = snap_to_street(origin_coord[0], origin_coord[1], origin_hint)
    if origin_snapped is not None:
        origin_coord = origin_snapped

    # 3. Coordenadas de paradas (pre-resueltas en validación)
    geocoded_ok, geocoded_fail = _resolve_coords_from_request(req, unique_addresses)

    if not geocoded_ok:
        raise HTTPException(400, detail="No se pudo geocodificar ninguna dirección.")

    # 3b. Snap a red viaria (OSRM /nearest) — valida rutabilidad y ajusta coords
    snap_coord_by_i: dict[int, tuple[float, float]] = {}
    routable_ok: list[tuple[str, tuple[float, float], int]] = []
    for addr, coord, orig_i in geocoded_ok:
        lat, lon = coord
        street_hint, _ = parse_address(addr)
        snapped = snap_to_street(lat, lon, street_hint)
        if snapped is None:
            geocoded_fail.append((addr, orig_i))
            logger.warning("Fuera del mapa OSRM: %s (%.4f, %.4f) → excluida", addr, lat, lon)
        else:
            snap_coord_by_i[orig_i] = snapped
            routable_ok.append((addr, coord, orig_i))
    geocoded_ok = routable_ok

    # 3c. Rechazar si alguna parada no tiene coords válidas
    if geocoded_fail:
        n = len(geocoded_fail)
        detail_list = ", ".join(f"'{addr}'" for addr, _ in geocoded_fail[:5])
        suffix = " …" if n > 5 else ""
        raise HTTPException(
            400,
            detail=(
                f"{n} parada{'s' if n > 1 else ''} sin coordenadas válidas "
                f"({detail_list}{suffix}). "
                "Resuelve todas las direcciones antes de calcular la ruta."
            ),
        )

    if not geocoded_ok:
        raise HTTPException(
            400,
            detail="Ninguna dirección se puede rutear. Verifica que las coordenadas están en la zona de cobertura.",
        )

    # Preparar listas finales (origen en posición 0)
    ok_addresses = [addr for addr, _, _ in geocoded_ok]
    ok_coords_snapped = [snap_coord_by_i[i] for _, _, i in geocoded_ok]
    ok_primary_names = [unique_primary_names[orig_i] for _, _, orig_i in geocoded_ok]
    ok_all_names = [all_client_names_lists[orig_i] for _, _, orig_i in geocoded_ok]
    ok_packages = [all_packages_lists[orig_i] for _, _, orig_i in geocoded_ok]
    ok_pkg_counts = [package_counts[orig_i] for _, _, orig_i in geocoded_ok]
    ok_aliases = [unique_aliases[orig_i] for _, _, orig_i in geocoded_ok]

    all_coords = [origin_coord] + ok_coords_snapped
    all_addresses = [origin_addr] + ok_addresses
    all_primary_names = [""] + ok_primary_names
    all_names_lists: list[list[str]] = [[]] + ok_all_names
    all_packages_per_stop: list[list[Package]] = [[]] + ok_packages
    all_pkg_counts = [0] + ok_pkg_counts
    all_aliases_list = [""] + ok_aliases

    # 4. Orden óptimo (LKH3)
    solver_result = optimize_route(all_coords)
    if solver_result is None:
        raise HTTPException(
            503,
            detail="LKH3 no pudo calcular la ruta. ¿Está corriendo OSRM (Docker)?",
        )

    wp_order = solver_result["waypoint_order"]
    stop_details_map = {sd["original_index"]: sd for sd in solver_result.get("stop_details", [])}
    ordered_coords = [all_coords[i] for i in wp_order]

    # 5. Construir respuesta
    stops = _build_stops(
        wp_order, all_coords, all_addresses, all_primary_names,
        all_names_lists, all_packages_per_stop, all_pkg_counts,
        all_aliases_list, stop_details_map,
    )

    # Usamos la distancia de la matriz (suma de tramos individuales) en lugar
    # de la distancia de /route con todos los waypoints, que puede estar inflada
    # por las restricciones de dirección de llegada/salida en calles de sentido único.
    total_dist = round(solver_result["total_distance"])
    computing_ms = round((time.perf_counter() - t_start) * 1000, 1)

    return OptimizeResponse(
        success=True,
        summary=RouteSummary(
            total_stops=len(ok_addresses),
            total_packages=total_packages,
            total_distance_m=total_dist,
            total_distance_display=format_distance(total_dist),
            computing_time_ms=computing_ms,
        ),
        stops=stops,
    )


# ── Evaluación de ruta pre-ordenada ──────────────────────────────────────────

@router.post(
    "/route-evaluate",
    response_model=RouteEvaluateResponse,
    responses={400: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
    summary="Evaluar distancia de una ruta ya ordenada (OSRM)",
)
def route_evaluate(req: RouteEvaluateRequest):
    """Recibe coords ya ordenadas (depósito en posición 0) y calcula la
    distancia total sumando pares consecutivos de la matriz OSRM."""
    if len(req.coords) < 2:
        raise HTTPException(400, detail="Se necesitan al menos 2 coordenadas (depósito + 1 parada).")

    coords: list[tuple[float, float]] = []
    for i, raw in enumerate(req.coords):
        if len(raw) != 2:
            raise HTTPException(400, detail=f"Coordenada {i} inválida: {raw}")
        coords.append((raw[0], raw[1]))

    matrix = get_osrm_matrix(coords)
    if matrix is None:
        raise HTTPException(503, detail="OSRM no pudo calcular las distancias.")

    _, dist_matrix = matrix
    total_dist = float(sum(dist_matrix[i][i + 1] for i in range(len(coords) - 1)))

    return RouteEvaluateResponse(
        total_distance_m=total_dist,
        total_distance_display=format_distance(total_dist),
        total_stops=len(coords) - 1,
    )
