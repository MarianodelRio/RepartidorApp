# 🎯 Script de Inicio Automático — Repartidor App

Este script (`start.sh`) automatiza completamente el inicio, detención y verificación de todos los servicios necesarios para ejecutar la aplicación Repartidor.

---

## 📦 ¿Qué hace el script?

El script gestiona **4 servicios principales**:

1. **OSRM** (Docker) — Motor de rutas en puerto 5000
2. **VROOM** (Docker) — Optimizador TSP/VRP en puerto 3000
3. **Backend FastAPI** — API REST en puerto 8000
4. **ngrok** — Túnel público para acceso remoto

---

## 🚀 Uso Rápido

```bash
cd /home/mariano/Desktop/app_repartir

# Iniciar todos los servicios
./start.sh start
# o simplemente:
./start.sh

# Ver el estado de los servicios
./start.sh status

# Detener todos los servicios
./start.sh stop

# Reiniciar todos los servicios
./start.sh restart
```

---

## 📋 Comandos Disponibles

### `./start.sh start` (por defecto)

Inicia todos los servicios en el siguiente orden:

1. **Verificación de requisitos**
   - Comprueba que Docker, Python, ngrok y el entorno virtual están instalados
   
2. **Servicios Docker**
   - Ejecuta `docker compose up -d`
   - Espera a que OSRM responda correctamente (hasta 30 segundos)
   - Espera a que VROOM responda correctamente (hasta 30 segundos)
   
3. **Backend FastAPI**
   - Activa el entorno virtual Python
   - Inicia uvicorn en background (puerto 8000)
   - Espera a que el endpoint `/health` responda
   - Muestra la versión del backend
   
4. **Túnel ngrok**
   - Inicia ngrok en background
   - Captura la URL pública generada
   - Verifica que la URL pública responde
   
5. **Resumen completo**
   - Muestra tabla con todos los servicios activos
   - URLs de acceso local y público
   - Comandos útiles para logs y gestión

**Ejemplo de salida:**
```
════════════════════════════════════════════════════════════
  🚀 Repartidor App - Inicio de Servicios v3.0.0
════════════════════════════════════════════════════════════

▶ Verificando requisitos previos...
  ✓ docker está instalado
  ✓ docker compose está instalado
  ✓ python3 está instalado
  ✓ ngrok está instalado
  ✓ Entorno virtual Python encontrado
  ✓ Directorio del proyecto encontrado

▶ Iniciando servicios Docker (OSRM + VROOM)...
  ✓ Servicios Docker iniciados

▶ Verificando servicios Docker...
  Esperando a OSRM (puerto 5000)... ✓
  ✓ OSRM está operativo
  Esperando a VROOM (puerto 3000)... ✓
  ✓ VROOM está operativo

▶ Iniciando backend FastAPI (puerto 8000)...
  ℹ Backend iniciado con PID: 12345

  Esperando a Backend... ✓
  ✓ Backend está operativo
  ℹ Versión: 2.1.0
  ℹ Docs: http://localhost:8000/docs

▶ Iniciando túnel ngrok...
  ℹ ngrok iniciado con PID: 12346
  ✓ Túnel ngrok creado
  ℹ URL pública: https://unpermanently-repairable-devon.ngrok-free.dev
  ℹ Panel ngrok: http://127.0.0.1:4040
  Verificando acceso público ✓
  ✓ Backend accesible públicamente

════════════════════════════════════════════════════════════
  ✨ Todos los servicios están operativos
════════════════════════════════════════════════════════════

Servicios Docker:
NAMES           STATUS              PORTS
osrm-posadas    Up 2 minutes        0.0.0.0:5000->5000/tcp
vroom-posadas   Up 2 minutes        (host network)

Puertos locales:
  • OSRM:    http://localhost:5000
  • VROOM:   http://localhost:3000
  • Backend: http://localhost:8000
  • Swagger: http://localhost:8000/docs

Acceso público (ngrok):
  • URL: https://unpermanently-repairable-devon.ngrok-free.dev
  • Health: https://unpermanently-repairable-devon.ngrok-free.dev/health
  • Panel ngrok: http://127.0.0.1:4040

Logs:
  • Backend: tail -f /home/mariano/Desktop/app_repartir/backend.log
  • ngrok:   tail -f /tmp/ngrok.log
  • OSRM:    docker logs osrm-posadas -f
  • VROOM:   docker logs vroom-posadas -f

Comandos útiles:
  • Detener todo: ./start.sh stop
  • Ver estado:   ./start.sh status
  • Reiniciar:    ./start.sh restart
```

