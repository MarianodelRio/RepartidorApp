/// Modelo de datos de un CSV de paradas.
///
/// Formato esperado: cliente,direccion,ciudad[,nota][,alias]
/// Cada fila = 1 paquete. Las agrupaciones se hacen después.
class CsvData {
  final List<String> clientes;
  final List<String> direcciones;
  final List<String> ciudades;
  final List<String> notas;
  final List<String> aliases; // nombre de negocio/lugar (opcional, activa Places)

  const CsvData({
    required this.clientes,
    required this.direcciones,
    required this.ciudades,
    this.notas = const [],
    this.aliases = const [],
  });

  /// Nº total de filas (= nº de paquetes).
  int get totalPackages => direcciones.length;

  bool get isEmpty => direcciones.isEmpty;
  bool get isNotEmpty => direcciones.isNotEmpty;
}
