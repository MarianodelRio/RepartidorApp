"""
Servicio de geocodificación con Nominatim.

Caché en disco: clave canónica = normalize(calle)#normalize(número).

Estrategia de geocodificación:
  1. Búsqueda directa en Nominatim con la dirección tal cual.
  2. Si falla: matching difuso contra el catálogo de calles reales de OSM
     (obtenido de Overpass API). Se usa token_set_ratio sobre nombres normalizados,
     lo que maneja artículos extra, orden de palabras, abreviaciones, etc.
     Si se encuentra una calle con similitud ≥ FUZZY_THRESHOLD, se reintenta
     Nominatim con el nombre corregido.
  3. Último recurso: solo el nombre de calle sin número.

El catálogo de calles de Overpass se persiste en disco y se recarga si tiene
más de STREET_LIST_TTL_DAYS días de antigüedad.
"""

import difflib
import json
import re
import time
import unicodedata
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

GeoResult = tuple[float, float]  # (lat, lon)

# ─── Caché en memoria ──────────────────────────────────────────────────────────
_cache: dict[str, GeoResult | None] = {}

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_CACHE_FILE = _DATA_DIR / "geocode_cache.json"
_STREETS_FILE = _DATA_DIR / "osm_streets.json"
_persisted: dict[str, dict] = {}

# Parámetros de fuzzy matching
FUZZY_THRESHOLD = 0.80      # similitud mínima para aceptar una corrección
STREET_LIST_TTL_DAYS = 7    # días antes de refrescar el catálogo de calles

# Catálogo de calles OSM (cargado lazily)
_osm_streets: list[str] | None = None
_osm_streets_norm: list[str] | None = None  # versiones normalizadas para comparar


# ─── Normalización ─────────────────────────────────────────────────────────────

