# Changelog — RepartidorApp

---

## [1.4.0] — Febrero 2026

### Changed
- **Umbral OSRM snap reducido 2000 m → 500 m**: las coordenadas que no tengan un nodo viario a menos de 500 m se consideran fuera del mapa y su parada pasa a geocode_failed, evitando que VROOM reciba puntos en medio del campo.
- **Ordenación de tramos de calle** (`_sort_street_runs`): tras la optimización VROOM, las paradas consecutivas en la misma calle se re-ordenan ascendentemente por número de portal, reduciendo el zigzag dentro de una misma vía.
- **Paradas con geocodificación fallida**: usan `lat=None, lon=None` en lugar de las coordenadas del depósito. Aparecen al final de la ruta con indicador ⚠️; no se envían a VROOM.
- **Modelos Flutter null-safe**: `StopInfo.lat/lon` y `DeliveryStop.lat/lon` son ahora `double?`. La deserialización `fromJson`/`fromMap` admite null sin lanzar excepción.
- **Guards null en Flutter**: `flyToStop`, `fitGpsAndNextStop`, `_buildStopMarkers`, el fallback GPS y la navegación externa comprueban `lat != null && lon != null` antes de operar.
- **Diálogo Reordenar mejorado**: el badge de cada parada muestra el número de orden fijo de la ruta original (no el índice de la lista filtrada); el subtítulo despliega cliente + nota de cada paquete.

### Fixed
- **Error de compilación Dart**: `double?` no asignable a `double` en `_fetchSegmentFromGps` para `destLat`/`destLon`; resuelto con comprobación explícita de null antes de la llamada a `ApiService.getRouteSegment`.

---

## [1.3.0] — Febrero 2026

### Added
- **Marcar parada como entregada desde Reordenar**: en el diálogo de reordenación, cada parada dispone ahora de un botón ✅ verde que la marca como entregada y la elimina de la lista al instante, sin necesidad de cerrar el sheet ni navegar a la tarjeta de siguiente parada.

### Changed
- **Título de parada = dirección**: en todas las pantallas (reparto, reordenar, completadas, lista de paradas, orden de carga) el título principal de cada parada muestra la dirección física, no el nombre del cliente. Los clientes pasan a subtítulo o lista de paquetes, permitiendo múltiples destinatarios por parada.
- **Diálogo de reordenar**: muestra todas las paradas no entregadas (pendientes + ausentes + incidencias), ya que ausentes e incidencias son reintentables. Antes solo se mostraban las pendientes.
- **Exportar CSV** (`ResultScreen`): nuevo formato con columnas `orden, direccion, num_paquetes, paquetes`. La columna `paquetes` detalla cada paquete como `cliente - nota`; para múltiples paquetes usa numeración `1. … | 2. …`.
- **Resumen de importación**: el recuadro «X paquetes / Y direcciones» en `ImportScreen` ya no aparece durante la validación; se muestra solo una vez la geocodificación ha finalizado correctamente.

---

## [1.2.0] — Febrero 2026

### Added
- **Columna `nota` en CSV**: el fichero de entrada ahora admite una cuarta columna opcional `nota` (piso, puerta, instrucciones como "dejar en portal", referencia de negocio, etc.). Si no existe la columna, la app funciona igual que antes (retrocompatibilidad total).
- **Modelo `Package`** (backend + Flutter): cada paquete dentro de una parada lleva `client_name` y `nota` independientes. Una parada agrupa N paquetes de la misma dirección física; la nota no afecta a geocodificación ni a la caché.
- **UI de paquetes en pantalla de reparto** (`DeliveryScreen`):
  - 1 paquete con nota → nota en gris debajo del nombre en la tarjeta de siguiente parada.
  - N paquetes → lista expandible `📦 N paquetes ▼` con filas `· cliente  nota`; expandida por defecto si ≤ 4 paquetes.
