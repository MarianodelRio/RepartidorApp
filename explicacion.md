# Documentación Técnica — App Repartir

Sistema de optimización de rutas de reparto para Posadas, Córdoba (España).
Compuesto por un backend Python/FastAPI, una app móvil Flutter, y servicios Docker (OSRM + VROOM).

> **Primera vez en el proyecto?** Sigue primero la [Guía de instalación](GUIA_INSTALACION.md) para montar el entorno desde cero. Este documento asume que ya tienes todo instalado.

---

## Para empezar: flujo de desarrollo

### 1. Arrancar los servicios

```bash
cd /ruta/a/app_repartir
./start.sh start   # inicia Docker (OSRM + VROOM), backend FastAPI y ngrok
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
    ├─ Selecciona CSV (cliente, dirección, ciudad)
    │       └─ CsvService.parse() → CsvData
    │
    ├─ POST /api/validation/start
    │       └─ Backend geocodifica cada dirección única (Nominatim)
    │          Devuelve: coordenadas, estado ok/problema, paquetes por parada
    │
    ├─ [Opcional] Usuario corrige coordenadas de paradas fallidas manualmente
    │
    ├─ POST /api/optimize
    │       └─ Backend recibe coords ya resueltas
    │          → VROOM resuelve el TSP (orden óptimo de visita)
    │          → OSRM calcula geometría e instrucciones de navegación
    │          Devuelve: lista ordenada de paradas + polilínea + instrucciones
    │
    ├─ ResultScreen: mapa con ruta, estadísticas, orden de carga LIFO
    │
    └─ DeliveryScreen: navegación GPS en tiempo real
            ├─ GET /api/route-segment → tramo GPS→próxima parada
            └─ Hive: persistencia local del estado de cada entrega
```

---

## 2. Backend Python

### 2.1 `main.py`

Punto de entrada de la aplicación FastAPI.

**Qué hace:**
- Inicializa la app con título "Posadas Route Planner" v2.3.0
- Configura CORS abierto (`allow_origins=["*"]`) para cualquier cliente
- Monta directorio `/static` para archivos estáticos
- Registra los dos routers: `optimize.router` en `/api` y `validation.router` en `/api`
- Expone tres endpoints propios:

**GET /health**
- Sin parámetros
- Respuesta: `{"status": "ok", "version": "2.3.0"}`
- Uso: comprobación de vida del servidor desde la app

**GET /api/services/status**
- Sin parámetros
- Prueba OSRM: GET `localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false` (timeout 5s)
- Prueba VROOM: GET `localhost:3000/health` (timeout 5s)
- Respuesta:
  ```json
  {
    "osrm": {"url": "http://localhost:5000", "status": "ok|down"},
    "vroom": {"url": "http://localhost:3000", "status": "ok|down"},
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

Fuente única de verdad para todas las constantes del sistema.

| Constante | Valor | Propósito |
|-----------|-------|-----------|
| `OSRM_BASE_URL` | `http://localhost:5000` | Contenedor Docker OSRM |
| `VROOM_BASE_URL` | `http://localhost:3000` | Contenedor Docker VROOM |
| `NOMINATIM_URL` | `https://nominatim.openstreetmap.org/search` | Geocodificación |
| `NOMINATIM_USER_AGENT` | `posadas-route-planner/2.0 (local)` | Identificación en Nominatim |
| `START_ADDRESS` | `"Calle Callejon de Jesús 1, Posadas, Córdoba, España"` | Dirección de origen por defecto |
| `POSADAS_CENTER` | `(37.802, -5.105)` | Centro del mapa (lat, lon) |
| `POSADAS_VIEWBOX` | `"-5.15,37.78,-5.06,37.83"` | Bounding box de Posadas para Nominatim |
| `MAX_STOPS` | `200` | Máximo de paradas por petición |
| `GEOCODE_DELAY` | `0.5` s | Espera entre llamadas a Nominatim (rate limit) |
| `GEOCODE_RETRY_DELAY` | `0.3` s | Espera entre estrategias de reintento |
| `GEOCODE_TIMEOUT` | `30` s | Timeout por llamada a Nominatim |
| `OSRM_TIMEOUT` | `60` s | Timeout para OSRM |
| `VROOM_TIMEOUT` | `120` s | Timeout para VROOM (resolver TSP puede tardar) |

