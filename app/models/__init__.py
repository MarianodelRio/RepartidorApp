"""
Modelos Pydantic para request/response de la API.
Contrato claro entre frontend y backend.
"""

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════
#  Modelos de entrada (Request)
# ═══════════════════════════════════════════

class OptimizeRequest(BaseModel):
    """Petición al endpoint /optimize."""
    addresses: list[str] = Field(
        ...,
        min_length=1,
        description="Lista de direcciones a visitar",
        json_schema_extra={"example": ["Calle Gaitán 1, Posadas", "Calle Santiago 2, Posadas"]},
    )
    client_names: list[str] | None = Field(
        default=None,
        description=(
            "Lista de nombres de cliente, uno por cada dirección (mismo orden). "
            "Campos opcionales — se aceptan valores vacíos."
        ),
    )
    start_address: str | None = Field(
        default=None,
        description="Dirección de inicio (origen). Si no se indica, se usa la predeterminada.",
    )
    coords: list[list[float] | None] | None = Field(
        default=None,
        description=(
            "Coordenadas pre-resueltas [lat, lon] para cada dirección (mismo orden). "
            "Si se proporcionan, se omite la geocodificación. null/vacío = geocodificar."
        ),
    )
    package_counts: list[int] | None = Field(
        default=None,
        description=(
            "Nº de paquetes por dirección (mismo orden que addresses). "
            "Si se proporciona, las direcciones ya vienen agrupadas y no se re-agrupan."
        ),
    )
    all_client_names: list[list[str]] | None = Field(
        default=None,
        description=(
            "Lista de listas con todos los nombres de cliente por dirección. "
            "Complementa package_counts cuando las direcciones ya vienen agrupadas."
        ),
    )


# ═══════════════════════════════════════════
#  Modelos de salida (Response)
# ═══════════════════════════════════════════

class Coordinate(BaseModel):
    lat: float
    lon: float


class StopInfo(BaseModel):
    """Una parada en la ruta optimizada.

    La identidad del punto se determina prioritariamente por 'client_name'
    (nombre del cliente/destinatario) en lugar de un ID numérico.
    Los campos de tiempo estimado (eta) se han eliminado porque no reflejan
    la realidad al incluir paradas físicas de carga/descarga.

    Cuando varias filas del Excel comparten la misma dirección se fusionan en
    una sola parada con package_count > 1 y client_names con todos los
    destinatarios.
    """
    order: int = Field(..., description="Posición en la secuencia optimizada (0 = origen)")
    address: str
    label: str
    client_name: str = Field("", description="Nombre del cliente/destinatario (identidad principal)")
    client_names: list[str] = Field(default_factory=list, description="Lista de todos los destinatarios en esta dirección")
    type: str = Field(..., description="'origin' o 'stop'")
    lat: float
    lon: float
    distance_meters: float = Field(0, description="Distancia acumulada hasta esta parada (m)")
    geocode_failed: bool = Field(False, description="True si la dirección no pudo geocodificarse")
    package_count: int = Field(1, description="Número de paquetes en esta dirección")


class RouteSummary(BaseModel):
    """Resumen general de la ruta.

    Nota: los campos de duración se han eliminado porque las estimaciones
    de tiempo no son fiables al no considerar las paradas físicas.
    """
    total_stops: int
    total_packages: int = Field(0, description="Número total de paquetes (puede ser > total_stops si hay agrupaciones)")
    total_distance_m: float = Field(..., description="Distancia total en metros")
    total_distance_display: str = Field(..., description="Distancia formateada (ej: '4.2 km')")
    computing_time_ms: float = Field(0, description="Tiempo de cómputo de la optimización en ms")


class RouteStep(BaseModel):
    """Instrucción de navegación paso a paso."""
    text: str
    distance_m: float
    location: Coordinate | None = None


class OptimizeResponse(BaseModel):
    """Respuesta del endpoint /optimize."""
    success: bool = True
    summary: RouteSummary
    stops: list[StopInfo]
    geometry: dict = Field(..., description="GeoJSON de la polilínea de la ruta")
    steps: list[RouteStep] = Field(default_factory=list, description="Instrucciones de navegación")


class ErrorResponse(BaseModel):
    """Respuesta de error estándar."""
    success: bool = False
    error: str
    detail: str = ""
