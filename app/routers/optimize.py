"""
Router de optimización de rutas.
Endpoint principal: POST /optimize

Cambios v2.1:
  - Se envían client_names opcionales y se usan como identidad del punto.
  - Se eliminan los campos de duración/ETA de la respuesta.
  - Para 2 rutas, VROOM equilibra por número de paradas (no por tiempo).

Cambios v2.3:
  - Direcciones duplicadas se fusionan en una sola parada con
    package_count y client_names agregados.
"""

import io
import time
from collections import OrderedDict
import pandas as pd

from fastapi import APIRouter, UploadFile, File, HTTPException

from app.core.config import START_ADDRESS, MAX_STOPS, POSADAS_CENTER
from app.models import (
    OptimizeRequest,
    OptimizeResponse,
    MultiRouteResponse,
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
    response_model=OptimizeResponse | MultiRouteResponse,
    responses={
        400: {"model": ErrorResponse},
        500: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
    },
    summary="Optimizar ruta desde lista de direcciones",
    description=(
        "Recibe una lista de direcciones, las geocodifica, calcula el orden "
        "óptimo de visita (TSP via VROOM/OSRM) y devuelve la ruta completa "
        "con geometría, ETAs e instrucciones de navegación. "
        "Si num_vehicles=2, devuelve una MultiRouteResponse con 2 rutas."
    ),
)
async def optimize(req: OptimizeRequest):
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

    # Separar datos de las paradas que sí se geocodificaron
    ok_addresses = [addr for addr, _, _ in geocoded_ok]
    ok_coords = [coord for _, coord, _ in geocoded_ok]
    ok_primary_names = [unique_primary_names[orig_i] for _, _, orig_i in geocoded_ok]
    ok_all_names = [all_client_names_lists[orig_i] for _, _, orig_i in geocoded_ok]
    ok_pkg_counts = [package_counts[orig_i] for _, _, orig_i in geocoded_ok]

    # Datos de las paradas fallidas
    fail_addresses = [addr for addr, _ in geocoded_fail]
    fail_primary_names = [unique_primary_names[orig_i] for _, orig_i in geocoded_fail]
    fail_all_names = [all_client_names_lists[orig_i] for _, orig_i in geocoded_fail]
    fail_pkg_counts = [package_counts[orig_i] for _, orig_i in geocoded_fail]

    if geocoded_fail:
        print(f"[optimize] ⚠ {len(geocoded_fail)} dirección(es) sin geocodificar: {fail_addresses}")

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
    vroom_result = optimize_route(all_coords, num_vehicles=req.num_vehicles)
    if vroom_result is None:
        raise HTTPException(
            503,
            detail="VROOM no pudo calcular la ruta. ¿Están corriendo los servicios Docker (OSRM + VROOM)?",
        )

    # ── Caso multi-ruta (2 vehículos) ────────────────────────
    if vroom_result.get("multi"):
        return await _build_multi_response(
            vroom_result, all_coords, all_addresses,
            all_primary_names, all_names_lists, all_pkg_counts,
            ok_addresses, t_start,
            fail_addresses, fail_primary_names, fail_all_names, fail_pkg_counts,
            total_packages,
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


async def _build_multi_response(
    vroom_result: dict,
    all_coords: list,
    all_addresses: list,
    all_primary_names: list,
    all_names_lists: list[list[str]],
    all_pkg_counts: list[int],
    delivery_addresses: list,
    t_start: float,
    fail_addresses: list | None = None,
    fail_primary_names: list | None = None,
    fail_all_names: list[list[str]] | None = None,
    fail_pkg_counts: list[int] | None = None,
    total_packages: int = 0,
) -> MultiRouteResponse:
    """Construye la respuesta para 2 rutas (reparto compartido)."""
    fail_addresses = fail_addresses or []
    fail_primary_names = fail_primary_names or []
    fail_all_names = fail_all_names or []
    fail_pkg_counts = fail_pkg_counts or []
    route_responses = []

    for route_idx, vr in enumerate(vroom_result["routes"]):
        wp_order = vr["waypoint_order"]
        stop_details_map = {
            sd["original_index"]: sd for sd in vr.get("stop_details", [])
        }

        ordered_coords = [all_coords[i] for i in wp_order]
        route_details = get_route_details(ordered_coords)
        if route_details is None:
            continue

        stops = []
        route_packages = 0
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
                if cname:
                    label = f"📍 {cname}"
                else:
                    label = f"📍 Parada {seq}"
                stop_type = "stop"
                sd = stop_details_map.get(orig_idx, {})
                dist_m = sd.get("arrival_distance", 0)
                route_packages += pkg_count

            stops.append(StopInfo(
                order=seq,
                address=addr,
                label=label,
                client_name=cname,
                client_names=[n for n in names_list if n],
                type=stop_type,
                lat=lat,
                lon=lon,
                distance_meters=round(dist_m),
                package_count=pkg_count,
            ))

        num_delivery_stops = len([s for s in stops if s.type == "stop"])

        # Añadir paradas fallidas al final de la primera ruta
        if route_idx == 0 and fail_addresses:
            for i, fail_addr in enumerate(fail_addresses):
                seq_fail = len(stops)
                fail_cname = fail_primary_names[i] if i < len(fail_primary_names) else ""
                fail_names = fail_all_names[i] if i < len(fail_all_names) else []
                fail_pkg = fail_pkg_counts[i] if i < len(fail_pkg_counts) else 1

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
            num_delivery_stops += len(fail_addresses)
            route_packages += sum(fail_pkg_counts)

        total_dist = route_details["total_distance"]

        nav_steps = [
            RouteStep(
                text=s["text"],
                distance_m=s["distance_m"],
                location=Coordinate(**s["location"]) if s.get("location") else None,
            )
            for s in route_details.get("steps", [])
        ]

        computing_ms = round((time.perf_counter() - t_start) * 1000, 1)

        route_responses.append(OptimizeResponse(
            success=True,
            summary=RouteSummary(
                total_stops=num_delivery_stops,
                total_packages=route_packages,
                total_distance_m=total_dist,
                total_distance_display=_format_distance(total_dist),
                computing_time_ms=computing_ms,
            ),
            stops=stops,
            geometry=route_details["geometry"],
            steps=nav_steps,
            route_index=route_idx,
            total_routes=len(vroom_result["routes"]),
        ))

    return MultiRouteResponse(
        success=True,
        routes=route_responses,
        total_routes=len(route_responses),
    )


@router.post(
    "/optimize/csv",
    response_model=OptimizeResponse | MultiRouteResponse,
    responses={
        400: {"model": ErrorResponse},
        500: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
    },
    summary="Optimizar ruta desde archivo CSV",
    description=(
        "Sube un CSV con al menos las columnas 'address' (obligatoria) y "
        "opcionalmente 'name'/'nombre' (nombre del cliente). "
        "Las columnas 'telefono' y 'notas' son opcionales y se ignoran."
    ),
)
async def optimize_csv(file: UploadFile = File(...)):
    """Acepta un CSV, extrae las direcciones (y nombres opcionales) y redirige a optimize()."""
    raw = await file.read()

    try:
        df = pd.read_csv(io.BytesIO(raw))
    except Exception as e:
        raise HTTPException(400, detail=f"Error leyendo CSV: {e}")

    # ── Buscar columna address (obligatoria, case-insensitive) ──
    addr_col = None
    for col in df.columns:
        if col.strip().lower() in ("address", "direccion", "dirección", "domicilio", "calle"):
            addr_col = col
            break

    if addr_col is None:
        raise HTTPException(
            400,
            detail="El CSV debe tener una columna de dirección ('address', 'direccion', 'domicilio' o 'calle')",
        )

    # ── Buscar columna name (opcional, case-insensitive) ──
    name_col = None
    for col in df.columns:
        if col.strip().lower() in ("name", "nombre", "cliente", "client", "destinatario", "nombre_cliente"):
            name_col = col
            break

    addresses = [str(a).strip() for a in df[addr_col] if str(a).strip()]
    if not addresses:
        raise HTTPException(400, detail="El CSV no contiene direcciones válidas")

    # Nombres opcionales — valores nulos/vacíos son aceptables
    client_names = None
    if name_col is not None:
        client_names = [
            str(n).strip() if pd.notna(n) else ""
            for n in df[name_col]
        ]

    req = OptimizeRequest(addresses=addresses, client_names=client_names)
    return await optimize(req)
