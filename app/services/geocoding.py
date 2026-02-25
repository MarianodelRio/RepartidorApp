"""
Servicio de geocodificación multi-fuente.

Caché en disco: clave canónica = normalize(calle)#normalize(número).

Estrategia de geocodificación (en orden de prioridad):
  0. Cartociudad (CNIG) — datos del Registro de Direcciones oficial español.
     Solo para direcciones con número de portal. Devuelve coordenadas de portal
     reales (o del portal más cercano). Si el resultado cae fuera del bbox de
     Posadas, se descarta para evitar falsos positivos.
  1. Búsqueda directa en Nominatim con la dirección tal cual.
  2. Si falla: matching difuso contra el catálogo de calles reales de OSM
     (obtenido de Overpass API). Se usa token_set_ratio sobre nombres normalizados,
     lo que maneja artículos extra, orden de palabras, abreviaciones, etc.
     Si se encuentra una calle con similitud ≥ FUZZY_THRESHOLD, se reintenta
     Nominatim con el nombre corregido.
  3. Último recurso: solo el nombre de calle sin número (centroide).

El catálogo de calles de Overpass se persiste en disco y se recarga si tiene
más de STREET_LIST_TTL_DAYS días de antigüedad.
"""

import difflib
import json
import re
import time
import unicodedata
from collections import Counter, defaultdict
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


def _extract_portal_int(number: str) -> int | None:
    """Extrae la parte numérica entera de un número de portal.
    '47b' → 47, '2-1' → 2, 'sn' → None, '' → None.
    """
    if not number or number == "sn":
        return None
    m = re.match(r"^(\d+)", number.strip())
    return int(m.group(1)) if m else None


def _interpolate_coord(
    num: int,
    ref_low: tuple[int, float, float],
    ref_high: tuple[int, float, float],
) -> "GeoResult | None":
    """Interpola/extrapola linealmente coords para el portal `num`.
    Usa ref_low y ref_high como anclas (pueden ser extra-range para extrapolar).
    Devuelve None si el resultado cae fuera del bbox de trabajo.
    """
    n_low, lat_low, lon_low = ref_low
    n_high, lat_high, lon_high = ref_high
    span = n_high - n_low
    if span == 0:
        return (lat_low, lon_low)
    ratio = (num - n_low) / span
    lat = lat_low + ratio * (lat_high - lat_low)
    lon = lon_low + ratio * (lon_high - lon_low)
    # Sanity: el resultado debe quedar dentro del área de trabajo
    if not (_POSADAS_LAT_MIN <= lat <= _POSADAS_LAT_MAX and
            _POSADAS_LON_MIN <= lon <= _POSADAS_LON_MAX):
        return None
    return (lat, lon)


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


# ─── Cartociudad (CNIG — Registro de Direcciones oficial) ──────────────────────

_CARTOCIUDAD_URL = "https://www.cartociudad.es/geocoder/api/geocoder/findJsonp"

# Bounding box de Posadas con margen generoso para rechazar falsos positivos
_POSADAS_LAT_MIN, _POSADAS_LAT_MAX = 37.76, 37.84
_POSADAS_LON_MIN, _POSADAS_LON_MAX = -5.16, -5.04


