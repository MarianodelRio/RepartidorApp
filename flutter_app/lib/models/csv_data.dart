/// Una fila del CSV: un paquete con todos sus campos.
class CsvRow {
  final String cliente;
  final String direccion;
  final String ciudad;
  final String nota;
  final String agencia;
  final String alias;

  const CsvRow({
    required this.cliente,
    required this.direccion,
    required this.ciudad,
    this.nota = '',
    this.agencia = '',
    this.alias = '',
  });
}

/// Colección de filas parseadas de un CSV de paradas.
///
/// Formato esperado: cliente,direccion,ciudad[,nota][,agencia][,alias]
/// Cada fila = 1 paquete. Las agrupaciones se hacen después.
class CsvData {
  final List<CsvRow> rows;

  const CsvData({required this.rows});

  /// Nº total de filas (= nº de paquetes).
  int get totalPackages => rows.length;

  bool get isEmpty => rows.isEmpty;
  bool get isNotEmpty => rows.isNotEmpty;
}
