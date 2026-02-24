# 📦 Repartidor App

> **Sistema completo de optimización de rutas de reparto para Posadas, Córdoba**
> Backend FastAPI + Flutter App + OSRM + VROOM

**Versión:** 1.2.0
**Última actualización:** Febrero 2026



---

## 🎯 ¿Qué es esto?

**Repartidor** es una aplicación móvil profesional que permite optimizar rutas de reparto:

- 📂 **Importa** un CSV o Excel con direcciones
- 🧮 **Calcula** la ruta más eficiente automáticamente
- 🗺️ **Visualiza** en mapa con navegación GPS
- ✅ **Gestiona** entregas en tiempo real (Entregado/Ausente/Incidencia)
- 💾 **Persiste** el progreso (puedes cerrar la app y continuar)

---

## ⚡ Up del servidor

### Opción 1: Script Automático 

```bash
cd /home/mariano/Desktop/app_repartir
./start.sh
```

✅ Inicia todo automáticamente  
✅ Verifica que funciona correctamente  
✅ Muestra URLs de acceso y estado

### Opción 2: Manual

```bash
# 1. Docker (OSRM + VROOM)
docker compose up -d

# 2. Backend FastAPI
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > backend.log 2>&1 &

# 3. ngrok (túnel público)
nohup ngrok http 8000 --log=stdout > /tmp/ngrok.log 2>&1 &
```

---

## 📚 Documentación y archivos relevantes

