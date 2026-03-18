"""Modelos Pydantic para los endpoints de validación."""

from pydantic import BaseModel

from app.models import Package


# ── Request ───────────────────────────────────────────────────────────────────

class CsvRow(BaseModel):
    cliente: str = ""
    direccion: str
    ciudad: str = ""
    nota: str = ""
    agencia: str = ""  # empresa de reparto (MRW, SEUR, etc.) — solo informativo
    alias: str = ""    # nombre de negocio/lugar (activa Google Places si se provee)
    tipo: str = "Normal"  # tipo de entrega: 'Express' o 'Normal'


class StartRequest(BaseModel):
    rows: list[CsvRow]


class OverrideRequest(BaseModel):
    address: str
    lat: float
    lon: float


# ── Response ──────────────────────────────────────────────────────────────────

class GeocodedStop(BaseModel):
    address: str
    alias: str = ""
    client_name: str
    packages: list[Package]
    lat: float
    lon: float
    confidence: str  # EXACT_ADDRESS | EXACT_PLACE | OVERRIDE
    tipo: str = "Normal"  # 'Express' si algún paquete es Express, si no 'Normal'


class FailedStop(BaseModel):
    address: str
    alias: str = ""
    packages: list[Package]
    tipo: str = "Normal"  # 'Express' si algún paquete es Express, si no 'Normal'


class StartResponse(BaseModel):
    geocoded: list[GeocodedStop]
    failed: list[FailedStop]
    total_packages: int
    unique_addresses: int
