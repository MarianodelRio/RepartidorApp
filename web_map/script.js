// script.js - mapa de Posadas con búsqueda de calles y coords al clicar

document.addEventListener('DOMContentLoaded', () => {
  const POSADAS = [37.8017289, -5.1070310];
  const DEFAULT_ZOOM = 14;

  if (typeof L === 'undefined') {
    document.getElementById('message').textContent = 'Error: Leaflet no se cargó.';
    return;
  }

  const map = L.map('map').setView(POSADAS, DEFAULT_ZOOM);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
  }).addTo(map);

  const markerLayer = L.layerGroup().addTo(map);
  const clickLayer = L.layerGroup().addTo(map);

  const input   = document.getElementById('street-input');
  const btn     = document.getElementById('search-btn');
  const clearBtn = document.getElementById('clear-btn');
  const message = document.getElementById('message');
  const coordsEl = document.getElementById('coords-display');

  // --- coordenadas al mover el ratón ---
  map.on('mousemove', (e) => {
    coordsEl.textContent = `${e.latlng.lat.toFixed(6)}, ${e.latlng.lng.toFixed(6)}`;
  });

  // --- clic en el mapa → marker con coords + botón copiar ---
  map.on('click', (e) => {
    clickLayer.clearLayers();
    const { lat, lng } = e.latlng;
    const coordStr = `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
    L.popup()
      .setLatLng([lat, lng])
      .setContent(
        `<div style="font-size:13px">
          <b>Coordenadas</b><br>
          Lat: ${lat.toFixed(6)}<br>
          Lon: ${lng.toFixed(6)}<br>
          <button onclick="navigator.clipboard.writeText('${coordStr}').then(()=>this.textContent='✓ Copiado')"
                  style="margin-top:6px;padding:3px 8px;cursor:pointer">
            Copiar
          </button>
        </div>`
      )
      .openOn(map);
    L.circleMarker([lat, lng], { radius: 6, color: '#e74c3c', fillColor: '#e74c3c', fillOpacity: 0.8 })
      .addTo(clickLayer);
  });

  function showMessage(text, isError = false) {
    message.textContent = text;
    message.style.color = isError ? 'crimson' : '#333';
  }

  function clearResults() {
    markerLayer.clearLayers();
    clickLayer.clearLayers();
    showMessage('');
  }

  async function buscarCalle(nombre) {
    if (!nombre.trim()) {
      showMessage('Escribe un nombre de calle.', true);
      return;
    }
    showMessage('Buscando...');
    markerLayer.clearLayers();

    const params = new URLSearchParams({
      format: 'json',
      street: nombre.trim(),
      city: 'Posadas',
      county: 'Córdoba',
      state: 'Andalucía',
      country: 'España',
      addressdetails: '1',
      limit: '8'
    });

    try {
      const res = await fetch(`https://nominatim.openstreetmap.org/search?${params}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      if (!data.length) {
        showMessage('Sin resultados para esa calle en Posadas.', true);
        return;
      }

      const bounds = [];
      data.forEach((item, i) => {
        const lat = parseFloat(item.lat);
        const lon = parseFloat(item.lon);
        bounds.push([lat, lon]);
        const marker = L.marker([lat, lon]).addTo(markerLayer);
        marker.bindPopup(
          `<div style="font-size:12px;max-width:220px">
            <b>${i + 1}. ${item.display_name}</b><br>
            <span style="color:#555">${lat.toFixed(6)}, ${lon.toFixed(6)}</span><br>
            <button onclick="navigator.clipboard.writeText('${lat.toFixed(6)}, ${lon.toFixed(6)}').then(()=>this.textContent='✓ Copiado')"
                    style="margin-top:5px;padding:2px 7px;cursor:pointer;font-size:11px">
              Copiar coords
            </button>
          </div>`
        );
        if (i === 0) marker.openPopup();
      });

      if (bounds.length === 1) {
        map.setView(bounds[0], 17);
      } else {
        map.fitBounds(bounds, { padding: [40, 40], maxZoom: 17 });
      }
      showMessage(`${data.length} resultado${data.length > 1 ? 's' : ''} encontrado${data.length > 1 ? 's' : ''}.`);
    } catch (err) {
      console.error(err);
      showMessage('Error al buscar. Comprueba la conexión.', true);
    }
  }

  btn.addEventListener('click', () => buscarCalle(input.value));
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') buscarCalle(input.value); });
  clearBtn.addEventListener('click', () => {
    input.value = '';
    clearResults();
    map.setView(POSADAS, DEFAULT_ZOOM);
  });
});
