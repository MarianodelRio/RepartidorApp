// Modelos de datos para geocodificación por parada.
//
// Reflejan el contrato del endpoint POST /api/streets/geocode_stops.

/// Input de una parada para geocode_stops.
class StopInputModel {
  final int index;
  final String streetKey;
  final String houseNumber;
  final String streetDisplay;
  final String city;
  final String postcode;
  final String originalAddress;

  const StopInputModel({
    required this.index,
    required this.streetKey,
    this.houseNumber = '',
    this.streetDisplay = '',
    this.city = 'posadas',
    this.postcode = '14730',
    this.originalAddress = '',
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'street_key': streetKey,
        'house_number': houseNumber,
        'street_display': streetDisplay,
        'city': city,
        'postcode': postcode,
        'original_address': originalAddress,
      };
}

/// Coordenadas de una calle resuelta (input para geocode_stops).
class ResolvedStreetInput {
  final String streetKey;
  final double lat;
  final double lon;
  final String canonicalName;

  const ResolvedStreetInput({
    required this.streetKey,
    required this.lat,
    required this.lon,
    this.canonicalName = '',
  });

  Map<String, dynamic> toJson() => {
        'street_key': streetKey,
        'lat': lat,
        'lon': lon,
        'canonical_name': canonicalName,
      };
}

/// Resultado de geocodificación + OSRM snap de una parada.
class StopGeoResult {
  final int index;
  final String streetKey;
  final String originalAddress;
  final double geocodedLat;
  final double geocodedLon;
  final String geocodeSource; // "house_number" | "street_center" | "fallback_center"
  final double snappedLat;
  final double snappedLon;
  final double snapDistanceM;
  final bool snapped;
  final List<String> warnings;

  const StopGeoResult({
    required this.index,
    required this.streetKey,
    required this.originalAddress,
    required this.geocodedLat,
    required this.geocodedLon,
    required this.geocodeSource,
    required this.snappedLat,
    required this.snappedLon,
    required this.snapDistanceM,
    required this.snapped,
    required this.warnings,
  });

  bool get hasWarnings => warnings.isNotEmpty;
  double get finalLat => snappedLat;
  double get finalLon => snappedLon;

  factory StopGeoResult.fromJson(Map<String, dynamic> json) {
    return StopGeoResult(
      index: json['index'] as int,
      streetKey: json['street_key'] as String,
      originalAddress: (json['original_address'] as String?) ?? '',
      geocodedLat: (json['geocoded_lat'] as num).toDouble(),
      geocodedLon: (json['geocoded_lon'] as num).toDouble(),
      geocodeSource: (json['geocode_source'] as String?) ?? '',
      snappedLat: (json['snapped_lat'] as num).toDouble(),
      snappedLon: (json['snapped_lon'] as num).toDouble(),
      snapDistanceM: (json['snap_distance_m'] as num?)?.toDouble() ?? 0.0,
      snapped: (json['snapped'] as bool?) ?? false,
      warnings: (json['warnings'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

/// Respuesta del endpoint geocode_stops.
class GeocodeStopsResponse {
  final bool success;
  final int total;
  final int geocodedByNumber;
  final int geocodedByCenter;
  final int snappedCount;
  final int warningsCount;
  final List<StopGeoResult> results;
  final double elapsedMs;

  const GeocodeStopsResponse({
    required this.success,
    required this.total,
    required this.geocodedByNumber,
    required this.geocodedByCenter,
    required this.snappedCount,
    required this.warningsCount,
    required this.results,
    this.elapsedMs = 0,
  });

  factory GeocodeStopsResponse.fromJson(Map<String, dynamic> json) {
    return GeocodeStopsResponse(
      success: json['success'] as bool,
      total: json['total'] as int,
      geocodedByNumber: json['geocoded_by_number'] as int,
      geocodedByCenter: json['geocoded_by_center'] as int,
      snappedCount: json['snapped_count'] as int,
      warningsCount: json['warnings_count'] as int,
      results: (json['results'] as List)
          .map((e) => StopGeoResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      elapsedMs: (json['elapsed_ms'] as num?)?.toDouble() ?? 0,
    );
  }
}
