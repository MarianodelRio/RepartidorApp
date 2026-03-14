"""
Map Editor Router
=================
Endpoints para el editor nativo de red viaria de la app Flutter.

  GET  /api/editor/geojson        → FeatureCollection GeoJSON de todas las vías
  POST /api/editor/save           → Aplica cambios y persiste el PBF
  POST /api/editor/rebuild        → Lanza ./start.sh rebuild-map en background
  GET  /api/editor/rebuild/status → Estado actual del rebuild
"""

import asyncio

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from app.core.config import PBF_PATH, PROJECT_DIR
from app.core.logging import get_logger
from app.models.map_editor import (
    RebuildStatusResponse,
    SaveRequest,
    SaveResponse,
)
from app.adapters.osrm import clear_snap_cache
from app.services.map_editor import apply_and_save, get_geojson

logger = get_logger(__name__)

router = APIRouter(prefix="/editor", tags=["map-editor"])

_START_SH = PROJECT_DIR / "start.sh"

# ── Estado del rebuild (en memoria; se reinicia con el proceso) ───────────────
_rebuild: dict[str, object] = {
    "running": False,
    "status":  "idle",    # idle | running | ok | error
    "message": "",
}


# ── Background task ───────────────────────────────────────────────────────────

async def _run_rebuild_bg() -> None:
    """Ejecuta ./start.sh rebuild-map como subproceso async en background."""
    global _rebuild
    _rebuild.update(running=True, status="running", message="Iniciando rebuild…")

    try:
        proc = await asyncio.create_subprocess_exec(
            "bash", str(_START_SH), "rebuild-map",
            cwd=str(PROJECT_DIR),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        stdout, _ = await proc.communicate()
        output = stdout.decode(errors="replace") if stdout else ""

        if proc.returncode == 0:
            clear_snap_cache()
            _rebuild.update(
                status="ok",
                message="Rebuild completado. OSRM activo con el nuevo mapa.",
            )
            logger.info("rebuild-map completado correctamente")
        else:
            _rebuild.update(
                status="error",
                message=f"rebuild-map falló (código {proc.returncode})",
            )
            logger.error("rebuild-map error:\n%s", output)

    except Exception as exc:
        _rebuild.update(status="error", message=str(exc))
        logger.exception("Error inesperado en rebuild")
    finally:
        _rebuild["running"] = False


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/geojson")
async def get_map_geojson() -> JSONResponse:
    """Devuelve la red viaria completa como GeoJSON (resultado cacheado en memoria)."""
    try:
        return JSONResponse(content=get_geojson())
    except Exception as exc:
        logger.exception("Error generando GeoJSON")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.post("/save", response_model=SaveResponse)
async def save_map_changes(request: SaveRequest) -> SaveResponse:
    """Aplica los cambios del editor al PBF y lo sobreescribe."""
    if not request.changes and not request.node_changes and not request.restriction_changes:
        raise HTTPException(status_code=400, detail="No se han proporcionado cambios.")
    try:
        apply_and_save(
            [c.model_dump() for c in request.changes],
            [c.model_dump() for c in request.node_changes],
            [c.model_dump() for c in request.restriction_changes],
        )
    except Exception as exc:
        logger.exception("Error guardando cambios en el mapa")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    total = len(request.changes) + len(request.node_changes) + len(request.restriction_changes)
    return SaveResponse(saved=total)


@router.post("/rebuild")
async def trigger_rebuild() -> JSONResponse:
    """Lanza ./start.sh rebuild-map en background y devuelve inmediatamente."""
    if _rebuild["running"]:
        raise HTTPException(status_code=409, detail="Ya hay un rebuild en curso.")
    if not PBF_PATH.exists():
        raise HTTPException(
            status_code=404,
            detail=f"PBF no encontrado: {PBF_PATH}",
        )
    asyncio.create_task(_run_rebuild_bg())
    return JSONResponse({"status": "started"})


@router.get("/rebuild/status", response_model=RebuildStatusResponse)
async def get_rebuild_status() -> RebuildStatusResponse:
    """Devuelve el estado actual del rebuild (para polling desde Flutter)."""
    return RebuildStatusResponse(**_rebuild)  # type: ignore[arg-type]
