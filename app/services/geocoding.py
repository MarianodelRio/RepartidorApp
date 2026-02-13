"""
Servicio de geocodificación con Nominatim.
Cache en memoria para evitar llamadas repetidas.

Limpieza y multi-estrategia para convertir direcciones de texto en coordenadas:
    - Normaliza abreviaturas y corrige encoding
    - Elimina ruido y aplica búsquedas alternas (texto libre, estructurada, bounded)
"""

import json
import re
import time
from pathlib import Path

import requests

from app.core.config import (
    NOMINATIM_URL,
    NOMINATIM_USER_AGENT,
    POSADAS_VIEWBOX,
    GEOCODE_DELAY,
    GEOCODE_RETRY_DELAY,
    GEOCODE_TIMEOUT,
)

# Cache en memoria: dirección normalizada → (lat, lon) | None
_cache: dict[str, tuple[float, float] | None] = {}

# ═══════════════════════════════════════════
#  Overrides manuales (direcciones no mapeadas)
# ═══════════════════════════════════════════
_OVERRIDES_FILE = Path(__file__).resolve().parent.parent / "data" / "geocode_overrides.json"
_overrides: dict[str, dict] = {}


def _load_overrides() -> None:
    """Carga overrides desde disco."""
    global _overrides
    if _OVERRIDES_FILE.exists():
        try:
            _overrides = json.loads(_OVERRIDES_FILE.read_text("utf-8"))
        except Exception:
            _overrides = {}


def _save_overrides() -> None:
    """Persiste overrides a disco."""
    _OVERRIDES_FILE.parent.mkdir(parents=True, exist_ok=True)
    _OVERRIDES_FILE.write_text(json.dumps(_overrides, ensure_ascii=False, indent=2), "utf-8")


def add_override(address: str, lat: float, lon: float) -> None:
    """Registra coordenadas manuales para una dirección."""
    key = address.strip().lower()
    _overrides[key] = {"lat": lat, "lon": lon, "original": address.strip()}
    _save_overrides()
    # Actualizar también la cache en memoria
    _cache[key] = (lat, lon)


# Cargar al importar el módulo
_load_overrides()


# ═══════════════════════════════════════════
#  Limpieza de direcciones
# ═══════════════════════════════════════════