---

### `./start.sh status`

Muestra el estado actual de todos los servicios **sin iniciar ni detener nada**.

Información mostrada:
- Estado de contenedores Docker (nombres, status, puertos)
- PID del backend FastAPI y resultado del health check
- Estado de ngrok y URL pública activa

**Uso típico:** Verificar si los servicios están corriendo antes de usar la app.

---

### `./start.sh stop`

Detiene todos los servicios de forma limpia y ordenada:

1. Detiene ngrok (`pkill ngrok`)
2. Detiene el backend FastAPI (envía señal SIGTERM, luego SIGKILL si es necesario)
3. Detiene los contenedores Docker (`docker compose down`)

**Salida típica:**
```
▶ Deteniendo servicios...
  ✓ ngrok detenido
  ✓ Backend detenido (PID: 12345)
  ✓ Servicios Docker detenidos

  ✓ Todos los servicios detenidos
```

---

### `./start.sh restart`

Equivalente a ejecutar `stop` seguido de `start` con una pausa de 2 segundos entre ambos.

**Uso típico:** Cuando has modificado código del backend o configuración de Docker.

---

## 🛡️ Características de Seguridad

### ✅ Verificación de requisitos previos

El script valida que están instalados:
- Docker y Docker Compose
- Python 3
- ngrok
- Entorno virtual Python en la ruta esperada
- Directorio del proyecto

Si falta alguno, el script **se detiene** y muestra un mensaje de error claro.

---

### ✅ Health checks automáticos

El script **no continúa** hasta que cada servicio responde correctamente:

- **OSRM:** Espera hasta 30 segundos a que responda con `"code":"Ok"` en una petición de ruta de prueba
- **VROOM:** Espera hasta 30 segundos a que devuelva HTTP 200 en `/health`
- **Backend:** Espera hasta 30 segundos a que `/health` devuelva `{"status":"ok"}`
- **ngrok:** Extrae y verifica la URL pública generada

Si algún servicio no responde a tiempo, el script muestra el **timeout** y los **logs relevantes** del servicio problemático.

---

### ✅ Detección de servicios ya corriendo

Si intentas ejecutar `./start.sh start` y los servicios ya están activos, el script:
- Detecta que están corriendo
- Muestra una advertencia (⚠)
- **No los reinicia** (evita interrupciones)
- Continúa con el siguiente paso

---

### ✅ Logs persistentes

- **Backend:** Se guarda en `backend.log` en el directorio del proyecto
- **ngrok:** Se guarda en `/tmp/ngrok.log`
- Ambos se pueden seguir en tiempo real con `tail -f`

---

## 🎨 Salida Visual

El script usa **colores y emojis** para una lectura rápida:

| Símbolo | Color | Significado |
|---------|-------|-------------|
| ✓ | Verde | Operación exitosa |
| ✗ | Rojo | Error o fallo |
| ⚠ | Amarillo | Advertencia o situación no crítica |
| ℹ | Cyan | Información adicional |
| ▶ | Azul | Inicio de una nueva sección |

---

## 🔧 Troubleshooting

### El script falla en "Esperando a OSRM"

**Causa:** OSRM no arrancó correctamente o los datos `.osrm` están corruptos.

**Solución:**
```bash
docker logs osrm-posadas --tail 50
# Si ves errores de "Cannot open file", regenera los datos OSRM
```

---

### El script falla en "Esperando a VROOM"

**Causa:** VROOM no puede conectarse a OSRM (necesita OSRM activo para funcionar).

**Solución:**
```bash
# Verificar que OSRM responde
curl "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false"

# Ver logs de VROOM
docker logs vroom-posadas --tail 50
```

---

### "Backend already in use" (puerto 8000 ocupado)

**Causa:** Ya hay un proceso usando el puerto 8000.

**Solución:**
```bash
# Opción 1: Usar el script para detener
./start.sh stop

# Opción 2: Manual
lsof -ti:8000 | xargs kill
```

---

### ngrok no muestra URL pública

**Causa:** ngrok puede tardar unos segundos en conectarse o puede haber problemas de red.

**Solución:**
```bash
# Ver logs de ngrok
tail -f /tmp/ngrok.log

# Reiniciar ngrok
pkill ngrok
./start.sh start
```

