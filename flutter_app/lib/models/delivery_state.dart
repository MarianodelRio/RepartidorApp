/// Modelos para el estado de ejecución del reparto.
///
/// Diseñados para ser serializables a Hive (base de datos local).
library;

import 'route_models.dart';

// ═══════════════════════════════════════════
//  Estado de una parada
// ═══════════════════════════════════════════

/// Posibles estados de una parada durante el reparto.
enum StopStatus {
  pending,    // Aún no visitada
  delivered,  // Entregado correctamente
  absent,     // No estaba el destinatario
}

extension StopStatusLabel on StopStatus {
  String get label => switch (this) {
        StopStatus.pending => 'Pendiente',
        StopStatus.delivered => 'Entregado',
        StopStatus.absent => 'No estaba',
      };

  String get emoji => switch (this) {
        StopStatus.pending => '⏳',
        StopStatus.delivered => '✅',
        StopStatus.absent => '🚫',
      };
}

// ═══════════════════════════════════════════
//  Parada con estado de reparto
// ═══════════════════════════════════════════

/// Representa una parada con su estado de ejecución.
class DeliveryStop {
  final int order;
  final String address;
  final String alias;
  final String label;
  final String clientName;
  final List<String> clientNames;
  final List<Package> packages;
  final String type;
  final double? lat;
  final double? lon;
  final double distanceMeters;
  final int packageCount;

  StopStatus status;
  String? note;
  DateTime? completedAt;

  DeliveryStop({
    required this.order,
    required this.address,
    this.alias = '',
    required this.label,
    this.clientName = '',
    this.clientNames = const [],
    this.packages = const [],
    required this.type,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    this.packageCount = 1,
    this.status = StopStatus.pending,
    this.note,
    this.completedAt,
  });

  bool get isOrigin => type == 'origin';
  bool get isCompleted => status != StopStatus.pending;
  bool get isPending => status == StopStatus.pending;

  /// ¿Hay más de un paquete en esta parada?
  bool get hasMultiplePackages => packageCount > 1;

  /// Identidad principal de la parada: la dirección (puede tener múltiples clientes).
  String get displayName => address;

  /// Convierte a Map para almacenamiento en Hive.
  Map<String, dynamic> toMap() => {
        'order': order,
        'address': address,
        'alias': alias,
        'label': label,
        'clientName': clientName,
        'clientNames': clientNames,
        'packages': packages.map((p) => p.toMap()).toList(),
        'type': type,
        'lat': lat,
        'lon': lon,
        'distanceMeters': distanceMeters,
        'packageCount': packageCount,
        'status': status.index,
        'note': note,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory DeliveryStop.fromMap(Map<dynamic, dynamic> map) {
    return DeliveryStop(
      order: map['order'] as int,
      address: map['address'] as String,
      alias: (map['alias'] as String?) ?? '',
      label: map['label'] as String,
      clientName: (map['clientName'] as String?) ?? '',
      clientNames: (map['clientNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      packages: (map['packages'] as List<dynamic>?)
              ?.map((e) => Package.fromMap(e as Map<dynamic, dynamic>))
              .toList() ??
          const [],
      type: map['type'] as String,
      lat: map['lat'] != null ? (map['lat'] as num).toDouble() : null,
      lon: map['lon'] != null ? (map['lon'] as num).toDouble() : null,
      distanceMeters: (map['distanceMeters'] as num).toDouble(),
      packageCount: (map['packageCount'] as int?) ?? 1,
      status: StopStatus.values[map['status'] as int],
      note: map['note'] as String?,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
    );
  }
}

// ═══════════════════════════════════════════
//  Sesión de reparto completa
// ═══════════════════════════════════════════

/// Sesión de reparto: contiene toda la información necesaria para
/// reanudar un reparto si la app se cierra.
class DeliverySession {
  final String id;
  final DateTime createdAt;
  final List<DeliveryStop> stops;
  final Map<String, dynamic> geometry;
  final int totalStops;
  final int totalPackages;
  final String totalDistanceDisplay;
  final double computingTimeMs;
  int currentStopIndex;

  DeliverySession({
    required this.id,
    required this.createdAt,
    required this.stops,
    required this.geometry,
    required this.totalStops,
    this.totalPackages = 0,
    required this.totalDistanceDisplay,
    required this.computingTimeMs,
    this.currentStopIndex = 1, // Empieza en 1 (el 0 es el origen)
  });

  /// Parada actual (siguiente a entregar).
  DeliveryStop? get currentStop {
    if (currentStopIndex >= stops.length) return null;
    return stops[currentStopIndex];
  }

  /// Número de paradas pendientes (sin contar origen).
  int get pendingCount =>
      stops.where((s) => !s.isOrigin && s.isPending).length;

  /// Número de paradas completadas.
  int get completedCount =>
      stops.where((s) => !s.isOrigin && s.isCompleted).length;

  /// Número de entregas exitosas.
  int get deliveredCount =>
      stops.where((s) => s.status == StopStatus.delivered).length;

  /// Número de ausentes.
  int get absentCount =>
      stops.where((s) => s.status == StopStatus.absent).length;

  /// ¿Se ha completado todo el reparto?
  bool get isFinished => pendingCount == 0;

  /// Progreso de 0.0 a 1.0.
  double get progress {
    final total = stops.where((s) => !s.isOrigin).length;
    if (total == 0) return 1.0;
    return completedCount / total;
  }

  /// Avanza a la siguiente parada pendiente.
  void advanceToNext() {
    for (int i = currentStopIndex + 1; i < stops.length; i++) {
      if (stops[i].isPending) {
        currentStopIndex = i;
        return;
      }
    }
    // Si no hay más pendientes, ya terminó
    currentStopIndex = stops.length;
  }

  /// Serializa a Map para Hive.
  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'stops': stops.map((s) => s.toMap()).toList(),
        'geometry': geometry,
        'totalStops': totalStops,
        'totalPackages': totalPackages,
        'totalDistanceDisplay': totalDistanceDisplay,
        'computingTimeMs': computingTimeMs,
        'currentStopIndex': currentStopIndex,
      };

  factory DeliverySession.fromMap(Map<dynamic, dynamic> map) {
    return DeliverySession(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      stops: (map['stops'] as List)
          .map((s) => DeliveryStop.fromMap(s as Map<dynamic, dynamic>))
          .toList(),
      geometry: Map<String, dynamic>.from(map['geometry'] as Map),
      totalStops: map['totalStops'] as int,
      totalPackages: (map['totalPackages'] as int?) ?? 0,
      totalDistanceDisplay: map['totalDistanceDisplay'] as String,
      computingTimeMs: (map['computingTimeMs'] as num).toDouble(),
      currentStopIndex: map['currentStopIndex'] as int,
    );
  }
}
