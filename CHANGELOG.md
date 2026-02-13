# Changelog — RepartidorApp v1.0.0

**Fecha de versión:** Febrero 2026

---

## Versión 1.0.0
**Esta versión 1.0.0 es la base funcional estable. Todos los cambios futuros deben documentarse aquí.**

### Arquitectura general
- **Backend:** Python 3.10 + FastAPI
- **Frontend:** Flutter 3.38 (Dart 3.10)
- **Optimización de rutas:** OSRM (motor de rutas) + VROOM (optimización TSP/VRP) vía Docker
- **Geocodificación:** Nominatim (OpenStreetMap, sin caché persistente)
- **Importación de datos:** CSV (columnas: cliente, dirección, ciudad)

---

## Funcionalidades principales

### Backend (FastAPI)

#### Endpoints principales
- `POST /api/validation/start`
  - Recibe lista de direcciones y nombres de cliente
  - Agrupa por dirección exacta (misma cadena = misma parada, suma paquetes)
  - Geocodifica cada dirección única con Nominatim
  - Devuelve: dirección, nº paquetes, coordenadas, estado (ok/problem), nombres de cliente

- `POST /api/optimize`
  - Recibe lista de direcciones (pueden venir ya agrupadas), nombres de cliente, coordenadas pre-resueltas, número de vehículos
  - Si recibe `package_counts` y `all_client_names`, usa los datos ya agrupados (no reagrupa)
  - Calcula la ruta óptima (TSP/VRP) usando VROOM y OSRM
  - Devuelve: secuencia optimizada de paradas, coordenadas, nombres de cliente, número de paquetes por parada, geometría de la ruta, instrucciones de navegación

- `GET /health`
  - Verifica que el backend está vivo

- `GET /api/services/status`
  - Verifica el estado de los servicios Docker (OSRM y VROOM)

- `GET /api/route-segment`
  - Devuelve la geometría GeoJSON del tramo entre dos puntos (para navegación paso a paso)

#### Modelos y lógica
- Agrupación de direcciones duplicadas (normalización ligera)
- Geocodificación multi-estrategia (texto libre, estructurada, bounded, etc.)
- Soporte para overrides manuales de coordenadas
- Respuestas detalladas con `package_count` y `client_names` por parada
- Sin caché persistente de geocoding (solo en memoria mientras el backend está vivo)

### Frontend (Flutter)

#### Funciones principales
- Importación de CSV con columnas `cliente`, `direccion`, `ciudad`
- Validación de direcciones (muestra problemas y permite corregir antes de calcular ruta)
- Cálculo de ruta optimizada (1 o 2 vehículos)
- Visualización de la ruta en mapa (con geometría y paradas)
- Visualización de número de paquetes y destinatarios por parada
- Gestión de entregas en tiempo real (marcar entregado, ausente, incidencia)
- Persistencia local del progreso de reparto
- Soporte para reanudar sesión de reparto

#### Modelos y servicios
- Modelos para validación (`ValidationResponse`, `StopValidationResult`)
- Modelos para optimización de ruta (`OptimizeResponse`, `StopInfo`, `RouteSummary`)
- Servicios para comunicación con backend (`ApiService`), importación de CSV (`CsvService`), localización GPS, persistencia local

### Scripts y utilidades
- `excel_a_csv.py`: conversión de Excel a CSV limpio
- `test_validation_flow.py`: script de testeo de validación y optimización
- `start.sh`: script de arranque automático de todos los servicios

### Estructura de carpetas relevante
- `app/`: backend FastAPI
- `flutter_app/`: frontend Flutter
- `osrm/`: archivos de datos de OSRM (no incluidos en el repo)
- `vroom-conf/`: configuración de VROOM
- `paradas.csv`, `paradas_calles_corregidas.csv`: ejemplos de datos de entrada

---

## Formato para futuras versiones

### [vX.Y.Z] — Fecha
#### Added
- ...
#### Changed
- ...
#### Fixed
- ...
#### Removed
- ...

---

