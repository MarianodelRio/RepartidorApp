// Modelos de datos para validación.
//
// Reflejan el contrato de POST /api/validation/start.

/// Resultado de una dirección única (agrupada por duplicados).
class StopValidationResult {
  final int index;
  final String address;
  final String status; // "ok" | "problem"
  final double? lat;
  final double? lon;
  final int packageCount;
  final List<String> clientNames;
  final String reason;

  const StopValidationResult({
    required this.index,
    required this.address,
    required this.status,
    this.lat,
    this.lon,
    this.packageCount = 1,
    this.clientNames = const [],
    this.reason = '',
  });

  bool get isOk => status == 'ok';
  bool get isProblem => status == 'problem';

  factory StopValidationResult.fromJson(Map<String, dynamic> json) {
    return StopValidationResult(
      index: json['index'] as int,
      address: json['address'] as String,
      status: json['status'] as String,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      packageCount: (json['package_count'] as int?) ?? 1,
      clientNames: (json['client_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      reason: (json['reason'] as String?) ?? '',
    );
  }
}

/// Respuesta de /api/validation/start.
class ValidationResponse {
  final bool success;
  final int totalStops;
  final int uniqueAddresses;
  final int okCount;
  final int problemCount;
  final List<StopValidationResult> stops;
  final double elapsedMs;

  const ValidationResponse({
    required this.success,
    required this.totalStops,
    required this.uniqueAddresses,
    required this.okCount,
    required this.problemCount,
    required this.stops,
    this.elapsedMs = 0,
  });

  factory ValidationResponse.fromJson(Map<String, dynamic> json) {
    return ValidationResponse(
      success: json['success'] as bool,
      totalStops: json['total_stops'] as int,
      uniqueAddresses: json['unique_addresses'] as int,
      okCount: json['ok_count'] as int,
      problemCount: json['problem_count'] as int,
      stops: (json['stops'] as List<dynamic>)
          .map((e) => StopValidationResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      elapsedMs: (json['elapsed_ms'] as num?)?.toDouble() ?? 0,
    );
  }
}
