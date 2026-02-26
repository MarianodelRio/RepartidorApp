import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';
import '../models/validation_models.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/persistence_service.dart';
import '../widgets/origin_selector.dart';
import 'map_picker_screen.dart';
import 'result_screen.dart';

// ═══════════════════════════════════════════
//  Pantalla de revisión de validación
//
//  Flujo:
//    1. Muestra todas las paradas geocodificadas en el mapa con pins de color
//    2. Lista las paradas fallidas con botón "Situar" (→ MapPickerScreen)
//    3. Al situar un pin, se registra en el backend y se actualiza el mapa
//    4. OriginSelector + botón "Calcular ruta" inician la optimización
// ═══════════════════════════════════════════

class ValidationReviewScreen extends StatefulWidget {
  final ValidationResult validationResult;

  const ValidationReviewScreen({super.key, required this.validationResult});

  @override
  State<ValidationReviewScreen> createState() => _ValidationReviewScreenState();
}

class _ValidationReviewScreenState extends State<ValidationReviewScreen> {
  late ValidationResult _result;
  final _mapController = MapController();

  OriginMode _originMode = OriginMode.defaultAddress;
  String _manualAddress = '';
  bool _isLoading = false;
  String? _error;

  static const _defaultCenter = LatLng(37.805503, -5.099805); // Posadas

