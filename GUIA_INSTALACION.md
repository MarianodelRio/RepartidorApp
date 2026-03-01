# Guía de instalación — Repartidor App v2.0.0

Guía completa para replicar el entorno de desarrollo en un ordenador nuevo, desde cero, partiendo del repositorio Git.

Compatible con **Linux (Ubuntu/Debian)** y **Windows 10/11 con WSL2** (Docker Desktop o Rancher Desktop).

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

### Resumen de herramientas

| Herramienta | Versión mínima | Linux | Windows (WSL2) |
|---|---|---|---|
| **Git** | cualquiera | `sudo apt install git` | incluido en WSL2 |
| **Python** | 3.10+ | `sudo apt install python3 python3-venv` | en WSL2 (ver abajo) |
| **Docker** | 24+ | Docker Engine (ver sección Linux) | Docker Desktop o Rancher Desktop |
| **Flutter SDK** | 3.38+ | instalación en Linux | instalación nativa Windows |
| **ngrok** | 3.x | instalación en Linux | en WSL2 (ver abajo) |

> **RAM recomendada:** mínimo 8 GB (el procesado OSRM de Andalucía requiere ~4-6 GB libres).
> **Disco:** reserva ~2 GB para los datos OSRM + imágenes Docker.

---

## Linux — Instalación completa de requisitos

### Instalar dependencias del sistema

```bash
sudo apt update
sudo apt install git python3 python3-venv python3-pip curl wget
```

### Instalar Docker Engine

```bash
# Eliminar instalaciones antiguas si las hay
sudo apt remove docker docker-engine docker.io containerd runc

# Añadir clave GPG oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Añadir repositorio de Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker + plugin Compose
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Permitir usar Docker sin sudo (requiere cerrar sesión y volver a entrar)
sudo usermod -aG docker $USER
newgrp docker
```

Verifica:
```bash
docker --version          # Docker version 24.x o superior
docker compose version    # Docker Compose version v2.x
```

### Instalar Flutter SDK en Linux

```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Añadir al PATH — añade esta línea a ~/.bashrc o ~/.zshrc
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

flutter doctor
flutter doctor --android-licenses
```

### Instalar ngrok en Linux

```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
  sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
  sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok

ngrok version   # ngrok version 3.x
```

---

## Windows — Instalación completa de requisitos

El backend, Docker y ngrok se ejecutan **dentro de WSL2** (subsistema Linux). Flutter se instala de forma nativa en Windows.

### Paso 1: Instalar WSL2 con Ubuntu

Abre **PowerShell como administrador** y ejecuta:

```powershell
wsl --install -d Ubuntu
```

Esto instala WSL2 y la distribución Ubuntu. Reinicia el ordenador cuando lo pida.

Al volver a encender, se abrirá un terminal Ubuntu pidiendo nombre de usuario y contraseña — créalos. Después verifica:

```powershell
wsl --list --verbose
# Ubuntu debe aparecer con VERSION 2
```

> Si Ubuntu ya existía con WSL1: `wsl --set-version Ubuntu 2`

### Paso 2: Instalar un gestor de contenedores Docker

Tienes dos opciones. **Rancher Desktop es la recomendada** porque es completamente gratuito.

#### Opción A — Rancher Desktop (recomendado, gratuito)