def _cartociudad_request(street: str, number: str) -> GeoResult | None:
    """
    Geocodifica con Cartociudad (CNIG).
    Devuelve (lat, lon) si encuentra un portal dentro del bbox de Posadas, o None.
    La API devuelve JSONP; se extrae el JSON con regex.
    """
    num_str = number if number and number != "sn" else ""
    query = f"{street} {num_str}, Posadas, Córdoba".strip()

    try:
        r = requests.get(
            _CARTOCIUDAD_URL,
            params={"q": query, "callback": "cb"},
            headers={"User-Agent": NOMINATIM_USER_AGENT},
            timeout=GEOCODE_TIMEOUT,
        )
        r.raise_for_status()

        # Quitar wrapper JSONP: cb({...}); → {...}
        m = re.match(r"^\w+\((.+)\)\s*;?\s*$", r.text.strip(), re.DOTALL)
        if not m:
            return None
        data = json.loads(m.group(1))
        if not data or not isinstance(data, dict):
            return None

        lat = float(data.get("lat") or 0)
        lng = float(data.get("lng") or 0)
        if lat == 0 and lng == 0:
            return None

        # Rechazar resultados fuera del área de trabajo
        if not (_POSADAS_LAT_MIN <= lat <= _POSADAS_LAT_MAX and
                _POSADAS_LON_MIN <= lng <= _POSADAS_LON_MAX):
            print(
                f"[geocode] Cartociudad fuera de bbox ({lat:.4f}, {lng:.4f}) "
                f"para '{street} {num_str}' — descartado"
            )
            return None

        portal = data.get("nportal", "?")
        print(
            f"[geocode] Cartociudad: '{street} {num_str}' → "
            f"portal {portal} ({lat:.5f}, {lng:.5f})"
        )
        return (lat, lng)

    except Exception as e:
        print(f"[geocode] Cartociudad error para '{query}': {e}")
        return None


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
    source: str = "nominatim",
) -> None:
    """Guarda una entrada geocodificada en disco."""
    addr_detail = raw.get("address", {})
    entry: dict = {
        "lat": lat,
        "lon": lon,
        "street": street,
        "number": number if number else None,
        "display_name": raw.get("display_name"),
        "osm_type": raw.get("osm_type"),        # "way" = centroide, "node" = portal exacto
        "osm_road": addr_detail.get("road"),
        "osm_house_number": addr_detail.get("house_number"),
        "source": source,
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


def _is_nominatim_centroid(address: str) -> bool:
    """
    True si la dirección fue geocodificada por Nominatim y el resultado es un
    centroide de calle (osm_type='way'), es decir, Nominatim encontró la calle
    pero no el portal concreto.
    False en cualquier otro caso (Cartociudad, portal exacto OSM, interpolado,
    no en caché, o sin número de portal).
    """
    try:
        street, number = _parse_address(address.strip())
        if not number or number == "sn":
            return False
        key = _cache_key(street, number)
        entry = _persisted.get(key, {})
        return (
            entry.get("source") == "nominatim" and
            entry.get("osm_type") == "way"
        )
    except Exception:
        return False


# ─── API pública ────────────────────────────────────────────────────────────────

def geocode(address: str) -> GeoResult | None:
    """
    Geocodifica una dirección y devuelve (lat, lon) o None.

    0. Si la cadena es directamente "lat,lon" (ej. coordenadas GPS), la devuelve sin llamada HTTP.
    1. Consulta caché (incluye overrides manuales).
    2. Intenta Cartociudad (CNIG) — solo si hay número de portal.
    3. Llama a Nominatim directamente.
    4. Si falla, hace fuzzy matching contra el catálogo OSM y reintenta.
    5. Último recurso: intenta sin número de portal (centroide de calle).
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

    # Intento 0: Cartociudad (portal exacto, datos CNIG) — solo si hay número
    if number and number != "sn":
        carto = _cartociudad_request(street, number)
        if carto:
            _cache[key] = carto
            _persist_entry(key, carto[0], carto[1], street, number, {
                "display_name": f"[cartociudad] {street} {number}, Posadas",
                "address": {"road": street, "house_number": number},
            }, source="cartociudad")
            return carto

    # Intento 1: búsqueda directa en Nominatim
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


def improve_geocoding(
    results: list[tuple[str, GeoResult | None]],
) -> list[tuple[str, GeoResult | None]]:
    """
    Post-proceso de batch: interpola posiciones para portales con centroide de Nominatim.

    Un portal "necesita mejora" cuando:
      - coord es None (geocodificación completamente fallida), o
      - _is_nominatim_centroid() es True: Nominatim devolvió osm_type='way',
        es decir, encontró la calle pero no el portal concreto.

    Para cada portal que necesita mejora, busca en la misma calle portales con
    coordenadas reales (Cartociudad, nodo OSM exacto, o interpolados previos) y
    realiza INTERPOLACIÓN LINEAL usando el portal conocido más cercano por debajo
    y el más cercano por arriba del número buscado.

    NO se extrapola fuera del rango de portales conocidos: si no hay referencia
    a ambos lados del portal, la entrada se deja sin cambios.

    Las coordenadas estimadas se guardan en caché con source='interpolated'.
    Si el resultado cae fuera del bbox de Posadas se descarta.
    """
    if not results:
        return results

    # ── 1. Parsear y marcar centroides ────────────────────────────────────────
    # (addr, street_norm, number, portal_int, coord, is_centroid)
    parsed: list[tuple[str, str, str, int | None, GeoResult | None, bool]] = []
    for addr, coord in results:
        try:
            street, number = _parse_address(addr)
            street_norm = _normalize(street)
            portal_int = _extract_portal_int(number)
        except Exception:
            parsed.append((addr, "", "", None, coord, False))
            continue
        is_centroid = _is_nominatim_centroid(addr)
        parsed.append((addr, street_norm, number, portal_int, coord, is_centroid))

    # ── 2. Tabla de referencia: portales con coords reales ────────────────────
    # Son válidos como referencia: Cartociudad, nodo OSM exacto, interpolados.
    # NO son válidos: centroides de Nominatim (osm_type='way') ni None.
    ref_table: dict[str, list[tuple[int, float, float]]] = defaultdict(list)
    for _, street_norm, _, portal_int, coord, is_centroid in parsed:
        if coord is None or portal_int is None or not street_norm:
            continue
        if is_centroid:
            continue  # centroide de Nominatim, no sirve como referencia
        ref_table[street_norm].append((portal_int, coord[0], coord[1]))

    for sn in ref_table:
        ref_table[sn].sort(key=lambda x: x[0])

    # ── 2b. Enriquecer ref_table con entradas de caché de la misma calle ──────
    # Las entradas del batch actual pueden no tener suficientes referencias.
    # Buscamos en _persisted otras entradas de la misma calle con coords reales
    # (Cartociudad, nodo OSM exacto, interpolados) de repartos anteriores.
    streets_needing = {
        sn
        for _, sn, _, portal_int, coord, is_centroid in parsed
        if (coord is None or is_centroid) and portal_int is not None and sn
    }

    for cached_key, entry in _persisted.items():
        parts = cached_key.split("#", 1)
        if len(parts) != 2:
            continue
        sn_cached, num_cached = parts
        if sn_cached not in streets_needing:
            continue
        # Solo si no es centroide de Nominatim
        if entry.get("source") == "nominatim" and entry.get("osm_type") == "way":
            continue
        portal_int_cached = _extract_portal_int(num_cached)
        if portal_int_cached is None:
            continue
        try:
            lat_c = float(entry["lat"])
            lon_c = float(entry["lon"])
        except (KeyError, TypeError, ValueError):
            continue
        # Añadir solo si ese número de portal no está ya en la tabla
        existing_nums = {r[0] for r in ref_table[sn_cached]}
        if portal_int_cached not in existing_nums:
            ref_table[sn_cached].append((portal_int_cached, lat_c, lon_c))

    # Re-ordenar tras añadir entradas de caché
    for sn in ref_table:
        ref_table[sn].sort(key=lambda x: x[0])

    # ── 3. Interpolar ─────────────────────────────────────────────────────────
    improved: list[tuple[str, GeoResult | None]] = []

    for addr, street_norm, number, portal_int, coord, is_centroid in parsed:
        needs_improvement = (coord is None or is_centroid) and portal_int is not None

        if not needs_improvement:
            improved.append((addr, coord))
            continue

        refs = ref_table.get(street_norm, [])
        if len(refs) < 2:
            improved.append((addr, coord))
            continue

        lowers = [r for r in refs if r[0] <= portal_int]
        uppers = [r for r in refs if r[0] > portal_int]

        # Solo interpolamos si hay referencias a AMBOS lados del portal.
        # Sin referencia inferior o superior no extrapolamos: la dirección de
        # numeración de la calle es desconocida y podría colocar el punto
        # en el extremo equivocado.
        if not lowers or not uppers:
            improved.append((addr, coord))
            continue

        ref_low, ref_high = lowers[-1], uppers[0]
        interp = _interpolate_coord(portal_int, ref_low, ref_high)
        if interp is None:
            improved.append((addr, coord))
            continue

        # Guardar en caché con source='interpolated'
        try:
            street, _ = _parse_address(addr)
            key = _cache_key(street, number)
            _cache[key] = interp
            _persist_entry(key, interp[0], interp[1], street, number, {
                "display_name": f"[interpolated] {addr}",
                "address": {"road": street, "house_number": number},
            }, source="interpolated")
        except Exception as e:
            print(f"[geocode] Error guardando interpolación para '{addr}': {e}")

        print(
            f"[geocode] Interpolado: '{addr}' → portal {portal_int} "
            f"({interp[0]:.5f}, {interp[1]:.5f})"
        )
        improved.append((addr, interp))

    return improved


# Cargar caché al importar el módulo
_load_cache()
