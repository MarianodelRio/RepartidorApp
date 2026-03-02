import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:repartir_app/services/csv_service.dart';

// Convierte un String a los bytes que produciría un fichero CSV real.
Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  CsvService.parse — casos básicos
  // ══════════════════════════════════════════════════════════════════

  group('CsvService.parse — básico', () {
    test('parsea una fila completa', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'Juan García,Calle Gaitán 24,Posadas',
      ));

      expect(data.clientes, ['Juan García']);
      expect(data.direcciones, ['Calle Gaitán 24']);
      expect(data.ciudades, ['Posadas']);
      expect(data.totalPackages, 1);
    });

    test('parsea múltiples filas', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'Juan,Calle Gaitán 24,Posadas\n'
        'María,Calle Mayor 5,Posadas',
      ));

      expect(data.totalPackages, 2);
      expect(data.clientes, ['Juan', 'María']);
      expect(data.direcciones, ['Calle Gaitán 24', 'Calle Mayor 5']);
    });

    test('CSV vacío devuelve CsvData vacío', () {
      final data = CsvService.parse(_bytes(''));
      expect(data.isEmpty, isTrue);
    });

    test('solo cabecera sin filas devuelve vacío', () {
      final data = CsvService.parse(_bytes('cliente,direccion,ciudad'));
      expect(data.isEmpty, isTrue);
    });

    test('ignora líneas vacías en el cuerpo', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        '\n'
        'Juan,Calle A 1,Posadas\n'
        '\n'
        'María,Calle B 2,Posadas\n'
        '\n',
      ));
      expect(data.totalPackages, 2);
    });

    test('ignora filas sin dirección', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'Juan,,Posadas\n'
        'María,Calle B 2,Posadas',
      ));
      expect(data.totalPackages, 1);
      expect(data.direcciones, ['Calle B 2']);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Detección de columnas opcionales
  // ══════════════════════════════════════════════════════════════════

  group('CsvService.parse — columnas opcionales', () {
    test('parsea columna nota', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad,nota\n'
        'Juan,Calle A 1,Posadas,2º izquierda',
      ));
      expect(data.notas, ['2º izquierda']);
    });

    test('nota vacía cuando no existe la columna', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.notas, ['']);
    });

    test('parsea columna alias', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad,alias\n'
        'Juan,Calle A 1,Posadas,Bar El Gato',
      ));
      expect(data.aliases, ['Bar El Gato']);
    });

    test('alias vacío cuando no existe la columna', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.aliases, ['']);
    });

    test('parsea todas las columnas a la vez', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad,nota,alias\n'
        'Juan,Calle A 1,Posadas,bajo,Bar El Gato',
      ));
      expect(data.clientes[0], 'Juan');
      expect(data.notas[0], 'bajo');
      expect(data.aliases[0], 'Bar El Gato');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Detección flexible de nombres de columna
  // ══════════════════════════════════════════════════════════════════

  group('CsvService.parse — variantes de cabecera', () {
    test('acepta "dirección" con tilde', () {
      final data = CsvService.parse(_bytes(
        'cliente,dirección,ciudad\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.direcciones, ['Calle A 1']);
    });

    test('acepta "address" en inglés', () {
      final data = CsvService.parse(_bytes(
        'name,address,city\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.direcciones, ['Calle A 1']);
    });

    test('acepta "nombre" como columna de cliente', () {
      final data = CsvService.parse(_bytes(
        'nombre,direccion,ciudad\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.clientes, ['Juan']);
    });

    test('acepta "domicilio" como columna de dirección', () {
      final data = CsvService.parse(_bytes(
        'cliente,domicilio,ciudad\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.direcciones, ['Calle A 1']);
    });

    test('acepta "localidad" como columna de ciudad', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,localidad\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.ciudades, ['Posadas']);
    });

    test('acepta cabeceras en mayúsculas', () {
      final data = CsvService.parse(_bytes(
        'CLIENTE,DIRECCION,CIUDAD\n'
        'Juan,Calle A 1,Posadas',
      ));
      expect(data.direcciones, ['Calle A 1']);
    });

    test('lanza FormatException si no hay columna de dirección', () {
      expect(
        () => CsvService.parse(_bytes('nombre,ciudad\nJuan,Posadas')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Parser de líneas CSV (comillas y caracteres especiales)
  // ══════════════════════════════════════════════════════════════════

  group('CsvService.parse — comillas y comas en campos', () {
    test('campo con coma entre comillas no parte la columna', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        '"García, Juan",Calle A 1,Posadas',
      ));
      expect(data.clientes[0], 'García, Juan');
      expect(data.direcciones[0], 'Calle A 1');
    });

    test('dirección con coma entre comillas se parsea completa', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'Juan,"Calle A, 1",Posadas',
      ));
      expect(data.direcciones[0], 'Calle A, 1');
    });

    test('comillas dobles escapadas dentro de un campo', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        '"García ""El Bueno""",Calle A 1,Posadas',
      ));
      expect(data.clientes[0], 'García "El Bueno"');
    });

    test('campo completamente entre comillas se limpia de ellas', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        '"Juan","Calle A 1","Posadas"',
      ));
      expect(data.clientes[0], 'Juan');
      expect(data.direcciones[0], 'Calle A 1');
      expect(data.ciudades[0], 'Posadas');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Codificación UTF-8
  // ══════════════════════════════════════════════════════════════════

  group('CsvService.parse — codificación', () {
    test('maneja caracteres españoles correctamente', () {
      final data = CsvService.parse(_bytes(
        'cliente,direccion,ciudad\n'
        'María Gómez,Avenida Andalucía 3,Córdoba',
      ));
      expect(data.clientes[0], 'María Gómez');
      expect(data.direcciones[0], 'Avenida Andalucía 3');
    });
  });
}
