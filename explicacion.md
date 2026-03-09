# Documentación Técnica — App Repartir

Sistema de optimización de rutas de reparto para Posadas, Córdoba (España).
Compuesto por un backend Python/FastAPI, una app móvil Flutter, y servicios Docker (OSRM) y el solver LKH3.

> **Primera vez en el proyecto?** Sigue primero la [Guía de instalación](GUIA_INSTALACION.md) para montar el entorno desde cero. Este documento asume que ya tienes todo instalado.

---

## Para empezar: flujo de desarrollo

### 1. Arrancar los servicios

```bash
cd /ruta/a/app_repartir
./start.sh start   # inicia OSRM (Docker), backend FastAPI y ngrok
./start.sh status  # comprueba que todo está verde
```

Si solo quieres el backend (sin Docker ni ngrok, p. ej. para depuración muy rápida):

```bash
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Depurar la app Flutter en el navegador (recomendado)

La forma más rápida de iterar sin dispositivo físico ni emulador:

```bash
# Asegúrate de que api_config.dart apunta al backend local (ver más abajo)
cd flutter_app
flutter run -d web-server --web-port=8080
# Abre http://localhost:8080 en el navegador
```

> **Limitaciones en web:** el GPS real y el file picker nativo de Android no funcionan en el navegador, pero la lógica de negocio, el mapa y las llamadas al backend se pueden probar completamente.

### 3. Compilar APK para dispositivo físico

```bash
# 1. Cambia api_config.dart a la URL de ngrok (ver más abajo)
cd flutter_app
flutter build apk --release
# APK resultante en: build/app/outputs/flutter-apk/app-release.apk
```

Instálalo en el móvil copiando el APK o con `flutter install` (USB + depuración USB activada).

### Cambiar la URL del backend

Archivo: [`flutter_app/lib/config/api_config.dart`](flutter_app/lib/config/api_config.dart)

```dart
// Para debug en navegador (flutter run -d web-server):
static const String baseUrl = 'http://127.0.0.1:8000';

// Para APK en dispositivo físico (necesita ngrok activo):
static const String baseUrl = 'https://xxxx-xxx.ngrok-free.app';
```

> La URL de ngrok cambia cada vez que reinicias ngrok (plan gratuito). Recuerda recompilar el APK tras cambiarla.

---

## Índice

- [Para empezar: flujo de desarrollo](#para-empezar-flujo-de-desarrollo)
1. [Visión general y flujo completo](#1-visión-general-y-flujo-completo)
2. [Backend Python](#2-backend-python)
   - [main.py](#21-mainpy)
   - [core/config.py](#22-coreconfigpy)
   - [models/__init__.py](#23-modelsinitpy)
   - [routers/optimize.py](#24-routersoptimizepy)
   - [routers/validation.py](#25-routersvalidationpy)
   - [services/geocoding.py](#26-servicesgecodingpy)
   - [services/routing.py](#27-servicesroutingpy)
3. [Flutter App](#3-flutter-app)
   - [main.dart](#31-maindart)
   - [config/api_config.dart](#32-configapi_configdart)
   - [config/app_theme.dart](#33-configapp_themedart)
   - [models/route_models.dart](#34-modelsroute_modelsdart)
   - [models/validation_models.dart](#35-modelsvalidation_modelsdart)
   - [models/delivery_state.dart](#36-modelsdelivery_statedart)
   - [models/csv_data.dart](#37-modelscsv_datadart)
   - [services/api_service.dart](#38-servicesapi_servicedart)
   - [services/csv_service.dart](#39-servicescsv_servicedart)
   - [services/location_service.dart](#310-serviceslocation_servicedart)
   - [services/persistence_service.dart](#311-servicespersistence_servicedart)
   - [screens/splash_screen.dart](#312-screenssplash_screendart)
   - [screens/import_screen.dart](#313-screensimport_screendart)
   - [screens/loading_order_screen.dart](#314-screensloading_order_screendart)
   - [screens/result_screen.dart](#315-screensresult_screendart)
   - [screens/delivery_screen.dart](#316-screensdelivery_screendart)
   - [widgets/route_map.dart](#317-widgetsroute_mapdart)
   - [widgets/stops_list.dart](#318-widgetstops_listdart)
   - [widgets/stats_banner.dart](#319-widgetsstats_bannerdart)
   - [widgets/origin_selector.dart](#320-widgetsorigin_selectordart)
4. [Diagrama de flujo de datos](#4-diagrama-de-flujo-de-datos)
5. [Servicios externos](#5-servicios-externos)

---

## 1. Visión general y flujo completo

```
[App Flutter]
    │
    ├─ Selecciona CSV (cliente, dirección, ciudad [, nota] [, alias])
    │       └─ CsvService.parse() → CsvData
    │
    ├─ POST /api/validation/start
    │       └─ Backend agrupa duplicados y geocodifica cada dirección única:
    │            1. Caché en disco (override permanente > google/places con TTL 30 días)
    │            2. Fuzzy matching en catálogo OSM + aprendidas (sin llamada HTTP)
    │            3. Google Geocoding API (ROOFTOP → EXACT_ADDRESS, RANGE_INTERPOLATED → GOOD)
    │            4. Google Places API (si hay alias y Google no fue exacto) → EXACT_PLACE
    │            5. FAILED
    │          Devuelve: geocoded[] (con coords + confidence) + failed[] (sin coords)
    │
    ├─ ValidationReviewScreen: el usuario revisa paradas, puede re-pinanr cualquier marcador
    │       └─ POST /api/validation/override → guarda pin manual en caché permanente
    │
    ├─ POST /api/optimize
    │       └─ Backend recibe coords ya resueltas (no re-geocodifica)
    │          → LKH3 resuelve el TSP (orden óptimo de visita)
    │          → Post-proceso: _reorder_no_backtrack agrupa paradas "de paso" (desvío ≤ 20 m)
    │          → OSRM calcula geometría de la ruta completa
    │          Devuelve: lista ordenada de paradas + polilínea GeoJSON
    │
    ├─ ResultScreen: mapa con ruta, estadísticas, orden de carga LIFO
    │
    └─ DeliveryScreen: navegación GPS en tiempo real
            ├─ GET /api/route-segment → tramo OSRM GPS→próxima parada (refresco cada 10 s)
            ├─ Re-pin de paradas durante el reparto (MapPickerScreen)
            └─ Hive: persistencia local del estado de cada entrega
