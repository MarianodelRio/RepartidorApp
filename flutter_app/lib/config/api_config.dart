/// Configuración de conexión al backend — Zero-Config.
///
/// URL fija apuntando al túnel ngrok de producción.
/// No requiere configuración por parte del usuario.
class ApiConfig {
  ApiConfig._();

  /// URL por defecto para desarrollo local. Cambia a tu túnel/URL de producción
  /// si necesitas exponer la API públicamente.
  static const String baseUrl = 'http://127.0.0.1:8000';
  /// static const String baseUrl = 'https://unpermanently-repairable-devon.ngrok-free.dev';

  // ── Endpoints ──
  static const String optimizeEndpoint = '/api/optimize';
  static const String healthEndpoint = '/health';
  static const String servicesStatusEndpoint = '/api/services/status';

  // ── Validación ──
  static const String validationStartEndpoint = '/api/validation/start';

  /// Timeout generoso para /api/optimize.
  /// El geocoding de 70-100 direcciones puede tardar 3-5 minutos.
  static const Duration timeout = Duration(minutes: 10);
}
