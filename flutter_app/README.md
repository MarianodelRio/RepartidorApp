# 📱 RepartidorApp — Flutter

> App móvil Android para gestionar rutas de reparto optimizadas.
> Parte del sistema **Repartidor v1.4.0** (FastAPI + OSRM + VROOM).

---

## Flujo de pantallas

```
SplashScreen
    └─▶ ImportScreen          ← Importar CSV con paradas
          └─▶ LoadingOrderScreen  ← Progreso de geocodificación y optimización
                └─▶ RoutePickerScreen   ← Seleccionar ruta (1 o 2 vehículos)
                      └─▶ ResultScreen        ← Mapa con ruta completa
                            └─▶ DeliveryScreen      ← Navegación GPS + marcar entregas
```

---

## Formato CSV de entrada

```csv
cliente,direccion,ciudad,nota
Ana García,Calle Mayor 1,Posadas,2º A
GLS Librería Papelería,Calle Gaitán 24,Posadas,
Juan Rodríguez,Avenida Principal 3,Posadas,bajo derecha
```

- **`nota`** es opcional. Si la columna no existe, la app funciona igual que antes.
- Varias filas con la misma dirección se agrupan en una sola parada (multi-paquete).
- La nota se muestra en la tarjeta de entrega pero **no afecta a geocodificación ni a la ruta**.

---

## Comandos de desarrollo

```bash
# Instalar dependencias
flutter pub get

# Ejecutar en dispositivo/emulador conectado
flutter run

# Compilar APK de release
flutter build apk --release
# Resultado: build/app/outputs/flutter-apk/app-release.apk

# Análisis estático
flutter analyze

# Ejecutar como web (para depuración rápida sin móvil)
flutter run -d web-server --web-port=8080
```

---

## Estructura de `lib/`

```
lib/
├── config/
│   ├── api_config.dart       # URL del backend (ngrok en producción)
│   └── app_theme.dart        # Colores y tema Material 3
│
├── models/
│   ├── csv_data.dart         # Datos crudos del CSV importado
│   ├── route_models.dart     # StopInfo, Package, RouteSummary...
│   ├── validation_models.dart# GeocodedStop, FailedStop
│   └── delivery_state.dart   # DeliverySession, DeliveryStop, StopStatus
│
├── services/
│   ├── api_service.dart      # Llamadas HTTP al backend FastAPI
│   ├── csv_service.dart      # Parseo CSV (detecta columnas automáticamente)
│   ├── gps_service.dart      # Wrapper Geolocator
│   └── persistence_service.dart # Sesión de reparto en Hive
│
├── screens/
│   ├── splash_screen.dart
│   ├── import_screen.dart    # Importar CSV + validación + cálculo de ruta
│   ├── loading_order_screen.dart
│   ├── route_picker_screen.dart
│   ├── result_screen.dart    # Mapa completo + exportar CSV
│   └── delivery_screen.dart  # Navegación GPS activa
│
└── widgets/
    ├── route_map.dart        # Mapa flutter_map con animación de cámara
    └── stops_list.dart       # Lista de paradas con paquetes y notas
```

---

## Dependencias principales

| Paquete | Uso |
|---|---|
| `flutter_map` ^7.0.2 | Mapa OSM |
| `latlong2` ^0.9.1 | Coordenadas |
| `geolocator` ^13.0.0 | GPS |
| `hive` ^2.2.3 | Persistencia local |
| `file_picker` ^8.0.0 | Selector de CSV |
| `http` ^1.2.0 | Llamadas al backend |
| `url_launcher` ^6.2.0 | Abrir Google Maps |
| `permission_handler` ^11.0.0 | Permisos Android |

---

## Configuración del backend

Edita `lib/config/api_config.dart`:

```dart
// Desarrollo local (Flutter web o emulador)
static const String baseUrl = 'http://127.0.0.1:8000';

// Producción (APK en móvil real vía ngrok)
static const String baseUrl = 'https://<tu-tunel>.ngrok-free.dev';
```

---

## Novedades v1.4.0

- **Paradas sin geocodificar en null**: `lat`/`lon` de `StopInfo` y `DeliveryStop` son `double?`; las paradas fallidas muestran ⚠️ y aparecen al final de la ruta sin enviarse a VROOM.
- **Diálogo Reordenar mejorado**: badge con número de orden fijo y paquetes con cliente + nota visibles.
- **Guards null-safe**: navegación externa, marcadores en mapa y tramo GPS comprueban coordenadas antes de operar.

## Novedades v1.3.0

- **Marcar entregada desde Reordenar**: botón ✅ en el diálogo de reordenación elimina la parada al instante.
- **Título de parada = dirección**: en todas las pantallas el título principal es la dirección física.

## Novedades v1.2.0

- **Campo `nota` por paquete**: piso, instrucciones o referencia visible en la tarjeta de entrega.
- **Ruta actualizada cada 30 s**: el polígono GPS→siguiente parada se refresca automáticamente mientras conduces.
- **Transiciones de cámara animadas**: al avanzar parada, el mapa vuela suavemente (900 ms easeInOutCubic) enmarcando posición y nuevo destino.
