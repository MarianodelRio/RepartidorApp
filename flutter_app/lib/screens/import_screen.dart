import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:typed_data';

import '../config/app_theme.dart';
import '../models/csv_data.dart';
import '../models/validation_v3_models.dart';
import '../services/api_service.dart';
import '../services/csv_service.dart';
import '../services/location_service.dart';
import '../services/persistence_service.dart';
import '../widgets/origin_selector.dart';
import 'delivery_screen.dart';
import 'result_screen.dart';

// ═══════════════════════════════════════════
//  Pantalla de importación — v8 CSV limpio
//
//  Flujo:
//    1. Subir CSV (cliente, direccion, ciudad)
//    2. Validar (agrupa + geocodifica con Nominatim)
//    3. Si hay problemas → pin manual en el mapa
//    4. Calcular ruta
// ═══════════════════════════════════════════

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // ── Datos importados ──
  CsvData? _csvData;
  String _fileName = '';

  // ── Configuración de ruta ──
  OriginMode _originMode = OriginMode.defaultAddress;
  String _manualAddress = '';

  // ── Estado general ──
  bool _isLoading = false;
  bool _isCheckingServer = false;
  String? _error;
  bool _serverOnline = false;
  bool _hasActiveSession = false;

  // ── Validación ──
  ValidationResponse? _validationResult;
  bool _isValidating = false;
  bool _hasEverValidated = false;

  // ── Direcciones ──
  List<String> _addresses = [];
  List<String> _clientNames = [];

  @override
  void initState() {
    super.initState();
    _checkServer();
    _checkActiveSession();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  // ── Getters de estado ──

  int get _stopCount => _addresses.length;
  int get _totalPackages => _csvData?.totalPackages ?? 0;

  int get _okCount => _validationResult?.okCount ?? 0;
  int get _problemCount => _validationResult?.problemCount ?? 0;
  int get _uniqueAddresses => _validationResult?.uniqueAddresses ?? 0;

  bool get _allOk =>
      _hasEverValidated &&
      _validationResult != null &&
      _validationResult!.problemCount == 0;

  bool get _canValidate =>
      _csvData != null &&
      _stopCount > 0 &&
      !_isLoading &&
      !_isValidating &&
      _serverOnline;

  bool get _canCalculate =>
      _csvData != null &&
      _stopCount > 0 &&
      !_isLoading &&
      !_isValidating &&
      _serverOnline &&
      _hasEverValidated;

  // ═══════════════════════════════════════════
  //  Servidor / Sesión
  // ═══════════════════════════════════════════

  Future<void> _checkActiveSession() async {
    final has = await PersistenceService.hasActiveSession();
    if (mounted) setState(() => _hasActiveSession = has);
  }

  Future<void> _resumeDelivery() async {
    final session = await PersistenceService.loadSession();
    if (session == null || !mounted) return;
    Navigator.of(context)
        .push(
            MaterialPageRoute(builder: (_) => DeliveryScreen(session: session)))
        .then((_) => _checkActiveSession());
  }

  Future<void> _checkServer() async {
    setState(() => _isCheckingServer = true);
    final online = await ApiService.healthCheck();
    if (mounted) {
      setState(() {
        _serverOnline = online;
        _isCheckingServer = false;
      });
    }
  }

  void _showError(String msg) {
    if (mounted) setState(() => _error = msg);
  }

  // ═══════════════════════════════════════════
  //  Importar archivo
  // ═══════════════════════════════════════════

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) {
        _showError('No se pudo leer el archivo');
        return;
      }
      final csvData = CsvService.parse(Uint8List.fromList(file.bytes!));
      if (csvData.isEmpty) {
        _showError('El archivo está vacío o no tiene datos válidos');
        return;
      }

      final addresses = csvData.fullAddresses;
      final clientNames = csvData.clientes;

      setState(() {
        _csvData = csvData;
        _fileName = file.name;
        _addresses = addresses;
        _clientNames = clientNames;
        _error = null;
        _validationResult = null;
        _hasEverValidated = false;
      });
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error al seleccionar archivo: $e');
    }
  }

  void _clearFile() {
    setState(() {
      _csvData = null;
      _fileName = '';
      _addresses = [];
      _clientNames = [];
      _error = null;
      _validationResult = null;
      _hasEverValidated = false;
    });
  }

  // ═══════════════════════════════════════════
  //  Validación
  // ═══════════════════════════════════════════

  Future<void> _validate() async {
    if (_addresses.isEmpty) return;

    setState(() {
      _isValidating = true;
      _error = null;
    });
    WakelockPlus.enable();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ValidationProgressDialog(),
    );

    try {
      final result = await ApiService.validationStart(
        addresses: _addresses,
        clientNames: _clientNames,
      );
      if (!mounted) return;
      Navigator.of(context).pop();

      setState(() {
        _validationResult = result;
        _hasEverValidated = true;
      });

      if (result.problemCount > 0) {
        _showProblemsSheet();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✅ ${result.okCount} direcciones validadas en ${result.elapsedMs.toStringAsFixed(0)}ms'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e.message);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError('Error de validación: $e');
    } finally {
      WakelockPlus.disable();
      if (mounted) setState(() => _isValidating = false);
    }
  }

  // ═══════════════════════════════════════════
  //  Pin manual (situar en el mapa)
  // ═══════════════════════════════════════════

  void _pinStop(StopValidationResult stop) {
    final latCtrl =
        TextEditingController(text: (stop.lat ?? 37.802).toStringAsFixed(6));
    final lonCtrl =
        TextEditingController(text: (stop.lon ?? -5.105).toStringAsFixed(6));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.add_location_alt, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Situar en el mapa',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_off,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(stop.address,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              if (stop.packageCount > 1) ...[
                const SizedBox(height: 6),
                Text(
                    '${stop.packageCount} paquetes en esta dirección',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 16),
              const Text('Introduce las coordenadas:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              TextField(
                controller: latCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Latitud',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.north,
                      size: 18, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lonCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Longitud',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.east,
                      size: 18, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Busca la dirección en Google Maps, mantén pulsado y copia las coordenadas.',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final parsedLat = double.tryParse(latCtrl.text);
              final parsedLon = double.tryParse(lonCtrl.text);
              if (parsedLat == null || parsedLon == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Coordenadas inválidas'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop();
              _applyPin(stop, parsedLat, parsedLon);
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Guardar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _applyPin(StopValidationResult stop, double lat, double lon) {
    if (_validationResult == null) return;

    final updatedStops = _validationResult!.stops.map((s) {
      if (s.index == stop.index) {
        return StopValidationResult(
          index: s.index,
          address: s.address,
          status: 'ok',
          lat: lat,
          lon: lon,
          packageCount: s.packageCount,
          clientNames: s.clientNames,
          reason: '',
        );
      }
      return s;
    }).toList();

    final newOk = updatedStops.where((s) => s.isOk).length;
    final newProblem = updatedStops.where((s) => s.isProblem).length;

    setState(() {
      _validationResult = ValidationResponse(
        success: true,
        totalStops: _validationResult!.totalStops,
        uniqueAddresses: _validationResult!.uniqueAddresses,
        okCount: newOk,
        problemCount: newProblem,
        stops: updatedStops,
        elapsedMs: _validationResult!.elapsedMs,
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('📍 Pin guardado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════
  //  Bottom Sheet: direcciones con problema
  // ═══════════════════════════════════════════

  void _showProblemsSheet() {
    if (_validationResult == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProblemsSheet(
        validationResult: _validationResult!,
        onPinStop: (stop) => _pinStop(stop),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Calcular ruta
  // ═══════════════════════════════════════════

  Future<void> _calculateRoute() async {
    if (_addresses.isEmpty) return;

    if (_problemCount > 0) {
      final confirmed = await _showUnresolvedConfirmation();
      if (!confirmed) return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    String? startAddress;
    if (_originMode == OriginMode.manual && _manualAddress.isNotEmpty) {
      startAddress = _manualAddress;
    } else if (_originMode == OriginMode.gps) {
      try {
        final pos = await LocationService.getCurrentPosition();
        startAddress = '${pos.latitude}, ${pos.longitude}';
      } catch (e) {
        setState(() => _isLoading = false);
        _showError('Error GPS: $e');
        return;
      }
    }

    WakelockPlus.enable();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RouteProgressDialog(totalAddresses: _addresses.length),
    );

    try {
      // Datos para optimize — se construyen desde la validación si existe
      List<String> optimizeAddresses;
      List<String> optimizeClientNames;
      List<List<double>?>? preResolvedCoords;
      List<int>? packageCounts;
      List<List<String>>? allClientNames;

      if (_validationResult != null && _validationResult!.stops.isNotEmpty) {
        // Enviar las 70 paradas únicas YA agrupadas por la validación.
        // Cada stop tiene: address, coords, package_count, client_names.
        final okStops = _validationResult!.stops
            .where((s) => s.isOk && s.lat != null && s.lon != null)
            .toList();

        if (okStops.isEmpty) {
          throw Exception('No hay paradas válidas para calcular la ruta');
        }

        optimizeAddresses = [];
        optimizeClientNames = [];
        preResolvedCoords = [];
        packageCounts = [];
        allClientNames = [];

        for (final st in okStops) {
          optimizeAddresses.add(st.address);
          // Nombre principal: primer nombre no vacío
          final primary = st.clientNames
              .firstWhere((n) => n.isNotEmpty, orElse: () => '');
          optimizeClientNames.add(primary);
          preResolvedCoords.add([st.lat!, st.lon!]);
          packageCounts.add(st.packageCount);
          allClientNames.add(st.clientNames);
        }
      } else {
        // Sin validación previa: enviar las direcciones originales
        optimizeAddresses = _addresses;
        optimizeClientNames = _clientNames;
        preResolvedCoords = null;
        packageCounts = null;
        allClientNames = null;
      }

      final result = await ApiService.optimize(
        addresses: optimizeAddresses,
        clientNames: optimizeClientNames,
        startAddress: startAddress,
        coords: preResolvedCoords,
        packageCounts: packageCounts,
        allClientNames: allClientNames,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      PersistenceService.clearValidationState();

      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => ResultScreen(response: result)))
          .then((_) => _checkActiveSession());
    } on ApiException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e.message);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e.toString());
    } finally {
      WakelockPlus.disable();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showUnresolvedConfirmation() async {
    final problemAddrs = _validationResult!.stops
        .where((s) => s.isProblem)
        .map((s) => s.address)
        .toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Direcciones sin resolver',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Hay $_problemCount dirección${_problemCount > 1 ? 'es' : ''} '
                'sin coordenadas.\n\n'
                'Usa "Situar en el mapa" para resolverlas antes de calcular.',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            if (problemAddrs.length <= 6) ...[
              ...problemAddrs.map((name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.location_off,
                            size: 14, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(name,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                  )),
            ] else ...[
              Text(
                '${problemAddrs.take(4).join(', ')} y ${problemAddrs.length - 4} más…',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.route, size: 18),
            label: const Text('Calcular igualmente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ═══════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldLight,
      appBar: AppBar(
        title: const Text('Repartidor'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isCheckingServer
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : GestureDetector(
                    onTap: _checkServer,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle,
                            size: 10,
                            color: _serverOnline
                                ? AppColors.success
                                : AppColors.error),
                        const SizedBox(width: 4),
                        Text(_serverOnline ? 'Online' : 'Offline',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              if (_hasActiveSession) ...[
                _buildResumeCard(),
                const SizedBox(height: 16),
              ],
              if (_error != null) _buildErrorBanner(),
              _buildUploadSection(),
              if (_csvData != null) ...[
                const SizedBox(height: 16),
                _buildLoadedSummary(),
                const SizedBox(height: 16),
                OriginSelector(
                  mode: _originMode,
                  manualAddress: _manualAddress,
                  onModeChanged: (m) => setState(() => _originMode = m),
                  onAddressChanged: (a) => setState(() => _manualAddress = a),
                ),
                const SizedBox(height: 20),
                _buildValidateButton(),
                if (_hasEverValidated && _validationResult != null) ...[
                  const SizedBox(height: 12),
                  _buildValidationSummary(),
                ],
                const SizedBox(height: 24),
                _buildCalculateButton(),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Widgets de la UI
  // ═══════════════════════════════════════════

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset('assets/icon.png',
              width: 100, height: 100, fit: BoxFit.cover),
        ),
        const SizedBox(height: 14),
        const Text('Repartidor',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5)),
        const SizedBox(height: 4),
        const Text('Optimización de rutas de reparto',
            style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400)),
      ],
    );
  }

  Widget _buildResumeCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success, AppColors.success.withAlpha(200)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.success.withAlpha(60),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _resumeDelivery,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Continuar Ruta',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text(
                          'Tienes un reparto en curso. Toca para retomarlo.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!,
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: Icon(Icons.close, size: 18, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadSection() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _csvData != null ? AppColors.success : AppColors.border,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Icon(
              _csvData != null ? Icons.check_circle : Icons.upload_file,
              size: 48,
              color: _csvData != null ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _csvData != null
                  ? 'Archivo cargado'
                  : 'Toca para importar CSV',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _csvData != null
                    ? AppColors.success
                    : AppColors.textPrimary,
              ),
            ),
            if (_csvData == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Formato: .csv (cliente, direccion, ciudad)',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ),
            if (_csvData != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_fileName,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            if (_csvData != null)
              TextButton.icon(
                onPressed: _clearFile,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Cambiar archivo'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Text('$_totalPackages',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(width: 4),
          Text('paquetes',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Container(
              width: 1,
              height: 22,
              color: AppColors.primary.withAlpha(40)),
          const SizedBox(width: 12),
          Text('$_stopCount',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success)),
          const SizedBox(width: 4),
          Text('direcciones',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildValidateButton() {
    final label = _isValidating ? 'Validando...' : 'Validar direcciones';

    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _canValidate ? _validate : null,
        icon: _isValidating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.fact_check_outlined, size: 20),
        label: Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.warning,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.textSecondary.withAlpha(180),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildValidationSummary() {
    return GestureDetector(
      onTap: _allOk ? null : _showProblemsSheet,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _allOk ? AppColors.successSurface : AppColors.cardLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _allOk
                ? AppColors.success.withAlpha(150)
                : AppColors.border,
          ),
          boxShadow: [
            if (!_allOk)
              BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uniqueAddresses > 0
                    ? _okCount / _uniqueAddresses
                    : 0,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(
                  _allOk ? AppColors.success : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statusChip(Icons.check_circle, '$_okCount',
                    AppColors.success, 'OK'),
                if (_problemCount > 0)
                  _statusChip(Icons.error_outline, '$_problemCount',
                      AppColors.error, 'Sin resolver'),
                _statusChip(Icons.inventory_2, '$_totalPackages',
                    AppColors.primary, 'Paquetes'),
              ],
            ),
            if (!_allOk) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('Toca para situar las direcciones con problema',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
            if (_allOk) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text('Todas las direcciones validadas',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
      IconData icon, String count, Color color, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(count,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _buildCalculateButton() {
    final hasProblems = _problemCount > 0;
    final label = _isLoading
        ? 'Calculando ruta...'
        : hasProblems
            ? 'Calcular ruta ($_problemCount sin resolver)'
            : 'Calcular ruta óptima';

    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _canCalculate ? _calculateRoute : null,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.route, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              hasProblems ? AppColors.warning : AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.textSecondary.withAlpha(180),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Diálogo de progreso de VALIDACIÓN
// ═══════════════════════════════════════════

class _ValidationProgressDialog extends StatefulWidget {
  const _ValidationProgressDialog();

  @override
  State<_ValidationProgressDialog> createState() =>
      _ValidationProgressDialogState();
}

class _ValidationProgressDialogState
    extends State<_ValidationProgressDialog> {
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _elapsedSeconds++);
      return mounted;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔍', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text('Validando direcciones…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Geocodificando con Nominatim',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text('Tiempo: ${_formatTime(_elapsedSeconds)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.screen_lock_portrait,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text('No cierres la app',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Diálogo de progreso de CÁLCULO DE RUTA
// ═══════════════════════════════════════════

class _RouteProgressDialog extends StatefulWidget {
  final int totalAddresses;

  const _RouteProgressDialog({required this.totalAddresses});

  @override
  State<_RouteProgressDialog> createState() => _RouteProgressDialogState();
}

class _RouteProgressDialogState extends State<_RouteProgressDialog> {
  int _messageIndex = 0;
  int _elapsedSeconds = 0;

  static const _steps = [
    (Icons.upload_file, 'Enviando datos…', AppColors.primary),
    (Icons.route, 'Calculando distancias…', AppColors.success),
    (Icons.auto_fix_high, 'Optimizando ruta…', AppColors.warning),
    (Icons.hourglass_top, 'Casi listo…', AppColors.primary),
  ];

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return false;
      setState(() => _messageIndex = (_messageIndex + 1) % _steps.length);
      return mounted;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _elapsedSeconds++);
      return mounted;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_messageIndex];
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: step.$3.withAlpha(25),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(step.$1, size: 32, color: step.$3),
              ),
              const SizedBox(height: 20),
              Text(step.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('${widget.totalAddresses} direcciones',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(step.$3),
                ),
              ),
              const SizedBox(height: 16),
              Text('Tiempo: ${_formatTime(_elapsedSeconds)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.screen_lock_portrait,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text('No cierres la app',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Bottom Sheet: direcciones con problema
// ═══════════════════════════════════════════

class _ProblemsSheet extends StatelessWidget {
  final ValidationResponse validationResult;
  final void Function(StopValidationResult stop) onPinStop;

  const _ProblemsSheet({
    required this.validationResult,
    required this.onPinStop,
  });

  @override
  Widget build(BuildContext context) {
    final okStops =
        validationResult.stops.where((s) => s.isOk).toList();
    final problemStops =
        validationResult.stops.where((s) => s.isProblem).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.fact_check,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Resultado de validación',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.successSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${okStops.length} OK',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success)),
                  ),
                ],
              ),
            ),
            if (problemStops.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.error.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 14, color: AppColors.error),
                          const SizedBox(width: 4),
                          Text(
                              '${problemStops.length} Sin resolver',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (problemStops.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                          '⚠️  Direcciones sin resolver',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error)),
                    ),
                    ...problemStops
                        .map((s) => _problemTile(s, context)),
                    const SizedBox(height: 16),
                  ],
                  if (okStops.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                          '✅  Validadas (${okStops.length})',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success)),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.successSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        okStops.length <= 5
                            ? okStops
                                .map((s) =>
                                    '${s.address} (${s.packageCount} paq.)')
                                .join('\n')
                            : '${okStops.length} direcciones validadas correctamente.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.success),
                      ),
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.done_all, size: 20),
                    label: const Text('Cerrar',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _problemTile(StopValidationResult stop, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_off, size: 16, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(stop.address,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${stop.packageCount} paquete${stop.packageCount > 1 ? 's' : ''}',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                if (stop.reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(stop.reason,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onPinStop(stop);
              },
              icon: const Icon(Icons.add_location_alt, size: 14),
              label: const Text('Situar en el mapa',
                  style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
