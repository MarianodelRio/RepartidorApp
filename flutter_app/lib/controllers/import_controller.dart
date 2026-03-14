import 'package:flutter/foundation.dart';

import '../models/csv_data.dart';
import '../models/origin_mode.dart';
import '../models/route_models.dart';
import '../models/validation_models.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/persistence_service.dart';

/// Controlador de estado para la pantalla de importación.
///
/// Gestiona cuatro grupos de estado independientes de la UI:
///   1. Estado del servidor (online / comprobando)
///   2. Sesión de reparto activa (reanudable)
///   3. CSV importado + resultado de validación + correcciones de pin
///   4. Origen de la ruta + cálculo de ruta optimizada
///
/// La pantalla observa este controller vía [ListenableBuilder].
/// No contiene [BuildContext], diálogos, ni navegación.
class ImportController extends ChangeNotifier {
  bool _disposed = false;

  // ── 1. Servidor ──────────────────────────────────────────────────

  bool _serverOnline = false;
  bool _isCheckingServer = false;

  bool get serverOnline => _serverOnline;
  bool get isCheckingServer => _isCheckingServer;

  Future<void> checkServer() async {
    _isCheckingServer = true;
    _notify();

    final online = await ApiService.healthCheck();

    if (_disposed) return;
    _serverOnline = online;
    _isCheckingServer = false;
    _notify();
  }

  // ── 2. Sesión activa ─────────────────────────────────────────────

  bool _hasActiveSession = false;

  bool get hasActiveSession => _hasActiveSession;

  Future<void> checkActiveSession() async {
    final has = await PersistenceService.hasActiveSession();
    if (_disposed) return;
    _hasActiveSession = has;
    _notify();
  }

  Future<void> discardSession() async {
    await PersistenceService.clearSession();
    if (_disposed) return;
    _hasActiveSession = false;
    _notify();
  }

  /// Marca la sesión como no activa sin llamar a Hive.
  /// Útil cuando la sesión ya fue descartada por otro motivo.
  void clearActiveSessionFlag() {
    _hasActiveSession = false;
    _notify();
  }

  // ── 3. CSV + Validación ──────────────────────────────────────────

  CsvData? _csvData;
  String _fileName = '';
  ValidationResult? _reviewResult;

  CsvData? get csvData => _csvData;
  String get fileName => _fileName;
  ValidationResult? get reviewResult => _reviewResult;

  /// Almacena el CSV parseado e invalida cualquier resultado de validación previo.
  void loadCsvData(CsvData data, String fileName) {
    _csvData = data;
    _fileName = fileName;
    _reviewResult = null;
    _notify();
  }

  /// Limpia todo el estado de importación: CSV, validación, origen y error de ruta.
  void clearCsvData() {
    _csvData = null;
    _fileName = '';
    _reviewResult = null;
    _originMode = OriginMode.defaultAddress;
    _manualAddress = '';
    _routeError = null;
    _notify();
  }

  /// Llama al backend para geocodificar y agrupar las paradas.
  /// Almacena el resultado en [reviewResult].
  /// Lanza [ApiException] si el servidor responde con error.
  Future<void> startValidation() async {
    assert(_csvData != null, 'startValidation requiere csvData cargado');

    final result = await ApiService.validationStart(csvData: _csvData!);

    if (_disposed) return;
    _reviewResult = result;
    _notify();
  }

  // ── 3b. Correcciones de pin ──────────────────────────────────────

  /// Convierte una parada fallida en geocodificada aplicando coordenadas manuales.
  /// Notifica al backend de forma fire-and-forget.
  void applyPin(FailedStop stop, double lat, double lon) {
    if (_reviewResult == null) return;

    ApiService.postOverride(address: stop.address, lat: lat, lon: lon);

    final newGeocoded = GeocodedStop(
      address: stop.address,
      alias: stop.alias,
      clientName:
          stop.clientNames.firstWhere((n) => n.isNotEmpty, orElse: () => ''),
      allClientNames: stop.clientNames,
      packages: stop.packages,
      packageCount: stop.packageCount,
      lat: lat,
      lon: lon,
      confidence: GeoConfidence.override,
    );

    _reviewResult = ValidationResult(
      geocoded: [..._reviewResult!.geocoded, newGeocoded],
      failed: _reviewResult!.failed
          .where((f) => f.address != stop.address)
          .toList(),
      totalPackages: _reviewResult!.totalPackages,
      uniqueAddresses: _reviewResult!.uniqueAddresses,
    );
    _notify();
  }