```

---

## 2. Backend Python

### 2.1 `main.py`

Punto de entrada de la aplicación FastAPI.

**Qué hace:**
- Inicializa la app con título "Posadas Route Planner" v2.2.0
- Configura CORS abierto (`allow_origins=["*"]`) para cualquier cliente
- Monta directorio `/static` para archivos estáticos
- Registra los dos routers: `optimize.router` en `/api` y `validation.router` en `/api`
- Expone tres endpoints propios:

**GET /health**
- Sin parámetros
- Respuesta: `{"status": "ok", "version": "2.2.0"}`
- Uso: comprobación de vida del servidor desde la app

**GET /api/services/status**
- Sin parámetros
- Prueba OSRM: GET `localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false` (timeout 5s)
- Respuesta:
  ```json
  {
    "osrm": {"url": "http://localhost:5000", "status": "ok|down"},
    "all_ok": true|false
  }
  ```

**GET /api/route-segment**
- Parámetros query: `origin_lat`, `origin_lon`, `dest_lat`, `dest_lon` (floats)
- Llama a OSRM: `GET localhost:5000/route/v1/driving/{lon},{lat};{lon},{lat}?overview=full&geometries=geojson`
- Respuesta: `{"geometry": <GeoJSON>, "distance_m": <int>}`
- En error: `{"geometry": null, "distance_m": 0}`
- Uso: la app lo llama durante la entrega para dibujar el tramo GPS → siguiente parada

---

### 2.2 `core/config.py`

Fuente única de verdad para todas las constantes del sistema. Carga variables de entorno desde `.env` mediante `python-dotenv`.

| Constante | Valor | Propósito |
|-----------|-------|-----------|
| `OSRM_BASE_URL` | `http://localhost:5000` | Contenedor Docker OSRM |
| `GOOGLE_API_KEY` | (desde `.env`) | Clave para Google Geocoding y Places APIs |
| `GOOGLE_GEOCODING_URL` | `https://maps.googleapis.com/maps/api/geocode/json` | Endpoint de geocodificación |
| `GOOGLE_PLACES_URL` | `https://maps.googleapis.com/maps/api/place/findplacefromtext/json` | Endpoint de Places |
| `GOOGLE_CACHE_TTL_DAYS` | `30` | Días antes de que expiren entradas google/places de la caché |
| `OVERPASS_USER_AGENT` | `posadas-route-planner/1.4.0 (local)` | User-Agent para Overpass API (catálogo de calles OSM) |
| `DEPOT_LAT / DEPOT_LON` | `37.8055, -5.0998` | Coordenadas exactas del depósito (Av. de Andalucía) |
| `START_ADDRESS` | `"Avenida de Andalucía, Posadas"` | Dirección de origen por defecto |
| `POSADAS_CENTER` | `(DEPOT_LAT, DEPOT_LON)` | Centro del mapa y bias para Places API |
| `MAX_STOPS` | `200` | Máximo de paradas por petición |
| `GEOCODE_TIMEOUT` | `30` s | Timeout por llamada a APIs externas |
| `OSRM_TIMEOUT` | `60` s | Timeout para OSRM |


---

### 2.3 `models/__init__.py`

Contratos de datos Pydantic entre frontend y backend.

**Modelos de entrada:**

`OptimizeRequest`
- `addresses: list[str]` — direcciones a visitar (requerido, mínimo 1)
- `client_names: list[str] | None` — nombres de cliente, mismo orden que addresses
- `start_address: str | None` — dirección de origen (usa START_ADDRESS si no se indica)
- `coords: list[list[float] | None] | None` — coordenadas pre-resueltas `[lat, lon]`; si se proporcionan se omite la geocodificación
- `package_counts: list[int] | None` — paquetes por dirección; si se proporciona, las direcciones ya vienen agrupadas (no se re-agrupan)
- `all_client_names: list[list[str]] | None` — todos los nombres por dirección cuando viene pre-agrupado
- `packages_per_stop: list[list[Package]] | None` — paquetes con `client_name` + `nota` por parada (reemplaza a `all_client_names`)
- `aliases: list[str] | None` — alias (nombre de negocio) por dirección, para mostrar en la UI

**Modelos de salida:**

`StopInfo` — una parada en la ruta
- `order: int` — posición en la secuencia (0 = origen)
- `address: str` — dirección completa
- `alias: str` — nombre de negocio/lugar (vacío si no aplica)
- `label: str` — etiqueta legible ("🏠 Origen", "📍 Juan García")
- `client_name: str` — nombre principal del cliente
- `client_names: list[str]` — todos los destinatarios en esta dirección
- `packages: list[Package]` — paquetes individuales con `client_name` y `nota`
- `type: str` — "origin" o "stop"
- `lat, lon: float | None` — coordenadas; `None` si geocodificación fallida
- `distance_meters: float` — distancia acumulada desde el origen
- `geocode_failed: bool` — True si no se pudo geocodificar
- `package_count: int` — número de paquetes

`RouteSummary` — resumen de la ruta
- `total_stops: int`, `total_packages: int`
- `total_distance_m: float`, `total_distance_display: str` (ej: "4.2 km")
- `computing_time_ms: float` — tiempo de cómputo del TSP

`OptimizeResponse` — respuesta completa de /optimize
- `success: bool`, `summary: RouteSummary`
- `stops: list[StopInfo]` — lista ordenada de paradas
- `geometry: dict` — GeoJSON de la polilínea

`ErrorResponse` — error estándar
- `success: bool = False`, `error: str`, `detail: str`

---

### 2.4 `routers/optimize.py`

Lógica principal de optimización. Orquesta: deduplicación → geocodificación → snap → LKH3 → OSRM.

**Funciones auxiliares:**

`_normalize_for_dedup(addr: str) → str`
Normaliza una dirección para detectar duplicados: quita acentos, pasa a minúsculas, elimina puntuación, colapsa espacios.
Ejemplo: `"Calle Gaitán 1,"` → `"calle gaitan 1"`

