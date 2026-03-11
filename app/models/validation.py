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
    all_client_names: list[str]  # retrocompat — derivado de packages
    packages: list[Package]
    package_count: int
    lat: float
    lon: float
    confidence: str  # EXACT_ADDRESS | GOOD | EXACT_PLACE | OVERRIDE


class FailedStop(BaseModel):
    address: str
    alias: str = ""
    client_names: list[str]  # retrocompat — derivado de packages
    packages: list[Package]
    package_count: int


class StartResponse(BaseModel):
    geocoded: list[GeocodedStop]
    failed: list[FailedStop]
    total_packages: int
    unique_addresses: int
