"""
Router de validación

Flujo: un solo endpoint POST /api/validation/start
  1. Recibe lista de direcciones
  2. Agrupa por dirección exacta (misma cadena = misma parada, +1 paquete)
  3. Geocodifica cada dirección única con Nominatim (geocoding.py)
  4. Devuelve: dirección, nº paquetes, coordenadas

Sin normalización, sin cache, sin street_db.
"""

import time
import unicodedata
from collections import OrderedDict

from pydantic import BaseModel
from fastapi import APIRouter

from app.services.geocoding import geocode

router = APIRouter(prefix="/validation", tags=["validation"])


# ═══════════════════════════════════════════
#  Modelos
# ═══════════════════════════════════════════

class StartRequest(BaseModel):
    addresses: list[str]
    client_names: list[str] | None = None


class StopResult(BaseModel):
    """Resultado por dirección única."""
    index: int
    address: str
    status: str          # "ok" | "problem"
    lat: float | None = None
    lon: float | None = None
    package_count: int = 1
    client_names: list[str] = []
    reason: str = ""


class StartResponse(BaseModel):
    success: bool
    total_stops: int        # Nº total de filas (paquetes)
    unique_addresses: int   # Nº de direcciones únicas
    ok_count: int
    problem_count: int
    stops: list[StopResult]
    elapsed_ms: float


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


# ═══════════════════════════════════════════
#  Endpoint principal
# ═══════════════════════════════════════════

@router.post("/start", response_model=StartResponse)
async def validation_start(req: StartRequest):
    """Valida todas las direcciones:
    1. Agrupa duplicados
    2. Geocodifica cada dirección única con Nominatim
    3. Devuelve resultado con coordenadas y nº de paquetes
    """
    t_start = time.time()

    addresses = req.addresses
    client_names = req.client_names or []
    # Rellenar nombres si faltan
    while len(client_names) < len(addresses):
        client_names.append("")

    # ── 1. Agrupar por dirección exacta ──
    groups: OrderedDict[str, dict] = OrderedDict()

    for i, addr in enumerate(addresses):
        key = _normalize_for_dedup(addr)
        if key not in groups:
            groups[key] = {
                "address": addr.strip(),
                "indices": [],
                "client_names": [],
            }
        groups[key]["indices"].append(i)
        groups[key]["client_names"].append(client_names[i])

    # ── 2. Geocodificar cada dirección única ──
    stops: list[StopResult] = []
    ok_count = 0
    problem_count = 0

    for idx, (key, group) in enumerate(groups.items()):
        addr = group["address"]
        coord = geocode(addr)

        if coord:
            status = "ok"
            ok_count += 1
            lat, lon = coord
            reason = ""
        else:
            status = "problem"
            problem_count += 1
            lat, lon = None, None
            reason = "No se encontró en Nominatim"

        stops.append(StopResult(
            index=idx,
            address=addr,
            status=status,
            lat=lat,
            lon=lon,
            package_count=len(group["indices"]),
            client_names=group["client_names"],
            reason=reason,
        ))

    elapsed = (time.time() - t_start) * 1000

    return StartResponse(
        success=True,
        total_stops=len(addresses),
        unique_addresses=len(groups),
        ok_count=ok_count,
        problem_count=problem_count,
        stops=stops,
        elapsed_ms=round(elapsed, 1),
    )
