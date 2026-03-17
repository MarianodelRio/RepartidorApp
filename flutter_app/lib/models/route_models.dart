/// Modelos de datos que reflejan los contratos del backend FastAPI.
library;

// ═══════════════════════════════════════════
//  Paquete individual (cliente + nota)
// ═══════════════════════════════════════════

/// Un paquete individual dentro de una parada: cliente + nota + agencia + tipo.
class Package {
  final String clientName;
  final String nota;
  final String agencia; // empresa de reparto (MRW, SEUR, etc.) — solo informativo
  final String tipo;    // 'Express' o 'Normal'

  const Package({
    this.clientName = '',
    this.nota = '',
    this.agencia = '',
    this.tipo = 'Normal',
  });

  factory Package.fromJson(Map<String, dynamic> json) => Package(
        clientName: (json['client_name'] as String?) ?? '',
        nota: (json['nota'] as String?) ?? '',
        agencia: (json['agencia'] as String?) ?? '',
        tipo: (json['tipo'] as String?) ?? 'Normal',
      );

  Map<String, dynamic> toJson() => {
        'client_name': clientName,
        'nota': nota,
        'agencia': agencia,
        'tipo': tipo,
      };

  Map<String, dynamic> toMap() => {
        'client_name': clientName,
        'nota': nota,
        'agencia': agencia,
        'tipo': tipo,
      };

  factory Package.fromMap(Map<dynamic, dynamic> map) => Package(
        clientName: (map['client_name'] as String?) ?? '',
        nota: (map['nota'] as String?) ?? '',
        agencia: (map['agencia'] as String?) ?? '',
        tipo: (map['tipo'] as String?) ?? 'Normal',
      );
}

// ═══════════════════════════════════════════
//  Parada en la ruta optimizada
// ═══════════════════════════════════════════
class StopInfo {
  final int order;
  final String address;
  final String alias;
  final String label;
  final String clientName;
  final List<String> clientNames;
  final List<Package> packages;
  final String type;  // 'origin' | 'stop'
  final double? lat;
  final double? lon;
  final double distanceMeters;
  final int packageCount;
  final String tipo;  // 'Express' o 'Normal'

  const StopInfo({
    required this.order,
    required this.address,
    this.alias = '',
    required this.label,
    this.clientName = '',
    this.clientNames = const [],
    this.packages = const [],
    required this.type,
    this.lat,
    this.lon,
    required this.distanceMeters,
    this.packageCount = 1,
    this.tipo = 'Normal',
  });

  bool get isOrigin => type == 'origin';
  bool get isExpress => tipo == 'Express';

  /// ¿Hay más de un paquete en esta parada?
  bool get hasMultiplePackages => packageCount > 1;

  /// Identidad principal de la parada: la dirección (puede tener múltiples clientes).
  String get displayName => address;

  factory StopInfo.fromJson(Map<String, dynamic> json) {
    return StopInfo(
      order: json['order'] as int,
      address: json['address'] as String,
      alias: (json['alias'] as String?) ?? '',
      label: json['label'] as String,
      clientName: (json['client_name'] as String?) ?? '',
      clientNames: (json['client_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      packages: (json['packages'] as List<dynamic>?)
              ?.map((e) => Package.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      type: json['type'] as String,
      lat: json['lat'] != null ? (json['lat'] as num).toDouble() : null,
      lon: json['lon'] != null ? (json['lon'] as num).toDouble() : null,
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      packageCount: (json['package_count'] as int?) ?? 1,
      tipo: (json['tipo'] as String?) ?? 'Normal',
    );
  }
}

// ═══════════════════════════════════════════
//  Resumen de la ruta
// ═══════════════════════════════════════════
class RouteSummary {
  final int totalStops;
  final int totalPackages;
  final double totalDistanceM;
  final String totalDistanceDisplay;
  final double computingTimeMs;

  const RouteSummary({
    required this.totalStops,
    this.totalPackages = 0,
    required this.totalDistanceM,
    required this.totalDistanceDisplay,
    required this.computingTimeMs,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    return RouteSummary(
      totalStops: json['total_stops'] as int,
      totalPackages: (json['total_packages'] as int?) ?? 0,
      totalDistanceM: (json['total_distance_m'] as num).toDouble(),
      totalDistanceDisplay: json['total_distance_display'] as String,
      computingTimeMs: (json['computing_time_ms'] as num).toDouble(),
    );
  }
}

// ═══════════════════════════════════════════
//  Respuesta completa de /optimize
// ═══════════════════════════════════════════
class OptimizeResponse {
  final bool success;
  final RouteSummary summary;
  final List<StopInfo> stops;

  const OptimizeResponse({
    required this.success,
    required this.summary,
    required this.stops,
  });

  factory OptimizeResponse.fromJson(Map<String, dynamic> json) {
    return OptimizeResponse(
      success: json['success'] as bool,
      summary:
          RouteSummary.fromJson(json['summary'] as Map<String, dynamic>),
      stops: (json['stops'] as List)
          .map((e) => StopInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
