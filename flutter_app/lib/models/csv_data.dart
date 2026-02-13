/// Modelo de datos de un CSV de paradas.
///
/// Formato esperado: cliente,direccion,ciudad
/// Cada fila = 1 paquete. Las agrupaciones se hacen después.
class CsvData {
  final List<String> clientes;
  final List<String> direcciones;
  final List<String> ciudades;

  const CsvData({
    required this.clientes,
    required this.direcciones,
    required this.ciudades,
  });

  /// Nº total de filas (= nº de paquetes).
  int get totalPackages => direcciones.length;

  /// Construye la dirección completa: "direccion, ciudad".
  /// Si la dirección ya contiene la ciudad, no la duplica.
  List<String> get fullAddresses {
    final result = <String>[];
    for (int i = 0; i < direcciones.length; i++) {
      final dir = direcciones[i].trim();
      final city = i < ciudades.length ? ciudades[i].trim() : '';
      if (city.isEmpty || dir.toLowerCase().contains(city.toLowerCase())) {
        result.add(dir);
      } else {
        result.add('$dir, $city');
      }
    }
    return result;
  }

  bool get isEmpty => direcciones.isEmpty;
  bool get isNotEmpty => direcciones.isNotEmpty;
}