`_group_duplicate_addresses(addresses, client_names) → tuple`
Agrupa filas del CSV que tienen la misma dirección normalizada. Usa `OrderedDict` para preservar el orden de primera aparición.
- Entrada: lista de direcciones con sus nombres de cliente
- Salida: `(unique_addresses, primary_names, all_names_lists, package_counts)`
- Ejemplo: `["Calle A", "Calle A", "Calle B"]` con clientes `["Ana", "Bob", ""]` → `(["Calle A", "Calle B"], ["Ana", ""], [["Ana","Bob"],[""]], [2, 1])`

**POST /api/optimize — flujo paso a paso:**

1. **Validación de entrada**: limpia y verifica que la lista no esté vacía y no supere MAX_STOPS (200)

2. **Decisión de agrupación**:
   - Si `package_counts` viene en la petición → datos ya agrupados (vienen de validación previa), se usan tal cual
   - Si no → se llama a `_group_duplicate_addresses()` para fusionar filas con la misma dirección

3. **Geocodificación del origen**: llama a `geocode(origin_addr)`; lanza 400 si falla

4. **Geocodificación de paradas** (tres casos):
   - Caso A: datos pre-agrupados + `coords` proporcionadas → se usan directamente (flujo normal tras validación)
   - Caso B: `coords` proporcionadas para datos sin agrupar → se deduplicam coords por clave normalizada
   - Caso C: sin `coords` → se llama a `geocode_batch()` para todo
   - Resultado: lista de paradas "ok" (con coords) y lista de paradas "fallidas" (sin coords)

5. **Ensamblado de coordenadas**: `all_coords = [origen] + [paradas_ok]`

6. **Optimización TSP con LKH3**: llama a `optimize_route(all_coords)`
   - Devuelve `waypoint_order`: lista de índices en orden óptimo; aplica `_reorder_no_backtrack` (desvío ≤ 20 m)
   - Lanza 503 si LKH3 falla o OSRM no está disponible

7. **Ruta detallada con OSRM**: reordena coords según `waypoint_order` y llama a `get_route_details()`
   - Devuelve geometría GeoJSON de la ruta completa
   - Lanza 503 si OSRM no está disponible

8. **Construcción de la respuesta**:
   - Para cada índice en `waypoint_order`: crea `StopInfo` con label y distancia acumulada
   - Las paradas fallidas se añaden al final con `geocode_failed=True` y coords del centro de Posadas
   - Devuelve `OptimizeResponse` completa

---

### 2.5 `routers/validation.py`

Valida y geocodifica direcciones antes de la optimización. No llama a OSRM.

**Modelos propios:**

`CsvRow`: `cliente: str`, `direccion: str`, `ciudad: str`, `nota: str`, `alias: str`

`StartRequest`: `rows: list[CsvRow]` — filas crudas del CSV

`GeocodedStop` — parada geocodificada con éxito:
- `address`, `alias`, `client_name`, `all_client_names`, `packages`, `package_count`, `lat`, `lon`
- `confidence: str` — nivel de confianza: `EXACT_ADDRESS | GOOD | EXACT_PLACE | OVERRIDE`

`FailedStop` — parada que no pudo geocodificarse:
- `address`, `alias`, `client_names`, `packages`, `package_count`

`StartResponse`:
- `geocoded: list[GeocodedStop]`, `failed: list[FailedStop]`
- `total_packages` (filas recibidas), `unique_addresses` (direcciones únicas)

**POST /api/validation/start — flujo:**

1. Agrupa filas por dirección normalizada usando `OrderedDict` (primera aparición gana). El primer alias no vacío del grupo se usa como alias de la parada.
2. Para cada dirección única: llama a `geocode(addr, alias=alias)` — pipeline completo con Google.
3. Devuelve listas separadas `geocoded` y `failed` con niveles de confianza.

**POST /api/validation/override — flujo:**

Recibe `{address, lat, lon}` y llama a `add_override()`, que guarda las coordenadas como override permanente en caché RAM y en disco. Tiene prioridad máxima en futuros repartos.

**Diferencia clave con optimize.py**: devuelve todos los resultados (ok y fallidos) sin calcular ruta. Permite al usuario ver y corregir paradas problemáticas antes de optimizar.

---

### 2.6 `services/geocoding.py`

Convierte direcciones en coordenadas GPS usando Google Geocoding API y Google Places API, con caché persistente en disco, fuzzy matching contra catálogo de calles OSM y soporte para overrides manuales (pin de usuario).

**Estado global:**
- `_cache: dict[str, GeoResult | None]` — caché en memoria; clave canónica = `normalize(calle)#normalize(número)`. También almacena entradas `"@alias_normalizado"` para búsqueda por nombre de negocio.
- `_persisted: dict[str, dict]` — espejo del `geocode_cache.json` en disco, con metadatos (source, confidence, cached_at, etc.)

**Clave canónica y normalización:**

`_normalize(text)` → minúsculas, sin acentos, espacios simples.

`_parse_address(raw)` → extrae `(nombre_calle, número_portal)` manejando abreviaturas de vía (C/ → Calle, Avda. → Avenida…), sufijos de ciudad, indicadores de piso/puerta, rangos (96-98) y `s/n`.

`_cache_key(street, number)` → `"normalize(calle)#normalize(número)"`.

**Catálogo de calles y fuzzy matching:**

`_get_street_catalog()` → devuelve el catálogo combinado (OSM + aprendidas) cargado desde `catalog.py`. Si falla, cae back a Overpass API con TTL de 7 días en disco (`osm_streets.json`).

`_find_closest_street(query_street)` → compara `query_street` contra el catálogo con `_token_set_ratio()`. Solo devuelve coincidencia si supera `FUZZY_THRESHOLD = 0.80` y la calle no está ya en el catálogo. Estrategia conservadora: todos los tokens de la query deben tener cobertura en la entrada del catálogo (typos de 1-2 chars admitidos, diferencias semánticas rechazadas).

**Pipeline de geocodificación — `geocode(address, alias="") → (GeoResult | None, confidence)`:**

