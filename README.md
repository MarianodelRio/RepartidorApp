# 📦 Repartidor App

> **Sistema completo de optimización de rutas de reparto para Posadas, Córdoba**  
> Backend FastAPI + Flutter App + OSRM + VROOM

**Versión:** 3.0.0  
**Última actualización:** Febrero 2026

---

## 🎯 ¿Qué es esto?

**Repartidor** es una aplicación móvil profesional que permite optimizar rutas de reparto:

- 📂 **Importa** un CSV o Excel con direcciones
- 🧮 **Calcula** la ruta más eficiente automáticamente
- 🗺️ **Visualiza** en mapa con navegación GPS
- ✅ **Gestiona** entregas en tiempo real (Entregado/Ausente/Incidencia)
- 💾 **Persiste** el progreso (puedes cerrar la app y continuar)
- 👥 **Reparto compartido** entre 2 repartidores

---

## ⚡ Inicio Rápido

### Opción 1: Script Automático (⭐ Recomendado)

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

## 📚 Documentación

> **[📖 ÍNDICE COMPLETO DE DOCUMENTACIÓN](INDICE_DOCS.md)** ← Empieza aquí

| Archivo | Descripción |
|---------|-------------|
| **[INDICE_DOCS.md](INDICE_DOCS.md)** | 🗺️ Guía de navegación de toda la documentación |
| **[INICIO_RAPIDO.md](INICIO_RAPIDO.md)** | ⚡ Una página con comandos esenciales |
| **[GUIA_INICIO.md](GUIA_INICIO.md)** | 📋 Guía paso a paso manual completa |
| **[README_SCRIPT.md](README_SCRIPT.md)** | 🚀 Cómo usar el script `start.sh` |
| **[DOCUMENTACION.md](DOCUMENTACION.md)** | 📖 Documentación técnica completa (2000+ líneas) |
| **[start.sh](start.sh)** | 🎯 Script de inicio automático |

### ¿Qué leer según tu necesidad?

- **No sé por dónde empezar** → `INDICE_DOCS.md` 🗺️
- **Solo quiero que funcione YA** → `INICIO_RAPIDO.md`
- **Quiero entender qué hace cada comando** → `GUIA_INICIO.md`
- **Quiero usar el script automático** → `README_SCRIPT.md`
- **Soy desarrollador, quiero entender TODO** → `DOCUMENTACION.md`

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
├── start.sh                 # 🚀 Script de inicio
├── INICIO_RAPIDO.md         # ⚡ Guía express
├── GUIA_INICIO.md          # 📋 Guía manual completa
├── README_SCRIPT.md         # 📖 Uso del script
└── DOCUMENTACION.md         # 📚 Docs técnicas completas
```

---

## 🐛 Troubleshooting

### Backend no arranca

```bash
# Ver logs
tail -f backend.log

# Verificar puerto libre
lsof -ti:8000

# Si está ocupado, matar proceso
lsof -ti:8000 | xargs kill
```

### Docker no responde

```bash
# Reiniciar servicios
docker compose down
docker compose up -d

# Ver logs
docker logs osrm-posadas
docker logs vroom-posadas
```

### App muestra 🔴 Offline

```bash
# Verificar backend
curl http://localhost:8000/health

# Verificar ngrok
curl http://127.0.0.1:4040/api/tunnels

# Reiniciar todo
./start.sh restart
```

---

## 🎨 Características v3.0

### ✨ Nuevo Sistema de Colores
- Paleta centralizada en `app_theme.dart`
- Modo oscuro automático (sigue sistema)
- Colores profesionales: Azul profundo + Verde esmeralda + Ámbar

### 🔄 Validación Incremental (v3.0+)
- Editar direcciones una por una
- Revalidar solo las modificadas
- Persistencia con Hive
- Indicadores visuales de estado

### 🗺️ Mapa Inteligente
- Segmento GPS → siguiente parada (verde)
- Marcador siguiente parada: grande y destacado
- Recálculo automático tras cada entrega
- Cámara ajusta GPS + destino simultáneamente

### 📊 Soporte Multi-formato
- CSV con detección automática de columnas
- Excel (.xlsx) con múltiples hojas
- Agrupación de direcciones duplicadas
- Suma automática de bultos

---

## 📝 Changelog

### v3.0.0 (Feb 2026)
- ✨ Rediseño completo de paleta de colores
- 🎨 Modo oscuro automático
- 🔄 Validación incremental con persistencia
- 📋 Script de inicio automático
- 📚 Documentación reorganizada

### v2.9.0
- 🎨 Interfaz de importación mejorada
- 🔍 Validación previa de direcciones
- ⚠️ Banner de errores expandible

### v2.8.0
- 🌐 Configuración zero-config con ngrok
- 🔗 URL pública estática

*(Ver DOCUMENTACION.md para changelog completo)*

---

## 👥 Equipo

- **Backend & Arquitectura:** Sistema FastAPI + Docker
- **Frontend:** App Flutter Material 3
- **Infraestructura:** OSRM + VROOM + ngrok
- **Zona:** Posadas, Córdoba, España

---

## 📄 Licencia

Proyecto interno — Uso privado

---

## 🆘 Soporte

Para problemas o preguntas:

1. Revisar `DOCUMENTACION.md` sección 12 (Troubleshooting)
2. Ejecutar `./start.sh status` y capturar salida
3. Revisar logs:
   - Backend: `tail -f backend.log`
   - Docker: `docker logs osrm-posadas`
   - ngrok: `tail -f /tmp/ngrok.log`

---

*Desarrollado con ❤️ para optimizar entregas en Posadas*