---

### 2.3 `models/__init__.py`

Contratos de datos Pydantic entre frontend y backend.

**Modelos de entrada:**

`OptimizeRequest`
- `addresses: list[str]` — direcciones a visitar (requerido, mínimo 1)
- `client_names: list[str] | None` — nombres de cliente, mismo orden que addresses
- `start_address: str | None` — dirección de origen (usa START_ADDRESS si no se indica)
- `coords: list[list[float] | None] | None` — coordenadas pre-resueltas `[lat, lon]` por dirección; si se proporcionan se omite la geocodificación
- `package_counts: list[int] | None` — paquetes por dirección; si se proporciona, las direcciones ya vienen agrupadas (no se re-agrupan)
- `all_client_names: list[list[str]] | None` — todos los nombres por dirección cuando viene pre-agrupado

**Modelos de salida:**

`StopInfo` — una parada en la ruta
- `order: int` — posición en la secuencia (0 = origen)
- `address: str` — dirección completa
- `label: str` — etiqueta legible ("🏠 Origen", "📍 Juan García")
- `client_name: str` — nombre principal del cliente
- `client_names: list[str]` — todos los destinatarios en esta dirección
- `type: str` — "origin" o "stop"
- `lat, lon: float` — coordenadas
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

Lógica principal de optimización. Orquesta: deduplicación → geocodificación → VROOM → OSRM.

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

6. **Optimización TSP con VROOM**: llama a `optimize_route(all_coords)`
   - Devuelve `waypoint_order`: lista de índices en orden óptimo de visita
   - Lanza 503 si VROOM no está disponible

7. **Ruta detallada con OSRM**: reordena coords según `waypoint_order` y llama a `get_route_details()`
   - Devuelve geometría GeoJSON de la ruta completa
   - Lanza 503 si OSRM no está disponible

8. **Construcción de la respuesta**:
   - Para cada índice en `waypoint_order`: crea `StopInfo` con label y distancia acumulada
   - Las paradas fallidas se añaden al final con `geocode_failed=True` y coords del centro de Posadas
   - Devuelve `OptimizeResponse` completa

---

### 2.5 `routers/validation.py`

Valida y geocodifica direcciones antes de la optimización. No llama a VROOM ni OSRM.

**Modelos propios:**

`CsvRow`: `cliente: str`, `direccion: str`, `ciudad: str`

`StartRequest`: `rows: list[CsvRow]` — filas crudas del CSV

`GeocodedStop` — parada geocodificada con éxito:
- `address, client_name, all_client_names, package_count, lat, lon`

`FailedStop` — parada que no pudo geocodificarse:
- `address, client_names, package_count`

`StartResponse`:
- `geocoded: list[GeocodedStop]`, `failed: list[FailedStop]`
- `total_packages` (filas recibidas), `unique_addresses` (direcciones únicas)

**POST /api/validation/start — flujo:**

1. Agrupa filas por dirección normalizada usando `OrderedDict` (primera aparición gana)
2. Para cada dirección única: llama a `geocode(addr)` respetando el rate limit de Nominatim
3. Devuelve listas separadas `geocoded` y `failed`

**Diferencia clave con optimize.py**: devuelve todos los resultados (ok y fallidos) sin calcular ruta. Permite al usuario ver y corregir paradas problemáticas antes de optimizar.

---

### 2.6 `services/geocoding.py`

Convierte direcciones en coordenadas GPS usando Nominatim con caché, overrides manuales y múltiples estrategias de búsqueda.