1. **Formato lat,lon directo** → si la dirección ya es `"37.80,-5.10"`, se devuelve directamente con confianza `OVERRIDE`.
2. **Caché en memoria** (`_cache[key]`) → si existe y no ha expirado (entradas google/places tienen TTL de 30 días), devuelve inmediatamente. Si expiró, se limpia para re-geocodificar.
3. **Caché por alias** (`_cache["@alias_normalizado"]`) → si hay alias y está en caché, devuelve con confianza `EXACT_PLACE`.
4. **Fuzzy matching** (sin HTTP) → intenta corregir el nombre de calle antes de consultar Google.
5. **Google Geocoding API** → si el resultado es `ROOFTOP`: guarda con `EXACT_ADDRESS`; si es `RANGE_INTERPOLATED`: guarda con `GOOD`; si es `GEOMETRIC_CENTER` o `APPROXIMATE`: no guarda, continúa al paso siguiente.
6. **Google Places API** (solo si `alias` no vacío) → busca el negocio en un radio de 1500 m alrededor del centro de Posadas. Guarda con `EXACT_PLACE`.
7. **FAILED** → guarda `None` en caché de memoria (no en disco) para evitar reintentos en la misma sesión.

**Persistencia:**

`_load_cache()` — al importar el módulo, carga `geocode_cache.json` en `_cache` y `_persisted`. Descarta entradas con source cartociudad (fuente antigua) y entradas google/places expiradas.

`_persist_entry(key, lat, lon, street, number, source, confidence, ...)` — guarda en `_persisted` y llama a `_save_cache()` para escribir el JSON en disco.

**API pública:**

`geocode(address, alias="") → (GeoResult | None, str)` — pipeline completo descrito arriba.

`geocode_batch(addresses) → list[(str, GeoResult | None)]` — itera `geocode()` sin alias. Usado como fallback legacy en `/optimize` cuando no se reciben coordenadas pre-resueltas.

`add_override(address, lat, lon)` — registra un pin manual. Fuente `"override"`, confianza `OVERRIDE`, prioridad máxima y sin TTL.

---

### 2.7 `services/routing.py`

Motor de optimización de rutas: LKH3 (TSP), OSRM (geometría y matriz de distancias), snap cache.

**Caché de snap** (`_snap_cache`, `snap_cache.json`)

Persiste en disco los resultados de OSRM `/nearest` (coordenada de entrada → coordenada snapeada a la red viaria). Sin TTL: los datos son estables mientras no cambie el mapa OSM. Se invalida borrando el fichero (lo hace `start.sh rebuild-map` automáticamente antes del extract).
- Clave: `"{lat:.5f},{lon:.5f}>{hint_normalizado}"`
- Valor: `[snap_lat, snap_lon]`
- Los fallos (None) no se cachean: se reintentan en cada llamada.

**`snap_to_street(lat, lon, street_hint) → tuple | None`**

Ajusta una coordenada al nodo de red viaria más cercano cuyo nombre de calle coincida con `street_hint`. Primero comprueba el caché en memoria; si hay miss, llama a OSRM `/nearest` con hasta 15 candidatos, selecciona el que mejor encaje con el hint (fuzzy sobre palabras significativas), guarda el resultado en caché y lo persiste en disco.

Devuelve `None` si el nodo más cercano supera 150 m (coordenada fuera del mapa OSRM).

**`get_osrm_matrix(coords) → tuple | None`**

Llama a OSRM `/table` con todas las coords snapeadas. Devuelve `(dur_matrix, dist_matrix)` como listas de listas de enteros. Una sola petición HTTP para N coords.

**`_solve_with_lkh(dist_matrix, dur_matrix) → list[int] | None`**

Resuelve el TSP abierto (sin retorno al depósito) vía subprocess al binario LKH3. Usa el truco ATSP + nodo fantasma:
- `cost(i → fantasma) = 0` → cualquier nodo puede ser el último
- `cost(fantasma → depósito) = 0` → retorno gratuito

Escribe los ficheros `.atsp` y `.par` en un directorio temporal, ejecuta LKH3, parsea el fichero `.tour`. Devuelve `None` si el binario no está disponible o falla.

**`_reorder_no_backtrack(ordered_ids, dist_matrix, threshold_m=20) → tuple`**

Post-proceso sobre el orden LKH3. Para cada parada `j` en posición `i`, busca el primer tramo anterior `(a → b)` donde el desvío para visitar `j` sea ≤ 20 m:

```
desvío = dist[a][j] + dist[j][b] − dist[a][b]
```

Si lo encuentra, mueve `j` a esa posición. Usa `moved_ids: set` para evitar ciclos (una parada se mueve como máximo una vez). Complejidad O(N²), < 1 ms para N=50.

**`optimize_route(coords) → dict | None`**

Flujo completo:
1. `get_osrm_matrix(coords)` → `(dur_matrix, dist_matrix)`
2. `_solve_with_lkh(dist_matrix, dur_matrix)` → `ordered_ids` (usa dist como coste)
3. `_reorder_no_backtrack(ordered_ids, dist_matrix)` → post-proceso
4. `_build_stop_details(ordered_ids, dur_matrix, dist_matrix)` → distancias acumuladas

Devuelve:
```python
{
  "waypoint_order": [0, 3, 1, 2],
  "stop_details": [
    {"original_index": 3, "arrival_distance": 500.0, "arrival_duration": 45.0},
    ...
  ],
  "total_distance": 2500.0,
  "total_duration": 180.0,
  "computing_time_ms": 350
}
```

**`get_route_details(coords_ordered) → dict | None`**

Dado el orden optimizado, llama a OSRM `/route` para obtener la geometría GeoJSON de la ruta completa.

```python
{
  "geometry": {...},        # GeoJSON LineString
  "total_distance": 2500,   # metros
  "total_duration": 180     # segundos
}
```

---

## 3. Flutter App

### 3.1 `main.dart`

Punto de entrada de la app.

- Llama a `WidgetsFlutterBinding.ensureInitialized()`
- Llama a `PersistenceService.init()` (inicializa Hive)
- Monta `MaterialApp` con:
  - `appLightTheme` / `appDarkTheme` (sigue el tema del sistema)
  - `home: SplashScreen()`
  - Banner de debug oculto

---

### 3.2 `config/api_config.dart`

Clase estática de solo lectura con toda la configuración de red. No se puede instanciar.

| Constante | Valor |
|-----------|-------|
| `baseUrl` | URL ngrok de producción (comentada: `http://127.0.0.1:8000` para desarrollo) |
| `optimizeEndpoint` | `/api/optimize` |
| `healthEndpoint` | `/health` |
| `validationStartEndpoint` | `/api/validation/start` |
| `timeout` | 10 minutos (cubre geocodificación de 70-100 direcciones con Google API) |

---

### 3.3 `config/app_theme.dart`

