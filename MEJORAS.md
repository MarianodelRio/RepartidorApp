# MEJORAS — App Repartir

> Análisis de producto completo. Fecha: marzo 2026. Versión analizada: 2.0.0
> Cubre backend FastAPI, app Flutter, infraestructura, arquitectura y producto.

---

## Índice

1. [Fallos críticos y potenciales](#1-fallos-críticos-y-potenciales)
2. [Mejoras inmediatas](#2-mejoras-inmediatas-esta-semana)
3. [Corto plazo](#3-corto-plazo-1-2-meses)
4. [Medio plazo](#4-medio-plazo-3-6-meses)
5. [Largo plazo](#5-largo-plazo-6-meses)
6. [Resumen por impacto/esfuerzo](#6-resumen-por-impactoesfuerzo)

---

## 1. Fallos Críticos y Potenciales

### 🔴 CRIT-001 — URL ngrok hardcodeada en la app

**Archivo:** `flutter_app/lib/config/api_config.dart:12`

El free tier de ngrok no garantiza la misma URL en cada reinicio. La URL `https://unpermanently-repairable-devon.ngrok-free.dev` está compilada en el APK. Cuando el túnel se regenera, todos los teléfonos con la app instalada dejan de funcionar hasta que se recompile y redistribuya un nuevo APK.

**Impacto:** La app deja de funcionar completamente en producción de forma silenciosa.
**Fix:** Usar ngrok paid (URL reservada estática) o pasar a infraestructura real (dominio propio + SSL).

---

### 🔴 CRIT-002 — API sin ninguna autenticación

**Archivo:** `app/main.py`, `app/routers/*.py`

Todos los endpoints son públicos. Cualquiera con la URL del ngrok puede:
- Agotar la cuota de Google Geocoding (hasta factura inesperada)
- Inyectar coordenadas incorrectas vía `/api/validation/override`
- Hacer DoS enviando CSVs de miles de filas
- Leer el caché de geocodificación (direcciones reales de clientes)

**Fix inmediato:** API key simple en header `X-API-Key` verificada en middleware. Largo plazo: JWT.

---

### 🔴 CRIT-003 — Pérdida de estado si la app se cierra durante el reparto

**Archivo:** `flutter_app/lib/screens/delivery_screen.dart`, `persistence_service.dart`

El estado se persiste en Hive después de actualizar la UI. Si la app se mata entre la actualización de pantalla y el `saveSession()`, la entrega marcada se pierde. El repartidor cree que marcó "entregado" pero al reabrir la app el paquete vuelve a aparecer como pendiente.

**Fix:** Persistir primero, actualizar UI después. Añadir `onWillPop` que fuerce guardado antes de salir.

---

### 🔴 CRIT-004 — Sin límite de tamaño en el CSV importado

**Archivo:** `flutter_app/lib/services/csv_service.dart`

Un CSV con 100.000 filas se procesa en memoria sin ningún límite. El móvil puede quedarse sin memoria y la app crashear sin mensaje de error útil.

**Fix:** Añadir validación `if (lines.length > 2000) throw FormatException(...)` antes de parsear.

---

### 🔴 CRIT-005 — Race condition en caché de geocodificación

**Archivo:** `app/services/geocoding.py:600-615`

El chequeo de TTL y la eliminación del entry caducado son dos operaciones separadas (TOCTOU). Con múltiples workers uvicorn, un thread puede leer una entrada mientras otro la borra, o viceversa.

**Fix:** Usar `threading.Lock` alrededor de todas las operaciones de lectura/escritura del dict `_cache`.

---

### 🟠 HIGH-001 — Geocodificación en batch completamente secuencial

**Archivo:** `app/services/geocoding.py:geocode_batch()`

Con 100 direcciones, cada geocodificación espera a que termine la anterior. Si Google tarda 500ms por dirección: 50 segundos de espera mínimo. Con timeouts puede llegar a minutos. El cliente Flutter tiene timeout de 10 minutos pero el usuario abandona antes.

**Fix:** Paralelizar con `asyncio.gather()` o `ThreadPoolExecutor` (máx. 10 concurrent para no superar rate limits).

---

### 🟠 HIGH-002 — Sin manejo de errores global en FastAPI

**Archivo:** `app/main.py`

Excepciones no controladas devuelven stack trace completo al cliente o un 500 vacío. Expone rutas internas, versiones de librerías, etc.

**Fix:** Añadir `@app.exception_handler(Exception)` que loguee internamente y devuelva `{"error": "Error interno"}`.

---

### 🟠 HIGH-003 — Distribución desequilibrada con múltiples vehículos

**Archivo:** `app/services/routing.py:optimize_route()`

VROOM sin restricciones de capacidad puede asignar `[24, 28, 2]` paradas a 3 vehículos — un conductor hace 2 entregas mientras los otros hacen 26. No hay ningún límite mínimo ni máximo por vehículo.

**Fix:** Añadir `capacity` a vehículos y `delivery: [1]` a jobs para forzar distribución equilibrada.

---

### 🟠 HIGH-004 — Sin validación de coordenadas entrantes en /optimize

**Archivo:** `app/routers/optimize.py:204-232`

Las coords pre-resueltas (`req.coords`) se usan directamente sin validar. Valores NaN, infinito, o lat/lon invertidos llegan a OSRM y producen errores 500 indescifrables para el usuario.

**Fix:** Validar `lat ∈ [-90,90]`, `lon ∈ [-180,180]`, detectar posibles inversiones (lon > 0 en España es sospechoso).

---

### 🟠 HIGH-005 — Sin reintentos en llamadas HTTP externas

**Archivo:** `app/services/geocoding.py`, `app/services/routing.py`

Google API, OSRM y VROOM fallan sin reintento ante cualquier error transitorio (timeout, 503, reset de conexión). Un fallo de 1 segundo en Google cancela la geocodificación de todo el lote.

**Fix:** Implementar retry con backoff exponencial (librería `tenacity`): 3 reintentos, espera 1s/2s/4s.

---

### 🟠 HIGH-006 — GDPR: datos de clientes en caché sin expiración ni borrado

**Archivo:** `app/data/geocode_cache.json`

El fichero JSON almacena direcciones reales de clientes indefinidamente. No hay endpoint para borrar una entrada concreta. Posible incumplimiento del derecho al olvido (GDPR Art. 17).

**Fix:** Añadir `DELETE /api/cache` con autenticación; asegurar que el TTL de 30 días también aplica a entradas sin fuente Google.

---

### 🟠 HIGH-007 — Dependencias Python sin versión fija

**Archivo:** `requirements.txt`

`fastapi`, `uvicorn`, `httpx` sin pin de versión. Una actualización automática puede romper la app silenciosamente.

**Fix:** `pip freeze > requirements.lock` y usar ese fichero en producción.

---

### 🟠 HIGH-008 — Fuzzy matching O(n·m) contra todo el catálogo

**Archivo:** `app/services/geocoding.py:353-386`

Para cada dirección a geocodificar, se hace `_token_set_ratio()` contra **todas** las calles del catálogo (~200 calles). Con 200 direcciones: 40.000 comparaciones de strings. Escala mal si el catálogo crece o si se amplía a más municipios.

**Fix:** Construir índice invertido de tokens al cargar el catálogo; buscar solo las calles que comparten tokens con la query.

---

## 2. Mejoras Inmediatas (esta semana)

### Código

**[INMEDIATA-01]** Mover `_normalize_for_dedup()` a módulo compartido (`app/services/utils.py`). Está duplicada idénticamente en `validation.py` y `optimize.py`.

**[INMEDIATA-02]** Reemplazar todos los `print()` del backend por `logging.info/warning/error`. Configurar nivel mediante variable de entorno `LOG_LEVEL`. Los prints actuales no distinguen severidad y se pierden en producción.

**[INMEDIATA-03]** Añadir límite de filas en `csv_service.dart` (ver CRIT-004).

**[INMEDIATA-04]** Pinear versiones en `requirements.txt` con `pip freeze`.

**[INMEDIATA-05]** Etiquetar las paradas fallidas con fondo rojo visible en `DeliveryScreen`. Actualmente aparecen al final de la lista sin diferenciación visual y el repartidor puede no notarlas.

**[INMEDIATA-06]** Añadir `response_model` declarado al endpoint `GET /api/route-segment` en el router para consistencia.

### UX

**[INMEDIATA-07]** Mostrar nivel de confianza de geocodificación en `ValidationReviewScreen`. Todos los stops geocodificados tienen el mismo checkmark verde aunque sean `GOOD` (interpolado, puede estar a 100m del portal real). Propuesta: ✅ Exacto / 🟡 Aproximado / 📍 Lugar.

**[INMEDIATA-08]** El `LoadingOrderScreen` no muestra el número de paradas que se están optimizando. Añadir `"Calculando ruta para X paradas..."` para reducir ansiedad de espera.

**[INMEDIATA-09]** En `DeliveryScreen`, las paradas con `geocode_failed=true` no tienen ningún indicador visual diferente al entrar en la pantalla. Añadir banner de advertencia al inicio si hay paradas sin geocodificar.

**[INMEDIATA-10]** El botón "Navegar" que abre Google Maps/Waze no tiene confirmación. Si el repartidor lo pulsa accidentalmente cambia de app. Hacer el botón menos prominente o añadir confirmación rápida.

---

## 3. Corto Plazo (1-2 meses)

### Rendimiento y Arquitectura

**[CORTO-01] Paralelizar geocodificación (mayor impacto en UX)**

La mejora más impactante en velocidad percibida. Con 10 llamadas concurrentes a Google, 100 direcciones pasarían de ~50s a ~5s. Requiere cambiar `geocode_batch()` a async y usar `asyncio.gather()` con semáforo.

**[CORTO-02] Capacidades en VROOM para multi-vehículo**

Añadir soporte de `capacity`/`delivery` en el payload de VROOM cuando `n_vehicles > 1`. Garantiza distribución equitativa. Requiere que el frontend pase `n_packages_per_stop` y que el backend calcule `capacity = ceil(total_stops / n_vehicles)`.

**[CORTO-03] Caché para geometría OSRM**

La llamada a OSRM `/route/v1/driving/` para obtener la polyline puede cachearse por hash de las coordenadas ordenadas. TTL: 1 hora. Evita recalcular la misma geometría si el usuario re-optimiza sin cambiar paradas.

**[CORTO-04] Background refresh de catálogo Overpass**

La descarga del catálogo OSM (puede tardar 40s) bloquea la primera geocodificación tras 7 días. Mover la descarga a una tarea en background (hilo separado al arrancar el servidor) que no bloquea peticiones entrantes.

**[CORTO-05] Retry con backoff en llamadas HTTP**

Implementar `tenacity` para reintentos automáticos en Google API, OSRM y VROOM. 3 reintentos, espera exponencial 1s/2s/4s. Cubre el 99% de los fallos transitorios de red.

### UX y Diseño

**[CORTO-06] Barra de progreso en geocodificación**

Actualmente hay un spinner genérico durante minutos. Implementar polling ligero (`/api/validation/status`) o Server-Sent Events para recibir progreso: `"Geocodificando 45/120 direcciones..."`. Impacto enorme en percepción de velocidad.

**[CORTO-07] Edición de dirección en ValidationReviewScreen**

Cuando una dirección falla la geocodificación, la única opción es poner un pin. Debería poder también **editar el texto** de la dirección (corregir typos, abreviaturas) y reintentar geocodificación sin volver a importar el CSV completo.

**[CORTO-08] Pantalla de resumen post-reparto**

Cuando el repartidor marca la última entrega, la app no tiene pantalla de cierre. Añadir `SummaryScreen` con: X entregados / Y ausentes / Z incidencias / Distancia recorrida / Tiempo empleado. Exportable como informe.

**[CORTO-09] Undo al marcar una parada**

Si el repartidor marca accidentalmente "Entregado" en la parada incorrecta, no hay forma de deshacer. Añadir snackbar con botón "Deshacer" que aparece 5 segundos tras marcar, permitiendo revertir el estado.

**[CORTO-10] Orden de carga inverso**

En `DeliveryScreen` hay una pantalla de "orden de carga" (orden inverso para cargar la furgoneta correctamente). Verificar que este orden es real y no solo se muestra como texto. Añadir posibilidad de imprimir o compartir.

**[CORTO-11] Vista lista vs mapa en ResultScreen**

Actualmente `ResultScreen` muestra primero el mapa. Para algunos repartidores es más útil ver primero la lista de paradas en orden. Añadir toggle Lista/Mapa.

### Datos y Validación

**[CORTO-12] Validación más estricta en CsvService**
- Detectar y advertir sobre filas con dirección idéntica (duplicados)
- Validar que la ciudad no está vacía masivamente (>50% vacías = columnas mal alineadas)
- Detectar posible inversión de columnas cliente/dirección
- Máximo 500 caracteres por campo

**[CORTO-13] Soporte de lat/lon en el CSV**

Permitir columnas `lat`/`lon` opcionales en el CSV. Si están presentes, usarlas directamente (skip geocodificación). Útil cuando el sistema origen ya tiene coordenadas.

**[CORTO-14] Exportar ruta en GPX**

Además del CSV actual de resultados, exportar en GPX para importar directamente en apps de navegación como OsmAnd, Maps.me o Garmin.

---

## 4. Medio Plazo (3-6 meses)

### Producto / Funcionalidad

**[MEDIO-01] Ventanas de tiempo (time windows)**

VROOM soporta natively `time_windows` por parada. Permitir indicar "entregar entre 9:00 y 11:00". El CSV aceptaría columnas `hora_desde` y `hora_hasta`. El optimizador respetaría estas restricciones.

**[MEDIO-02] Multi-día: historial de repartos**

Guardar historial de sesiones para poder:
- Ver repartos anteriores con estadísticas
- Comparar eficiencia entre días/conductores
- Exportar informe mensual

**[MEDIO-03] Foto de entrega / firma digital**

Para repartos que lo requieran, opción de adjuntar foto (`image_picker`) al marcar "Entregado". La foto se asocia a la parada y puede exportarse. Útil en casos de disputas.

**[MEDIO-04] Notificación al destinatario**

Integrar notificación (SMS via Twilio o WhatsApp Business API) al destinatario cuando el repartidor esté a N paradas. Reduce ausencias y mejora la experiencia del cliente final.

**[MEDIO-05] Zona de cobertura configurable**

Actualmente el mapa OSRM solo cubre Andalucía. Hacer la zona configurable via `config.py` para poder usar el sistema en otras provincias sin recompilar la app.

**[MEDIO-06] Panel web de administración**

Dashboard web ligero para:
- Ver estadísticas de repartos históricos
- Gestionar el caché de geocodificación (ver, forzar borrado, re-geocodificar)
- Monitorizar estado de OSRM/VROOM/ngrok en tiempo real
- Ver qué direcciones fallan repetidamente para corregirlas en el catálogo

### Arquitectura

**[MEDIO-07] Autenticación real (JWT)**

Implementar autenticación con JWT: login simple usuario/contraseña, token con expiración de 8h. Middleware FastAPI verifica el token. La app Flutter almacena el token en `flutter_secure_storage`.

**[MEDIO-08] Base de datos real para caché**

Migrar el caché de geocodificación de JSON plano a SQLite (local) o PostgreSQL. Beneficios: consultas indexadas, soporte transaccional, sin riesgo de corrupción en escrituras concurrentes, consultas de auditoría.

**[MEDIO-09] Despliegue unificado con Docker Compose**

Añadir el backend FastAPI como servicio en `docker-compose.yml`. Actualmente el backend corre fuera de Docker, requiriendo activar el venv manualmente. `docker compose up` debería levantar OSRM + VROOM + Backend.

**[MEDIO-10] Versionado de la API**

Añadir prefijo `/api/v1/` a todos los endpoints. Permite desplegar cambios breaking en `/api/v2/` sin romper clientes con la app anterior instalada.

**[MEDIO-11] Tests automáticos** ✅ *Completado en v2.1.0*

~~Añadir suite de tests mínima~~

Implementado en v2.1.0: 328 tests en total (218 backend + 110 Flutter), cobertura backend 71-100% por módulo, cobertura Flutter 98.6%. Análisis estático con mypy y dart analyze (0 errores). Script `run_tests.sh` unificado.

### Datos y Geocodificación

**[MEDIO-12] Learned streets con metadata de calidad**

El fichero `learned_streets.json` guarda calles aprendidas pero sin metadata. Añadir: origen, fecha, número de confirmaciones. Descartar entradas con baja confianza tras N días sin uso.

**[MEDIO-13] Detección de coordenadas sospechosas**

Tras geocodificar, comparar coordenada con el centroide de la ciudad. Si está a más de 5km, marcar como sospechosa y pedir confirmación antes de incluir en la ruta. Evita silenciosamente geocodificaciones incorrectas en ciudades homónimas.

**[MEDIO-14] Trie para fuzzy matching eficiente**

Construir índice invertido de tokens al cargar el catálogo. Buscar solo calles que comparten tokens con la query, en lugar de comparar contra todas las calles. Escala a catálogos de miles de calles sin degradación.

---

## 5. Largo Plazo (6+ meses)

### Infraestructura

**[LARGO-01] Eliminar ngrok — infraestructura propia**

VPS propio (Hetzner/DigitalOcean ~5€/mes) con dominio fijo + Let's Encrypt SSL + nginx como reverse proxy. Elimina la dependencia de la URL de ngrok, el límite de conexiones del free tier y la necesidad de recompilar el APK cuando la URL cambia.

**[LARGO-02] Mapa OSRM actualizable sin downtime**

Actualizar el mapa OSRM requiere parar el servicio y reasignar varios GB. Implementar A/B deployment: dos instancias OSRM (osrm-a y osrm-b), nginx hace proxy a la activa, se actualiza la inactiva y se hace swap. Zero-downtime map updates.

**[LARGO-03] Escalar para múltiples empresas (multi-tenant)**

Si el producto se comercializa:
- Aislamiento de datos por empresa (geocaché separado, historial separado)
- Planes con límites de paradas/mes
- API keys de Google por cliente
- Panel de administración multi-tenant

**[LARGO-04] App iOS**

El proyecto Flutter no está activamente mantenido para iOS. Para expandir necesita:
- Signing y provisioning profiles
- Permisos en `Info.plist` (location, file access)
- Ajuste de UI para Safe Area en iPhones con notch
- Publicación en App Store

**[LARGO-05] Integración con ERP/TMS**

Conectar directamente con sistemas de gestión de almacén (ERP) o transporte (TMS):
- Webhook para recibir pedidos automáticamente
- API de retorno con confirmaciones de entrega
- Integración con operadoras (GLS, MRW, Correos) para tracking nativo

**[LARGO-06] Optimización con tráfico en tiempo real**

VROOM + OSRM trabajan con un mapa estático (sin tráfico). Para mayor calidad en zonas con congestión horaria:
- Google Route Optimization API (~$0.80/reparto, incluye tráfico live)
- HERE Maps Routing API (free tier generoso)
- Especialmente relevante en repartos de mañana temprano o mediodía

**[LARGO-07] Monitorización y alertas**

Instrumentar la app con métricas (Prometheus + Grafana o similar):
- Tasa de éxito de geocodificación por día
- Tiempo medio de respuesta por endpoint
- Coste estimado de Google API consumido
- Alertas si la tasa de fallos supera un umbral

---

## 6. Resumen por Impacto/Esfuerzo

### Hacer ya (alto impacto, bajo esfuerzo)
| Item | Descripción |
|------|-------------|
| INMEDIATA-01 | Deduplicar `_normalize_for_dedup` |
| INMEDIATA-02 | Logging estructurado (reemplazar prints) |
| INMEDIATA-03 | Límite de filas CSV |
| INMEDIATA-04 | Pinear dependencias Python |
| INMEDIATA-07 | Mostrar nivel de confianza en validación |
| INMEDIATA-08 | Mostrar nº paradas en loading screen |
| CORTO-09 | Undo al marcar parada |
| CORTO-08 | Pantalla resumen post-reparto |

### Planificar próxima iteración (alto impacto, esfuerzo medio)
| Item | Descripción |
|------|-------------|
| CRIT-002 | Autenticación mínima (API key) |
| CRIT-003 | Fix persistencia antes de UI |
| CORTO-01 | Paralelizar geocodificación |
| CORTO-02 | Capacidades VROOM multi-vehículo |
| CORTO-06 | Progreso de geocodificación en tiempo real |
| CORTO-07 | Edición de dirección en revisión |

### Para una versión mayor
| Item | Descripción |
|------|-------------|
| MEDIO-01 | Time windows en optimización |
| MEDIO-02 | Multi-día / historial de repartos |
| MEDIO-07 | Autenticación JWT |
| MEDIO-08 | Base de datos real |
| LARGO-01 | Infraestructura propia (eliminar ngrok) |
| LARGO-06 | Optimización con tráfico en tiempo real |
