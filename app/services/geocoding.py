"""
Servicio de geocodificación multi-fuente.

Caché en disco: clave canónica = normalize(calle)#normalize(número).

Pipeline (en orden de prioridad):
  1. Caché en disco: override permanente, google/places con TTL de GOOGLE_CACHE_TTL_DAYS días.
  2. Fuzzy matching contra catálogo estático (streets.json).
     Sin llamada HTTP. Corrige el nombre de la calle antes de consultar APIs.
  3. Google Geocoding API — solo ROOFTOP → EXACT_ADDRESS.
     Cualquier otro resultado (RANGE_INTERPOLATED, GEOMETRIC_CENTER, APPROXIMATE)
     no se acepta directamente; se intenta con Places si hay alias.
  4. Google Places API — si hay alias de negocio.
  5. FAILED → devuelve None. No se cachea para permitir reintentos en futuras llamadas.

Errores transitorios (timeout, red, HTTP 429/5xx) se reintentan con backoff
exponencial (_GEOCODE_RETRY_DELAYS). Errores permanentes (ZERO_RESULTS, fuera de
bbox) no se reintentan.

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
import threading
import time
from pathlib import Path

import requests

from app.core.config import (
    POSADAS_CENTER,
    GOOGLE_API_KEY,
    GOOGLE_GEOCODING_URL,
    GOOGLE_PLACES_URL,
    GOOGLE_CACHE_TTL_DAYS,
    GEOCODE_TIMEOUT,
)
from app.utils.normalization import normalize_text
from app.utils.validation import in_work_bbox
from app.core.logging import get_logger

logger = get_logger(__name__)

GeoResult = tuple[float, float]  # (lat, lon)

# ─── Caché en memoria ──────────────────────────────────────────────────────────
# Solo almacena coordenadas válidas; los FAILED no se cachean.
_cache: dict[str, GeoResult] = {}

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_CACHE_FILE = _DATA_DIR / "geocode_cache.json"
_persisted: dict[str, dict] = {}

# Parámetros de fuzzy matching
FUZZY_THRESHOLD = 0.80

# Catálogo de calles (cargado lazily desde streets.json vía catalog.py)
_streets: list[str] | None = None
_streets_norm: list[str] | None = None
_streets_norm_set: set[str] | None = None  # búsqueda O(1) de pertenencia

# ─── Threading ─────────────────────────────────────────────────────────────────
# RLock protege _cache, _persisted y _save_cache(). No se mantiene durante
# llamadas a APIs externas (Google) para no serializar peticiones.
_lock = threading.RLock()

# ─── Errores transitorios y reintentos ─────────────────────────────────────────

class _GeoTransientError(Exception):
    """Error transitorio en llamada a API de geocodificación (red, timeout, rate-limit).
    Se reintenta con backoff exponencial; a diferencia de devolver None, indica
    que el problema es temporal y merece reintento.
    """

_GEOCODE_RETRY_DELAYS: tuple[float, ...] = (1.0, 2.0)  # segundos entre reintentos

# ─── Places: distancias de referencia ──────────────────────────────────────────
_PLACES_MAX_DIST_M: float = 300.0           # con ref_coord de Geocoding precisa
_PLACES_MAX_DIST_FALLBACK_M: float = 1000.0  # cuando Google no devuelve ninguna coord

# ─── Title-case para calles españolas ──────────────────────────────────────────
_LOWERCASE_WORDS: frozenset[str] = frozenset({
    "de", "del", "la", "el", "los", "las", "y", "a", "al", "e", "con", "sin",
})

# ─── Abreviaturas de tipo de vía ───────────────────────────────────────────────
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

# Alias local — la implementación canónica vive en app/utils/normalization.py.
_normalize = normalize_text


def _title_street(s: str) -> str:
    """Title-case para nombres de calle respetando preposiciones y artículos españoles.

    'CALLE DE LA PAZ'      → 'Calle de la Paz'
    'avenida blas infante'  → 'Avenida Blas Infante'
    'calle de los olivos'   → 'Calle de los Olivos'
    """
    words = s.split()
    return " ".join(
        w.capitalize() if i == 0 or w.lower() not in _LOWERCASE_WORDS else w.lower()
        for i, w in enumerate(words)
    )


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


def address_key(address: str) -> str:
    """Clave canónica de una dirección para detección de duplicados.

    Expande abreviaturas de tipo de vía (C/ → Calle, Avda → Avenida) y elimina
    sufijos de ciudad antes de normalizar, garantizando que variantes de la
    misma dirección produzcan la misma clave:

      'C/ Gaitán 24'              → 'calle gaitan#24'
      'Calle Gaitán, 24, Posadas' → 'calle gaitan#24'
      'CALLE GAITAN 24'           → 'calle gaitan#24'
    """
    street, number = _parse_address(address.strip())
    return _cache_key(street, number)


def canonical_address(address: str) -> str:
    """Forma canónica de una dirección: expande abreviaturas, normaliza capitalización
    y elimina sufijos de ciudad.

    'C/ gaitán, 24, Posadas'  → 'Calle Gaitán 24'
    'AVDA BLAS INFANTE 5'     → 'Avenida Blas Infante 5'
    'calle de la paz 3'       → 'Calle de la Paz 3'

    Útil para mostrar al usuario y como referencia limpia de la dirección.
    """
    street, number = _parse_address(address.strip())
    parts = [_title_street(street)]
    if number:
        parts.append(number)
    return " ".join(parts)


def get_corrected_street(address: str) -> str:
    """
    Devuelve el nombre de calle más preciso conocido para una dirección.

    Si el fuzzy matching corrigió el nombre de calle durante la geocodificación,
    devuelve el nombre corregido guardado en caché (fuzzy_corrected_to).
    En caso contrario devuelve el nombre de calle extraído del texto original.

    Uso: obtener el street_hint para snap_to_street; el nombre corregido
    mejora el matching contra los nombres de la red viaria OSRM.
    """
    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)
    corrected = _persisted.get(key, {}).get("fuzzy_corrected_to")
    return corrected if corrected else street


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


# ─── Catálogo de calles (streets.json — solo lectura) ──────────────────────────

def _get_street_catalog() -> list[str]:
    """Devuelve el catálogo de calles, cargándolo lazily desde catalog.py."""
    global _streets, _streets_norm, _streets_norm_set

    if _streets is not None:
        return _streets

    try:
        from app.services.catalog import get_catalog
        streets = get_catalog()
        _streets = streets
        _streets_norm = [_normalize(s) for s in streets]
        _streets_norm_set = set(_streets_norm)
        return _streets
    except Exception as e:
        logger.error("Error cargando catálogo de calles: %s", e)
        return []


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
    if _streets_norm_set and query_norm in _streets_norm_set:
        return None

    best_score = 0.0
    best_street = None

    for osm_name, osm_norm in zip(streets, _streets_norm or []):
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
    Devuelve ((lat, lon), location_type) o None si la dirección no se encuentra.
    Lanza _GeoTransientError para errores de red, timeout o rate-limit (429/5xx).
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
        if r.status_code == 429 or r.status_code >= 500:
            raise _GeoTransientError(f"HTTP {r.status_code} para '{address}'")
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

    except _GeoTransientError:
        raise
    except requests.Timeout:
        raise _GeoTransientError(f"timeout ({GEOCODE_TIMEOUT}s) para '{address}'")
    except requests.ConnectionError as exc:
        raise _GeoTransientError(f"error de red para '{address}': {exc}")
    except Exception as e:
        logger.error("Google Geocoding error: %s", e)
        return None


# ─── Distancia haversine ───────────────────────────────────────────────────────

def _haversine_m(a: GeoResult, b: GeoResult) -> float:
    """Distancia en metros entre dos coordenadas (lat, lon)."""
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * 6_371_000 * math.asin(math.sqrt(h))


# ─── Google Places API ─────────────────────────────────────────────────────────

def _places_name_matches(alias: str, name_returned: str) -> bool:
    """True si el nombre devuelto por Places corresponde al alias buscado.

    Comparación basada en tokens: todos los tokens significativos (longitud ≥ 3)
    del alias deben tener cobertura en los tokens del nombre devuelto
    (coincidencia exacta o similitud ≥ _TOKEN_CHAR_THRESHOLD).

    Más robusto que SequenceMatcher puro ante nombres que comparten subsecuencias
    largas pero son negocios distintos (ej. "Bar El Gato" vs "El Gato Azul":
    el token "bar" no aparece en el nombre devuelto → rechazado).

    Fallback para alias sin tokens significativos (solo artículos/preposiciones):
    SequenceMatcher ≥ 0.70.
    """
    alias_norm = _normalize(alias)
    name_norm = _normalize(name_returned)

    sig_tokens = [t for t in alias_norm.split() if len(t) >= 3]
    if not sig_tokens:
        # Solo tokens cortos — fallback a similitud de cadena completa
        return difflib.SequenceMatcher(None, alias_norm, name_norm).ratio() >= 0.70

    name_tokens = name_norm.split()
    for token in sig_tokens:
        if token in name_tokens:
            continue
        best = max(
            (difflib.SequenceMatcher(None, token, nt).ratio() for nt in name_tokens),
            default=0.0,
        )
        if best < _TOKEN_CHAR_THRESHOLD:
            return False
    return True


def _google_places(
    alias: str,
    ref_coord: GeoResult,
    max_dist: float,
) -> GeoResult | None:
    """
    Busca un negocio/lugar por nombre con Google Places Find Place.
    Solo se usa cuando Google Geocoding falla/es impreciso y hay alias.
    Lanza _GeoTransientError para errores de red, timeout o rate-limit (429/5xx).

    Validaciones:
      1. bbox de comarca.
      2. Nombre devuelto satisface _places_name_matches (comparación por tokens).
      3. Distancia a ref_coord ≤ max_dist.
         ref_coord puede ser la coord de Geocoding (precisa) o POSADAS_CENTER (fallback
         cuando Google no devuelve ningún resultado), con max_dist ajustado en cada caso.
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
        if r.status_code == 429 or r.status_code >= 500:
            raise _GeoTransientError(f"HTTP {r.status_code} para alias '{alias}'")
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

        name_returned = candidate.get("name", "")
        if not _places_name_matches(alias, name_returned):
            logger.warning(
                "Places: nombre '%s' no coincide con alias '%s' → rechazado",
                name_returned, alias,
            )
            return None

        coord: GeoResult = (lat, lng)
        dist_m = _haversine_m(ref_coord, coord)
        if dist_m > max_dist:
            logger.warning(
                "Places: '%s' a %.0f m de la referencia → rechazado (umbral %.0f m)",
                alias, dist_m, max_dist,
            )
            return None

        logger.info("Places: '%s' → '%s' (%.5f, %.5f)", alias, name_returned, lat, lng)
        return coord

    except _GeoTransientError:
        raise
    except requests.Timeout:
        raise _GeoTransientError(f"timeout ({GEOCODE_TIMEOUT}s) para alias '{alias}'")
    except requests.ConnectionError as exc:
        raise _GeoTransientError(f"error de red para alias '{alias}': {exc}")
    except Exception as e:
        logger.error("Google Places error: %s", e)
        return None


