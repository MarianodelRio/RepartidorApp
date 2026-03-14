# Backend — Reglas de trabajo

## Capas internas

```
routers/      ← validación de entrada y serialización. Sin lógica de negocio.
services/     ← toda la lógica. Es donde vive el trabajo real.
utils/        ← funciones puras sin estado.
core/config.py← fuente única de configuración. Todos los valores vienen de aquí.
app/data/     ← caché en disco (JSON). Es estado runtime, no código.
```

La dirección del flujo es siempre: router → service → util. No saltarse capas.

## Módulos por nivel de riesgo

**Alto — proponer antes de implementar, cambios mínimos, ejecutar suite completo tras modificar**

- `services/routing.py`: integra LKH3 + OSRM + snap cache + matriz de distancias. Cambios aquí tienen efecto cascada en resultados de ruta y en la caché persistida en disco.
- `services/geocoding.py`: llama a Google APIs + fuzzy matching + caché en disco. Los errores aquí son caros (llamadas externas), pueden ser silenciosos (fallos suaves) y difíciles de reproducir.

**Medio — revisar impacto antes de cambiar**

- `services/catalog.py`: Overpass API + catálogo OSM. Afecta a la validación previa a geocodificar.
- `core/config.py`: cualquier cambio de valor afecta a todo el backend. Documentar el motivo.
- `routers/validation.py`: pipeline de validación de direcciones. Estado intermedio entre geocoding y optimize.

**Bajo — cambios rutinarios**

- `routers/optimize.py`, `routers/system.py`: capas finas, mayormente serialización.
- `models/`, `utils/`: funciones puras, bien cubiertas por tests.

## Zonas de cambio controlado

- `app/data/*.json`: son estado runtime generado automáticamente. No editar directamente. Si hay que limpiarlos, es una decisión del usuario.
- `core/config.py`: es la fuente única. Si se cambia un valor por defecto, dejar claro por qué.

## Tests

Los tests viven en `tests/` (sibling de `app/`). La estructura es un archivo por servicio o capa lógica.

**Tests puros** (no necesitan `.env` ni servicios externos — siempre ejecutables):
- `test_dedup.py`, `test_geocoding_pure.py`, `test_routing_pure.py`, `test_catalog_pure.py`

**Tests de integración** (necesitan OSRM activo y `GOOGLE_API_KEY`):
- `test_geocoding_service.py`, `test_routing_service.py`

Al añadir funcionalidad en un servicio, añadir el test correspondiente en el archivo de ese servicio.

Comando para ejecutar todo (tests + cobertura + mypy): `./run_tests.sh`
Solo tests: `python -m pytest`
Solo tipado: `python -m mypy app/`
