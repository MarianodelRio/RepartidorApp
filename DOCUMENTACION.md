# 📦 Repartir App — Documentación Completa del Proyecto

> **Versión:** 3.2.0  
> **Última actualización:** Febrero 2026  
> **Ubicación:** `/home/mariano/Desktop/app_repartir/`  
> **Zona de operación:** Posadas, Córdoba, España

---

## 📑 Índice

1. [Visión General del Proyecto](#1-visión-general-del-proyecto)
2. [Arquitectura del Sistema](#2-arquitectura-del-sistema)
3. [Tecnologías y Herramientas](#3-tecnologías-y-herramientas)
4. [Estructura de Archivos Completa](#4-estructura-de-archivos-completa)
5. [Backend (FastAPI + Python)](#5-backend-fastapi--python)
   - 5.1 [Configuración Central](#51-configuración-central-appcoreconfig)
   - 5.2 [Modelos Pydantic](#52-modelos-pydantic-appmodels__init__py)
   - 5.3 [Servicio de Geocodificación](#53-servicio-de-geocodificación-appservicesgeocodingpy)
   - 5.4 [Servicio de Routing (VROOM + OSRM)](#54-servicio-de-routing-appservicesroutingpy)
   - 5.5 [Router de Optimización](#55-router-de-optimización-approutersoptimizepy)
   - 5.6 [Normalizador de Direcciones](#56-normalizador-de-direcciones-appservicesaddress_normalizerpy--nuevo-bloque-1)
   - 5.7 [Router de Validación](#57-router-de-validación-approutersvalidatepy--nuevo-bloque-1)
   - 5.8 [Base de Datos de Calles](#58-base-de-datos-de-calles-appservicesstreet_dbpy--nuevo-bloque-2)
   - 5.9 [Resolución de Calles](#59-resolución-de-calles-appservicesstreet_resolverpy--nuevo-bloque-2)
   - 5.10 [Router de Calles](#510-router-de-calles-approutersstreetspy--nuevo-bloque-2)
   - 5.11 [Punto de Entrada](#511-punto-de-entrada-appmainpy)
6. [Servicios Docker (OSRM + VROOM)](#6-servicios-docker-osrm--vroom)
   - 6.1 [OSRM — Motor de Rutas](#61-osrm--motor-de-rutas)
   - 6.2 [VROOM — Optimizador TSP/VRP](#62-vroom--optimizador-tspvrp)
   - 6.3 [Docker Compose](#63-docker-compose)
7. [Flutter App (Frontend Móvil)](#7-flutter-app-frontend-móvil)
   - 7.1 [Configuración del Proyecto](#71-configuración-del-proyecto)
   - 7.2 [Punto de Entrada (main.dart)](#72-punto-de-entrada-maindart)
   - 7.3 [Configuración API (api_config.dart)](#73-configuración-api-api_configdart)
   - 7.4 [Modelos de Datos Flutter](#74-modelos-de-datos-flutter)
   - 7.5 [Servicios Flutter](#75-servicios-flutter)
   - 7.6 [Pantallas (Screens)](#76-pantallas-screens)
   - 7.7 [Widgets Reutilizables](#77-widgets-reutilizables)
   - 7.8 [Configuración Android](#78-configuración-android)
8. [Flujo de Datos Completo](#8-flujo-de-datos-completo)
9. [API — Contratos y Endpoints](#9-api--contratos-y-endpoints)
10. [Guía de Instalación y Arranque](#10-guía-de-instalación-y-arranque)
11. [Guía de Desarrollo y Modificaciones](#11-guía-de-desarrollo-y-modificaciones)
12. [Problemas Conocidos y Soluciones](#12-problemas-conocidos-y-soluciones)
13. [Glosario Técnico](#13-glosario-técnico)
14. [Generación de APK y Despliegue en Móvil](#14-generación-de-apk-y-despliegue-en-móvil)

---

## 1. Visión General del Proyecto

### ¿Qué es Repartir App?

**Repartir App** es una aplicación móvil profesional diseñada para **optimizar rutas de reparto** en la localidad de **Posadas (Córdoba, España)**. Permite a un repartidor:

1. **Importar** un archivo CSV con las direcciones de entrega del día.
2. **Calcular automáticamente** el orden óptimo de visita (ruta más corta/rápida).
3. **Visualizar** la ruta en un mapa interactivo con lista de paradas por nombre de cliente.
4. **Ejecutar** el reparto marcando cada entrega como "Entregado", "No estaba" o "Incidencia".
5. **Reanudar** el reparto si la app se cierra (persistencia local).
6. **Dividir** el trabajo entre 2 repartidores cuando hay muchos paquetes.

### ¿Cómo funciona a alto nivel?

```
┌─────────────────┐       HTTP/JSON       ┌──────────────────┐
│                  │ ───────────────────▶  │                  │
│  Flutter App     │                       │  FastAPI Backend │
│  (Android/iOS)   │ ◀───────────────────  │  (Python)        │
│                  │                       │                  │
└─────────────────┘                       └────────┬─────────┘
                                                   │
                                          ┌────────┴─────────┐
                                          │                  │
                                    ┌─────▼─────┐    ┌──────▼──────┐
                                    │   OSRM    │    │   VROOM     │
                                    │ (Docker)  │    │  (Docker)   │
                                    │ Puerto    │    │  Puerto     │
                                    │ 5000      │    │  3000       │
                                    └───────────┘    └─────────────┘
                                    Motor de rutas    Optimizador
                                    (calles reales)   (orden óptimo)
```

El **usuario** interactúa solo con la app Flutter en su teléfono. La app envía las direcciones al backend FastAPI, que se encarga de:
- **Geocodificar** las direcciones (texto → coordenadas GPS) usando Nominatim/OpenStreetMap.
- **Optimizar** el orden de visita usando VROOM (resuelve el Problema del Viajante).
- **Calcular** la ruta real por calles usando OSRM (direcciones paso a paso).
- **Devolver** todo empaquetado al móvil.

---

## 2. Arquitectura del Sistema

### Diagrama de Componentes

```
┌─ Dispositivo Móvil ──────────────────────────────────────────┐
│                                                              │
│  ┌─ Flutter App ──────────────────────────────────────────┐  │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐            │  │
│  │  │  Screens  │  │ Widgets  │  │  Services │            │  │
│  │  │(pantallas)│  │(UI compo-│  │(lógica de │            │  │
│  │  │          │  │ nentes)  │  │ negocio)  │            │  │
│  │  └────┬─────┘  └────┬─────┘  └─────┬─────┘            │  │
│  │       │              │              │                   │  │
│  │  ┌────▼──────────────▼──────────────▼─────┐            │  │
│  │  │              Models                     │            │  │
│  │  │  (contratos de datos compartidos)       │            │  │
│  │  └────────────────┬───────────────────────┘            │  │
│  │                   │                                     │  │
│  │  ┌────────────────▼───────────────────────┐            │  │
│  │  │         Hive (almacenamiento local)    │            │  │
│  │  │  Persistencia de sesiones de reparto   │            │  │
│  │  └────────────────────────────────────────┘            │  │
│  └────────────────────────────────────────────────────────┘  │
│                           │ HTTP                             │
└───────────────────────────┼──────────────────────────────────┘
                            │
┌─ Servidor (localhost) ────┼──────────────────────────────────┐
│                           ▼                                  │
│  ┌─ FastAPI (puerto 8000) ───────────────────────────────┐  │
│  │  main.py → routers/optimize.py                        │  │
│  │           ↓               ↓                           │  │
│  │  services/geocoding.py   services/routing.py          │  │
│  │  (Nominatim API)         (VROOM + OSRM clients)       │  │
│  └───────────┬───────────────────┬───────────────────────┘  │
│              │                   │                           │
│  ┌───────────▼────┐   ┌─────────▼──────┐                   │
│  │ OSRM (Docker)  │   │ VROOM (Docker) │                   │
│  │ Puerto 5000    │   │ Puerto 3000    │                   │
│  │ Datos: Andalu- │   │ Usa OSRM para  │                   │
│  │ cía OSM (.pbf) │   │ distancias     │                   │
│  └────────────────┘   └────────────────┘                   │
└──────────────────────────────────────────────────────────────┘
```

### Capas del sistema

| Capa | Tecnología | Responsabilidad |
|------|-----------|-----------------|
| **Presentación** | Flutter (Dart) | UI móvil, interacción con usuario |
| **API REST** | FastAPI (Python) | Orquestación, validación, transformación |
| **Geocodificación** | Nominatim (OSM) | Convertir "Calle X" → (lat, lon) |
| **Optimización** | VROOM (Docker) | Resolver TSP/VRP (orden óptimo) |
| **Routing** | OSRM (Docker) | Calcular rutas reales por calles |
| **Persistencia** | Hive (Flutter) | Guardar sesión de reparto localmente |
| **Mapas** | OpenStreetMap tiles | Visualización del mapa en la app |

---

## 3. Tecnologías y Herramientas

### Backend

| Herramienta | Versión | Para qué se usa |
|-------------|---------|-----------------|
| **Python** | 3.10.12 | Lenguaje del backend |
| **FastAPI** | última | Framework web para la API REST |
| **Uvicorn** | última | Servidor ASGI que ejecuta FastAPI |
| **Pydantic** | v2 | Validación de datos y modelos request/response |
| **Requests** | última | Cliente HTTP para llamar a OSRM/VROOM/Nominatim |
| **Pandas** | última | Parseo de archivos CSV en el endpoint `/optimize/csv` |
| **python-multipart** | última | Soporte para subida de archivos (multipart/form-data) |
| **aiosqlite** | 0.22.1 | SQLite async para la BD de calles (Bloque 2) |
| **RapidFuzz** | 3.14.3 | Fuzzy string matching determinista (Bloque 2) |

### Servicios Docker

| Servicio | Imagen | Puerto | Función |
|----------|--------|--------|---------|
| **OSRM** | `osrm/osrm-backend` | 5000 | Motor de rutas: calcula la ruta real entre puntos por calles |
| **VROOM** | `ghcr.io/vroom-project/vroom-docker:v1.14.0` | 3000 | Optimizador: resuelve el Problema del Viajante (TSP/VRP) |

### Frontend (Flutter)

| Herramienta | Versión | Para qué se usa |
|-------------|---------|-----------------|
| **Flutter** | 3.38.9 | Framework de UI multiplataforma |
| **Dart** | 3.10.8 | Lenguaje de programación de Flutter |

### Paquetes Flutter (pubspec.yaml)

| Paquete | Versión | Función |
|---------|---------|---------|
| `http` | ^1.2.0 | Llamadas HTTP al backend FastAPI |
| `file_picker` | ^8.0.0 | Selector de archivos del sistema (para CSV) |
| `geolocator` | ^13.0.0 | Acceso al GPS del dispositivo |
| `csv` | ^6.0.0 | Parser de archivos CSV en el cliente |
| `intl` | ^0.20.0 | Formateo de fechas y números (internacionalización) |
| `permission_handler` | ^11.0.0 | Solicitar/verificar permisos del sistema (GPS) |
| `flutter_map` | ^7.0.2 | Widget de mapa con tiles de OpenStreetMap |
| `latlong2` | ^0.9.1 | Tipos de datos para coordenadas (LatLng) |
| `hive` | ^2.2.3 | Base de datos local NoSQL ultrarrápida |
| `hive_flutter` | ^1.1.0 | Integración de Hive con Flutter |
| `url_launcher` | ^6.2.0 | Abrir Google Maps para navegación externa |

### Herramientas de desarrollo

| Herramienta | Para qué se usa |
|-------------|-----------------|
| **Docker** + **Docker Compose** | Ejecutar OSRM y VROOM como contenedores |
| **VS Code** | Editor de código principal |
| **Android Studio / Emulador** | Probar la app en dispositivo virtual |
| **Nominatim** (online) | Servicio gratuito de geocodificación de OpenStreetMap |

---

## 4. Estructura de Archivos Completa

```
app_repartir/                          ← RAÍZ DEL PROYECTO
│
├── docker-compose.yml                 ← Define servicios Docker (OSRM + VROOM)
├── requirements.txt                   ← Dependencias Python del backend
├── paradas.csv                        ← Archivo CSV de ejemplo con direcciones
├── DOCUMENTACION.md                   ← Este archivo
│
├── venv/                              ← Entorno virtual Python (NO tocar)
│
├── osrm/                              ← Datos cartográficos de Andalucía para OSRM
│   ├── andalucia-latest.osm.pbf       ← Datos brutos de OpenStreetMap
│   ├── andalucia-latest.osrm          ← Datos procesados por OSRM
│   ├── andalucia-latest.osrm.*        ← (20+ archivos de índices de OSRM)
│   └── ...
│
├── vroom-conf/                        ← Configuración de VROOM
│   ├── config.yml                     ← Puerto, threads, conexión a OSRM
│   └── access.log                     ← Logs de acceso de VROOM
│
├── app/                               ← 🐍 BACKEND PYTHON (FastAPI)
│   ├── main.py                        ← Punto de entrada de FastAPI (lifecycle DB)
│   ├── core/
│   │   ├── __init__.py
│   │   └── config.py                  ← Configuración centralizada (URLs, constantes)
│   ├── data/
│   │   └── streets.db                 ← 🗄️ SQLite: alias + virtual + cache (NUEVO Bloque 2)
│   ├── models/
│   │   ├── __init__.py                ← Todos los modelos Pydantic (Request/Response)
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── optimize.py                ← Endpoints POST /optimize y /optimize/csv
│   │   ├── validate.py                ← Endpoints /validate-addresses, /normalize-addresses
│   │   └── streets.py                 ← 🆕 Endpoints /streets/* (Bloque 2)
│   └── services/
│       ├── __init__.py
│       ├── geocoding.py               ← Geocodificación con Nominatim (texto → coords)
│       ├── routing.py                 ← Optimización VROOM + rutas OSRM
│       ├── address_normalizer.py      ← 🆕 Normalización + agrupación (Bloque 1)
│       ├── street_db.py               ← 🆕 SQLite async (alias/virtual/cache) (Bloque 2)
│       └── street_resolver.py         ← 🆕 Resolución batch + scoring RapidFuzz (Bloque 2)
│
└── flutter_app/                       ← 📱 FRONTEND FLUTTER
    ├── pubspec.yaml                   ← Dependencias y config del proyecto Flutter
    ├── android/                       ← Configuración nativa Android
    │   └── app/src/main/
    │       └── AndroidManifest.xml    ← Permisos (GPS, Internet, cleartext)
    └── lib/                           ← 🎯 CÓDIGO FUENTE DART
        ├── main.dart                  ← Punto de entrada de la app
        │
        ├── config/
        │   ├── api_config.dart        ← URL del backend (ngrok), timeouts, endpoints
        │   └── app_theme.dart         ← 🎨 Paleta de colores centralizada (NUEVO v3.0)
        │
        ├── models/
        │   ├── route_models.dart      ← Modelos de datos (espejo del backend)
        │   └── delivery_state.dart    ← Estado de ejecución del reparto
        │
        ├── services/
        │   ├── api_service.dart       ← Cliente HTTP → backend FastAPI
        │   ├── csv_service.dart       ← Parser de CSV en el cliente
        │   ├── location_service.dart  ← Acceso al GPS con manejo de permisos
        │   └── persistence_service.dart ← Persistencia Hive (guardar/cargar sesión)
        │
        ├── screens/
        │   ├── splash_screen.dart     ← Pantalla de bienvenida animada
        │   ├── import_screen.dart     ← Pantalla principal: importar CSV + calcular
        │   ├── result_screen.dart     ← Resultados: mapa + lista de paradas
        │   ├── delivery_screen.dart   ← Ejecución del reparto (Entregado/No estaba)
        │   ├── loading_order_screen.dart ← Ayuda para cargar furgoneta (LIFO)
        │   └── route_picker_screen.dart ← Elegir entre 2 rutas (reparto compartido)
        │
        └── widgets/
            ├── route_map.dart         ← Mapa interactivo con ruta, marcadores y GPS
            ├── stops_list.dart        ← Lista de paradas con nombre de cliente y distancia
            ├── column_mapper.dart     ← Selector de columnas del CSV
            ├── csv_preview_table.dart ← Vista previa de datos del CSV
            ├── origin_selector.dart   ← Selector del punto de inicio
            └── stats_banner.dart      ← Banner con estadísticas (paradas/km/min)
```

---

## 5. Backend (FastAPI + Python)

El backend es una **API REST** escrita en Python con FastAPI. Su trabajo es:
1. Recibir direcciones del cliente móvil.
2. Convertirlas en coordenadas GPS (geocodificación).
3. Calcular el orden óptimo de visita (VROOM).
4. Obtener la ruta real por calles con instrucciones (OSRM).
5. Devolver todo como JSON al móvil.

### 5.1 Configuración Central (`app/core/config.py`)

Este archivo centraliza **todas** las constantes del proyecto. Si necesitas cambiar una URL, un timeout, o la dirección de inicio por defecto, este es el único lugar donde hacerlo.

```python
# Rutas del proyecto
BASE_DIR = Path(__file__).resolve().parent.parent    # → /app_repartir/app/
PROJECT_DIR = BASE_DIR.parent                         # → /app_repartir/

# URLs de servicios Docker locales
OSRM_BASE_URL = "http://localhost:5000"       # Motor de rutas
VROOM_BASE_URL = "http://localhost:3000"      # Optimizador TSP

# Geocodificación (servicio público gratuito de OpenStreetMap)
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_USER_AGENT = "posadas-route-planner/2.0 (local)"

# Zona de trabajo fija: Posadas, Córdoba
START_ADDRESS = "Calle Callejon de Jesús 1, Posadas, Córdoba, España"
POSADAS_CENTER = (37.802, -5.105)             # Centro de Posadas (lat, lon)
POSADAS_VIEWBOX = "-5.15,37.78,-5.06,37.83"  # Bounding box para priorizar resultados

# Límites
MAX_STOPS = 200            # Máximo de paradas por petición
GEOCODE_DELAY = 1.0        # Segundos entre llamadas a Nominatim (rate limit)
GEOCODE_TIMEOUT = 30       # Timeout de geocodificación
OSRM_TIMEOUT = 60          # Timeout para OSRM
VROOM_TIMEOUT = 120        # Timeout para VROOM
```

**Cosas importantes:**
- `START_ADDRESS`: Es la dirección por defecto del taller/almacén. Es el punto desde donde sale el repartidor.
- `POSADAS_VIEWBOX`: Un rectángulo geográfico que cubre Posadas. Se usa para que Nominatim priorice resultados dentro de esta zona.
- `GEOCODE_DELAY`: Nominatim es gratuito pero tiene rate limiting (1 petición/segundo). Este delay lo respeta.

---

### 5.2 Modelos Pydantic (`app/models/__init__.py`)

Los modelos definen el **contrato** entre frontend y backend. Pydantic los valida automáticamente: si el frontend envía datos mal formados, FastAPI rechaza la petición con un error claro.

#### Modelo de Entrada (Request)

```python
class OptimizeRequest(BaseModel):
    addresses: list[str]                      # Lista de direcciones (obligatoria, mínimo 1)
    client_names: list[str] | None = None     # Nombres de cliente (opcional, mismo orden que addresses)
    start_address: str | None = None          # Dirección de inicio (opcional)
    num_vehicles: int = 1                     # 1 o 2 vehículos/rutas (valor 1 por defecto)
```

**Ejemplo de uso:**
```json
{
  "addresses": [
    "Calle Gaitán 1, Posadas",
    "Calle Santiago 2, Posadas",
    "Calle Molinos 1, Posadas"
  ],
  "client_names": ["Juan García", "María López", ""],
  "start_address": null,
  "num_vehicles": 1
}
```

> **Nota v2.1:** Los campos `client_names`, `telefono` y `notas` son opcionales.
> Solo `addresses` es obligatorio. Valores vacíos o nulos se aceptan sin error.

#### Modelos de Salida (Response)

| Modelo | Campos clave | Descripción |
|--------|-------------|-------------|
| `StopInfo` | order, address, label, client_name, type, lat, lon, distance_meters | Una parada identificada por `client_name` (si existe) |
| `RouteSummary` | total_stops, total_distance_m, total_distance_display, computing_time_ms | Resumen global de la ruta (sin estimaciones de tiempo) |
| `RouteStep` | text, distance_m, location | Una instrucción de navegación ("Girar a la derecha por Calle Mayor") |
| `Coordinate` | lat, lon | Par de coordenadas |
| `OptimizeResponse` | success, summary, stops, geometry, steps, route_index, total_routes | Respuesta completa con ruta optimizada |
| `MultiRouteResponse` | success, routes (lista de OptimizeResponse), total_routes | Respuesta con 2 rutas para reparto compartido |
| `ErrorResponse` | success=false, error, detail | Respuesta de error estándar |

**Campos especiales de `OptimizeResponse`:**
- `geometry`: Es un objeto GeoJSON de tipo `LineString` con las coordenadas exactas de la polilínea de la ruta. El mapa de Flutter lo dibuja directamente.
- `route_index`: Cuando hay 2 rutas, indica si es la ruta 0 o la ruta 1.
- `total_routes`: Cuántas rutas se generaron en total (1 o 2).

**Campos de `StopInfo`:**
- `type`: Vale `"origin"` para el punto de partida y `"stop"` para las paradas de entrega.
- `client_name`: Nombre del cliente/destinatario. Es la **identidad principal** del punto.
- `label`: Texto de visualización (ej: "📍 Juan García" o "📍 Parada 3" si no hay nombre).
- `distance_meters`: Distancia acumulada desde el inicio hasta esta parada.

> **Nota v2.1:** Los campos `eta_seconds`, `eta_display`, `total_duration_s` y `total_duration_display`
> han sido **eliminados** porque las estimaciones de tiempo no son fiables al no considerar
> las paradas físicas de carga/descarga.

---

### 5.3 Servicio de Geocodificación (`app/services/geocoding.py`)

**¿Qué hace?** Convierte texto como `"Calle Gaitán 1, Posadas"` en coordenadas GPS `(37.8021, -5.1043)`.

**¿Cómo funciona?**
1. Recibe una dirección en texto.
2. La normaliza añadiendo ", Posadas, Córdoba, España" si no lo tiene ya.
3. Consulta la API de Nominatim (servicio gratuito de OpenStreetMap).
4. Cachea el resultado para no repetir consultas.
5. Respeta un delay de 1 segundo entre consultas (rate limiting de Nominatim).

**Funciones principales:**

| Función | Entrada | Salida | Descripción |
|---------|---------|--------|-------------|
| `clean_address(raw)` | `"Calle Gaitán 1"` | `"Calle Gaitán 1, Posadas, Córdoba, España"` | Normaliza la dirección |
| `geocode(address)` | Dirección texto | `(lat, lon)` o `None` | Geocodifica una dirección |
| `geocode_batch(addresses)` | Lista de direcciones | Lista de `(addr, (lat,lon)|None)` | Geocodifica varias respetando rate limit |
| `clear_cache()` | — | — | Limpia la caché de geocodificación |

**La caché:** Es un diccionario en memoria (`_cache`). La clave es la dirección en minúsculas, el valor es `(lat, lon)` o `None`. Esto evita llamar a Nominatim dos veces por la misma dirección. **Se pierde al reiniciar el servidor.**

**Parámetros de la consulta a Nominatim:**
- `countrycodes=es`: Solo buscar en España.
- `viewbox`: Priorizar resultados dentro del rectángulo que cubre Posadas.
- `bounded=0`: No restringir estrictamente al viewbox (permite resultados cercanos).
- `format=jsonv2`: Formato de respuesta JSON v2.
- `limit=1`: Solo el mejor resultado.

---

### 5.4 Servicio de Routing (`app/services/routing.py`)

Este es el **corazón del backend**. Tiene dos funciones principales:

#### `optimize_route(coords, num_vehicles=1)` → Orden óptimo (VROOM)

**¿Qué problema resuelve?** El "Problema del Viajante" (TSP — Travelling Salesman Problem): dado un conjunto de puntos, ¿en qué orden visitarlos para minimizar la distancia total?

**¿Cómo funciona?**
1. Recibe una lista de coordenadas. La primera es el origen (fija, no se reordena).
2. Construye una petición para VROOM con:
   - **Vehículos** (`vehicles`): 1 o 2 vehículos que parten del origen (sin retorno → "Open Trip").
   - **Trabajos** (`jobs`): Las paradas a visitar.
3. VROOM resuelve el problema usando OSRM para las distancias reales (no en línea recta).
4. Devuelve el orden óptimo con tiempos y distancias acumuladas.

**Formato del payload a VROOM:**
```json
{
  "vehicles": [
    {"id": 0, "profile": "car", "start": [-5.105, 37.802]}
  ],
  "jobs": [
    {"id": 1, "location": [-5.104, 37.801]},
    {"id": 2, "location": [-5.106, 37.803]}
  ],
  "options": {"g": true}
}
```

> **Nota v2.1 — Equilibrio por carga en 2 rutas:**
> Para 2 vehículos, se usa el sistema de `capacity` / `amount` de VROOM para
> equilibrar por **número de paradas** (no por tiempo de trayecto):
> ```json
> {
>   "vehicles": [
>     {"id": 0, "profile": "car", "start": [...], "capacity": [4]},
>     {"id": 1, "profile": "car", "start": [...], "capacity": [4]}
>   ],
>   "jobs": [
>     {"id": 1, "location": [...], "amount": [1]},
>     {"id": 2, "location": [...], "amount": [1]}
>   ]
> }
> ```
> Cada job "pesa" 1 unidad y la capacidad se fija a `ceil(N/2)`, asegurando
> que las paradas se reparten equitativamente en volumen entre ambas rutas.

**Respuesta para 1 vehículo:**
```python
{
    "waypoint_order": [0, 2, 1, 3],    # Orden óptimo (0 = origen)
    "stop_details": [...],              # Distancia por parada
    "total_distance": 4200,             # Metros totales
    "total_duration": 720,              # Segundos totales (uso interno, no se expone)
}
```

**Respuesta para 2 vehículos (multi-ruta):**
```python
{
    "multi": True,
    "routes": [
        {"waypoint_order": [0, 1, 3], "stop_details": [...], ...},
        {"waypoint_order": [0, 2, 4], "stop_details": [...], ...},
    ]
}
```

VROOM reparte las paradas entre los 2 vehículos equilibrando por número de paradas (carga) para asegurar un reparto de trabajo equitativo.

#### `get_route_details(coords_ordered)` → Ruta real con instrucciones (OSRM)

**¿Qué hace?** Dado un orden de coordenadas ya optimizado, calcula la ruta real por calles con:
- La **polilínea exacta** (GeoJSON) para dibujar en el mapa.
- Las **instrucciones de navegación** paso a paso en español.

**¿Cómo funciona?**
1. Construye una URL de la API de OSRM con todas las coordenadas encadenadas.
2. Pide geometría completa en formato GeoJSON + steps (instrucciones).
3. Traduce las instrucciones de OSRM (en inglés) al español usando diccionarios de traducción.

**Diccionarios de traducción:**
```python
MANEUVER_ES = {
    "depart": "Salir",
    "arrive": "Llegar al destino",
    "turn": → se combina con modifier
    "roundabout": "Entrar en la rotonda",
    ...
}
MODIFIER_ES = {
    "left": "a la izquierda",
    "right": "a la derecha",
    "slight left": "ligeramente a la izquierda",
    ...
}
```

**Funciones auxiliares:**
- `_step_text(mtype, modifier, name)`: Genera texto como "Girar a la derecha por Calle Mayor".
- `_format_distance(meters)`: `450` → `"450 m"`, `4200` → `"4.2 km"`.

> **Nota v2.1:** `_format_duration()` sigue existiendo en el código pero ya no se exporta
> ni se usa en la respuesta API, ya que los tiempos estimados se han eliminado.

---

### 5.5 Router de Optimización (`app/routers/optimize.py`)

Contiene los **2 endpoints** principales de la API:

#### `POST /api/optimize`

Recibe una lista de direcciones en JSON y devuelve la ruta optimizada.

**Flujo paso a paso:**
1. Validar que hay direcciones y que no exceden `MAX_STOPS` (200).
2. Determinar la dirección de origen (la del request o la predeterminada).
3. Geocodificar el origen.
4. Geocodificar todas las paradas (en lote, respetando rate limit).
5. Llamar a VROOM para optimizar el orden (`optimize_route()`).
6. Si hay 2 vehículos → construir `MultiRouteResponse` con `_build_multi_response()`.
7. Si hay 1 vehículo → llamar a OSRM para la ruta detallada (`get_route_details()`).
8. Construir la respuesta con paradas, resumen, geometría e instrucciones.
9. Devolver `OptimizeResponse` o `MultiRouteResponse`.

#### `POST /api/optimize/csv`

Recibe un archivo CSV por `multipart/form-data`. Solo la columna de dirección es obligatoria; nombre, teléfono y notas son opcionales.

**Flujo:**
1. Lee el archivo CSV con Pandas.
2. Busca una columna de dirección (acepta: `address`, `direccion`, `dirección`, `domicilio`, `calle`).
3. Busca una columna de nombre (acepta: `name`, `nombre`, `cliente`, `destinatario`, `nombre_cliente`) — opcional.
4. Extrae direcciones y nombres (si existen).
5. Crea un `OptimizeRequest(addresses=..., client_names=...)` y llama a `optimize()`.

> **Nota v2.1 — CSV flexible:** `telefono` y `notas` son opcionales (se aceptan valores nulos/vacíos).
> Solo `address`/`direccion` es obligatorio.

#### `_build_multi_response()` (función auxiliar)

Cuando se piden 2 rutas:
1. Para cada ruta del resultado de VROOM, obtiene la ruta detallada de OSRM.
2. Construye un `OptimizeResponse` por cada ruta, con su propia geometría, paradas e instrucciones.
3. Los envuelve en un `MultiRouteResponse`.

---

### 5.6 Normalizador de Direcciones (`app/services/address_normalizer.py`) — NUEVO Bloque 1

Módulo de ~525 líneas que normaliza direcciones crudas y las agrupa por calle.

**Funciones principales:**

| Función | Entrada | Salida | Descripción |
|---------|---------|--------|-------------|
| `normalize_text(text)` | `"  Cálle  Córdoba  "` | `"calle cordoba"` | Minúsculas, sin acentos, espacios limpios |
| `normalize_address(raw)` | `"C/ Córdoba 12, 14730"` | `NormalizedAddress(...)` | Pipeline completo de normalización |
| `group_by_street(addrs)` | `["C/ Córdoba 12", "C/ Córdoba 15"]` | `(normalized[], groups[])` | Agrupa por `street_key` |

**Dataclasses:**

- **`NormalizedAddress`**: `street_key`, `full_street`, `house_number`, `postcode`, `city`, `extra`, `for_geocoding`
- **`StreetGroup`**: `street_key`, `street_display`, `city`, `postcode`, `stop_indices[]`, `addresses[]`, `house_numbers[]`, `count`

**Diccionario de abreviaturas** (~45 entradas): `C/ → Calle`, `AVDA → Avenida`, `Pza → Plaza`, `CRTA → Carretera`, etc.

**`street_key`** es la clave de agrupación normalizada: `"calle cordoba|posadas|14730"`. Permite:
- Agrupar paradas en la misma calle (1 geocodificación por calle en vez de por dirección).
- Lookup O(1) en la BD SQLite (Bloque 2).

---

### 5.7 Router de Validación (`app/routers/validate.py`) — NUEVO Bloque 1

Endpoints para validar y normalizar direcciones antes de optimizar.

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/api/validate-addresses` | POST | Valida + geocodifica con `street_groups` y `unique_streets` en respuesta |
| `/api/normalize-addresses` | POST | Solo normaliza y agrupa (sin geocodificar) |
| `/api/add-geocode-override` | POST | Override manual de coordenadas |

---

### 5.8 Base de Datos de Calles (`app/services/street_db.py`) — NUEVO Bloque 2

Servicio SQLite async (~334 líneas) para resolución O(1) de calles antes de consultar Nominatim.

**Tablas:**

```
┌─────────────────────────────────────────────────────────────────┐
│  alias (PK: street_key)                                        │
│  ├── raw_street_norm   → Nombre crudo normalizado               │
│  ├── canonical_name    → Nombre canónico confirmado              │
│  ├── lat, lon          → Coordenadas                             │
│  ├── city, postcode    → Contexto                                │
│  └── updated_at        → Timestamp                               │
├─────────────────────────────────────────────────────────────────┤
│  street_virtual (PK: street_key)                                │
│  ├── name_norm         → Nombre normalizado                      │
│  ├── lat, lon          → Coordenadas manuales                    │
│  ├── osrm_snap_lat/lon → Snap OSRM al nodo más cercano          │
│  └── updated_at        → Timestamp                               │
├─────────────────────────────────────────────────────────────────┤
│  geocode_cache (PK: street_key)                                 │
│  ├── lat, lon          → Coordenadas cacheadas                   │
│  ├── canonical_name    → Nombre resuelto                         │
│  ├── confidence        → Score 0-100                             │
│  ├── source            → "nominatim" | "alias" | "virtual" | "pin" │
│  └── updated_at        → Timestamp                               │
└─────────────────────────────────────────────────────────────────┘
```

**API del módulo:**

| Función | Descripción |
|---------|-------------|
| `get_db()` | Conexión singleton async |
| `close_db()` | Cierra conexión |
| `get_aliases_batch(keys[])` | Lookup batch → `dict[key, AliasRow]` |
| `get_virtuals_batch(keys[])` | Lookup batch → `dict[key, StreetVirtualRow]` |
| `get_cache_batch(keys[])` | Lookup batch → `dict[key, GeocodeCacheRow]` |
| `upsert_alias(...)` | Inserta o actualiza alias |
| `upsert_street_virtual(...)` | Inserta o actualiza calle virtual |
| `upsert_geocode_cache(...)` | Inserta o actualiza cache |
| `get_db_stats()` | Contadores por tabla |

**Ruta del fichero:** `app/data/streets.db` (creado automáticamente al arrancar).

---

### 5.9 Resolución de Calles (`app/services/street_resolver.py`) — NUEVO Bloque 2

Motor de resolución batch (~468 líneas) con scoring determinista (sin IA).

**Cadena de prioridad:**

```
StreetGroup[] ──▶ 1. alias (SQLite, O(1))
                  2. street_virtual (SQLite, O(1))
                  3. geocode_cache (SQLite, O(1))
                  4. Nominatim (API, 1 req/calle) ──▶ scoring ──▶ cache
```

**Scoring determinista (RapidFuzz):**

| Componente | Puntos | Método |
|------------|--------|--------|
| Similitud nombre | 0–60 | `rapidfuzz.fuzz.token_sort_ratio` (solo parte calle) |
| City match | 0–20 | Comparación normalizada |
| Postcode match | 0–15 | Igualdad o prefijo 3 dígitos |
| Tipo vía compatible | 0–5 | Tabla de equivalencias |
| **Total** | **0–100** | |

**Umbrales:**

| Score | Status | Acción |
|-------|--------|--------|
| ≥ 80 | `resolved` | Auto-resuelto, se guarda en cache |
| 60–79 | `needs_review` | Propone candidato, requiere confirmación |
| < 60 | `unresolved` | Sin match fiable, requiere intervención manual |

**Rendimiento medido:**
- 4 calles con cache/alias: **5.3ms** total
- 2 calles con Nominatim: **~5s** por calle (rate-limited)

---

### 5.10 Router de Calles (`app/routers/streets.py`) — NUEVO Bloque 2

Endpoints REST para resolución y confirmación de calles.

| Endpoint | Método | Descripción | Efecto |
|----------|--------|-------------|--------|
| `/api/streets/resolve_batch` | POST | Resuelve calles en batch | Consulta BD + Nominatim |
| `/api/streets/confirm_alias` | POST | Confirma alias | Upsert alias + cache |
| `/api/streets/create_virtual` | POST | Crea calle virtual | Upsert virtual + cache + OSRM snap |
| `/api/streets/confirm_pin` | POST | Confirma coordenadas manuales | Upsert cache (+ alias opcional) |
| `/api/streets/stats` | GET | Estadísticas de la BD | Solo lectura |

**Principio clave:** Una confirmación de alias/virtual/pin arregla **N paradas** a la vez (todas las de esa calle), no una por una.

---

### 5.11 Punto de Entrada (`app/main.py`)

Configura la aplicación FastAPI:

```python
app = FastAPI(
    title="Posadas Route Planner",
    version="2.1.0",
    docs_url="/docs",      # Swagger UI interactivo
    redoc_url="/redoc",     # Documentación alternativa
)
```

**Middleware CORS:** Permite peticiones desde cualquier origen (`allow_origins=["*"]`).

**Routers registrados:**
- `optimize.router` → `/api/optimize`, `/api/optimize/csv`
- `validate.router` → `/api/validate-addresses`, `/api/normalize-addresses`
- `streets.router` → `/api/streets/*` (Bloque 2)

**Lifecycle events (Bloque 2):**
- `startup` → `await get_db()` (inicializa SQLite)
- `shutdown` → `await close_db()` (cierra conexión)

**Endpoints de sistema:**
- `GET /health` → `{"status": "ok", "version": "2.1.0"}`
- `GET /api/services/status` → Estado de OSRM y VROOM

**Cómo arrancar:**
```bash
cd /home/mariano/Desktop/app_repartir
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Documentación automática:** Acceder a `http://localhost:8000/docs` para ver Swagger UI con todos los endpoints, modelos y poder probar la API interactivamente.

---

## 6. Servicios Docker (OSRM + VROOM)

### 6.1 OSRM — Motor de Rutas

**¿Qué es OSRM?** Open Source Routing Machine. Es un motor que calcula rutas reales por carreteras usando datos de OpenStreetMap. Es como "Google Maps" pero local y gratuito.

**¿Qué datos usa?** El archivo `osrm/andalucia-latest.osm.pbf` contiene toda la red de carreteras de Andalucía descargada de OpenStreetMap. Los archivos `.osrm.*` son índices pre-procesados para consultas rápidas.

**Algoritmo:** MLD (Multi-Level Dijkstra) — el más moderno y rápido de OSRM.

**API que expone (puerto 5000):**
```
GET /route/v1/driving/{lon1},{lat1};{lon2},{lat2}?overview=full&geometries=geojson&steps=true
```
Devuelve: ruta con polilínea GeoJSON, distancia, duración e instrucciones paso a paso.

**Contenedor Docker:**
```yaml
osrm:
  image: osrm/osrm-backend
  container_name: osrm-posadas
  ports: ["5000:5000"]
  volumes: ["./osrm:/data"]
  command: osrm-routed --algorithm mld /data/andalucia-latest.osrm
```

### 6.2 VROOM — Optimizador TSP/VRP

**¿Qué es VROOM?** Vehicle Routing Open-source Optimization Machine. Es un solver que resuelve problemas de optimización de rutas (TSP = un vehículo, VRP = múltiples vehículos).

**¿Cómo funciona?** Recibe una lista de "jobs" (puntos a visitar) y "vehicles" (vehículos disponibles), y devuelve el orden óptimo de visita para minimizar la distancia/tiempo total. Usa OSRM internamente para conocer las distancias reales entre puntos.

**Configuración (`vroom-conf/config.yml`):**
```yaml
cliArgs:
  threads: 4            # Hilos de cómputo
  explore: 5            # Nivel de exploración (0-5, 5 = más exhaustivo)
  maxlocations: 1000    # Máximo de puntos
  maxvehicles: 200      # Máximo de vehículos
  port: 3000            # Puerto del servicio
  router: 'osrm'        # Motor de rutas a usar
routingServers:
  osrm:
    car:
      host: '0.0.0.0'
      port: '5000'      # ← Se conecta a nuestro OSRM
```

**Contenedor Docker:**
```yaml
vroom:
  image: ghcr.io/vroom-project/vroom-docker:v1.14.0
  container_name: vroom-posadas
  network_mode: host          # ← IMPORTANTE: usa la red del host
  environment:
    - VROOM_ROUTER=osrm
  volumes: ["./vroom-conf:/conf"]
  depends_on: [osrm]
```

**¿Por qué `network_mode: host`?** Porque VROOM necesita conectarse a OSRM en `localhost:5000`. Con el modo `host`, el contenedor de VROOM comparte la red del host y puede acceder directamente.

### 6.3 Docker Compose

El archivo `docker-compose.yml` define ambos servicios. Se arrancan juntos con:

```bash
cd /home/mariano/Desktop/app_repartir
docker compose up -d
```

Y se verifican con:
```bash
docker ps
# Debe mostrar: osrm-posadas (puerto 5000) y vroom-posadas (puerto 3000)
```

**Orden de arranque:** `vroom` depende de `osrm` (`depends_on`), así que Docker arranca OSRM primero.

---

## 7. Flutter App (Frontend Móvil)

### 7.1 Configuración del Proyecto

**Archivo `pubspec.yaml`:**
- **Nombre:** `repartir_app`
- **SDK Dart:** `^3.10.8`
- **Versión:** `1.0.0+1`
- Ver tabla de paquetes en la sección 3.

**Tema de la app:**
- Material3 habilitado.
- Color principal: `#2563EB` (azul).
- Fuente: Roboto.
- Fondo de scaffolds: `#F1F5F9` (gris claro).

### 7.2 Punto de Entrada (`main.dart`)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PersistenceService.init();    // Inicializa Hive (BD local)
  runApp(const RepartirApp());        // Arranca la app
}
```

**Flujo de arranque:**
1. Inicializa los bindings de Flutter (necesario antes de llamar a código nativo).
2. Inicializa Hive para la persistencia local.
3. Arranca la app con `ImportScreen` como pantalla inicial.

### 7.3 Configuración API (`api_config.dart`)

A partir de la v2.8 la app usa una URL fija de ngrok (túnel estático) para conectarse al backend.
El usuario **no necesita configurar nada** — la app funciona out-of-the-box.

```dart
class ApiConfig {
  ApiConfig._();

  /// URL de producción (túnel ngrok estático).
  static const String baseUrl =
      'https://unpermanently-repairable-devon.ngrok-free.dev';

  // ── Endpoints ──
  static const String optimizeEndpoint = '/api/optimize';
  static const String optimizeCsvEndpoint = '/api/optimize/csv';
  static const String routeSegmentEndpoint = '/api/route-segment';
  static const String validateEndpoint = '/api/validate-addresses';
  static const String addOverrideEndpoint = '/api/add-geocode-override';
  static const String healthEndpoint = '/health';
  static const String servicesStatusEndpoint = '/api/services/status';

  /// Timeout generoso para /api/optimize.
  /// El geocoding de 70-100 direcciones puede tardar 3-5 minutos.
  static const Duration timeout = Duration(minutes: 10);
}
```

**Zero-Config:** Ya NO es necesario cambiar la URL en el código para usar la app en un dispositivo
físico. El túnel ngrok enruta el tráfico desde cualquier dispositivo con Internet hacia el
servidor local donde corren OSRM y VROOM.

**Endpoints actuales:**
| Endpoint | Método | Función |
|----------|--------|---------|
| `/health` | GET | Verifica que el servidor está vivo |
| `/api/services/status` | GET | Estado de OSRM y VROOM |
| `/api/optimize` | POST | Optimiza ruta (JSON con coordenadas) |
| `/api/optimize/csv` | POST | Optimiza ruta desde CSV (multipart) |
| `/api/route-segment` | POST | Segmento entre dos puntos (recálculo GPS) |
| `/api/validate-addresses` | POST | Valida direcciones sin optimizar |
| `/api/add-geocode-override` | POST | Añade override de geocodificación |

### 7.3.1 Tema de Colores Centralizado (`app_theme.dart`) — NUEVO v3.0

Este archivo centraliza **toda** la paleta de colores y la configuración de tema de la app.
Permite cambiar el aspecto visual modificando un único archivo.

```dart
abstract final class AppColors {
  // ── Primario — Azul Profundo / Medianoche ──
  static const Color primary = Color(0xFF003399);
  static const Color primaryLight = Color(0xFF1A56DB);
  static const Color primarySurface = Color(0xFFE8EEFB);

  // ── Éxito — Verde Esmeralda Sólido ──
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFF4CAF50);
  static const Color successSurface = Color(0xFFE8F5E9);

  // ── Advertencia — Ámbar Intenso ──
  static const Color warning = Color(0xFFE65100);
  static const Color warningLight = Color(0xFFF57C00);
  static const Color warningSurface = Color(0xFFFFF3E0);

  // ── Error — Rojo Carmesí ──
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFE53935);
  static const Color errorSurface = Color(0xFFFFEBEE);

  // ── Neutros (Modo Claro) ──
  static const Color scaffoldLight = Color(0xFFF5F5F5);   // Gris humo
  static const Color cardLight = Color(0xFFFFFFFF);        // Blanco puro
  static const Color textPrimary = Color(0xFF0D1B2A);     // Casi negro
  static const Color textSecondary = Color(0xFF475569);    // Gris oscuro
  static const Color textTertiary = Color(0xFF78909C);     // Gris medio

  // ── Neutros (Modo Oscuro) ──
  static const Color scaffoldDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1E1E1E);
  static const Color textPrimaryDark = Color(0xFFECEFF1);
  static const Color primaryDark = Color(0xFF448AFF);      // Azul eléctrico

  // ── Mapa ──
  static const Color polylineNav = Color(0xFF2979FF);      // Azul eléctrico
  static const Color polylineBorder = Color(0xB3FFFFFF);   // Blanco 70%
  static const Color markerCompleted = Color(0xFF9E9E9E);  // Gris piedra
  static const Color markerOrigin = Color(0xFFE65100);     // Ámbar intenso
  static const Color markerNext = Color(0xFF003399);       // Azul profundo

  // ── Estados de entrega ──
  static const Color delivered = success;
  static const Color absent = warning;
  static const Color incident = error;
}

// ThemeData para modo claro y oscuro
final ThemeData appLightTheme = ThemeData(...);
final ThemeData appDarkTheme = ThemeData(...);
```

**Modo Oscuro Automático:** La app usa `ThemeMode.system` — cambia automáticamente entre tema
claro y oscuro según la configuración del dispositivo. Los colores oscuros usan acentos de
azul eléctrico (`0xFF448AFF`) para mantener coherencia visual.

### 7.4 Modelos de Datos Flutter

#### `route_models.dart` — Espejo del backend

Estos modelos son la **versión Dart** de los modelos Pydantic del backend. Cada uno tiene un `factory fromJson()` para deserializar JSON.

| Clase Dart | Modelo Python equivalente | Campos clave |
|-----------|--------------------------|-------------|
| `Coordinate` | `Coordinate` | lat, lon |
| `StopInfo` | `StopInfo` | order, address, label, clientName, type, lat, lon, distanceMeters |
| `RouteSummary` | `RouteSummary` | totalStops, totalDistanceM, totalDistanceDisplay, computingTimeMs |
| `RouteStep` | `RouteStep` | text, distanceM, location |
| `OptimizeResponse` | `OptimizeResponse` | success, summary, stops, geometry, steps, routeIndex, totalRoutes |
| `MultiRouteResponse` | `MultiRouteResponse` | success, routes (lista), totalRoutes |

**Getters importantes en `StopInfo`:**
```dart
bool get isOrigin => type == 'origin';  // ¿Es el punto de partida?
String get displayName => clientName.isNotEmpty ? clientName : address;  // Identidad principal
```

#### `delivery_state.dart` — Estado de ejecución

Estos modelos se usan **solo en el cliente** para gestionar el reparto en curso:

**`StopStatus` (enum):**
```dart
enum StopStatus {
  pending,    // ⏳ Aún no visitada
  delivered,  // ✅ Entregado correctamente
  absent,     // 🚫 No estaba el destinatario
  incident,   // ⚠️ Incidencia (con nota de texto)
}
```

Tiene extensiones para obtener `label` ("Entregado") y `emoji` ("✅").

**`DeliveryStop`:**
Es como `StopInfo` pero con campos **mutables** para el estado del reparto:
- `status`: El estado actual (pending/delivered/absent/incident).
- `note`: Nota de texto para incidencias.
- `completedAt`: Fecha/hora en que se completó.
- Getters: `isOrigin`, `isCompleted`, `isPending`.
- Tiene `toMap()` y `fromMap()` para serializar a Hive.

**`DeliverySession`:**
Representa una sesión completa de reparto. Contiene:
- `id`: Identificador único (basado en timestamp).
- `createdAt`: Fecha/hora de creación.
- `stops`: Lista de `DeliveryStop`.
- `geometry`: GeoJSON de la ruta (para el mapa).
- `currentStopIndex`: Índice de la parada actual (empieza en 1 porque 0 es el origen).
- Datos del resumen (totalStops, distancias, etc.).

**Getters calculados de `DeliverySession`:**
```dart
DeliveryStop? get currentStop     // La parada que toca ahora
int get pendingCount              // Cuántas faltan
int get completedCount            // Cuántas se han hecho
int get deliveredCount            // Solo las entregadas OK
int get absentCount               // Las que no estaban
int get incidentCount             // Las con incidencia
bool get isFinished               // ¿Se completó todo?
double get progress               // 0.0 a 1.0 para la barra
```

**Método `advanceToNext()`:** Busca la siguiente parada con estado `pending` y actualiza `currentStopIndex`.

---

### 7.5 Servicios Flutter

#### `api_service.dart` — Cliente HTTP

Clase estática que comunica la app con el backend FastAPI.

| Método | Descripción | Retorna |
|--------|-------------|---------|
| `healthCheck()` | Ping al backend | `bool` (¿está vivo?) |
| `servicesStatus()` | Estado de OSRM y VROOM | `Map<String, dynamic>?` |
| `optimize(addresses, startAddress, numVehicles)` | Envía direcciones, recibe ruta optimizada | `OptimizeResponse` o `MultiRouteResponse` |
| `optimizeCsv(csvBytes, fileName)` | Sube CSV, recibe ruta | `OptimizeResponse` |

**Detección automática de multi-ruta:**
```dart
final json = jsonDecode(response.body);
if (json.containsKey('routes')) {
  return MultiRouteResponse.fromJson(json);   // 2 rutas
}
return OptimizeResponse.fromJson(json);        // 1 ruta
```

**Manejo de errores:** Si el backend devuelve un error (código ≠ 200), lanza `ApiException` con el mensaje del backend.

#### `csv_service.dart` — Parser de CSV

Parsea archivos CSV **en el cliente** (sin enviarlos al servidor). Esto permite mostrar una vista previa y seleccionar columnas antes de enviar.

| Método | Descripción |
|--------|-------------|
| `parse(bytes)` | Decodifica bytes (UTF-8 o Latin1), detecta delimitador (`,` o `;`), retorna `CsvData` |
| `detectAddressColumn(headers)` | Busca una cabecera que se parezca a "dirección", "address", "calle", etc. |
| `detectNameColumn(headers)` | Busca "nombre", "cliente", "destinatario", etc. |

**`CsvData`:** Tiene `headers` (lista de strings), `rows` (lista de listas), `rowCount`, `column(index)` y `preview(n)`.

#### `location_service.dart` — GPS

Obtiene la ubicación actual del dispositivo con manejo completo de permisos.

```dart
static Future<Position> getCurrentPosition() async {
  // 1. ¿Servicio de ubicación activo?
  // 2. ¿Tenemos permiso? Si no, solicitarlo.
  // 3. Obtener posición con LocationAccuracy.high y timeout 15s.
}
```

Lanza `LocationException` con mensaje descriptivo en español si algo falla.

#### `persistence_service.dart` — Persistencia Local (Hive)

Permite **guardar y recuperar** sesiones de reparto. Si el usuario cierra la app o el móvil se reinicia, puede retomar el reparto donde lo dejó.

| Método | Descripción |
|--------|-------------|
| `init()` | Inicializa Hive (llamar una vez en `main()`) |
| `saveSession(session)` | Guarda la sesión en la BD local |
| `loadSession()` | Carga la sesión guardada (si existe) |
| `hasActiveSession()` | ¿Hay una sesión en curso? |
| `clearSession()` | Borra la sesión (reparto completado) |
| `updateStopStatus(session, index, status, note)` | Actualiza una parada, avanza a la siguiente y persiste |
| `createSession(OptimizeResponse)` | Crea una nueva sesión desde la respuesta del backend |

**¿Qué es Hive?** Una base de datos NoSQL ultrarrápida para Flutter. Guarda datos como pares clave-valor en el almacenamiento local del dispositivo. No necesita configuración ni esquemas.

**Cómo funciona internamente:**
- Abre un "box" (caja) llamado `delivery_session`.
- Guarda/lee un único valor con la clave `active_session`.
- Serializa `DeliverySession` a `Map<String, dynamic>` (con `toMap()`/`fromMap()`).

---

### 7.6 Pantallas (Screens)

#### `import_screen.dart` — Pantalla Principal

Es la primera pantalla que ve el usuario. Permite:

1. **Continuar un reparto activo** (si existe): Muestra una tarjeta verde con "Continuar Ruta".
2. **Importar un CSV**: Toca para abrir el selector de archivos.
3. **Vista previa del CSV**: Muestra las primeras filas en una tabla.
4. **Mapear columnas**: Confirmar qué columna es "Dirección" y cuál "Nombre" (auto-detectado).
5. **Elegir punto de inicio**: Taller (predeterminado), GPS, o dirección manual.
6. **Elegir número de rutas**: 1 ruta (un repartidor) o 2 rutas (reparto compartido).
7. **Calcular ruta óptima**: Envía al backend y navega al resultado.

**Estado interno:**
```dart
CsvData? _csvData;           // Datos parseados del CSV
String _fileName;             // Nombre del archivo
int _addressColIndex;         // Índice de la columna de dirección
int _nameColIndex;            // Índice de la columna de nombre
OriginMode _originMode;       // Modo de origen (default/gps/manual)
String _manualAddress;        // Dirección manual (si aplica)
int _numVehicles;             // 1 o 2 rutas
bool _isLoading;              // ¿Calculando?
bool _serverOnline;           // ¿Backend disponible?
bool _hasActiveSession;       // ¿Hay reparto en curso?
```

**Indicador de servidor:** En la AppBar hay un punto verde/rojo que indica si el backend está activo. Se puede tocar para refrescar.

#### `result_screen.dart` — Resultados

Muestra la ruta optimizada tras el cálculo:

1. **Banner de estadísticas**: Paradas y distancia total.
2. **Tiempo de cálculo**: "⚡ Calculado en 342 ms".
3. **Mapa** (35% de la pantalla): Ruta dibujada con marcadores numerados.
4. **Lista de paradas**: Ordenada, con nombre del cliente como título principal y distancia. Tocar una centra el mapa.
5. **Botón LIFO** (AppBar): Abre la pantalla de orden de carga.
6. **"🚀 Iniciar Reparto"** (bottom bar): Crea la sesión y navega a `DeliveryScreen`.

> **Nota v2.2:** Se eliminó la pestaña "Instrucciones de navegación" y el `TabBar` se reemplazó
> por la lista de paradas directa, simplificando la interfaz.

#### `delivery_screen.dart` — Ejecución del Reparto

La pantalla donde el repartidor pasa la mayor parte del tiempo:

1. **AppBar verde** "En Reparto" con:
   - Botón reordenar (↕): Drag & Drop de paradas pendientes.
   - Badge de completadas con contador.
2. **Barra de progreso**: "4 de 7 entregas" con barra visual y emojis (✅ 🚫 ⚠️).
3. **Mapa dinámico** (zona principal):
   - **No** dibuja la ruta completa (sin polilínea azul global).
   - Dibuja solo el **segmento GPS → siguiente parada** (polilínea verde).
   - El marcador de la **siguiente parada** es significativamente más grande y verde.
   - Las paradas restantes son marcadores pequeños y discretos.
   - Las paradas completadas aparecen en gris con ✓.
   - GPS en tiempo real con marcador pulsante.
4. **Tarjeta "Siguiente Parada"** (parte inferior):
   - Número de orden, nombre del cliente, dirección.
   - Botón de navegación externa (abre Google Maps).
   - Botones de acción:
     - **✅ Entregado** (grande, verde) — un solo toque.
     - **🚫 No estaba** (borde naranja) — un solo toque.
     - **⚠️ Incidencia** (icono rojo) — abre diálogo para escribir nota.

**Recálculo automático:** Al marcar una parada (Entregado / No estaba / Incidencia), el segmento
se borra y se solicita automáticamente al backend el nuevo tramo desde la posición GPS actual
hasta la siguiente parada pendiente. Lo mismo ocurre al reordenar paradas.

**Drag & Drop (reordenar):** Al pulsar ↕ se abre un bottom sheet con las paradas pendientes. Se mantiene pulsado y se arrastra para cambiar el orden. Al pulsar "Aplicar", se reorganizan las paradas y se persiste en Hive.

**Navegación externa:** Al pulsar el icono de brújula, se abre Google Maps con las coordenadas del destino. Intenta primero el intent `google.navigation:` (navegación directa) y luego la URL web como fallback.

**Finalización:** Cuando todas las paradas están completadas:
- Se muestra un diálogo con resumen (entregados, ausentes, incidencias, duración, distancia).
- Botón "🧹 Cerrar Sesión y Limpiar" que borra la sesión de Hive y vuelve al inicio.
- También aparece un banner verde en la parte inferior con las mismas opciones.

**Protección contra salida accidental:** `PopScope` captura el botón "Atrás" y muestra un diálogo de confirmación. El progreso se guarda automáticamente.

#### `loading_order_screen.dart` — Orden de Carga (LIFO)

Pantalla de ayuda para **cargar la furgoneta**. Usa lógica LIFO (Last In, First Out):
- El paquete de la **última parada** va al **fondo** de la furgoneta.
- El paquete de la **primera parada** va **junto a la puerta**.

Muestra las paradas en orden inverso con etiquetas visuales "AL FONDO" y "JUNTO A LA PUERTA".

#### `route_picker_screen.dart` — Elegir Ruta (Reparto Compartido)

Cuando se calculan 2 rutas, esta pantalla muestra:
- Un encabezado "Reparto Compartido" con pregunta "¿Quién eres?".
- Dos opciones seleccionables con nombres de repartidor:
  - **Evaristo** (azul 🔵)
  - **Juanma** (morado 🟣)
- Cada opción muestra: paradas y distancia en texto compacto.
- Selección visual con radio-button y animación.
- Botón "Continuar como [nombre]" que confirma y navega a `ResultScreen`.

> **Nota v2.2:** Se rediseñó de tarjetas con tap directo a selector con confirmación,
> centrado en el nombre del repartidor. Más claro para Juanma.

---

### 7.7 Widgets Reutilizables

| Widget | Archivo | Descripción |
|--------|---------|-------------|
| `RouteMap` | `route_map.dart` | Mapa interactivo con 2 modos: preview (ruta completa) y delivery (segmento dinámico GPS → siguiente parada) |
| `StopsList` | `stops_list.dart` | Lista de paradas con nombre de cliente, distancia y highlight al tocar |
| `ColumnMapper` | `column_mapper.dart` | Selectores dropdown para mapear columnas del CSV |
| `CsvPreviewTable` | `csv_preview_table.dart` | Tabla scrollable con vista previa del CSV |
| `OriginSelector` | `origin_selector.dart` | 3 opciones: Taller/GPS/Manual para el punto de inicio |
| `StatsBanner` | `stats_banner.dart` | Banner horizontal con 3 estadísticas (paradas/distancia/tiempo) |

#### `route_map.dart` — Detalles técnicos

Este es el widget más complejo del proyecto. Soporta **dos modos de operación**:

**Modo Preview** (por defecto — `ResultScreen`):
- Dibuja la polilínea azul de la ruta completa.
- Marcadores de tamaño normal para todas las paradas.

**Modo Delivery** (`deliveryMode: true` — `DeliveryScreen`):
- **No** dibuja la ruta completa.
- Solo dibuja el **segmento verde** GPS → siguiente parada (`segmentGeometry`).
- El marcador de la **siguiente parada** (`nextStopIndex`) es significativamente más grande (50px) y verde.
- Las paradas restantes son marcadores pequeños (24px) y discretos (gris claro).
- Las paradas completadas aparecen en gris con ✓.
- Al marcar una parada, `DeliveryScreen` borra el segmento anterior y solicita uno nuevo al backend.

**Capas del mapa (de abajo a arriba):**
1. **TileLayer**: Tiles de OpenStreetMap (`tile.openstreetmap.org`).
2. **PolylineLayer**: Sombra (8px) + línea principal (5px). Azul en preview, verde en delivery.
3. **MarkerLayer (paradas)**: Marcadores circulares numerados.
4. **MarkerLayer (GPS)**: Punto azul con pulso animado.

**Tipos de marcadores:**
- 🏠 **Origen**: Círculo amarillo con icono home.
- 🔢 **Parada normal**: Círculo azul con número.
- 🟢 **Siguiente parada** (delivery mode): Círculo verde grande (50px) con número.
- 🔘 **Parada restante** (delivery mode): Círculo gris pequeño (24px).
- ✓ **Parada completada**: Círculo gris con check.
- 🔵 **Parada resaltada**: Más grande, con sombra.

**GPS en tiempo real:**
- Usa `Geolocator.getPositionStream()` con `LocationAccuracy.medium` y `distanceFilter: 15m` (optimizado para batería de 8-10 horas).
- Marcador con animación de pulso (ciclo de 1.5 segundos).
- Modo "seguir GPS": el mapa se mueve automáticamente con la posición.
- La posición GPS se expone vía `currentPosition` getter para que `DeliveryScreen` la use como origen del segmento.

**Controles flotantes (esquina inferior derecha):**
- 🗺️ "Ver toda la ruta": Ajusta zoom para mostrar la ruta completa.
- 📍 "Mi ubicación": Centra en la posición GPS actual.

**Métodos públicos** (accesibles vía `GlobalKey<RouteMapState>`):**
```dart
void flyToStop(int index)       // Centra el mapa en una parada
void fitRoute()                 // Zoom para ver toda la ruta
void centerOnGps()              // Centra en la posición GPS
LatLng? get currentPosition     // Posición GPS actual
```

---

### 7.8 Configuración Android

**Archivo: `android/app/src/main/AndroidManifest.xml`**

**Permisos declarados:**
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

**Configuración especial:**
- `android:usesCleartextTraffic="true"`: Necesario para conexiones HTTP sin HTTPS (el backend local usa HTTP).
- `<queries>` para `url_launcher`: Declara que la app puede abrir URLs con esquema `google.navigation:` y `https:` (necesario desde Android 11+).

---

## 8. Flujo de Datos Completo

### Escenario: Repartidor importa CSV y hace reparto

```
                          USUARIO
                            │
                   1. Abre la app
                            │
                            ▼
                    ┌───────────────┐
                    │ ImportScreen   │ ← healthCheck() → Backend OK? ✅
                    │               │
                    │ 2. Selecciona │
                    │    archivo CSV │
                    └───────┬───────┘
                            │
                   3. CsvService.parse()
                      (parsea en local)
                            │
                            ▼
                   4. Muestra preview,
                      auto-detecta columnas,
                      elige origen y nº rutas
                            │
                   5. Pulsa "Calcular"
                            │
                            ▼
                    ┌───────────────┐     POST /api/optimize
                    │ ApiService    │─────────────────────────────▶ ┌──────────┐
                    │ .optimize()   │                                │ FastAPI  │
                    └───────┬───────┘                                │          │
                            │                                       │ 6. Geocod│
                            │                                       │ 7. VROOM │
                            │                                       │ 8. OSRM  │
                            │         JSON Response                 │          │
                            │◀──────────────────────────────────────│          │
                            │                                       └──────────┘
                            ▼
                   ┌─────────────────┐
                   │ 1 ruta?         │──▶ ResultScreen
                   │ 2 rutas?        │──▶ RoutePickerScreen → ResultScreen
                   └─────────────────┘
                            │
                   9. ResultScreen:
                      mapa + lista de paradas
                            │
                  10. Pulsa "Iniciar Reparto"
                            │
                      PersistenceService
                      .createSession()
                      .saveSession()
                            │
                            ▼
                    ┌───────────────┐
                    │DeliveryScreen  │
                    │                │
                    │ 11. Por cada   │
                    │     parada:    │
                    │  ✅ Entregado  │──▶ updateStopStatus() + saveSession()
                    │  🚫 No estaba │──▶ updateStopStatus() + saveSession()
                    │  ⚠️ Incidencia│──▶ updateStopStatus() + saveSession()
                    │                │
                    │ 12. Cuando     │
                    │     termina:   │
                    │  🧹 Limpiar   │──▶ clearSession() + popUntil(first)
                    └───────────────┘
```

### Escenario: App se cierra y se reabre

```
1. App se cierra (swipe, batería, etc.)
   → La sesión YA estaba guardada en Hive (se guarda en cada acción)

2. App se reabre
   → main() → PersistenceService.init()
   → ImportScreen.initState() → _checkActiveSession()
   → Hive tiene sesión → _hasActiveSession = true

3. Usuario ve la tarjeta verde "Continuar Ruta"
   → Toca → PersistenceService.loadSession()
   → DeliverySession restaurada con todos los estados
   → Navega a DeliveryScreen con la sesión
   → currentStopIndex apunta a la siguiente pendiente
```

---

## 9. API — Contratos y Endpoints

### Tabla de Endpoints

| Método | Ruta | Descripción | Request | Response |
|--------|------|-------------|---------|----------|
| `GET` | `/health` | Health check | — | `{"status": "ok", "version": "2.1.0"}` |
| `GET` | `/api/services/status` | Estado OSRM+VROOM | — | `{"osrm": {"status": "ok"}, ...}` |
| `POST` | `/api/optimize` | Optimizar ruta desde direcciones | `OptimizeRequest` (JSON) | `OptimizeResponse` / `MultiRouteResponse` |
| `POST` | `/api/optimize/csv` | Optimizar ruta desde CSV | `file` (multipart) | `OptimizeResponse` / `MultiRouteResponse` |
| `POST` | `/api/validate-addresses` | Validar + geocodificar direcciones | `{addresses[], client_names[]}` | `{results[], street_groups[], unique_streets}` |
| `POST` | `/api/normalize-addresses` | Normalizar + agrupar (sin geocodificar) | `{addresses[], client_names[]}` | `{normalized[], groups[]}` |
| `POST` | `/api/add-geocode-override` | Override manual de coordenadas | `{address, lat, lon}` | `{success}` |
| `GET` | `/api/route-segment` | Geometría de tramo (OSRM) | query params | `{geometry, distance_m}` |
| `POST` | `/api/streets/resolve_batch` | **Bloque 2** — Resolución batch de calles | `{groups: StreetGroupInput[]}` | `ResolveBatchResponse` |
| `POST` | `/api/streets/confirm_alias` | **Bloque 2** — Confirmar alias de calle | `ConfirmAliasRequest` | `{success, message}` |
| `POST` | `/api/streets/create_virtual` | **Bloque 2** — Crear calle virtual | `CreateVirtualRequest` | `{success, message, osrm_snap_*}` |
| `POST` | `/api/streets/confirm_pin` | **Bloque 2** — Confirmar pin manual | `ConfirmPinRequest` | `{success, message, alias_created}` |
| `GET` | `/api/streets/stats` | **Bloque 2** — Estadísticas BD calles | — | `{alias, street_virtual, geocode_cache}` |

### Ejemplo completo de /api/optimize

**Request:**
```json
POST /api/optimize
Content-Type: application/json

{
  "addresses": [
    "Calle Gaitán 1, Posadas, Córdoba, España",
    "Calle Santiago 2, Posadas, Córdoba, España",
    "Calle Molinos 1, Posadas, Córdoba, España"
  ],
  "start_address": null,
  "num_vehicles": 1
}
```

**Response (1 vehículo):**
```json
{
  "success": true,
  "summary": {
    "total_stops": 3,
    "total_distance_m": 2450.0,
    "total_distance_display": "2.5 km",
    "total_duration_s": 420.0,
    "total_duration_display": "7 min",
    "computing_time_ms": 342.1
  },
  "stops": [
    {
      "order": 0,
      "address": "Calle Callejon de Jesús 1, Posadas, Córdoba, España",
      "label": "🏠 Origen",
      "type": "origin",
      "lat": 37.8021,
      "lon": -5.1043,
      "eta_seconds": 0,
      "eta_display": "Inicio",
      "distance_meters": 0
    },
    {
      "order": 1,
      "address": "Calle Molinos 1, Posadas, Córdoba, España",
      "label": "📍 Parada 1",
      "type": "stop",
      "lat": 37.8018,
      "lon": -5.1051,
      "eta_seconds": 120,
      "eta_display": "2 min",
      "distance_meters": 450
    }
  ],
  "geometry": {
    "type": "LineString",
    "coordinates": [[-5.1043, 37.8021], [-5.1051, 37.8018], ...]
  },
  "steps": [
    {
      "text": "Salir por Calle Callejón de Jesús",
      "distance_m": 120,
      "duration_s": 15,
      "location": {"lat": 37.8021, "lon": -5.1043}
    },
    {
      "text": "Girar a la derecha por Calle Molinos",
      "distance_m": 80,
      "duration_s": 10,
      "location": {"lat": 37.8019, "lon": -5.1047}
    }
  ],
  "route_index": 0,
  "total_routes": 1
}
```

**Response (2 vehículos):**
```json
{
  "success": true,
  "routes": [
    { /* OptimizeResponse completo para Ruta A */ },
    { /* OptimizeResponse completo para Ruta B */ }
  ],
  "total_routes": 2
}
```

### Códigos de Error

| Código | Cuándo ocurre | Ejemplo de respuesta |
|--------|--------------|---------------------|
| 400 | Datos de entrada inválidos | `{"detail": "La lista de direcciones está vacía"}` |
| 400 | Geocodificación fallida | `{"detail": "No se pudieron geocodificar: Calle Inexistente 999"}` |
| 503 | VROOM o OSRM no disponibles | `{"detail": "VROOM no pudo calcular la ruta. ¿Están corriendo los servicios Docker?"}` |

---

## 10. Guía de Instalación y Arranque

### Requisitos Previos

- **Docker** y **Docker Compose** instalados.
- **Python 3.10+** instalado.
- **Flutter 3.x** instalado (con soporte Android).
- **Android Studio** con un emulador configurado (o dispositivo físico).

### Paso 1: Arrancar Servicios Docker

```bash
cd /home/mariano/Desktop/app_repartir

# Arrancar OSRM y VROOM en background
docker compose up -d

# Verificar que están corriendo
docker ps
# Esperado:
# osrm-posadas → 0.0.0.0:5000->5000/tcp
# vroom-posadas → network_mode: host (puerto 3000)

# Verificar OSRM
curl "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false"
# Debe devolver JSON con "code": "Ok"

# Verificar VROOM
curl http://localhost:3000/health
# Debe devolver 200 OK
```

### Paso 2: Arrancar Backend FastAPI

```bash
cd /home/mariano/Desktop/app_repartir

# Activar entorno virtual
source venv/bin/activate

# Instalar dependencias (primera vez)
pip install -r requirements.txt

# Arrancar servidor
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Verificar
# Abrir http://localhost:8000/docs en el navegador → Swagger UI
# Abrir http://localhost:8000/health → {"status": "ok"}
```

### Paso 3: Arrancar App Flutter

```bash
cd /home/mariano/Desktop/app_repartir/flutter_app

# Obtener dependencias (primera vez)
flutter pub get

# Verificar configuración
flutter doctor

# Arrancar emulador Android (si no está corriendo)
# O conectar dispositivo físico con USB debugging

# Ejecutar la app
flutter run

# Para compilar APK de release:
flutter build apk --release
```

### Paso 4: Verificar Conectividad

1. La app muestra un indicador verde "Online" en la AppBar → el backend responde.
2. Si muestra rojo "Offline":
   - **Emulador**: Verificar que la URL es `http://10.0.2.2:8000`.
   - **Dispositivo físico**: Cambiar `api_config.dart` a la IP del PC (ej: `http://192.168.1.50:8000`).
   - **Backend**: ¿Está corriendo `uvicorn`?

---

## 11. Guía de Desarrollo y Modificaciones

### Cambiar la dirección de inicio (taller)

**Archivo:** `app/core/config.py`
```python
START_ADDRESS = "Tu nueva dirección aquí, Ciudad, Provincia, País"
```

### Cambiar la zona geográfica (de Posadas a otra ciudad)

1. **Descargar nuevos datos OSM** para la región:
   - Ir a https://download.geofabrik.de/ y descargar el `.osm.pbf` correspondiente.
   - Procesar con OSRM:
     ```bash
     docker run -v ./osrm:/data osrm/osrm-backend osrm-extract -p /opt/car.lua /data/tu-region.osm.pbf
     docker run -v ./osrm:/data osrm/osrm-backend osrm-partition /data/tu-region.osrm
     docker run -v ./osrm:/data osrm/osrm-backend osrm-customize /data/tu-region.osrm
     ```

2. **Actualizar `docker-compose.yml`:**
   ```yaml
   command: osrm-routed --algorithm mld /data/tu-region.osrm
   ```

3. **Actualizar `app/core/config.py`:**
   ```python
   START_ADDRESS = "Nueva dirección de inicio"
   POSADAS_CENTER = (lat, lon)          # Centro de la nueva ciudad
   POSADAS_VIEWBOX = "lon1,lat1,lon2,lat2"  # Bounding box
   ```

### Añadir un nuevo campo a las paradas

1. **Backend** → `app/models/__init__.py`: Añadir campo a `StopInfo`.
2. **Backend** → `app/routers/optimize.py`: Rellenar el campo al construir `StopInfo`.
3. **Flutter** → `lib/models/route_models.dart`: Añadir campo a `StopInfo` y en `fromJson()`.
4. **Flutter** → Si se necesita persistir → `lib/models/delivery_state.dart`: Añadir en `DeliveryStop`, `toMap()` y `fromMap()`.

### Añadir un nuevo endpoint al backend

1. Crear el handler en `app/routers/optimize.py` (o crear un nuevo router).
2. Si es un nuevo router, registrarlo en `app/main.py`:
   ```python
   app.include_router(nuevo_router.router, prefix="/api")
   ```
3. Añadir modelos de request/response en `app/models/__init__.py`.
4. Actualizar `flutter_app/lib/config/api_config.dart` con el nuevo endpoint.
5. Añadir método en `flutter_app/lib/services/api_service.dart`.

### Añadir una nueva pantalla Flutter

1. Crear archivo en `lib/screens/nueva_screen.dart`.
2. Importar los modelos que necesite de `models/`.
3. Navegar desde otra pantalla:
   ```dart
   Navigator.of(context).push(
     MaterialPageRoute(builder: (_) => NuevaScreen(data: data)),
   );
   ```

### Paleta de colores del proyecto

| Color | Hex | Uso |
|-------|-----|-----|
| Azul principal | `#2563EB` | Botones, marcadores, indicadores |
| Verde éxito | `#10B981` | Entregado, AppBar reparto, progreso |
| Amarillo/Ámbar | `#F59E0B` | Origen, "No estaba", advertencias |
| Rojo error | `#EF4444` | Incidencias, errores |
| Gris texto | `#64748B` | Texto secundario |
| Gris claro fondo | `#F1F5F9` | Fondo de pantallas |
| Blanco | `#FFFFFF` | Fondo de tarjetas |
| Gris completado | `#94A3B8` | Paradas completadas en mapa |

### Ejecutar análisis estático

```bash
# Flutter (errores de código)
cd flutter_app && flutter analyze

# Python (verificar compilación)
cd app_repartir
source venv/bin/activate
python -m py_compile app/main.py
python -m py_compile app/routers/optimize.py
python -m py_compile app/services/routing.py
python -m py_compile app/services/geocoding.py
python -m py_compile app/models/__init__.py
```

---

## 12. Problemas Conocidos y Soluciones

### El backend no conecta con OSRM/VROOM

**Síntoma:** Error 503 "VROOM no pudo calcular la ruta".
**Solución:**
```bash
docker compose up -d
docker ps  # Verificar que ambos están corriendo
```

### La app Flutter no conecta con el backend

**Síntoma:** Indicador rojo "Offline" en la AppBar.
**Causa más común:** URL incorrecta en `api_config.dart`.
- **Emulador Android:** Debe ser `http://10.0.2.2:8000`
- **Dispositivo físico:** Debe ser la IP local del PC (`http://192.168.x.x:8000`)
- **iOS Simulator:** Puede ser `http://localhost:8000`

### Error "cleartext traffic not permitted"

**Síntoma:** La app no puede hacer peticiones HTTP.
**Solución:** Ya resuelto. Verificar que `AndroidManifest.xml` tiene:
```xml
android:usesCleartextTraffic="true"
```

### Geocodificación falla para algunas direcciones

**Síntoma:** "No se pudieron geocodificar las siguientes direcciones: ..."
**Causas:**
- La dirección es ambigua o no existe en OpenStreetMap.
- Nominatim está sobrecargado (servicio público gratuito).
**Solución:** Asegurarse de que las direcciones incluyen ", Posadas, Córdoba".

### GPS no funciona en el emulador

**Síntoma:** No aparece el punto azul en el mapa.
**Solución:** En el emulador Android, ir a Extended Controls (tres puntos) → Location → Enviar una ubicación manual.

### La app se cierra y se pierden datos

**Esto NO debería ocurrir.** Los datos se guardan en Hive automáticamente en cada acción. Si ocurre:
1. Verificar que `PersistenceService.init()` se llama en `main()`.
2. Verificar que `updateStopStatus()` se llama correctamente en `delivery_screen.dart`.

### VROOM v1.14.0 no se encuentra

**Solución:** La imagen correcta es de GitHub Container Registry:
```bash
docker pull ghcr.io/vroom-project/vroom-docker:v1.14.0
```
No está en Docker Hub estándar.

---

## 13. Glosario Técnico

| Término | Significado |
|---------|------------|
| **API REST** | Interfaz de programación que usa HTTP (GET, POST) para comunicar sistemas. |
| **ASGI** | Asynchronous Server Gateway Interface. Protocolo que permite a Python manejar peticiones web asíncronas. Uvicorn es un servidor ASGI. |
| **CSV** | Comma-Separated Values. Archivo de texto donde cada línea es una fila y los valores se separan por comas (o punto y coma). |
| **Docker** | Tecnología que permite ejecutar aplicaciones en "contenedores" aislados, como mini máquinas virtuales ligeras. |
| **Docker Compose** | Herramienta para definir y ejecutar múltiples contenedores Docker con un solo archivo de configuración (`docker-compose.yml`). |
| **Endpoint** | Una URL específica de una API que acepta peticiones. Ej: `POST /api/optimize`. |
| **FastAPI** | Framework web para Python que genera APIs REST automáticamente documentadas. |
| **GeoJSON** | Formato estándar para representar datos geográficos en JSON. Se usa para la polilínea de la ruta. |
| **Geocodificación** | Proceso de convertir una dirección de texto ("Calle X 1") en coordenadas GPS (latitud, longitud). |
| **GPS** | Global Positioning System. Sistema satelital que permite conocer la posición geográfica de un dispositivo. |
| **Hive** | Base de datos local NoSQL para Flutter. Almacena datos en el dispositivo sin necesidad de conexión a internet. |
| **JSON** | JavaScript Object Notation. Formato de texto para intercambiar datos estructurados. |
| **LIFO** | Last In, First Out. Principio de pila: lo último que se pone es lo primero que se saca. Se usa para cargar la furgoneta. |
| **Marker** | Punto visual en el mapa que indica una ubicación (parada, origen, GPS). |
| **MLD** | Multi-Level Dijkstra. Algoritmo de OSRM para encontrar la ruta más corta entre dos puntos en un grafo de carreteras. |
| **Nominatim** | Servicio gratuito de geocodificación de OpenStreetMap. Convierte direcciones en coordenadas y viceversa. |
| **NoSQL** | Base de datos que no usa tablas SQL. Hive almacena pares clave-valor. |
| **Open Trip** | Tipo de ruta donde el vehículo no vuelve al punto de partida (a diferencia de un "round trip"). |
| **OpenStreetMap (OSM)** | Mapa del mundo creado por voluntarios. Gratuito y libre. Se usa para tiles del mapa y datos de carreteras. |
| **OSRM** | Open Source Routing Machine. Motor de cálculo de rutas que usa datos de OpenStreetMap. |
| **Polyline** | Línea formada por múltiples segmentos que representa la ruta en el mapa. |
| **Pydantic** | Biblioteca Python para validación de datos. Define modelos con tipos y restricciones, y valida automáticamente. |
| **Rate Limiting** | Restricción en el número de peticiones por unidad de tiempo. Nominatim permite ~1 petición/segundo. |
| **Scaffold** | Widget principal de Flutter que proporciona la estructura básica de una pantalla (AppBar, body, bottom bar). |
| **StatefulWidget** | Widget de Flutter que puede cambiar su estado interno (datos) y reconstruirse. |
| **StatelessWidget** | Widget de Flutter que no cambia una vez construido. |
| **Tiles** | Imágenes cuadradas que forman el mapa. Se descargan según la zona y el zoom. |
| **TSP** | Travelling Salesman Problem (Problema del Viajante). Problema de optimización: visitar N puntos en el orden más eficiente. |
| **Uvicorn** | Servidor ASGI ultrarrápido para Python. Ejecuta aplicaciones FastAPI. |
| **Viewbox** | Rectángulo geográfico que define una zona de interés para la geocodificación. |
| **VROOM** | Vehicle Routing Open-source Optimization Machine. Resuelve problemas de optimización de rutas (TSP y VRP). |
| **VRP** | Vehicle Routing Problem. Extensión del TSP con múltiples vehículos. |
| **Widget** | Bloque de construcción de la UI en Flutter. Todo es un widget: botones, textos, layouts, pantallas. |

---

## Anexo A: Resumen de Comandos Útiles

```bash
# ── Docker ──
docker compose up -d              # Arrancar OSRM + VROOM
docker compose down               # Parar servicios
docker compose logs -f            # Ver logs en tiempo real
docker ps                         # Listar contenedores activos

# ── Backend ──
cd /home/mariano/Desktop/app_repartir
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
# Swagger UI: http://localhost:8000/docs

# ── Flutter ──
cd /home/mariano/Desktop/app_repartir/flutter_app
flutter pub get                   # Instalar dependencias
flutter analyze                   # Verificar errores
flutter run                       # Ejecutar en emulador/dispositivo
flutter build apk --release       # Compilar APK de release
flutter clean                     # Limpiar build (si hay problemas)

# ── Verificar servicios ──
curl http://localhost:8000/health
curl http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false
curl http://localhost:3000/health
```

---

## Anexo B: Puertos del Sistema

| Puerto | Servicio | Protocolo | Notas |
|--------|----------|-----------|-------|
| 3000 | VROOM | HTTP | Optimizador de rutas (network_mode: host) |
| 5000 | OSRM | HTTP | Motor de rutas |
| 8000 | FastAPI (Uvicorn) | HTTP | Backend principal |
| N/A | Nominatim | HTTPS | Servicio externo (nominatim.openstreetmap.org) |
| N/A | OSM Tiles | HTTPS | Servicio externo (tile.openstreetmap.org) |

---

## 14. Generación de APK y Despliegue en Móvil

### 14.1 Requisitos Previos

- **Flutter 3.x** instalado (verificar con `flutter doctor`).
- **Android SDK** instalado (mínimo SDK 21, target SDK 36).
  ```bash
  # Instalar Android SDK command-line tools (si no están)
  # Descargar desde https://developer.android.com/studio#command-tools
  # Descomprimir en ~/Android/Sdk/cmdline-tools/latest/
  
  # Aceptar licencias
  flutter doctor --android-licenses
  ```
- **Java 17** instalado:
  ```bash
  sudo apt install openjdk-17-jdk
  ```

### 14.2 Configurar la IP del Backend

**⚠️ CRÍTICO:** El móvil necesita conectarse al PC donde corre el backend. Ambos deben estar en la **misma red WiFi**.

1. Obtener la IP local del PC:
   ```bash
   hostname -I | awk '{print $1}'
   # Ejemplo: 192.168.1.108
   ```

2. Editar `flutter_app/lib/config/api_config.dart`:
   ```dart
   static const String baseUrl = 'http://TU_IP_LOCAL:8000';
   // Ejemplo: 'http://192.168.1.108:8000'
   ```

> **Nota:** Si la IP de tu PC cambia (por ejemplo, al reiniciar el router), debes actualizar este archivo y regenerar la APK.

### 14.3 Configuración de Red Android (Network Security Config)

Android bloquea por defecto el tráfico HTTP no cifrado (cleartext). El proyecto incluye la configuración necesaria para permitirlo:

**Archivo:** `android/app/src/main/res/xml/network_security_config.xml`
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">192.168.1.108</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>
        <domain includeSubdomains="true">localhost</domain>
    </domain-config>
</network-security-config>
```

> **Si cambias de IP**, actualiza también el `<domain>` en este archivo.

**Referenciado en:** `android/app/src/main/AndroidManifest.xml`
```xml
<application
    android:usesCleartextTraffic="true"
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

### 14.4 Configuración de Gradle (Memoria)

El build de Android con Gradle consume mucha RAM. En equipos con ≤ 8 GB de RAM, es **imprescindible** limitar la memoria de Gradle para evitar que el sistema se congele.

**Archivo:** `android/gradle.properties`
```properties
# IMPORTANTE: Ajustar -Xmx según tu RAM disponible
# 8 GB RAM → usar -Xmx2G
# 16 GB RAM → usar -Xmx4G
org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
org.gradle.daemon=false
org.gradle.parallel=false
```

> **⚠️ NUNCA** poner `-Xmx` mayor que tu RAM total. Si tienes 8 GB, máximo `-Xmx2G` o `-Xmx3G`.

### 14.5 Generar la APK

```bash
cd /home/mariano/Desktop/app_repartir/flutter_app

# 1. Obtener dependencias
flutter pub get

# 2. Generar APK release (tarda 2-8 minutos la primera vez)
flutter build apk --release

# 3. La APK se genera en:
#    build/app/outputs/flutter-apk/app-release.apk (~50 MB)

# 4. (Opcional) Copiar al escritorio para fácil acceso
cp build/app/outputs/flutter-apk/app-release.apk ~/Desktop/RepartirApp.apk
```

### 14.6 Instalar en el Móvil

1. **Transferir la APK** al móvil:
   - Cable USB → copiar a la carpeta `Download`
   - Enviarte la APK por Telegram/WhatsApp a ti mismo
   - Subir a Google Drive y descargar desde el móvil
   - Bluetooth

2. **Habilitar instalación de fuentes desconocidas:**
   - Ajustes → Seguridad → "Instalar apps de fuentes desconocidas"
   - (En Android 8+: se pide permiso por app al abrir la APK)

3. **Abrir la APK** desde el explorador de archivos del móvil → **Instalar**

### 14.7 Probar la App

#### Pre-requisitos (en el PC):
```bash
# 1. Docker corriendo con OSRM y VROOM
docker compose up -d

# 2. Backend FastAPI corriendo
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 3. Verificar
curl http://localhost:8000/health
# → {"status":"ok","version":"2.0.0"}
```

#### En el móvil:
1. **Conectar a la misma WiFi** que el PC
2. **Abrir Repartir App**
3. Verificar el indicador **🟢 Online** en la barra superior
   - Si muestra **🔴 Offline**: ver sección [Troubleshooting](#148-troubleshooting-conexión-móvil)
4. **Importar CSV:** Tocar el botón "Toca para seleccionar CSV"
   - Transferir el archivo `paradas_test_grande.csv` al móvil previamente
5. **Mapear columnas:** Seleccionar `direccion` como columna de dirección
6. **Seleccionar origen:** Dirección manual, GPS, o dirección por defecto
7. **Elegir número de rutas:** 1 ruta o 2 rutas
8. **Calcular:** Tocar el botón azul "Calcular Ruta Óptima"
9. **Ver resultados:** Mapa con marcadores numerados, lista de paradas con ETA
10. **Iniciar reparto:** Botón "Iniciar Reparto" → pantalla de ejecución
11. **Marcar paradas:** Entregado ✅ / No estaba ⚠️ / Incidencia ❌
12. **Navegar:** Botón de navegación abre Google Maps con la dirección
13. **Finalizar:** Al completar todas las paradas, ver resumen con distancia y duración

### 14.8 Troubleshooting: Conexión Móvil

| Problema | Causa | Solución |
|----------|-------|----------|
| App muestra "Offline" | Móvil no alcanza el backend | Verificar misma WiFi |
| "Este sitio no puede proporcionar una conexión segura" | Android bloquea HTTP | Verificar `network_security_config.xml` y regenerar APK |
| Timeout al calcular ruta | Red lenta o muchas paradas | Aumentar `timeout` en `api_config.dart` |
| IP cambió tras reinicio | DHCP asignó nueva IP | Actualizar `api_config.dart` + `network_security_config.xml` y regenerar APK |
| "Offline" pero la IP es correcta | Router con AP Isolation | Desactivar "AP Isolation" / "Client Isolation" en el router |

**Prueba rápida desde el móvil:** Abrir el navegador y visitar `http://TU_IP:8000/health`. Si muestra `{"status":"ok"}`, la conexión funciona.

### 14.9 CSV de Prueba

El proyecto incluye dos archivos CSV de prueba:

| Archivo | Paradas | Columnas | Uso |
|---------|---------|----------|-----|
| `paradas.csv` | 7 | `id`, `address` | Prueba rápida |
| `paradas_test_grande.csv` | 40 | `id`, `nombre_cliente`, `direccion`, `telefono`, `notas` | Prueba completa |

Todas las direcciones son calles reales de Posadas, Córdoba, España.

---

## 15. Changelog

### v2.2.0 — Rediseño de Interfaz (Tarea 6.2)

**Cambios UI:**

1. **Eliminada pestaña "Instrucciones de Navegación"** en `result_screen.dart`:
   - Se eliminó el `TabBar` / `TabBarView` completo.
   - La lista de paradas (`StopsList`) se muestra directamente sin tabs.
   - Se eliminaron `_buildStepsList()` y la clase `_StepTile`.

2. **Nombre del cliente como título principal** en todas las pantallas:
   - `stops_list.dart`: El título del tile es `clientName` (no el label con emoji).
   - `delivery_screen.dart` (`_NextStopCard`): Muestra `clientName` en lugar de `label`.
   - `delivery_screen.dart` (historial + drag-reorder): Usa `clientName` como texto principal.
   - `loading_order_screen.dart`: Muestra `clientName` como título del paquete.
   - Si `clientName` está vacío, se usa `label` como fallback.

3. **Rediseño de `RoutePickerScreen`**:
   - Convertida de `StatelessWidget` a `StatefulWidget` con selección explícita.
   - AppBar ahora dice "¿Quién eres?" en vez de "Elegir Ruta".
   - Selector tipo radio: se toca el nombre del repartidor para seleccionarlo.
   - Animación visual con borde, color de fondo y check al seleccionar.
   - Botón de confirmación "Continuar como [nombre]" (antes era tap directo sin confirmación).
   - Los nombres de los repartidores (Evaristo/Juanma) se muestran como título grande.

---

### v2.3.0 — Mapa Dinámico "Siguiente Parada" (Tarea 6.3)

**Backend:**
- Nuevo endpoint `GET /api/route-segment` — devuelve geometría GeoJSON del camino entre dos puntos
  vía OSRM. Parámetros: `origin_lat`, `origin_lon`, `dest_lat`, `dest_lon`.

**Flutter — `route_map.dart`:**
- Nuevo modo **delivery** (`deliveryMode: true`):
  - Elimina la polilínea azul de la ruta completa.
  - Solo dibuja el **segmento verde** GPS → siguiente parada.
  - Marcador de la siguiente parada: **50px** verde vibrante con sombra grande.
  - Paradas restantes: **24px** gris claro (discretas para no distraer).
  - Getter `currentPosition` expuesto para uso externo.
- Nuevos parámetros: `deliveryMode`, `segmentGeometry`, `nextStopIndex`.

**Flutter — `delivery_screen.dart`:**
- Al iniciar reparto: solicita segmento GPS → primera parada vía `/api/route-segment`.
- Al marcar parada (Entregado / No estaba / Incidencia): borra segmento anterior y solicita
  automáticamente el nuevo tramo GPS → siguiente parada pendiente.
- Al reordenar paradas: recalcula segmento hacia la nueva siguiente parada.
- Fallback si no hay GPS: usa la parada anterior como punto de origen.

**Flutter — `api_service.dart`:**
- Nuevo método `getRouteSegment()` para solicitar tramos OSRM al backend.

**Flutter — `api_config.dart`:**
- Nueva constante `routeSegmentEndpoint`.

---

### v2.4.0 — Repartidor: Rebrand, Icono y Soporte Excel (Tarea 7)

**Rebrand:**
- App renombrada de "Repartir App" a **"Repartidor"** en:
  - `AndroidManifest.xml` (`android:label`)
  - `main.dart` (`MaterialApp.title`)
  - AppBar de la pantalla de importación

**Icono personalizado:**
- Icono original (`icon.png` 1536×1024) redimensionado a 1536×1536 (padding blanco).
- Generados mipmaps Android con `flutter_launcher_icons`: `ic_launcher` y adaptive icon.
- Icono registrado como asset para uso en la pantalla principal.

**Pantalla inicial rediseñada (`import_screen.dart`):**
- Nuevo header con logo (100×100 `assets/icon.png`) + título "Repartidor"
  + subtítulo "Optimización de rutas de reparto".
- Zona de importación ahora acepta **Excel (.xlsx)** además de CSV.
- Texto actualizado: "Toca para importar archivo" (antes decía CSV).

**Soporte Excel (`lib/services/excel_service.dart` — NUEVO):**
- Parsea archivos `.xlsx` con múltiples hojas (Table 1, 2, 3…).
- Detección inteligente de columnas:
  - Hojas con cabecera: busca "Nombre", "Dirección", "Localidad", "Bult".
  - Hojas sin cabecera: heurística por contenido (patrones de calle, localidad).
- Concatena Dirección + ", " + Localidad para dirección completa.
- Agrupa filas duplicadas por dirección y suma bultos.
- Devuelve `CsvData` unificado con headers `[Nombre, Dirección, Bultos]`.
- Compatible con pipeline existente (ColumnMapper, CsvPreviewTable, etc.).

**Dependencias:**
- `excel: ^4.0.6` (nueva)
- `flutter_launcher_icons: ^0.14.4` (dev)

---

### v2.5.0 — Mapa Limpio, GPS Real y Segmento Dinámico (Tarea 8)

**Flutter — `route_map.dart`:**
- **Preview limpio:** En modo previsualización (tras calcular la ruta), se eliminó la polilínea
  azul de la ruta completa. Solo se dibujan los marcadores de los clientes para evitar saturar
  visualmente al conductor antes de empezar.
- Se eliminó el método `_getRoutePolyline()` (ya no se usa).

**Flutter — `delivery_screen.dart`:**
- **Inicio desde GPS real:** Al pulsar "Iniciar Reparto", el primer tramo se genera **siempre
  desde la ubicación GPS actual del dispositivo**, no desde el punto inicial del taller/origen.
  Se añadió método `_getCurrentGps()` que:
  1. Intenta obtener la posición del stream del mapa (ya activo).
  2. Si no está disponible, solicita directamente a `Geolocator.getCurrentPosition()`.
  3. En caso de fallo, reintenta tras 2 segundos.
- **Segmento dinámico en cada cambio de estado:** Cada vez que se marca una parada como
  Entregado / Ausente / Incidencia, se recalcula el segmento GPS → siguiente parada usando
  `_fetchSegmentFromGps()` (antes `_fetchSegmentToNextStop()`).
- Al reordenar paradas, también se recalcula el segmento desde GPS real.
- Fallback: si tras reintentos no hay GPS, usa la parada anterior como origen.
- Nuevo import: `package:geolocator/geolocator.dart` (ya era dependencia del proyecto).

---

### v2.6.0 — Cámara Inteligente, Splash Screen y Consistencia de Nombres (Tarea 9)

**Flutter — `route_map.dart` (Bounding Box GPS + Destino):**
- Nuevo método `fitGpsAndNextStop()` que encuadra simultáneamente la posición GPS actual
  y la siguiente parada en un bounding box con padding de 60px. El conductor ve de un vistazo
  cuánto le falta y por dónde va.
- En modo delivery, el botón flotante inferior izquierdo ahora llama a `fitGpsAndNextStop()`
  (icono `crop_free`). En preview sigue llamando a `fitRoute()` (icono `zoom_out_map`).
- Si no hay GPS disponible, centra en el destino como fallback.

**Flutter — `splash_screen.dart` (NUEVO):**
- Pantalla de portada profesional con:
  - Gradiente azul oscuro → azul medio (estilo Wolt/minimalista).
  - Logo 120×120px con bordes redondeados y sombra.
  - Título "Repartidor" (34px, blanco, negrita).
  - Subtítulo "Optimización de rutas de reparto" (semitransparente).
  - `CircularProgressIndicator` discreto.
  - Crédito "Posadas, Córdoba".
- Animaciones de entrada: fade-in + slide-up + scale con `AnimationController` (1.2s).
- Transición automática a `ImportScreen` tras 2.5s con fade de 600ms.

**Flutter — `main.dart`:**
- `home:` cambiado de `ImportScreen` a `SplashScreen`.

**Backend — `optimize.py` (Consistencia de nombres):**
- Cuando no hay `client_name`, el label ahora muestra la dirección abreviada
  (`"📍 Calle Ejemplo, 5…"`) en vez de `"📍 Parada X"`.
- Garantiza que nunca aparezca "Parada X" genérico en la interfaz del usuario.

**Consistencia Visual (verificación):**
- Todos los widgets (`_NextStopCard`, `_CompletedTile`, `StopsList`, `LoadingOrderScreen`,
  reorder sheet) ya priorizan `clientName` sobre `label` como texto principal.
- Con el Excel real, `clientName` siempre está poblado → no se muestra nunca "Parada X".

---

### v2.7.0 — Geocodificación Robusta y Paradas Sin Mapear (Tarea 10)

**Backend — `app/services/geocoding.py` (REESCRITURA COMPLETA):**
- **Limpieza agresiva de direcciones (14 pasos):** diseñada para el Excel real de reparto:
  - Limpia `\xa0`, caracteres de control y encoding roto (`?`, `´`).
  - Corrige acentos: `FernÁndez→Fernández`, `M?SICO→MÚSICO`, `Le?n→León`, `Garc?a→García`.
  - Elimina ruido entre paréntesis: `(estanco)`, `(bar Rogelio)`, `(TOLDOS`.
  - Elimina texto de notas: `Si Ausente Dejar`, `OFICINA DE MAPFRE`, `ESCALERA: ESTANCO`.
  - Normaliza abreviaturas de vía: `C/→Calle`, `CL→Calle`, `AVDA→Avenida`, `Pza→Plaza`, `CRTA→Carretera`, `GALLE→CALLE`.
  - Elimina duplicados de vía: `CL CL. X→Calle X`.
  - Normaliza número: `Nº`, `nº`, `n°`, `n.`, `número` → eliminados.
  - Normaliza s/n: `s/n`, `S,N`, `SN` → `s/n`.
  - Elimina duplicados de número: `n25 n25→25`.
  - Pega número a calle: `Infante78→Infante 78`, `dominguez1a→dominguez 1a`.
  - Elimina pisos/puertas: `1ºB`, `2º B`, `Bajo1`, `bj`.
  - Elimina prefijos de negocio: `suministros BECADAC/`.
  - Elimina guión/coma iniciales: `-,Profesor...→Profesor...`.
  - Añade `, Posadas, Córdoba, España` si no está presente.
- **Geocodificación multi-estrategia (5 niveles de fallback):**
  1. Texto libre limpio completo → Nominatim `q=`.
  2. Búsqueda estructurada → Nominatim `street=` / `city=` / `county=`.
  3. Sin número (solo calle + ciudad).
  4. Bounded=1 (forzar resultados dentro del viewbox de Posadas).
  5. Últimas palabras de la calle (ej: `Carretera Córdoba-Palma del Río KM 31→RIO KM`).
- **Validación de zona:** descarta resultados que estén a más de 0.15° del centro de Posadas.
- **Cache inteligente:** almacena tanto éxitos como fallos para evitar llamadas repetidas.

**Backend — `app/routers/optimize.py` (Fallos parciales):**
- Ya NO lanza `HTTPException(400)` cuando alguna dirección falla.
- Separa direcciones geocodificadas OK vs. fallidas.
- Optimiza la ruta SOLO con las direcciones que se geocodificaron correctamente.
- Las direcciones fallidas se añaden al final de la ruta con `geocode_failed=True`
  y coordenadas dummy (centro de Posadas).
- Log en consola: `[optimize] ⚠ X dirección(es) sin geocodificar: [...]`.

**Backend — `app/models/__init__.py`:**
- `StopInfo`: nuevo campo `geocode_failed: bool = False`.

**Flutter — `lib/models/route_models.dart`:**
- `StopInfo`: nuevo campo `geocodeFailed` parseado del JSON.

**Flutter — `lib/models/delivery_state.dart`:**
- `DeliveryStop`: nuevo campo `geocodeFailed`, serializable a Hive.

**Flutter — `lib/services/persistence_service.dart`:**
- Propaga `geocodeFailed` al crear `DeliveryStop` desde `StopInfo`.

**Flutter — `lib/widgets/stops_list.dart` (UI):**
- Paradas sin geocodificar: fondo amarillo claro, borde naranja, icono ⚠️ en lugar de número,
  título en color ámbar, subtítulo `"⚠ Sin ubicación — [dirección]"`.

**Flutter — `lib/screens/loading_order_screen.dart` (UI):**
- Paquetes sin geocodificar: badge ⚠️ naranja, título en color ámbar, subtítulo con aviso.

**Flutter — `lib/screens/delivery_screen.dart` (UI + lógica):**
- `_NextStopCard`: si la parada es sin geocodificar, muestra badge ⚠️ naranja y título
  `"SIN UBICACIÓN EN MAPA"` en lugar de `"SIGUIENTE PARADA"`.
- Lista reordenable: mismos indicadores visuales (badge naranja, texto de aviso).
- `_fetchSegmentFromGps()`: si la parada actual es `geocodeFailed`, no solicita segmento
  al backend (evita error de coordenadas dummy).
- `_deliveryToStopInfo()`: propaga el campo `geocodeFailed`.

---

### v2.8.0 — Configuración Zero-Config con ngrok (Tarea 11)

**Flutter — `lib/config/api_config.dart` (REDISEÑO):**
- URL base cambiada de IP local a túnel ngrok estático:
  `https://unpermanently-repairable-devon.ngrok-free.dev`.
- El usuario **no necesita configurar nada** — la app funciona out-of-the-box desde cualquier
  dispositivo con conexión a Internet.
- Timeout aumentado a 10 minutos para soportar geocodificación de 70-100 direcciones.
- Nuevos endpoints: `/api/route-segment`, `/api/validate-addresses`, `/api/add-geocode-override`.

**Eliminado:**
- Ya no es necesario editar IPs ni `network_security_config.xml`.
- Instrucciones obsoletas de configuración de red eliminadas de la documentación.

---

### v2.9.0 — Interfaz de Importación Mejorada (Tarea 12)

**Flutter — `lib/screens/import_screen.dart` (MEJORAS UI):**
- **Header visual mejorado:** icono de camión con gradiente, título y subtítulo profesionales.
- **Tarjeta de resumen CSV:** muestra archivo cargado, columnas mapeadas, número de direcciones.
- **Banner de errores expandible:** lista detallada de direcciones con problemas de geocodificación.
- **Sección de subida modernizada:** zona de drop con animaciones, estados visuales claros.
- **Selector de rutas mejorado:** botones toggle con iconos y etiquetas descriptivas.
- **Diálogo de progreso por pasos:** indicadores visuales para cada etapa del proceso
  (Conectando, Geocodificando, Optimizando, Calculando ruta).
- **Validación de direcciones:** llama a `/api/validate-addresses` antes de optimizar,
  mostrando problemas potenciales al usuario.
- **Soporte para overrides:** permite añadir correcciones de geocodificación manualmente.
- **Manejo de errores mejorado:** SnackBars informativos con acciones contextuales.

**Mejoras de UX:**
- Estados de carga con shimmer effects.
- Transiciones suaves entre estados.
- Feedback visual inmediato en todas las acciones.
- Mejor manejo de sesiones activas (banner de reanudación).

---

### v3.0.0 — Rediseño de Paleta de Colores (Tarea 13)

**Nuevo archivo — `lib/config/app_theme.dart`:**
- Centraliza **toda** la paleta de colores en una única clase `AppColors`.
- Define `ThemeData` para modo claro (`appLightTheme`) y oscuro (`appDarkTheme`).
- Regla de oro: texto sobre color → blanco; texto sobre fondo claro → azul/gris oscuro.

**Nueva paleta de colores:**

| Rol | Color | Hex | Uso |
|-----|-------|-----|-----|
| Primary | Azul Profundo/Medianoche | `#003399` | AppBar, botones principales, acentos |
| Success | Verde Esmeralda | `#2E7D32` | Entregado, confirmaciones, checks |
| Warning | Ámbar Intenso | `#E65100` | Ausente, alertas, paradas sin geocodificar |
| Error | Rojo Carmesí | `#C62828` | Errores, incidencias, acciones destructivas |
| Scaffold | Gris Humo | `#F5F5F5` | Fondo de pantallas (modo claro) |
| Card | Blanco Puro | `#FFFFFF` | Tarjetas y contenedores (modo claro) |
| Text Primary | Casi Negro | `#0D1B2A` | Títulos y texto principal |
| Text Secondary | Gris Oscuro | `#475569` | Subtítulos y texto secundario |
| Polyline | Azul Eléctrico | `#2979FF` | Ruta en mapa con borde blanco |

**Modo Oscuro Automático:**
- `ThemeMode.system` — la app cambia automáticamente según configuración del dispositivo.
- Scaffold oscuro: `#121212`, Cards: `#1E1E1E`, Acento: `#448AFF` (azul eléctrico).

**Archivos actualizados con AppColors:**
- `lib/main.dart` — usa `appLightTheme` y `appDarkTheme`.
- `lib/screens/splash_screen.dart` — gradiente y colores centralizados.
- `lib/screens/import_screen.dart` — todos los colores refactorizados.
- `lib/screens/result_screen.dart` — estadísticas y UI actualizadas.
- `lib/screens/delivery_screen.dart` — estados de entrega con nueva paleta.
- `lib/screens/route_picker_screen.dart` — selector de rutas actualizado.
- `lib/screens/loading_order_screen.dart` — lista LIFO con nuevos colores.
- `lib/widgets/route_map.dart` — marcadores y polilíneas actualizados.
- `lib/widgets/stops_list.dart` — lista de paradas con nueva paleta.
- `lib/widgets/stats_banner.dart` — banner de estadísticas actualizado.
- `lib/widgets/column_mapper.dart` — selectores de columnas actualizados.
- `lib/widgets/origin_selector.dart` — selector de origen actualizado.
- `lib/widgets/csv_preview_table.dart` — tabla de preview actualizada.

**Beneficios:**
- Cambiar un color afecta toda la app (mantenibilidad).
- Contraste WCAG mejorado para accesibilidad.
- Coherencia visual en todas las pantallas.
- Soporte nativo para modo oscuro sin código adicional.

---

### v3.1.0 — Normalización y Agrupación por Calle (Bloque 1)

**Backend — `app/services/address_normalizer.py` (NUEVO, ~525 líneas):**
- Pipeline de normalización: `normalize_text()` → `normalize_address()` → `NormalizedAddress`.
- Diccionario de ~45 abreviaturas de vías españolas (`C/ → Calle`, `AVDA → Avenida`, etc.).
- Extracción de código postal, número de portal, tipo de vía.
- `street_key`: clave determinista `"calle|ciudad|cp"` para agrupar + lookup O(1).
- `group_by_street()`: agrupa lista de direcciones por calle → `StreetGroup[]`.

**Backend — `app/routers/validate.py` (AMPLIADO):**
- `POST /api/validate-addresses`: ahora incluye `street_key` por dirección + `street_groups[]` + `unique_streets`.
- `POST /api/normalize-addresses`: nuevo endpoint para preview de agrupación.

**Flutter — `import_screen.dart`:**
- Eliminado CSV, solo Excel (.xlsx/.xls).
- Resumen de validación muestra "X direcciones en Y calles" con badge.
- `AddressEntry` incluye campo `streetKey`.

**Flutter — Modelos actualizados:**
- `validation_models.dart`: `StreetGroupInfo`, `streetKey` en `AddressValidationResult`.
- `csv_data.dart`: nuevo modelo `CsvData` standalone.
- `api_config.dart`: añadido `normalizeEndpoint`.

---

### v3.2.0 — Resolución de Calles con SQLite + RapidFuzz (Bloque 2)

**Backend — `app/services/street_db.py` (NUEVO, ~334 líneas):**
- Base de datos SQLite async (aiosqlite) con 3 tablas:
  - `alias` — Mapeo confirmado nombre crudo → canónico + coords (PK: street_key).
  - `street_virtual` — Calles no existentes en OSM, con snap OSRM (PK: street_key).
  - `geocode_cache` — Cache persistente de resultados Nominatim (PK: street_key).
- Singleton connection con init en `startup` y close en `shutdown`.
- Operaciones batch: `get_aliases_batch()`, `get_virtuals_batch()`, `get_cache_batch()`.
- Fichero: `app/data/streets.db` (creado automáticamente).

**Backend — `app/services/street_resolver.py` (NUEVO, ~468 líneas):**
- Motor de resolución batch con cadena de prioridad: alias → virtual → cache → Nominatim.
- Scoring determinista con RapidFuzz (sin IA):
  - Similitud nombre: 0–60 puntos (`token_sort_ratio`, solo parte de calle).
  - City match: 0–20 puntos.
  - Postcode match: 0–15 puntos.
  - Tipo vía compatible: 0–5 puntos.
- Umbrales: ≥80 auto-resolved, 60–79 needs_review, <60 unresolved.
- Resultados Nominatim auto-resueltos se guardan en cache.

**Backend — `app/routers/streets.py` (NUEVO, ~382 líneas):**
- `POST /api/streets/resolve_batch` — Resolución batch (input: `StreetGroupInput[]`).
- `POST /api/streets/confirm_alias` — Confirma alias → upsert alias + cache.
- `POST /api/streets/create_virtual` — Crea calle virtual + snap OSRM.
- `POST /api/streets/confirm_pin` — Pin manual de coordenadas.
- `GET /api/streets/stats` — Contadores de cada tabla.
- Principio: 1 confirmación arregla N paradas (todas las de esa calle).

**Backend — `app/main.py` (MODIFICADO):**
- Importa `streets.router` y lo registra con prefix `/api`.
- Lifecycle: `startup` → `init_db()`, `shutdown` → `close_db()`.
- Versión actualizada a `2.1.0`.

**Dependencias nuevas:**
- `rapidfuzz==3.14.3` — Fuzzy matching determinista.
- `aiosqlite==0.22.1` — SQLite async para FastAPI.

**Rendimiento verificado:**
- 4 calles con alias/virtual/cache: **5.3ms** (vs ~10s con Nominatim).
- Factor de mejora: **~1800x** en calles ya resueltas.

---

*Documento generado para el proyecto Repartidor — Posadas, Córdoba, España.*
