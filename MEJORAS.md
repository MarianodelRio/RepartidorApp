# Hoja de Ruta de Mejoras — App Repartir

> Análisis técnico y estratégico completo del sistema. Cubre backend Python/FastAPI,
> app Flutter/Android, infraestructura Docker/ngrok, operaciones, escalabilidad,
> monitorización, CI/CD, multi-tenancia y expansión geográfica.
> Última revisión: febrero 2026 — versión del sistema: 1.4.0

---

## Índice

1. [Inmediatas — bugs y riesgos activos](#1-inmediatas--bugs-y-riesgos-activos)
2. [Corto plazo — mejoras de producto](#2-corto-plazo--mejoras-de-producto)
3. [Medio plazo — funcionalidades nuevas](#3-medio-plazo--funcionalidades-nuevas)
4. [Largo plazo — arquitectura y escalabilidad técnica](#4-largo-plazo--arquitectura-y-escalabilidad-técnica)
5. [Seguridad y privacidad](#5-seguridad-y-privacidad)
6. [Negocio y operaciones (nivel empresa)](#6-negocio-y-operaciones-nivel-empresa)
7. [Monitorización y observabilidad](#7-monitorización-y-observabilidad)
8. [CI/CD y automatización de despliegues](#8-cicd-y-automatización-de-despliegues)
9. [Escalabilidad geográfica — expansión a otras ciudades](#9-escalabilidad-geográfica--expansión-a-otras-ciudades)
10. [Escalabilidad de carga — más usuarios concurrentes](#10-escalabilidad-de-carga--más-usuarios-concurrentes)
11. [Multi-tenancia — múltiples empresas en la misma plataforma](#11-multi-tenancia--múltiples-empresas-en-la-misma-plataforma)
12. [Mantenimiento y operaciones del sistema](#12-mantenimiento-y-operaciones-del-sistema)
13. [Resiliencia y recuperación ante desastres](#13-resiliencia-y-recuperación-ante-desastres)
14. [Costes e infraestructura por escenario](#14-costes-e-infraestructura-por-escenario)
15. [Roadmap de producto a 18 meses](#15-roadmap-de-producto-a-18-meses)

---

## 1. Inmediatas — bugs y riesgos activos

Problemas que pueden causar pérdida de datos, crashes o comportamiento incorrecto hoy mismo.

---

### 1.1 Paradas fallidas se sitúan con coords falsas en el mapa

**Archivo:** `app/routers/optimize.py` líneas 354-355

Cuando una dirección no se puede geocodificar, el backend le asigna las coordenadas del
centro de Posadas (`POSADAS_CENTER`) y la incluye en la respuesta. El cliente dibuja ese
pin en el mapa como si fuera real. El repartidor puede ir a buscar un paquete al centro
de la ciudad cuando la dirección real está en otro sitio.

**Solución:** Devolver `lat: null, lon: null` y `geocode_failed: true`. La app ya tiene
ese campo en el modelo `StopInfo`; solo falta no rellenar coords falsas.

---

### 1.2 Estado de entregas no persiste si la app se cierra por fuerza

**Archivo:** `flutter_app/lib/screens/delivery_screen.dart` líneas 154-178

Las entregas solo se escriben en Hive cuando el usuario pulsa "Entregar / Ausente / Incidencia".
Si el teléfono se apaga o el sistema operativo mata la app entre dos pulsaciones, todo el
progreso de esa sesión se pierde. No hay autoguardado.

**Solución:** Guardar estado completo en Hive cada vez que cambia cualquier parada
(`_applyReorder`, cambio de `currentStopIndex`, etc.), no solo al marcar manualmente.

---

### 1.3 Coordenadas de paradas no se validan en rango

**Archivos:** `flutter_app/lib/models/validation_models.dart`, `route_models.dart`

No hay validación de que `lat ∈ [-90, 90]` y `lon ∈ [-180, 180]` en ningún modelo
Dart ni Pydantic. Un valor erróneo del backend (ej. `lat: 999`) llega al mapa y puede
causar un crash silencioso del renderizador de `flutter_map`.

**Solución:** Añadir `assert` en los constructores Dart y un `field_validator` Pydantic
en `StopInfo` y `OptimizeRequest`.

---

### 1.4 Memory leak en AnimationController del marcador GPS

**Archivo:** `flutter_app/lib/widgets/route_map.dart` líneas 496-517

`_GpsMarker` crea un `AnimationController` en `initState()`. Si el widget padre se
reemplaza antes de que el widget llame a `dispose()` (ej. el usuario entra y sale
rápidamente de `DeliveryScreen`), el controlador sigue activo en memoria.
Con varias entradas/salidas pueden acumularse varios controladores activos.

**Solución:** Añadir `mounted` check en los listeners y garantizar que `dispose()` se
llama siempre antes de salir del árbol.

---

### 1.5 Reordenación de paradas puede dejar `currentStopIndex` incorrecto

**Archivo:** `flutter_app/lib/screens/delivery_screen.dart` líneas 555-593

En `_applyReorder()`, tras reconstruir la lista de paradas, la búsqueda del nuevo
`currentStopIndex` itera buscando la primera parada `pending && !isOrigin`. Si hay
paradas completadas intercaladas después del reordenamiento, el índice puede apuntar
a una parada ya completada o quedar fuera de rango.

**Solución:** Calcular el índice sobre la nueva lista ya reordenada, no sobre la original.

---

### 1.6 Sesión corrupta en Hive falla silenciosamente

**Archivo:** `flutter_app/lib/screens/import_screen.dart` líneas 97-104

Si `PersistenceService.loadSession()` lanza excepción (datos Hive corruptos tras
actualización de la app), no se muestra ningún aviso. El usuario pulsa "Continuar Ruta"
y no ocurre nada.

**Solución:** Capturar la excepción y mostrar un diálogo:
_"La sesión guardada no pudo cargarse. ¿Descartarla y empezar de nuevo?"_

---

### 1.7 CSV con dos columnas que contienen "direc" elige la equivocada

**Archivo:** `flutter_app/lib/services/csv_service.dart` líneas 58-87

El parser detecta la columna de dirección buscando `contains('direcc')`. Si el CSV
tiene columnas `Dirección` y `Dirección Secundaria`, puede seleccionar la segunda.
No hay aviso de ambigüedad.

**Solución:** Usar coincidencia exacta primero, fuzzy solo como fallback con log de
advertencia visible al usuario.

---

### 1.8 MapPickerScreen acepta coordenadas en cualquier lugar del mundo

**Archivo:** `flutter_app/lib/screens/map_picker_screen.dart` líneas 26-34

No hay validación de que el punto seleccionado esté dentro del área de trabajo. Un usuario
puede tocar en el Atlántico sin querer y el pin se guarda. Nominatim no puede rutear esa
posición y la parada fallará en OSRM silenciosamente.

**Solución:** Validar que las coords estén dentro del viewbox de Posadas
(`POSADAS_VIEWBOX = "-5.15,37.78,-5.06,37.83"`) y mostrar aviso si están fuera.

---

### 1.9 GPS se solicita de forma bloqueante y secuencial

**Archivo:** `flutter_app/lib/screens/import_screen.dart` (lógica de optimización)

Cuando el modo de origen es GPS, la app llama a `Geolocator.getCurrentPosition()` con
un timeout de hasta 22 segundos. Si el GPS tarda (interior de edificio, primera vez),
bloquea el hilo de UI y el spinner parece congelado. No hay feedback de que se está
esperando la posición GPS específicamente.

**Solución:** Llamar en `compute()` o con `Future.timeout()` explícito, y mostrar
mensaje "Obteniendo GPS…" diferenciado del resto del proceso.

---

### 1.10 `ApiService` usa `catch(_)` genérico sin distinguir tipos de error

**Archivo:** `flutter_app/lib/services/api_service.dart`

Todos los errores HTTP, de red, de parseo JSON y de timeout se capturan en el mismo
`catch` y se convierten en el mismo mensaje genérico. El usuario no sabe si falló la
conexión, el servidor, o el backend procesando.

**Solución:** Distinguir `SocketException` (sin red), `TimeoutException` (timeout),
`FormatException` (JSON inválido) y `HttpException` (error HTTP), con mensajes
específicos para cada caso.

---

### 1.11 Hive no tiene versioning de esquema

**Archivo:** `flutter_app/lib/services/persistence_service.dart`

Si se añaden o eliminan campos a los `TypeAdapter` de Hive entre versiones de la app,
la deserialización de sesiones antiguas lanza una excepción no manejada. El usuario
ve "Continuar Ruta" y la app se congela o cierra.

**Solución:** Añadir campo `schemaVersion` a los adaptadores Hive y migrar o descartar
sesiones de versiones incompatibles con un diálogo informativo.

---

### 1.12 CSV sin límite de tamaño ni validación de encoding

**Archivo:** `flutter_app/lib/services/csv_service.dart`

El parser carga el CSV completo en memoria de una sola vez. Un archivo de 50 MB
(posible si se pega contenido erróneo) puede causar `OutOfMemoryError`. Además, solo
funciona con UTF-8; un CSV exportado de Excel en Windows con encoding Windows-1252
producirá caracteres corruptos en las direcciones sin ningún aviso.

**Solución:** Límite de tamaño (ej. 5 MB), detección de encoding con la librería
`charset_detector`, y aviso explícito si el encoding no es UTF-8 ni Latin-1.

---

### 1.13 `docker-compose.yml` sin health checks ni límites de recursos

**Archivo:** `docker-compose.yml`

OSRM y VROOM no tienen health checks configurados. `depends_on: osrm` solo espera a
que el contenedor exista, no a que OSRM responda. En máquinas lentas, VROOM puede
arrancar antes de que OSRM haya cargado el grafo (~30s), causando errores de conexión.
Tampoco hay límites de CPU/RAM; OSRM puede consumir toda la RAM disponible durante el
arranque con el grafo de Andalucía.

**Solución:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:5000/route/v1/driving/..."]
  interval: 10s
  timeout: 5s
  retries: 10
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '2'
```

---

### 1.14 VROOM usa `network_mode: host` — roto en Windows y macOS

**Archivo:** `docker-compose.yml` línea 18

`network_mode: host` solo funciona en Linux. En Windows (WSL2) y macOS (Docker Desktop),
VROOM no puede acceder a `localhost:5000` donde está OSRM. La app falla silenciosamente
en optimización con un mensaje genérico.

**Solución:** Cambiar VROOM a red de Docker normal y apuntar a OSRM por nombre de
servicio:
```yaml
vroom:
  networks:
    - app-net
  environment:
    - VROOM_ROUTER=osrm
    - OSRM_URL=http://osrm:5000
```

---

## 2. Corto plazo — mejoras de producto

Cambios visibles por el usuario o el operador, factibles en 1-3 días cada uno.

---

### 2.1 Botón "Cancelar" en el diálogo de cálculo de ruta

**Archivo:** `flutter_app/lib/screens/import_screen.dart` — `_RouteProgressDialog`

El diálogo de progreso puede quedarse bloqueado en "Casi listo…" si el backend falla
silenciosamente. El usuario no puede cancelar ni reintentar. El timeout de `ApiConfig`
es de 10 minutos.

**Solución:** Añadir botón "Cancelar" que llame a `client.close()` sobre el request HTTP
en curso, descarte el diálogo y vuelva al estado de importación.

---

### 2.2 Feedback real durante la validación (progreso por parada)

**Archivo:** `app/routers/validation.py` y `flutter_app/lib/services/api_service.dart`

Con 100 paradas, Nominatim tarda entre 60 y 150 segundos. El usuario ve el mismo spinner
sin saber cuántas direcciones han sido procesadas.

**Solución corta:** El backend puede exponer un endpoint `GET /api/validation/{job_id}/progress`
con `{"total": 100, "done": 47, "failed": 3}`. La app puede hacer polling cada 2s.

---

### 2.3 Exportar resultado final del reparto como CSV

**Archivo:** `flutter_app/lib/screens/delivery_screen.dart`

Al terminar el reparto, solo se puede ver el resumen en pantalla. No hay forma de
exportar qué se entregó, qué estuvo ausente y qué tuvo incidencia.

**Columnas propuestas:** `cliente, dirección, estado, nota, hora_marcado`

**Implementación:** Mismo patrón que `result_screen.dart:_exportCsv()` — generar CSV
desde `_session.stops` y compartir con `share_plus`.

---

### 2.4 Editar la dirección de texto de una parada fallida antes de situar en mapa

**Archivo:** `flutter_app/lib/screens/import_screen.dart` — `_buildFailedList()`

Actualmente, si una dirección falla porque tiene una errata ("Clle Gaitán" en lugar de
"Calle Gaitán"), la única opción es situar a mano en el mapa. Sería más rápido poder
editar el texto y reintentar la geocodificación.

**Solución:** Añadir un campo de texto editable en la tarjeta de parada fallida con botón
"Reintentar geocodificación".

---

### 2.5 Confirmación visual de que la entrega se guardó correctamente

**Archivo:** `flutter_app/lib/screens/delivery_screen.dart`

Cuando se marca una parada, el cambio es instantáneo visualmente pero no hay ningún
indicador de que se guardó en Hive. Si el guardado falla (disco lleno, bug), el usuario
no lo sabe.

**Solución:** Mostrar una animación breve de checkmark (tipo toast) confirmando "Guardado"
solo después de que `PersistenceService.updateStopStatus()` complete sin error.

---

### 2.6 Tiles de mapa oscuros en modo noche

**Archivo:** `flutter_app/lib/widgets/route_map.dart` línea 296

Los tiles OSM estándar son fondos claros. Por la noche, con brillo reducido, son
difíciles de leer. El modo oscuro del sistema no afecta a las tiles.

**Solución:** Detectar `Theme.of(context).brightness == Brightness.dark` y cambiar
`urlTemplate` a tiles oscuros (ej. Stadia Alidade Smooth Dark, que es gratuito).

---

### 2.7 Marcadores de parada más grandes en modo reparto

**Archivo:** `flutter_app/lib/widgets/route_map.dart` líneas 362-373

En `deliveryMode`, los marcadores no activos tienen tamaño 24×24 píxeles, por debajo
del mínimo táctil de 48×48 recomendado por Material Design. Difícil de tocar conduciendo
o con la mano no dominante.

**Solución:** Mínimo 32×32 para marcadores secundarios en delivery, 48×48 para la
siguiente parada.

---

### 2.8 ETA estimada a la siguiente parada

**Archivo:** `flutter_app/lib/screens/delivery_screen.dart` — `_NextStopCard`

Se muestra la dirección y la distancia en metros pero no el tiempo estimado. Con
`distance_meters / velocidad_media` se puede mostrar "~8 min" sin ninguna llamada extra.

**Solución:** Calcular `(distanceMeters / 8.0 * 3.6).round()` minutos (velocidad media
de reparto urbano: ~20 km/h = 8 m/s efectivos) y mostrarlo en la tarjeta.

---

### 2.9 Precarga del catálogo de calles OSM al arrancar el servidor

**Archivo:** `app/main.py`, `app/services/geocoding.py` línea 281

La primera petición de validación descarga el catálogo de calles de Overpass (puede
tardar 20-40 segundos). El usuario ve un timeout aparente sin explicación.

**Solución:** Añadir evento `@app.on_event("startup")` que llame a `_get_osm_streets()`
en background, de modo que al llegar la primera petición real ya esté en memoria.

---

### 2.10 Validar coordenadas Nominatim fuera del viewbox

**Archivo:** `app/services/geocoding.py` — `geocode()` línea 440

Nominatim a veces devuelve resultados geográficamente incorrectos (ciudad homónima en
otro país). No hay comprobación de que las coords estén dentro del área de trabajo.

**Solución:**
```python
lon1, lat1, lon2, lat2 = map(float, POSADAS_VIEWBOX.split(","))
if not (lon1 <= lon <= lon2 and lat1 <= lat <= lat2):
    return None  # Resultado fuera de zona — descartado
```

---

## 3. Medio plazo — funcionalidades nuevas

Características que añaden valor real al negocio. Estimación: 1-2 semanas cada una.

---

### 3.1 Historial de repartos

**Estado actual:** Cero persistencia. Una vez completado un reparto, los datos
desaparecen del teléfono y nunca llegan al servidor.

**Propuesta:**
- El backend guarda cada ruta optimizada en SQLite: fecha, n.º paradas, distancia,
  tiempo de cálculo, GeoJSON.
- Al finalizar el reparto, Flutter sincroniza el resultado: qué se entregó, qué
  estuvo ausente, con timestamp.
- Pantalla de historial simple: lista de repartos por fecha con estadísticas básicas.

**Tablas mínimas:**
```sql
routes (id, date, stops_count, distance_m, computing_ms, created_at)
deliveries (id, route_id, address, client, lat, lon, status, note, completed_at)
```

---

### 3.2 Dashboard web del operador

**Estado actual:** El jefe de reparto no tiene visibilidad en tiempo real. Solo puede
ver lo que el repartidor le comunica por teléfono.

**Propuesta:**
- Página web sencilla (Flask + HTML o Vue.js)
- Mapa con los repartidores en tiempo real (si comparten GPS voluntariamente)
- Tabla: paradas completadas / pendientes / fallidas actualizándose vía polling
- Botón "Descargar resumen del día"
- Alertas automáticas: "Repartidor lleva más de 20 min en la misma parada"

---

### 3.3 Soporte multi-vehículo real

**Estado actual:** VROOM soporta VRP (Problema de Rutas con Múltiples Vehículos) de
forma nativa pero el backend siempre envía 1 vehículo.

**Propuesta:**
- Campo `num_vehicles: int` en `OptimizeRequest`
- Backend crea N vehículos en VROOM con la misma parada de salida
- Respuesta incluye array de rutas: `[{vehicle_id: 1, stops: [...]}, ...]`
- `ResultScreen` muestra selector: "Ruta 1 (n paradas) / Ruta 2 (n paradas)"
- Cada repartidor abre su ruta en su teléfono

---

### 3.4 Modo offline básico

**Estado actual:** Sin internet, nada funciona salvo marcar entregas ya cargadas.

**Propuesta mínima:**
- Cachear la geometría de la ruta en Hive al cargarla (ya está parcialmente implementado)
- Cachear los segmentos GPS conforme se van calculando (no volver a pedirlos)
- Indicador claro en la app: "Sin conexión — usando ruta en caché"
- La app sigue siendo usable para navegar y marcar entregas

**Lo que no puede ser offline:** Validación y optimización (requieren Nominatim/VROOM).

---

### 3.5 Reintentar geocodificación con backoff adaptativo

**Archivo:** `app/services/geocoding.py`

Nominatim devuelve HTTP 429 cuando se supera el rate limit. Actualmente se ignora y la
dirección se marca como fallida permanentemente en esa sesión.

**Propuesta:**
```python
if response.status_code == 429:
    wait = int(response.headers.get("Retry-After", 60))
    time.sleep(wait)
    return geocode(address)  # Reintentar una vez
```
Reducción esperada de paradas "fallidas" por rate limit: ~80%.

---

### 3.6 Endpoint de override manual de coordenadas (admin)

**Archivo:** `app/services/geocoding.py` — `add_override()` existe pero no está expuesta

Si una calle de Posadas no existe en Nominatim (callejón sin nombre oficial, polígono
industrial nuevo), la única solución actual es editar el JSON a mano con acceso SSH.

**Propuesta:**
```
POST /api/admin/geocoding/override
{ "address": "Calle Nueva s/n", "lat": 37.8034, "lon": -5.1012 }
```
Con token de admin en header. Persiste en `geocode_cache.json` con flag `"manual": true`.

---

### 3.7 Notas de entrega con foto (prueba de entrega)

**Estado actual:** Solo se puede elegir Entregado / Ausente / Incidencia, con texto libre.

**Propuesta:**
- Botón de cámara en la tarjeta de entrega
- Foto se guarda local (no se sube al servidor por privacidad)
- Se incluye en el CSV de exportación como ruta de archivo o base64
- Útil para auditoría ante reclamaciones de GLS

---

### 3.8 Búsqueda de dirección en MapPickerScreen

**Archivo:** `flutter_app/lib/screens/map_picker_screen.dart`

Actualmente el mapa se abre centrado en Posadas y el usuario tiene que buscar visualmente
la ubicación. Si la parada está en una calle poco conocida, hay que hacer zoom y moverse
mucho.

**Propuesta:** Añadir un campo de búsqueda en el AppBar del MapPickerScreen que llame a
Nominatim y mueva el mapa a la dirección resultante, dejando que el usuario afine tocando.

---

### 3.9 Estadísticas de eficiencia por ruta

**Estado actual:** Solo se muestra distancia total y n.º de paradas.

**Métricas propuestas** (calculables con datos ya disponibles):
- Distancia real recorrida vs. distancia teórica optimizada
- Tasa de éxito (entregas / total paradas)
- Dirección con más fallos de geocodificación
- Tiempo estimado de ruta (distancia / velocidad media configurable)
- Comparación entre días: "Hoy: 87 paradas en 4h 20min — Ayer: 91 en 5h 10min"

---

### 3.10 Integración directa con la API de GLS España

**Estado actual:** El operador descarga hojas de reparto en PDF, las transcribe a CSV
manualmente y las importa. Proceso lento y propenso a errores.

**Propuesta A (extracción de PDF):**
```python
import pdfplumber
with pdfplumber.open("hoja_gls.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
        # Parsear regex para extraer dirección, destinatario, código de barras
```

**Propuesta B (API GLS):** GLS España tiene una API REST para empresas distribuidoras
(`api.gls-group.eu`). Con credenciales de empresa, se puede obtener la lista de envíos
del día automáticamente, sin transcripción manual.

---

### 3.11 Notificaciones push al operador

**Estado actual:** El jefe no recibe ninguna notificación automática sobre el reparto.

**Propuesta mínima (sin infraestructura push):**
- Al iniciar reparto: Telegram bot envía "Repartidor ha iniciado — X paradas"
- Al completar parada con incidencia: alerta inmediata
- Al finalizar: resumen completo por Telegram/email
- Webhook configurable: `POST https://hooks.slack.com/...`

**Propuesta completa:** Firebase Cloud Messaging (FCM) — gratuito hasta 10.000 msg/mes,
integración nativa con Flutter (`firebase_messaging` package).

---

## 4. Largo plazo — arquitectura y escalabilidad técnica

Cambios estructurales que requieren más planificación. Rentables si el sistema crece
a más de 2-3 repartidores o más de 200 paradas diarias.

---

### 4.1 Reemplazar ngrok con servidor propio

**Problema:** ngrok gratuito cambia la URL pública en cada reinicio. Cada vez hay que
distribuir un nuevo APK o editar `api_config.dart`. Además, la API está expuesta al
mundo sin autenticación.

**Propuesta:**
- VPS básico (~5-10 €/mes): Hetzner CX11, Contabo, etc.
- Nginx como reverse proxy con HTTPS automático (Let's Encrypt + Certbot)
- URL fija: `https://api.repartir.tuempresa.es`
- API Key en header para autenticar dispositivos móviles
- `api_config.dart` con URL fija compilada; cuando la empresa cambie de servidor,
  solo hay que cambiar la IP en el DNS

---

### 4.2 Base de datos relacional

**Problema:** Todo el estado vive en archivos JSON, memoria y Hive local. Sin base de
datos no es posible historial, multi-usuario, auditoría ni dashboard.

**Propuesta (progresiva):**
1. SQLite para empezar (cero coste, sin configuración)
2. PostgreSQL cuando haya más de 1 repartidor o se quiera acceso remoto
3. ORM ligero: SQLModel (compatible con FastAPI y Pydantic)

**Tablas mínimas:** `routes`, `deliveries`, `clients`, `geocode_cache` (migrar JSON),
`vehicles`, `users`

---

### 4.3 Endpoints async y paralelización de servicios

**Problema:** Los endpoints FastAPI son síncronos bloqueantes. Una petición de
optimización con 200 paradas bloquea el thread durante hasta 120 segundos. Con 3
usuarios concurrentes, el servidor queda saturado.

**Propuesta:**
- Convertir `optimize()` y `validate()` a `async def`
- Usar `httpx.AsyncClient` para llamadas a OSRM, VROOM y Nominatim
- Paralelizar `can_osrm_snap()` (actualmente 1 request por parada)
- Reducción esperada: latencia total de 200 paradas de ~150s a ~40-60s

---

### 4.4 Sistema de colas para optimización (job queue)

**Problema:** Las peticiones lentas bloquean workers. No hay feedback de posición en cola.

**Propuesta:**
- Celery + Redis como broker de tareas
- `/api/optimize` devuelve `{ "job_id": "abc123" }` inmediatamente
- Flutter hace polling a `/api/jobs/abc123/status` cada 3 segundos
- Ventajas: n.º de workers ilimitado, priorización, reintentos automáticos, historial

---

### 4.5 Caché compartida con Redis

**Problema:** `geocode_cache.json` se escribe completo a disco en cada nueva
geocodificación. Con múltiples workers Uvicorn, cada uno tiene su propia copia en
memoria — inconsistente.

**Propuesta:**
- Redis como caché compartida entre workers
- TTL configurable por tipo de entrada (geocodificaciones: 30 días, rutas: 1 hora)
- `geocode()` consulta Redis antes de llamar a Nominatim
- Reducción de llamadas HTTP a Nominatim: ~70-80% con caché caliente

---

### 4.6 Fuzzy matching con RapidFuzz

**Archivo:** `app/services/geocoding.py` líneas 157-209

`difflib.SequenceMatcher` es Python puro: lento para 2000+ calles con 100+ paradas.
`rapidfuzz` es el mismo algoritmo escrito en C++, ~100× más rápido.

**Cambio mínimo:**
```python
from rapidfuzz import fuzz, process

def _find_closest_street(query_street: str) -> str | None:
    result = process.extractOne(
        _normalize(query_street),
        _osm_streets_norm,
        scorer=fuzz.token_set_ratio,
        score_cutoff=FUZZY_THRESHOLD * 100,
    )
    if result:
        return _osm_streets[result[2]]
    return None
```

---

### 4.7 Persistencia de caché con SQLite (en lugar de JSON)

**Problema:** `geocode_cache.json` se reescribe entero en cada inserción. Con 5000
entradas (~500 KB), cada geocodificación hace un write de 500 KB a disco.

**Propuesta:**
```sql
CREATE TABLE geocode_cache (
    key TEXT PRIMARY KEY,
    lat REAL, lon REAL,
    street TEXT, number TEXT,
    display_name TEXT,
    created_at INTEGER,
    manual BOOLEAN DEFAULT 0
);
```
Un insert SQLite tarda ~0.1 ms vs ~10-50 ms del JSON dump. Sin contención de I/O.

---

### 4.8 Cobertura de tests automáticos

**Estado actual:** Cero tests en backend y frontend.

**Prioridad de tests:**
1. `_parse_address()` — función crítica con 15+ regex, fácil de romper
2. `geocode()` — lógica de caché y fallback
3. `_group_duplicate_addresses()` — lógica de agrupación
4. `optimize()` endpoint — test de integración con OSRM/VROOM en modo mock
5. `CsvService.parse()` — casos edge: BOM, separadores, columnas extra
6. `PersistenceService` — serialización/deserialización round-trip

**Herramientas:** `pytest` + `httpx.AsyncClient` para backend; `flutter_test` para Dart.

---

### 4.9 Separación de ambientes (dev / staging / prod)

**Estado actual:** Una sola configuración hardcodeada.

**Propuesta:**
- `--dart-define=ENV=dev|prod` en Flutter para seleccionar `api_config`
- `.env` en backend con `OSRM_URL`, `VROOM_URL`, `DB_URL`, `API_KEY`
- `docker-compose.override.yml` para desarrollo local
- Script de CI/CD: GitHub Actions que compila APK al hacer push a `main`

---

### 4.10 Circuit breakers para OSRM y VROOM

**Problema:** Si OSRM está caído, cada petición espera el timeout completo (60s).

**Propuesta:**
```python
from pybreaker import CircuitBreaker

osrm_breaker = CircuitBreaker(fail_max=3, reset_timeout=30)

@osrm_breaker
def call_osrm(coords):
    ...
```
Si OSRM falla 3 veces, el circuit breaker "abre" y devuelve error inmediato durante
30 segundos. Los threads quedan libres.

---

## 5. Seguridad y privacidad

---

### 5.1 API sin autenticación expuesta vía ngrok (CRÍTICO)

La URL pública de ngrok permite a cualquiera:
- Geocodificar ilimitadas direcciones (abusa de Nominatim en tu nombre)
- Ejecutar optimizaciones que consumen CPU de OSRM/VROOM
- Leer direcciones y coordenadas de clientes en las respuestas

**Solución mínima inmediata:**
```python
# app/main.py
API_KEY = os.environ.get("API_KEY", "dev-key")

@app.middleware("http")
async def check_api_key(request: Request, call_next):
    if request.url.path.startswith("/api/"):
        if request.headers.get("X-API-Key") != API_KEY:
            return JSONResponse({"error": "Unauthorized"}, status_code=401)
    return await call_next(request)
```

---

### 5.2 Datos de clientes sin cifrar en Hive

Los datos del reparto (nombres, direcciones, coordenadas de clientes) se guardan en
Hive sin cifrado. Si el teléfono es robado, todos esos datos son legibles.

**Posibles implicaciones RGPD/LPDP:** Las direcciones de clientes son datos personales.

**Solución:**
```dart
final encryptionKey = await HiveAesCipher.generateSecureKey();
await Hive.openBox('sessions', encryptionCipher: HiveAesCipher(encryptionKey));
```

---

### 5.3 Rate limiting ausente

Sin rate limiting, un script puede agotar la cuota de Nominatim o saturar VROOM.

**Solución:**
```python
from slowapi import Limiter
limiter = Limiter(key_func=get_remote_address)

@limiter.limit("5/minute")
@router.post("/optimize")
async def optimize(req: OptimizeRequest):
    ...
```

---

### 5.4 CORS permisivo (`allow_origins=["*"]`)

**Archivo:** `app/main.py` línea 36

Permite que cualquier sitio web haga requests a la API desde el navegador.

**Solución:** Restringir a dominios conocidos:
```python
allow_origins=["https://api.tuempresa.es", "http://localhost:3000"]
```

---

### 5.5 Sin logging de auditoría

No hay registro de quién optimizó qué ruta, cuándo se marcaron las entregas ni qué
cambios manuales se hicieron.

**Propuesta:** Registrar en BD o log estructurado:
- Peticiones a `/api/optimize` con IP, timestamp y hash del contenido
- Cambios de estado de paradas con timestamp
- Accesos fallidos (API key incorrecta)

---

### 5.6 Cumplimiento RGPD — política de retención de datos

Cuando se implemente historial en base de datos, las direcciones de clientes son datos
personales bajo el RGPD. Se necesita:

- Política de retención: ¿cuánto tiempo se guardan los datos de reparto? (recomendado: 90 días)
- Endpoint de borrado: `DELETE /api/routes/{id}` — derecho al olvido
- Registro de actividad de tratamiento (RAT) documentado
- Aviso legal en la app: para qué se usan los datos
- Si hay expansión a múltiples empresas: el operador de datos de cada empresa es independiente

---

### 5.7 Dependencias con vulnerabilidades conocidas

No hay herramienta de auditoría de dependencias configurada. Una dependencia del backend
con CVE crítico podría estar presente semanas sin saberlo.

**Solución:**
```bash
# Backend
pip install pip-audit
pip-audit  # Detecta CVEs en requirements.txt

# Flutter
flutter pub audit  # Disponible en Flutter 3.7+
```
Añadir ambos a CI/CD para que fallen el build si hay CVE critico.

---

### 5.8 Secretos en código fuente

`ngrok` auth token, posibles API keys futuras y cualquier configuración sensible
no debe ir en el repositorio git ni en `api_config.dart` compilado en el APK.

**Solución:**
- Backend: variables de entorno via `.env` (nunca en git) con `python-dotenv`
- Flutter: `--dart-define-from-file=secrets.json` en el build — el archivo no entra en git
- GitHub: secretos en Settings → Secrets para uso en CI/CD

---

## 6. Negocio y operaciones (nivel empresa)

---

### 6.1 Historial diario de repartos con métricas

**Impacto:** Sin historial, no es posible:
- Saber cuántos paquetes se entregaron en el mes
- Identificar clientes con entregas recurrentes fallidas
- Justificar ante GLS o el cliente final qué pasó con un paquete
- Calcular eficiencia del repartidor por día y por zona

**Coste de implementación:** Bajo — añadir 2 tablas SQLite y un endpoint de sync.

---

### 6.2 Automatizar importación de hoja de reparto GLS

**Estado actual:** Proceso manual: PDF → CSV → importar. 15-30 minutos por jornada.

**Propuesta:** Endpoint `POST /api/import/pdf` con extracción automática:
- Ahorro de tiempo estimado: 20 min/día × 250 días laborables = **83 horas/año**
- Eliminación de errores de transcripción

---

### 6.3 Sistema de precios y facturación

Si la plataforma se ofrece a otras empresas de reparto, se necesita:
- Modelo de facturación: por paradas/mes, por empresa, por repartidor
- Panel de administración con uso por empresa
- Integración con pasarela de pago (Stripe es la opción estándar para SaaS B2B)
- Facturas automáticas mensuales en PDF

---

### 6.4 Configuración de zona de trabajo ampliable

**Estado actual:** Viewbox fijo a Posadas. Imposible repartir en Palma del Río o
Montoro sin editar `config.py`.

**Propuesta:**
- Parámetro `zone` en config: `ZONES = {"posadas": {...}, "palma_del_rio": {...}}`
- OSRM con mapa completo de Andalucía (ya está cargado)
- Viewbox dinámico según zona seleccionada en la app

---

### 6.5 Gestión de clientes frecuentes

Direcciones que aparecen todos los días (supermercados, comercios) se geocodifican
repetidamente aunque ya estén en caché.

**Propuesta:**
- BD de clientes frecuentes con coordenadas verificadas manualmente
- Al importar CSV, cruzar con esa BD y usar coords conocidas directamente
- Editor de clientes frecuentes en la web del operador

---

### 6.6 SLA interno y tiempo de respuesta garantizado

Para uso empresarial real, hay que definir:

- **Tiempo máximo de optimización:** 200 paradas en < 120s (actualmente podría superar)
- **Uptime objetivo:** 99% durante horario laboral (07:00-20:00)
- **Proceso de escalada:** Si el sistema falla, ¿hay plan B? (p.ej. Google Maps manual)
- **Ventana de mantenimiento:** ej. domingos 22:00-02:00

---

## 7. Monitorización y observabilidad

Esta sección cubre cómo saber en todo momento que el sistema funciona, detectar
problemas antes de que impacten a los repartidores, y analizar el comportamiento
histórico. Es imprescindible para cualquier sistema en producción.

---

### 7.1 Health checks en todos los niveles

**Estado actual:** Solo existe `GET /health` que devuelve `{"status": "ok"}` siempre,
sin comprobar OSRM, VROOM, ni si Nominatim responde.

**Propuesta de health check completo:**
```python
@app.get("/health/full")
async def full_health():
    checks = {}
    # OSRM
    try:
        r = requests.get(f"{OSRM_URL}/route/v1/...", timeout=3)
        checks["osrm"] = "ok" if r.status_code == 200 else "degraded"
    except:
        checks["osrm"] = "down"
    # VROOM
    checks["vroom"] = ...
    # Nominatim (test con dirección conocida)
    checks["nominatim"] = ...
    # Disco (espacio libre)
    checks["disk_gb_free"] = shutil.disk_usage("/").free / 1e9
    # RAM
    checks["ram_mb_free"] = psutil.virtual_memory().available / 1e6

    overall = "ok" if all(v == "ok" for v in checks.values()) else "degraded"
    return {"status": overall, "checks": checks, "timestamp": time.time()}
```

---

### 7.2 Métricas con Prometheus + Grafana

Para monitorización profesional sin coste de licencias:

**Stack gratuito y estándar:**
- `prometheus-fastapi-instrumentator` — expone métricas en `/metrics` automáticamente
- Prometheus — recolecta métricas cada 15s
- Grafana — dashboards visuales con alertas

**Métricas clave a monitorizar:**
```
http_requests_total{endpoint="/api/optimize", status="200"}
http_request_duration_seconds{endpoint="/api/optimize", p99}
geocoding_cache_hit_ratio
geocoding_failed_total
vroom_optimization_duration_seconds
osrm_snap_failed_total
active_delivery_sessions
```

**Añadir al `docker-compose.yml`:**
```yaml
prometheus:
  image: prom/prometheus
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
  ports:
    - "9090:9090"

grafana:
  image: grafana/grafana
  ports:
    - "3001:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=admin
```

**Coste:** Cero. Solo recursos de la máquina (Prometheus+Grafana: ~200 MB RAM).

---

### 7.3 Logging estructurado (JSON logs)

**Estado actual:** Los logs de Uvicorn son texto plano en `backend.log`. No se pueden
filtrar, agregar, ni analizar.

**Propuesta:**
```python
import structlog

logger = structlog.get_logger()

logger.info("geocoding_complete",
    address=address,
    result="cache_hit",
    duration_ms=elapsed,
    lat=lat, lon=lon
)
```

Con logs JSON, se puede hacer `grep '"result": "failed"'` o ingestarlos en Loki/Elastic.

**Campos mínimos recomendados:** `timestamp`, `level`, `event`, `duration_ms`,
`request_id`, `ip`, `endpoint`

---

### 7.4 Tracing distribuido

Cuando una petición de optimización falla, es difícil saber si falló en Nominatim,
OSRM, VROOM o en el código propio. El tracing distribuido asigna un ID único a cada
petición y registra cada llamada a servicios externos.

**Herramienta recomendada:** OpenTelemetry (estándar abierto) + Jaeger (gratuito)

```python
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

FastAPIInstrumentor.instrument_app(app)
RequestsInstrumentor().instrument()
```

Resultado: en Jaeger puedes ver exactamente cuánto tardó cada llamada a OSRM y VROOM.

---

### 7.5 Alertas automáticas

Una vez con métricas Prometheus, se pueden configurar alertas:

| Condición | Acción | Urgencia |
|-----------|--------|----------|
| OSRM down > 1 min | Email/Telegram al admin | Crítica |
| Error rate > 10% en 5 min | Telegram al admin | Alta |
| Latencia p99 > 30s | Slack al equipo técnico | Media |
| Disco < 5 GB libre | Email diario | Baja |
| Ninguna petición en 2h (horario laboral) | Check manual | Info |

**Herramienta:** Alertmanager (parte del stack Prometheus, gratuito)

---

### 7.6 Monitorización del dispositivo móvil

La app Flutter no envía ninguna telemetría cuando falla o se comporta de forma anómala.

**Propuesta:** Firebase Crashlytics (gratuito hasta 1M eventos/mes):
- Captura automática de excepciones no manejadas
- Stack trace completo con contexto
- Dashboard: "En los últimos 7 días, 3 usuarios experimentaron crash en DeliveryScreen"
- Muy fácil de integrar con el package `firebase_crashlytics`

**Alternativa sin Firebase:** Sentry (tier gratuito generoso, también muy bueno).

---

### 7.7 Dashboard operacional del día

Una página web sencilla que el jefe puede ver en el ordenador mientras el repartidor
está en ruta:

- Paradas completadas / pendientes / fallidas (actualización cada 30s)
- Posición GPS del repartidor en el mapa (si autorizado)
- Alerta si llevan > 15 min en la misma parada
- Botón para llamar al repartidor directamente desde el dashboard
- Gráfico diario: "rendimiento de hoy vs. media de la semana"

---

## 8. CI/CD y automatización de despliegues

Esta sección describe cómo automatizar compilaciones, tests y despliegues para que
actualizar el sistema no requiera intervención manual.

---

### 8.1 Pipeline GitHub Actions básico

**Estado actual:** Para actualizar el backend hay que hacer SSH al servidor, `git pull`,
y reiniciar Uvicorn manualmente. Para distribuir un nuevo APK hay que compilar
manualmente y enviar el archivo por WhatsApp/email.

**Pipeline propuesto (`/.github/workflows/deploy.yml`):**

```yaml
name: Build & Deploy

on:
  push:
    branches: [main]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: pytest app/tests/ -v
      - run: pip-audit  # Auditoría de CVEs

  build-apk:
    needs: test-backend
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.38.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --dart-define=ENV=prod --dart-define-from-file=secrets.json
      - uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: flutter_app/build/app/outputs/flutter-apk/app-release.apk

  deploy-backend:
    needs: test-backend
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: deploy
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /opt/repartir
            git pull origin main
            source venv/bin/activate
            pip install -r requirements.txt
            systemctl restart repartir-backend
```

**Resultado:** Cada `git push` a `main` lanza tests, compila APK y despliega el
backend automáticamente. El APK está disponible en GitHub Releases.

---

### 8.2 Distribución automática del APK

**Estado actual:** Hay que enviar el APK manualmente por WhatsApp.

**Propuestas:**
- **GitHub Releases:** Al etiquetar un commit con `v1.2.0`, Actions crea la release
  automáticamente con el APK adjunto. Los repartidores tienen la URL fija de descarga.
- **Firebase App Distribution:** Los repartidores reciben una notificación en el móvil
  cuando hay una nueva versión. Gratuito hasta 100 testers.
- **Google Play (canal interno):** Si hay presupuesto para la cuenta de desarrollador
  (25€ único), se puede distribuir por Play Store con canal de prueba cerrado.

---

### 8.3 Versionado semántico y changelog automático

**Estado actual:** La versión en `pubspec.yaml` se actualiza manualmente.

**Propuesta:**
- Conventional Commits: mensajes tipo `feat:`, `fix:`, `chore:` — formato estándar
- `semantic-release` genera automáticamente la versión nueva basándose en los commits
- CHANGELOG.md generado automáticamente con todos los cambios por versión

---

### 8.4 Entorno de staging

Antes de desplegar a producción, conviene probar en un entorno idéntico:

- VPS pequeño separado (2-4 €/mes) con los mismos servicios
- Rama `develop` → staging, rama `main` → producción
- URL staging: `https://staging-api.repartir.tuempresa.es`
- Los tests de integración corren contra staging, no contra producción

---

### 8.5 Rollback automático

Si el deploy falla (el health check no pasa después del despliegue), el script debe
revertir automáticamente a la versión anterior:

```bash
# En el servidor
git pull origin main && \
systemctl restart repartir-backend && \
sleep 5 && \
curl -f http://localhost:8000/health || \
(git stash && systemctl restart repartir-backend && echo "ROLLBACK realizado")
```

---

## 9. Escalabilidad geográfica — expansión a otras ciudades

Esta sección describe cómo pasar de operar solo en Posadas, Córdoba, a operar en
cualquier municipio de España (o del mundo).

---

### 9.1 Problema actual: todo está hardcodeado a Posadas

Los siguientes elementos están fijos al municipio de Posadas y requieren cambios
de código para operar en otro lugar:

| Elemento | Ubicación | Problema |
|----------|-----------|---------|
| `POSADAS_CENTER` | `config.py` | Centro del mapa fijo |
| `POSADAS_VIEWBOX` | `config.py` | Área de geocodificación fija |
| `START_ADDRESS` | `config.py` | Dirección del taller fija |
| Catálogo de calles Overpass | `geocoding.py` | Query fija a Posadas |
| Mapa OSRM | `docker-compose.yml` | `andalucia-latest.osrm` — funciona para Andalucía |
| Idioma Nominatim | `geocoding.py` | `accept-language: es` — OK para España |

**Impacto:** Un repartidor de Málaga no puede usar el sistema sin que un técnico
edite 5 archivos de código.

---

### 9.2 Configuración multi-zona

**Propuesta: archivo `zones.json`**

```json
{
  "posadas": {
    "name": "Posadas, Córdoba",
    "center": [37.805503, -5.099805],
    "viewbox": "-5.15,37.78,-5.06,37.83",
    "default_depot": "Av. de Andalucía, Posadas",
    "overpass_area": 3600346388
  },
  "malaga": {
    "name": "Málaga",
    "center": [36.720016, -4.420034],
    "viewbox": "-4.55,36.67,-4.35,36.77",
    "default_depot": "",
    "overpass_area": 3600343745
  },
  "sevilla": {
    "name": "Sevilla",
    "center": [37.388631, -5.982101],
    "viewbox": "-6.05,37.33,-5.90,37.45",
    "default_depot": "",
    "overpass_area": 3600342837
  }
}
```

- La empresa configura su zona al registrarse
- El catálogo de calles Overpass se descarga para esa zona
- No hay que tocar código para añadir una ciudad nueva

---

### 9.3 OSRM con mapa de España completo

**Estado actual:** `andalucia-latest.osrm` (~2 GB) — funciona para toda Andalucía.

**Opciones para escalar:**

| Mapa | Tamaño aprox. | Cobertura |
|------|---------------|-----------|
| `andalucia-latest.osrm` | ~2 GB | Andalucía (actual) |
| `spain-latest.osrm` | ~8 GB | España completa |
| `europe-latest.osrm` | ~50 GB | Europa |

**Propuesta:** Para expansión nacional, usar el mapa de España completo. El servidor
necesitaría 16+ GB RAM para cargarlo en memoria. Alternativa: usar el API público de
OSRM (`router.project-osrm.org`) para prototipos, con servidor propio para producción.

**Alternativa moderna: Valhalla** — motor de rutas con soporte de actualizaciones
incrementales (no hay que recargar todo el mapa al actualizar datos OSM).

---

### 9.4 Nominatim propio vs. API pública para volumen alto

**Estado actual:** Se usa el servidor público de Nominatim (`nominatim.openstreetmap.org`).
Los términos de uso limitan a 1 req/seg por IP y prohíben uso comercial intensivo.

**Opciones según volumen:**

| Escenario | Solución recomendada | Coste |
|-----------|---------------------|-------|
| < 50 req/día | API pública Nominatim | Gratis |
| 50-500 req/día | Nominatim propio en Docker | ~10€/mes (VPS) |
| > 500 req/día | Photon (alternativa más rápida) o Pelias | ~20-50€/mes |
| > 5.000 req/día | Google Maps Geocoding API | ~5€ por cada 1000 req |

**Photon** es especialmente interesante: open source, más rápido que Nominatim,
y admite búsqueda de texto libre con autocomplete.

---

### 9.5 Adaptar geocodificación a municipios sin numeración normalizada

En municipios rurales pequeños, muchas calles no tienen numeración en OSM ("Calle
Real, s/n"). El algoritmo actual asume número de casa. Habría que:

- Detectar `s/n` y buscar el centroide de la calle
- Ampliar el fuzzy matching con variantes dialectales regionales
- Permitir que el catálogo de calles OSM se actualice automáticamente cada semana
  con los datos más recientes de OpenStreetMap

---

### 9.6 Internacionalización (i18n) de la app

Si la app se expande a otras regiones de España o a mercados internacionales:

- Los textos en Dart están hardcodeados en español
- No hay soporte de múltiples idiomas
- `flutter_localizations` + archivos `.arb` — estándar de Flutter para i18n
- Dialectos: fechas en formato ES, separador decimal coma, etc.

Para una primera expansión a Portugal o Latinoamérica, el esfuerzo de traducción
sería bajo si los textos ya están en archivos `.arb`.

---

## 10. Escalabilidad de carga — más usuarios concurrentes

Esta sección describe qué ocurre si 10, 50 o 500 empresas usan el sistema
simultáneamente y cómo prepararse para ello.

---

### 10.1 Cuellos de botella actuales (análisis de capacidad)

Con la arquitectura actual, los límites de capacidad estimados son:

| Componente | Límite aprox. | Cuello de botella |
|------------|---------------|-------------------|
| Uvicorn (1 worker) | ~2 req/s ligeras | Síncrono, bloqueante |
| Nominatim público | 1 req/s | Rate limit externo |
| VROOM (1 instancia) | ~5-10 opt/min | CPU-intensivo |
| OSRM (1 instancia) | ~100 req/s | No es el cuello |
| Hive local | N/A | Solo 1 dispositivo |
| `geocode_cache.json` | ~1000 entradas eficiente | I/O del JSON dump |

**Conclusión:** Con el sistema actual, 2-3 empresas usando el sistema simultáneamente
comenzarían a experimentar degradación. No está diseñado para carga.

---

### 10.2 Escalado vertical (más potencia en la misma máquina)

Primer paso, más sencillo y económico:

- Más workers Uvicorn: `uvicorn app.main:app --workers 4`
  - Problema: el caché JSON y el estado en memoria no se comparte entre workers
  - Solución: Redis para caché compartida (ver 4.5)
- OSRM ya es multi-threaded, escala con CPUs
- VROOM puede correr múltiples instancias en puertos distintos con un load balancer

**Hetzner CX31 (4 CPU, 8 GB RAM):** ~10,99€/mes — soportaría cómodamente 10-15
empresas pequeñas con reparto diario.

---

### 10.3 Escalado horizontal (múltiples servidores)

Para 50+ empresas concurrentes o picos de demanda:

**Arquitectura propuesta:**
```
[App Flutter] → [Load Balancer (Nginx)]
                       ↓
        [API Server 1] [API Server 2] [API Server N]
                       ↓
               [Redis] [PostgreSQL]
                       ↓
        [OSRM Cluster] [VROOM Workers]
```

- **Load balancer:** Nginx o Traefik (gratuitos)
- **Sesiones sin estado:** Los API servers no guardan estado — todo en Redis/PG
- **OSRM:** Una sola instancia puede manejar carga muy alta (en Mapbox producción
  se sirve con instancias similares)
- **VROOM:** Escalar horizontalmente es trivial — más workers consumiendo de una cola
  Celery

---

### 10.4 Base de datos: desde SQLite hasta PostgreSQL

| Fase | Usuarios | BD recomendada | Notas |
|------|----------|----------------|-------|
| MVP | 1-5 empresas | SQLite | Sin configuración, perfecto para empezar |
| Crecimiento | 5-50 empresas | PostgreSQL | ACID, concurrencia, índices avanzados |
| Escala | 50-500 empresas | PostgreSQL + PgBouncer | Pool de conexiones |
| Gran escala | 500+ empresas | PostgreSQL con read replicas | Separar lecturas/escrituras |

Migrar de SQLite a PostgreSQL con SQLModel es prácticamente transparente — solo
cambia la connection string.

---

### 10.5 CDN para tiles del mapa

**Estado actual:** Cada dispositivo Flutter carga tiles de `tile.openstreetmap.org`
directamente. OSM tiene límite de uso y latencia variable.

**Problema a escala:** Con 1000 usuarios cargando mapas simultáneamente, OSM podría
bloquear las peticiones (su política prohíbe uso comercial intensivo).

**Solución:**
- **Stadia Maps:** 200.000 tiles/mes gratis, luego ~6$/mes. API compatible con OSM.
- **MapTiler:** Similar, con mapas más bonitos.
- **Servidor propio de tiles:** `TileServer-GL` (Docker) — usar si se tiene el mapa
  de España cargado de todas formas para OSRM.

---

### 10.6 Cola de trabajo para picos de demanda

Si todas las empresas lanzan su optimización a las 8:00 de la mañana:

**Sin colas:** 50 peticiones de optimización simultáneas → servidor saturado → timeouts

**Con Celery + Redis:**
- Las peticiones entran a la cola
- Los workers las procesan en orden (o con prioridad)
- La app muestra "Posición en cola: 3. Tiempo estimado: ~45s"
- Los workers pueden escalar horizontalmente según la carga

---

## 11. Multi-tenancia — múltiples empresas en la misma plataforma

Si el sistema se convierte en un SaaS que venden a otras empresas de reparto.

---

### 11.1 Modelo de multi-tenancia: shared vs. dedicated

Hay tres modelos principales, con trade-offs distintos:

| Modelo | Base de datos | Aislamiento | Coste por cliente | Complejidad |
|--------|---------------|-------------|-------------------|-------------|
| **Shared DB** | Una BD, `tenant_id` en cada tabla | Bajo | Muy bajo | Media |
| **Schema separado** | Un schema PostgreSQL por empresa | Medio | Bajo | Alta |
| **Instancia separada** | Un servidor completo por empresa | Alto | Alto | Baja |

**Recomendación para empezar:** Shared DB con `tenant_id`. Es lo más sencillo de
implementar y suficiente para 50-100 empresas.

---

### 11.2 Modelo de datos multi-tenant

```sql
-- Tabla central de empresas
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    plan TEXT DEFAULT 'free',  -- 'free', 'basic', 'pro'
    zone TEXT,                  -- ciudad/área de operación
    depot_lat REAL,
    depot_lon REAL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Usuarios (repartidores + operadores)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES organizations(id),
    email TEXT UNIQUE,
    role TEXT,  -- 'driver', 'operator', 'admin'
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Todas las tablas de negocio tienen org_id
CREATE TABLE routes (
    id UUID PRIMARY KEY,
    org_id UUID REFERENCES organizations(id),
    ...
);
```

---

### 11.3 Autenticación multi-tenant

- **Opción A (simple):** API Key por organización — fácil, sin sesiones
- **Opción B (robusta):** JWT con claim `org_id` — permite múltiples usuarios
  por empresa, roles y permisos

Para una app Flutter, JWT es la elección correcta a largo plazo:
```python
# Al optimizar, siempre filtrar por org del token
@router.post("/optimize")
async def optimize(req: OptimizeRequest, current_user: User = Depends(get_current_user)):
    # current_user.org_id viene del JWT
    # Nunca puede acceder a datos de otra empresa
    ...
```

---

### 11.4 Panel de administración SaaS

Para gestionar las empresas clientes:

- Listado de organizaciones: plan, uso del mes, última actividad
- Métricas por empresa: paradas procesadas, tasa de geocodificación exitosa
- Suspender/reactivar cuenta
- Ver el historial de facturación
- Soporte: ver logs de errores de una empresa específica

**Herramienta recomendada para MVP:** Retool o AppSmith — se pueden construir paneles
de administración en horas, sin código frontend.

---

### 11.5 Límites de uso por plan

Para monetizar y evitar abuso del servicio gratuito:

```python
PLAN_LIMITS = {
    "free": {
        "max_stops_per_day": 50,
        "max_routes_per_month": 20,
        "max_vehicles": 1,
        "geocoding_zones": 1,
    },
    "basic": {
        "max_stops_per_day": 200,
        "max_routes_per_month": 100,
        "max_vehicles": 3,
        "geocoding_zones": 3,
    },
    "pro": {
        "max_stops_per_day": 2000,
        "max_routes_per_month": 1000,
        "max_vehicles": 20,
        "geocoding_zones": "unlimited",
    }
}
```

---

## 12. Mantenimiento y operaciones del sistema

Esta sección describe los procesos operativos necesarios para mantener el sistema
sano a largo plazo. Un sistema sin mantenimiento acaba fallando.

---

### 12.1 Actualizaciones de datos OSM

Los datos de OpenStreetMap cambian continuamente: nuevas calles, numeraciones
corregidas, negocios que abren o cierran. Sin actualizaciones:

- El catálogo de calles de Overpass queda desactualizado en semanas
- OSRM puede rutar por calles que ya no existen o no poder rutar por calles nuevas

**Proceso recomendado:**
```bash
# crontab -e
# Actualizar mapa OSRM cada domingo a las 3:00 AM
0 3 * * 0 /opt/repartir/scripts/update_osrm.sh

# update_osrm.sh
wget -q https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf -O /tmp/osrm.pbf
docker exec osrm-posadas osrm-extract -p /profiles/car.lua /data/andalucia-latest.osrm
docker restart osrm-posadas
```

---

### 12.2 Backups automáticos

**Estado actual:** Cero backups. Si el servidor falla, se pierden:
- `geocode_cache.json` — meses de geocodificaciones manuales
- Historial de repartos (cuando se implemente)
- Configuración del sistema

**Estrategia 3-2-1:**
- **3** copias de los datos
- **2** medios de almacenamiento distintos
- **1** offsite (fuera del servidor principal)

**Implementación práctica:**
```bash
# crontab
0 2 * * * /opt/repartir/scripts/backup.sh

# backup.sh
DATE=$(date +%Y%m%d_%H%M)
tar -czf /backups/repartir_${DATE}.tar.gz \
    /opt/repartir/app/data/ \
    /opt/repartir/osrm/
# Subir a S3/Backblaze B2 (< 1€/mes para pocos GB)
rclone copy /backups/repartir_${DATE}.tar.gz backblaze:repartir-backups/
# Borrar backups de más de 30 días
find /backups -name "*.tar.gz" -mtime +30 -delete
```

---

### 12.3 Actualizaciones de dependencias

Las dependencias tienen vulnerabilidades de seguridad descubiertas continuamente.
Sin un proceso de actualización, el sistema acumula deuda técnica y riesgo.

**Proceso mensual:**
```bash
# Backend
pip-audit  # Ver CVEs
pip list --outdated  # Ver versiones desactualizadas
pip install --upgrade package_name
pytest  # Verificar que no se rompe nada

# Flutter
flutter pub outdated
flutter pub upgrade --major-versions
flutter test
```

**Automatización:** Dependabot (GitHub) crea PRs automáticos cuando hay nuevas
versiones de dependencias. Los tests de CI validan que el PR no rompe nada.

---

### 12.4 Rotación de logs

**Estado actual:** `backend.log` crece indefinidamente. En 6 meses puede ocupar varios
GB y llenar el disco del servidor.

**Solución:** `logrotate` (incluido en Linux):
```
# /etc/logrotate.d/repartir
/opt/repartir/backend.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        kill -HUP $(lsof -ti :8000) 2>/dev/null || true
    endscript
}
```

---

### 12.5 Proceso de actualización de la app Flutter

Con el sistema actual (APK distribuido por WhatsApp), actualizar requiere:
1. Compilar APK en el ordenador del desarrollador
2. Enviar por WhatsApp al repartidor
3. El repartidor desinstala la versión anterior y instala la nueva

**Problemas:** El repartidor puede olvidarse, instalar la versión equivocada, o seguir
usando una versión antigua con bugs.

**Solución:**
- In-app update check: al abrir la app, consultar la versión mínima requerida al backend
- Si la versión instalada es menor: pantalla de bloqueo con enlace de descarga
- Si es recomendada pero no obligatoria: snackbar "Hay una nueva versión disponible"

```dart
// Al arrancar la app
final minVersion = await ApiService.getMinRequiredVersion();
final currentVersion = await PackageInfo.fromPlatform().version;
if (Version.parse(currentVersion) < Version.parse(minVersion)) {
  // Mostrar pantalla de actualización obligatoria
}
```

---

### 12.6 Documentación técnica del sistema

**Estado actual:** El conocimiento del sistema está en la cabeza del desarrollador
y en el CLAUDE.md. Si hay que pasar el sistema a otro técnico, no hay documentación
de operaciones.

**Documentos mínimos recomendados:**
- **Runbook:** Qué hacer cuando OSRM no arranca, cuando falla la geocodificación, etc.
- **Architecture Decision Records (ADR):** Por qué se eligió VROOM sobre OR-Tools,
  por qué Hive sobre SQLite local, etc.
- **Playbook de incidentes:** Pasos a seguir si hay un outage durante el reparto del día
- **Onboarding de desarrollador:** Cómo configurar el entorno desde cero en 30 min

---

## 13. Resiliencia y recuperación ante desastres

---

### 13.1 Escenarios de fallo y planes de contingencia

| Escenario | Probabilidad | Impacto | Plan de contingencia |
|-----------|-------------|---------|---------------------|
| OSRM falla durante reparto | Media | Alto | La app funciona con ruta cacheada, sin segmentos nuevos |
| Servidor backend apagado | Baja | Crítico | Scripts de auto-restart, monitoring con alerta |
| Disco lleno en servidor | Media | Crítico | Rotación de logs, alertas de uso de disco |
| ngrok cambia URL | Alta (cada restart) | Alto | Servidor propio (ver 4.1) |
| Teléfono del repartidor sin batería | Alta | Medio | Ruta impresa como backup |
| Sin cobertura 4G | Media | Medio | Modo offline con ruta cacheada |
| Pérdida de datos Hive | Baja | Alto | Esquema versioning + migración |
| Servidor hackeado | Muy baja | Crítico | API key, rate limiting, backups offsite |

---

### 13.2 Objetivo de tiempo de recuperación (RTO/RPO)

Para un sistema de reparto, los SLOs realistas son:

- **RPO (Recovery Point Objective):** Máximo 24h de pérdida de datos
  → Backups diarios son suficientes
- **RTO (Recovery Time Objective):** Sistema operativo en < 2h tras fallo
  → Script de instalación automática en VPS nuevo

**Script de recuperación:**
```bash
# recover.sh — restaurar todo el sistema en un VPS nuevo en < 30 min
apt install docker.io docker-compose-v2 python3-venv nginx certbot
git clone https://github.com/tuempresa/repartir /opt/repartir
cd /opt/repartir
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
rclone copy backblaze:repartir-backups/latest.tar.gz /tmp/
tar -xzf /tmp/latest.tar.gz -C /opt/repartir/
./start.sh start
# En < 30 min el sistema está operativo con datos del día anterior
```

---

### 13.3 Modo degradado (graceful degradation)

Cuando un componente falla, el sistema no debe caerse completamente:

- **VROOM caído:** Mostrar error claro "Optimizador no disponible. Puedes usar la ruta
  manual o volver a intentarlo en 5 minutos." No bloquear el acceso al historial.
- **Nominatim sin respuesta:** Usar la caché local. Si no hay caché, pedir al usuario
  que sitúe manualmente en el mapa.
- **OSRM caído:** Permitir repartir con la ruta ya calculada (cacheada en Hive).
  Desactivar solo la navegación por segmentos.
- **Sin internet en el teléfono:** Continuar con la ruta cargada. Sincronizar al
  recuperar conexión.

---

### 13.4 Tests de carga y caos

Antes de ir a producción con múltiples usuarios:

- **Locust** (Python) para simular 10, 50, 100 usuarios concurrentes lanzando
  optimizaciones simultáneas
- **Chaos engineering básico:** Apagar OSRM manualmente mientras hay peticiones en curso
  y verificar que el sistema se recupera y los circuit breakers funcionan
- **Test de disco lleno:** Llenar el disco artificialmente y verificar el comportamiento

---

## 14. Costes e infraestructura por escenario

Estimación de costes reales para distintas etapas de crecimiento.

---

### 14.1 Escenario A: Sistema actual (1 empresa, 1 repartidor)

**Costes mensuales:**

| Componente | Coste |
|------------|-------|
| PC/servidor local | 0€ (ya existe) |
| ngrok gratuito | 0€ |
| Nominatim público | 0€ |
| OSRM (Docker local) | 0€ |
| Electricidad del PC (24/7) | ~8-15€ |
| **Total** | **~8-15€/mes** |

**Riesgo:** Si el PC falla durante el reparto, no hay backup.

---

### 14.2 Escenario B: Servidor propio (1-5 empresas)

**Costes mensuales:**

| Componente | Coste |
|------------|-------|
| Hetzner CX21 (2 vCPU, 4 GB RAM) | 5,77€ |
| Dominio `.es` | ~0,83€ (10€/año) |
| SSL (Let's Encrypt) | 0€ |
| Backblaze B2 (backups ~10 GB) | ~0,60€ |
| Nominatim propio (mismo VPS) | 0€ |
| Monitoring (Grafana Cloud free tier) | 0€ |
| **Total** | **~7€/mes** |

**Nota:** Hetzner CX21 aguanta cómodamente 2-3 optimizaciones concurrentes.

---

### 14.3 Escenario C: SaaS para 10-50 empresas

**Costes mensuales:**

| Componente | Coste |
|------------|-------|
| Hetzner CX41 (4 vCPU, 8 GB RAM) | 15,90€ |
| PostgreSQL gestionado (Supabase free o Neon) | 0-25€ |
| Redis (Upstash free tier o Hetzner) | 0-5€ |
| Backblaze B2 (50 GB) | 3€ |
| MapTiler/Stadia Maps (tiles mapa) | 0-10€ |
| Firebase Crashlytics + Analytics | 0€ |
| GitHub Actions (CI/CD) | 0€ |
| Sentry (error tracking) | 0€ (26k eventos/mes gratis) |
| **Total** | **~20-60€/mes** |

**Ingresos estimados:** 10 empresas × 30€/mes = 300€/mes.
**Margen:** ~80% — altamente rentable desde el primer cliente.

---

### 14.4 Escenario D: SaaS para 100-500 empresas

| Componente | Coste |
|------------|-------|
| 3× Hetzner CX41 (API servers) | 47,70€ |
| Hetzner CCX33 (OSRM, 8 vCPU) | 35,80€ |
| Hetzner CX21 (Load balancer + Redis) | 5,77€ |
| PostgreSQL (Supabase Pro o self-hosted) | 25-100€ |
| CDN tiles mapa | 20-50€ |
| Backups y monitoring | 20€ |
| **Total infraestructura** | **~155-260€/mes** |

**Ingresos estimados:** 200 empresas × 30€/mes = 6.000€/mes.
**Margen después de costes:** ~95% — escalabilidad económica muy favorable.

---

### 14.5 Comparativa make vs. buy

Para algunos componentes, comparar construir vs. usar servicio externo:

| Componente | Build (coste) | Buy (coste) | Recomendación |
|------------|---------------|-------------|---------------|
| OSRM | 0€ + servidor | — | Build: OSRM es gratuito |
| Geocodificación | Nominatim propio ~5€ | Google Maps ~50€/mes | Build hasta 5000 req/día |
| Optimización | VROOM 0€ + CPU | OR-Tools cloud 0€ | Build: VROOM es excelente |
| Push notifications | FCM gratuito | — | FCM (Google) gratuito |
| Auth | JWT propio 0€ | Auth0 ~23€/mes | Build hasta 1000 usuarios |
| Email transaccional | Resend 0€ (3000/mes) | SendGrid 0€ | Resend o SendGrid |

---

## 15. Roadmap de producto a 18 meses

Secuencia recomendada de implementación, priorizando impacto y riesgo.

---

### Fase 0: Estabilización (1-2 meses) — hacer lo que ya existe robusto

**Prioridad máxima — no escalar hasta completar esto:**

1. ✅ API Key básica para proteger la API (ver 5.1)
2. ✅ Servidor propio con URL fija — eliminar dependencia de ngrok (ver 4.1)
3. ✅ Health check completo + alertas Telegram básicas (ver 7.1)
4. ✅ Backups automáticos diarios (ver 12.2)
5. ✅ Corregir bugs críticos: 1.1, 1.2, 1.9, 1.11 (ver sección 1)
6. ✅ Tests básicos de las funciones críticas de geocodificación (ver 4.8)

**Coste estimado:** Tiempo técnico. Infraestructura: ~7€/mes.

---

### Fase 1: Producto completo (2-4 meses) — funcionalidades clave

1. Historial de repartos en SQLite (ver 3.1)
2. Exportar CSV de resultados (ver 2.3)
3. Dashboard web básico del operador (ver 3.2)
4. Extracción automática de PDF de GLS (ver 3.10)
5. Soporte multi-vehículo (ver 3.3)
6. Notificaciones Telegram al operador (ver 3.11)
7. Foto como prueba de entrega (ver 3.7)

**Coste estimado:** 2-4 semanas de desarrollo. Sin costes adicionales de infraestructura.

---

### Fase 2: Preparación para SaaS (4-8 meses) — arquitectura multi-tenant

1. Sistema de autenticación JWT con organizaciones (ver 11.3)
2. Multi-tenancia: tenant_id en todas las tablas (ver 11.2)
3. Configuración multi-zona (ver 9.2)
4. Pipeline CI/CD con GitHub Actions (ver 8.1)
5. Monitoring completo: Prometheus + Grafana (ver 7.2)
6. Logging estructurado (ver 7.3)
7. Rate limiting y circuit breakers (ver 4.10, 5.3)

**Coste estimado:** 1-2 meses de desarrollo. Infraestructura: ~20-30€/mes.

---

### Fase 3: Lanzamiento SaaS (8-12 meses) — primeros clientes externos

1. Landing page con demo
2. Sistema de registro de empresas con onboarding guiado
3. Pasarela de pago (Stripe) con planes (ver 11.5)
4. Panel de administración SaaS (ver 11.4)
5. Documentación para clientes (guía de usuario, FAQ)
6. Soporte al cliente (email/chat básico)
7. App en Google Play (canal interno) para distribución profesional

**Coste estimado:** 2-3 meses de desarrollo + 25€ Play Store. Infraestructura: ~60€/mes.
**ROI potencial:** 10 clientes × 30€/mes = 300€/mes desde el primer mes.

---

### Fase 4: Escalabilidad y crecimiento (12-18 meses)

1. Expansión a mapa de España completo (ver 9.3)
2. Cola de tareas con Celery (ver 4.4)
3. Caché Redis compartida (ver 4.5)
4. Nominatim propio o Photon (ver 9.4)
5. Firebase Crashlytics en la app (ver 7.6)
6. OSRM con Valhalla (actualizaciones incrementales)
7. API pública para integraciones ERP

---

## Resumen de prioridades

| # | Mejora | Área | Impacto | Esfuerzo |
|---|--------|------|---------|----------|
| 1 | Autenticación API mínima (API Key) | Seguridad | Crítico | 3h |
| 2 | Servidor propio + URL fija (eliminar ngrok) | Infraestructura | Crítico | 1 día |
| 3 | Backups automáticos | Operaciones | Crítico | 2h |
| 4 | Coords falsas en paradas fallidas (1.1) | Backend | Alto | 1h |
| 5 | Autoguardado estado reparto (1.2) | Flutter | Alto | 2h |
| 6 | Health check completo + alertas | Monitoring | Alto | 4h |
| 7 | docker-compose: health checks + límites (1.13) | Infra | Alto | 1h |
| 8 | Botón cancelar en progreso de cálculo | Flutter UX | Medio | 2h |
| 9 | Precarga catálogo calles en startup | Backend | Medio | 1h |
| 10 | Validar coords dentro del viewbox | Backend/Flutter | Medio | 2h |
| 11 | Exportar CSV resultado de reparto | Flutter | Medio | 3h |
| 12 | Reintentar geocodif. con backoff | Backend | Medio | 2h |
| 13 | CI/CD con GitHub Actions | DevOps | Alto | 1 día |
| 14 | Tests automáticos backend | Técnico | Alto | 1 semana |
| 15 | Logging estructurado JSON | Observabilidad | Alto | 4h |
| 16 | Historial de repartos (SQLite) | Backend+Flutter | Alto | 2 semanas |
| 17 | Cifrado de datos Hive | Seguridad | Alto | 2h |
| 18 | Rate limiting API | Seguridad | Alto | 2h |
| 19 | Multi-vehículo real (VRP) | Backend+Flutter | Alto | 2 semanas |
| 20 | Dashboard web del operador | Negocio | Alto | 2-3 semanas |
| 21 | Extracción automática PDF GLS | Negocio | Alto | 1 semana |
| 22 | Prometheus + Grafana + Alertmanager | Monitoring | Alto | 1 día |
| 23 | Async endpoints + httpx | Escalabilidad | Medio | 1 semana |
| 24 | Redis caché compartida | Escalabilidad | Medio | 2-3 días |
| 25 | Multi-zona (config geográfica) | Escalabilidad geo | Alto | 1 semana |
| 26 | Modo offline completo | Flutter | Medio | 2 semanas |
| 27 | Job queue (Celery) | Escalabilidad | Bajo-ahora | 2 semanas |
| 28 | Multi-tenancia completa | SaaS | Muy alto | 4-6 semanas |
| 29 | Integración ERP / GLS API | Negocio | Muy alto | Largo plazo |
| 30 | OSRM mapa España completo | Escalabilidad geo | Alto | 2 días (datos) |
