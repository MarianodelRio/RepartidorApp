import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/models/delivery_state.dart';
import 'package:repartir_app/models/route_models.dart';

// ── Helpers ────────────────────────────────────────────────────────

DeliveryStop _makeStop({
  int order = 1,
  String type = 'stop',
  StopStatus status = StopStatus.pending,
  int packageCount = 1,
}) =>
    DeliveryStop(
      order: order,
      address: 'Calle Test $order',
      label: '📍 Stop $order',
      type: type,
      lat: 37.80,
      lon: -5.10,
      distanceMeters: 100.0,
      packageCount: packageCount,
      status: status,
    );

DeliveryStop _makeOrigin() => _makeStop(order: 0, type: 'origin');

DeliverySession _makeSession(List<DeliveryStop> stops) => DeliverySession(
      id: 'test-session-1',
      createdAt: DateTime(2026, 3, 1, 10, 0, 0),
      stops: stops,
      geometry: {'type': 'LineString', 'coordinates': []},
      totalStops: stops.where((s) => !s.isOrigin).length,
      totalPackages: stops.fold(0, (sum, s) => sum + s.packageCount),
      totalDistanceDisplay: '2.5 km',
      computingTimeMs: 7.0,
    );

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  StopStatus — extensiones label y emoji
  // ══════════════════════════════════════════════════════════════════

  group('StopStatus labels', () {
    test('pending tiene label "Pendiente"', () {
      expect(StopStatus.pending.label, 'Pendiente');
    });
    test('delivered tiene label "Entregado"', () {
      expect(StopStatus.delivered.label, 'Entregado');
    });
    test('absent tiene label "No estaba"', () {
      expect(StopStatus.absent.label, 'No estaba');
    });
  });

  group('StopStatus emojis', () {
    test('cada estado tiene un emoji distinto', () {
      final emojis = StopStatus.values.map((s) => s.emoji).toSet();
      expect(emojis.length, StopStatus.values.length);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  DeliveryStop — getters
  // ══════════════════════════════════════════════════════════════════

  group('DeliveryStop getters', () {
    test('isOrigin es true cuando type == "origin"', () {
      expect(_makeOrigin().isOrigin, isTrue);
    });

    test('isOrigin es false cuando type == "stop"', () {
      expect(_makeStop().isOrigin, isFalse);
    });

    test('isPending es true cuando status == pending', () {
      expect(_makeStop(status: StopStatus.pending).isPending, isTrue);
    });

    test('isPending es false cuando status != pending', () {
      expect(_makeStop(status: StopStatus.delivered).isPending, isFalse);
    });

    test('isCompleted es false cuando status == pending', () {
      expect(_makeStop(status: StopStatus.pending).isCompleted, isFalse);
    });

    test('isCompleted es true para delivered y absent', () {
      expect(_makeStop(status: StopStatus.delivered).isCompleted, isTrue);
      expect(_makeStop(status: StopStatus.absent).isCompleted, isTrue);
    });

    test('hasMultiplePackages es false con packageCount 1', () {
      expect(_makeStop(packageCount: 1).hasMultiplePackages, isFalse);
    });

    test('hasMultiplePackages es true con packageCount > 1', () {
      expect(_makeStop(packageCount: 3).hasMultiplePackages, isTrue);
    });

    test('displayName devuelve la dirección', () {
      final stop = _makeStop(order: 5);
      expect(stop.displayName, stop.address);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  DeliveryStop — serialización toMap / fromMap
  // ══════════════════════════════════════════════════════════════════

  group('DeliveryStop.toMap / fromMap', () {
    test('round-trip preserva todos los campos', () {
      final stop = DeliveryStop(
        order: 2,
        address: 'Calle Mayor 5',
        alias: 'Bar Central',
        label: '📍 Bar Central',
        clientName: 'Ana',
        clientNames: ['Ana', 'Luis'],
        packages: [
          Package(clientName: 'Ana', nota: 'bajo'),
          Package(clientName: 'Luis', nota: ''),
        ],
        type: 'stop',
        lat: 37.802,
        lon: -5.105,
        distanceMeters: 250.0,
        packageCount: 2,
        status: StopStatus.delivered,
        note: 'sin ascensor',
        completedAt: DateTime(2026, 3, 1, 11, 30, 0),
      );

      final restored = DeliveryStop.fromMap(stop.toMap());

      expect(restored.order, stop.order);
      expect(restored.address, stop.address);
      expect(restored.alias, stop.alias);
      expect(restored.clientName, stop.clientName);
      expect(restored.clientNames, stop.clientNames);
      expect(restored.packages.length, stop.packages.length);
      expect(restored.packages[0].clientName, 'Ana');
      expect(restored.type, stop.type);
      expect(restored.lat, stop.lat);
      expect(restored.lon, stop.lon);
      expect(restored.distanceMeters, stop.distanceMeters);
      expect(restored.packageCount, stop.packageCount);
      expect(restored.status, stop.status);
      expect(restored.note, stop.note);
      expect(restored.completedAt, stop.completedAt);
    });

    test('lat y lon null se preservan', () {
      final stop = DeliveryStop(
        order: 1,
        address: 'Calle X 1',
        label: '📍 Calle X 1',
        type: 'stop',
        lat: null,
        lon: null,
        distanceMeters: 0,
      );
      final restored = DeliveryStop.fromMap(stop.toMap());
      expect(restored.lat, isNull);
      expect(restored.lon, isNull);
    });

    test('completedAt null se preserva', () {
      final stop = _makeStop();
      final restored = DeliveryStop.fromMap(stop.toMap());
      expect(restored.completedAt, isNull);
    });

    test('note null se preserva', () {
      final stop = _makeStop();
      final restored = DeliveryStop.fromMap(stop.toMap());
      expect(restored.note, isNull);
    });

    test('todos los StopStatus se serializan correctamente', () {
      for (final status in StopStatus.values) {
        final stop = _makeStop(status: status);
        final restored = DeliveryStop.fromMap(stop.toMap());
        expect(restored.status, status);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  DeliverySession — contadores y getters
  // ══════════════════════════════════════════════════════════════════

  group('DeliverySession — contadores', () {
    test('pendingCount no cuenta el origen', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.pending),
        _makeStop(order: 2, status: StopStatus.pending),
      ]);
      expect(session.pendingCount, 2);
    });

    test('pendingCount es 0 cuando todas están completadas', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.absent),
      ]);
      expect(session.pendingCount, 0);
    });

    test('completedCount cuenta delivered y absent', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.absent),
        _makeStop(order: 3, status: StopStatus.pending),
      ]);
      expect(session.completedCount, 2);
    });

    test('deliveredCount solo cuenta delivered', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.delivered),
        _makeStop(order: 3, status: StopStatus.absent),
      ]);
      expect(session.deliveredCount, 2);
    });

    test('absentCount solo cuenta absent', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.absent),
        _makeStop(order: 2, status: StopStatus.delivered),
      ]);
      expect(session.absentCount, 1);
    });

  });

  group('DeliverySession — isFinished y progress', () {
    test('isFinished es false si hay paradas pendientes', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.pending),
      ]);
      expect(session.isFinished, isFalse);
    });

    test('isFinished es true cuando todas las paradas están completadas', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.absent),
      ]);
      expect(session.isFinished, isTrue);
    });

    test('progress es 0.0 cuando nada está completado', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1),
        _makeStop(order: 2),
      ]);
      expect(session.progress, 0.0);
    });

    test('progress es 1.0 cuando todo está completado', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.delivered),
      ]);
      expect(session.progress, 1.0);
    });

    test('progress es 0.5 cuando la mitad está completada', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.pending),
      ]);
      expect(session.progress, 0.5);
    });

    test('progress es 1.0 cuando no hay paradas (solo origen)', () {
      final session = _makeSession([_makeOrigin()]);
      expect(session.progress, 1.0);
    });
  });

  group('DeliverySession — currentStop y advanceToNext', () {
    test('currentStop devuelve la parada en currentStopIndex', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1),
        _makeStop(order: 2),
      ]);
      // currentStopIndex empieza en 1 (el origen es 0)
      expect(session.currentStop?.order, 1);
    });

    test('currentStop es null cuando se superan todas las paradas', () {
      final session = _makeSession([_makeOrigin()])
        ..currentStopIndex = 999;
      expect(session.currentStop, isNull);
    });

    test('advanceToNext salta a la siguiente parada pendiente', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered), // completada
        _makeStop(order: 2, status: StopStatus.pending),   // pendiente
        _makeStop(order: 3, status: StopStatus.pending),
      ])..currentStopIndex = 1;

      session.advanceToNext();
      expect(session.currentStopIndex, 2);
    });

    test('advanceToNext pone currentStopIndex a stops.length si no hay más pendientes', () {
      final stops = [
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.delivered),
      ];
      final session = _makeSession(stops)..currentStopIndex = 1;
      session.advanceToNext();
      expect(session.currentStopIndex, stops.length);
      expect(session.currentStop, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  DeliverySession — serialización toMap / fromMap
  // ══════════════════════════════════════════════════════════════════

  group('DeliverySession.toMap / fromMap', () {
    test('round-trip preserva todos los campos', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.pending),
      ])..currentStopIndex = 2;

      final restored = DeliverySession.fromMap(session.toMap());

      expect(restored.id, session.id);
      expect(restored.createdAt, session.createdAt);
      expect(restored.stops.length, session.stops.length);
      expect(restored.totalStops, session.totalStops);
      expect(restored.totalPackages, session.totalPackages);
      expect(restored.totalDistanceDisplay, session.totalDistanceDisplay);
      expect(restored.computingTimeMs, session.computingTimeMs);
      expect(restored.currentStopIndex, session.currentStopIndex);
    });

    test('el estado de cada parada se preserva en la sesión', () {
      final session = _makeSession([
        _makeOrigin(),
        _makeStop(order: 1, status: StopStatus.delivered),
        _makeStop(order: 2, status: StopStatus.absent),
      ]);

      final restored = DeliverySession.fromMap(session.toMap());
      expect(restored.stops[1].status, StopStatus.delivered);
      expect(restored.stops[2].status, StopStatus.absent);
    });
  });
}
