"""
Router de validación

Flujo: un solo endpoint POST /api/validation/start
  1. Recibe filas crudas del CSV {cliente, direccion, ciudad}
  2. Construye dirección completa (direccion + ciudad si procede)
  3. Agrupa por dirección normalizada (misma parada = +1 paquete)
  4. Geocodifica cada dirección única con Nominatim
  5. Devuelve dos listas: geocoded (con coords) y failed (sin coords)
"""

import time
import unicodedata
from collections import OrderedDict

from pydantic import BaseModel
from fastapi import APIRouter

from app.services.geocoding import geocode, _cache as _geocode_cache
from app.core.config import GEOCODE_DELAY

router = APIRouter(prefix="/validation", tags=["validation"])


# ═══════════════════════════════════════════
#  Modelos de entrada
# ═══════════════════════════════════════════

class CsvRow(BaseModel):
    cliente: str = ""
    direccion: str
    ciudad: str = ""


class StartRequest(BaseModel):
    rows: list[CsvRow]


# ═══════════════════════════════════════════
#  Modelos de salida
# ═══════════════════════════════════════════

class GeocodedStop(BaseModel):
    address: str
    client_name: str            # primer nombre no vacío del grupo
    all_client_names: list[str]
    package_count: int
    lat: float
    lon: float


class FailedStop(BaseModel):
    address: str
    client_names: list[str]
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
    """Normalización ligera para detectar duplicados exactos.
    Quita acentos, minúsculas, espacios extra."""
    s = addr.strip().lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = s.replace(",", " ").replace(".", " ")
    return " ".join(s.split())


# Nota: No usamos _build_full_address porque Posadas, Córdoba se añade manualmente.

# ═══════════════════════════════════════════
#  Endpoint principal
# ═══════════════════════════════════════════

@router.post("/start", response_model=StartResponse)
def validation_start(req: StartRequest):
    """Valida todas las direcciones:
    1. Construye dirección completa desde (direccion, ciudad)
    2. Agrupa duplicados
    3. Geocodifica cada dirección única con Nominatim
    4. Devuelve listas separadas: geocoded y failed
    """
    rows = req.rows
    total_packages = len(rows)

    # ── 1. Agrupar por dirección normalizada ──
    groups: OrderedDict[str, dict] = OrderedDict()

    for row in rows:
        # Usar la dirección tal cual; Posadas, Córdoba se añaden manualmente en los datos
        full_address = row.direccion.strip()
        key = _normalize_for_dedup(full_address)
        if key not in groups:
            groups[key] = {
                "address": full_address,
                "client_names": [],
            }
        groups[key]["client_names"].append(row.cliente)

    # ── 2. Geocodificar cada dirección única ──
    geocoded: list[GeocodedStop] = []
    failed: list[FailedStop] = []

    for group in groups.values():
        addr = group["address"]
        client_names = group["client_names"]
        package_count = len(client_names)
        primary = next((n for n in client_names if n), "")

        key = addr.strip().lower()
        already_in_cache = key in _geocode_cache
        coord = geocode(addr)
        if not already_in_cache:
            # La dirección requirió una llamada a Nominatim; respetar rate limit
            time.sleep(GEOCODE_DELAY)

        if coord:
            lat, lon = coord
            geocoded.append(GeocodedStop(
                address=addr,
                client_name=primary,
                all_client_names=client_names,
                package_count=package_count,
                lat=lat,
                lon=lon,
            ))
        else:
            failed.append(FailedStop(
                address=addr,
                client_names=client_names,
                package_count=package_count,
            ))

    return StartResponse(
        geocoded=geocoded,
        failed=failed,
        total_packages=total_packages,
        unique_addresses=len(groups),
    )
