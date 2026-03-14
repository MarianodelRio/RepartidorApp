# Repartidor App

Sistema de optimización de rutas de reparto para Posadas (Córdoba). Importa un CSV de direcciones, geocodifica, optimiza el recorrido con LKH3 y lo muestra en la app móvil.

## Arquitectura

```
Flutter App (Android)
      │ HTTP JSON
      ▼
Backend FastAPI (Python 3.10)
      ├── Google Geocoding API  → geocodificación de direcciones
      ├── Google Places API     → geocodificación de negocios por alias
      ├── Overpass API (OSM)    → catálogo de calles para fuzzy matching
      ├── LKH3 (binario local)  → solver TSP
      └── OSRM (Docker)         → distancias y rutas reales por carretera
```

## Puertos

| Puerto | Servicio |
|--------|----------|
| 8000   | Backend FastAPI |
| 5000   | OSRM (Docker) |
| 4040   | Panel ngrok |

## Stack

| Capa | Tecnología |
|------|-----------|
| Backend | Python 3.10, FastAPI, Uvicorn |
| Frontend | Flutter 3.38+, Dart 3.10+, Android |
| Routing | OSRM via Docker |
| TSP | LKH3 (binario local) |
| Storage | Sin base de datos. Caché JSON en `app/data/` |

## Restricciones de arquitectura

- Sin base de datos relacional ni NoSQL server. El backend persiste estado en ficheros JSON (`app/data/`).
- No añadir dependencias nuevas (Python o Dart) sin justificación explícita.
- `mypy` debe pasar con 0 errores. `dart analyze` con 0 warnings.
- La única variable de entorno necesaria es `GOOGLE_API_KEY` (en `.env` en la raíz).

## Contextos locales

- Reglas de trabajo del backend y tests: `app/CLAUDE.md`
- Reglas de trabajo de la app Flutter: `flutter_app/CLAUDE.md`
