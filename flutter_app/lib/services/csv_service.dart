import 'dart:convert';
import 'dart:typed_data';

import '../models/csv_data.dart';

/// Servicio para parsear archivos CSV de paradas.
///
/// Formato esperado:
///   cliente,direccion,ciudad
///
/// Cada fila = 1 paquete.
class CsvService {
  /// Parsea bytes de un CSV y devuelve CsvData.
  static CsvData parse(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(text);

    if (lines.isEmpty) {
      return const CsvData(clientes: [], direcciones: [], ciudades: []);
    }

    // Detectar columnas desde la cabecera
    final headerLine = lines.first;
    final headers = _parseCsvLine(headerLine);
    final colMap = _detectColumns(headers);

    if (colMap['direccion']! < 0) {
      throw FormatException(
        'No se encontró la columna "direccion" en la cabecera.\n'
        'Cabeceras detectadas: ${headers.join(", ")}',
      );
    }

    final clientes = <String>[];
    final direcciones = <String>[];
    final ciudades = <String>[];

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final fields = _parseCsvLine(line);
      final dir = _safeGet(fields, colMap['direccion']!).trim();
      if (dir.isEmpty) continue;

      clientes.add(_safeGet(fields, colMap['cliente']!).trim());
      direcciones.add(dir);
      ciudades.add(_safeGet(fields, colMap['ciudad']!).trim());
    }

    return CsvData(
      clientes: clientes,
      direcciones: direcciones,
      ciudades: ciudades,
    );
  }

  /// Detecta las columnas cliente, direccion, ciudad por nombre.
  static Map<String, int> _detectColumns(List<String> headers) {
    int clienteIdx = -1, direccionIdx = -1, ciudadIdx = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().trim();
      if (clienteIdx < 0 &&
          (h == 'cliente' || h == 'nombre' || h == 'name' ||
           h.contains('client') || h.contains('nombre'))) {
        clienteIdx = i;
      }
      if (direccionIdx < 0 &&
          (h == 'direccion' || h == 'dirección' || h == 'address' ||
           h.contains('direcc') || h.contains('calle') || h.contains('domicilio'))) {
        direccionIdx = i;
      }
      if (ciudadIdx < 0 &&
          (h == 'ciudad' || h == 'localidad' || h == 'city' ||
           h.contains('ciudad') || h.contains('localidad') ||
           h.contains('poblac'))) {
        ciudadIdx = i;
      }
    }

    return {
      'cliente': clienteIdx,
      'direccion': direccionIdx,
      'ciudad': ciudadIdx,
    };
  }

  /// Parsea una línea CSV respetando comillas.
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++; // Saltar el siguiente "
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          fields.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(ch);
        }
      }
    }
    fields.add(buffer.toString());
    return fields;
  }

  static String _safeGet(List<String> list, int index) {
    if (index < 0 || index >= list.length) return '';
    return list[index];
  }
}
