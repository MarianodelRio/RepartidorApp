# web_map — Visualizador de mapa de Posadas (Córdoba)

Herramienta web simple para explorar el mapa de Posadas y verificar geocodificación de calles.
Usa Leaflet.js + Nominatim (OpenStreetMap). Sin dependencias externas en tiempo de ejecución: Leaflet está incluido localmente en `lib/`.

## Arrancar

```bash
cd /home/mariano/Desktop/app_repartir/web_map
python -m http.server 5500
```

Abrir en el navegador: <http://localhost:5500>

> Si el puerto está ocupado, cambia el número: `python -m http.server 5501`

## Funcionalidades

- **Búsqueda de calles** — escribe el nombre y pulsa Enter o "Buscar". Muestra hasta 8 resultados como marcadores.
- **Clic en el mapa** — abre un popup con las coordenadas (lat, lon) del punto y botón "Copiar".
- **Hover** — muestra las coordenadas del cursor en tiempo real (esquina superior derecha del header).
- **Limpiar** — elimina marcadores y vuelve a la vista inicial de Posadas.

## Archivos

```
web_map/
├── index.html      # Estructura HTML
├── script.js       # Lógica: mapa, búsqueda Nominatim, coords al clicar
├── styles.css      # Estilos
└── lib/
    ├── leaflet.js
    ├── leaflet.css
    └── images/     # Iconos de marcadores
```

## Configuración

- Centro del mapa: `37.8017289, -5.1070310` (Posadas, Córdoba)
- Zoom inicial: 14
- Búsqueda acotada a Posadas · Córdoba · Andalucía · España

## Depuración

- Si el mapa no aparece: abre DevTools (F12) → Network y comprueba que `lib/leaflet.js` y `lib/leaflet.css` responden 200.
- Si `L is undefined` en consola: verifica que `lib/leaflet.js` está presente.
