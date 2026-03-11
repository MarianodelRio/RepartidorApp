import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/models/route_models.dart';

// JSON de ejemplo que simula exactamente lo que devuelve el backend.
Map<String, dynamic> _stopInfoJson({
  String type = 'stop',
  double? lat = 37.8012,
  double? lon = -5.1050,
}) =>
    {
      'order': 1,
      'address': 'Calle Gaitán 24',
      'alias': 'Bar El Gato',
      'label': '📍 Juan García',
      'client_name': 'Juan García',
      'client_names': ['Juan García'],
      'packages': [
        {'client_name': 'Juan García', 'nota': ''},
      ],
      'type': type,
      'lat': lat,
      'lon': lon,
      'distance_meters': 350.0,
      'package_count': 1,
    };

Map<String, dynamic> _routeSummaryJson() => {
      'total_stops': 5,
      'total_packages': 7,
      'total_distance_m': 4200.0,
      'total_distance_display': '4.2 km',
      'computing_time_ms': 7.0,
    };

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  StopInfo.fromJson — contrato con el backend
  // ══════════════════════════════════════════════════════════════════

  group('StopInfo.fromJson', () {
    test('deserializa todos los campos', () {
      final stop = StopInfo.fromJson(_stopInfoJson());
      expect(stop.order, 1);
      expect(stop.address, 'Calle Gaitán 24');
      expect(stop.alias, 'Bar El Gato');
      expect(stop.label, '📍 Juan García');
      expect(stop.clientName, 'Juan García');
      expect(stop.clientNames, ['Juan García']);
      expect(stop.type, 'stop');
      expect(stop.lat, 37.8012);
      expect(stop.lon, -5.1050);
      expect(stop.distanceMeters, 350.0);
      expect(stop.packageCount, 1);
    });

    test('deserializa lista de packages', () {
      final stop = StopInfo.fromJson(_stopInfoJson());
      expect(stop.packages.length, 1);
      expect(stop.packages[0].clientName, 'Juan García');
    });

    test('lat y lon pueden ser null (dirección no geocodificada)', () {
      final stop = StopInfo.fromJson(_stopInfoJson(lat: null, lon: null));
      expect(stop.lat, isNull);
      expect(stop.lon, isNull);
    });

    test('alias ausente usa cadena vacía', () {
      final json = Map<String, dynamic>.from(_stopInfoJson())..remove('alias');
      final stop = StopInfo.fromJson(json);
      expect(stop.alias, '');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  StopInfo — getters
  // ══════════════════════════════════════════════════════════════════

  group('StopInfo getters', () {
    test('isOrigin es true cuando type == "origin"', () {
      final stop = StopInfo.fromJson(_stopInfoJson(type: 'origin'));
      expect(stop.isOrigin, isTrue);
    });

    test('isOrigin es false cuando type == "stop"', () {
      final stop = StopInfo.fromJson(_stopInfoJson(type: 'stop'));
      expect(stop.isOrigin, isFalse);
    });

    test('hasMultiplePackages es false con packageCount == 1', () {
      final stop = StopInfo.fromJson(_stopInfoJson());
      expect(stop.hasMultiplePackages, isFalse);
    });

    test('hasMultiplePackages es true con packageCount > 1', () {
      final json = Map<String, dynamic>.from(_stopInfoJson())
        ..['package_count'] = 3;
      final stop = StopInfo.fromJson(json);
      expect(stop.hasMultiplePackages, isTrue);
    });

    test('displayName devuelve la dirección', () {
      final stop = StopInfo.fromJson(_stopInfoJson());
      expect(stop.displayName, 'Calle Gaitán 24');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  RouteSummary.fromJson
  // ══════════════════════════════════════════════════════════════════

  group('RouteSummary.fromJson', () {
    test('deserializa todos los campos', () {
      final summary = RouteSummary.fromJson(_routeSummaryJson());
      expect(summary.totalStops, 5);
      expect(summary.totalPackages, 7);
      expect(summary.totalDistanceM, 4200.0);
      expect(summary.totalDistanceDisplay, '4.2 km');
      expect(summary.computingTimeMs, 7.0);
    });

    test('total_packages ausente es 0 por defecto', () {
      final json = Map<String, dynamic>.from(_routeSummaryJson())
        ..remove('total_packages');
      final summary = RouteSummary.fromJson(json);
      expect(summary.totalPackages, 0);
    });

    test('acepta distancia como entero (int → double)', () {
      final json = Map<String, dynamic>.from(_routeSummaryJson())
        ..['total_distance_m'] = 4200;
      final summary = RouteSummary.fromJson(json);
      expect(summary.totalDistanceM, 4200.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  OptimizeResponse.fromJson
  // ══════════════════════════════════════════════════════════════════

  group('OptimizeResponse.fromJson', () {
    test('deserializa respuesta completa del backend', () {
      final response = OptimizeResponse.fromJson({
        'success': true,
        'summary': _routeSummaryJson(),
        'stops': [_stopInfoJson(type: 'origin'), _stopInfoJson()],
      });

      expect(response.success, isTrue);
      expect(response.stops.length, 2);
      expect(response.stops[0].isOrigin, isTrue);
      expect(response.summary.totalStops, 5);
    });

    test('lista de paradas vacía es válida', () {
      final response = OptimizeResponse.fromJson({
        'success': true,
        'summary': _routeSummaryJson(),
        'stops': [],
      });
      expect(response.stops, isEmpty);
    });
  });
}