# ─── Retry para errores transitorios ──────────────────────────────────────────

def _call_with_retry(fn, *args, **kwargs):
    """Ejecuta fn(*args, **kwargs) con reintentos exponenciales ante _GeoTransientError.

    Devuelve el resultado de fn si tiene éxito, o None si se agotan los reintentos.
    fn debe devolver None (fallo permanente) o lanzar _GeoTransientError (transitorio).
    """
    for attempt, delay in enumerate((*_GEOCODE_RETRY_DELAYS, None)):
        try:
            return fn(*args, **kwargs)
        except _GeoTransientError as exc:
            if delay is None:
                logger.error("%s: agotados reintentos → %s", fn.__name__, exc)
                return None
            logger.warning(
                "%s: error transitorio (%s), reintentando en %.0fs…",
                fn.__name__, exc, delay,
            )
            time.sleep(delay)
    return None  # inalcanzable


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
    confidence: str = "EXACT_ADDRESS",
    corrected_to: str | None = None,
    alias: str | None = None,
) -> None:
    """Guarda una entrada geocodificada en disco. Debe llamarse bajo _lock."""
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
         Los FAILED nunca se cachean: siempre se reintenta en la próxima llamada.
      2. Fuzzy matching en catálogo (corrección de nombre sin API).
      3. Google Geocoding: solo ROOFTOP → EXACT_ADDRESS.
         Resto de resultados (RANGE_INTERPOLATED, GEOMETRIC_CENTER, APPROXIMATE)
         se usan solo como referencia de distancia para validar Places.
      4. Google Places (solo si alias): valida tokens del nombre y distancia.
         Si Google no devolvió ninguna coord, usa POSADAS_CENTER como referencia
         con radio ampliado (_PLACES_MAX_DIST_FALLBACK_M).
      5. FAILED — no se cachea para permitir reintentos en futuras llamadas.
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

    # 1. Caché — protegida por _lock
    with _lock:
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
                confidence = entry.get("confidence", "EXACT_ADDRESS")
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
    google_result = _call_with_retry(_google_geocode, corrected_street, number)
    if google_result:
        coord, location_type = google_result
        if location_type == "ROOFTOP":
            with _lock:
                _cache[key] = coord
                _persist_entry(
                    key, coord[0], coord[1], street, number,
                    source="google", confidence="EXACT_ADDRESS",
                    corrected_to=corrected_to,
                    alias=alias if alias else None,
                )
            return coord, "EXACT_ADDRESS"
        # RANGE_INTERPOLATED / GEOMETRIC_CENTER / APPROXIMATE — no aceptado:
        # guardar como referencia de distancia para validar Places
        ref_coord = coord

    # 4. Google Places (solo si hay alias de negocio)
    if alias:
        # Si Geocoding no devolvió ninguna coord, usar POSADAS_CENTER con radio más amplio
        places_ref = ref_coord if ref_coord is not None else POSADAS_CENTER
        places_max_dist = _PLACES_MAX_DIST_M if ref_coord is not None else _PLACES_MAX_DIST_FALLBACK_M
        places_coord = _call_with_retry(_google_places, alias, places_ref, places_max_dist)
        if places_coord:
            with _lock:
                _cache[key] = places_coord
                _persist_entry(
                    key, places_coord[0], places_coord[1], street, number,
                    source="places", confidence="EXACT_PLACE",
                    corrected_to=corrected_to, alias=alias,
                )
            return places_coord, "EXACT_PLACE"

    # 5. FAILED — no se cachea para permitir reintentos en futuras llamadas
    return None, "FAILED"


def add_override(address: str, lat: float, lon: float) -> None:
    """
    Registra coordenadas manuales para una dirección (override permanente).
    Tiene prioridad sobre cualquier resultado automático.
    Las coordenadas deben ser válidas (verificadas por el router antes de llamar).
    """
    street, number = _parse_address(address.strip())
    key = _cache_key(street, number)
    with _lock:
        _cache[key] = (lat, lon)
        _persist_entry(
            key, lat, lon, street, number,
            source="override", confidence="OVERRIDE",
        )


# Cargar caché al importar el módulo
_load_cache()
