"""
Modelos Pydantic para el editor de mapa (request / response).
Contrato entre la app Flutter y el backend.
"""

from pydantic import BaseModel, Field, field_validator

# Valores válidos para el tag oneway de OSM
_VALID_ONEWAY: frozenset[str] = frozenset({"yes", "-1"})


# ═══════════════════════════════════════════
#  Modelos auxiliares
# ═══════════════════════════════════════════

class SegmentSpec(BaseModel):
    """Identifica un sub-tramo de una vía por los refs de sus nodos límite."""

    start_node_ref: str = Field(..., description="Ref del nodo inicial del segmento")
    end_node_ref:   str = Field(..., description="Ref del nodo final del segmento")


# ═══════════════════════════════════════════
#  Modelos de entrada (Request)
# ═══════════════════════════════════════════

class WayChange(BaseModel):
    """Cambio de etiquetas para una vía completa o un sub-tramo de ella."""

    id:      int       = Field(..., description="ID de la vía OSM")
    highway: str       = Field(..., description="Nuevo valor del tag highway")
    oneway:  str | None = Field(None, description="'yes' | '-1' | null (bidireccional)")
    name:    str | None = Field(None, description="Nuevo nombre; null elimina el tag")
    segment: SegmentSpec | None = Field(
        None,
        description="Si está presente, solo se edita este tramo; la vía se parte en save",
    )

    @field_validator("oneway", mode="before")
    @classmethod
    def normalise_oneway(cls, v: object) -> str | None:
        if v is None or v == "":
            return None
        if v not in _VALID_ONEWAY:
            raise ValueError(f"oneway debe ser 'yes', '-1' o null; recibido: {v!r}")
        return str(v)

    @field_validator("name", mode="before")
    @classmethod
    def normalise_name(cls, v: object) -> str | None:
        if v is None:
            return None
        return str(v).strip() or None


class NodeChange(BaseModel):
    """Cambio de etiquetas de barrera o acceso en un nodo OSM."""

    node_ref: str      = Field(..., description="ID del nodo OSM")
    barrier:  str | None = Field(None, description="'bollard' | null elimina el tag")
    access:   str | None = Field(None, description="'no'      | null elimina el tag")


class RestrictionChange(BaseModel):
    """Añade o elimina una restricción de giro entre dos vías."""

    from_way_id:  int  = Field(..., description="ID de la vía origen")
    via_node_ref: str  = Field(..., description="ID del nodo de giro")
    to_way_id:    int  = Field(..., description="ID de la vía destino")
    restrict:     bool = Field(..., description="True = añadir restricción; False = eliminarla")


class SaveRequest(BaseModel):
    """Cuerpo del POST /api/editor/save."""

    changes:             list[WayChange]         = Field(default_factory=list)
    node_changes:        list[NodeChange]         = Field(default_factory=list)
    restriction_changes: list[RestrictionChange]  = Field(default_factory=list)


# ═══════════════════════════════════════════
#  Modelos de salida (Response)
# ═══════════════════════════════════════════

class SaveResponse(BaseModel):
    """Respuesta del POST /api/editor/save."""

    ok:    bool = True
    saved: int  = Field(..., description="Número total de cambios persistidos en el PBF")


class RebuildStatusResponse(BaseModel):
    """Respuesta del GET /api/editor/rebuild/status."""

    running: bool
    status:  str = Field(..., description="idle | running | ok | error")
    message: str = ""
