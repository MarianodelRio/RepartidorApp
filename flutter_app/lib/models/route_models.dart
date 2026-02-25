/// Modelos de datos que reflejan los contratos del backend FastAPI.
library;

// ═══════════════════════════════════════════
//  Paquete individual (cliente + nota)
// ═══════════════════════════════════════════

/// Un paquete individual dentro de una parada: cliente + nota de entrega.
class Package {
  final String clientName;
  final String nota;

  const Package({this.clientName = '', this.nota = ''});

  factory Package.fromJson(Map<String, dynamic> json) => Package(
        clientName: (json['client_name'] as String?) ?? '',
        nota: (json['nota'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'client_name': clientName,
        'nota': nota,
      };

  Map<String, dynamic> toMap() => {
        'client_name': clientName,
        'nota': nota,
      };

  factory Package.fromMap(Map<dynamic, dynamic> map) => Package(
        clientName: (map['client_name'] as String?) ?? '',
        nota: (map['nota'] as String?) ?? '',
      );
}

// ═══════════════════════════════════════════
//  Parada en la ruta optimizada
// ═══════════════════════════════════════════
class StopInfo {
  final int order;
  final String address;
  final String label;
  final String clientName;
  final List<String> clientNames;
  final List<Package> packages;
  final String type; // 'origin' | 'stop'
  final double? lat; // null si geocodificación fallida
  final double? lon; // null si geocodificación fallida
  final double distanceMeters;
  final bool geocodeFailed;
  final int packageCount;

  const StopInfo({
    required this.order,
    required this.address,
    required this.label,
    this.clientName = '',
    this.clientNames = const [],
    this.packages = const [],
    required this.type,
    this.lat,
    this.lon,
    required this.distanceMeters,
    this.geocodeFailed = false,
    this.packageCount = 1,
  });

  bool get isOrigin => type == 'origin';

  /// ¿Hay más de un paquete en esta parada?
  bool get hasMultiplePackages => packageCount > 1;

  /// Identidad principal de la parada: la dirección (puede tener múltiples clientes).
  String get displayName => address;

  factory StopInfo.fromJson(Map<String, dynamic> json) {
    return StopInfo(
      order: json['order'] as int,
      address: json['address'] as String,
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
      geocodeFailed: (json['geocode_failed'] as bool?) ?? false,
      packageCount: (json['package_count'] as int?) ?? 1,
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
  final Map<String, dynamic> geometry; // GeoJSON

  const OptimizeResponse({
    required this.success,
    required this.summary,
    required this.stops,
    required this.geometry,
  });

  factory OptimizeResponse.fromJson(Map<String, dynamic> json) {
    return OptimizeResponse(
      success: json['success'] as bool,
      summary:
          RouteSummary.fromJson(json['summary'] as Map<String, dynamic>),
      stops: (json['stops'] as List)
          .map((e) => StopInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      geometry: json['geometry'] as Map<String, dynamic>,
    );
  }
}