| Archivo / Carpeta | Descripción |
|-------------------|-------------|
| **CHANGELOG.md** | Historial y versión inicial estable (v1.0.0) |
| **start.sh** | Script de arranque automático (si está presente) |
| **docker-compose.yml** | Definición de servicios Docker (OSRM, VROOM, etc.) |
| **requirements.txt** | Dependencias Python para el backend |
| **vroom-conf/** | Configuraciones de ejemplo para VROOM |
| **app/** | Código del backend (FastAPI) |
| **flutter_app/** | Código de la app Flutter |


---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                   📱 Flutter App                        │
│            (Android - Dart + Material 3)                │
│                                                         │
│  • import_screen.dart  → Importar CSV/Excel            │
│  • result_screen.dart  → Ver ruta optimizada           │
│  • delivery_screen.dart → Ejecutar reparto             │
└─────────────────┬───────────────────────────────────────┘
                  │ HTTP JSON
                  ▼
┌─────────────────────────────────────────────────────────┐
│              🐍 Backend FastAPI (Python)                │
│                                                         │
│  • geocoding.py → Convertir texto → GPS                │
│  • routing.py   → Calcular ruta óptima                 │
│  • optimize.py  → Endpoint principal                   │
└──┬──────────────────────────────┬───────────────────────┘
   │                              │
   │ ┌────────────────────────┐   │ ┌──────────────────┐
   └─▶ 🐳 OSRM (Docker)        │   └─▶ 🐳 VROOM (Docker)│
     │ Motor de rutas reales  │     │ Optimizador TSP  │
     │ Puerto: 5000           │     │ Puerto: 3000     │
     └────────────────────────┘     └──────────────────┘
```

---

## 🛠️ Stack Tecnológico

### Backend
- **Python 3.10** + FastAPI
- **OSRM** (rutas reales por calles)
- **VROOM** (optimización TSP/VRP)
- **Nominatim** (geocodificación OSM)
- **Docker Compose** (orquestación)

### Frontend
- **Flutter 3.38** (Dart 3.10)
- **flutter_map** (mapas OSM)
- **Hive** (persistencia local)
- **geolocator** (GPS)

### Infraestructura
- **ngrok** (túnel público)
- **Docker** (contenedores)

---

## 📊 Puertos del Sistema

| Puerto | Servicio | Acceso |
|--------|----------|--------|
| **3000** | VROOM | http://localhost:3000 |
| **5000** | OSRM | http://localhost:5000 |
| **8000** | Backend | http://localhost:8000 |
| **4040** | ngrok panel | http://127.0.0.1:4040 |

---

## 🎮 Comandos del Script

```bash
./start.sh          # Iniciar todos los servicios
./start.sh status   # Ver estado actual
./start.sh stop     # Detener todos los servicios
./start.sh restart  # Reiniciar (útil tras cambios)
```

---

## ✅ Verificación Rápida

```bash
# Backend
curl http://localhost:8000/health
# → {"status":"ok","version":"2.1.0"}

# OSRM
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep "Ok"
# → "code":"Ok"

# VROOM
curl -I http://localhost:3000/health
# → HTTP 200

# ngrok
curl http://127.0.0.1:4040/api/tunnels | grep public_url
# → "public_url":"https://..."
```

## 🐞 Debuggear local (Flutter web + backend)

Si quieres depurar la app sin compilar un APK ni usar un emulador físico, la opción más rápida es ejecutar la app Flutter como web app y conectar al backend local. Resumen de pasos:

1) Cambiar la URL del backend para desarrollo

 - Edita `flutter_app/lib/config/api_config.dart` y cambia `baseUrl` por:

```dart
static const String baseUrl = 'http://127.0.0.1:8000';
```

2) Arrancar el backend y servicios usando el script `start.sh` (recomendado)

```bash
# Desde la raíz del proyecto
./start.sh start    # inicia Docker (OSRM + VROOM), backend y ngrok

# Comandos útiles del script:
./start.sh status   # ver estado de servicios
./start.sh stop     # detener todos los servicios
./start.sh restart  # reiniciar
```

Si prefieres arrancar sólo el backend manualmente (por ejemplo para depuración muy rápida), puedes hacerlo con el venv:

```bash
source venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
# o en background
nohup venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > /tmp/backend.log 2>&1 &
```

3) Lanzar la app Flutter como servidor web

```bash
cd flutter_app
flutter pub get
flutter run -d web-server --web-port=8080
# abre luego http://localhost:8080 en tu navegador
```


---

## 🚀 Despliegue en Móvil

### Generar APK

```bash
cd flutter_app
flutter build apk --release
# APK en: build/app/outputs/flutter-apk/app-release.apk
```

### Instalar

1. Copiar APK al móvil
2. Habilitar "Fuentes desconocidas"
3. Instalar
4. Abrir app → debe mostrar 🟢 Online

**La app usa automáticamente el túnel ngrok** configurado en `lib/config/api_config.dart`:
```dart
static const String baseUrl = 
    'https://unpermanently-repairable-devon.ngrok-free.dev';
```

---

## 📁 Estructura del Proyecto

```
app_repartir/
├── app/                      # 🐍 Backend Python
│   ├── main.py              # Punto de entrada FastAPI
│   ├── core/config.py       # Configuración central
│   ├── routers/             # Endpoints API
│   └── services/            # Lógica de negocio
│
├── flutter_app/             # 📱 App móvil
│   ├── lib/
│   │   ├── config/          # Tema y API config
│   │   ├── models/          # Modelos de datos
│   │   ├── services/        # HTTP, GPS, persistencia
│   │   ├── screens/         # Pantallas
│   │   └── widgets/         # Componentes UI
│   └── android/             # Config Android
│
├── osrm/                    # 🗺️ Datos OSM Andalucía
├── vroom-conf/              # ⚙️ Config VROOM
│
├── docker-compose.yml       # 🐳 Definición servicios
├── requirements.txt         # 📦 Dependencias Python
│
├── start.sh                 # 🚀 Script de inicio (si está presente)
└── CHANGELOG.md      # � Changelog y versión inicial
```


## ⚠️ Mapas OSRM (no incluidos)

La carpeta `osrm/` con el mapa no se incluye en el repo por su tamaño.

Si necesitas volver a poner la carpeta `osrm/` en tu entorno local, estos son los pasos recomendados (ejecutar desde la raíz del proyecto, y ajusta nombres según tu fichero PBF):

1. Descarga el PBF de la zona que necesites (por ejemplo, Geofabrik). Ejemplo:
```bash
mkdir -p osrm
cd osrm
# Ejemplo (sustituye URL por la del área que necesites)
wget -O andalucia-latest.osm.pbf "https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf"
cd ..
```

2. Generar los índices OSRM (usando la imagen Docker oficial). Aquí usamos el perfil por defecto (`/opt/car.lua`) y el algoritmo MLD:

```bash
# Extraer datos
docker run --rm -t -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-extract -p /opt/car.lua /data/andalucia-latest.osm.pbf

# Particionar y customizar (MLD)
docker run --rm -t -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-partition /data/andalucia-latest.osrm
docker run --rm -t -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-customize /data/andalucia-latest.osrm

# Iniciar el servicio OSRM (puerto 5000)
docker run -d --name osrm -p 5000:5000 -v "$(pwd)/osrm:/data" osrm/osrm-backend osrm-routed --algorithm mld /data/andalucia-latest.osrm
```

Alternativa (si prefieres `osrm-contract` en vez de `mld`) — consulta la documentación de OSRM para tu versión y perfil de coste.

3. Verifica que OSRM responde:

```bash
curl "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false"
# deberías ver un JSON con "code":"Ok"
```

Notas:
- El repositorio incluye un `.gitignore` que excluye la carpeta `osrm/` para evitar añadir archivos pesados por accidente.
- Si prefieres no usar Docker, puedes instalar `osrm-backend` localmente y ejecutar los mismos comandos (`osrm-extract`, `osrm-partition`, `osrm-customize`, `osrm-routed`).
- Los nombres de archivo (`andalucia-latest.osm.pbf` y `andalucia-latest.osrm`) son solo ejemplos; usa los que correspondan a tu área.