def _normalize(text: str) -> str:
    """Minúsculas, sin acentos, espacios simples."""
    nfkd = unicodedata.normalize("NFKD", text.lower())
    no_acc = "".join(c for c in nfkd if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", no_acc).strip()


def _parse_address(raw: str) -> tuple[str, str]:
    """
    Extrae (nombre_de_calle, número_portal) de una dirección en texto libre.

    Pasos de limpieza (en orden):
      1. Elimina sufijo ciudad/país (precedido por coma).
      2. Elimina contenido en paréntesis y texto tras paréntesis sin cerrar.
      3. Normaliza prefijos de número: nº, n°, núm., y también "n " suelto antes de dígito
         y "N?" (codificación corrupta de "nº").
      4. Elimina indicadores de piso/nota al final: bajo, baja, bj, local, planta, etc.
      5. Elimina ordinales de piso al final: "2º", "1ºB", etc.
      6. Limpia puntuación sobrante al final.
      7. Extrae el número de portal (último token numérico + letra opcional).
    """
    s = raw.strip()

    # 1. Eliminar sufijo de ciudad/país (siempre tras coma para no confundir
    #    "Calle Córdoba" o "Avenida de Andalucía" con el sufijo geográfico)
    s = re.sub(
        r",\s*(posadas|14730|c[oó]rdoba|andaluc[ií]a|espa[nñ]a).*$",
        "", s, flags=re.IGNORECASE,
    ).strip().rstrip(",").strip()

    # 2. Eliminar contenido entre paréntesis y paréntesis sin cerrar
    s = re.sub(r"\s*\([^)]*\)\s*", " ", s)   # "(texto completo)"
    s = re.sub(r"\s*\(.*$", "", s)            # "(texto sin cerrar al final"
    s = s.strip().rstrip(",-").strip()

    # 3. Normalizar prefijos de número
    #    Palabra completa "número"/"numero" (sin cortar otras palabras como "numeroso")
    s = re.sub(r"\bn[uú]m[eé]ro\b\.?\s*", " ", s, flags=re.IGNORECASE)
    #    Formas cortas: nº, n°, núm., Nº. — SOLO si lo que sigue NO es letra
    #    (lookahead (?=[\s\d]|$) evita destruir palabras como "número")
    s = re.sub(r"\bn[uúº°][mn]?\.?(?=[\s\d]|$)", " ", s, flags=re.IGNORECASE)
    #    "N?digit" → codificación corrupta de "nºdigit" (e.g. "N?2" → " 2")
    s = re.sub(r"\bN\?\s*(?=\d)", " ", s)
    #    "n digit" → bare "n" (con o sin espacio) antes de dígito (e.g. "n17", "N21", "n 2")
    s = re.sub(r"\bn\s*(?=\d)", " ", s, flags=re.IGNORECASE)
    s = re.sub(r"\s+", " ", s).strip()

    # 4. Eliminar indicadores de piso/portal al final (tras el número de portal)
    #    Cubre: bajo, baja, bj, local, planta, piso, casa, bis, nave, oficina, taller
    _noise = (
        r"(?:bajo|baja|bj|local|planta|piso|casa|bis|nave|oficina|taller|"
        r"sotano|s[oó]tano|entreplanta|dcha|izda|izq|der|pta|dup)"
    )
    # Caso "NÚMERO PISO INDICADOR" (ej. "72 1 planta"): el número antes del indicador
    # es el piso, no el portal → eliminar "piso + indicador" cuando van tras otro número
    s = re.sub(
        r"(?<=\d)[\s,]+\d+\s*" + _noise + r"[\s\S]*$",
        "", s, flags=re.IGNORECASE,
    )
    # Caso simple "NÚMERO INDICADOR" (ej. "6 Bajo"): solo el indicador al final
    s = re.sub(
        r"[\s,]+(?:\d+[ºo°]\s*[a-zA-Z]?\s*)?" + _noise + r"[\s\S]*$",
        "", s, flags=re.IGNORECASE,
    )

    # 5. Eliminar ordinales de piso al final: "2º 2º", "1ºB", "2º C", etc.
    #    (pueden quedar varios pegados)
    s = re.sub(r"([\s,]+\d+[ºo°]\s*[a-zA-Z]?)+$", "", s, flags=re.IGNORECASE)

    # 6. Limpiar puntuación sobrante al final
    s = s.strip().rstrip(",-./").strip()

    # 7. Buscar número de portal al final:
    #    dígitos + opcional (guión o espacio) + opcional una letra
    #    Cubre: "28", "2b", "2B", "12-d", "37b"
    # Número de portal: dígitos + opcional (guión+dígitos±letra | guión/espacio+letra)
    # Cubre: "28", "2b", "2B", "12-d", "37b", "2-1", "2-1b"
    m = re.search(r"[\s,]+(\d+(?:-\d+[a-zA-Z]?|[-\s]?[a-zA-Z])?)\s*$", s)
    if m:
        raw_num = m.group(1)
        number = re.sub(r"\s+", "", raw_num).lower()  # "37 b" → "37b"
        street = s[: m.start()].rstrip(" ,").strip()
        if street:
            return street, number

    if re.search(r"\bs/?n\b", s, re.IGNORECASE):
        street = re.sub(r"\s*,?\s*s/?n.*$", "", s, flags=re.IGNORECASE).strip()
        return street, "sn"

    return s, ""


def _cache_key(street: str, number: str) -> str:
    """Clave canónica: normalize(calle)#normalize(número)."""
    return f"{_normalize(street)}#{_normalize(number)}"


# ─── Fuzzy matching ────────────────────────────────────────────────────────────

def _token_set_ratio(a: str, b: str) -> float:
    """
    Similitud basada en conjuntos de tokens (equivalente a RapidFuzz token_set_ratio).
    Maneja bien casos donde una cadena contiene tokens extra:
      "calle los hornos" vs "calle hornos" → 1.0
      "av blas infante"  vs "avenida de blas infante" → muy alto
    """
    a_tokens = set(a.split())
    b_tokens = set(b.split())
    intersection = sorted(a_tokens & b_tokens)
    diff_a = sorted(a_tokens - b_tokens)
    diff_b = sorted(b_tokens - a_tokens)

    t0 = " ".join(intersection)
    t1 = " ".join(intersection + diff_a)
    t2 = " ".join(intersection + diff_b)

    def _ratio(x: str, y: str) -> float:
        if not x and not y:
            return 1.0
        return difflib.SequenceMatcher(None, x, y).ratio()

    return max(_ratio(t0, t1), _ratio(t0, t2), _ratio(t1, t2))


def _find_closest_street(query_street: str) -> str | None:
    """
    Busca en el catálogo OSM el nombre de calle más parecido al consultado.
    Devuelve el nombre OSM original (con mayúsculas/acentos originales) o None
    si la similitud no supera FUZZY_THRESHOLD.
    """
    streets = _get_osm_streets()
    if not streets:
        return None

    query_norm = _normalize(query_street)
    best_score = 0.0
    best_street = None

    for osm_name, osm_norm in zip(streets, _osm_streets_norm or []):
        score = _token_set_ratio(query_norm, osm_norm)
        if score > best_score:
            best_score = score
            best_street = osm_name

    if best_score >= FUZZY_THRESHOLD and best_street and best_street != query_street:
        print(
            f"[geocode] Fuzzy match: '{query_street}' → '{best_street}' "
            f"(score={best_score:.2f})"
        )
        return best_street

    return None


# ─── Catálogo de calles OSM (Overpass) ────────────────────────────────────────

_OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Bounding box: lat_min, lon_min, lat_max, lon_max (Posadas, Córdoba)
_BBOX = "37.78,-5.15,37.83,-5.06"


def _fetch_streets_from_overpass() -> list[str]:
    """Obtiene todos los nombres de vías de OSM en el área de trabajo."""
    query = f"""
    [out:json][timeout:30];
    way["highway"]["name"]({_BBOX});
    out tags;
    """
    r = requests.post(
        _OVERPASS_URL,
        data={"data": query},
        headers={"User-Agent": NOMINATIM_USER_AGENT},
        timeout=40,
    )
    r.raise_for_status()
    data = r.json()
    names: set[str] = set()
    for elem in data.get("elements", []):
        name = elem.get("tags", {}).get("name", "").strip()
        if name:
            names.add(name)
    return sorted(names)


def _load_streets_from_disk() -> list[str] | None:
    """Carga el catálogo desde disco si existe y no está obsoleto."""
    if not _STREETS_FILE.exists():
        return None
    try:
        raw = json.loads(_STREETS_FILE.read_text("utf-8"))
        age_days = (time.time() - raw.get("timestamp", 0)) / 86400
        if age_days > STREET_LIST_TTL_DAYS:
            return None
        return raw.get("streets", [])
    except Exception:
        return None


def _save_streets_to_disk(streets: list[str]) -> None:
    try:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        _STREETS_FILE.write_text(
            json.dumps({"timestamp": time.time(), "streets": streets},
                       ensure_ascii=False, indent=2),
            "utf-8",
        )
    except Exception as e:
        print(f"[geocode] Error guardando catálogo de calles: {e}")


def _get_osm_streets() -> list[str]:
    """Devuelve el catálogo de calles, cargándolo lazily si es necesario."""
    global _osm_streets, _osm_streets_norm

    if _osm_streets is not None:
        return _osm_streets

    # Intentar desde disco primero
    streets = _load_streets_from_disk()

    if streets is None:
        print("[geocode] Descargando catálogo de calles desde Overpass...")
        try:
            streets = _fetch_streets_from_overpass()
            _save_streets_to_disk(streets)
            print(f"[geocode] Catálogo listo: {len(streets)} calles")
        except Exception as e:
            print(f"[geocode] Error descargando catálogo Overpass: {e}")
            _osm_streets = []
            _osm_streets_norm = []
            return []

    _osm_streets = streets
    _osm_streets_norm = [_normalize(s) for s in streets]
    return _osm_streets


# ─── Nominatim ─────────────────────────────────────────────────────────────────

def _nominatim_request(params: dict) -> dict | None:
    """Llama a Nominatim con los params dados; devuelve el primer resultado o None."""
    base = {
        "format": "jsonv2",
        "limit": 1,
        "countrycodes": "es",
        "addressdetails": 1,
    }
    base.update(params)
    try:
        r = requests.get(
            NOMINATIM_URL,
            params=base,
            headers={"User-Agent": NOMINATIM_USER_AGENT},
            timeout=GEOCODE_TIMEOUT,
        )
        r.raise_for_status()
        data = r.json()
        if data and isinstance(data, list):
            return data[0]
    except Exception as e:
        print(f"[geocode] Nominatim error: {e}")
    return None


def _geocode_street_number(street: str, number: str) -> dict | None:
    """
    Intenta geocodificar (calle, número) con Nominatim.
    Prueba primero con número y luego sin él como fallback.
    """
    city_ctx = "Posadas, Córdoba, España"
    num_str = number if number and number != "sn" else ""

    full = f"{street} {num_str}".strip() if num_str else street
    result = _nominatim_request({
        "q": f"{full}, {city_ctx}",
        "viewbox": POSADAS_VIEWBOX,
        "bounded": 0,
    })
    return result


# ─── Persistencia ──────────────────────────────────────────────────────────────

def _load_cache() -> None:
    """Carga entradas del JSON en la caché en memoria al arrancar."""
    global _persisted
    if not _CACHE_FILE.exists():
        _persisted = {}
        return
    try:
        _persisted = json.loads(_CACHE_FILE.read_text("utf-8"))
        for key, entry in _persisted.items():
            try:
                _cache[key] = (float(entry["lat"]), float(entry["lon"]))
            except Exception:
                pass
    except Exception:
        _persisted = {}


def _persist_entry(
    key: str, lat: float, lon: float,
    street: str, number: str, raw: dict,
    corrected_to: str | None = None,
) -> None:
    """Guarda una entrada geocodificada en disco."""
    addr_detail = raw.get("address", {})
    entry: dict = {
        "lat": lat,
        "lon": lon,
        "street": street,
        "number": number if number else None,
        "display_name": raw.get("display_name"),
        "osm_road": addr_detail.get("road"),
        "osm_house_number": addr_detail.get("house_number"),
    }
    if corrected_to:
        entry["fuzzy_corrected_to"] = corrected_to
    _persisted[key] = entry
    try:
        _CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        _CACHE_FILE.write_text(
            json.dumps(_persisted, ensure_ascii=False, indent=2), "utf-8"
        )
    except Exception as e:
        print(f"[geocode] Error guardando caché: {e}")


# ─── API pública ────────────────────────────────────────────────────────────────

def geocode(address: str) -> GeoResult | None:
    """
    Geocodifica una dirección y devuelve (lat, lon) o None.

    1. Si la cadena es directamente "lat,lon" (ej. coordenadas GPS), la devuelve sin llamada HTTP.
    2. Consulta caché (incluye overrides manuales).
    3. Llama a Nominatim directamente.
    4. Si falla, hace fuzzy matching contra el catálogo OSM y reintenta.
    5. Último recurso: intenta sin número de portal.
    """
    if not address or not address.strip():
        return None

    # Detectar formato "lat,lon" — usado por GPS y por el selector de mapa manual
    coord_match = re.match(
        r'^\s*([-+]?\d+\.?\d*)\s*,\s*([-+]?\d+\.?\d*)\s*$',
        address.strip(),
    )
    if coord_match:
        return (float(coord_match.group(1)), float(coord_match.group(2)))

    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)

    if key in _cache:
        return _cache[key]

    corrected_to: str | None = None

    # Intento 1: búsqueda directa
    raw = _geocode_street_number(street, number)

    # Intento 2: fuzzy match si falló
    if raw is None:
        time.sleep(GEOCODE_RETRY_DELAY)
        closest = _find_closest_street(street)
        if closest:
            corrected_to = closest
            raw = _geocode_street_number(closest, number)

    # Intento 3: sin número como último recurso
    if raw is None and number:
        time.sleep(GEOCODE_RETRY_DELAY)
        raw = _nominatim_request({
            "q": f"{corrected_to or street}, Posadas, Córdoba, España",
            "viewbox": POSADAS_VIEWBOX,
            "bounded": 0,
        })

    if raw:
        try:
            lat, lon = float(raw["lat"]), float(raw["lon"])
            _cache[key] = (lat, lon)
            _persist_entry(key, lat, lon, street, number, raw, corrected_to)
            return (lat, lon)
        except Exception:
            pass

    _cache[key] = None
    return None


def is_cached(address: str) -> bool:
    """Devuelve True si la dirección ya está en caché (sin llamada HTTP)."""
    if not address or not address.strip():
        return False
    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)
    return key in _cache


def geocode_batch(addresses: list[str]) -> list[tuple[str, GeoResult | None]]:
    """
    Geocodifica una lista de direcciones respetando el rate-limit de Nominatim.
    Devuelve lista de (dirección_original, (lat, lon) | None).
    """
    results = []
    for i, addr in enumerate(addresses):
        already = is_cached(addr)
        coord = geocode(addr)
        results.append((addr, coord))
        if not already and i < len(addresses) - 1:
            time.sleep(GEOCODE_DELAY)
    return results


def add_override(address: str, lat: float, lon: float) -> None:
    """
    Registra coordenadas manuales para una dirección (override manual).
    Tiene prioridad sobre cualquier resultado automático.
    """
    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)
    _cache[key] = (lat, lon)
    _persist_entry(key, lat, lon, street, number, {
        "display_name": f"[manual] {address.strip()}",
        "address": {},
    })


def clear_cache() -> None:
    """Limpia la caché en memoria (no borra el disco)."""
    _cache.clear()


# Cargar caché al importar el módulo
_load_cache()
