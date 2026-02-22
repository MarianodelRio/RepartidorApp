"""
Router de optimización de rutas.
Endpoint principal: POST /optimize

Descripción:
    - Recibe direcciones, calcula la orden óptima de visita (TSP/VRP) y devuelve
        la ruta con geometría, ETAs e instrucciones.
    - Soporta envío de coordenadas pre-resueltas y datos pre-agrupados.
"""

import time
from collections import OrderedDict

from fastapi import APIRouter, HTTPException

from app.core.config import START_ADDRESS, MAX_STOPS, POSADAS_CENTER
from app.models import (
    OptimizeRequest,
    OptimizeResponse,
    ErrorResponse,
    StopInfo,
    RouteSummary,
    RouteStep,
    Coordinate,
)
from app.services.geocoding import geocode, geocode_batch
from app.services.routing import (
    optimize_route,
    get_route_details,
    can_osrm_snap,
    _format_distance,
)

router = APIRouter(tags=["optimize"])


# ═══════════════════════════════════════════
#  Utilidad: agrupar direcciones duplicadas
# ═══════════════════════════════════════════

def _normalize_for_dedup(addr: str) -> str:
    """Normalización ligera para detectar duplicados.

    Quita acentos, pasa a minúsculas, elimina espacios extras y
    separadores comunes para que 'Calle Gaitán 1' == 'calle gaitan  1'.
    """
    import unicodedata
    s = addr.strip().lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    # Quitar comas, puntos y espacios duplicados
    s = s.replace(",", " ").replace(".", " ")
    return " ".join(s.split())


def _group_duplicate_addresses(
    addresses: list[str],
    client_names: list[str],
) -> tuple[list[str], list[str], list[list[str]], list[int]]:
    """Agrupa filas con la misma dirección normalizada.

    Devuelve:
        unique_addresses: lista de direcciones únicas (texto original del
                          primer representante de cada grupo).
        unique_primary_names: nombre del cliente principal por grupo (el
                              primero no vacío, o "").
        all_client_names: lista de listas con todos los nombres de cada grupo.
        package_counts: número de paquetes (filas) por grupo.
    """
    # OrderedDict para preservar el orden de primera aparición
    groups: OrderedDict[str, dict] = OrderedDict()

    for addr, cname in zip(addresses, client_names):
        key = _normalize_for_dedup(addr)
        if key not in groups:
            groups[key] = {
                "address": addr,       # texto original de la primera aparición
                "client_names": [],
                "count": 0,
            }
        groups[key]["client_names"].append(cname)
        groups[key]["count"] += 1

    unique_addresses = []
    unique_primary_names = []
    all_client_names_out = []
    package_counts = []

    for g in groups.values():
        unique_addresses.append(g["address"])
        # Nombre principal: primer nombre no vacío
        names = g["client_names"]
        primary = next((n for n in names if n), "")
        unique_primary_names.append(primary)
        all_client_names_out.append(names)
        package_counts.append(g["count"])

    return unique_addresses, unique_primary_names, all_client_names_out, package_counts