**Estado global:**
- `_cache: dict[str, tuple | None]` — caché en memoria; clave = dirección en minúsculas
- `_overrides: dict` — overrides manuales cargados desde `/app/data/geocode_overrides.json` al iniciar el módulo

**`clean_address(raw: str) → str`**

Limpieza agresiva de 14 pasos sobre la dirección cruda:
1. Elimina caracteres de control y espacios no estándar
2. Corrige errores de codificación (`FernÁndez` → `Fernández`, `?` → carácter correcto)
3. Corrige acentos mal escritos (`Mari´a` → `María`)
4. Elimina contenido entre paréntesis irrelevante (`(TOLDOS...)`)
5. Elimina descriptores finales: "Si Ausente", "ESCALERA X", "LOCAL", "PUERTA X", etc.
6. Corrige errores tipográficos comunes (`adofo` → `Adolfo`)
7. Normaliza abreviaturas de tipo de vía: `C/`, `CL`, `c.` → `Calle`; `AVDA`, `AV` → `Avenida`; etc.
8. Normaliza "número": elimina `Nº`, `nº`, `n°`, `num`, `número`
9. Normaliza "sin número": `s/n`, `s-n`, `SN` → `s/n`
10. Elimina números de planta/puerta: `1º A`, `Bajo`, `BJ`
11. Limpia puntuación y espacios redundantes
12. Si no contiene "posadas" → añade `, Posadas`
13. Si no contiene "córdoba" → añade `, Córdoba, España`

**`geocode(address: str) → tuple[float, float] | None`**

Estrategia de 5 intentos en cascada (con 0.3s entre cada uno):
1. **Caché**: si ya se geocodificó antes, devuelve resultado inmediato
2. **Override manual**: si el usuario la corrigió antes, usa esas coords
3. **Búsqueda libre (limpia)**: Nominatim con la dirección limpia, viewbox como pista
4. **Búsqueda estructurada**: separa nombre de calle y número, búsqueda con campos separados
5. **Búsqueda simplificada (sin número)**: busca solo el nombre de la calle
6. **Búsqueda acotada**: misma búsqueda pero con `bounded=1` (fuerza Posadas estrictamente)
7. **Nombre corto**: últimas 2 palabras del nombre de calle + "Posadas, Córdoba, España"

Cada llamada a Nominatim valida que el resultado esté dentro de ±0.15° del centro de Posadas (~16 km). Si no, se descarta.

**`geocode_batch(addresses: list[str]) → list[tuple]`**

Llama a `geocode()` para cada dirección. Entre llamadas a direcciones nuevas (no cacheadas) espera `GEOCODE_DELAY` (0.5s) para respetar el rate limit de Nominatim. No espera tras el último resultado.

**`add_override(address, lat, lon)`**

Guarda una corrección manual en memoria y en disco (`/app/data/geocode_overrides.json`). Se invoca cuando el usuario pina manualmente una dirección en la app.

---

### 2.7 `services/routing.py`

Interfaz con VROOM (TSP) y OSRM (geometría de ruta).

**`optimize_route(coords: list[tuple]) → dict | None`**

Resuelve el TSP (Problema del Viajante) usando VROOM.

Petición a VROOM (`POST localhost:3000`):
```json
{
  "vehicles": [{"id": 0, "profile": "car", "start": [lon, lat]}],
  "jobs": [{"id": 1, "location": [lon, lat]}, ...],
  "options": {"g": true}
}
```

El vehículo no tiene punto de llegada ("Open Trip Problem"): el repartidor no vuelve al origen.

Respuesta procesada:
```python
{
  "waypoint_order": [0, 3, 1, 2],        # índices en orden óptimo
  "stop_details": [
    {"original_index": 3, "arrival_distance": 500.0, "arrival_duration": 45.0},
    ...
  ],
  "total_distance": 2500.0,              # metros
  "total_duration": 180.0,               # segundos
  "computing_time_ms": 50
}
```

