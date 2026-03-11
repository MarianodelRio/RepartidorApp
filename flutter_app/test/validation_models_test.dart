import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/models/validation_models.dart';

// JSON de ejemplo que simula exactamente lo que devuelve el backend.
Map<String, dynamic> _geocodedStopJson({
  String confidence = 'EXACT_ADDRESS',
}) =>
    {
      'address': 'Calle Gaitán 24',
      'alias': 'Bar El Gato',
      'client_name': 'Juan García',
      'all_client_names': ['Juan García', 'María López'],
      'packages': [
        {'client_name': 'Juan García', 'nota': '', 'agencia': 'MRW'},
        {'client_name': 'María López', 'nota': '2º izq', 'agencia': ''},
      ],
      'package_count': 2,
      'lat': 37.8012,
      'lon': -5.1050,
      'confidence': confidence,
    };

Map<String, dynamic> _failedStopJson() => {
      'address': 'Calle Inventada 99',
      'alias': '',
      'client_names': ['Pedro Ruiz'],
      'packages': [
        {'client_name': 'Pedro Ruiz', 'nota': '', 'agencia': 'SEUR'},
      ],
      'package_count': 1,
    };

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  GeoConfidence.fromString
  // ══════════════════════════════════════════════════════════════════

  group('GeoConfidence.fromString', () {
    test('EXACT_ADDRESS → exactAddress', () {
      expect(GeoConfidence.fromString('EXACT_ADDRESS'), GeoConfidence.exactAddress);
    });

    test('GOOD → good', () {
      expect(GeoConfidence.fromString('GOOD'), GeoConfidence.good);
    });

    test('EXACT_PLACE → exactPlace', () {
      expect(GeoConfidence.fromString('EXACT_PLACE'), GeoConfidence.exactPlace);
    });

    test('OVERRIDE → override', () {
      expect(GeoConfidence.fromString('OVERRIDE'), GeoConfidence.override);
    });

    test('FAILED → failed', () {
      expect(GeoConfidence.fromString('FAILED'), GeoConfidence.failed);
    });

    test('cadena desconocida → failed', () {
      expect(GeoConfidence.fromString('UNKNOWN'), GeoConfidence.failed);
      expect(GeoConfidence.fromString(''), GeoConfidence.failed);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  GeoConfidence.isAccepted
  // ══════════════════════════════════════════════════════════════════

  group('GeoConfidence.isAccepted', () {
    test('exactAddress, good, exactPlace y override son aceptados', () {
      expect(GeoConfidence.exactAddress.isAccepted, isTrue);
      expect(GeoConfidence.good.isAccepted, isTrue);
      expect(GeoConfidence.exactPlace.isAccepted, isTrue);
      expect(GeoConfidence.override.isAccepted, isTrue);
    });

    test('failed NO es aceptado', () {
      expect(GeoConfidence.failed.isAccepted, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  GeocodedStop.fromJson — contrato con el backend
  // ══════════════════════════════════════════════════════════════════

  group('GeocodedStop.fromJson', () {
    test('deserializa todos los campos correctamente', () {
      final stop = GeocodedStop.fromJson(_geocodedStopJson());
      expect(stop.address, 'Calle Gaitán 24');
      expect(stop.alias, 'Bar El Gato');
      expect(stop.clientName, 'Juan García');
      expect(stop.allClientNames, ['Juan García', 'María López']);
      expect(stop.packageCount, 2);
      expect(stop.lat, 37.8012);
      expect(stop.lon, -5.1050);
      expect(stop.confidence, GeoConfidence.exactAddress);
    });

    test('deserializa la lista de packages con agencia', () {
      final stop = GeocodedStop.fromJson(_geocodedStopJson());
      expect(stop.packages.length, 2);
      expect(stop.packages[0].clientName, 'Juan García');
      expect(stop.packages[0].agencia, 'MRW');
      expect(stop.packages[1].nota, '2º izq');
      expect(stop.packages[1].agencia, '');
    });

    test('confidence GOOD se mapea correctamente', () {
      final stop = GeocodedStop.fromJson(_geocodedStopJson(confidence: 'GOOD'));
      expect(stop.confidence, GeoConfidence.good);
    });

    test('alias ausente usa cadena vacía', () {
      final json = Map<String, dynamic>.from(_geocodedStopJson())
        ..remove('alias');
      final stop = GeocodedStop.fromJson(json);
      expect(stop.alias, '');
    });

    test('all_client_names ausente usa lista vacía', () {
      final json = Map<String, dynamic>.from(_geocodedStopJson())
        ..remove('all_client_names');
      final stop = GeocodedStop.fromJson(json);
      expect(stop.allClientNames, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  GeocodedStop.copyWith
  // ══════════════════════════════════════════════════════════════════

  group('GeocodedStop.copyWith', () {
    test('actualiza lat y lon', () {
      final original = GeocodedStop.fromJson(_geocodedStopJson());
      final modified = original.copyWith(lat: 38.0, lon: -5.5);
      expect(modified.lat, 38.0);
      expect(modified.lon, -5.5);
      expect(modified.address, original.address); // sin cambios
    });

    test('actualiza confidence', () {
      final original = GeocodedStop.fromJson(_geocodedStopJson());
      final modified = original.copyWith(confidence: GeoConfidence.override);
      expect(modified.confidence, GeoConfidence.override);
      expect(modified.clientName, original.clientName); // sin cambios
    });

    test('sin argumentos no cambia nada', () {
      final original = GeocodedStop.fromJson(_geocodedStopJson());
      final copy = original.copyWith();
      expect(copy.address, original.address);
      expect(copy.lat, original.lat);
      expect(copy.confidence, original.confidence);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  FailedStop.fromJson
  // ══════════════════════════════════════════════════════════════════

  group('FailedStop.fromJson', () {
    test('deserializa todos los campos', () {
      final stop = FailedStop.fromJson(_failedStopJson());
      expect(stop.address, 'Calle Inventada 99');
      expect(stop.alias, '');
      expect(stop.clientNames, ['Pedro Ruiz']);
      expect(stop.packageCount, 1);
    });

    test('deserializa la lista de packages', () {
      final stop = FailedStop.fromJson(_failedStopJson());
      expect(stop.packages.length, 1);
      expect(stop.packages[0].clientName, 'Pedro Ruiz');
    });

    test('client_names ausente usa lista vacía', () {
      final json = Map<String, dynamic>.from(_failedStopJson())
        ..remove('client_names');
      final stop = FailedStop.fromJson(json);
      expect(stop.clientNames, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  ValidationResult.fromJson
  // ══════════════════════════════════════════════════════════════════

  group('ValidationResult.fromJson', () {
    test('deserializa geocoded y failed correctamente', () {
      final result = ValidationResult.fromJson({
        'geocoded': [_geocodedStopJson()],
        'failed': [_failedStopJson()],
        'total_packages': 3,
        'unique_addresses': 2,
      });

      expect(result.geocoded.length, 1);
      expect(result.failed.length, 1);
      expect(result.totalPackages, 3);
      expect(result.uniqueAddresses, 2);
    });

    test('listas vacías son válidas', () {
      final result = ValidationResult.fromJson({
        'geocoded': [],
        'failed': [],
        'total_packages': 0,
        'unique_addresses': 0,
      });
      expect(result.geocoded, isEmpty);
      expect(result.failed, isEmpty);
    });
  });
}
