import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:typed_data';

import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../controllers/import_controller.dart';
import '../models/csv_data.dart';
import '../models/origin_mode.dart';
import '../models/validation_models.dart';
import '../services/api_service.dart';
import '../services/csv_service.dart';
import '../services/persistence_service.dart';
import '../widgets/origin_selector.dart';
import 'delivery_screen.dart';
import 'map_picker_screen.dart';
import 'result_screen.dart';

// ═══════════════════════════════════════════
//  Pantalla de importación + revisión de validación
//
//  Flujo en una sola pantalla:
//    1. Subir CSV (cliente, direccion, ciudad[, nota, alias])
//    2. Validación automática → transforma el body en mapa + panel
//    3. Pin manual de fallidas + calcular ruta
// ═══════════════════════════════════════════

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // ── Controller ──
  late final ImportController _ctrl;

  // ── Estado general ──
  String? _error;

  // ── Mapa de revisión (UI pura) ──
  final _mapController = MapController();
  final _mapSectionKey = GlobalKey();

  static const _defaultCenter = LatLng(37.805503, -5.099805);

  @override
  void initState() {
    super.initState();
    _ctrl = ImportController();
    _ctrl.checkServer();
    _ctrl.checkActiveSession();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  Servidor / Sesión
  // ═══════════════════════════════════════════

  Future<void> _resumeDelivery() async {
    final session = await PersistenceService.loadSession();
    if (session == null || !mounted) return;
    Navigator.of(context)
        .push(
            MaterialPageRoute(builder: (_) => DeliveryScreen(session: session)))
        .then((_) => _ctrl.checkActiveSession());
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

      // Si hay reparto en curso, descartarlo al iniciar uno nuevo.
      if (_ctrl.hasActiveSession) {
        await _ctrl.discardSession();
      }

      if (!mounted) return;
      _ctrl.loadCsvData(csvData, file.name);
      setState(() => _error = null);

      await _validate();
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error al seleccionar archivo: $e');
    }
  }

  void _clearFile() {
    _ctrl.clearCsvData(); // limpia CSV, validación, origen y error de ruta
    setState(() => _error = null);
  }

  // ═══════════════════════════════════════════
  //  Validación automática
  // ═══════════════════════════════════════════

  Future<void> _validate() async {
    if (_ctrl.csvData == null) return;

    if (!_ctrl.serverOnline) {
      await _ctrl.checkServer();
      if (!_ctrl.serverOnline) {
        _showError(
            'El servidor no está disponible. Verifica que el backend está activo en ${ApiConfig.baseUrl}');
        return;
      }
    }

    setState(() => _error = null);
    WakelockPlus.enable();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ValidationProgressDialog(),
    );

    try {
      await _ctrl.startValidation();
      if (!mounted) return;
      Navigator.of(context).pop();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitMapToStops();
        final ctx = _mapSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
          );
        }
      });
    } on ApiException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e.message);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError('Error de validación: $e');
    } finally {
      WakelockPlus.disable();
    }
  }

  // ═══════════════════════════════════════════
  //  Revisión: mapa + pines
  // ═══════════════════════════════════════════

  void _fitMapToStops() {
    final geocoded = _ctrl.reviewResult?.geocoded ?? [];
    if (geocoded.isEmpty) return;
    final points = geocoded.map((s) => LatLng(s.lat, s.lon)).toList();
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  Future<void> _pinStop(FailedStop stop) async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(address: stop.address),
      ),
    );
    if (result != null) _applyPin(stop, result.latitude, result.longitude);
  }

  void _applyPin(FailedStop stop, double lat, double lon) {
    _ctrl.applyPin(stop, lat, lon);
    _mapController.move(LatLng(lat, lon), 16);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pin guardado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _repinGeocodedStop(GeocodedStop stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_location_alt, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text('Cambiar ubicación',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          stop.alias.isNotEmpty
              ? '${stop.address}  —  ${stop.alias}'
              : stop.address,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.edit_location_alt, size: 18),
            label: const Text('Continuar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapPickerScreen(address: stop.address)),
    );
    if (result != null) {
      _applyRepinGeocoded(stop, result.latitude, result.longitude);
    }
  }

  void _applyRepinGeocoded(GeocodedStop stop, double lat, double lon) {
    _ctrl.applyRepinGeocoded(stop, lat, lon);
    _mapController.move(LatLng(lat, lon), 16);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación actualizada manualmente'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════
  //  Calcular ruta
  // ═══════════════════════════════════════════

  Future<void> _calculateRoute() async {
    WakelockPlus.enable();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RouteProgressDialog(
          totalAddresses: _ctrl.reviewResult!.geocoded.length),
    );

    try {
      final result = await _ctrl.calculateRoute();
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(response: result)),
      );
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      // _ctrl.routeError ya contiene el mensaje; ListenableBuilder rerenderiza.
    } finally {
      WakelockPlus.disable();
    }
  }

  Color _markerColor(GeoConfidence confidence) {
    return confidence == GeoConfidence.override
        ? const Color(0xFF7B1FA2) // morado = ubicación manual
        : AppColors.success;     // verde  = geocodificación automática
  }

  // ═══════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final result = _ctrl.reviewResult;
    final hasFailed = result != null && result.failed.isNotEmpty;
    final canCalculate =
        result != null && !_ctrl.isCalculating && result.geocoded.isNotEmpty && !hasFailed;

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
            child: _ctrl.isCheckingServer
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : GestureDetector(
                    onTap: _ctrl.checkServer,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle,
                            size: 10,
                            color: _ctrl.serverOnline
                                ? AppColors.success
                                : AppColors.error),
                        const SizedBox(width: 4),
                        Text(_ctrl.serverOnline ? 'Online' : 'Offline',
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
              if (_ctrl.hasActiveSession) ...[
                _buildResumeCard(),
                const SizedBox(height: 16),
              ],
              if (_error != null) _buildErrorBanner(),
              _buildUploadSection(),

              // ── Resultados de validación (aparecen bajo la zona de carga) ──
              if (result != null) ...[
                const SizedBox(height: 20),

                // Mapa con altura fija y botón de centrar en esquina
                ClipRRect(
                  key: _mapSectionKey,
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.38,
                    child: Stack(
                      children: [
                        _buildReviewMap(),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            elevation: 3,
                            child: InkWell(
                              onTap: _fitMapToStops,
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.fit_screen,
                                    size: 20, color: AppColors.primary),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Error de cálculo
                if (_ctrl.routeError != null) ...[
                  _buildReviewErrorBanner(),
                  const SizedBox(height: 12),
                ],

                // Leyenda justo bajo el mapa
                _buildLegend(),
                const SizedBox(height: 10),

                // Resumen centrado
                _buildReviewSummary(),

                // Paradas fallidas
                if (hasFailed) ...[
                  const SizedBox(height: 12),
                  _buildFailedList(result.failed),
                ],

                const SizedBox(height: 16),

                // Selector de origen
                OriginSelector(
                  mode: _ctrl.originMode,
                  manualAddress: _ctrl.manualAddress,
                  onModeChanged: _ctrl.setOriginMode,
                  onAddressChanged: _ctrl.setManualAddress,
                ),

                const SizedBox(height: 16),

                // Botón calcular ruta
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: canCalculate ? _calculateRoute : null,
                    icon: _ctrl.isCalculating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.route, size: 22),
                    label: Text(
                      _ctrl.isCalculating ? 'Calculando...' : 'Calcular ruta óptima',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.textSecondary.withAlpha(180),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Widgets fase de revisión
  // ═══════════════════════════════════════════

  Widget _buildReviewMap() {
    final markers = _ctrl.reviewResult!.geocoded.map((stop) {
      final color = _markerColor(stop.confidence);
      return Marker(
        point: LatLng(stop.lat, stop.lon),
        width: 36,
        height: 44,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => _repinGeocodedStop(stop),
          child: Tooltip(
            message: stop.alias.isNotEmpty
                ? '${stop.address}  —  ${stop.alias}'
                : stop.address,
            child: Icon(Icons.location_pin, color: color, size: 36),
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.posadas.repartir_app',
        ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildReviewErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_ctrl.routeError!,
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: _ctrl.clearRouteError,
            child: Icon(Icons.close, size: 18, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewSummary() {
    final geocoded = _ctrl.reviewResult!.geocoded.length;
    final packages = _ctrl.reviewResult!.totalPackages;
    final failed = _ctrl.reviewResult!.failed.length;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          _SummaryChip(
            count: geocoded,
            label: 'direcciones',
            color: AppColors.success,
          ),
          _SummaryChip(
            count: packages,
            label: 'paquetes',
            color: AppColors.primary,
          ),
          if (failed > 0)
            _SummaryChip(
              count: failed,
              label: 'sin resolver',
              color: AppColors.error,
            ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return const Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(color: AppColors.success, label: 'Automático'),
        _LegendItem(color: Color(0xFF7B1FA2), label: 'Manual'),
      ],
    );
  }

  Widget _buildFailedList(List<FailedStop> failed) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.location_off, size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Text(
                  '${failed.length} dirección${failed.length > 1 ? 'es' : ''} sin geocodificar',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...failed.map((stop) => _buildFailedTile(stop)),
        ],
      ),
    );
  }

  Widget _buildFailedTile(FailedStop stop) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    children: [
                      TextSpan(text: stop.address),
                      if (stop.alias.isNotEmpty)
                        TextSpan(
                          text: '  —  ${stop.alias}',
                          style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w400,
                              color: AppColors.primary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stop.packageCount} paquete${stop.packageCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: () => _pinStop(stop),
              icon: const Icon(Icons.add_location_alt, size: 14),
              label: const Text('Situar', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Widgets fase de carga (upload)
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
      child: Stack(
        children: [
          Material(
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
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
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
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: _ctrl.discardSession,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
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
    final hasCsv = _ctrl.csvData != null;
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasCsv ? AppColors.success : AppColors.border,
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
              hasCsv ? Icons.check_circle : Icons.upload_file,
              size: 36,
              color: hasCsv ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              hasCsv ? 'Archivo cargado' : 'Toca para importar CSV',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hasCsv ? AppColors.success : AppColors.textPrimary,
              ),
            ),
            if (!hasCsv)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Formato: .csv (cliente, direccion, ciudad, nota, agencia, alias)',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ),
            if (hasCsv)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_ctrl.fileName,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            if (hasCsv)
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
              Text('Geocodificando… puede tardar varios minutos',
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
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
//  Widgets auxiliares de revisión
// ═══════════════════════════════════════════

class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _SummaryChip(
      {required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_pin, color: color, size: 14),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
