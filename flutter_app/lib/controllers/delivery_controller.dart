import 'package:flutter/foundation.dart';

import '../models/delivery_state.dart';
import '../services/api_service.dart';
import '../services/persistence_service.dart';

/// Controlador de estado para la pantalla de reparto.
///
/// Gestiona tres grupos de estado independientes de la UI:
///   1. Sesión activa (stops, índice actual, progreso)
///   2. Geometría del segmento GPS → siguiente parada
///   3. Mutaciones: marcar parada, reordenar paradas, re-pin manual
///
/// La pantalla observa este controller vía [ListenableBuilder].
/// No contiene [BuildContext], diálogos, ni navegación.
class DeliveryController extends ChangeNotifier {
  bool _disposed = false;

  // ── 1. Sesión ──────────────────────────────────────────────────────

  final DeliverySession _session;

  DeliverySession get session => _session;

  DeliveryController(this._session);

  // ── 2. Segmento de ruta ────────────────────────────────────────────

  Map<String, dynamic>? _segmentGeometry;

  Map<String, dynamic>? get segmentGeometry => _segmentGeometry;

  /// Solicita al backend el camino OSRM desde la parada anterior
  /// hasta la siguiente parada pendiente.
  /// Puede llamarse sin await (fire-and-forget): tiene el guard [_disposed].
  Future<void> fetchSegment() async {
    final currentStop = _session.currentStop;
    if (currentStop == null ||
        currentStop.lat == null ||
        currentStop.lon == null) {
      _segmentGeometry = null;
      _notify();
      return;
    }

    final destLat = currentStop.lat!;
    final destLon = currentStop.lon!;

    final prevIdx = _session.currentStopIndex - 1;
    final prevStop = (prevIdx >= 0 && prevIdx < _session.stops.length)
        ? _session.stops[prevIdx]
        : null;

    double? originLat;
    double? originLon;
    if (prevStop != null &&
        prevStop.lat != null &&
        prevStop.lon != null) {
      originLat = prevStop.lat!;
      originLon = prevStop.lon!;
    } else if (_session.stops.isNotEmpty &&
        _session.stops[0].lat != null &&
        _session.stops[0].lon != null) {
      originLat = _session.stops[0].lat!;
      originLon = _session.stops[0].lon!;
    } else {
      return;
    }

    final geo = await ApiService.getRouteSegment(
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
    );

    if (_disposed) return;
    _segmentGeometry = geo;
    _notify();
  }

  // ── 3. Mutaciones de parada ────────────────────────────────────────

  /// Marca la parada actual con [status] y avanza al siguiente pendiente.
  /// Limpia el segmento viejo e inicia la carga del nuevo de forma
  /// asíncrona (fire-and-forget). Si el reparto termina, limpia el segmento.
  Future<void> markCurrentStop(StopStatus status, {String? note}) async {
    final stopIndex = _session.currentStopIndex;
    if (stopIndex >= _session.stops.length) return;

    await PersistenceService.updateStopStatus(
      _session,
      stopIndex,
      status,
      note: note,
    );

    if (_disposed) return;
    _segmentGeometry = null;
    _notify();

    if (!_session.isFinished) {
      fetchSegment(); // fire-and-forget: actualiza segmentGeometry de forma async
    }
  }

  /// Marca cualquier parada por índice (no solo la actual).
  ///
  /// Si el índice coincide con [currentStopIndex], delega en [markCurrentStop]
  /// para que avance el puntero y recargue el segmento GPS.
  Future<void> markStopByIndex(
    int sessionIndex,
    StopStatus status, {
    String? note,
  }) async {
    if (sessionIndex >= _session.stops.length) return;

    if (sessionIndex == _session.currentStopIndex) {
      await markCurrentStop(status, note: note);
      return;
    }

    await PersistenceService.updateStopStatus(
      _session,
      sessionIndex,
      status,
      note: note,
    );

    if (_disposed) return;
    if (_session.isFinished) {
      _segmentGeometry = null;
    }
    _notify();
  }

  /// Aplica el nuevo orden de paradas pendientes.
  ///
  /// [reorderedPending] contiene las paradas no entregadas en el nuevo orden.
  /// Reconstruye la lista de stops y reposiciona [currentStopIndex].
  Future<void> applyReorder(List<DeliveryStop> reorderedPending) async {
    final origin = _session.stops.where((s) => s.isOrigin).toList();
    final delivered = _session.stops
        .where((s) => !s.isOrigin && s.status == StopStatus.delivered)
        .toList();

    final newStops = [...origin, ...delivered, ...reorderedPending];

    _session.stops
      ..clear()
      ..addAll(newStops);

    // Apuntar al primer pendiente reintentable (ausente o pendiente)
    for (int i = 0; i < _session.stops.length; i++) {
      final s = _session.stops[i];
      if (!s.isOrigin && s.status != StopStatus.delivered) {
        _session.currentStopIndex = i;
        break;
      }
    }

    await PersistenceService.saveSession(_session);
    if (_disposed) return;

    _segmentGeometry = null;
    _notify();

    if (_session.currentStop != null) {
      fetchSegment(); // fire-and-forget
    }
  }

  /// Aplica un re-pin manual a una parada de la sesión activa.
  /// Notifica al backend y recarga el segmento si es la parada actual.
  Future<void> applyRepin(
    int sessionIndex,
    double lat,
    double lon,
  ) async {
    if (sessionIndex >= _session.stops.length) return;

    final stop = _session.stops[sessionIndex];

    ApiService.postOverride(address: stop.address, lat: lat, lon: lon);

    _session.stops[sessionIndex] = DeliveryStop(
      order: stop.order,
      address: stop.address,
      alias: stop.alias,
      label: stop.label,
      clientName: stop.clientName,
      clientNames: stop.clientNames,
      packages: stop.packages,
      type: stop.type,
      lat: lat,
      lon: lon,
      distanceMeters: stop.distanceMeters,
      packageCount: stop.packageCount,
      status: stop.status,
      note: stop.note,
      completedAt: stop.completedAt,
    );

    await PersistenceService.saveSession(_session);
    if (_disposed) return;

    if (sessionIndex == _session.currentStopIndex) {
      _segmentGeometry = null;
      _notify();
      fetchSegment(); // fire-and-forget
    } else {
      _notify();
    }
  }

  /// Guarda la sesión en Hive.
  /// Usado por el observer de ciclo de vida y el diálogo de salida.
  Future<void> save() async {
    await PersistenceService.saveSession(_session);
  }

  /// Elimina la sesión activa de Hive.
  /// Llamar al finalizar el reparto antes de navegar fuera.
  Future<void> clearSession() async {
    await PersistenceService.clearSession();
  }

  // ─────────────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
