import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/models/csv_data.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  CsvData — getters y constructores
  // ══════════════════════════════════════════════════════════════════

  group('CsvData — isEmpty / isNotEmpty', () {
    test('isEmpty es true cuando no hay direcciones', () {
      const data = CsvData(
        clientes: [],
        direcciones: [],
        ciudades: [],
      );
      expect(data.isEmpty, isTrue);
      expect(data.isNotEmpty, isFalse);
    });

    test('isNotEmpty es true cuando hay al menos una dirección', () {
      const data = CsvData(
        clientes: ['Juan'],
        direcciones: ['Calle A 1'],
        ciudades: ['Posadas'],
      );
      expect(data.isNotEmpty, isTrue);
      expect(data.isEmpty, isFalse);
    });
  });

  group('CsvData — totalPackages', () {
    test('totalPackages es 0 para lista vacía', () {
      const data = CsvData(
        clientes: [],
        direcciones: [],
        ciudades: [],
      );
      expect(data.totalPackages, 0);
    });

    test('totalPackages refleja el número de filas', () {
      const data = CsvData(
        clientes: ['Juan', 'María', 'Pedro'],
        direcciones: ['Calle A 1', 'Calle B 2', 'Calle C 3'],
        ciudades: ['Posadas', 'Posadas', 'Posadas'],
      );
      expect(data.totalPackages, 3);
    });

    test('totalPackages se basa en direcciones, no en clientes', () {
      // Puede haber clientes vacíos pero las direcciones mandan
      const data = CsvData(
        clientes: ['', ''],
        direcciones: ['Calle A 1', 'Calle B 2'],
        ciudades: ['Posadas', 'Posadas'],
      );
      expect(data.totalPackages, 2);
    });
  });

  group('CsvData — columnas opcionales', () {
    test('notas, agencias y aliases tienen valor por defecto []', () {
      const data = CsvData(
        clientes: ['Juan'],
        direcciones: ['Calle A 1'],
        ciudades: ['Posadas'],
      );
      expect(data.notas, isEmpty);
      expect(data.agencias, isEmpty);
      expect(data.aliases, isEmpty);
    });

    test('acepta notas, agencias y aliases explícitos', () {
      const data = CsvData(
        clientes: ['Juan'],
        direcciones: ['Calle A 1'],
        ciudades: ['Posadas'],
        notas: ['bajo'],
        agencias: ['MRW'],
        aliases: ['Bar El Gato'],
      );
      expect(data.notas, ['bajo']);
      expect(data.agencias, ['MRW']);
      expect(data.aliases, ['Bar El Gato']);
    });
  });
}
