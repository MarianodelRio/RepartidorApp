# Repartidor App

> **Sistema completo de optimización de rutas de reparto para Posadas, Córdoba**
> Backend FastAPI + Flutter App + OSRM + LKH3

**Versión:** 2.2.0
**Última actualización:** Marzo 2026

---

## ¿Qué es esto?

**Repartidor** es una aplicación móvil profesional que permite optimizar rutas de reparto:

- Importa un CSV con direcciones
- Calcula la ruta más eficiente automáticamente (solver LKH3 TSP)
- Visualiza en mapa con navegación GPS
- Gestiona entregas en tiempo real (Entregado/Ausente/Incidencia)
- Persiste el progreso (puedes cerrar la app y continuar)

---

## Up del servidor

### Opción 1: Script automático

```bash
cd /home/mariano/Desktop/app_repartir
./start.sh
```

Inicia OSRM (Docker), backend FastAPI y ngrok. Verifica que todo funciona y muestra las URLs.

### Opción 2: Manual

```bash
# 1. Docker (OSRM)
docker compose up -d

# 2. Backend FastAPI
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > backend.log 2>&1 &

# 3. ngrok (túnel público)
nohup ngrok http 8000 --log=stdout > /tmp/ngrok.log 2>&1 &
```

---

## Documentación y archivos relevantes

