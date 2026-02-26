"""
Router de validación

Flujo: POST /api/validation/start
  1. Recibe filas crudas del CSV {cliente, direccion, ciudad, nota, alias}
  2. Agrupa por dirección normalizada (misma parada = +1 paquete)
  3. Geocodifica cada dirección única con el pipeline multi-fuente:
     Cartociudad → Google Geocoding → Google Places (si alias) → FAILED
  4. Devuelve: geocoded (con coords + confidence) y failed (sin coords)

POST /api/validation/override
  Registra coordenadas manuales (pin) para una dirección → caché permanente.
"""

import unicodedata
from collections import OrderedDict

from pydantic import BaseModel
from fastapi import APIRouter

from app.services.geocoding import geocode, add_override
from app.models import Package

router = APIRouter(prefix="/validation", tags=["validation"])


# ═══════════════════════════════════════════
#  Modelos de entrada
# ═══════════════════════════════════════════

class CsvRow(BaseModel):
    cliente: str = ""
    direccion: str
    ciudad: str = ""
    nota: str = ""
    alias: str = ""     # nombre de negocio/lugar (opcional, activa Google Places)


class StartRequest(BaseModel):
    rows: list[CsvRow]


class OverrideRequest(BaseModel):
    address: str
    lat: float
    lon: float


# ═══════════════════════════════════════════
#  Modelos de salida
# ═══════════════════════════════════════════

class GeocodedStop(BaseModel):
    address: str
    client_name: str            # primer nombre no vacío del grupo
    all_client_names: list[str] # retrocompat — derivado de packages
    packages: list[Package]
    package_count: int
    lat: float
    lon: float
    confidence: str             # EXACT_ADDRESS | GOOD | EXACT_PLACE | OVERRIDE


class FailedStop(BaseModel):
    address: str
    client_names: list[str]     # retrocompat — derivado de packages
    packages: list[Package]
    package_count: int


class StartResponse(BaseModel):
    geocoded: list[GeocodedStop]
    failed: list[FailedStop]
    total_packages: int         # total filas recibidas
    unique_addresses: int       # len(geocoded) + len(failed)


# ═══════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════

def _normalize_for_dedup(addr: str) -> str:
    """Normalización ligera para detectar duplicados exactos."""
    s = addr.strip().lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = s.replace(",", " ").replace(".", " ")
    return " ".join(s.split())


# ═══════════════════════════════════════════
#  Endpoints
# ═══════════════════════════════════════════

@router.post("/start", response_model=StartResponse)
def validation_start(req: StartRequest):
    """Valida todas las direcciones del CSV:
    1. Agrupa duplicados
    2. Geocodifica con pipeline: Cartociudad → Google → Places → FAILED
    3. Devuelve listas separadas: geocoded (con coords) y failed (sin coords)
    """
    rows = req.rows
    total_packages = len(rows)

    # ── 1. Agrupar por dirección normalizada ──────────────────────────────────
    groups: OrderedDict[str, dict] = OrderedDict()

    for row in rows:
        full_address = row.direccion.strip()
        key = _normalize_for_dedup(full_address)
        if key not in groups:
            groups[key] = {
                "address": full_address,
                "packages": [],
                "alias": "",
            }
        # Usar el primer alias no vacío del grupo
        if not groups[key]["alias"] and row.alias.strip():
            groups[key]["alias"] = row.alias.strip()
        groups[key]["packages"].append(Package(client_name=row.cliente, nota=row.nota))

    # ── 2. Geocodificar cada dirección única ──────────────────────────────────
    addr_results: list[tuple[str, tuple | None, str]] = []
    for group in groups.values():
        addr = group["address"]
        alias = group.get("alias", "")
        coord, confidence = geocode(addr, alias=alias)
        addr_results.append((addr, coord, confidence))

    # ── 3. Construir listas geocoded / failed ──────────────────────────────────
    coord_map: dict[str, tuple[tuple | None, str]] = {
        addr: (coord, conf)
        for addr, coord, conf in addr_results
    }

    geocoded: list[GeocodedStop] = []
    failed: list[FailedStop] = []

    for group in groups.values():
        addr = group["address"]
        packages: list[Package] = group["packages"]
        package_count = len(packages)
        client_names = [p.client_name for p in packages]
        primary = next((p.client_name for p in packages if p.client_name), "")

        coord, confidence = coord_map.get(addr, (None, "FAILED"))
        if coord:
            lat, lon = coord
            geocoded.append(GeocodedStop(
                address=addr,
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
    """
    Registra coordenadas manuales (pin del usuario) para una dirección.
    Se guarda en caché permanente y tendrá prioridad en futuros repartos.
    """
    add_override(req.address, req.lat, req.lon)
    return {"ok": True, "address": req.address}
