"""
Router de validación.

POST /api/validation/start
  1. Recibe filas del CSV {cliente, direccion, ciudad, nota, alias}
  2. Agrupa por clave canónica (expande abreviaturas, elimina sufijos de ciudad)
  3. Geocodifica cada dirección única: Google Geocoding → Places → FAILED
  4. Devuelve geocoded[] (con coords) y failed[] (sin coords)

POST /api/validation/override
  Registra coordenadas manuales para una dirección → caché permanente.
"""

from collections import OrderedDict

from fastapi import APIRouter, HTTPException

from app.core.config import MAX_STOPS
from app.core.logging import get_logger
from app.models import Package
from app.models.validation import (
    StartRequest,
    OverrideRequest,
    GeocodedStop,
    FailedStop,
    StartResponse,
)
from app.services.geocoding import geocode, add_override, address_key, canonical_address
from app.utils.validation import validate_coord

router = APIRouter(prefix="/validation", tags=["validation"])
logger = get_logger(__name__)


@router.post("/start", response_model=StartResponse)
def validation_start(req: StartRequest):
    """Valida las direcciones del CSV: dedup → geocodifica → geocoded/failed."""
    rows = req.rows
    total_packages = len(rows)

    # 1. Agrupar por clave canónica (expande abreviaturas y sufijos de ciudad)
    groups: OrderedDict[str, dict] = OrderedDict()
    for row in rows:
        key = address_key(row.direccion)
        if key not in groups:
            groups[key] = {
                "address": canonical_address(row.direccion),
                "packages": [],
                "alias": "",
            }
        if not groups[key]["alias"] and row.alias.strip():
            groups[key]["alias"] = row.alias.strip()
        tipo = "Express" if row.tipo.strip().lower() == "express" else "Normal"
        groups[key]["packages"].append(
            Package(client_name=row.cliente, nota=row.nota, agencia=row.agencia, tipo=tipo)
        )

    # 2. Limitar a MAX_STOPS direcciones únicas (post-dedup controla llamadas API)
    if len(groups) > MAX_STOPS:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Demasiadas direcciones únicas: {len(groups)} "
                f"(máximo {MAX_STOPS} tras deduplicar). "
                f"Divide el reparto en lotes más pequeños."
            ),
        )

    # 3. Geocodificar y clasificar en una sola pasada
    geocoded: list[GeocodedStop] = []
    failed: list[FailedStop] = []

    for group in groups.values():
        addr = group["address"]
        packages: list[Package] = group["packages"]
        primary = next((p.client_name for p in packages if p.client_name), "")
        alias = group["alias"]
        stop_tipo = "Express" if any(p.tipo == "Express" for p in packages) else "Normal"
        coord, confidence = geocode(addr, alias=alias)

        if coord:
            lat, lon = coord
            geocoded.append(GeocodedStop(
                address=addr,
                alias=alias,
                client_name=primary,
                packages=packages,
                lat=lat,
                lon=lon,
                confidence=confidence,
                tipo=stop_tipo,
            ))
        else:
            failed.append(FailedStop(
                address=addr,
                alias=alias,
                packages=packages,
                tipo=stop_tipo,
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
    error = validate_coord(req.lat, req.lon)
    if error:
        raise HTTPException(status_code=400, detail=f"Coordenadas inválidas: {error}")
    add_override(req.address, req.lat, req.lon)
    return {"ok": True, "address": req.address}
