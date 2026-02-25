# Guía de instalación — Repartidor App v1.4.0

Guía completa para replicar el entorno de desarrollo en un ordenador nuevo, desde cero, partiendo del repositorio Git.

Compatible con **Linux (Ubuntu/Debian)** y **Windows 10/11 con WSL2**.

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

### Herramientas necesarias

| Herramienta | Versión mínima | Linux | Windows (WSL2) |
|---|---|---|---|
| **Git** | cualquiera | `sudo apt install git` | incluido en WSL2 |
| **Python** | 3.10+ | `sudo apt install python3 python3-venv` | en WSL2 (ver abajo) |
| **Docker** | 24+ | Docker Engine (ver abajo) | Docker Desktop (ver abajo) |
| **Flutter SDK** | 3.38+ | en terminal Linux | instalación nativa Windows |
| **ngrok** | 3.x | en terminal Linux | en WSL2 (ver abajo) |

> **RAM recomendada:** mínimo 8 GB (el procesado OSRM de Andalucía requiere ~4-6 GB libres).
> **Disco:** reserva ~2 GB para los datos OSRM + imágenes Docker.

---

### 🐧 Linux — Instalar Docker Engine

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

Verifica:
```bash
docker --version          # Docker version 24.x o superior
docker compose version    # Docker Compose version v2.x
```

---

### 🪟 Windows — Preparar WSL2 + Docker Desktop

El backend, Docker y ngrok se ejecutan **dentro de WSL2**. Flutter se instala de forma nativa en Windows.

#### Paso 1: Instalar WSL2 con Ubuntu

Abre **PowerShell como administrador** y ejecuta:

```powershell
wsl --install -d Ubuntu
```

Esto instala WSL2 y la distribución Ubuntu. Reinicia el ordenador cuando lo pida.

Al volver a encender, se abrirá un terminal Ubuntu pidiéndote nombre de usuario y contraseña para WSL2. Créalos.

Verifica la versión:
```powershell
wsl --list --verbose
# Ubuntu debe aparecer con VERSION 2
```

> Si Ubuntu ya estaba instalado con WSL1, actualiza:
> `wsl --set-version Ubuntu 2`

#### Paso 2: Instalar Docker Desktop