---

### "docker compose: command not found"

**Causa:** Docker Compose no está instalado o la versión de Docker es antigua.

**Solución:**
```bash
# Para Docker moderno (>= 20.10):
docker compose version

# Para Docker antiguo:
docker-compose version

# Instalar Docker Compose plugin si falta:
sudo apt install docker-compose-plugin
```

---

## 📊 Estructura de Procesos

Cuando el script está corriendo completamente, estos son los procesos activos:

```
┌─ Servicios Docker ─────────────────────┐
│                                         │
│  osrm-posadas    (puerto 5000)         │
│  vroom-posadas   (network: host)       │
│                                         │
└─────────────────────────────────────────┘

┌─ Procesos Python ──────────────────────┐
│                                         │
│  uvicorn (PID: XXXX)                   │
│    ├─ worker (PID: YYYY)               │
│    └─ reloader (si --reload activo)    │
│                                         │
└─────────────────────────────────────────┘

┌─ Túnel ngrok ──────────────────────────┐
│                                         │
│  ngrok (PID: ZZZZ)                     │
│    └─ tunnel: BACKEND_PORT → URL       │
│                                         │
└─────────────────────────────────────────┘
```

---

## 🧹 Limpieza Manual (si el script falla)

Si por alguna razón el script no detiene correctamente los servicios:

```bash
# Detener todos los procesos relacionados
pkill ngrok
pkill -f "uvicorn app.main:app"
docker compose -f /home/mariano/Desktop/app_repartir/docker-compose.yml down

# Liberar el puerto 8000 si sigue ocupado
lsof -ti:8000 | xargs kill -9

# Verificar que todo está limpio
docker ps
ss -ltnp | grep -E ':(5000|8000|3000)\s'
pgrep ngrok
```

---

## 📚 Recursos Relacionados

- **Guía de Inicio Manual:** `GUIA_INICIO.md` — Comandos paso a paso sin el script
- **Documentación Completa:** `DOCUMENTACION.md` — Arquitectura, API, troubleshooting avanzado
- **Logs:**
  - Backend: `backend.log` (en el directorio del proyecto)
  - ngrok: `/tmp/ngrok.log`
  - Docker: `docker logs <nombre_contenedor>`

---

## 🎯 Flujo de Trabajo Recomendado

### Desarrollo diario

```bash
# Al empezar el día
./start.sh start

# Trabajar normalmente...
# (editar código, probar en la app, etc.)

# Ver logs en tiempo real si es necesario
tail -f backend.log

# Al terminar
./start.sh stop
```

---

### Después de cambios en el código

```bash
# El backend se recarga automáticamente (--reload)
# No necesitas reiniciar nada

# Si cambiaste configuración de Docker:
./start.sh restart
```

---

### Resolución de problemas

```bash
# Ver estado de todo
./start.sh status

# Si algo falla, reiniciar
./start.sh restart

# Si persiste el problema, detener todo y revisar logs
./start.sh stop
docker logs osrm-posadas
docker logs vroom-posadas
tail -f backend.log
tail -f /tmp/ngrok.log
```

---

## ✨ Características Avanzadas

### Detección inteligente de servicios

El script usa varios métodos para detectar si un servicio está corriendo:

- **Docker:** `docker ps --format '{{.Names}}'` (búsqueda por nombre)
- **Backend:** `lsof -Pi :8000 -sTCP:LISTEN` (búsqueda por puerto)
- **ngrok:** `pgrep -x ngrok` (búsqueda por nombre de proceso)

Esto garantiza que el script **nunca inicia servicios duplicados**.

---

### Timeouts configurables

Si los tiempos de espera son muy cortos para tu sistema, puedes ajustarlos editando las variables en el script:

```bash
# Línea ~30 en start.sh
wait_for_service() {
    local max_attempts="${3:-30}"  # ← Cambiar 30 a un valor mayor
    # ...
}
```

---

### Ejecución en segundo plano persistente

Todos los servicios se inician con `nohup` y redirección de salida, lo que significa que:
- Sobreviven si cierras la terminal
- Los logs se guardan en archivos
- Puedes cerrar SSH y los servicios siguen corriendo

Para detenerlos después de cerrar la terminal:
```bash
ssh usuario@servidor
./start.sh stop
```

---

*Última actualización: Febrero 2026 — v3.0.0*
