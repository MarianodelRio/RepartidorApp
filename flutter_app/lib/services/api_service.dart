import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/route_models.dart';
import '../models/validation_v3_models.dart';

/// Servicio de comunicación con el backend FastAPI.
class ApiService {
  /// Headers comunes para todas las peticiones.
  /// Incluye 'ngrok-skip-browser-warning' para evitar la página
  /// de advertencia de ngrok free en peticiones programáticas.
  static Map<String, String> get _defaultHeaders => {
        'ngrok-skip-browser-warning': '1',
      };

  /// Headers para peticiones JSON.
  static Map<String, String> get _jsonHeaders => {
        ..._defaultHeaders,
        'Content-Type': 'application/json',
      };

  /// Verifica que el backend esté vivo.
  static Future<bool> healthCheck() async {
    try {
      final url = '${ApiConfig.baseUrl}${ApiConfig.healthEndpoint}';
      final response = await http
          .get(Uri.parse(url), headers: _defaultHeaders)
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Verifica el estado de OSRM y VROOM.
  static Future<Map<String, dynamic>?> servicesStatus() async {
    try {
      final response = await http
          .get(
              Uri.parse(
                  '${ApiConfig.baseUrl}${ApiConfig.servicesStatusEndpoint}'),
              headers: _defaultHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Envía lista de direcciones al endpoint /api/optimize.
  /// [addresses] - Lista de direcciones a optimizar.
  /// [clientNames] - Lista de nombres de cliente (opcional, mismo orden).
  /// [startAddress] - Dirección de inicio (opcional, usa la del backend si null).
  /// [numVehicles] - Número de vehículos/rutas (1 o 2).
  /// [coords] - Coordenadas pre-resueltas [[lat, lon], ...] (opcional).
  ///            Si se proporcionan, el backend omite la geocodificación.
  ///
  /// Retorna un [OptimizeResponse] si numVehicles==1,
  /// o un [MultiRouteResponse] si numVehicles==2.
  static Future<dynamic> optimize({
    required List<String> addresses,
    List<String>? clientNames,
    String? startAddress,
    int numVehicles = 1,
    List<List<double>?>? coords,
    List<int>? packageCounts,
    List<List<String>>? allClientNames,
  }) async {
    final body = <String, dynamic>{
      'addresses': addresses,
      'num_vehicles': numVehicles,
    };
    if (clientNames != null && clientNames.isNotEmpty) {
      body['client_names'] = clientNames;
    }
    if (startAddress != null && startAddress.isNotEmpty) {
      body['start_address'] = startAddress;
    }
    if (coords != null && coords.isNotEmpty) {
      body['coords'] = coords;
    }
    if (packageCounts != null && packageCounts.isNotEmpty) {
      body['package_counts'] = packageCounts;
    }
    if (allClientNames != null && allClientNames.isNotEmpty) {
      body['all_client_names'] = allClientNames;
    }

    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.optimizeEndpoint}'),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Si la respuesta tiene "routes", es multi-ruta
      if (json.containsKey('routes')) {
        return MultiRouteResponse.fromJson(json);
      }
      return OptimizeResponse.fromJson(json);
    } else {
      // Extraer mensaje de error del backend
      String errorMsg = 'Error del servidor (${response.statusCode})';
      try {
        final errJson = jsonDecode(response.body);
        errorMsg = errJson['detail'] ?? errJson['error'] ?? errorMsg;
      } catch (_) {}
      throw ApiException(errorMsg, response.statusCode);
    }
  }

  /// Envía un archivo CSV al endpoint /api/optimize/csv.
  /// [csvBytes] - Bytes del archivo CSV.
  /// [fileName] - Nombre del archivo.
  static Future<OptimizeResponse> optimizeCsv({
    required List<int> csvBytes,
    required String fileName,
  }) async {
    final uri =
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.optimizeCsvEndpoint}');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_defaultHeaders)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        csvBytes,
        filename: fileName,
      ));

    final streamedResponse = await request.send().timeout(ApiConfig.timeout);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return OptimizeResponse.fromJson(json);
    } else {
      String errorMsg = 'Error del servidor (${response.statusCode})';
      try {
        final errJson = jsonDecode(response.body);
        errorMsg = errJson['detail'] ?? errJson['error'] ?? errorMsg;
      } catch (_) {}
      throw ApiException(errorMsg, response.statusCode);
    }
  }

  /// Solicita a OSRM (vía backend) la geometría del tramo entre dos puntos.
  /// Retorna el GeoJSON geometry o null si falla.
  static Future<Map<String, dynamic>?> getRouteSegment({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/route-segment'
        '?origin_lat=$originLat&origin_lon=$originLon'
        '&dest_lat=$destLat&dest_lon=$destLon',
      );
      final response = await http
          .get(uri, headers: _defaultHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['geometry'] != null) {
          return json['geometry'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  Validación
  // ═══════════════════════════════════════════

  /// Valida todas las direcciones en un solo paso (agrupa + geocodifica).
  static Future<ValidationResponse> validationStart({
    required List<String> addresses,
    List<String>? clientNames,
  }) async {
    final body = <String, dynamic>{
      'addresses': addresses,
    };
    if (clientNames != null && clientNames.isNotEmpty) {
      body['client_names'] = clientNames;
    }

    final response = await http
        .post(
          Uri.parse(
              '${ApiConfig.baseUrl}${ApiConfig.validationStartEndpoint}'),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ValidationResponse.fromJson(json);
    } else {
      String errorMsg = 'Error del servidor (${response.statusCode})';
      try {
        final errJson = jsonDecode(response.body);
        errorMsg = errJson['detail'] ?? errJson['error'] ?? errorMsg;
      } catch (_) {}
      throw ApiException(errorMsg, response.statusCode);
    }
  }
}

/// Excepción personalizada para errores de la API.
class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
