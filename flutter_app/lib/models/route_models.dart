/// Modelos de datos que reflejan los contratos del backend FastAPI.
///
/// Cambios v2.1:
///   - StopInfo: añadido `clientName`, eliminados `etaSeconds` y `etaDisplay`.
///   - RouteSummary: eliminados `totalDurationS` y `totalDurationDisplay`.
///   - RouteStep: eliminado `durationS`.
///   - La identidad de cada parada se basa en `clientName` si existe.
library;

// ═══════════════════════════════════════════
//  Coordenada
// ═══════════════════════════════════════════
class Coordinate {
  final double lat;
  final double lon;

  const Coordinate({required this.lat, required this.lon});

  factory Coordinate.fromJson(Map<String, dynamic> json) {
    return Coordinate(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
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
  final String type; // 'origin' | 'stop'
  final double lat;
  final double lon;
  final double distanceMeters;
  final bool geocodeFailed;
  final int packageCount;

  const StopInfo({
    required this.order,
    required this.address,
    required this.label,
    this.clientName = '',
    this.clientNames = const [],
    required this.type,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    this.geocodeFailed = false,
    this.packageCount = 1,
  });

  bool get isOrigin => type == 'origin';

  /// ¿Hay más de un paquete en esta parada?
  bool get hasMultiplePackages => packageCount > 1;

  /// Identidad principal: nombre del cliente si existe, sino la dirección.
  String get displayName => clientName.isNotEmpty ? clientName : address;

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
      type: json['type'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
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
//  Instrucción de navegación
// ═══════════════════════════════════════════
class RouteStep {
  final String text;
  final double distanceM;
  final Coordinate? location;

  const RouteStep({
    required this.text,
    required this.distanceM,
    this.location,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    return RouteStep(
      text: json['text'] as String,
      distanceM: (json['distance_m'] as num).toDouble(),
      location: json['location'] != null
          ? Coordinate.fromJson(json['location'] as Map<String, dynamic>)
          : null,
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
  final List<RouteStep> steps;
  final int routeIndex;
  final int totalRoutes;

  const OptimizeResponse({
    required this.success,
    required this.summary,
    required this.stops,
    required this.geometry,
    required this.steps,
    this.routeIndex = 0,
    this.totalRoutes = 1,
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
      steps: (json['steps'] as List)
          .map((e) => RouteStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      routeIndex: (json['route_index'] as int?) ?? 0,
      totalRoutes: (json['total_routes'] as int?) ?? 1,
    );
  }
}

// ═══════════════════════════════════════════
//  Respuesta multi-ruta (2 vehículos)
// ═══════════════════════════════════════════
class MultiRouteResponse {
  final bool success;
  final List<OptimizeResponse> routes;
  final int totalRoutes;

  const MultiRouteResponse({
    required this.success,
    required this.routes,
    required this.totalRoutes,
  });

  factory MultiRouteResponse.fromJson(Map<String, dynamic> json) {
    return MultiRouteResponse(
      success: json['success'] as bool,
      routes: (json['routes'] as List)
          .map((e) => OptimizeResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalRoutes: json['total_routes'] as int,
    );
  }
}