Sistema de diseño completo con paleta de colores y temas Material 3.

**Colores principales (`AppColors`):**
- Primario: `#003399` (azul medianoche profundo)
- Éxito: `#2E7D32` (verde esmeralda)
- Advertencia: `#E65100` (ámbar/naranja)
- Error: `#C62828` (rojo carmesí)
- Mapa: azul `#2979FF` (polilínea), ámbar `#E65100` (origen), azul `#003399` (próxima parada), gris `#9E9E9E` (paradas completadas)

Expone `appLightTheme` y `appDarkTheme` (MaterialTheme con ColorScheme, estilos de botones, AppBar, SnackBar, etc.).

---

### 3.4 `models/route_models.dart`

Modelos Dart que reflejan los contratos del backend.

**`StopInfo`** — parada en la ruta optimizada
- Campos: `order`, `address`, `label`, `clientName`, `clientNames`, `type`, `lat`, `lon`, `distanceMeters`, `geocodeFailed`, `packageCount`
- Getters: `isOrigin` (type=="origin"), `hasMultiplePackages` (packageCount>1), `displayName` (clientName si existe, si no address)
- `fromJson()` desde respuesta del backend

**`RouteSummary`** — `totalStops`, `totalPackages`, `totalDistanceM`, `totalDistanceDisplay`, `computingTimeMs`. `fromJson()`.

**`OptimizeResponse`** — respuesta completa de `/api/optimize`
- `success`, `summary`, `stops`, `geometry` (GeoJSON como Map)
- `fromJson()` construye todos los objetos anidados

---

### 3.5 `models/validation_models.dart`

Modelos para la respuesta de `/api/validation/start`.

**`GeoConfidence` (enum)**: `exactAddress`, `good`, `exactPlace`, `override`, `failed`
- Refleja los niveles de confianza del backend.
- Extension `.label` → texto legible; `.color` → color semáforo para la UI.

**`GeocodedStop`** — parada que se geocodificó con éxito
- `address`, `alias`, `clientName`, `allClientNames`, `packages`, `packageCount`, `lat`, `lon`
- `confidence: GeoConfidence`
- `fromJson()`

**`FailedStop`** — parada que no pudo geocodificarse
- `address`, `alias`, `clientNames`, `packages`, `packageCount`
- `fromJson()`

**`ValidationResult`** — respuesta completa de `/api/validation/start`
- `geocoded: List<GeocodedStop>`, `failed: List<FailedStop>`
- `totalPackages` (filas del CSV recibidas), `uniqueAddresses` (direcciones únicas procesadas)
- `fromJson()`

---

### 3.6 `models/delivery_state.dart`

Modelos para el estado de entrega en curso. Estos se persisten en Hive.

**`StopStatus` (enum)**: `pending`, `delivered`, `absent`, `incident`
- Extension: `.label` → texto en español; `.emoji` → emoji

**`DeliveryStop`** — versión mutable de StopInfo con estado de entrega
- Campos: todos los de StopInfo + `status` (mutable), `note?` (mutable), `completedAt?` (mutable)
- Getters: `isOrigin`, `isCompleted`, `isPending`, `hasMultiplePackages`, `displayName`
- `toMap()` / `fromMap()` para serialización en Hive

**`DeliverySession`** — sesión de reparto completa (reanudable)
- `id` (único), `createdAt`, `stops`, `geometry`, `totalStops`, `totalPackages`, `totalDistanceDisplay`, `computingTimeMs`
- `currentStopIndex` (mutable): índice de la parada actual
- Getters: `currentStop`, `pendingCount`, `completedCount`, `deliveredCount`, `absentCount`, `incidentCount`, `isFinished`, `progress` (0.0–1.0)
- `advanceToNext()`: avanza `currentStopIndex` a la siguiente parada pendiente
- `toMap()` / `fromMap()` para Hive

---

### 3.7 `models/csv_data.dart`

Contenedor simple para los datos del CSV cargado.

**`CsvData`**: `clientes`, `direcciones`, `ciudades`, `notas`, `aliases` (todas `List<String>`, una por fila del CSV)
- `totalPackages` getter → `direcciones.length`
- `isEmpty` / `isNotEmpty`

---

### 3.8 `services/api_service.dart`

Capa de comunicación HTTP con el backend. Todos los métodos son estáticos.

**Headers comunes:**
- `ngrok-skip-browser-warning: 1` — evita la página de advertencia de ngrok en peticiones programáticas
- `Content-Type: application/json` — para peticiones con body JSON

**Métodos:**

`healthCheck() → Future<bool>`
- GET `/health`, timeout 15s
- Devuelve `true` si status 200, `false` en cualquier error

`optimize({addresses, clientNames?, startAddress?, coords?, packageCounts?, packagesPerStop?, aliases?}) → Future<OptimizeResponse>`
- POST `/api/optimize` con JSON body
- Solo incluye campos opcionales si no son null/vacíos
- Timeout: 10 minutos
- En error HTTP: extrae `detail` o `error` del body y lanza `ApiException`

`getRouteSegment({originLat, originLon, destLat, destLon}) → Future<Map<String,dynamic>?>`
- GET `/api/route-segment` con query params
- Timeout 15s
- Devuelve el GeoJSON geometry o `null` si falla

`validationStart({csvData: CsvData}) → Future<ValidationResult>`
- POST `/api/validation/start` con JSON body `{"rows": [{cliente, direccion, ciudad, nota, alias}, ...]}`
- Timeout: 10 minutos
- En error HTTP: lanza `ApiException`

`postOverride({address, lat, lon}) → Future<void>`
- POST `/api/validation/override` con JSON body
- Fire-and-forget: errores de red se ignoran silenciosamente
- Se llama al confirmar un pin manual (tanto en validación como en reparto)

**`ApiException`**: `message` + `statusCode`. Tipo para errores de API.

---

### 3.9 `services/csv_service.dart`

Parsea archivos CSV en memoria, sin depender del backend.

**`parse(Uint8List bytes) → CsvData`**

1. Decodifica bytes como UTF-8
2. Divide en líneas, detecta headers en la primera fila
3. `_detectColumns(headers)` hace matching fuzzy de nombres de columna:
   - `cliente/clientes/nombre/nombres/client` → columna de cliente
   - `dirección/direccion/address/domicilio/calle` → columna de dirección (obligatoria)
   - `ciudad/city/localidad/municipio/población` → columna de ciudad
   - `nota/notas/note/observacion` → columna de nota (opcional)
   - `alias/negocio/lugar/establecimiento` → columna de alias (opcional; activa Google Places)
