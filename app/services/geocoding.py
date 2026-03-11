"""
Servicio de geocodificación multi-fuente.

Caché en disco: clave canónica = normalize(calle)#normalize(número).

Pipeline (en orden de prioridad):
  1. Caché en disco: override permanente, google/places con TTL de GOOGLE_CACHE_TTL_DAYS días.
  2. Fuzzy matching contra catálogo combinado (OSM + aprendidas).
     Sin llamada HTTP. Corrige el nombre de la calle antes de consultar APIs.
  3. Google Geocoding API — solo ROOFTOP → EXACT_ADDRESS.
     Cualquier otro resultado (RANGE_INTERPOLATED, GEOMETRIC_CENTER, APPROXIMATE)
     no se acepta directamente; se intenta con Places si hay alias.
  4. Google Places API — si hay alias de negocio.
  5. FAILED → devuelve None.

Confianza devuelta (str):
  EXACT_ADDRESS  — portal exacto (Google ROOFTOP)
  EXACT_PLACE    — lugar/negocio encontrado por Places
  OVERRIDE       — pin manual
  FAILED         — no geocodificado (requiere pin manual)
"""

import difflib
import json
import math
import re
import time
import unicodedata
from pathlib import Path

import requests

from app.core.config import (
    OVERPASS_USER_AGENT,
    POSADAS_CENTER,
    GOOGLE_API_KEY,
    GOOGLE_GEOCODING_URL,
    GOOGLE_PLACES_URL,
    GOOGLE_CACHE_TTL_DAYS,
    GEOCODE_TIMEOUT,
)
from app.utils.validation import in_work_bbox
from app.core.logging import get_logger

logger = get_logger(__name__)

GeoResult = tuple[float, float]  # (lat, lon)

# ─── Caché en memoria ──────────────────────────────────────────────────────────
_cache: dict[str, GeoResult | None] = {}

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_CACHE_FILE = _DATA_DIR / "geocode_cache.json"
_STREETS_FILE = _DATA_DIR / "osm_streets.json"
_persisted: dict[str, dict] = {}

# Parámetros de fuzzy matching
FUZZY_THRESHOLD = 0.80
STREET_LIST_TTL_DAYS = 7

# Catálogo de calles OSM (cargado lazily)
_osm_streets: list[str] | None = None
_osm_streets_norm: list[str] | None = None
_osm_streets_norm_set: set[str] | None = None  # búsqueda O(1) de pertenencia


# Abreviaturas de tipo de vía que se expanden antes de analizar la dirección
_VIA_ABBREVS = (
    (r"(?<!\w)C/\s*",          "Calle "),       # C/5 → Calle 5
    (r"\bCl\.?(?=\s|$)",       "Calle"),        # Cl. / Cl → Calle
    (r"\bAvda\.?(?=\s|$)",     "Avenida"),      # Avda. / Avda → Avenida
    (r"\bAv\.",                "Avenida"),      # Av. → Avenida
    (r"\bPza\.?(?=\s|$)",      "Plaza"),        # Pza. / Pza → Plaza
    (r"\bCtra\.?(?=\s|$)",     "Carretera"),    # Ctra. / Ctra → Carretera
    (r"\bUrb\.?(?=\s|$)",      "Urbanización"), # Urb. → Urbanización
    (r"\bPsje\.?(?=\s|$)",     "Pasaje"),       # Psje. → Pasaje
    (r"\bPje\.?(?=\s|$)",      "Pasaje"),       # Pje. → Pasaje
    (r"\bRda\.?(?=\s|$)",      "Ronda"),        # Rda. → Ronda
    (r"\bTrav\.?(?=\s|$)",     "Travesía"),     # Trav. → Travesía
)


# ─── Normalización ─────────────────────────────────────────────────────────────

