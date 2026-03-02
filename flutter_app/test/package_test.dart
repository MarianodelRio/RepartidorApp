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
      });
      expect(pkg.clientName, 'Juan García');
      expect(pkg.nota, '2º izquierda');
    });

    test('campos ausentes usan cadena vacía', () {
      final pkg = Package.fromJson({});
      expect(pkg.clientName, '');
      expect(pkg.nota, '');
    });

    test('campos null usan cadena vacía', () {
      final pkg = Package.fromJson({'client_name': null, 'nota': null});
      expect(pkg.clientName, '');
      expect(pkg.nota, '');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Package — serialización toJson / toMap
  // ══════════════════════════════════════════════════════════════════

  group('Package.toJson', () {
    test('serializa ambos campos', () {
      const pkg = Package(clientName: 'Juan', nota: 'bajo');
      final json = pkg.toJson();
      expect(json['client_name'], 'Juan');
      expect(json['nota'], 'bajo');
    });

    test('round-trip fromJson → toJson preserva los valores', () {
      final original = {'client_name': 'María', 'nota': '3º derecha'};
      final restored = Package.fromJson(original).toJson();
      expect(restored, original);
    });
  });

  group('Package.toMap / fromMap', () {
    test('round-trip toMap → fromMap preserva los valores', () {
      const pkg = Package(clientName: 'Pedro', nota: 'portería');
      final map = pkg.toMap();
      final restored = Package.fromMap(map);
      expect(restored.clientName, pkg.clientName);
      expect(restored.nota, pkg.nota);
    });

    test('fromMap con campos null usa cadena vacía', () {
      final pkg = Package.fromMap({'client_name': null, 'nota': null});
      expect(pkg.clientName, '');
      expect(pkg.nota, '');
    });
  });
}
