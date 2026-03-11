"""
Utilidades de validación geográfica compartidas entre routers y servicios.
"""

import math

from app.core.config import BBOX_LAT_MIN, BBOX_LAT_MAX, BBOX_LON_MIN, BBOX_LON_MAX


def in_work_bbox(lat: float, lon: float) -> bool:
    """True si las coordenadas caen dentro del área de trabajo (comarca)."""
    return (
        BBOX_LAT_MIN <= lat <= BBOX_LAT_MAX and
        BBOX_LON_MIN <= lon <= BBOX_LON_MAX
    )


def validate_coord(lat: float, lon: float) -> str | None:
    """Valida coordenadas geográficas para la zona de trabajo.

    Devuelve None si son correctas, o un mensaje de error descriptivo.
    Comprueba: finitud, rango global, longitud positiva en España, bbox de comarca.
    """
    if not math.isfinite(lat) or not math.isfinite(lon):
        return f"coordenada no finita: ({lat}, {lon})"
    if not (-90 <= lat <= 90):
        return f"latitud {lat} fuera del rango global [-90, 90]"
    if not (-180 <= lon <= 180):
        return f"longitud {lon} fuera del rango global [-180, 180]"
    if lon > 0:
        return (
            f"longitud positiva ({lon:.4f}) en zona española — "
            f"¿lat y lon invertidos? recibido ({lat:.4f}, {lon:.4f})"
        )
    if not (BBOX_LAT_MIN <= lat <= BBOX_LAT_MAX):
        return (
            f"latitud {lat:.4f} fuera del área de trabajo "
            f"[{BBOX_LAT_MIN}, {BBOX_LAT_MAX}]"
        )
    if not (BBOX_LON_MIN <= lon <= BBOX_LON_MAX):
        return (
            f"longitud {lon:.4f} fuera del área de trabajo "
            f"[{BBOX_LON_MIN}, {BBOX_LON_MAX}]"
        )
    return None
