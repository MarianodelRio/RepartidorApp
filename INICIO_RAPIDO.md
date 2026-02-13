# ⚡ Inicio Rápido — Repartidor App

> **Una sola página con todo lo esencial para levantar y usar el sistema**

---

## 🎯 Comando Único (Recomendado)

```bash
cd /home/mariano/Desktop/app_repartir && ./start.sh
```

✅ Inicia Docker (OSRM + VROOM)  
✅ Inicia Backend FastAPI  
✅ Inicia túnel ngrok  
✅ Verifica que todo funciona  
✅ Muestra URLs de acceso

---

## 📋 Comandos del Script

```bash
./start.sh          # Iniciar todo
./start.sh status   # Ver estado
./start.sh stop     # Detener todo
./start.sh restart  # Reiniciar todo
```

---

## 🔧 Inicio Manual (paso a paso)

### 1. Docker (OSRM + VROOM)
```bash
cd /home/mariano/Desktop/app_repartir
docker compose up -d
```

### 2. Backend FastAPI
```bash
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > backend.log 2>&1 &
```

### 3. Túnel ngrok
```bash
nohup ngrok http 8000 --log=stdout > /tmp/ngrok.log 2>&1 &
sleep 2
grep -Eo 'url=https?://[^ ]+' /tmp/ngrok.log | head -n 1
```

---

## 🌐 URLs de Acceso

| Servicio | URL | Qué hace |
|----------|-----|----------|
| **Backend Health** | http://localhost:8000/health | Verifica que el backend responde |
| **Swagger Docs** | http://localhost:8000/docs | Documentación interactiva de la API |
| **Panel ngrok** | http://127.0.0.1:4040 | Ver túnel activo y tráfico |
| **OSRM** | http://localhost:5000 | Motor de rutas (interno) |
| **VROOM** | http://localhost:3000 | Optimizador (interno) |

**URL pública (ngrok):**  
Usar el comando o ver en el panel: http://127.0.0.1:4040

---

## ✅ Verificación Rápida

```bash
# Todo en un comando
curl -s http://localhost:8000/health && \
curl -s "http://localhost:5000/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" | grep -q "Ok" && \
curl -s -o /dev/null -w "Backend: %{http_code}\nOSRM: OK\nVROOM: " http://localhost:3000/health && \
echo "✓ Todos los servicios OK"
```

**Salida esperada:**
```
{"status":"ok","version":"2.1.0"}
Backend: 200
OSRM: OK
VROOM: 200
✓ Todos los servicios OK
```

---

## 🛑 Detener Todo

### Automático (recomendado)
```bash
./start.sh stop
```

### Manual
```bash
pkill ngrok
pkill -f uvicorn
docker compose down
```

---

## 📊 Ver Logs

```bash
# Backend
tail -f backend.log

# ngrok
tail -f /tmp/ngrok.log

# Docker
docker logs osrm-posadas -f
docker logs vroom-posadas -f
```

---

## 🐛 Troubleshooting Express

| Problema | Solución |
|----------|----------|
| Puerto 8000 ocupado | `lsof -ti:8000 \| xargs kill` |
| Docker no arranca | `docker compose down && docker compose up -d` |
| Backend no responde | `tail -f backend.log` (ver errores) |
| ngrok sin URL | `tail -f /tmp/ngrok.log` (ver conexión) |

---

## 📱 Usar con la App Flutter

1. **Backend debe estar corriendo** (verificar con http://localhost:8000/health)
2. **ngrok debe estar activo** (ver URL en http://127.0.0.1:4040)
3. **La app usa automáticamente** la URL configurada: `https://unpermanently-repairable-devon.ngrok-free.dev`
4. **Abrir la app** → debe mostrar 🟢 Online en la AppBar

Si muestra 🔴 Offline:
- Verificar que backend responde: `curl http://localhost:8000/health`
- Verificar que ngrok está activo: `curl http://127.0.0.1:4040/api/tunnels`
- Reiniciar servicios: `./start.sh restart`

---

## 📚 Documentación Completa

- **Script detallado:** `README_SCRIPT.md`
- **Guía manual:** `GUIA_INICIO.md`
- **Documentación técnica:** `DOCUMENTACION.md`

---

## 🎯 Workflow Diario

```bash
# Por la mañana
cd /home/mariano/Desktop/app_repartir
./start.sh

# Trabajar...
# (La app Flutter se conecta automáticamente)

# Por la noche
./start.sh stop
```

**Nota:** El backend se recarga automáticamente al cambiar código Python (flag `--reload`). No necesitas reiniciar para ver cambios.

---

*Repartidor App v3.0.0 — Posadas, Córdoba, España*
