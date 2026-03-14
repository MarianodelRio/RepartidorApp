import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/models/csv_data.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  CsvData — getters y constructores
  // ══════════════════════════════════════════════════════════════════

  group('CsvData — isEmpty / isNotEmpty', () {
    test('isEmpty es true cuando no hay filas', () {
      const data = CsvData(rows: []);
      expect(data.isEmpty, isTrue);
      expect(data.isNotEmpty, isFalse);
    });

    test('isNotEmpty es true cuando hay al menos una fila', () {
      const data = CsvData(rows: [
        CsvRow(cliente: 'Juan', direccion: 'Calle A 1', ciudad: 'Posadas'),
      ]);
      expect(data.isNotEmpty, isTrue);
      expect(data.isEmpty, isFalse);
    });
  });

  group('CsvData — totalPackages', () {
    test('totalPackages es 0 para lista vacía', () {
      const data = CsvData(rows: []);
      expect(data.totalPackages, 0);
    });

    test('totalPackages refleja el número de filas', () {
      const data = CsvData(rows: [
        CsvRow(cliente: 'Juan', direccion: 'Calle A 1', ciudad: 'Posadas'),
        CsvRow(cliente: 'María', direccion: 'Calle B 2', ciudad: 'Posadas'),
        CsvRow(cliente: 'Pedro', direccion: 'Calle C 3', ciudad: 'Posadas'),
      ]);
      expect(data.totalPackages, 3);
    });

    test('totalPackages cuenta filas aunque cliente esté vacío', () {
      const data = CsvData(rows: [
        CsvRow(cliente: '', direccion: 'Calle A 1', ciudad: 'Posadas'),
        CsvRow(cliente: '', direccion: 'Calle B 2', ciudad: 'Posadas'),
      ]);
      expect(data.totalPackages, 2);
    });
  });

  group('CsvData — campos opcionales de CsvRow', () {
    test('nota, agencia y alias tienen valor vacío por defecto', () {
      const data = CsvData(rows: [
        CsvRow(cliente: 'Juan', direccion: 'Calle A 1', ciudad: 'Posadas'),
      ]);
      expect(data.rows.first.nota, isEmpty);
      expect(data.rows.first.agencia, isEmpty);
      expect(data.rows.first.alias, isEmpty);
    });

    test('acepta nota, agencia y alias explícitos', () {
      const data = CsvData(rows: [
        CsvRow(
          cliente: 'Juan',
          direccion: 'Calle A 1',
          ciudad: 'Posadas',
          nota: 'bajo',
          agencia: 'MRW',
          alias: 'Bar El Gato',
        ),
      ]);
      expect(data.rows.first.nota, 'bajo');
      expect(data.rows.first.agencia, 'MRW');
      expect(data.rows.first.alias, 'Bar El Gato');
    });
  });
}