4. Para cada fila: extrae campos usando `_parseCsvLine()` (maneja campos con comillas y comas internas)
5. Lanza `FormatException` si no encuentra la columna de dirección
6. Devuelve `CsvData` con las cinco listas

---

### 3.10 `services/location_service.dart`

Wrapper sobre el paquete `geolocator` para acceso al GPS del dispositivo.

**`getCurrentPosition() → Future<Position>`**

1. Verifica que el servicio de localización esté habilitado; si no → `LocationException("Activa la ubicación...")`
2. Verifica permisos; si denegado → solicita; si denegado permanentemente → `LocationException("Permiso denegado permanentemente...")`
3. Llama a `Geolocator.getCurrentPosition(desiredAccuracy: high, timeLimit: 15s)`
4. Devuelve `Position` (lat, lon, altitud, velocidad, etc.)

**`LocationException`**: excepción tipada con mensaje amigable en español.

---

### 3.11 `services/persistence_service.dart`

Persistencia local mediante Hive. Permite reanudar una entrega tras cerrar la app.

**Inicialización:**
- `init()`: inicializa Hive Flutter, abre el box `'delivery_session'`. Protegido contra doble inicialización.

**Métodos de sesión de entrega:**

`createSession(OptimizeResponse) → DeliverySession`
- Convierte `OptimizeResponse.stops` → `List<DeliveryStop>` con `status = pending`
- Asigna `id` único (timestamp) y `createdAt = DateTime.now()`
- No persiste (hay que llamar a `saveSession()` después)

`saveSession(DeliverySession)` → serializa con `toMap()` y guarda en Hive con clave `'active_session'`

`loadSession() → DeliverySession?` → carga de Hive y deserializa; devuelve `null` si está corrupto o no existe

`hasActiveSession() → bool` → comprueba si existe la clave en Hive

`clearSession()` → elimina la clave del Hive box

`updateStopStatus(session, stopIndex, status, {note?})`
- Muta `session.stops[stopIndex].status`, `.note`, `.completedAt`
- Llama a `session.advanceToNext()` para mover `currentStopIndex`
- Guarda inmediatamente en Hive (garantiza no perder datos)

**Métodos de estado de validación** (para persistir correcciones del usuario entre sesiones):
- `saveValidationState(Map)` / `loadValidationState() → Map?` / `clearValidationState()`
- Box separado: `'validation_state'`

---

### 3.12 `screens/splash_screen.dart`

Pantalla de entrada con animaciones. Dura 2.5 segundos.

**Qué muestra:** Fondo con gradiente azul profundo, icono de la app (120×120), título "Repartidor", subtítulo, spinner de carga, texto "Posadas, Córdoba".

**Lógica:** Lanza tres animaciones simultáneas (fade-in 0→1, slide-up 30px→0, scale 0.8→1.0) durante 1200ms. Tras 2500ms navega a `ImportScreen` con transición fade de 600ms usando `pushReplacement`.

**Navegación:** SplashScreen → ImportScreen (sin vuelta atrás)

---

### 3.13 `screens/import_screen.dart`

Pantalla principal de importación y configuración de ruta. Es el hub central de la app.

**Qué muestra:**
- Estado del servidor (badge Online/Offline, recargable)
- Tarjeta "Continuar Ruta" si hay sesión activa guardada en Hive
- Área de carga de CSV (file picker)
- Resumen del CSV cargado (paquetes totales)
- Botón "Validar Direcciones" (activo tras cargar CSV)
- Diálogo de progreso durante validación ("Geocodificando… puede tardar varios minutos" + contador de tiempo)
- Banner de error

**Flujo principal:**

`_pickFile()` → abre file picker para CSV, llama a `CsvService.parse()`, guarda el `CsvData`.

`_startValidation()`:
1. Comprueba servidor online
2. Activa wakelock y muestra `_ValidationProgressDialog`
3. Llama a `ApiService.validationStart(csvData)`
4. En éxito: cierra diálogo y navega a `ValidationReviewScreen`

`_ValidationProgressDialog`: diálogo no cancelable con spinner, "Geocodificando… puede tardar varios minutos", barra indeterminada y contador de tiempo transcurrido.

**Navegación:**
- → `DeliveryScreen` (si retoma sesión existente)
- → `ValidationReviewScreen` (tras validar CSV)

---

### 3.14 `screens/validation_review_screen.dart`

Pantalla de revisión de resultados de geocodificación. El usuario ve todas las paradas antes de calcular la ruta, puede corregir errores y decidir cómo proceder con las fallidas.

**Qué muestra:**
- Mapa con marcadores de todas las paradas geocodificadas. El color del marcador refleja el nivel de confianza (verde=EXACT_ADDRESS, naranja=GOOD/EXACT_PLACE/OVERRIDE). Los marcadores son tappables para re-pinanr la parada.
- Lista de paradas geocodificadas con chip de confianza y alias (si existe).
- Lista de paradas fallidas con botón "Pin en mapa" para situar manualmente.
- `OriginSelector` para elegir el punto de inicio.
- Botón "Calcular ruta" (envía a `/api/optimize`).

**Re-pin de parada geocodificada:**
1. El usuario toca un marcador del mapa → diálogo de confirmación.
2. Se abre `MapPickerScreen` → el usuario toca la posición correcta.
3. Se llama a `ApiService.postOverride()` (fire-and-forget).
4. La parada se sustituye en `_result.geocoded` con `confidence: GeoConfidence.override` y nuevas coords.

**Re-pin de parada fallida:**
1. El usuario pulsa "Pin en mapa" en la lista de fallidas → diálogo de confirmación.
2. Se abre `MapPickerScreen`.
3. Se llama a `postOverride()`, se mueve la parada de `_result.failed` a `_result.geocoded`.

**`_calculateRoute()`:**
1. Obtiene origen (GPS / manual / defecto según `OriginSelector`)
2. Llama a `ApiService.optimize()` pasando coords, packages_per_stop, aliases
3. Navega a `ResultScreen`

**Navegación:**
- ← ImportScreen (atrás)
- → ResultScreen (tras calcular ruta)

---

