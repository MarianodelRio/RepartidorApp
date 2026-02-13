import 'package:geolocator/geolocator.dart';

/// Servicio de geolocalización del dispositivo.
class LocationService {
  /// Obtiene la ubicación actual del dispositivo.
  /// Devuelve [Position] o lanza excepción descriptiva.
  static Future<Position> getCurrentPosition() async {
    // 1. Verificar que el servicio de ubicación está activo
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
        'El servicio de ubicación está desactivado. '
        'Actívalo en Ajustes del dispositivo.',
      );
    }

    // 2. Verificar/solicitar permisos
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException(
          'Permiso de ubicación denegado. '
          'La app necesita acceder al GPS para usar tu ubicación como origen.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        'Permiso de ubicación denegado permanentemente. '
        'Ve a Ajustes > Aplicaciones para concederlo.',
      );
    }

    // 3. Obtener posición
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }
}

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);

  @override
  String toString() => message;
}