def clean_address(raw: str) -> str:
    """
    Limpieza agresiva de direcciones del Excel de reparto.
    Diseñado para las direcciones reales de Posadas.
    """
    s = raw.strip()
    if not s:
        return s

    # ── 1. Limpiar caracteres basura ──
    s = s.replace('\xa0', ' ')
    s = re.sub(r'[\x00-\x1f\x7f]', '', s)

    # ── 2. Corregir encoding roto ──
    _encoding_fixes = {
        'FernÁndez': 'Fernández',
        'M?SICO': 'MÚSICO', 'M?sico': 'Músico',
        'Le?n': 'León', 'LE?N': 'LEÓN',
        'Garc?a': 'García', 'GARC?A': 'GARCÍA',
        'N?2': 'Nº 2', 'N?': 'Nº ',
        'n°': 'nº',
    }
    for old, new in _encoding_fixes.items():
        s = s.replace(old, new)
    # ? sueltos (Fernando ? el Santo → Fernando el Santo)
    s = re.sub(r'\s*\?\s*', ' ', s)

    # Acento incorrecto ´ (comilla) por acento real
    _accent_fixes = {
        "Mari´a": "María", "mari´a": "maría",
        "Garci´a": "García", "garci´a": "garcía",
        "Jose´": "José", "jose´": "josé",
    }
    for old, new in _accent_fixes.items():
        s = s.replace(old, new)
    # Genérico: vocal + ´ → vocal con acento
    s = re.sub(r'a´', 'á', s)
    s = re.sub(r'e´', 'é', s)
    s = re.sub(r'i´', 'í', s)
    s = re.sub(r'o´', 'ó', s)
    s = re.sub(r'u´', 'ú', s)

    # ── 3. Eliminar ruido entre paréntesis ──
    s = re.sub(r'\([^)]*\)', '', s)
    # Paréntesis abierto sin cerrar: "(TOLDOS..." → ""
    s = re.sub(r'\([^)]*$', '', s)

    # ── 4. Eliminar texto extra después de indicadores ──
    noise_after = [
        r'\bSi Ausente\b.*', r'\bseguros\b.*', r'\bOFICINA DE\b.*',
        r'\bESCALERA:?\s*\w+', r'\bLOCAL\b', r'\bCasa\b$',
        r'\bP\.\d+\b.*', r'\bPt\.\w+\b.*',
        r'\bPTA\.?\s*(IZQ|DER|DCHA|IZDA)?\b', r'\bPUERTA\b.*',
    ]
    for pat in noise_after:
        s = re.sub(pat, '', s, flags=re.IGNORECASE)

    # ── 4b. Corregir typos comunes ──
    _typo_fixes = {
        'adofo': 'Adolfo',
        'ADOFO': 'ADOLFO',
    }
    for old, new in _typo_fixes.items():
        s = s.replace(old, new)

    # ── 5. Normalizar abreviaturas de vía ──
    abbreviations = [
        (r'\bGALLE\b', 'CALLE'),
        (r'\bCALLE:\s*', 'CALLE '),
        (r'\bCL\b\.?\s*', 'Calle '),
        (r'\bC/\s*', 'Calle '),
        (r'\bC\.\s+', 'Calle '),
        (r'\bC\s+(?=[A-ZÁÉÍÓÚÑ])', 'Calle '),
        (r'\bCalleDona\b', 'Calle Doña'),
        (r'\bAVDA\.?\b', 'Avenida'),
        (r'\bAV\.?\b', 'Avenida'),
        (r'\bAvda\.?\b', 'Avenida'),
        (r'\bAv\.\s', 'Avenida '),
        (r'\bPZA\.?\b', 'Plaza'),
        (r'\bPza\.?\b', 'Plaza'),
        (r'\bCRTA\.?\b', 'Carretera'),
        (r'\bCtra\.?\b', 'Carretera'),
        (r'\bPSJ\.?\b', 'Pasaje'),
    ]
    for pattern, replacement in abbreviations:
        s = re.sub(pattern, replacement, s)

    # Eliminar duplicados de tipo de vía ("Calle Calle X" → "Calle X")
    s = re.sub(r'\b(Calle|CALLE|Avenida|AVENIDA|Plaza|PLAZA|Carretera|CARRETERA)\s+\1\b',
               r'\1', s, flags=re.IGNORECASE)

    # ── 6. Normalizar "número" ──
    s = re.sub(r'\bnúmero\b', '', s, flags=re.IGNORECASE)
    s = re.sub(r'\bNº\.?\s*', '', s, flags=re.IGNORECASE)
    s = re.sub(r'\bnº\.?\s*', '', s)
    s = re.sub(r'\bn\s*°\s*', '', s)
    s = re.sub(r'\bnum\.?\s*', '', s, flags=re.IGNORECASE)
    # n. o n seguido de dígito (ej: "n.1", "n2")
    s = re.sub(r'\bn\.?\s*(?=\d)', '', s)

    # ── 7. Limpiar s/n variantes ──
    s = re.sub(r'\bs/?n\b', 's/n', s, flags=re.IGNORECASE)
    s = re.sub(r'\bS,N\b', 's/n', s)
    s = re.sub(r'\bSN\b', 's/n', s)

    # ── 8. Eliminar duplicados de número ──
    s = re.sub(r'\bn?(\d+)\s+n?\1\b', r'\1', s)

    # ── 9. Pegar número a calle si falta espacio ──
    s = re.sub(r'([a-záéíóúñ])(\d)', r'\1 \2', s)

    # ── 10. Limpiar pisos/puertas ──
    s = re.sub(r'\s+\d+º\s*[A-Za-z]?\b', '', s)
    s = re.sub(r'\s+\d+ª\s*[A-Za-z]?\b', '', s)
    s = re.sub(r'\s+[Bb][Aa][Jj][Oo]\.?\s*\d*', '', s)
    s = re.sub(r'\s+[Bb][Jj]\.?\b', '', s)
    s = re.sub(r'\s+\d+\s*[º°]\s*\d*\s*$', '', s)

    # ── 11. Limpiar comas, puntos y espacios extra ──
    s = s.rstrip('.,;: -')
    s = re.sub(r'\s*,\s*,+', ',', s)
    s = re.sub(r'\s{2,}', ' ', s)
    s = s.strip()

    # ── 12. Eliminar prefijo tipo "suministros X/" ──
    s = re.sub(r'^suministros\s+\w+\s*[/]', '', s, flags=re.IGNORECASE)

    # ── 13. Eliminar guión/coma iniciales ──
    s = re.sub(r'^[-,.\s]+', '', s)

    s = s.strip()

    # ── 14. Añadir ciudad si no está presente ──
    lower = s.lower()
    if 'posadas' not in lower:
        s += ', Posadas'
    if 'córdoba' not in lower and 'cordoba' not in lower:
        s += ', Córdoba, España'
    return s