### 3.16 `screens/loading_order_screen.dart`

Pantalla informativa de orden de carga LIFO (Last-In-First-Out) para la furgoneta.

**Qué muestra:** Lista de paradas en orden inverso (el primero de la ruta va al fondo de la furgoneta, el último queda junto a la puerta). Marca visualmente el primer elemento ("AL FONDO") y el último ("JUNTO A LA PUERTA"). Cada elemento muestra número de parada, cliente, dirección y cantidad de paquetes.

**Lógica:** Filtra el origen, invierte la lista de stops. El primero resultante (último a entregar) va al fondo; el último (primera entrega) queda junto a la puerta.

**Navegación:** ResultScreen → LoadingOrderScreen → atrás a ResultScreen

---

### 3.17 `screens/result_screen.dart`

Visualización de la ruta optimizada antes de iniciar el reparto.

**Qué muestra:**
- `StatsBanner` con: paradas totales, paquetes totales (si hay agrupaciones), distancia total, tiempo de cómputo
- Mapa interactivo (35% de altura) con `RouteMap` en modo preview (geometría completa)
- Lista de paradas con `StopsList`
- Botón "Iniciar Reparto"

**Interacción:**
- Tap en una parada de la lista → `_mapKey.currentState?.flyToStop()` centra el mapa en esa parada
- Tap en un marcador del mapa → selecciona esa parada en la lista
- Botón "Ordenar Paquetes (LIFO)" → navega a `LoadingOrderScreen`
- Botón "Iniciar Reparto" → llama a `PersistenceService.createSession()` y `saveSession()`, navega a `DeliveryScreen`

**Estado:** `_highlightedStop: int?` — índice de parada seleccionada (sincronizado entre mapa y lista)

**Navegación:**
- → `LoadingOrderScreen`
- → `DeliveryScreen`

---

### 3.18 `screens/delivery_screen.dart`

Pantalla de ejecución del reparto en tiempo real. La más compleja de la app.

**Qué muestra:**
- AppBar: "En Reparto" + badge con conteo de completadas
- Cabecera de progreso: "X de Y entregas" con chips (✅ entregadas, 🚫 ausentes, ⚠️ incidencias) y barra de progreso
- Mapa en modo delivery (tramo GPS → próxima parada, no la ruta completa)
- Tarjeta "Siguiente Parada" (`_NextStopCard`): número, alias (si existe), dirección, lista de paquetes, botón de navegación externa (Google Maps), botón de re-pin (naranja, `edit_location_alt`)
- Botones de acción: "Entregado" (verde, grande), "Ausente" (ámbar), "Incidencia" (rojo, pequeño)

**Estado:** recibe `DeliverySession` existente del constructor. Muta directamente sobre ese objeto.

**Métodos clave:**

`initState()`: espera 1.5s, llama a `_fetchSegmentFromGps()` para dibujar el primer tramo. Inicia `_segmentTimer` con `Timer.periodic(10 s)` para refrescar el tramo automáticamente.

`_getCurrentGps()`:
1. Primero intenta obtener posición del stream activo del mapa (ya tiene GPS)
2. Si no, llama a `Geolocator.getCurrentPosition()` con timeout 10s
3. Devuelve `null` si GPS no disponible

`_fetchSegmentFromGps()`:
1. Obtiene posición GPS (2 intentos)
2. Si no hay GPS: usa la parada anterior completada, o la primera parada, como origen
3. Llama a `ApiService.getRouteSegment()` para obtener la geometría del tramo
4. Actualiza `_segmentGeometry` → `RouteMap` redibuja el tramo actual

`_markStop(status, note?)`:
1. Llama a `PersistenceService.updateStopStatus()` → persiste en Hive inmediatamente
2. Si la sesión está terminada → llama a `_showFinishedDialog()`
3. Si no → recalcula segmento GPS → próxima parada y recentra mapa

`_repinStop(stop, sessionIndex)`:
1. Muestra diálogo de confirmación
2. Abre `MapPickerScreen` para que el usuario toque la posición correcta
3. Llama a `ApiService.postOverride()` (fire-and-forget)
4. Crea un nuevo `DeliveryStop` con `lat`, `lon` y `geocodeFailed: false` actualizados
5. Sustituye `_session.stops[sessionIndex]`, guarda sesión en Hive
6. Si es la parada actual, recalcula el segmento GPS

`_showReorderSheet()`:
- Muestra `ReorderableListView` con las paradas no completadas (pendientes + ausentes + incidencias)
- Cada parada tiene botón de re-pin y botón de marcar entregada
- Al confirmar: reconstruye la lista [origen, completadas, pendientes-reordenadas]
- Guarda sesión, recalcula segmento

`_showFinishedDialog()`:
- Muestra resumen: entregadas, ausentes, incidencias, tiempo total, distancia
- "Cerrar Sesión y Limpiar" → `PersistenceService.clearSession()` → `Navigator.popUntil(first)`

**Servicios llamados:**
- `Geolocator.getCurrentPosition()` — GPS del dispositivo
- `ApiService.getRouteSegment()` — tramo OSRM entre dos puntos (refresco cada 10 s + tras cada parada)
- `ApiService.postOverride()` — guarda pin manual en backend
- `PersistenceService.updateStopStatus()` / `saveSession()` — persiste cada entrega y re-pin
- `launchUrl()` — abre Google Maps externo para navegación giro a giro

**Navegación:** tras finalizar → `ImportScreen` (popUntil el primero de la pila)

---

### 3.19 `widgets/route_map.dart`

Widget de mapa interactivo basado en `flutter_map` + OpenStreetMap. Usado tanto en modo preview (ruta completa) como en modo delivery (solo el tramo actual).

**Props de entrada:**
| Prop | Tipo | Descripción |
|------|------|-------------|
| `stops` | `List<StopInfo>` | Paradas a mostrar con marcadores |
| `geometry` | `Map<String,dynamic>` | GeoJSON de la ruta completa |
| `highlightedStopIndex` | `int?` | Parada seleccionada (resalta y vuela) |
| `onMarkerTapped` | `ValueChanged<int>?` | Callback al tocar un marcador |
| `completedIndices` | `Set<int>?` | Paradas ya entregadas (grises) |
| `deliveryMode` | `bool` | true = muestra tramo GPS→próxima parada |
| `segmentGeometry` | `Map?` | GeoJSON del tramo actual (solo delivery) |
| `nextStopIndex` | `int?` | Próxima parada (marcador grande azul) |

