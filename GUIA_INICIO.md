# 🚀 Guía de Inicio — Repartidor App

> **Comandos esenciales para levantar el backend y los servicios necesarios**  
> Proyecto: **Repartidor** — Optimización de rutas de reparto (Posadas, Córdoba)  
> Versión: 3.0.0

---

## 📋 Requisitos Previos

Antes de ejecutar, asegúrate de tener instalado:

- **Docker** y **Docker Compose** (servicios OSRM y VROOM)
- **Python 3.10+** con entorno virtual en `/home/mariano/Desktop/app_repartir/venv`
- **ngrok** instalado (para exponer el backend públicamente)

---

## ⚡ Inicio Rápido (Manual)

### 1️⃣ Levantar servicios Docker (OSRM + VROOM)

```bash
cd /home/mariano/Desktop/app_repartir
docker compose up -d
```

**Verificación:**
```bash
docker ps
# Debe mostrar: osrm-posadas (puerto 5000) y vroom-posadas (puerto 3000)
```

**Prueba OSRM:**
```bash
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep -o '"code":"[^"]*"'
# Debe devolver: "code":"Ok"
```

**Prueba VROOM:**
```bash
curl -s http://localhost:3000/health
# Debe devolver: HTTP 200 (sin contenido o mensaje simple)
```

---

### 2️⃣ Arrancar Backend FastAPI

```bash
cd /home/mariano/Desktop/app_repartir
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > backend.log 2>&1 &
```

**Verificación:**
```bash
sleep 2
curl -s http://localhost:8000/health
# Debe devolver: {"status":"ok","version":"2.1.0"}
```

**Ver logs en tiempo real (opcional):**
```bash
tail -f backend.log
# Ctrl+C para salir
```

---

### 3️⃣ Levantar túnel ngrok

```bash
nohup ngrok http 8000 --log=stdout > /tmp/ngrok.log 2>&1 &
```

**Obtener URL pública:**
```bash
sleep 2
grep -Eo 'url=https?://[^ ]+' /tmp/ngrok.log | head -n 1
# Ejemplo: url=https://unpermanently-repairable-devon.ngrok-free.dev
```

**Verificar túnel (navegador):**
- Abrir la URL mostrada + `/health` en el navegador
- Ejemplo: `https://unpermanently-repairable-devon.ngrok-free.dev/health`
- Debe mostrar: `{"status":"ok","version":"2.1.0"}`

**API de ngrok (localhost):**
```bash
curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*"' | head -n 1
# Muestra la URL pública en formato JSON
```

---

## 🛑 Detener Servicios

### Detener backend FastAPI
```bash
# Buscar el proceso
ps aux | grep uvicorn | grep -v grep
# Matar por PID (reemplazar XXXX con el PID mostrado)
kill XXXX
```

### Detener ngrok
```bash
pkill ngrok
```

### Detener Docker
```bash
cd /home/mariano/Desktop/app_repartir
docker compose down
```

---

## 🔍 Verificación Completa del Sistema

### Estado de todos los servicios
```bash
echo "=== DOCKER ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\n=== OSRM (puerto 5000) ==="
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep -o '"code":"[^"]*"' || echo "❌ OSRM no responde"

echo -e "\n=== VROOM (puerto 3000) ==="
curl -s -w "HTTP %{http_code}\n" -o /dev/null http://localhost:3000/health || echo "❌ VROOM no responde"

echo -e "\n=== BACKEND FASTAPI (puerto 8000) ==="
curl -s http://localhost:8000/health || echo "❌ Backend no responde"

echo -e "\n=== NGROK ==="
curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*"' | head -n 1 || echo "❌ ngrok no responde"
```

---

## 📊 Puertos del Sistema

| Puerto | Servicio | Estado Esperado | Comando de Prueba |
|--------|----------|-----------------|-------------------|
| **3000** | VROOM (optimizador) | HTTP 200 | `curl -I http://localhost:3000/health` |
| **5000** | OSRM (motor de rutas) | `"code":"Ok"` | `curl "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false"` |
| **8000** | FastAPI (backend) | `{"status":"ok"}` | `curl http://localhost:8000/health` |
| **4040** | ngrok (API local) | JSON con `public_url` | `curl http://127.0.0.1:4040/api/tunnels` |

---

## 🐛 Troubleshooting

### ❌ "OSRM not responding" o VROOM no arranca

**Causa:** Servicios Docker no iniciados o con errores.

**Solución:**
```bash
cd /home/mariano/Desktop/app_repartir
docker compose down
docker compose up -d
docker logs osrm-posadas
docker logs vroom-posadas
```

---

### ❌ Backend devuelve 503 "VROOM no pudo calcular la ruta"

**Causa:** VROOM no puede conectarse a OSRM.

**Solución:**
```bash
# Verificar que OSRM responde
curl -I http://localhost:5000
# Reiniciar servicios Docker en orden
docker compose down && docker compose up -d
```

---

### ❌ ngrok devuelve "Connection refused"

**Causa:** ngrok no está corriendo o el backend no está en puerto 8000.

**Solución:**
```bash
# Verificar backend
curl http://localhost:8000/health
# Si falla, arrancar backend primero
# Luego iniciar ngrok
pkill ngrok
nohup ngrok http 8000 --log=stdout > /tmp/ngrok.log 2>&1 &
```

---

### ❌ Backend "Address already in use" (puerto 8000 ocupado)

**Causa:** Ya hay un proceso usando el puerto 8000.

**Solución:**
```bash
# Encontrar el proceso
lsof -ti:8000
# Matar el proceso (reemplazar XXXX con el PID)
kill XXXX
# O forzar:
kill -9 XXXX
# Volver a arrancar backend
```

---

### ❌ Contenedores Docker consumen mucha CPU

**Causa:** Peticiones repetidas o VROOM en modo de optimización intensiva.

**Solución:**
```bash
# Ver uso de recursos
docker stats --no-stream
# Si es necesario, reiniciar servicios
docker compose restart
```

---

## 📚 Documentación Completa

Para más detalles sobre arquitectura, API, Flutter app y troubleshooting avanzado, consulta:

```bash
/home/mariano/Desktop/app_repartir/DOCUMENTACION.md
```

---

## 🎯 Uso con Script Automático

El proyecto incluye un script `start.sh` que automatiza todo el proceso:

```bash
cd /home/mariano/Desktop/app_repartir
chmod +x start.sh
./start.sh
```

El script:
- ✅ Verifica requisitos (Docker, Python venv, ngrok)
- ✅ Inicia servicios Docker en orden correcto
- ✅ Espera a que OSRM y VROOM estén listos (health checks)
- ✅ Inicia el backend FastAPI
- ✅ Inicia ngrok y captura la URL pública
- ✅ Realiza pruebas de conectividad completas
- ✅ Muestra resumen visual con colores y emojis
- ✅ Opción para detener todos los servicios de forma limpia

---

*Última actualización: Febrero 2026 — v3.0.0*
