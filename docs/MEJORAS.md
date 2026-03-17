# Roadmap — Repartidor App

> Documento vivo. Actualizar al cerrar cada fase.
> Versión base: **1.0.0** — Marzo 2026

---

## Índice

- [Fase 0 — Testeo con repartidor](#fase-0--testeo-con-repartidor)
- [Fase 1 — Producción: despliegue en Azure](#fase-1--producción-despliegue-en-azure)
- [Fase 2 — Otros pueblos: multi-zona ligero](#fase-2--otros-pueblos-multi-zona-ligero)
- [Fase 3 — App escalable](#fase-3--app-escalable)
- [Deuda técnica persistente](#deuda-técnica-persistente)

---

## Fase 0 — Testeo con repartidor

**Objetivo:** Pulir el proyecto actual con un repartidor real. No añadir funcionalidades grandes, solo corregir lo que el uso real descubra y mejorar los puntos débiles conocidos.

### Pendiente técnico

| Item | Descripción | Prioridad |
|------|-------------|-----------|
| Mejora editor de mapa | `MapEditorScreen` es funcional pero necesita pulido: mejor UX al seleccionar/editar vías, feedback visual más claro al guardar y rebuildar | Alta |
| Límite de filas CSV | Añadir validación `if rows > 500: error` en `CsvService` antes de parsear. Evita OOM en el móvil con ficheros grandes | Alta |
| Barra de progreso en geocodificación | El spinner dura minutos sin feedback. Mostrar `"Geocodificando X/N direcciones..."` con contador progresivo en `ImportScreen` | Alta |
| Mostrar confianza en validación | Los stops `GOOD` (interpolado, puede estar a 100 m del portal) y `EXACT_ADDRESS` tienen el mismo icono verde. Diferenciarlos: ✅ Exacto / 🟡 Aproximado / 📍 Lugar | Media |
| Editar texto de dirección fallida | Cuando una dirección falla geocodificación, solo existe la opción de poner pin manual. Añadir edición del texto para corregir typos y reintentar sin reimportar el CSV completo | Media |
| Pantalla resumen post-reparto | Al completar el reparto, mostrar: entregados / ausentes / distancia total / tiempo empleado. Con botón para compartir o exportar | Media |
| Error handler global en FastAPI | `@app.exception_handler(Exception)` que loguee internamente y devuelva `{"error": "Error interno"}`. Evita exponer stack traces al cliente | Media |

### Cambios de diseño del repartidor

> Anotar aquí los cambios que pida el repartidor durante el testeo.

- [ ] *Pendiente de feedback*

---

## Fase 1 — Producción: despliegue en Azure

**Objetivo:** Pasar de entorno local a una VM Azure estable. La app funciona para un repartidor (o dos) sin depender de que el PC del desarrollador esté encendido ni de una URL ngrok cambiante.

### 1.1 Infraestructura Azure

**Máquina recomendada:** Azure VM Ubuntu 22.04 — serie **B2s** (2 vCPU, 4 GB RAM) para empezar, escalar a **B2ms** (8 GB) si OSRM lo necesita.

| Tarea | Detalle |
|-------|---------|
| Provisionar VM (Ubuntu 22.04 LTS) | Abrir puertos 80 y 443. Puerto 8000 solo accesible desde localhost (nginx hace proxy) |
| Dominio propio + SSL | Asociar dominio (p.ej. `repartidor.ejemplo.com`) + certificado Let's Encrypt con Certbot. Elimina ngrok definitivamente |
| Nginx como reverse proxy | Nginx escucha en 443, hace proxy a FastAPI en 8000. Configurar `proxy_read_timeout 600` para geocodificaciones largas |
| Docker en la VM | Docker Engine + Docker Compose. Migrar `docker-compose.yml` tal cual |
| LKH3 en la VM | Compilar o copiar el binario. Verificar ruta en `config.py` |
| Datos OSRM | Subir `osrm/` a la VM vía `rsync`. ~800 MB. Si el tamaño crece, mover a Azure Blob Storage |
| `.env` en la VM | `GOOGLE_API_KEY` y futura `API_KEY` de la app. Nunca en el repositorio |
| Backend como servicio systemd | El backend arranca automáticamente al reiniciar la VM y se reinicia si cae |
| Backup automático de caché | Cron diario que copia `app/data/` a Azure Blob Storage. Previene perder el geocoding cache si se destruye la VM |

**Configuración systemd:**
```ini
# /etc/systemd/system/repartidor.service
[Unit]
Description=Repartidor Backend
After=network.target docker.service

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/app_repartir
EnvironmentFile=/home/ubuntu/app_repartir/.env
ExecStart=/home/ubuntu/app_repartir/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 1.2 CI/CD con GitHub Actions

Push a `main` → tests → deploy automático a la VM.

```
.github/workflows/
├── test.yml      ← en cada PR: pytest + mypy + dart analyze
└── deploy.yml    ← en push a main (tras tests): SSH → git pull → restart
```

**`test.yml`** (en cada PR y push):
- Setup Python 3.10 + `pip install -r requirements.txt`
- `python -m pytest` (solo tests puros, sin OSRM ni Google API)
- `python -m mypy app/`
- Setup Flutter SDK + `flutter analyze`
- `flutter test` (tests unitarios Flutter)

**`deploy.yml`** (solo en push a `main` tras pasar tests):
- SSH a la VM con clave almacenada en GitHub Secrets
- `git pull origin main`
- `pip install -r requirements.txt` (si hay cambios de dependencias)
- `systemctl restart repartidor`
- Health check: `curl http://localhost:8000/health`

**Secrets de GitHub necesarios:**
```
AZURE_VM_HOST       IP o dominio de la VM
AZURE_VM_USER       Usuario SSH (p.ej. ubuntu)
AZURE_VM_SSH_KEY    Clave privada SSH (generada para este propósito)
```

### 1.3 Autenticación básica

Sin auth, cualquiera con la URL puede agotar la cuota de Google o inyectar datos.

| Tarea | Detalle |
|-------|---------|
| API key en header | Middleware FastAPI que verifica `X-API-Key` en todas las peticiones. La key se define en `.env` como `APP_API_KEY` |
| Flutter | Añadir `X-API-Key` como header fijo en `ApiService`. La key se compila en el APK (aceptable para uso interno de un solo repartidor) |
| Rate limiting | `slowapi`: máx. 1 req/s por IP en endpoints de geocodificación. Evita abuso accidental o intencionado |

### 1.4 Nuevas funcionalidades

| Item | Descripción |
|------|-------------|
| **Agente CSV** | Dado un fichero (Excel, PDF, imagen de albarán...), un agente LLM lo transforma automáticamente al formato CSV de la app. *Diseño y prompt pendiente — solo apuntado* |
| **Dos repartidores** | Dividir la ruta optimizada entre dos conductores de forma inteligente. *El diseño de particionado y la UI se definirán aparte — solo apuntado* |
| Pinear versiones Python | `pip freeze > requirements.lock`. Usar ese fichero en la VM para reproducibilidad exacta |
| Retry en llamadas HTTP | `tenacity`: 3 reintentos con backoff 1s/2s/4s en llamadas a Google API y OSRM. Cubre el 99% de fallos transitorios de red |

### 1.5 Actualizar app Flutter para producción

- Cambiar `api_config.dart` de ngrok a la URL fija del dominio
- Añadir header `X-API-Key`
- Compilar APK release y distribuir al repartidor

---

## Fase 2 — Otros pueblos: multi-zona ligero

**Objetivo:** Permitir que el sistema funcione en otros municipios sin rediseño de arquitectura. Simple, para validar con 2-3 pueblos antes de invertir en la infraestructura de Fase 3.

### 2.1 Configuración por zona

Cada zona tiene su propia configuración en `app/data/zones.json`:

```json
{
  "posadas": {
    "name": "Posadas",
    "depot_lat": 37.805503,
    "depot_lon": -5.099805,
    "google_city_hint": "Posadas, Córdoba",
    "overpass_bbox": "37.77,-5.14,37.84,-5.07"
  },
  "palma_rio": {
    "name": "Palma del Río",
    "depot_lat": 37.700,
    "depot_lon": -5.280,
    "google_city_hint": "Palma del Río, Córdoba",
    "overpass_bbox": "37.67,-5.32,37.73,-5.24"
  }
}
```

El endpoint `/optimize` acepta `zone_id` opcional (default: zona principal). La app Flutter añade selector de zona.

### 2.2 Separación de cachés por zona

Cada zona tiene su propia carpeta de datos:
```
app/data/
├── posadas/
│   ├── geocode_cache.json
│   ├── learned_streets.json
│   └── snap_cache.json
└── palma_rio/
    ├── geocode_cache.json
    └── ...
```

### 2.3 Autenticación por zona

Ampliar el sistema de API key a tokens con zona asignada: `{token: zone_id}` en un fichero de configuración. Sin base de datos todavía.

### 2.4 Panel web de administración (básico)

Interfaz web mínima (FastAPI + Jinja2, sin frontend separado) para:
- Ver zonas y su estado (OSRM activo, nº entradas en caché, última geocodificación)
- Añadir o editar zonas sin tocar JSON a mano
- Forzar limpieza de caché de una zona
- Ver qué direcciones fallan repetidamente en cada zona

### 2.5 Mapa OSRM multi-zona

Opciones por orden de complejidad:

1. **Mapa de Andalucía completo** ← ya lo tenemos. Cubre todos los pueblos de Andalucía sin cambios. Recomendado para empezar
2. **Mapas por provincia** — si el mapa completo genera latencia alta. Procesar PBFs de Geofabrik por provincia
3. **OSRM multi-instancia** — solo si el mapa único se queda insuficiente

---

## Fase 3 — App escalable

**Objetivo:** Rediseñar la base técnica para soportar múltiples empresas, múltiples repartidores, historial completo y un producto comercializable.

### 3.1 Base de datos — PostgreSQL

Migrar de ficheros JSON a **Azure Database for PostgreSQL - Flexible Server**.

**Esquema principal:**
```sql
tenants           -- empresas/clientes
users             -- repartidores y admins (tenant_id)
zones             -- configuración de zona por tenant
geocode_cache     -- caché geocodificación con TTL (reemplaza JSON)
snap_cache        -- caché OSRM snap (reemplaza JSON)
delivery_sessions -- historial de repartos
delivery_stops    -- paradas por sesión con estado final y metadata
```

**Ventajas clave:**
- Lookup O(log n) en geocoding cache (vs O(n) en JSON)
- Sin race conditions en escrituras concurrentes
- Historial de repartos consultable y exportable
- Borrado selectivo por cliente (GDPR)
- Backup y restore nativos de Azure

### 3.2 Workers y geocodificación paralela

| Componente | Herramienta | Propósito |
|------------|-------------|-----------|
| Cola de tareas | Celery + Redis | Geocodificación asíncrona en batch |
| Cache distribuida | Azure Cache for Redis | Backend de Celery + caché de sesiones |
| Progreso en tiempo real | Polling `GET /api/validation/{job_id}/status` | Flutter muestra `"Geocodificando 45/70..."` |

**Flujo con workers:**
1. `POST /api/validation/start` → crea job, devuelve `{job_id}` de forma inmediata
2. Celery lanza hasta 10 geocodificaciones en paralelo (semáforo para no superar rate limit de Google)
3. Flutter hace polling cada 2s para ver progreso
4. Al terminar: `GET /api/validation/{job_id}/result`

**Resultado:** 100 direcciones pasan de ~80s a ~10s.

### 3.3 Autenticación JWT

| Aspecto | Detalle |
|---------|---------|
| Implementación | `python-jose` + `passlib`. Endpoints `/auth/login` y `/auth/refresh` |
| Roles | `superadmin` / `admin` (gestiona su tenant) / `repartidor` (solo reparto) |
| Flutter | Token en `flutter_secure_storage`. Header `Authorization: Bearer {token}` |
| Expiración | Access token 8h, refresh token 30 días |

### 3.4 Infraestructura escalable en Azure

| Componente | Servicio Azure |
|------------|----------------|
| Backend FastAPI | Azure Container Apps (escala automática, pago por uso) |
| Base de datos | Azure Database for PostgreSQL Flexible Server (B1ms → escalar según carga) |
| Redis | Azure Cache for Redis (C0 básico) |
| OSRM | Azure VM dedicada (B2ms) — no escala horizontalmente |
| Imágenes Docker | Azure Container Registry |
| Ficheros / APKs | Azure Blob Storage + CDN |
| CI/CD | GitHub Actions → ACR → Container Apps (rolling deploy) |
| Monitorización | Azure Application Insights: latencia, errores, coste Google API |

### 3.5 Multi-tenant completo

| Aspecto | Detalle |
|---------|---------|
| Aislamiento | `tenant_id` en todas las tablas. Row-level security en PostgreSQL |
| Configuración | Cada empresa: su propio depot, zona, cuota de Google API |
| Panel superadmin | Gestión de tenants, uso de API, facturación estimada |
| Onboarding | `POST /admin/tenants` crea tenant + admin + zona inicial |

### 3.6 Funcionalidades de producto

| Funcionalidad | Descripción |
|---------------|-------------|
| Historial de repartos | Sesiones anteriores: paradas, entregados/ausentes, distancia, duración. Exportable a CSV |
| Foto de entrega | Al marcar "Entregado", adjuntar foto con `image_picker`. Se sube a Blob Storage y se asocia a la parada |
| Notificación al destinatario | SMS o WhatsApp (Twilio) cuando el repartidor está a N paradas. Reduce ausencias |
| Ventanas de tiempo | Columnas `hora_desde`/`hora_hasta` en el CSV. Restricciones de horario por parada en LKH3 |
| App iOS | Activar target iOS en Flutter. Signing, permisos `Info.plist`, publicación App Store |
| Optimización con tráfico real | Integración con Google Route Optimization API para rutas con tráfico en tiempo real |
| Zero-downtime OSRM updates | Dos instancias OSRM (A/B), nginx hace swap sin cortar servicio al actualizar el mapa |

---

## Deuda técnica persistente

Items que aplican a todas las fases. Resolver en la primera oportunidad razonable.

| Item | Impacto | Fase recomendada |
|------|---------|-----------------|
| Geocodificación secuencial (1 dirección a la vez) | Lentitud con >30 direcciones | 1 (parcial) / 3 (completo con workers) |
| Sin retry en llamadas HTTP externas | Fallos transitorios de red cancelan toda la operación | 1 |
| Dependencias Python sin versión fija | Actualizaciones automáticas pueden romper en producción | 1 |
| `start.sh` con ruta hardcodeada del desarrollador | No funciona en otras máquinas sin editar manualmente | 1 |
| Race condition en caché geocodificación (multi-worker) | Solo relevante con múltiples workers Uvicorn | 3 |

---

*Última actualización: Marzo 2026 — v1.0.0*