def _normalize(text: str) -> str:
    """Minúsculas, sin acentos, espacios simples."""
    nfkd = unicodedata.normalize("NFKD", text.lower())
    no_acc = "".join(c for c in nfkd if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", no_acc).strip()


def _parse_address(raw: str) -> tuple[str, str]:
    """
    Extrae (nombre_de_calle, número_portal) de una dirección en texto libre.

    Para rangos como "96-98", devuelve "96-98" como número.
    Usa _portal_display() para obtener solo "96" al consultar APIs externas.
    """
    s = raw.strip()

    # 0. Expandir abreviaturas de tipo de vía (C/ → Calle, Av. → Avenida, …)
    for _pat, _repl in _VIA_ABBREVS:
        s = re.sub(_pat, _repl, s, flags=re.IGNORECASE)
    s = re.sub(r"\s+", " ", s).strip()

    # 1. Eliminar sufijo de ciudad/país (precedido por coma)
    s = re.sub(
        r",\s*(posadas|14730|c[oó]rdoba|andaluc[ií]a|espa[nñ]a).*$",
        "", s, flags=re.IGNORECASE,
    ).strip().rstrip(",").strip()

    # 2. Eliminar contenido entre paréntesis y paréntesis sin cerrar
    s = re.sub(r"\s*\([^)]*\)\s*", " ", s)
    s = re.sub(r"\s*\(.*$", "", s)
    s = s.strip().rstrip(",-").strip()

    # 3. Normalizar prefijos de número
    s = re.sub(r"\bn[uú]m[eé]ro\b\.?\s*", " ", s, flags=re.IGNORECASE)
    s = re.sub(r"\bn[uúº°][mn]?\.?(?=[\s\d]|$)", " ", s, flags=re.IGNORECASE)
    s = re.sub(r"\bN\?\s*(?=\d)", " ", s)
    s = re.sub(r"\bn\s*(?=\d)", " ", s, flags=re.IGNORECASE)
    s = re.sub(r"\s+", " ", s).strip()

    # 4. Eliminar indicadores de piso/portal al final
    _noise = (
        r"(?:bajo|baja|bj|local|planta|piso|casa|bis|nave|oficina|taller|"
        r"sotano|s[oó]tano|entreplanta|dcha|izda|izq|der|pta|dup)"
    )
    s = re.sub(
        r"(?<=\d)[\s,]+\d+\s*" + _noise + r"[\s\S]*$",
        "", s, flags=re.IGNORECASE,
    )
    s = re.sub(
        r"[\s,]+(?:\d+[ºo°]\s*[a-zA-Z]?\s*)?" + _noise + r"[\s\S]*$",
        "", s, flags=re.IGNORECASE,
    )

    # 4b. Eliminar detalles de acceso (bloque/portal/escalera/puerta) tras el número
    #     Lookbehind garantiza que sólo actúa cuando hay un dígito previo,
    #     preservando calles como "Calle del Portal" o "Pasaje del Bloque".
    s = re.sub(
        r"(?<=\d)[\s,;]+(?:bloque|portal|escalera|puerta)\b[\s\S]*$",
        "", s, flags=re.IGNORECASE,
    )

    # 5. Eliminar ordinales de piso al final
    s = re.sub(r"([\s,]+\d+[ºo°]\s*[a-zA-Z]?)+$", "", s, flags=re.IGNORECASE)

    # 6. Limpiar puntuación sobrante
    s = s.strip().rstrip(",-./").strip()

    # 7. Extraer número de portal (último token numérico + letra/rango opcional)
    m = re.search(r"[\s,]+(\d+(?:-\d+[a-zA-Z]?|[-\s]?[a-zA-Z])?)\s*$", s)
    if m:
        raw_num = m.group(1)
        number = re.sub(r"\s+", "", raw_num).lower()
        street = s[: m.start()].rstrip(" ,").strip()
        if street:
            return street, number

    if re.search(r"\bs/?n\b", s, re.IGNORECASE):
        street = re.sub(r"\s*,?\s*s/?n.*$", "", s, flags=re.IGNORECASE).strip()
        return street, "sn"

    return s, ""


def _portal_display(number: str) -> str:
    """
    Para rangos como '96-98', extrae solo el número primario para APIs externas.
    '96-98' → '96', '2b' → '2b', '' → ''.
    """
    if not number or number == "sn":
        return ""
    m = re.match(r"^(\d+)", number)
    return m.group(1) if m else number


def _cache_key(street: str, number: str) -> str:
    """Clave canónica: normalize(calle)#normalize(número)."""
    return f"{_normalize(street)}#{_normalize(number)}"


# ─── Catálogo de calles (Overpass + Catastro + aprendidas) ─────────────────────

_OVERPASS_URL = "https://overpass-api.de/api/interpreter"
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
        headers={"User-Agent": OVERPASS_USER_AGENT},
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
        logger.error("Error guardando catálogo OSM: %s", e)


def _get_street_catalog() -> list[str]:
    """
    Devuelve el catálogo combinado de calles, cargándolo lazily.
    Intenta primero el catálogo combinado (catalog.py); si no, solo Overpass.
    """
    global _osm_streets, _osm_streets_norm, _osm_streets_norm_set

    if _osm_streets is not None:
        return _osm_streets

    # Intentar catálogo combinado (OSM + Catastro + aprendidas)
    try:
        from app.services.catalog import get_combined_catalog
        streets = get_combined_catalog()
        if streets:
            _osm_streets = streets
            _osm_streets_norm = [_normalize(s) for s in streets]
            _osm_streets_norm_set = set(_osm_streets_norm)
            return _osm_streets
    except Exception as e:
        logger.error("Error cargando catálogo combinado: %s", e)

    # Fallback: solo Overpass
    osm_streets: list[str] | None = _load_streets_from_disk()
    if osm_streets is None:
        logger.info("Descargando catálogo de calles desde Overpass...")
        try:
            osm_streets = _fetch_streets_from_overpass()
            _save_streets_to_disk(osm_streets)
            logger.info("Catálogo Overpass listo: %d calles", len(osm_streets))
        except Exception as e:
            logger.error("Error descargando Overpass: %s", e)
            _osm_streets = []
            _osm_streets_norm = []
            _osm_streets_norm_set = set()
            return []

    assert osm_streets is not None  # None entra en el if de arriba, que siempre retorna o asigna
    _osm_streets = osm_streets
    _osm_streets_norm = [_normalize(s) for s in osm_streets]
    _osm_streets_norm_set = set(_osm_streets_norm)
    return _osm_streets


# ─── Fuzzy matching ────────────────────────────────────────────────────────────

# Similitud mínima de caracteres para que dos tokens individuales "casen"
_TOKEN_CHAR_THRESHOLD = 0.85
# Máximo de tokens extra que puede tener el catálogo respecto a la query
_MAX_EXTRA_TOKENS = 1


def _token_set_ratio(a: str, b: str) -> float:
    """
    Similitud token-a-token conservadora.

    Estrategia: TODOS los tokens de la query (a) deben tener cobertura en el
    catálogo (b). Si alguno no la tiene, devuelve 0.0 directamente.
    Además el catálogo puede tener como máximo _MAX_EXTRA_TOKENS tokens extra.

    Cobertura de un token:
      - Coincidencia exacta (normalizada) → sim = 1.0
      - SequenceMatcher con cualquier token del catálogo ≥ _TOKEN_CHAR_THRESHOLD
        → sim = ese valor (typo de 1-2 chars)
      - Por debajo → token sin cobertura → score 0.0

    Rationale: Google Geocoding ya gestiona correcciones semánticas; el fuzzy
    matching sólo debe actuar para typos obvios en calles conocidas. Preferimos
    no corregir antes que corregir mal y enviar a Google una calle incorrecta.

    Ejemplos:
      "calle hornoss"        vs "calle hornos"              → 0.96  (typo +s)
      "calle oro"            vs "calle hornos"              → 0.0   (distinto)
      "avenida blas infante" vs "avenida de blas infante"   → 0.95  (1 extra)
      "calle santiago"       vs "calle fernandez de santiago"→ 0.0   (2 extra)
      "avenida de la muralla"vs "avenida de la paz"         → 0.0   ("muralla"≠"paz")
    """
    a_tokens = a.split()
    b_tokens = b.split()

    if not a_tokens:
        return 0.0

    # Rechazar si el catálogo tiene demasiados tokens extra o si la query es más larga
    extra = len(b_tokens) - len(a_tokens)
    if extra > _MAX_EXTRA_TOKENS or extra < 0:
        return 0.0

    b_set = set(b_tokens)

    # Cada token de la query debe tener cobertura en el catálogo
    token_sims: list[float] = []
    for qt in a_tokens:
        if qt in b_set:
            token_sims.append(1.0)
        else:
            best_sim = max(
                (difflib.SequenceMatcher(None, qt, ct).ratio() for ct in b_tokens),
                default=0.0,
            )
            if best_sim < _TOKEN_CHAR_THRESHOLD:
                return 0.0  # Token sin cobertura → descarta la entrada del catálogo
            token_sims.append(best_sim)

    # Score: media de similitudes de tokens, penalización leve por tokens extra
    avg_sim = sum(token_sims) / len(token_sims)
    return avg_sim * (1.0 - 0.05 * extra)


def _find_closest_street(query_street: str) -> str | None:
    """
    Busca en el catálogo el nombre de calle más parecido.
    Devuelve el nombre original (con mayúsculas/acentos) o None si no supera el umbral.
    Devuelve None también si la calle ya está en el catálogo (no hace falta corrección).
    """
    streets = _get_street_catalog()
    if not streets:
        return None

    query_norm = _normalize(query_street)

    # Si la calle normalizada ya está en el catálogo, no hay nada que corregir
    if _osm_streets_norm_set and query_norm in _osm_streets_norm_set:
        return None

    best_score = 0.0
    best_street = None

    for osm_name, osm_norm in zip(streets, _osm_streets_norm or []):
        score = _token_set_ratio(query_norm, osm_norm)
        if score > best_score:
            best_score = score
            best_street = osm_name

    if best_score >= FUZZY_THRESHOLD and best_street and best_street != query_street:
        logger.info("Fuzzy match: '%s' → '%s' (score=%.2f)", query_street, best_street, best_score)
        return best_street

    return None


# ─── Google Geocoding API ──────────────────────────────────────────────────────

def _google_geocode(street: str, number: str) -> tuple[GeoResult, str] | None:
    """
    Geocodifica con Google Geocoding API.
    Devuelve ((lat, lon), location_type) o None.
    location_type: ROOFTOP | RANGE_INTERPOLATED | GEOMETRIC_CENTER | APPROXIMATE
    """
    if not GOOGLE_API_KEY:
        return None

    num_str = _portal_display(number) if number and number != "sn" else ""
    addr_base = f"{street} {num_str}".strip() if num_str else street
    address = f"{addr_base}, Posadas, Córdoba, España"

    params = {
        "address": address,
        "key": GOOGLE_API_KEY,
        "components": "locality:Posadas|country:ES",
        "language": "es",
    }

    try:
        r = requests.get(GOOGLE_GEOCODING_URL, params=params, timeout=GEOCODE_TIMEOUT)
        r.raise_for_status()
        data = r.json()

        if data.get("status") != "OK" or not data.get("results"):
            status = data.get("status", "?")
            if status not in ("ZERO_RESULTS",):
                logger.warning("Google status=%s para '%s'", status, address)
            return None

        result = data["results"][0]
        location = result["geometry"]["location"]
        location_type = result["geometry"].get("location_type", "APPROXIMATE")

        lat = float(location["lat"])
        lng = float(location["lng"])

        if not in_work_bbox(lat, lng):
            logger.warning("Google fuera de bbox (%.4f, %.4f) para '%s'", lat, lng, address)
            return None

        logger.info("Google: '%s' → %s (%.5f, %.5f)", address, location_type, lat, lng)
        return (lat, lng), location_type

    except Exception as e:
        logger.error("Google error: %s", e)
        return None


# ─── Distancia haversine ───────────────────────────────────────────────────────

_PLACES_NAME_SIM_THRESHOLD = 0.55   # similitud mínima nombre Places vs alias
_PLACES_MAX_DIST_M = 300.0          # distancia máxima (m) entre Places y ref Geocoding


def _haversine_m(a: GeoResult, b: GeoResult) -> float:
    """Distancia en metros entre dos coordenadas (lat, lon)."""
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * 6_371_000 * math.asin(math.sqrt(h))


# ─── Google Places API ─────────────────────────────────────────────────────────

def _google_places(alias: str, ref_coord: GeoResult | None = None) -> GeoResult | None:
    """
    Busca un negocio/lugar por nombre con Google Places Find Place.
    Solo se usa cuando Google Geocoding falla/es impreciso y hay alias.

    Validaciones:
      1. bbox de comarca.
      2. Similitud del nombre devuelto con el alias buscado ≥ _PLACES_NAME_SIM_THRESHOLD.
      3. Si ref_coord proporcionada: distancia ≤ _PLACES_MAX_DIST_M.
    """
    if not GOOGLE_API_KEY or not alias:
        return None

    params = {
        "input": f"{alias}, Posadas, Córdoba",
        "inputtype": "textquery",
        "fields": "geometry,name",
        "locationbias": f"circle:1500@{POSADAS_CENTER[0]},{POSADAS_CENTER[1]}",
        "key": GOOGLE_API_KEY,
        "language": "es",
    }

    try:
        r = requests.get(GOOGLE_PLACES_URL, params=params, timeout=GEOCODE_TIMEOUT)
        r.raise_for_status()
        data = r.json()

        if data.get("status") != "OK" or not data.get("candidates"):
            return None

        candidate = data["candidates"][0]
        location = candidate["geometry"]["location"]
        lat = float(location["lat"])
        lng = float(location["lng"])

        if not in_work_bbox(lat, lng):
            logger.warning("Places fuera de bbox para '%s'", alias)
            return None

        # Validar que el nombre devuelto se parece al alias buscado
        name_returned = candidate.get("name", "")
        sim = difflib.SequenceMatcher(
            None, _normalize(alias), _normalize(name_returned)
        ).ratio()
        if sim < _PLACES_NAME_SIM_THRESHOLD:
            logger.warning(
                "Places: nombre '%s' no coincide con alias '%s' (sim=%.2f) → rechazado",
                name_returned, alias, sim,
            )
            return None

        coord: GeoResult = (lat, lng)

        # Validar distancia respecto a la coord de referencia de Geocoding (si existe)
        if ref_coord is not None:
            dist_m = _haversine_m(ref_coord, coord)
            if dist_m > _PLACES_MAX_DIST_M:
                logger.warning(
                    "Places: '%s' a %.0f m de la dirección → rechazado (umbral %d m)",
                    alias, dist_m, _PLACES_MAX_DIST_M,
                )
                return None

        logger.info("Places: '%s' → '%s' (%.5f, %.5f)", alias, name_returned, lat, lng)
        return coord

    except Exception as e:
        logger.error("Google Places error: %s", e)
        return None


# ─── TTL de caché Google ───────────────────────────────────────────────────────

def _google_cache_expired(entry: dict) -> bool:
    """True si una entrada google/places ha superado el TTL configurado."""
    cached_at = entry.get("cached_at")
    if cached_at is None:
        return False
    age_days = (time.time() - float(cached_at)) / 86400
    return age_days > GOOGLE_CACHE_TTL_DAYS


# ─── Persistencia ──────────────────────────────────────────────────────────────

def _save_cache() -> None:
    try:
        _CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        _CACHE_FILE.write_text(
            json.dumps(_persisted, ensure_ascii=False, indent=2), "utf-8"
        )
    except Exception as e:
        logger.error("Error guardando caché: %s", e)


def _load_cache() -> None:
    """Carga entradas del JSON en la caché en memoria al arrancar.
    Descarta entradas google/places expiradas."""
    global _persisted
    if not _CACHE_FILE.exists():
        _persisted = {}
        return
    try:
        raw = json.loads(_CACHE_FILE.read_text("utf-8"))
        _persisted = {}
        for key, entry in raw.items():
            try:
                lat = float(entry["lat"])
                lon = float(entry["lon"])
                src = entry.get("source", "")
                if src == "cartociudad":
                    continue  # Fuente antigua eliminada: entrada ignorada
                if src in ("google", "places") and _google_cache_expired(entry):
                    continue  # Expirada: se re-geocodificará
                _persisted[key] = entry
                _cache[key] = (lat, lon)
                alias_stored = entry.get("alias", "")
                if alias_stored:
                    _cache["@" + _normalize(alias_stored)] = (lat, lon)
            except Exception:
                pass
    except Exception:
        _persisted = {}


def _persist_entry(
    key: str,
    lat: float,
    lon: float,
    street: str,
    number: str,
    source: str = "google",
    confidence: str = "GOOD",
    corrected_to: str | None = None,
    alias: str | None = None,
) -> None:
    """Guarda una entrada geocodificada en disco."""
    entry: dict = {
        "lat": lat,
        "lon": lon,
        "street": street,
        "number": number if number else None,
        "source": source,
        "confidence": confidence,
    }
    if source in ("google", "places"):
        entry["cached_at"] = time.time()
    if corrected_to:
        entry["fuzzy_corrected_to"] = corrected_to
    if alias:
        entry["alias"] = alias
        _cache["@" + _normalize(alias)] = (lat, lon)
    _persisted[key] = entry
    _save_cache()


# ─── API pública ────────────────────────────────────────────────────────────────

def geocode(address: str, alias: str = "") -> tuple[GeoResult | None, str]:
    """
    Geocodifica una dirección. Devuelve ((lat, lon), confidence).
    confidence: EXACT_ADDRESS | EXACT_PLACE | OVERRIDE | FAILED

    Pipeline:
      0. Formato "lat,lon" directo → OVERRIDE.
      1. Caché (_cache): clave de dirección ("calle#num") o clave de alias ("@nombre").
      2. Fuzzy matching en catálogo (corrección de nombre sin API).
      3. Google Geocoding: solo ROOFTOP → EXACT_ADDRESS.
         Resto de resultados (RANGE_INTERPOLATED, GEOMETRIC_CENTER, APPROXIMATE)
         se usan solo como referencia de distancia para validar Places.
      4. Google Places (solo si alias): valida nombre (sim≥0.55) y distancia (≤300m).
      5. FAILED (requiere pin manual).
    """
    if not address or not address.strip():
        return None, "FAILED"

    # 0. Formato "lat,lon" directo
    coord_match = re.match(
        r"^\s*([-+]?\d+\.?\d*)\s*,\s*([-+]?\d+\.?\d*)\s*$",
        address.strip(),
    )
    if coord_match:
        return (float(coord_match.group(1)), float(coord_match.group(2))), "OVERRIDE"

    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)

    # 1. Caché (por dirección o por alias — misma estructura _cache)
    if key in _cache:
        coord = _cache[key]
        entry = _persisted.get(key, {})
        src = entry.get("source", "")
        if src in ("google", "places") and _google_cache_expired(entry):
            # Expirada: limpiar memoria y disco, y re-geocodificar
            del _cache[key]
            if entry.get("alias"):
                _cache.pop("@" + _normalize(entry["alias"]), None)
            _persisted.pop(key, None)
            _save_cache()
        else:
            if coord is None:
                return None, "FAILED"
            confidence = entry.get("confidence", "GOOD")
            return coord, confidence

    if alias:
        alias_coord = _cache.get("@" + _normalize(alias))
        if alias_coord is not None:
            logger.info("Caché por alias '%s' → EXACT_PLACE", alias)
            return alias_coord, "EXACT_PLACE"

    # 2. Fuzzy matching (sin API — solo corrige el nombre de calle)
    corrected_to: str | None = None
    corrected_street = street
    closest = _find_closest_street(street)
    if closest:
        corrected_to = closest
        corrected_street = closest

    # 3. Google Geocoding — solo ROOFTOP es aceptado directamente
    ref_coord: GeoResult | None = None
    google_result = _google_geocode(corrected_street, number)
    if google_result:
        coord, location_type = google_result
        if location_type == "ROOFTOP":
            _cache[key] = coord
            _persist_entry(
                key, coord[0], coord[1], street, number,
                source="google", confidence="EXACT_ADDRESS",
                corrected_to=corrected_to,
                alias=alias if alias else None,
            )
            if corrected_to:
                try:
                    from app.services.catalog import save_learned_street
                    save_learned_street(corrected_to)
                except Exception:
                    pass
            return coord, "EXACT_ADDRESS"
        # RANGE_INTERPOLATED / GEOMETRIC_CENTER / APPROXIMATE:
        # guardar como referencia de distancia para validar Places
        ref_coord = coord

    # 4. Google Places (solo si hay alias de negocio)
    if alias:
        places_coord = _google_places(alias, ref_coord=ref_coord)
        if places_coord:
            _cache[key] = places_coord
            _persist_entry(
                key, places_coord[0], places_coord[1], street, number,
                source="places", confidence="EXACT_PLACE",
                corrected_to=corrected_to, alias=alias,
            )
            return places_coord, "EXACT_PLACE"

    # 5. FAILED
    _cache[key] = None
    return None, "FAILED"


def add_override(address: str, lat: float, lon: float) -> None:
    """
    Registra coordenadas manuales para una dirección (override permanente).
    Tiene prioridad sobre cualquier resultado automático.
    """
    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)
    _cache[key] = (lat, lon)
    _persist_entry(
        key, lat, lon, street, number,
        source="override", confidence="OVERRIDE",
    )


# Cargar caché al importar el módulo
_load_cache()