- **UI de paquetes en lista de paradas** (`StopsListScreen`): lista compacta con `· cliente  nota` bajo la dirección de cada parada multi-paquete.
- **Ruta GPS actualizada periódicamente**: el tramo OSRM entre posición actual y siguiente parada se refresca automáticamente cada **30 segundos** mientras el repartidor conduce, sin necesidad de interacción.
- **Transición animada de cámara** (`RouteMap`): al avanzar a la siguiente parada o reordenar, la cámara vuela suavemente (900 ms, `easeInOutCubic`) enmarcando GPS + nueva parada. Se elimina el salto brusco anterior.
- **CSVs de prueba**: `data_input/test_nota.csv` (5 filas de ejemplo con nota) y `data_input/prueba1_nuevo.csv` (67 envíos reales con notas extraídas del PDF GLS).

### Changed
- **`_markStop()` y `_applyReorder()`**: reemplazan el `Future.delayed(500 ms)` por `addPostFrameCallback`, lo que garantiza que la animación de cámara arranca en el primer frame tras el cambio de parada (sin espera artificial).
- El polígono de ruta antiguo se limpia inmediatamente al marcar una parada, evitando el artefacto de "polígono apuntando a la parada ya completada" durante la transición.
- **`packages_per_stop`** en el endpoint `/api/optimize`: sustituye a la lista plana `all_client_names` para transportar clientes + notas sin pérdida de información.

### Technical
- `RouteMapState` añade `TickerProviderStateMixin` + `AnimationController _cameraAnimController`.
- `_DeliveryScreenState` añade `Timer? _segmentTimer` con cancelación correcta en `dispose()`.
- Persistencia Hive (`DeliveryStop`) incluye `packages` con deserialización retrocompatible (fallback `[]` para sesiones antiguas).

---

## [1.1.0] — Febrero 2026

### Added
- **Geocodificación con matching difuso**: cuando Nominatim no encuentra una dirección exacta, se busca la calle más parecida en el catálogo real de OSM usando `token_set_ratio` (stdlib `difflib`). Maneja artículos extra, abreviaciones y variaciones de nombre sin reglas idiomáticas específicas.
- **Catálogo de calles OSM via Overpass API**: se descarga automáticamente (174 calles de Posadas) y se persiste en `app/data/osm_streets.json` con TTL de 7 días. Se recarga solo cuando caduca.
- **Caché persistente de geocodificación** (`app/data/geocode_cache.json`): los resultados sobreviven reinicios del backend. Clave canónica: `normalize(calle)#normalize(número)`.
- **CSV de referencia `data/paradas_limpio.csv`**: fichero con 103 direcciones bien formateadas como plantilla y requisito de calidad para futuras importaciones.
- **Botón para exportar ruta en CSV** (Flutter): nueva acción en `ResultScreen` que permite guardar la secuencia de paradas optimizada como fichero CSV.
- **Función pública `is_cached(address)`** en el servicio de geocodificación, para consultar la caché sin exponer el dict interno.

### Changed
- **Parser de direcciones mejorado** (`_parse_address`): maneja correctamente `nº`, `número`, `n°`, `n17`, `N21`, números compuestos (`2-1`), indicadores de piso/planta (`bajo`, `1 planta`, `local`, etc.), sufijos de ciudad separados por coma y contenido entre paréntesis (cerrados y abiertos).
- **Estrategia de geocodificación multi-paso**: directo Nominatim → corrección difusa + reintento → último recurso sin número. Resultado: 94.9 % de éxito (74/78 direcciones únicas) sobre el CSV de prueba.
- **Pantalla de importación renovada** (Flutter `ImportScreen`): simplificación del flujo de validación y mejoras visuales en `ApiService`.
- **Endpoint de validación** (`/api/validation/start`): nuevo método de validación con mejor agrupación de duplicados y respuesta de estado enriquecida.

### Removed
- `app/data/geocode_overrides.json`: sustituido por la nueva caché persistente `geocode_cache.json` con estructura y claves mejoradas.

---

## [1.0.0] — Febrero 2026

**Esta versión 1.0.0 es la base funcional estable. Todos los cambios futuros deben documentarse aquí.**

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
- Sin caché persistente de geocoding en v1.0.0 (solo en memoria mientras el backend está vivo)

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

