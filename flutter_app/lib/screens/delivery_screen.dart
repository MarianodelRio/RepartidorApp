import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/delivery_state.dart';
import '../models/route_models.dart';
import '../services/api_service.dart';
import '../services/persistence_service.dart';
import '../widgets/route_map.dart';

/// Pantalla de ejecución de reparto.
///
/// Muestra el mapa con el camino dinámico GPS → siguiente parada,
/// la tarjeta de "Siguiente Parada" y botones de acción.
class DeliveryScreen extends StatefulWidget {
  final DeliverySession session;

  const DeliveryScreen({super.key, required this.session});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final GlobalKey<RouteMapState> _mapKey = GlobalKey<RouteMapState>();
  late DeliverySession _session;

  /// Geometría del segmento GPS → siguiente parada.
  Map<String, dynamic>? _segmentGeometry;

  @override
  void initState() {
    super.initState();
    _session = widget.session;

    // Centrar en la primera parada pendiente y pedir segmento desde GPS real
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_session.currentStop != null) {
        _fetchSegmentFromGps();
        // Encuadrar GPS + destino con un pequeño delay para que el mapa tenga GPS
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _mapKey.currentState?.fitGpsAndNextStop();
        });
      }
    });
  }

  // ═══════════════════════════════════════════
  //  Segmento dinámico GPS → Siguiente Parada
  // ═══════════════════════════════════════════

  /// Obtiene la posición GPS actual del dispositivo.
  /// Primero intenta desde el mapa (ya en streaming), si no,
  /// solicita directamente a Geolocator.
  Future<Position?> _getCurrentGps() async {
    // Intentar desde el mapa (ya tiene stream activo)
    final mapPos = _mapKey.currentState?.currentPosition;
    if (mapPos != null) {
      return Position(
        latitude: mapPos.latitude,
        longitude: mapPos.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }

    // Solicitar directamente
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Solicita al backend el camino OSRM **siempre desde la posición GPS real**
  /// hasta la siguiente parada pendiente. Si GPS no disponible tras reintentos,
  /// usa la parada anterior como fallback.
  /// Para paradas sin geocodificar, no se calcula segmento.
  Future<void> _fetchSegmentFromGps() async {
    final currentStop = _session.currentStop;
    if (currentStop == null) {
      setState(() => _segmentGeometry = null);
      return;
    }

    // Si la parada no tiene ubicación real, no pedir segmento
    if (currentStop.geocodeFailed) {
      setState(() => _segmentGeometry = null);
      return;
    }

    // Punto de destino: la siguiente parada
    final destLat = currentStop.lat;
    final destLon = currentStop.lon;

    // Punto de origen: siempre GPS real
    double originLat;
    double originLon;

    // Intentar obtener GPS (con reintento si el mapa aún no tiene posición)
    Position? gps = await _getCurrentGps();

    // Si no se obtuvo en el primer intento, esperar un poco y reintentar
    if (gps == null) {
      await Future.delayed(const Duration(seconds: 2));
      gps = await _getCurrentGps();
    }

    if (gps != null) {
      originLat = gps.latitude;
      originLon = gps.longitude;
    } else {
      // Fallback: usar la parada anterior completada
      final prevIdx = _session.currentStopIndex - 1;
      if (prevIdx >= 0 && prevIdx < _session.stops.length) {
        originLat = _session.stops[prevIdx].lat;
        originLon = _session.stops[prevIdx].lon;
      } else if (_session.stops.isNotEmpty) {
        originLat = _session.stops[0].lat;
        originLon = _session.stops[0].lon;
      } else {
        return;
      }
    }

    final geo = await ApiService.getRouteSegment(
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
    );

    if (mounted) {
      setState(() => _segmentGeometry = geo);
    }
  }

  // ═══════════════════════════════════════════
  //  Acciones de parada
  // ═══════════════════════════════════════════

  /// Marca la parada actual con un estado (un solo toque).
  Future<void> _markStop(StopStatus status, {String? note}) async {
    final stopIndex = _session.currentStopIndex;
    if (stopIndex >= _session.stops.length) return;

    await PersistenceService.updateStopStatus(
      _session,
      stopIndex,
      status,
      note: note,
    );

    setState(() {});

    if (_session.isFinished) {
      // Borrar segmento al terminar
      setState(() => _segmentGeometry = null);
      if (mounted) _showFinishedDialog();
    } else {
      // Encuadrar GPS + siguiente destino y recalcular segmento
      _fetchSegmentFromGps();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _mapKey.currentState?.fitGpsAndNextStop();
      });
    }
  }

  /// Muestra el diálogo para incidencias (con campo de texto).
  void _showIncidentDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.error),
            SizedBox(width: 8),
            Text('Registrar Incidencia',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Describe la incidencia...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            filled: true,
            fillColor: AppColors.scaffoldLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markStop(StopStatus.incident,
                  note: controller.text.trim().isEmpty
                      ? 'Sin detalle'
                      : controller.text.trim());
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  /// Diálogo final cuando se completó todo el reparto.
  void _showFinishedDialog() {
    final elapsed = DateTime.now().difference(_session.createdAt);
    final elapsedText = elapsed.inMinutes < 60
        ? '${elapsed.inMinutes} min'
        : '${elapsed.inHours} h ${elapsed.inMinutes % 60} min';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎉 ¡Reparto Completado!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 64),
            const SizedBox(height: 16),
            _summaryRow('✅ Entregados', '${_session.deliveredCount}'),
            _summaryRow('🚫 Ausentes', '${_session.absentCount}'),
            _summaryRow('⚠️ Incidencias', '${_session.incidentCount}'),
            const Divider(height: 24),
            _summaryRow(
                '📦 Total', '${_session.completedCount}/${_session.totalStops}'),
            if (_session.totalPackages > _session.totalStops)
              _summaryRow('📦 Paquetes', '${_session.totalPackages}'),
            _summaryRow('⏱️ Duración', elapsedText),
            _summaryRow('📏 Distancia', _session.totalDistanceDisplay),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                await PersistenceService.clearSession();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                nav.popUntil((route) => route.isFirst);
              },
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: const Text('Cerrar Sesión y Limpiar'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Navegación externa (Google Maps)
  // ═══════════════════════════════════════════

  Future<void> _openExternalNavigation() async {
    final stop = _session.currentStop;
    if (stop == null) return;

    // Intent de Google Maps con coordenadas
    final uri = Uri.parse(
      'google.navigation:q=${stop.lat},${stop.lon}&mode=d',
    );

    // Fallback: abrir en navegador con Google Maps URL
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${stop.lat},${stop.lon}&travelmode=driving',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la navegación')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════
  //  Confirmar abandono de reparto
  // ═══════════════════════════════════════════

  Future<bool> _onWillPop() async {
    if (_session.isFinished) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Salir del reparto?'),
        content: const Text(
          'El progreso se guarda automáticamente. '
          'Podrás continuar desde donde lo dejaste.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  // ═══════════════════════════════════════════
  //  Drag & Drop reordenar paradas pendientes
  // ═══════════════════════════════════════════

  void _showReorderSheet() {
    // Construir lista de paradas pendientes (sin origen)
    final pendingEntries = <_ReorderEntry>[];
    for (int i = 0; i < _session.stops.length; i++) {
      final s = _session.stops[i];
      if (s.isPending && !s.isOrigin) {
        pendingEntries.add(_ReorderEntry(index: i, stop: s));
      }
    }

    if (pendingEntries.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.85,
              minChildSize: 0.35,
              builder: (ctx, scrollController) => Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_vert, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reordenar Paradas',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Mantén pulsado y arrastra para cambiar el orden.',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollController: scrollController,
                      itemCount: pendingEntries.length,
                      onReorder: (oldIdx, newIdx) {
                        setSheetState(() {
                          if (newIdx > oldIdx) newIdx--;
                          final item = pendingEntries.removeAt(oldIdx);
                          pendingEntries.insert(newIdx, item);
                        });
                      },
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          elevation: 4,
                          shadowColor: AppColors.primary.withAlpha(40),
                          borderRadius: BorderRadius.circular(10),
                          child: child,
                        );
                      },
                      itemBuilder: (ctx, i) {
                        final entry = pendingEntries[i];
                        return Container(
                          key: ValueKey(entry.index),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.cardLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.border),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: entry.stop.geocodeFailed
                                    ? AppColors.warning
                                    : AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: entry.stop.geocodeFailed
                                    ? const Icon(Icons.warning_amber_rounded,
                                        color: Colors.white, size: 18)
                                    : Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ),
                            title: Text(
                              entry.stop.clientName.isNotEmpty
                                  ? entry.stop.clientName
                                  : entry.stop.label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: entry.stop.geocodeFailed
                                      ? AppColors.warning
                                      : AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              entry.stop.geocodeFailed
                                  ? '⚠ Sin ubicación — ${entry.stop.address}'
                                  : '${entry.stop.address}${entry.stop.hasMultiplePackages ? '  📦×${entry.stop.packageCount}' : ''}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Icon(Icons.drag_handle,
                                color: AppColors.border),
                          ),
                        );
                      },
                    ),
                  ),
                  // Botón aplicar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await _applyReorder(pendingEntries);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('Aplicar nuevo orden',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Aplica el nuevo orden de paradas pendientes a la sesión.
  Future<void> _applyReorder(List<_ReorderEntry> newOrder) async {
    // Reconstruir la lista de stops:
    // 1. Mantener completadas y origen en su posición relativa
    // 2. Insertar pendientes en el nuevo orden después de la última completada

    final origin = _session.stops.where((s) => s.isOrigin).toList();
    final completed =
        _session.stops.where((s) => !s.isOrigin && s.isCompleted).toList();
    final reorderedPending = newOrder.map((e) => e.stop).toList();

    final newStops = <DeliveryStop>[
      ...origin,
      ...completed,
      ...reorderedPending,
    ];

    _session.stops
      ..clear()
      ..addAll(newStops);

    // Actualizar currentStopIndex al primer pendiente
    for (int i = 0; i < _session.stops.length; i++) {
      if (_session.stops[i].isPending && !_session.stops[i].isOrigin) {
        _session.currentStopIndex = i;
        break;
      }
    }

    await PersistenceService.saveSession(_session);
    setState(() {});

    // Centrar mapa en la nueva parada actual
    if (_session.currentStop != null) {
      _fetchSegmentFromGps();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _mapKey.currentState?.fitGpsAndNextStop();
      });
    }
  }

  // ═══════════════════════════════════════════
  //  Lista de paradas completadas
  // ═══════════════════════════════════════════

  void _showCompletedStops() {
    final completed = _session.stops.where((s) => s.isCompleted).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (ctx, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.checklist, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Completadas (${completed.length})',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: completed.isEmpty
                  ? const Center(
                      child: Text('Ninguna parada completada aún',
                          style: TextStyle(color: AppColors.textTertiary)),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: completed.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (ctx, i) =>
                          _CompletedTile(stop: completed[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Build principal
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final currentStop = _session.currentStop;
    final isFinished = _session.isFinished;

    // Convertir DeliveryStops a StopInfo para el mapa
    final mapStops = _session.stops;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffoldLight,
        appBar: AppBar(
          title: const Text('En Reparto'),
          centerTitle: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // Botón reordenar paradas pendientes
            if (!isFinished)
              IconButton(
                onPressed: _showReorderSheet,
                icon: const Icon(Icons.swap_vert),
                tooltip: 'Reordenar paradas',
              ),
            // Botón completados
            IconButton(
              onPressed: _showCompletedStops,
              icon: Badge(
                label: Text('${_session.completedCount}'),
                isLabelVisible: _session.completedCount > 0,
                child: const Icon(Icons.checklist),
              ),
              tooltip: 'Paradas completadas',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── Barra de progreso ──
              _ProgressHeader(session: _session),

              // ── Mapa (modo reparto: solo segmento GPS → siguiente parada) ──
              Expanded(
                child: RouteMap(
                  key: _mapKey,
                  stops: _deliveryToStopInfo(mapStops),
                  geometry: _session.geometry,
                  highlightedStopIndex:
                      isFinished ? null : _session.currentStopIndex,
                  completedIndices: _completedIndices(),
                  deliveryMode: true,
                  segmentGeometry: _segmentGeometry,
                  nextStopIndex:
                      isFinished ? null : _session.currentStopIndex,
                ),
              ),

              // ── Tarjeta de siguiente parada + acciones ──
              if (!isFinished && currentStop != null)
                _NextStopCard(
                  stop: currentStop,
                  pendingCount: _session.pendingCount,
                  onDelivered: () => _markStop(StopStatus.delivered),
                  onAbsent: () => _markStop(StopStatus.absent),
                  onIncident: _showIncidentDialog,
                  onNavigate: _openExternalNavigation,
                ),

              if (isFinished) _buildFinishedBanner(),
            ],
          ),
        ),
      ),
    );
  }

  /// Convertir DeliveryStop a StopInfo para compatibilidad con RouteMap.
  List<StopInfo> _deliveryToStopInfo(List<DeliveryStop> stops) {
    return stops
        .map((s) => StopInfo(
              order: s.order,
              address: s.address,
              label: s.label,
              clientName: s.clientName,
              clientNames: s.clientNames,
              type: s.type,
              lat: s.lat,
              lon: s.lon,
              distanceMeters: s.distanceMeters,
              geocodeFailed: s.geocodeFailed,
              packageCount: s.packageCount,
            ))
        .toList();
  }

  /// Índices de paradas completadas para visualizarlas diferente en el mapa.
  Set<int> _completedIndices() {
    final indices = <int>{};
    for (int i = 0; i < _session.stops.length; i++) {
      if (_session.stops[i].isCompleted) indices.add(i);
    }
    return indices;
  }

  Widget _buildFinishedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: AppColors.successSurface,
      child: Column(
        children: [
          const Text(
            '🎉 ¡Reparto completado!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '✅ ${_session.deliveredCount}  ·  🚫 ${_session.absentCount}  ·  ⚠️ ${_session.incidentCount}',
            style: const TextStyle(fontSize: 13, color: AppColors.success),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await PersistenceService.clearSession();
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            icon: const Icon(Icons.cleaning_services, size: 18),
            label: const Text('Cerrar Sesión y Limpiar'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Sub-widgets
// ═══════════════════════════════════════════

/// Barra de progreso del reparto.
class _ProgressHeader extends StatelessWidget {
  final DeliverySession session;

  const _ProgressHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${session.completedCount} de ${session.totalStops} entregas'
                '${session.totalPackages > session.totalStops ? ' (${session.totalPackages} 📦)' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
              Row(
                children: [
                  _miniChip('✅', '${session.deliveredCount}',
                      AppColors.delivered),
                  const SizedBox(width: 6),
                  _miniChip('🚫', '${session.absentCount}',
                      AppColors.absent),
                  const SizedBox(width: 6),
                  _miniChip('⚠️', '${session.incidentCount}',
                      AppColors.incident),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: session.progress,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String emoji, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$emoji $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Tarjeta de "Siguiente Parada" con botones de acción.
///
/// Filosofía "Un solo toque": Entregado y No estaba son un solo tap.
class _NextStopCard extends StatelessWidget {
  final DeliveryStop stop;
  final int pendingCount;
  final VoidCallback onDelivered;
  final VoidCallback onAbsent;
  final VoidCallback onIncident;
  final VoidCallback onNavigate;

  const _NextStopCard({
    required this.stop,
    required this.pendingCount,
    required this.onDelivered,
    required this.onAbsent,
    required this.onIncident,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Cabecera: Siguiente parada ──
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: stop.geocodeFailed
                          ? AppColors.warning
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: stop.geocodeFailed
                          ? const Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 24)
                          : Text(
                              '${stop.order}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              stop.geocodeFailed
                                  ? 'SIN UBICACIÓN EN MAPA'
                                  : 'SIGUIENTE PARADA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: stop.geocodeFailed
                                    ? AppColors.warning
                                    : AppColors.primary,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '· $pendingCount restantes',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          stop.clientName.isNotEmpty
                              ? stop.clientName
                              : stop.label,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,  // Negrita Azul Profundo
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stop.address,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (stop.hasMultiplePackages)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withAlpha(25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.warning, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.inventory_2,
                                        size: 13, color: AppColors.warning),
                                    const SizedBox(width: 3),
                                    Text(
                                      '×${stop.packageCount}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.warning,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        // Show all client names when there are multiple packages
                        if (stop.hasMultiplePackages && stop.clientNames.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '👥 ${stop.clientNames.join(', ')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Botón de navegación externa ──
                  Material(
                    color: AppColors.primarySurface,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.hardEdge,
                    child: InkWell(
                      onTap: onNavigate,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.navigation,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Botones de acción (sólidos, grandes) ──
              Row(
                children: [
                  // ✅ Entregado — el principal, grande y verde esmeralda
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: onDelivered,
                        icon: const Icon(Icons.check_circle, size: 24, color: Colors.white),
                        label: const Text('Entregado',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 🚫 No estaba — Botón sólido ámbar
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: onAbsent,
                        icon: const Icon(Icons.person_off, size: 20, color: Colors.white),
                        label: const Text('Ausente',
                            style: TextStyle(fontSize: 14, color: Colors.white)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // ⚠️ Incidencia — Botón sólido rojo
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: FilledButton(
                      onPressed: onIncident,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Icon(Icons.warning_amber, size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile de una parada completada en el bottom sheet.
class _CompletedTile extends StatelessWidget {
  final DeliveryStop stop;

  const _CompletedTile({required this.stop});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;

    switch (stop.status) {
      case StopStatus.delivered:
        statusColor = AppColors.delivered;
        statusIcon = Icons.check_circle;
      case StopStatus.absent:
        statusColor = AppColors.absent;
        statusIcon = Icons.person_off;
      case StopStatus.incident:
        statusColor = AppColors.incident;
        statusIcon = Icons.warning_amber;
      case StopStatus.pending:
        statusColor = AppColors.textTertiary;
        statusIcon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withAlpha(60)),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: statusColor.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(statusIcon, size: 18, color: statusColor),
        ),
        title: Text(
          '${stop.order}. ${stop.clientName.isNotEmpty ? stop.clientName : stop.label}'
          '${stop.hasMultiplePackages ? '  📦×${stop.packageCount}' : ''}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${stop.status.emoji} ${stop.status.label}',
              style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600),
            ),
            if (stop.note != null && stop.note!.isNotEmpty)
              Text(
                '📝 ${stop.note}',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: stop.completedAt != null
            ? Text(
                '${stop.completedAt!.hour.toString().padLeft(2, '0')}:'
                '${stop.completedAt!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8)),
              )
            : null,
      ),
    );
  }
}

/// Entrada auxiliar para el reordenamiento drag & drop.
class _ReorderEntry {
  final int index;
  final DeliveryStop stop;

  const _ReorderEntry({required this.index, required this.stop});
}