1. Descarga desde [rancherdesktop.io](https://rancherdesktop.io/) e instala con las opciones por defecto.
2. En el primer arranque, en **Preferences → Container Engine** selecciona **dockerd (moby)** — esto hace que `docker` y `docker compose` funcionen igual que Docker Desktop.
3. En **Preferences → WSL** activa la integración con tu distribución Ubuntu.
4. Reinicia Rancher Desktop si cambiaste el motor.

Verifica desde el terminal de Ubuntu (WSL2):
```bash
docker --version
docker compose version
```

#### Opción B — Docker Desktop

1. Descarga desde [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) e instala con las opciones por defecto.
2. Abre Docker Desktop → **Settings → General** → activa **"Use the WSL 2 based engine"**.
3. Ve a **Settings → Resources → WSL Integration** → activa la integración con tu distribución Ubuntu.

Verifica desde el terminal de Ubuntu (WSL2):
```bash
docker --version
docker compose version
```

> **Nota:** Docker Desktop requiere licencia de pago en empresas con más de 250 empleados o ingresos superiores a 10M€.

### Paso 3: Instalar dependencias en WSL2

Abre el terminal de Ubuntu (busca "Ubuntu" en el menú inicio):

```bash
sudo apt update
sudo apt install python3 python3-venv python3-pip git curl wget
```

### Paso 4: Instalar ngrok en WSL2

```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
  sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
  sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok

ngrok version   # ngrok version 3.x
```

### Paso 5: Instalar Flutter en Windows (nativo)

Flutter se instala nativamente en Windows para aprovechar el SDK de Android sin problemas de compatibilidad.

1. Descarga el archivo zip desde [docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows).
2. Extráelo en una ruta sin espacios, por ejemplo `C:\flutter`.
3. Añade `C:\flutter\bin` al **PATH** del sistema:
   - Busca "Variables de entorno" en el menú inicio.
   - En "Variables del sistema" → selecciona `Path` → clic en "Editar" → "Nuevo" → escribe `C:\flutter\bin`.
   - Acepta y cierra.
4. Abre una terminal nueva (PowerShell o CMD) y verifica:

```powershell
flutter doctor
flutter doctor --android-licenses
```

> Los comandos de Flutter se ejecutan siempre en **PowerShell o CMD de Windows**, nunca en WSL2.

---

## 2. Clonar el repositorio

### En Linux

```bash
git clone <URL-del-repositorio> app_repartir
cd app_repartir
```

### En Windows (terminal WSL2 — Ubuntu)

Clona **dentro del sistema de ficheros de WSL2** (no en `/mnt/c/`), para que Docker tenga acceso directo y el rendimiento sea óptimo:

```bash
cd ~
git clone <URL-del-repositorio> app_repartir
cd app_repartir
```

> ⚠️ **No clones en `/mnt/c/Users/...`**. El acceso a la carpeta de Windows desde WSL2 es muy lento y puede causar problemas con los volúmenes de Docker.

### Estructura tras clonar

```
app_repartir/
├── app/                  # Backend Python (FastAPI)
│   ├── main.py
│   ├── core/config.py
│   ├── routers/
│   └── services/
├── flutter_app/          # App móvil Flutter
├── vroom-conf/           # Configuración de VROOM
├── docker-compose.yml
├── requirements.txt
├── start.sh
└── GUIA_INSTALACION.md   ← estás aquí

# ⚠️ La carpeta osrm/ NO está en el repo (~774 MB).
#    El paso 4 explica cómo generarla.
```

### Ajustar la ruta en start.sh

`start.sh` tiene la ruta del proyecto codificada. Cámbiala a tu ruta real:

```bash
# Edita la línea PROJECT_DIR en start.sh
# Linux:
nano start.sh
# Busca: PROJECT_DIR="/home/mariano/Desktop/app_repartir"
# Sustitúyela por tu ruta, por ejemplo:
# PROJECT_DIR="/home/tu-usuario/app_repartir"

# En WSL2, la ruta sería similar:
# PROJECT_DIR="/home/tu-usuario-wsl/app_repartir"
```

---

## 3. Backend Python

> Ejecuta estos comandos en **terminal Linux** o **terminal WSL2 (Ubuntu)**, desde la raíz del proyecto.

### Crear y activar el entorno virtual

```bash
cd ~/app_repartir          # o tu ruta al proyecto

python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
```

### Configurar la clave de API de Google

El backend requiere una clave de Google para geocodificación. Crea el fichero `.env` en la raíz del proyecto:

```bash
echo "GOOGLE_API_KEY=tu-clave-de-api-aqui" > .env
```

> La clave necesita habilitadas las APIs: **Geocoding API** y **Places API (New)**. Crea o consulta la clave en [console.cloud.google.com](https://console.cloud.google.com).

### Verificar el backend

```bash
source venv/bin/activate
uvicorn app.main:app --port 8000
# Debe mostrar:
#   INFO: Application startup complete.
# Ctrl+C para salir
```

---

## 4. Datos OSRM (mapa de rutas)

> ⚠️ La carpeta `osrm/` **no está en el repositorio** por su tamaño (~774 MB).
> Hay que descargar el mapa de Andalucía y procesarlo con Docker. **Solo hay que hacerlo una vez.**
>
> Ejecuta en **terminal Linux** o **terminal WSL2 (Ubuntu)**, desde la raíz del proyecto.

### Paso 1: Descargar el mapa

```bash
mkdir -p osrm
cd osrm

# Descarga el mapa de Andalucía desde Geofabrik (~450 MB, puede tardar varios minutos)
wget -O andalucia-latest.osm.pbf \
  "https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf"

cd ..
```

### Paso 2: Procesar el mapa (tarda ~10-20 min)

```bash
# 1) Extraer la red de carreteras con perfil de coche
docker run --rm -t \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-extract -p /opt/car.lua /data/andalucia-latest.osm.pbf

# 2) Particionar (algoritmo MLD)
docker run --rm -t \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-partition /data/andalucia-latest.osrm

# 3) Personalizar pesos
docker run --rm -t \
  -v "$(pwd)/osrm:/data" \
  osrm/osrm-backend \
  osrm-customize /data/andalucia-latest.osrm
```

Tras completarse, `osrm/` tendrá ~774 MB con todos los índices necesarios.

### Paso 3: Verificar

```bash
# Arrancar OSRM temporalmente para probar
docker run --rm -d -p 5000:5000 \
  -v "$(pwd)/osrm:/data" \
  --name osrm-test \
  osrm/osrm-backend \
  osrm-routed --algorithm mld /data/andalucia-latest.osrm

sleep 5

# Debe responder "code":"Ok"
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep '"code"'

# Parar el contenedor de prueba
docker stop osrm-test
```

---

## 5. Servicios Docker (OSRM + VROOM)

> Ejecuta en **terminal Linux** o **terminal WSL2 (Ubuntu)**, desde la raíz del proyecto.
>
> En Windows: Rancher Desktop o Docker Desktop deben estar abiertos antes de ejecutar estos comandos.

```bash
cd ~/app_repartir

# Arrancar OSRM (puerto 5000) y VROOM (puerto 3000)
docker compose up -d

# Verificar que están activos
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Salida esperada:
```
NAMES            STATUS          PORTS
vroom-posadas    Up X seconds
osrm-posadas     Up X seconds    0.0.0.0:5000->5000/tcp
```

> Los servicios tienen `restart: unless-stopped`, por lo que se reanudan automáticamente al reiniciar el sistema (siempre que Docker esté corriendo).

> **Nota sobre Rancher Desktop:** VROOM usa `network_mode: host` en el `docker-compose.yml` para comunicarse con OSRM. Esto funciona correctamente con Rancher Desktop en modo `dockerd (moby)` sobre WSL2.

---

## 6. Configurar ngrok

ngrok crea un túnel público HTTPS para que la app móvil (APK en el teléfono) alcance el backend que corre en tu PC. Es necesario para probar con dispositivos físicos.

### Paso 1: Crear cuenta y configurar token

1. Regístrate en [ngrok.com](https://ngrok.com) (el plan gratuito es suficiente).
2. En el panel de ngrok: **Your Authtoken** → copia el token.
3. Configura ngrok (en terminal Linux o WSL2):

```bash
ngrok config add-authtoken <tu-token-aquí>
```

### Paso 2: Actualizar la URL en la app Flutter

Cuando ngrok esté activo obtendrás una URL del tipo `https://xxxx-xxx.ngrok-free.app`.

Edita [flutter_app/lib/config/api_config.dart](flutter_app/lib/config/api_config.dart):

```dart
// Para desarrollo con emulador en el mismo PC:
static const String baseUrl = 'http://127.0.0.1:8000';

// Para APK en dispositivo físico (usa tu URL de ngrok):
static const String baseUrl = 'https://xxxx-xxx.ngrok-free.app';
```

> La URL de ngrok cambia cada vez que reinicias ngrok (plan gratuito). Recuerda recompilar el APK después de cambiarla.

---

## 7. App Flutter

### En Linux

```bash
cd ~/app_repartir/flutter_app

flutter pub get 2>&1 | cat    # instala dependencias
flutter run                   # ejecuta en dispositivo/emulador conectado
```

### En Windows

Los comandos de Flutter se ejecutan en **PowerShell o CMD de Windows**, no en WSL2.

```powershell
# Navega al proyecto usando la ruta UNC de WSL2
# Sustituye "tu-usuario-wsl" por tu usuario de Ubuntu
cd \\wsl$\Ubuntu\home\tu-usuario-wsl\app_repartir\flutter_app

flutter pub get
flutter run
```

> **El backend corre en WSL2**, no en Windows. Desde Flutter en Windows, `127.0.0.1` apunta a Windows, no a WSL2. Para desarrollo local, obtén la IP de WSL2:
> ```bash
> # En terminal Ubuntu (WSL2):
> hostname -I
> # Devuelve algo como: 172.24.x.x
> ```
> Usa esa IP en `api_config.dart` durante el desarrollo. En producción (APK en móvil) usa siempre la URL de ngrok.

### Compilar APK para Android

```bash
# Asegúrate de que api_config.dart tiene la URL de ngrok antes de compilar

# En Linux:
cd ~/app_repartir/flutter_app
flutter build apk --release

# En Windows (PowerShell):
cd \\wsl$\Ubuntu\home\tu-usuario-wsl\app_repartir\flutter_app
flutter build apk --release
```

El APK resultante estará en:
```
flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

Para instalar en el teléfono:
1. Activa **Opciones de desarrollador** → **Depuración USB** en Android.
2. Conecta el teléfono por USB y acepta la solicitud de depuración.
3. `flutter install` o copia el APK manualmente al teléfono y ábrelo.

---

## 8. Arrancar todo

`start.sh` automatiza el arranque completo: verifica requisitos, arranca Docker, espera a que los servicios estén operativos, lanza el backend FastAPI y crea el túnel ngrok.

### En Linux

```bash
cd ~/app_repartir
./start.sh start
```

### En Windows (terminal WSL2 — Ubuntu)

Primero asegúrate de que Rancher Desktop o Docker Desktop está abierto. Luego:

```bash
cd ~/app_repartir
./start.sh start
```

### Qué hace start.sh

1. Verifica que Docker, Python y ngrok están instalados y el venv existe.
2. Arranca los contenedores OSRM (puerto 5000) y VROOM (puerto 3000).
3. Espera a que OSRM y VROOM respondan correctamente.
4. Lanza el backend FastAPI en background (puerto 8000), con el venv activado.
5. Lanza ngrok y muestra la URL pública.
6. Muestra un resumen con todos los servicios y URLs.

### Otros comandos

```bash
./start.sh stop      # Detener todo (ngrok, backend, Docker)
./start.sh restart   # Reiniciar todo
./start.sh status    # Ver estado de cada servicio
./start.sh logs      # Ver últimos logs de todos los servicios
```

---

## 9. Verificación

Ejecuta en terminal Linux o WSL2 para confirmar que todo funciona:

```bash
# 1. Backend FastAPI
curl http://localhost:8000/health
# → {"status":"ok","version":"2.0.0"}

# 2. OSRM (motor de rutas)
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep '"code"'
# → "code":"Ok"

# 3. VROOM (optimizador TSP)
curl -o /dev/null -s -w "%{http_code}\n" http://localhost:3000/health
# → 200

# 4. ngrok (túnel público)
curl -s http://127.0.0.1:4040/api/tunnels | grep public_url
# → "public_url":"https://xxxx.ngrok-free.app"

# 5. Swagger UI — abre en el navegador:
#    http://localhost:8000/docs
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

El fichero `.osrm` no existe. Repite el **paso 4** completo (descarga + procesado del mapa).

```bash
# Verifica que los ficheros existen:
ls osrm/
# Debe haber archivos: andalucia-latest.osrm, .osrm.partition, .osrm.cells, etc.
```

### Backend falla al importar módulos

El entorno virtual no está activado. `start.sh` lo activa automáticamente, pero si arrancas manualmente:

```bash
cd ~/app_repartir
source venv/bin/activate
uvicorn app.main:app --port 8000
```

### Backend falla con "GOOGLE_API_KEY not found" o errores de geocodificación

El fichero `.env` no existe o la clave no es válida:

```bash
cat .env
# Debe mostrar: GOOGLE_API_KEY=AIza...
```

Si no existe: `echo "GOOGLE_API_KEY=tu-clave" > .env`

### `docker compose up -d` falla: "permission denied" (Linux)

El usuario no está en el grupo docker:

```bash
sudo usermod -aG docker $USER
newgrp docker
# Si no funciona, cierra sesión y vuelve a entrar
```

### Docker no funciona desde WSL2 (Windows)

- Verifica que Rancher Desktop o Docker Desktop está abierto.
- En Rancher Desktop: Preferences → WSL → comprueba que Ubuntu está activado.
- En Docker Desktop: Settings → Resources → WSL Integration → activa Ubuntu.
- Reinicia el gestor de contenedores.

### Rancher Desktop — error con `docker compose` o `network_mode: host`

Asegúrate de estar usando el motor **dockerd (moby)**, no containerd/nerdctl:

- Rancher Desktop → Preferences → Container Engine → selecciona **dockerd (moby)** → Apply.
- Reinicia Rancher Desktop.

### WSL2 se queda sin memoria durante el procesado OSRM

WSL2 tiene un límite de RAM por defecto (~50% de la RAM del sistema). Auméntalo creando el fichero `C:\Users\<tu-usuario>\.wslconfig`:

```ini
[wsl2]
memory=6GB
processors=4
```

Aplica los cambios:
```powershell
# En PowerShell de Windows:
wsl --shutdown
# Luego abre Ubuntu de nuevo
```

### Flutter en Windows no conecta al backend en WSL2

`127.0.0.1` desde Windows apunta a Windows, no a WSL2. Obtén la IP de WSL2:

```bash
# En terminal Ubuntu (WSL2):
hostname -I
# Devuelve algo como: 172.24.160.1
```

Usa esa IP en `api_config.dart` durante el desarrollo local. En producción (APK en móvil) usa la URL de ngrok.

### ngrok: "authentication failed" o "ERR_NGROK_105"

```bash
ngrok config add-authtoken <tu-token>
# El token está en: https://dashboard.ngrok.com/get-started/your-authtoken
```

### La app (APK en móvil) no conecta al backend

1. Verifica que ngrok está corriendo: `./start.sh status`
2. Comprueba que `api_config.dart` tiene la URL de ngrok (no `127.0.0.1`).
3. La URL de ngrok cambia cada vez que reinicias ngrok (plan gratuito) — actualiza y recompila el APK.

```bash
# URL actual de ngrok:
curl -s http://127.0.0.1:4040/api/tunnels | grep public_url
```

### VROOM responde 500 en optimizaciones

VROOM necesita comunicarse con OSRM. Verifica que ambos contenedores están activos y VROOM puede ver OSRM:

```bash
docker ps                              # ambos deben aparecer como "Up"
docker logs vroom-posadas --tail 30    # busca errores de conexión a OSRM
```

### La caché de geocodificación está corrupta

```bash
# Borra la caché; se regenerará automáticamente con el siguiente uso
rm app/data/geocode_cache.json
```

---

## Formato del CSV de entrada

```
cliente,direccion,ciudad
Juan García,Calle Gaitán 24,Posadas
María López,Avenida Blas Infante 37,Posadas
```

### Columnas soportadas

| Columna | Obligatoria | Descripción |
|---------|-------------|-------------|
| `cliente` | Sí | Nombre del destinatario |
| `direccion` | Sí | Dirección completa con número de portal |
| `ciudad` | Sí | Debe ser `Posadas` |
| `nota` | No | Nota interna (no afecta a la ruta) |
| `alias` | No | Nombre del negocio; activa la búsqueda en Google Places |

Requisitos:
- Separador: coma (`,`)
- Codificación: UTF-8
- Consulta `data_input/prueba1_nuevo.csv` como referencia

---

*Guía actualizada para Repartidor App v2.0.0 — Marzo 2026*