  @override
  void initState() {
    super.initState();
    _result = widget.validationResult;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMapToStops());
  }

  void _fitMapToStops() {
    if (_result.geocoded.isEmpty) return;
    final points = _result.geocoded.map((s) => LatLng(s.lat, s.lon)).toList();
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

  // ── Pin manual ──────────────────────────────────────────────────────────────

  Future<void> _pinStop(FailedStop stop) async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(address: stop.address),
      ),
    );
    if (result != null) {
      _applyPin(stop, result.latitude, result.longitude);
    }
  }

  void _applyPin(FailedStop stop, double lat, double lon) {
    // Persistir en caché permanente del backend (fire-and-forget)
    ApiService.postOverride(address: stop.address, lat: lat, lon: lon);

    final newGeocoded = GeocodedStop(
      address: stop.address,
      clientName: stop.clientNames.firstWhere((n) => n.isNotEmpty, orElse: () => ''),
      allClientNames: stop.clientNames,
      packages: stop.packages,
      packageCount: stop.packageCount,
      lat: lat,
      lon: lon,
      confidence: GeoConfidence.override,
    );

    setState(() {
      _result = ValidationResult(
        geocoded: [..._result.geocoded, newGeocoded],
        failed: _result.failed.where((f) => f.address != stop.address).toList(),
        totalPackages: _result.totalPackages,
        uniqueAddresses: _result.uniqueAddresses,
      );
    });

    // Desplazar mapa al nuevo pin
    _mapController.move(LatLng(lat, lon), 16);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pin guardado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ── Calcular ruta ───────────────────────────────────────────────────────────

  Future<void> _calculateRoute() async {
    final failedCount = _result.failed.length;
    if (failedCount > 0) {
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
        if (mounted) setState(() { _isLoading = false; _error = 'Error GPS: $e'; });
        return;
      }
    }

    WakelockPlus.enable();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RouteProgressDialog(totalAddresses: _result.geocoded.length),
    );

    try {
      final geocoded = _result.geocoded;
      if (geocoded.isEmpty) throw Exception('No hay paradas válidas para calcular la ruta');

      final optimizeAddresses = <String>[];
      final optimizeClientNames = <String>[];
      final preResolvedCoords = <List<double>?>[];
      final packageCounts = <int>[];
      final packagesPerStop = <List<Package>>[];

      for (final st in geocoded) {
        optimizeAddresses.add(st.address);
        optimizeClientNames.add(st.clientName);
        preResolvedCoords.add([st.lat, st.lon]);
        packageCounts.add(st.packageCount);
        packagesPerStop.add(st.packages);
      }

      final result = await ApiService.optimize(
        addresses: optimizeAddresses,
        clientNames: optimizeClientNames,
        startAddress: startAddress,
        coords: preResolvedCoords,
        packageCounts: packageCounts,
        packagesPerStop: packagesPerStop,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar diálogo
      PersistenceService.clearValidationState();

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(response: result)),
      );
    } on ApiException catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) setState(() => _error = e.toString());
    } finally {
      WakelockPlus.disable();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showUnresolvedConfirmation() async {
    final failed = _result.failed;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
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
                'Hay ${failed.length} dirección${failed.length > 1 ? 'es' : ''} '
                'sin coordenadas.\n\n'
                'Usa "Situar" para resolverlas antes de calcular.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textPrimary, height: 1.4),
              ),
            ),
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

  // ── Color por nivel de confianza ────────────────────────────────────────────

  Color _markerColor(GeoConfidence confidence) {
    switch (confidence) {
      case GeoConfidence.exactAddress:
        return AppColors.success;            // verde
      case GeoConfidence.good:
        return AppColors.successLight;       // verde claro
      case GeoConfidence.exactPlace:
        return const Color(0xFF1565C0);      // azul
      case GeoConfidence.override:
        return const Color(0xFF6A1B9A);      // morado
      case GeoConfidence.failed:
        return AppColors.error;
    }
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mapa (pantalla completa)
          _buildMap(),

          // AppBar flotante
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildAppBar(context),
          ),

          // Panel inferior
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final geocodedCount = _result.geocoded.length;
    final failedCount = _result.failed.length;
    return Container(
      color: AppColors.primary,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Revisar direcciones',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(
                  '$geocodedCount geocodificadas  •  '
                  '${failedCount > 0 ? '$failedCount sin resolver' : 'Todas OK'}',
                  style: TextStyle(
                      color: failedCount > 0
                          ? Colors.orange[200]
                          : Colors.white70,
                      fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen, color: Colors.white),
            tooltip: 'Centrar mapa',
            onPressed: _fitMapToStops,
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final markers = _result.geocoded.map((stop) {
      final color = _markerColor(stop.confidence);
      return Marker(
        point: LatLng(stop.lat, stop.lon),
        width: 36,
        height: 44,
        alignment: Alignment.topCenter,
        child: Tooltip(
          message: '${stop.address}${stop.clientName.isNotEmpty ? '\n${stop.clientName}' : ''}',
          child: Icon(Icons.location_pin, color: color, size: 36),
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
          userAgentPackageName: 'com.example.flutter_app',
        ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    final failed = _result.failed;
    final hasFailed = failed.isNotEmpty;
    final canCalculate = !_isLoading && _result.geocoded.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.50,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Contenido scrollable
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Error banner
                  if (_error != null) ...[
                    _buildErrorBanner(),
                    const SizedBox(height: 12),
                  ],

                  // Resumen numérico
                  _buildSummary(),
                  const SizedBox(height: 8),

                  // Leyenda de colores
                  _buildLegend(),

                  // Lista de paradas fallidas
                  if (hasFailed) ...[
                    const SizedBox(height: 12),
                    _buildFailedList(failed),
                  ],

                  const SizedBox(height: 12),

                  // Selector de origen
                  OriginSelector(
                    mode: _originMode,
                    manualAddress: _manualAddress,
                    onModeChanged: (m) => setState(() => _originMode = m),
                    onAddressChanged: (a) => setState(() => _manualAddress = a),
                  ),

                  const SizedBox(height: 16),

                  // Botón calcular
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: canCalculate ? _calculateRoute : null,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.route, size: 22),
                      label: Text(
                        _isLoading
                            ? 'Calculando...'
                            : hasFailed
                                ? 'Calcular ruta (${failed.length} sin resolver)'
                                : 'Calcular ruta óptima',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            hasFailed ? AppColors.warning : AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.textSecondary.withAlpha(180),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
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

  Widget _buildSummary() {
    return Row(
      children: [
        _SummaryChip(
          count: _result.geocoded.length,
          label: 'geocodificadas',
          color: AppColors.success,
        ),
        const SizedBox(width: 8),
        _SummaryChip(
          count: _result.failed.length,
          label: 'sin resolver',
          color: _result.failed.isEmpty ? AppColors.textTertiary : AppColors.error,
        ),
        const SizedBox(width: 8),
        _SummaryChip(
          count: _result.totalPackages,
          label: 'paquetes',
          color: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: const [
        _LegendItem(color: AppColors.success, label: 'Exacto'),
        _LegendItem(color: AppColors.successLight, label: 'Bueno'),
        _LegendItem(color: Color(0xFF1565C0), label: 'Lugar'),
        _LegendItem(color: Color(0xFF6A1B9A), label: 'Manual'),
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
                Text(
                  stop.address,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
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
}

// ── Chip de resumen numérico ─────────────────────────────────────────────────

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
          Text(
            '$count',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ── Item de leyenda ──────────────────────────────────────────────────────────

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

// ── Diálogo de progreso de cálculo de ruta ───────────────────────────────────

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
