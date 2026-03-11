import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/models/route_models.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  Package — deserialización JSON (contrato con el backend)
  // ══════════════════════════════════════════════════════════════════

  group('Package.fromJson', () {
    test('deserializa campos completos', () {
      final pkg = Package.fromJson({
        'client_name': 'Juan García',
        'nota': '2º izquierda',
        'agencia': 'MRW',
      });
      expect(pkg.clientName, 'Juan García');
      expect(pkg.nota, '2º izquierda');
      expect(pkg.agencia, 'MRW');
    });

    test('campos ausentes usan cadena vacía', () {
      final pkg = Package.fromJson({});
      expect(pkg.clientName, '');
      expect(pkg.nota, '');
      expect(pkg.agencia, '');
    });

    test('campos null usan cadena vacía', () {
      final pkg = Package.fromJson({'client_name': null, 'nota': null, 'agencia': null});
      expect(pkg.clientName, '');
      expect(pkg.nota, '');
      expect(pkg.agencia, '');
    });

    test('agencia ausente en JSON legado usa cadena vacía', () {
      // Compatibilidad con respuestas del backend sin el campo agencia
      final pkg = Package.fromJson({'client_name': 'Ana', 'nota': 'bajo'});
      expect(pkg.agencia, '');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Package — serialización toJson / toMap
  // ══════════════════════════════════════════════════════════════════

  group('Package.toJson', () {
    test('serializa los tres campos', () {
      const pkg = Package(clientName: 'Juan', nota: 'bajo', agencia: 'SEUR');
      final json = pkg.toJson();
      expect(json['client_name'], 'Juan');
      expect(json['nota'], 'bajo');
      expect(json['agencia'], 'SEUR');
    });

    test('round-trip fromJson → toJson preserva los valores', () {
      final original = {'client_name': 'María', 'nota': '3º derecha', 'agencia': 'MRW'};
      final restored = Package.fromJson(original).toJson();
      expect(restored, original);
    });

    test('agencia vacía se serializa como cadena vacía', () {
      const pkg = Package(clientName: 'Juan', nota: '');
      expect(pkg.toJson()['agencia'], '');
    });
  });

  group('Package.toMap / fromMap', () {
    test('round-trip toMap → fromMap preserva los valores', () {
      const pkg = Package(clientName: 'Pedro', nota: 'portería', agencia: 'GLS');
      final map = pkg.toMap();
      final restored = Package.fromMap(map);
      expect(restored.clientName, pkg.clientName);
      expect(restored.nota, pkg.nota);
      expect(restored.agencia, pkg.agencia);
    });

    test('fromMap con campos null usa cadena vacía', () {
      final pkg = Package.fromMap({'client_name': null, 'nota': null, 'agencia': null});
      expect(pkg.clientName, '');
      expect(pkg.nota, '');
      expect(pkg.agencia, '');
    });
  });
}
