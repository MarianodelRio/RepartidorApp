"""
Router de validación.

POST /api/validation/start
  1. Recibe filas del CSV {cliente, direccion, ciudad, nota, alias}
  2. Agrupa por dirección normalizada (misma parada = +1 paquete)
  3. Geocodifica cada dirección única: Google Geocoding → Places → FAILED
  4. Devuelve geocoded[] (con coords) y failed[] (sin coords)

POST /api/validation/override
  Registra coordenadas manuales para una dirección → caché permanente.
"""

from collections import OrderedDict

from fastapi import APIRouter

from app.core.logging import get_logger
from app.models import Package
from app.models.validation import (
    StartRequest,
    OverrideRequest,
    GeocodedStop,
    FailedStop,
    StartResponse,
)
from app.services.geocoding import geocode, add_override
from app.utils.normalization import normalize_for_dedup as _normalize_for_dedup

router = APIRouter(prefix="/validation", tags=["validation"])
logger = get_logger(__name__)


@router.post("/start", response_model=StartResponse)
def validation_start(req: StartRequest):
    """Valida las direcciones del CSV: dedup → geocodifica → geocoded/failed."""
    rows = req.rows
    total_packages = len(rows)

    # 1. Agrupar por dirección normalizada
    groups: OrderedDict[str, dict] = OrderedDict()
    for row in rows:
        full_address = row.direccion.strip()
        key = _normalize_for_dedup(full_address)
        if key not in groups:
            groups[key] = {"address": full_address, "packages": [], "alias": ""}
        if not groups[key]["alias"] and row.alias.strip():
            groups[key]["alias"] = row.alias.strip()
        groups[key]["packages"].append(Package(client_name=row.cliente, nota=row.nota))

    # 2. Geocodificar cada dirección única
    coord_map: dict[str, tuple[tuple | None, str]] = {}
    for group in groups.values():
        addr = group["address"]
        coord, confidence = geocode(addr, alias=group.get("alias", ""))
        coord_map[addr] = (coord, confidence)

    # 3. Clasificar en geocoded / failed
    geocoded: list[GeocodedStop] = []
    failed: list[FailedStop] = []

    for group in groups.values():
        addr = group["address"]
        packages: list[Package] = group["packages"]
        package_count = len(packages)
        client_names = [p.client_name for p in packages]
        primary = next((p.client_name for p in packages if p.client_name), "")
        coord, confidence = coord_map.get(addr, (None, "FAILED"))
        alias = group.get("alias", "")

        if coord:
            lat, lon = coord
            geocoded.append(GeocodedStop(
                address=addr,
                alias=alias,
                client_name=primary,
                all_client_names=client_names,
                packages=packages,
                package_count=package_count,
                lat=lat,
                lon=lon,
                confidence=confidence,
            ))
        else:
            failed.append(FailedStop(
                address=addr,
                alias=alias,
                client_names=client_names,
                packages=packages,
                package_count=package_count,
            ))

    return StartResponse(
        geocoded=geocoded,
        failed=failed,
        total_packages=total_packages,
        unique_addresses=len(groups),
    )


@router.post("/override")
def validation_override(req: OverrideRequest):
    """Registra coordenadas manuales (pin) para una dirección (override permanente)."""
    add_override(req.address, req.lat, req.lon)
    return {"ok": True, "address": req.address}
