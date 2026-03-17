# Changelog — Repartidor App

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.0.0/)

---

## [1.0.0] — Marzo 2026

Primera versión de producción. Base funcional estable para entrega al repartidor.

### Stack

- **Backend:** Python 3.10 + FastAPI + Uvicorn
- **Frontend:** Flutter 3.38 (Dart 3.10), Android
- **Rutas:** OSRM (Docker, puerto 5000)
- **Optimización TSP:** LKH3 (binario local, determinista)
- **Geocodificación:** Google Geocoding API + Google Places API + Overpass (fuzzy matching)

### Funcionalidades

#### Importación y validación
- Importación de CSV (`cliente, direccion, ciudad [, nota] [, agencia] [, alias]`)
- Pipeline de geocodificación multi-fuente con niveles de confianza: `EXACT_ADDRESS`, `GOOD`, `EXACT_PLACE`, `OVERRIDE`
- Caché persistente en disco con TTL 30 días para entradas Google/Places
- Catálogo de calles OSM (Overpass API, TTL 7 días) + calles aprendidas permanentes
- Corrección manual de coordenadas (pin en mapa) para direcciones no geocodificadas

#### Optimización de rutas
- Snap de coordenadas a la red viaria real (OSRM `/nearest`, caché sin TTL)
- Matriz de distancias y tiempos reales (OSRM `/table`)
- Solver TSP abierto con LKH3 — determinista, ~350 ms para 50 paradas
- Post-proceso anti-zigzag: adelanta paradas de paso (desvío ≤ 20 m)

#### Reparto en campo
- Navegación GPS en tiempo real con tramo OSRM dinámico
- Marcado de paradas: Entregado / Ausente
- Deshacer estado de parada (devolver a pendiente) desde mapa y lista
- Reordenación drag & drop de paradas pendientes
- Re-pin manual de ubicación durante el reparto
- Apertura de Google Maps/navegación externa por parada
- Sesión persistente en Hive (reanudable si la app se cierra)

#### Modo 2 rutas (Express / Normal)
- Nueva columna `tipo` en el CSV (`Express` o `Normal`; case-insensitive; vacío = Normal). Formato completo: `cliente, direccion, ciudad, nota, agencia, tipo, alias`
- Toggle "1 ruta / 2 rutas" en `ImportScreen`. Con 2 rutas: el frontend divide las paradas por tipo y lanza dos llamadas paralelas al backend
- Nueva `RouteSelectionScreen`: muestra ambas rutas (paradas, paquetes, km) y permite elegir cuál abrir
- Badge **Express** en las tarjetas de parada (`StopsList`) — solo visible cuando hay paquetes Express
- Título dinámico de AppBar en `ResultScreen` ("Ruta Express / Normal") y `DeliveryScreen` ("Reparto Express / Normal")
- `DeliverySession.routeType: String?` para identificar la sesión activa en modo 2 rutas
- Backward compatible: CSVs sin columna `tipo` funcionan igual que antes

#### Calidad
- 273+ tests backend (pytest), análisis estático mypy (0 errores)
- 128+ tests Flutter, cobertura ≥ 98 % en modelos y servicios, dart analyze (0 warnings)
- Script `run_tests.sh` unificado (tests + cobertura + análisis estático)

---

## Formato para versiones futuras

```
## [X.Y.Z] — Mes Año

### Added
-

### Changed
-

### Fixed
-

### Removed
-
```