**`get_route_details(coords_ordered: list[tuple]) → dict | None`**

Obtiene la geometría GeoJSON de la ruta completa desde OSRM, dado un orden de visita ya optimizado.

Petición: `GET localhost:5000/route/v1/driving/{lon,lat};.../overview=full&geometries=geojson`

Respuesta:
```python
{
  "geometry": {...},   # GeoJSON LineString
  "total_distance": 2500,   # metros
  "total_duration": 180     # segundos
}
```

**`can_osrm_snap(lat, lon) → bool`**

Comprueba que OSRM puede mapear la coordenada a un nodo de la red viaria a menos de 2 km. Se llama antes de enviar coords a VROOM para evitar errores 500 por coordenadas fuera del mapa.

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
| `baseUrl` | `http://127.0.0.1:8000` (desarrollo local) |
| `optimizeEndpoint` | `/api/optimize` |
| `healthEndpoint` | `/health` |
| `servicesStatusEndpoint` | `/api/services/status` |
| `validationStartEndpoint` | `/api/validation/start` |
| `timeout` | 10 minutos (cubre geocodificación lenta de 70-100 direcciones) |

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

**`GeocodedStop`** — parada que se geocodificó con éxito
- `address`, `clientName`, `allClientNames`, `packageCount`, `lat`, `lon`
- `fromJson()`

**`FailedStop`** — parada que no pudo geocodificarse
- `address`, `clientNames`, `packageCount`
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

**`CsvData`**: `clientes`, `direcciones`, `ciudades` (todas `List<String>`, una por fila del CSV)
- `totalPackages` getter → `direcciones.length`
- `fullAddresses` getter → combina dirección + ciudad ("dirección, ciudad"), evitando duplicar la ciudad si ya aparece en la dirección
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

`servicesStatus() → Future<Map<String,dynamic>?>`
- GET `/api/services/status`, timeout 10s
- Devuelve el mapa JSON o `null` si falla

`optimize({addresses, clientNames?, startAddress?, coords?, packageCounts?, allClientNames?}) → Future<OptimizeResponse>`
- POST `/api/optimize` con JSON body
- Solo incluye campos opcionales si no son null/vacíos
- Timeout: 10 minutos
- En error HTTP: extrae `detail` o `error` del body y lanza `ApiException`

`getRouteSegment({originLat, originLon, destLat, destLon}) → Future<Map<String,dynamic>?>`
- GET `/api/route-segment` con query params
- Timeout 15s
- Devuelve el GeoJSON geometry o `null` si falla

`validationStart({csvData: CsvData}) → Future<ValidationResult>`
- POST `/api/validation/start` con JSON body `{"rows": [{cliente, direccion, ciudad}, ...]}`
- Timeout: 10 minutos
- En error HTTP: lanza `ApiException`

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
4. Para cada fila: extrae cliente, dirección, ciudad usando `_parseCsvLine()` (maneja campos con comillas y comas internas)
5. Lanza `FormatException` si no encuentra la columna de dirección
6. Devuelve `CsvData` con las tres listas

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
- Tarjeta "Continuar Ruta" si hay sesión activa guardada
- Área de carga de CSV (file picker)
- Resumen del CSV cargado (paquetes totales, paradas únicas)
- Selector de origen (defecto / GPS / manual)
- Botón "Validar Direcciones"
- Resumen de validación (barra de progreso, chips OK/Problemas/Paquetes)
- Botón "Calcular Ruta Óptima"
- Banner de error