def _extract_street_only(cleaned: str) -> str:
    """Extrae solo el nombre de la calle (sin número) de una dirección limpia."""
    s = re.sub(r',\s*Posadas.*$', '', cleaned, flags=re.IGNORECASE)
    s = re.sub(r'\s+\d+[-/]?\d*\s*[A-Za-z]?\s*$', '', s)
    s = re.sub(r'\s+s/n\s*$', '', s, flags=re.IGNORECASE)
    return s.strip()


def _simplify_for_search(cleaned: str) -> str:
    """Simplifica una dirección para búsqueda más amplia (solo calle + ciudad)."""
    street = _extract_street_only(cleaned)
    if street:
        return f"{street}, Posadas, Córdoba, España"
    return cleaned


# ═══════════════════════════════════════════
#  Geocodificación multi-estrategia
# ═══════════════════════════════════════════

def _nominatim_query(query: str, bounded: int = 0) -> tuple[float, float] | None:
    """Hace una consulta a Nominatim y devuelve (lat, lon) o None."""
    params = {
        "q": query,
        "format": "jsonv2",
        "limit": 1,
        "countrycodes": "es",
        "viewbox": POSADAS_VIEWBOX,
        "bounded": bounded,
    }
    headers = {"User-Agent": NOMINATIM_USER_AGENT}

    try:
        r = requests.get(NOMINATIM_URL, params=params, headers=headers, timeout=GEOCODE_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        if not data:
            return None

        lat = float(data[0]["lat"])
        lon = float(data[0]["lon"])

        # Validar que el resultado está en la zona de Posadas (± margen generoso)
        if abs(lat - 37.802) > 0.15 or abs(lon + 5.105) > 0.15:
            print(f"[geocode] Resultado fuera de zona para '{query}': ({lat}, {lon})")
            return None

        return (lat, lon)
    except Exception as e:
        print(f"[geocode] Error Nominatim para '{query}': {e}")
        return None


def _structured_query(street: str, city: str = "Posadas",
                      county: str = "Córdoba", country: str = "España") -> tuple[float, float] | None:
    """Consulta estructurada a Nominatim (más precisa que texto libre)."""
    params = {
        "street": street,
        "city": city,
        "county": county,
        "country": country,
        "format": "jsonv2",
        "limit": 1,
    }
    headers = {"User-Agent": NOMINATIM_USER_AGENT}

    try:
        r = requests.get(NOMINATIM_URL, params=params, headers=headers, timeout=GEOCODE_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        if not data:
            return None

        lat = float(data[0]["lat"])
        lon = float(data[0]["lon"])

        if abs(lat - 37.802) > 0.15 or abs(lon + 5.105) > 0.15:
            return None

        return (lat, lon)
    except Exception:
        return None


def geocode(address: str) -> tuple[float, float] | None:
    """
    Geocodifica una dirección usando múltiples estrategias:
      1. Dirección limpia completa (texto libre)
      2. Búsqueda estructurada (street/city/county)
      3. Solo nombre de calle + Posadas (sin número)
      4. Búsqueda con bounded=1 (forzar zona Posadas)
      5. Últimas palabras significativas de la calle

    Cache en memoria para evitar llamadas repetidas.
    """
    key = address.strip().lower()
    if key in _cache:
        return _cache[key]

    # Comprobar overrides manuales
    if key in _overrides:
        ov = _overrides[key]
        result = (ov["lat"], ov["lon"])
        _cache[key] = result
        print(f"[geocode] ✓ Override manual para '{address}': {result}")
        return result

    cleaned = clean_address(address)
    print(f"[geocode] '{address}' → limpio: '{cleaned}'")

    # ── Estrategia 1: Texto libre completo ──
    result = _nominatim_query(cleaned)
    if result:
        print(f"[geocode] ✓ Estrategia 1 (texto libre): {result}")
        _cache[key] = result
        return result

    time.sleep(GEOCODE_RETRY_DELAY)

    # ── Estrategia 2: Búsqueda estructurada ──
    street_part = _extract_street_only(cleaned)
    num_match = re.search(r'\s+(\d+[-/]?\d*)\s*[A-Za-z]?\s*$',
                          re.sub(r',\s*Posadas.*$', '', cleaned, flags=re.IGNORECASE))
    street_with_num = street_part
    if num_match:
        street_with_num = f"{street_part} {num_match.group(1)}"

    result = _structured_query(street_with_num)
    if result:
        print(f"[geocode] ✓ Estrategia 2 (estructurada): {result}")
        _cache[key] = result
        return result

    time.sleep(GEOCODE_RETRY_DELAY)

    # ── Estrategia 3: Solo calle + ciudad (sin número) ──
    simplified = _simplify_for_search(cleaned)
    if simplified != cleaned:
        result = _nominatim_query(simplified)
        if result:
            print(f"[geocode] ✓ Estrategia 3 (sin número): {result}")
            _cache[key] = result
            return result

        time.sleep(GEOCODE_RETRY_DELAY)

    # ── Estrategia 4: Bounded (forzar zona Posadas) ──
    result = _nominatim_query(simplified, bounded=1)
    if result:
        print(f"[geocode] ✓ Estrategia 4 (bounded): {result}")
        _cache[key] = result
        return result

    time.sleep(GEOCODE_RETRY_DELAY)

    # ── Estrategia 5: Últimas palabras de la calle ──
    words = street_part.split()
    if len(words) >= 2:
        short_street = ' '.join(words[-2:]) if len(words) > 2 else words[-1]
        short_query = f"Calle {short_street}, Posadas, Córdoba, España"
        result = _nominatim_query(short_query)
        if result:
            print(f"[geocode] ✓ Estrategia 5 (calle corta '{short_street}'): {result}")
            _cache[key] = result
            return result

    # ── Falló todo ──
    print(f"[geocode] ✗ FALLÓ para '{address}' (limpio: '{cleaned}')")
    _cache[key] = None
    return None


def geocode_batch(addresses: list[str]) -> list[tuple[str, tuple[float, float] | None]]:
    """
    Geocodifica una lista de direcciones respetando rate-limit de Nominatim.
    Devuelve lista de (dirección_original, (lat, lon) | None).
    """
    results = []
    for i, addr in enumerate(addresses):
        coord = geocode(addr)
        results.append((addr, coord))
        if addr.strip().lower() not in _cache and i < len(addresses) - 1:
            time.sleep(GEOCODE_DELAY)
    return results


def clear_cache():
    """Limpia la cache de geocodificación."""
    _cache.clear()
