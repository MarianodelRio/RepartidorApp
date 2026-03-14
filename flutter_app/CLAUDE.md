# Flutter App — Reglas de trabajo

## Capas internas

```
screens/                   ← UI y navegación. Sin lógica de negocio.
services/
  ├── api_service.dart      ← toda la comunicación HTTP con el backend
  ├── persistence_service.dart ← persistencia local (Hive)
  ├── csv_service.dart      ← parseo de CSV de entrada
  └── location_service.dart ← GPS
models/                    ← modelos de datos. Sin dependencias de UI.
widgets/                   ← componentes reutilizables.
config/
  ├── api_config.dart       ← URL del backend (ver abajo)
  └── app_theme.dart        ← tema visual
```

## URL del backend

`lib/config/api_config.dart` es el único lugar donde vive la URL del backend.

- **Debug local** (Flutter web o emulador en el mismo PC): `http://127.0.0.1:8000`
- **APK en dispositivo físico**: URL del túnel ngrok activo

Nunca hardcodear la URL en otro lugar. Antes de compilar un APK release, verificar que apunta a ngrok y no a localhost.

## Persistencia

Hive es la solución de persistencia local. No introducir alternativas.

## Target

Android es el target activo. El código iOS existe en el repo pero no es el objetivo.

## Zona de cambio controlado

- `android/`: tocar solo para permisos o configuración de build. Cambios aquí pueden romper el APK de formas no obvias; revisar con cuidado.

## Calidad

`dart analyze` debe pasar con 0 warnings antes de proponer cualquier cambio.

Tests: `flutter test` desde `flutter_app/`
Cobertura objetivo: ≥ 98% sobre modelos y servicios.