**Estado interno:**
| Variable | Tipo | Propósito |
|----------|------|-----------|
| `_csvData` | `CsvData?` | CSV cargado y parseado |
| `_fileName` | `String` | Nombre del archivo |
| `_originMode` | `OriginMode` | Modo de origen seleccionado |
| `_manualAddress` | `String` | Dirección manual si aplica |
| `_isLoading` | `bool` | Cálculo de ruta en curso |
| `_isCheckingServer` | `bool` | Comprobación de servidor en curso |
| `_error` | `String?` | Mensaje de error actual |
| `_serverOnline` | `bool` | Servidor accesible |
| `_hasActiveSession` | `bool` | Hay sesión de reparto guardada |
| `_validationResult` | `ValidationResponse?` | Resultado de validación |
| `_isValidating` | `bool` | Validación en curso |
| `_hasEverValidated` | `bool` | Se ejecutó validación al menos una vez |
| `_addresses` | `List<String>` | Direcciones del CSV |
| `_clientNames` | `List<String>` | Nombres del CSV |

**Métodos clave:**

`_pickFile()`: abre file picker para CSV, llama a `CsvService.parse()`, extrae `fullAddresses` y `clientes`, resetea validación anterior.

`_validate()`:
1. Activa wakelock (evita que la pantalla se apague)
2. Muestra diálogo de progreso con contador de tiempo
3. Llama a `ApiService.validationStart(addresses, clientNames)`
4. Si hay problemas, abre bottom sheet con lista de direcciones problemáticas
5. Permite "Situar en el mapa" → diálogo para introducir lat/lon manualmente

`_applyPin(stop, lat, lon)`: reconstruye el `ValidationResponse` con las coordenadas corregidas para esa parada; actualiza contadores de ok/problema.

`_calculateRoute()`:
1. Si hay problemas sin resolver, muestra confirmación "¿Calcular igualmente?"
2. Obtiene dirección de origen (manual, GPS o defecto)
3. Si hay validación previa: usa las paradas únicas ya geocodificadas como entrada (evita re-geocodificar)
4. Si no: usa las direcciones brutas del CSV
5. Llama a `ApiService.optimize()` con los datos
6. Muestra progreso animado con mensajes rotativos
7. En éxito: limpia estado de validación, navega a `ResultScreen`

**Navegación:**
- → `DeliveryScreen` (si retoma sesión existente)
- → `ResultScreen` (tras calcular ruta)

---

### 3.14 `screens/loading_order_screen.dart`

Pantalla informativa de orden de carga LIFO (Last-In-First-Out) para la furgoneta.

**Qué muestra:** Lista de paradas en orden inverso (el primero de la ruta va al fondo de la furgoneta, el último queda junto a la puerta). Marca visualmente el primer elemento ("AL FONDO") y el último ("JUNTO A LA PUERTA"). Cada elemento muestra número de parada, cliente, dirección y cantidad de paquetes.

**Lógica:** Filtra el origen, invierte la lista de stops. El primero resultante (último a entregar) va al fondo; el último (primera entrega) queda junto a la puerta.

**Navegación:** ResultScreen → LoadingOrderScreen → atrás a ResultScreen

---

### 3.15 `screens/result_screen.dart`

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

### 3.16 `screens/delivery_screen.dart`

Pantalla de ejecución del reparto en tiempo real. La más compleja de la app.

**Qué muestra:**
- AppBar: "En Reparto" + badge con conteo de completadas
- Cabecera de progreso: "X de Y entregas" con chips (✅ entregadas, 🚫 ausentes, ⚠️ incidencias) y barra de progreso
- Mapa en modo delivery (tramo GPS → próxima parada, no la ruta completa)
- Tarjeta "Siguiente Parada": número, cliente, dirección, paquetes, botón de navegación externa
- Botones de acción: "Entregado" (verde, grande), "Ausente" (ámbar), "Incidencia" (rojo, pequeño)

**Estado:** recibe `DeliverySession` existente del constructor. Muta directamente sobre ese objeto.

**Métodos clave:**

`initState()`: espera 1.5s y llama a `_fetchSegmentFromGps()` para dibujar el primer tramo.

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