1. Descarga Docker Desktop desde [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
2. Instala con las opciones por defecto
3. Abre Docker Desktop → **Settings → General** → activa **"Use the WSL 2 based engine"**
4. Ve a **Settings → Resources → WSL Integration** → activa la integración con tu distribución Ubuntu

Verifica desde el terminal WSL2 (Ubuntu):
```bash
docker --version
docker compose version
```

#### Paso 3: Instalar dependencias en WSL2

Abre el terminal de Ubuntu (busca "Ubuntu" en el menú inicio) y ejecuta:

```bash
sudo apt update
sudo apt install python3 python3-venv python3-pip git curl wget
```

#### Paso 4: Instalar ngrok en WSL2

```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok
```

---

### 🐧 Linux — Instalar Flutter SDK

```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Añadir al PATH (añade esta línea a ~/.bashrc o ~/.zshrc)
export PATH="$HOME/flutter/bin:$PATH"
source ~/.bashrc

flutter doctor
flutter doctor --android-licenses
```

---

### 🪟 Windows — Instalar Flutter (nativo)

Flutter se instala nativamente en Windows para aprovechar el SDK de Android sin problemas de compatibilidad.

1. Descarga el instalador desde [docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows)
2. Extrae en una ruta sin espacios, por ejemplo `C:\flutter`
3. Añade `C:\flutter\bin` al **PATH** del sistema:
   - Busca "Variables de entorno" en el menú inicio
   - En "Variables del sistema" → `Path` → Nuevo → `C:\flutter\bin`
4. Abre una terminal nueva (PowerShell o CMD) y verifica:

```powershell
flutter doctor
flutter doctor --android-licenses
```

> **Nota:** Los comandos de Flutter se ejecutan en **PowerShell o CMD de Windows**, no en WSL2.

---

### 🐧 Linux — Instalar ngrok

```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok
ngrok version
```

---

## 2. Clonar el repositorio

### 🐧 Linux

```bash
git clone <URL-del-repositorio> app_repartir
cd app_repartir
```

### 🪟 Windows (WSL2)

Clona **dentro del sistema de ficheros de WSL2** (no en `/mnt/c/`), para que Docker tenga acceso directo y el rendimiento sea óptimo:

```bash
# En el terminal de Ubuntu (WSL2):
cd ~
git clone <URL-del-repositorio> app_repartir
cd app_repartir
```

> ⚠️ No clones en `/mnt/c/Users/...`. El acceso a la carpeta de Windows desde WSL2 es mucho más lento y puede causar problemas con Docker volumes.

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

> Ejecuta estos comandos en **terminal Linux** o **terminal WSL2 (Ubuntu)**.

```bash
# Desde la raíz del proyecto
python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
```

Verifica:
```bash
uvicorn app.main:app --port 8000
# Debe mostrar: INFO: Application startup complete.
# Ctrl+C para salir
```

---

## 4. Datos OSRM (mapa de rutas)

> ⚠️ Esta carpeta **no está en el repositorio** por su tamaño (774 MB).
> Hay que descargar el mapa de Andalucía y procesarlo con Docker. Solo hay que hacerlo **una vez**.
>
> Ejecuta estos comandos en **terminal Linux** o **terminal WSL2 (Ubuntu)**.

### Paso 1: Crear la carpeta y descargar el mapa

```bash
mkdir -p osrm
cd osrm

# Descargar el mapa de Andalucía desde Geofabrik (~450 MB, puede tardar varios minutos)
wget -O andalucia-latest.osm.pbf \
  "https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf"

cd ..
```

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
docker run --rm -p 5000:5000 \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-routed --algorithm mld /data/andalucia-latest.osrm &

sleep 5

curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" \
  | grep '"code"'
# Debe responder: "code":"Ok"

docker stop $(docker ps -q --filter ancestor=osrm/osrm-backend)
```

---

## 5. Servicios Docker (OSRM + VROOM)

> Ejecuta en **terminal Linux** o **terminal WSL2 (Ubuntu)**.

```bash
# Arrancar OSRM (puerto 5000) y VROOM (puerto 3000)
docker compose up -d

# Verificar que están activos
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Los servicios están configurados con `restart: unless-stopped`, por lo que se reanudan automáticamente al reiniciar.

> **Windows:** Docker Desktop debe estar abierto (o configurado para arrancar con Windows) para que los contenedores funcionen.

---

## 6. Configurar ngrok

ngrok crea un túnel público para que la app móvil (en el teléfono) alcance el backend. Necesario para probar con APK en un dispositivo real.

### Paso 1: Crear cuenta y obtener auth token

1. Regístrate en [ngrok.com](https://ngrok.com) (plan gratuito es suficiente)
2. En el panel: **Your Authtoken** → copia el token
3. Configura ngrok con tu token (en terminal Linux o WSL2):

```bash
ngrok config add-authtoken <tu-token-aquí>
```

### Paso 2: (Solo para APK) Actualizar la URL en la app

Cuando ngrok esté activo, obtendrás una URL del tipo `https://xxxx-xxx.ngrok-free.app`.

Edita [`flutter_app/lib/config/api_config.dart`](flutter_app/lib/config/api_config.dart):

```dart
// Para desarrollo local (Flutter en el mismo PC):
static const String baseUrl = 'http://127.0.0.1:8000';

// Para APK en dispositivo físico (usa tu URL de ngrok):
static const String baseUrl = 'https://xxxx-xxx.ngrok-free.app';
```

> **Nota:** La URL de ngrok cambia cada vez que reinicias ngrok (plan gratuito).

---

## 7. App Flutter

### 🐧 Linux

```bash
cd flutter_app
flutter pub get
flutter run                    # en dispositivo/emulador conectado
flutter run -d web-server --web-port=8080   # en navegador (para depurar)
```

### 🪟 Windows

Los comandos de Flutter se ejecutan en **PowerShell o CMD de Windows** (no en WSL2), apuntando a la carpeta del proyecto dentro de WSL2:

```powershell
# Opción A: accede al proyecto desde Windows usando la ruta \\wsl$
cd \\wsl$\Ubuntu\home\<tu-usuario>\app_repartir\flutter_app
flutter pub get
flutter run
```

O, más cómodo, copia la carpeta `flutter_app` a Windows si prefieres tenerla en `C:\`:

```powershell
cd C:\ruta\a\flutter_app
flutter pub get
flutter run
```

Para depurar en el navegador:
```powershell
flutter run -d web-server --web-port=8080
# Abre http://localhost:8080
```

> El backend corre en WSL2. Desde Flutter en Windows, accede a él usando la IP de WSL2 en lugar de `127.0.0.1`. Para encontrarla:
> ```bash
> # En terminal WSL2:
> hostname -I   # algo como 172.x.x.x
> ```
> Actualiza `api_config.dart` con esa IP durante el desarrollo local en Windows.
> En producción (APK), usa siempre la URL de ngrok.

### Compilar APK para Android (Linux y Windows)

```bash
# Asegúrate de que api_config.dart tiene la URL de ngrok antes de compilar
flutter build apk --release
# APK en: build/app/outputs/flutter-apk/app-release.apk
```

Para instalar en el teléfono:
1. Activa **Opciones de desarrollador** → **Depuración USB**
2. Conecta por USB y acepta la solicitud
3. `flutter install` o copia el APK manualmente

---

## 8. Arrancar todo

### 🐧 Linux

```bash
cd /ruta/a/app_repartir
./start.sh start
```

### 🪟 Windows (WSL2)

Abre el terminal de Ubuntu (WSL2) y ejecuta:

```bash
cd ~/app_repartir
./start.sh start
```

> Docker Desktop debe estar abierto antes de ejecutar `start.sh`.
> Los servicios quedan corriendo en WSL2. Para pararlos: `./start.sh stop`.

`start.sh` hace automáticamente:
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
./start.sh logs     # Ver últimos logs
```

---

## 9. Verificación

> Ejecuta en terminal Linux o WSL2.

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

# 5. Swagger UI
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
Activa el entorno virtual antes de arrancar:
```bash
source venv/bin/activate
uvicorn app.main:app --port 8000
```
El `start.sh` lo hace automáticamente.

### `docker compose up -d` falla: "permission denied" (Linux)
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Docker no funciona desde WSL2 (Windows)
- Verifica que Docker Desktop está abierto
- Ve a Docker Desktop → Settings → Resources → WSL Integration → activa Ubuntu
- Reinicia Docker Desktop

### WSL2 se queda sin memoria con el procesado OSRM
WSL2 tiene un límite de RAM por defecto. Auméntalo creando `C:\Users\<usuario>\.wslconfig`:
```ini
[wsl2]
memory=6GB
processors=4
```
Reinicia WSL2: `wsl --shutdown` en PowerShell, luego abre Ubuntu de nuevo.

### Flutter en Windows no conecta al backend en WSL2
WSL2 tiene su propia IP de red, diferente de `127.0.0.1`. Obtén la IP:
```bash
# En terminal WSL2:
hostname -I
```
Usa esa IP en `api_config.dart` durante el desarrollo. En producción (APK en móvil) usa siempre la URL de ngrok.

### ngrok: "authentication failed" o "ERR_NGROK_105"
```bash
ngrok config add-authtoken <tu-token>
```

### La app Flutter no conecta al backend (APK en móvil)
- Verifica que ngrok está corriendo: `./start.sh status`
- Comprueba que `api_config.dart` tiene la URL de ngrok (no `127.0.0.1` ni la IP de WSL2)
- Recompila el APK después de cambiar la URL: `flutter build apk --release`

### VROOM responde 500 en optimizaciones con muchas paradas
Verifica que los dos contenedores ven el puerto 5000:
```bash
docker exec vroom-posadas curl -s http://localhost:5000/health
```

### El geocoding falla en muchas direcciones
- La caché OSM se descarga de Overpass API al primer uso y se guarda en `app/data/osm_streets.json`.
- La caché de geocodificación está en `app/data/geocode_cache.json`. Si está corrupta, bórrala y se regenerará.

---

## Formato del CSV de entrada

```
cliente,direccion,ciudad
Juan García,Calle Gaitán 24,Posadas
María López,Avenida Blas Infante 37,Posadas
```

Requisitos:
- Separador: coma (`,`)
- Codificación: UTF-8
- La columna `ciudad` debe ser `Posadas`
- Consulta `data_input/prueba1.csv` como referencia

---

*Guía generada para Repartidor App v1.1.0 — Febrero 2026*