**Métodos públicos (vía `GlobalKey<RouteMapState>`):**
- `flyToStop(int index)` — anima el mapa a la parada indicada
- `fitRoute()` — encuadra toda la ruta en la vista
- `fitGpsAndNextStop()` — encuadra GPS + próxima parada
- `centerOnGps()` — centra en posición GPS y activa seguimiento

**GPS tracking:**
- Solicita permisos, obtiene posición inicial (10s timeout, precisión media)
- Suscribe stream continuo con filtro de 15 metros (ahorra batería)
- En modo delivery: llama a `fitGpsAndNextStop()` en cada update
- El usuario puede "soltar" el seguimiento moviendo el mapa manualmente

**Capas del mapa (en orden de pintado):**
1. Tiles de OpenStreetMap
2. Polilínea de ruta: vacía en preview; en delivery → tramo actual con borde blanco + línea azul eléctrico
3. Marcadores de paradas (`_StopMarkerIcon`)
4. Marcador GPS (`_GpsMarker` — punto azul con halo pulsante)

**`_StopMarkerIcon`** — burbuja de marcador con estado visual:
- Tamaño: 46px (next) > 40px (resaltado) > 36px (origen) > 30px (normal) > 20px (pequeño)
- Color: gris (completado), azul (próximo), naranja (origen), azul faded (pequeño)
- Contenido: ✓ (completado), 🏠 (origen), número de orden (otros)

**`_GpsMarker`** — punto GPS animado (halo pulsante 1500ms)

---

### 3.20 `widgets/stops_list.dart`

Lista scrollable de paradas. Sincronizada con el mapa.

**Props:** `stops`, `highlightedIndex?`, `onStopTapped?`

**Comportamiento:**
- Separa paradas geocodificadas de paradas fallidas con `_UnresolvedSeparator`
- `_StopTile`: tile animado (250ms). Resalte con fondo azul claro; fallos con fondo ámbar. Muestra: icono de orden, nombre del cliente (o dirección si no hay), distancia acumulada, chip de paquetes si >1

---

### 3.21 `widgets/stats_banner.dart`

Fila horizontal de tarjetas de estadísticas.

**`StatItem`**: `label`, `value`, `icon`

**`StatsBanner`**: recibe `List<StatItem>`, renderiza una fila de tarjetas con icono + valor grande + label. Fondo claro con sombra suave.

---

### 3.22 `widgets/origin_selector.dart`

Selector del punto de inicio de la ruta.

**`OriginMode` (enum)**: `defaultAddress`, `manual`, `gps`

**`OriginSelector`** — props: `mode`, `manualAddress`, `onModeChanged`, `onAddressChanged`

Muestra tres opciones:
1. **Defecto**: "C/ Callejón de Jesús 1, Posadas" (dirección fija del almacén)
2. **GPS**: "Usar GPS del dispositivo"
3. **Manual**: abre campo de texto para introducir dirección libre

La opción seleccionada aparece con borde de color y check circle. La opción manual muestra un `TextField` adicional debajo.

---

## 4. Diagrama de flujo de datos

```
CSV (bytes)
  └─ CsvService.parse()
       └─ CsvData {clientes, direcciones, ciudades, notas, aliases}
                 │
                 ▼
         ApiService.validationStart()
              │  POST /api/validation/start
              │    └─ validation.py
              │         └─ geocoding.py (por dirección única)
              │              1. Caché disco (override > google/places con TTL)
              │              2. Fuzzy matching catálogo OSM (sin HTTP)
              │              3. Google Geocoding API → EXACT_ADDRESS | GOOD
              │              4. Google Places API (si alias) → EXACT_PLACE
              │              5. FAILED
              │
              ▼
         ValidationResult
         {geocoded[]{lat, lon, confidence, alias}, failed[]}
              │
              ├─ ValidationReviewScreen: usuario toca marcadores → re-pin → postOverride()
              │
              ▼
         ApiService.optimize()
              │  POST /api/optimize
              │    └─ optimize.py
              │         ├─ coords pre-resueltas (no re-geocodifica)
              │         ├─ routing.optimize_route()
              │         │      └─ LKH3 (subprocess) → waypoint_order
              │         ├─ _sort_street_runs() (post-proceso portales)
              │         └─ routing.get_route_details()
              │                └─ OSRM (HTTP) → geometry GeoJSON
              │
              ▼
         OptimizeResponse
         {stops[orden optimizado], geometry GeoJSON}
              │
              ├─ ResultScreen (preview del mapa)
              │
              └─ PersistenceService.createSession()
                   └─ DeliverySession → Hive (persistente)
                        │
                        ▼
                   DeliveryScreen
                        │
                        ├─ Geolocator.getCurrentPosition() → GPS
                        │
                        ├─ ApiService.getRouteSegment() (cada 10 s)
                        │    GET /api/route-segment
                        │      └─ OSRM → segmento GPS→parada
                        │
                        ├─ _repinStop() → MapPickerScreen → postOverride()
                        │
                        └─ PersistenceService.updateStopStatus()
                             └─ Hive (estado de cada entrega)
```

---

## 5. Servicios externos

| Servicio | URL | Protocolo | Propósito | Timeout |
|----------|-----|-----------|-----------|---------|
| **Google Geocoding API** | `maps.googleapis.com/maps/api/geocode/json` | HTTPS | Geocodificación principal (precisión portal) | 30s/llamada |
| **Google Places API** | `maps.googleapis.com/maps/api/place/findplacefromtext/json` | HTTPS | Geocodificación de negocios por alias | 30s/llamada |
| **Overpass API** | `overpass-api.de/api/interpreter` | HTTPS | Catálogo de calles OSM para fuzzy matching (TTL 7 días) | 40s |
| **OSRM** | `localhost:5000` | HTTP (Docker) | Rutas por carretera, geometría GeoJSON, snap de coordenadas | 60s |
| **LKH3** | binario local | subprocess | Resolución del TSP (orden óptimo de visita) | 60s |
| **Google Maps** | externo | URL scheme | Navegación giro a giro (abre la app del sistema) | — |
| **OpenStreetMap tiles** | `tile.openstreetmap.org` | HTTPS | Teselas del mapa base en la app Flutter | — |