  /// Reemplaza las coordenadas de una parada ya geocodificada.
  /// Notifica al backend de forma fire-and-forget.
  void applyRepinGeocoded(GeocodedStop stop, double lat, double lon) {
    if (_reviewResult == null) return;

    ApiService.postOverride(address: stop.address, lat: lat, lon: lon);

    final updated = GeocodedStop(
      address: stop.address,
      alias: stop.alias,
      clientName: stop.clientName,
      allClientNames: stop.allClientNames,
      packages: stop.packages,
      packageCount: stop.packageCount,
      lat: lat,
      lon: lon,
      confidence: GeoConfidence.override,
    );

    _reviewResult = ValidationResult(
      geocoded: _reviewResult!.geocoded
          .map((s) => s.address == stop.address ? updated : s)
          .toList(),
      failed: _reviewResult!.failed,
      totalPackages: _reviewResult!.totalPackages,
      uniqueAddresses: _reviewResult!.uniqueAddresses,
    );
    _notify();
  }

  // ── 4. Origen + Cálculo de ruta ──────────────────────────────────

  OriginMode _originMode = OriginMode.defaultAddress;
  String _manualAddress = '';
  bool _isCalculating = false;
  String? _routeError;

  OriginMode get originMode => _originMode;
  String get manualAddress => _manualAddress;
  bool get isCalculating => _isCalculating;
  String? get routeError => _routeError;

  void setOriginMode(OriginMode mode) {
    _originMode = mode;
    _notify();
  }

  void setManualAddress(String address) {
    _manualAddress = address;
    _notify();
  }

  void clearRouteError() {
    _routeError = null;
    _notify();
  }

  /// Resuelve el origen, construye el payload y llama a [ApiService.optimize].
  ///
  /// - Actualiza [isCalculating] y [routeError] internamente.
  /// - Lanza [LocationException] si el GPS falla.
  /// - Lanza [ApiException] si el servidor responde con error.
  /// - La pantalla gestiona el diálogo de progreso y la navegación.
  Future<OptimizeResponse> calculateRoute() async {
    assert(_reviewResult != null, 'calculateRoute requiere reviewResult');

    _isCalculating = true;
    _routeError = null;
    _notify();

    try {
      // Resolver dirección de inicio según modo de origen
      String? startAddress;
      if (_originMode == OriginMode.manual && _manualAddress.isNotEmpty) {
        startAddress = _manualAddress;
      } else if (_originMode == OriginMode.gps) {
        final pos = await LocationService.getCurrentPosition();
        startAddress = '${pos.latitude}, ${pos.longitude}';
      }

      if (_disposed) throw Exception('Cancelado');

      // Construir payload desde las paradas geocodificadas
      final geocoded = _reviewResult!.geocoded;
      if (geocoded.isEmpty) {
        throw Exception('No hay paradas válidas para calcular la ruta');
      }

      final optimizeAddresses = <String>[];
      final optimizeClientNames = <String>[];
      final preResolvedCoords = <List<double>?>[];
      final packageCounts = <int>[];
      final packagesPerStop = <List<Package>>[];
      final aliases = <String>[];

      for (final st in geocoded) {
        optimizeAddresses.add(st.address);
        optimizeClientNames.add(st.clientName);
        preResolvedCoords.add([st.lat, st.lon]);
        packageCounts.add(st.packageCount);
        packagesPerStop.add(st.packages);
        aliases.add(st.alias);
      }

      final result = await ApiService.optimize(
        addresses: optimizeAddresses,
        clientNames: optimizeClientNames,
        startAddress: startAddress,
        coords: preResolvedCoords,
        packageCounts: packageCounts,
        packagesPerStop: packagesPerStop,
        aliases: aliases,
      );

      if (_disposed) throw Exception('Cancelado');

      await PersistenceService.clearValidationState();
      return result;
    } catch (e) {
      if (_disposed) rethrow;
      _routeError = e is ApiException ? e.message : e.toString();
      _notify();
      rethrow;
    } finally {
      if (!_disposed) {
        _isCalculating = false;
        _notify();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
