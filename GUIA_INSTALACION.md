# Guía de instalación — Repartidor App v1.1.0

Guía completa para replicar el entorno de desarrollo en un ordenador nuevo, desde cero, partiendo del repositorio Git.

---

## Índice

1. [Requisitos previos](#1-requisitos-previos)
2. [Clonar el repositorio](#2-clonar-el-repositorio)
3. [Backend Python](#3-backend-python)
4. [Datos OSRM (mapa de rutas)](#4-datos-osrm-mapa-de-rutas)
5. [Servicios Docker (OSRM + VROOM)](#5-servicios-docker-osrm--vroom)
6. [Configurar ngrok](#6-configurar-ngrok)
7. [App Flutter](#7-app-flutter)
8. [Arrancar todo](#8-arrancar-todo)
9. [Verificación](#9-verificación)
10. [Solución de problemas](#10-solución-de-problemas)

---

## 1. Requisitos previos

### Herramientas a instalar

| Herramienta | Versión mínima | Instalar |
|---|---|---|
| **Git** | cualquiera | `sudo apt install git` |
| **Python** | 3.10+ | `sudo apt install python3 python3-venv python3-pip` |
| **Docker Engine** | 24+ | ver abajo |
| **Docker Compose** | v2 (plugin) | incluido con Docker Engine |
| **Flutter SDK** | 3.38+ | ver abajo |
| **ngrok** | 3.x | ver abajo |

> **RAM recomendada:** mínimo 8 GB (el procesado OSRM de Andalucía requiere ~4-6 GB libres).
> **Disco:** reserva ~2 GB para los datos OSRM procesados + imágenes Docker.

---

### Instalar Docker Engine (Linux)

```bash
# Eliminar instalaciones antiguas si las hay
sudo apt remove docker docker-engine docker.io containerd runc

# Instalar dependencias
sudo apt update
sudo apt install ca-certificates curl gnupg lsb-release

# Añadir clave GPG oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Añadir repositorio
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker + plugin Compose
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Permitir usar Docker sin sudo (requiere cerrar sesión y volver a entrar)
sudo usermod -aG docker $USER
```

Verifica la instalación:
```bash
docker --version          # Docker version 24.x o superior
docker compose version    # Docker Compose version v2.x
```

---

### Instalar Flutter SDK

```bash
# Descargar e instalar Flutter (ajusta la versión si hay una más nueva)
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Añadir al PATH (añade esta línea a ~/.bashrc o ~/.zshrc)
export PATH="$HOME/flutter/bin:$PATH"

# Recargar configuración
source ~/.bashrc

# Verificar
flutter doctor
```

Flutter pedirá aceptar las licencias de Android SDK. Si solo necesitas compilar APK:
```bash
flutter doctor --android-licenses
```

---

### Instalar ngrok

```bash
# Descargar e instalar
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok

# Verificar
ngrok version   # ngrok version 3.x
```

---

## 2. Clonar el repositorio

```bash
git clone <URL-del-repositorio> app_repartir
cd app_repartir
```

Estructura tras clonar:

```
app_repartir/
├── app/                  # Backend Python (FastAPI)
├── flutter_app/          # App móvil Flutter
├── vroom-conf/           # Configuración de VROOM
├── docker-compose.yml
├── requirements.txt
├── start.sh
└── GUIA_INSTALACION.md   ← estás aquí
# ⚠️ La carpeta osrm/ NO está en el repo (774 MB).
#    El paso 4 explica cómo generarla.
```

---

## 3. Backend Python

```bash
# Desde la raíz del proyecto
python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
```

Verifica que funciona:
```bash
uvicorn app.main:app --port 8000
# Debe mostrar: INFO: Application startup complete.
# Ctrl+C para salir
```

---

## 4. Datos OSRM (mapa de rutas)

> ⚠️ Esta carpeta **no está en el repositorio** por su tamaño (774 MB).
> Hay que descargar el mapa de Andalucía y procesarlo con Docker. Solo hay que hacerlo **una vez**.

### Paso 1: Crear la carpeta y descargar el mapa

```bash
mkdir -p osrm
cd osrm

# Descargar el mapa de Andalucía desde Geofabrik (~450 MB, puede tardar varios minutos)
wget -O andalucia-latest.osm.pbf \
  "https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf"

cd ..
```

> El archivo `.osm.pbf` de Andalucía ocupa ~450 MB. Si la conexión es lenta, puedes usar `curl -L -o osrm/andalucia-latest.osm.pbf <URL>`.

### Paso 2: Procesar el mapa (solo una vez, tarda ~10-20 min)

```bash
# Extraer la red de carreteras con perfil de coche
docker run --rm -t \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-extract -p /opt/car.lua /data/andalucia-latest.osm.pbf

# Particionar (algoritmo MLD)
docker run --rm -t \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-partition /data/andalucia-latest.osrm

# Personalizar pesos
docker run --rm -t \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-customize /data/andalucia-latest.osrm
```

Tras completarse, la carpeta `osrm/` tendrá ~774 MB con todos los índices necesarios.

### Paso 3: Verificar

```bash
# Levantar OSRM temporalmente para probar
docker run --rm -p 5000:5000 \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-routed --algorithm mld /data/andalucia-latest.osrm &

sleep 5

# Probar una ruta en Posadas
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" \
  | grep '"code"'
# Debe responder: "code":"Ok"

# Parar el contenedor de prueba
docker stop $(docker ps -q --filter ancestor=osrm/osrm-backend)
```

---

## 5. Servicios Docker (OSRM + VROOM)

Con los datos OSRM ya preparados, los servicios se gestionan con `docker-compose.yml`:

```bash
# Arrancar OSRM (puerto 5000) y VROOM (puerto 3000)
docker compose up -d

# Verificar que están activos
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Los servicios están configurados con `restart: unless-stopped`, por lo que se reanudan automáticamente al reiniciar el ordenador.

---

## 6. Configurar ngrok

ngrok crea un túnel público para que la app móvil (en el teléfono) alcance el backend que corre en tu ordenador. Es necesario para probar con APK en un dispositivo real.

### Paso 1: Crear cuenta y obtener auth token

1. Regístrate en [ngrok.com](https://ngrok.com) (plan gratuito es suficiente)
2. En el panel: **Your Authtoken** → copia el token
3. Configura ngrok con tu token:

```bash
ngrok config add-authtoken <tu-token-aquí>
```

### Paso 2: (Solo para uso con APK) Actualizar la URL en la app

Cuando el backend esté corriendo y ngrok activo, obtendrás una URL pública del tipo `https://xxxx-xxx.ngrok-free.app`.

Edita [`flutter_app/lib/config/api_config.dart`](flutter_app/lib/config/api_config.dart):

```dart
// Para desarrollo local (Flutter en el mismo PC):
static const String baseUrl = 'http://127.0.0.1:8000';

// Para APK en dispositivo físico (usa tu URL de ngrok):
static const String baseUrl = 'https://xxxx-xxx.ngrok-free.app';
```

> **Nota:** La URL de ngrok cambia cada vez que reinicias ngrok (plan gratuito). Para una URL fija, ngrok ofrece dominios estáticos de pago, o puedes usar una URL fija propia.

---

## 7. App Flutter

```bash
cd flutter_app

# Instalar dependencias Dart/Flutter
flutter pub get

# Ejecutar en dispositivo/emulador conectado
flutter run

# Ejecutar como app de escritorio Linux (útil para depurar)
flutter run -d linux
```

### Depurar en el navegador (recomendado para desarrollo rápido)

La forma más cómoda de depurar sin compilar APK ni conectar un dispositivo es correr la app como web app:

```bash
cd flutter_app
flutter run -d web-server --web-port=8080
# Abre http://localhost:8080 en tu navegador
```

> **Requisito:** Antes de lanzar, asegúrate de que `flutter_app/lib/config/api_config.dart` tiene la URL del backend local:
> ```dart
> static const String baseUrl = 'http://127.0.0.1:8000';
> ```
> El backend debe estar corriendo (`./start.sh start` o `uvicorn app.main:app --port 8000`).

### Compilar APK para Android

```bash
cd flutter_app

# Antes de compilar, asegúrate de que api_config.dart apunta a la URL de ngrok:
# static const String baseUrl = 'https://xxxx-xxx.ngrok-free.app';

flutter build apk --release
# APK resultante en: build/app/outputs/flutter-apk/app-release.apk
```

Para instalar el APK en un teléfono Android:
1. Activa **Opciones de desarrollador** → **Depuración USB** en el teléfono
2. Conecta el teléfono por USB y acepta la solicitud de depuración
3. `flutter install` o copia el APK manualmente y permite "fuentes desconocidas"

---

## 8. Arrancar todo

Una vez completada la instalación, el arranque diario es un solo comando:

```bash
cd /ruta/a/app_repartir
./start.sh start
```

Esto hace automáticamente:
1. Verifica requisitos (Docker, Python, ngrok)
2. Arranca los contenedores OSRM + VROOM
3. Espera a que OSRM y VROOM estén operativos
4. Lanza el backend FastAPI en background (puerto 8000)
5. Lanza ngrok y muestra la URL pública

Otros comandos:
```bash
./start.sh stop     # Detener todo
./start.sh restart  # Reiniciar todo
./start.sh status   # Ver estado de cada servicio
./start.sh logs     # Ver últimos logs de todos los servicios
```

---

## 9. Verificación

```bash
# 1. Backend
curl http://localhost:8000/health
# → {"status":"ok","version":"1.1.0"}

# 2. OSRM
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep '"code"'
# → "code":"Ok"

# 3. VROOM
curl -I http://localhost:3000/health
# → HTTP/1.1 200 OK

# 4. ngrok
curl -s http://127.0.0.1:4040/api/tunnels | grep public_url
# → "public_url":"https://xxxx.ngrok-free.app"

# 5. Swagger UI (documentación interactiva de la API)
# Abre en el navegador: http://localhost:8000/docs
```

### Puertos del sistema

| Puerto | Servicio |
|--------|----------|
| 8000 | Backend FastAPI |
| 5000 | OSRM (motor de rutas) |
| 3000 | VROOM (optimizador TSP) |
| 4040 | Panel de ngrok |

---

## 10. Solución de problemas

### OSRM no arranca: "Cannot open /data/andalucia-latest.osrm"
El fichero `.osrm` no existe. Repite el paso 4 (procesado del mapa).

### Backend falla al importar módulos
Asegúrate de que el entorno virtual está activado antes de arrancar:
```bash
source venv/bin/activate
uvicorn app.main:app --port 8000
```
El `start.sh` lo hace automáticamente.

### `docker compose up -d` falla: "permission denied"
El usuario no está en el grupo `docker`. Ejecuta:
```bash
sudo usermod -aG docker $USER
# Cierra sesión y vuelve a entrar, o ejecuta:
newgrp docker
```

### ngrok: "authentication failed" o "ERR_NGROK_105"
El auth token no está configurado:
```bash
ngrok config add-authtoken <tu-token>
```

### La app Flutter no conecta al backend (APK en móvil)
- Verifica que ngrok está corriendo: `./start.sh status`
- Comprueba que `api_config.dart` tiene la URL de ngrok (no `127.0.0.1`)
- Recuerda recompilar el APK después de cambiar la URL: `flutter build apk --release`

### VROOM responde 500 en optimizaciones con muchas paradas
VROOM usa `network_mode: host` para comunicarse con OSRM. Verifica que los dos contenedores ven el puerto 5000:
```bash
docker exec vroom-posadas curl -s http://localhost:5000/health
```

### El geocoding falla en muchas direcciones
- El catálogo de calles OSM se descarga de Overpass API al primer uso y se cachea 7 días en `app/data/osm_streets.json`. Si hay problemas de red, puede fallar.
- La caché de geocodificación está en `app/data/geocode_cache.json`. Si está corrupta, bórrala y se regenerará.

---

## Formato del CSV de entrada

La app espera un CSV con exactamente estas tres columnas:

```
cliente,direccion,ciudad
Juan García,Calle Gaitán 24,Posadas
María López,Avenida Blas Infante 37,Posadas
```

Requisitos:
- Separador: coma (`,`)
- Codificación: UTF-8
- La columna `ciudad` debe ser `Posadas` (la geocodificación está limitada a esa área)
- Consulta `data/paradas_limpio.csv` como referencia de formato correcto

---

*Guía generada para Repartidor App v1.1.0 — Febrero 2026*
