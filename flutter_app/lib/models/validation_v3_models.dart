// Modelos de datos para validación.
//
// Reflejan el contrato de POST /api/validation/start.

/// Parada geocodificada correctamente.
class GeocodedStop {
  final String address;
  final String clientName;
  final List<String> allClientNames;
  final int packageCount;
  final double lat;
  final double lon;

  const GeocodedStop({
    required this.address,
    required this.clientName,
    required this.allClientNames,
    required this.packageCount,
    required this.lat,
    required this.lon,
  });

  factory GeocodedStop.fromJson(Map<String, dynamic> json) {
    return GeocodedStop(
      address: json['address'] as String,
      clientName: (json['client_name'] as String?) ?? '',
      allClientNames: (json['all_client_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      packageCount: (json['package_count'] as int?) ?? 1,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}

/// Parada que no pudo geocodificarse.
class FailedStop {
  final String address;
  final List<String> clientNames;
  final int packageCount;

  const FailedStop({
    required this.address,
    required this.clientNames,
    required this.packageCount,
  });

  factory FailedStop.fromJson(Map<String, dynamic> json) {
    return FailedStop(
      address: json['address'] as String,
      clientNames: (json['client_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      packageCount: (json['package_count'] as int?) ?? 1,
    );
  }
}

/// Resultado completo de /api/validation/start.
class ValidationResult {
  final List<GeocodedStop> geocoded;
  final List<FailedStop> failed;
  final int totalPackages;
  final int uniqueAddresses;

  const ValidationResult({
    required this.geocoded,
    required this.failed,
    required this.totalPackages,
    required this.uniqueAddresses,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) {
    return ValidationResult(
      geocoded: (json['geocoded'] as List<dynamic>)
          .map((e) => GeocodedStop.fromJson(e as Map<String, dynamic>))
          .toList(),
      failed: (json['failed'] as List<dynamic>)
          .map((e) => FailedStop.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalPackages: (json['total_packages'] as int?) ?? 0,
      uniqueAddresses: (json['unique_addresses'] as int?) ?? 0,
    );
  }
}