@router.post(
    "/optimize",
    response_model=OptimizeResponse,
    responses={
        400: {"model": ErrorResponse},
        500: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
    },
    summary="Optimizar ruta desde lista de direcciones",
    description=(
        "Recibe una lista de direcciones, las geocodifica, calcula el orden "
        "óptimo de visita (TSP via VROOM/OSRM) y devuelve la ruta completa "
        "con geometría, ETAs e instrucciones de navegación."
    ),
)
def optimize(req: OptimizeRequest):
    t_start = time.perf_counter()

    addresses = [a.strip() for a in req.addresses if a.strip()]
    if not addresses:
        raise HTTPException(400, detail="La lista de direcciones está vacía")
    if len(addresses) > MAX_STOPS:
        raise HTTPException(400, detail=f"Máximo {MAX_STOPS} paradas permitidas")

    # Construir lista de nombres de cliente (puede ser None o parcial)
    client_names_raw = req.client_names or []
    # Rellenar con vacío si faltan nombres
    client_names = [
        client_names_raw[i].strip() if i < len(client_names_raw) else ""
        for i in range(len(addresses))
    ]

    origin_addr = req.start_address or START_ADDRESS

    # ── 1. Agrupar direcciones duplicadas ─────────────────────
    # Si vienen package_counts, las direcciones ya están agrupadas (de validación)
    pre_grouped = (
        req.package_counts is not None
        and len(req.package_counts) == len(addresses)
    )

    if pre_grouped:
        unique_addresses = addresses
        package_counts = req.package_counts  # type: ignore[assignment]
        # client_names aquí es el nombre "principal" por parada
        unique_primary_names = client_names
        # Lista de todos los nombres por parada
        if req.all_client_names and len(req.all_client_names) == len(addresses):
            all_client_names_lists = req.all_client_names
        else:
            all_client_names_lists = [[cn] if cn else [] for cn in client_names]

        total_packages = sum(package_counts)
        print(
            f"[optimize] 📦 Recibidas {len(unique_addresses)} paradas "
            f"pre-agrupadas ({total_packages} paquetes totales)"
        )
    else:
        unique_addresses, unique_primary_names, all_client_names_lists, package_counts = \
            _group_duplicate_addresses(addresses, client_names)

        total_packages = sum(package_counts)

        if len(unique_addresses) != len(addresses):
            merged = len(addresses) - len(unique_addresses)
            print(
                f"[optimize] 📦 {len(addresses)} filas → {len(unique_addresses)} "
                f"paradas únicas ({merged} duplicadas fusionadas)"
            )

    # ── 2. Geocodificar origen ────────────────────────────────
    origin_coord = geocode(origin_addr)
    if origin_coord is None:
        raise HTTPException(
            400,
            detail=f"No se pudo geocodificar el origen: {origin_addr}",
        )

    # ── 3. Geocodificar paradas (únicas) ──────────────────────
    if pre_grouped and req.coords and len(req.coords) == len(unique_addresses):
        # Coords ya vienen 1:1 con las paradas únicas
        geocoded_ok = []
        geocoded_fail = []
        for i, (addr, coord) in enumerate(zip(unique_addresses, req.coords)):
            if coord and len(coord) == 2:
                geocoded_ok.append((addr, (coord[0], coord[1]), i))
            else:
                geocoded_fail.append((addr, i))
        if geocoded_ok:
            print(f"[optimize] 🎯 {len(geocoded_ok)} coords pre-resueltas (validación)")
    elif req.coords and len(req.coords) == len(addresses):
        # Coords pre-resueltas para filas NO agrupadas — dedup por clave
        _dedup_map: dict[str, tuple[float, float]] = {}
        for addr, coord in zip(addresses, req.coords):
            key = _normalize_for_dedup(addr)
            if key not in _dedup_map and coord and len(coord) == 2:
                _dedup_map[key] = (coord[0], coord[1])

        geocoded_ok = []
        geocoded_fail = []
        for i, addr in enumerate(unique_addresses):
            key = _normalize_for_dedup(addr)
            coord = _dedup_map.get(key)
            if coord:
                geocoded_ok.append((addr, coord, i))
            else:
                geocoded_fail.append((addr, i))

        if geocoded_ok:
            print(f"[optimize] 🎯 Usando {len(geocoded_ok)} coordenadas pre-resueltas (validación)")
    else:
        batch = geocode_batch(unique_addresses)
        geocoded_ok = [(addr, coord, i) for i, (addr, coord) in enumerate(batch) if coord is not None]
        geocoded_fail = [(addr, i) for i, (addr, coord) in enumerate(batch) if coord is None]

    if not geocoded_ok:
        raise HTTPException(
            400,
            detail="No se pudo geocodificar ninguna dirección.",
        )

    if geocoded_fail:
        print(f"[optimize] ⚠ {len(geocoded_fail)} dirección(es) sin geocodificar")

    # ── 3b. Validar que las coords geocodificadas son ruteables por OSRM ──
    # Evita que VROOM devuelva 500 al recibir coordenadas fuera del mapa de rutas
    routable_ok = []
    for item in geocoded_ok:
        addr, coord, orig_i = item
        lat, lon = coord
        if can_osrm_snap(lat, lon):
            routable_ok.append(item)
        else:
            geocoded_fail.append((addr, orig_i))
            print(f"[optimize] ⚠ Coordenada fuera del mapa OSRM: {addr} ({lat:.4f},{lon:.4f}) → excluida")
    geocoded_ok = routable_ok

    if not geocoded_ok:
        raise HTTPException(
            400,
            detail="Ninguna dirección se puede rutear. Verifica que las coordenadas están en la zona de cobertura.",
        )

    # Separar datos de paradas ruteables y fallidas
    ok_addresses = [addr for addr, _, _ in geocoded_ok]
    ok_coords = [coord for _, coord, _ in geocoded_ok]
    ok_primary_names = [unique_primary_names[orig_i] for _, _, orig_i in geocoded_ok]
    ok_all_names = [all_client_names_lists[orig_i] for _, _, orig_i in geocoded_ok]
    ok_pkg_counts = [package_counts[orig_i] for _, _, orig_i in geocoded_ok]

    fail_addresses = [addr for addr, _ in geocoded_fail]
    fail_primary_names = [unique_primary_names[orig_i] for _, orig_i in geocoded_fail]
    fail_all_names = [all_client_names_lists[orig_i] for _, orig_i in geocoded_fail]
    fail_pkg_counts = [package_counts[orig_i] for _, orig_i in geocoded_fail]

    # coords[0] = origen, coords[1..n] = paradas geocodificadas
    all_coords = [origin_coord] + ok_coords
    all_addresses = [origin_addr] + ok_addresses
    # Nombre del cliente principal: "" para el origen + nombres de cada parada
    all_primary_names = [""] + ok_primary_names
    # Todos los nombres de cliente por parada
    all_names_lists: list[list[str]] = [[]] + ok_all_names
    # Paquetes por parada
    all_pkg_counts = [0] + ok_pkg_counts

    # ── 3. Optimizar orden con VROOM ──────────────────────────
    vroom_result = optimize_route(all_coords)
    if vroom_result is None:
        raise HTTPException(
            503,
            detail="VROOM no pudo calcular la ruta. ¿Están corriendo los servicios Docker (OSRM + VROOM)?",
        )

    # ── 4. Reordenar según resultado de VROOM ─────────────────
    wp_order = vroom_result["waypoint_order"]
    stop_details_map = {
        sd["original_index"]: sd for sd in vroom_result.get("stop_details", [])
    }

    ordered_coords = [all_coords[i] for i in wp_order]

    # ── 5. Obtener ruta detallada de OSRM ─────────────────────
    route_details = get_route_details(ordered_coords)
    if route_details is None:
        raise HTTPException(
            503,
            detail="OSRM no pudo calcular la ruta detallada",
        )

    # ── 6. Construir respuesta ────────────────────────────────
    stops = []
    for seq, orig_idx in enumerate(wp_order):
        lat, lon = all_coords[orig_idx]
        addr = all_addresses[orig_idx]
        cname = all_primary_names[orig_idx] if orig_idx < len(all_primary_names) else ""
        names_list = all_names_lists[orig_idx] if orig_idx < len(all_names_lists) else []
        pkg_count = all_pkg_counts[orig_idx] if orig_idx < len(all_pkg_counts) else 1

        if orig_idx == 0:
            label = "🏠 Origen"
            stop_type = "origin"
            dist_m = 0.0
            pkg_count = 0
            names_list = []
        else:
            # Identidad: usar nombre del cliente si existe, sino dirección
            if cname:
                label = f"📍 {cname}"
            else:
                # Usar dirección abreviada en vez de "Parada X"
                short_addr = addr[:30] + "…" if len(addr) > 30 else addr
                label = f"📍 {short_addr}"
            stop_type = "stop"
            sd = stop_details_map.get(orig_idx, {})
            dist_m = sd.get("arrival_distance", 0)

        stops.append(StopInfo(
            order=seq,
            address=addr,
            label=label,
            client_name=cname,
            client_names=[n for n in names_list if n],  # solo nombres no vacíos
            type=stop_type,
            lat=lat,
            lon=lon,
            distance_meters=round(dist_m),
            package_count=pkg_count,
        ))

    # ── 6b. Añadir paradas fallidas al final (sin coordenadas reales) ──
    for i, fail_addr in enumerate(fail_addresses):
        seq_fail = len(stops)
        fail_cname = fail_primary_names[i]
        fail_names = fail_all_names[i]
        fail_pkg = fail_pkg_counts[i]

        if fail_cname:
            fail_label = f"⚠️ {fail_cname}"
        else:
            short = fail_addr[:30] + "…" if len(fail_addr) > 30 else fail_addr
            fail_label = f"⚠️ {short}"

        stops.append(StopInfo(
            order=seq_fail,
            address=fail_addr,
            label=fail_label,
            client_name=fail_cname,
            client_names=[n for n in fail_names if n],
            type="stop",
            lat=POSADAS_CENTER[0],
            lon=POSADAS_CENTER[1],
            distance_meters=0,
            geocode_failed=True,
            package_count=fail_pkg,
        ))

    # Steps de navegación (sin duration_s)
    nav_steps = [
        RouteStep(
            text=s["text"],
            distance_m=s["distance_m"],
            location=Coordinate(**s["location"]) if s.get("location") else None,
        )
        for s in route_details.get("steps", [])
    ]

    total_dist = route_details["total_distance"]
    computing_ms = round((time.perf_counter() - t_start) * 1000, 1)

    return OptimizeResponse(
        success=True,
        summary=RouteSummary(
            total_stops=len(ok_addresses) + len(fail_addresses),
            total_packages=total_packages,
            total_distance_m=total_dist,
            total_distance_display=_format_distance(total_dist),
            computing_time_ms=computing_ms,
        ),
        stops=stops,
        geometry=route_details["geometry"],
        steps=nav_steps,
    )


