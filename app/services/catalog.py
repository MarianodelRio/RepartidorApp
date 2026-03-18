"""
Catálogo de calles de Posadas.

streets.json — archivo gestionado manualmente. El código solo lee.
Se usa en geocoding.py para el paso de fuzzy matching.
"""

import json
from pathlib import Path

from app.core.logging import get_logger

logger = get_logger(__name__)

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_STREETS_FILE = _DATA_DIR / "streets.json"

# Catálogo en memoria (cargado lazily, nunca invalidado en runtime)
_catalog: list[str] | None = None


def get_catalog() -> list[str]:
    """Devuelve la lista de calles de Posadas desde streets.json.

    Se cachea en memoria al primer acceso. Para recargar tras editar el
    archivo hay que reiniciar el proceso.
    """
    global _catalog
    if _catalog is not None:
        return _catalog

    if not _STREETS_FILE.exists():
        logger.warning("streets.json no encontrado — fuzzy matching desactivado")
        return []

    try:
        _catalog = json.loads(_STREETS_FILE.read_text("utf-8")).get("streets", [])
        logger.info("Catálogo cargado: %d calles", len(_catalog))
        return _catalog
    except Exception as e:
        logger.error("Error leyendo streets.json: %s", e)
        return []
