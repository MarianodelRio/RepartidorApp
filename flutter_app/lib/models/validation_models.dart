// Modelos de datos para validación.
//
// Reflejan el contrato de POST /api/validation/start.

import 'route_models.dart';

/// Niveles de confianza de geocodificación.
enum GeoConfidence {
  exactAddress, // EXACT_ADDRESS — portal exacto (Google ROOFTOP)
  good,         // GOOD — buena estimación (Google RANGE_INTERPOLATED)
  exactPlace,   // EXACT_PLACE — lugar/negocio encontrado por Places
  override,     // OVERRIDE — pin manual del usuario
  failed,       // FAILED — no geocodificado

  ;

  static GeoConfidence fromString(String s) {
    switch (s) {
      case 'EXACT_ADDRESS':
        return GeoConfidence.exactAddress;
      case 'GOOD':
        return GeoConfidence.good;
      case 'EXACT_PLACE':
        return GeoConfidence.exactPlace;
      case 'OVERRIDE':
        return GeoConfidence.override;
      default:
        return GeoConfidence.failed;
    }
  }

  /// True si la confianza es suficiente para mostrar en verde (no requiere revisión).
  bool get isAccepted =>
      this == exactAddress || this == good || this == exactPlace || this == override;
}

/// Parada geocodificada correctamente.
class GeocodedStop {
  final String address;
  final String alias;
  final String clientName;
  final List<String> allClientNames;
  final List<Package> packages;
  final int packageCount;
  final double lat;
  final double lon;
  final GeoConfidence confidence;

  const GeocodedStop({
    required this.address,
    this.alias = '',
    required this.clientName,
    required this.allClientNames,
    this.packages = const [],
    required this.packageCount,
    required this.lat,
    required this.lon,
    this.confidence = GeoConfidence.good,
  });

  factory GeocodedStop.fromJson(Map<String, dynamic> json) {
    return GeocodedStop(
      address: json['address'] as String,
      alias: (json['alias'] as String?) ?? '',
      clientName: (json['client_name'] as String?) ?? '',
      allClientNames: (json['all_client_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      packages: (json['packages'] as List<dynamic>?)
              ?.map((e) => Package.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      packageCount: (json['package_count'] as int?) ?? 1,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      confidence: GeoConfidence.fromString(
          (json['confidence'] as String?) ?? 'EXACT_ADDRESS'),
    );
  }

  /// Crea una copia con los campos modificados.
  GeocodedStop copyWith({
    GeoConfidence? confidence,
    double? lat,
    double? lon,
  }) {
    return GeocodedStop(
      address: address,
      alias: alias,
      clientName: clientName,
      allClientNames: allClientNames,
      packages: packages,
      packageCount: packageCount,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// Parada que no pudo geocodificarse.
class FailedStop {
  final String address;
  final String alias;
  final List<String> clientNames;
  final List<Package> packages;
  final int packageCount;

  const FailedStop({
    required this.address,
    this.alias = '',
    required this.clientNames,
    this.packages = const [],
    required this.packageCount,
  });

  factory FailedStop.fromJson(Map<String, dynamic> json) {
    return FailedStop(
      address: json['address'] as String,
      alias: (json['alias'] as String?) ?? '',
      clientNames: (json['client_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      packages: (json['packages'] as List<dynamic>?)
              ?.map((e) => Package.fromJson(e as Map<String, dynamic>))
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
