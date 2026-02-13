import 'package:hive_flutter/hive_flutter.dart';

import '../models/delivery_state.dart';
import '../models/route_models.dart';

/// Servicio de persistencia local usando Hive.
///
/// Guarda la sesión de reparto activa para poder reanudarla
/// si la app se cierra o el móvil se reinicia.
class PersistenceService {
  static const _boxName = 'delivery_session';
  static const _sessionKey = 'active_session';

  static bool _initialized = false;

  /// Inicializa Hive. Llamar una vez en main().
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _initialized = true;
  }

  /// Guarda o actualiza la sesión de reparto activa.
  static Future<void> saveSession(DeliverySession session) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_sessionKey, session.toMap());
  }

  /// Carga la sesión de reparto activa, si existe.
  static Future<DeliverySession?> loadSession() async {
    final box = await Hive.openBox(_boxName);
    final data = box.get(_sessionKey);
    if (data == null) return null;

    try {
      return DeliverySession.fromMap(data as Map<dynamic, dynamic>);
    } catch (_) {
      // Si hay datos corruptos, borrar
      await box.delete(_sessionKey);
      return null;
    }
  }

  /// ¿Hay una sesión activa guardada?
  static Future<bool> hasActiveSession() async {
    final box = await Hive.openBox(_boxName);
    return box.containsKey(_sessionKey);
  }

  /// Elimina la sesión activa (reparto completado o descartado).
  static Future<void> clearSession() async {
    final box = await Hive.openBox(_boxName);
    await box.delete(_sessionKey);
  }

  /// Actualiza el estado de una parada específica y persiste.
  static Future<void> updateStopStatus(
    DeliverySession session,
    int stopIndex,
    StopStatus status, {
    String? note,
  }) async {
    if (stopIndex < 0 || stopIndex >= session.stops.length) return;

    session.stops[stopIndex].status = status;
    session.stops[stopIndex].note = note;
    session.stops[stopIndex].completedAt = DateTime.now();

    // Avanzar al siguiente
    session.advanceToNext();

    // Persistir inmediatamente
    await saveSession(session);
  }

  /// Crea una nueva sesión a partir de un OptimizeResponse.
  static DeliverySession createSession(OptimizeResponse response) {
    final id =
        'session_${DateTime.now().millisecondsSinceEpoch}';

    final stops = response.stops.map((s) => DeliveryStop(
          order: s.order,
          address: s.address,
          label: s.label,
          clientName: s.clientName,
          clientNames: s.clientNames,
          type: s.type,
          lat: s.lat,
          lon: s.lon,
          distanceMeters: s.distanceMeters,
          geocodeFailed: s.geocodeFailed,
          packageCount: s.packageCount,
        )).toList();

    return DeliverySession(
      id: id,
      createdAt: DateTime.now(),
      stops: stops,
      geometry: response.geometry,
      totalStops: response.summary.totalStops,
      totalPackages: response.summary.totalPackages,
      totalDistanceDisplay: response.summary.totalDistanceDisplay,
      computingTimeMs: response.summary.computingTimeMs,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Persistencia de validación de direcciones
  // ═══════════════════════════════════════════════════════════

  static const _validationBoxName = 'validation_state';
  static const _validationKey = 'active_validation';

  /// Guarda el estado de validación (ediciones, resultados parciales).
  static Future<void> saveValidationState(Map<String, dynamic> state) async {
    final box = await Hive.openBox(_validationBoxName);
    await box.put(_validationKey, state);
  }

  /// Carga el estado de validación guardado.
  static Future<Map<String, dynamic>?> loadValidationState() async {
    final box = await Hive.openBox(_validationBoxName);
    final data = box.get(_validationKey);
    if (data == null) return null;
    try {
      return Map<String, dynamic>.from(data as Map);
    } catch (_) {
      await box.delete(_validationKey);
      return null;
    }
  }

  /// Elimina el estado de validación guardado.
  static Future<void> clearValidationState() async {
    final box = await Hive.openBox(_validationBoxName);
    await box.delete(_validationKey);
  }
}
