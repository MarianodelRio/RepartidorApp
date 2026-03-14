"""
Map Editor Router
=================
  GET  /editor               → HTML editor page (single-page app)
  GET  /api/editor/geojson   → GeoJSON FeatureCollection of all highway ways
  POST /api/editor/save      → Apply changes (whole-way or segment), save PBF
"""

import logging
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, field_validator

from osm_app.osm_editor import apply_and_save, get_geojson

logger = logging.getLogger(__name__)

router = APIRouter(tags=["map-editor"])

_STATIC_DIR = Path(__file__).parent / "static"

VALID_ONEWAY = frozenset({"yes", "-1"})


# ── Models ────────────────────────────────────────────────────────────────────

class SegmentSpec(BaseModel):
    """Identifies a sub-segment of a way by its boundary node refs."""
    start_node_ref: str
    end_node_ref: str


class WayChange(BaseModel):
    id: int
    highway: str
    oneway: str | None   # "yes" | "-1" | None  (None = bidirectional)
    name: str | None     # new name | None = remove the tag

    # If present, only this slice of the way is changed;
    # the way is split at start/end_node_ref on save.
    segment: SegmentSpec | None = None

    @field_validator("oneway", mode="before")
    @classmethod
    def normalise_oneway(cls, v: object) -> str | None:
        if v is None or v == "":
            return None
        if v not in VALID_ONEWAY:
            raise ValueError(f"oneway must be 'yes', '-1', or null; got {v!r}")
        return str(v)

    @field_validator("name", mode="before")
    @classmethod
    def normalise_name(cls, v: object) -> str | None:
        if v is None:
            return None
        return str(v).strip() or None  # blank string → remove tag


class NodeChange(BaseModel):
    """Tag change for a single OSM node (barrier / access restrictions)."""
    node_ref: str
    barrier: str | None = None   # "bollard" | None (None removes the tag)
    access: str | None  = None   # "no"      | None (None removes the tag)


class RestrictionChange(BaseModel):
    """Add or remove a turn restriction relation between two ways."""
    from_way_id:  int
    via_node_ref: str
    to_way_id:    int
    restrict:     bool   # True = add restriction, False = remove it


class SaveRequest(BaseModel):
    changes: list[WayChange] = []
    node_changes: list[NodeChange] = []
    restriction_changes: list[RestrictionChange] = []


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/editor", include_in_schema=False)
async def serve_editor() -> FileResponse:
    return FileResponse(_STATIC_DIR / "index.html")


@router.get("/api/editor/geojson")
async def get_map_geojson() -> JSONResponse:
    try:
        return JSONResponse(content=get_geojson())
    except Exception as exc:
        logger.exception("Error generating GeoJSON")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.post("/api/editor/save")
async def save_map_changes(request: SaveRequest) -> JSONResponse:
    if not request.changes and not request.node_changes and not request.restriction_changes:
        raise HTTPException(status_code=400, detail="No se han proporcionado cambios.")
    try:
        apply_and_save(
            [c.model_dump() for c in request.changes],
            [c.model_dump() for c in request.node_changes],
            [c.model_dump() for c in request.restriction_changes],
        )
    except Exception as exc:
        logger.exception("Error saving map changes")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    total = len(request.changes) + len(request.node_changes) + len(request.restriction_changes)
    return JSONResponse({"ok": True, "saved": total})