`_showReorderSheet()`:
- Muestra `ReorderableListView` con las paradas pendientes
- Al confirmar: reconstruye la lista [origen, completadas, pendientes-reordenadas]
- Guarda sesión, recalcula segmento

`_showFinishedDialog()`:
- Muestra resumen: entregadas, ausentes, incidencias, tiempo total, distancia
- "Cerrar Sesión y Limpiar" → `PersistenceService.clearSession()` → `Navigator.popUntil(first)`

`_onWillPop()`: si no está terminado, muestra confirmación; informa que el progreso está guardado y se puede reanudar.

**Servicios llamados:**
- `Geolocator.getCurrentPosition()` — GPS del dispositivo
- `ApiService.getRouteSegment()` — tramo OSRM entre dos puntos
- `PersistenceService.updateStopStatus()` — persiste cada entrega
- `launchUrl()` — abre Google Maps externo para navegación

**Navegación:** tras finalizar → `ImportScreen` (popUntil el primero de la pila)

---

### 3.17 `widgets/route_map.dart`

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

### 3.18 `widgets/stops_list.dart`

Lista scrollable de paradas. Sincronizada con el mapa.

**Props:** `stops`, `highlightedIndex?`, `onStopTapped?`

**Comportamiento:**
- Separa paradas geocodificadas de paradas fallidas con `_UnresolvedSeparator`
- `_StopTile`: tile animado (250ms). Resalte con fondo azul claro; fallos con fondo ámbar. Muestra: icono de orden, nombre del cliente (o dirección si no hay), distancia acumulada, chip de paquetes si >1

---

### 3.19 `widgets/stats_banner.dart`

Fila horizontal de tarjetas de estadísticas.

**`StatItem`**: `label`, `value`, `icon`

**`StatsBanner`**: recibe `List<StatItem>`, renderiza una fila de tarjetas con icono + valor grande + label. Fondo claro con sombra suave.

---

### 3.20 `widgets/origin_selector.dart`

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
       └─ CsvData {clientes, direcciones, ciudades}
            └─ fullAddresses: List<String>
                 │
                 ▼
         ApiService.validationStart()
              │  POST /api/validation/start
              │    └─ validation.py
              │         └─ geocoding.py
              │              └─ Nominatim (HTTP)
              │
              ▼
         ValidationResponse
         {okCount, problemCount, stops[]{lat, lon, status}}
              │
              │  [Opcional: usuario corrige coords manualmente]
              │
              ▼
         ApiService.optimize()
              │  POST /api/optimize
              │    └─ optimize.py
              │         ├─ geocoding.py (solo paradas sin coords)
              │         ├─ routing.optimize_route()
              │         │      └─ VROOM (HTTP) → waypoint_order
              │         └─ routing.get_route_details()
              │                └─ OSRM (HTTP) → geometry + steps
              │
              ▼
         OptimizeResponse
         {stops[order optimizado], geometry GeoJSON, steps[]}
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
                        ├─ ApiService.getRouteSegment()
                        │    POST /api/route-segment
                        │      └─ OSRM → segmento GPS→parada
                        │
                        └─ PersistenceService.updateStopStatus()
                             └─ Hive (estado de cada entrega)
```

---

## 5. Servicios externos

| Servicio | URL | Protocolo | Propósito | Timeout |
|----------|-----|-----------|-----------|---------|
| **Nominatim** | `nominatim.openstreetmap.org` | HTTPS | Geocodificación de direcciones | 30s/llamada |
| **OSRM** | `localhost:5000` | HTTP (Docker) | Cálculo de rutas por carretera, geometría GeoJSON, instrucciones | 60s |
| **VROOM** | `localhost:3000` | HTTP (Docker) | Resolución del TSP (orden óptimo de visita) | 120s |
| **Google Maps** | externo | URL scheme | Navegación giro a giro (abre la app del sistema) | — |
| **OpenStreetMap tiles** | `tile.openstreetmap.org` | HTTPS | Teselas del mapa base en la app Flutter | — |