| Archivo / Carpeta | Descripción |
|-------------------|-------------|
| **CHANGELOG.md** | Historial completo de versiones |
| **explicacion.md** | Documentación técnica detallada de todos los módulos |
| **start.sh** | Script de arranque y gestión de servicios |
| **run_tests.sh** | Tests + cobertura + análisis estático (backend y Flutter) |
| **docker-compose.yml** | Servicios Docker (OSRM) |
| **requirements.txt** | Dependencias Python del backend |
| **mypy.ini** | Configuración de análisis estático Python |
| **app/** | Código del backend (FastAPI) |
| **tests/** | Tests del backend (221 tests, pytest) |
| **flutter_app/** | Código de la app Flutter |
| **docs/** | Documentación adicional (regenerar OSRM, etc.) |

---

## Tests y Calidad

Ejecutar todo (tests + cobertura + análisis estático):

```bash
./run_tests.sh
```

### Backend — 221 tests (pytest)

| Módulo | Tests |
|--------|-------|
| `test_health.py` | 7 |
| `test_validation_endpoint.py` | 11 |
| `test_optimize_endpoint.py` | 22 |
| `test_geocoding_service.py` | 26 |
| `test_catalog_service.py` | 13 |
| `test_routing_service.py` | 35 |
| tests unitarios puros | 107 |

Análisis estático con **mypy** (0 errores). Configuración en `mypy.ini`.

```bash
python -m pytest          # solo tests
python -m mypy app/       # solo tipado estático
```

### Flutter — tests unitarios

Cobertura total: **≥ 98 %** sobre modelos y servicios.

```bash
cd flutter_app
flutter test              # solo tests
dart analyze              # análisis estático (0 warnings)
```

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter App                           │
│            (Android - Dart + Material 3)                │
│                                                         │
│  • import_screen.dart      → Importar CSV              │
│  • validation_review.dart  → Revisar geocodificación   │
│  • result_screen.dart      → Ver ruta optimizada       │
│  • delivery_screen.dart    → Ejecutar reparto          │
└─────────────────┬───────────────────────────────────────┘
                  │ HTTP JSON
                  ▼
┌─────────────────────────────────────────────────────────┐
│              Backend FastAPI (Python)                   │
│                                                         │
│  • geocoding.py  → Google Geocoding + Places + fuzzy   │
│  • routing.py    → LKH3 TSP + OSRM + snap cache        │
│  • optimize.py   → Endpoint principal                   │
└──────────────────────────┬──────────────────────────────┘
                           │
              ┌────────────────────────┐
              │     OSRM (Docker)      │
              │  Motor de rutas reales │
              │  Puerto: 5000          │
              └────────────────────────┘
```

---

## Stack Tecnológico

### Backend
- **Python 3.10** + FastAPI
- **OSRM** (rutas reales por calles, Docker)
- **LKH3** (solver TSP, binario local)
- **Google Geocoding API** (geocodificación principal, precisión portal)
- **Google Places API** (geocodificación de negocios por alias)
- **Overpass API** (catálogo de calles para fuzzy matching)

### Frontend
- **Flutter 3.38** (Dart 3.10)
- **flutter_map** (mapas OSM)
- **Hive** (persistencia local)
- **geolocator** (GPS)

### Infraestructura
- **ngrok** (túnel público)
- **Docker** (OSRM)

---

## Puertos del Sistema

| Puerto | Servicio | Acceso |
|--------|----------|--------|
| **5000** | OSRM | http://localhost:5000 |
| **8000** | Backend | http://localhost:8000 |
| **4040** | ngrok panel | http://127.0.0.1:4040 |

---

## Comandos del Script

```bash
./start.sh                # Iniciar todos los servicios
./start.sh status         # Ver estado actual
./start.sh stop           # Detener todos los servicios
./start.sh restart        # Reiniciar
./start.sh rebuild-map    # Reprocesar PBF editado y reiniciar OSRM
```

---

## Verificación Rápida

```bash
# Backend
curl http://localhost:8000/health
# → {"status":"ok","version":"2.2.0"}

# OSRM
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep "Ok"
# → "code":"Ok"

# ngrok
curl http://127.0.0.1:4040/api/tunnels | grep public_url
# → "public_url":"https://..."
```

---

## Depurar local (Flutter web + backend)

1. Edita `flutter_app/lib/config/api_config.dart`:
```dart
static const String baseUrl = 'http://127.0.0.1:8000';
```

2. Arranca los servicios:
```bash
./start.sh start
```

3. Lanza Flutter como web:
```bash
cd flutter_app
flutter run -d web-server --web-port=8080
# abre http://localhost:8080
```

---

## Despliegue en Móvil

```bash
cd flutter_app
flutter build apk --release
# APK en: build/app/outputs/flutter-apk/app-release.apk
```

La app usa el túnel ngrok configurado en `lib/config/api_config.dart`.

---

## Estructura del Proyecto

```
app_repartir/
├── app/                      # Backend Python
│   ├── main.py              # Punto de entrada FastAPI
│   ├── core/config.py       # Configuración central
│   ├── routers/             # Endpoints API
│   ├── services/            # Lógica de negocio
│   ├── models/              # Modelos Pydantic
│   └── data/                # Cachés en disco (geocode, snap)
│
├── flutter_app/             # App móvil
│   ├── lib/
│   │   ├── config/          # Tema y API config
│   │   ├── models/          # Modelos de datos
│   │   ├── services/        # HTTP, GPS, persistencia
│   │   ├── screens/         # Pantallas
│   │   └── widgets/         # Componentes UI
│   └── android/             # Config Android
│
├── osrm/                    # Datos OSM (mapa de Posadas)
├── docs/                    # Documentación adicional
├── docker-compose.yml       # Definición servicios Docker
├── requirements.txt         # Dependencias Python
├── start.sh                 # Script de gestión de servicios
└── CHANGELOG.md             # Historial de versiones
```

## Mapas OSRM

La carpeta `osrm/` con el mapa no se incluye en el repo por su tamaño.

Tras editar el mapa en JOSM:
```bash
./start.sh rebuild-map
```

Desde cero (descargando Andalucía):
```bash
mkdir -p osrm && cd osrm
wget -O andalucia-latest.osm.pbf "https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf"
cd ..
docker run --rm -t -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-extract -p /opt/car.lua /data/andalucia-latest.osm.pbf
docker run --rm -t -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-partition /data/andalucia-latest.osrm
docker run --rm -t -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-customize /data/andalucia-latest.osrm
```
