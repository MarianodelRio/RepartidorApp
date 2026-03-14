import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../controllers/delivery_controller.dart';
import 'map_picker_screen.dart';
import '../models/delivery_state.dart';
import '../models/route_models.dart';
import '../widgets/route_map.dart';
import '../widgets/stop_packages_section.dart';

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

class _DeliveryScreenState extends State<DeliveryScreen>
    with WidgetsBindingObserver {
  final GlobalKey<RouteMapState> _mapKey = GlobalKey<RouteMapState>();
  late final DeliveryController _ctrl;

  /// Índice de la parada seleccionada al tocar un marcador (null = panel oculto).
  int? _selectedStopIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = DeliveryController(widget.session);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ctrl.session.currentStop != null) {
        _ctrl.fetchSegment();
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _mapKey.currentState?.fitGpsAndNextStop();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  Persistencia ante cierre del SO
  // ═══════════════════════════════════════════

  /// Guarda la sesión cuando el SO lleva la app a segundo plano o la va a matar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _ctrl.save();
    }
  }

  // ═══════════════════════════════════════════
  //  Acciones de parada
  // ═══════════════════════════════════════════

  /// Abre el panel de información al tocar un marcador en el mapa.
  void _onMarkerTapped(int index) {
    final stop = _ctrl.session.stops[index];
    if (stop.isOrigin) return;
    setState(() => _selectedStopIndex = index);
    _mapKey.currentState?.flyToStop(index);
  }

  /// Marca la parada actual con un estado.
  /// Muestra el diálogo final si el reparto termina, o anima el mapa si no.
  Future<void> _onMarkCurrentStop(StopStatus status, {String? note}) async {
    await _ctrl.markCurrentStop(status, note: note);
    if (!mounted) return;
    if (_ctrl.session.isFinished) {
      _showFinishedDialog();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapKey.currentState?.fitGpsAndNextStop();
      });
    }
  }

  /// Marca cualquier parada por índice (no solo la actual).
  Future<void> _onMarkStopByIndex(
    int sessionIndex,
    StopStatus status, {
    String? note,
  }) async {
    if (sessionIndex >= _ctrl.session.stops.length) return;
    setState(() => _selectedStopIndex = null);

    if (sessionIndex == _ctrl.session.currentStopIndex) {
      await _onMarkCurrentStop(status, note: note);
      return;
    }

    await _ctrl.markStopByIndex(sessionIndex, status, note: note);
    if (!mounted) return;
    if (_ctrl.session.isFinished) {
      _showFinishedDialog();
    }
  }

  /// Diálogo final cuando se completó todo el reparto.
  void _showFinishedDialog() {
    final elapsed = DateTime.now().difference(_ctrl.session.createdAt);
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
            _summaryRow('✅ Entregados', '${_ctrl.session.deliveredCount}'),
            _summaryRow('🚫 Ausentes', '${_ctrl.session.absentCount}'),
            const Divider(height: 24),
            _summaryRow(
                '📦 Total',
                '${_ctrl.session.completedCount}/${_ctrl.session.totalStops}'),
            if (_ctrl.session.totalPackages > _ctrl.session.totalStops)
              _summaryRow('📦 Paquetes', '${_ctrl.session.totalPackages}'),
            _summaryRow('⏱️ Duración', elapsedText),
            _summaryRow('📏 Distancia', _ctrl.session.totalDistanceDisplay),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                await _ctrl.clearSession();
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
  //  Re-pin manual de una parada
  // ═══════════════════════════════════════════

  Future<void> _repinStop(
    DeliveryStop stop,
    int sessionIndex, {
    void Function(DeliveryStop)? onStopUpdated,
  }) async {
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
    if (result == null || !mounted) return;

    await _ctrl.applyRepin(sessionIndex, result.latitude, result.longitude);
    if (!mounted) return;

    onStopUpdated?.call(_ctrl.session.stops[sessionIndex]);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ubicación corregida'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Navegación externa (Google Maps)
  // ═══════════════════════════════════════════

  Future<void> _openNavigationToStop(DeliveryStop stop) async {
    if (stop.lat == null || stop.lon == null) return;
    final uri = Uri.parse('google.navigation:q=${stop.lat},${stop.lon}&mode=d');
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

  Future<void> _openExternalNavigation() async {
    final stop = _ctrl.session.currentStop;
    if (stop == null) return;
    await _openNavigationToStop(stop);
  }

  // ═══════════════════════════════════════════
  //  Confirmar abandono de reparto
  // ═══════════════════════════════════════════

  Future<bool> _onWillPop() async {
    if (_ctrl.session.isFinished) return true;

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

    if (result == true) {
      await _ctrl.save();
    }
    return result ?? false;
  }

  // ═══════════════════════════════════════════
  //  Drag & Drop reordenar paradas pendientes
  // ═══════════════════════════════════════════

  void _showReorderSheet() {
    final pendingEntries = <_ReorderEntry>[];
    for (int i = 0; i < _ctrl.session.stops.length; i++) {
      final s = _ctrl.session.stops[i];
      if (!s.isOrigin && s.status != StopStatus.delivered) {
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_vert,
                            color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reordenar Paradas',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Mantén pulsado y arrastra para cambiar el orden.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary),
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
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${entry.stop.order}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            title: RichText(
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                                children: [
                                  TextSpan(text: entry.stop.address),
                                  if (entry.stop.alias.isNotEmpty)
                                    TextSpan(
                                      text:
                                          '  —  ${entry.stop.alias}',
                                      style: const TextStyle(
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w400,
                                          color: AppColors.primary),
                                    ),
                                ],
                              ),
                            ),
                            subtitle: StopPackagesSection(
                                packages: entry.stop.packages,
                                fontSize: 11),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Botón cambiar ubicación
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Cambiar ubicación',
                                    icon: Icon(
                                      Icons.edit_location_alt,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                    onPressed: () async {
                                      final capturedEntry = entry;
                                      await _repinStop(
                                        capturedEntry.stop,
                                        capturedEntry.index,
                                        onStopUpdated: (newStop) {
                                          setSheetState(() {
                                            final idx = pendingEntries
                                                .indexWhere((e) =>
                                                    e.index ==
                                                    capturedEntry
                                                        .index);
                                            if (idx != -1) {
                                              pendingEntries[idx] =
                                                  _ReorderEntry(
                                                      index: capturedEntry
                                                          .index,
                                                      stop: newStop);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 2),
                                // Botón marcar como entregada
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Marcar como entregada',
                                    icon: Icon(
                                      Icons.check_circle_outline,
                                      color: AppColors.success,
                                      size: 22,
                                    ),
                                    onPressed: () async {
                                      await _ctrl.markStopByIndex(
                                          entry.index,
                                          StopStatus.delivered);
                                      setSheetState(() =>
                                          pendingEntries.removeAt(i));
                                    },
                                  ),
                                ),
                              ],
                            ),
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
                          await _ctrl.applyReorder(
                              pendingEntries.map((e) => e.stop).toList());
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

  // ═══════════════════════════════════════════
  //  Lista de paradas completadas
  // ═══════════════════════════════════════════

  void _showCompletedStops() {
    final completed =
        _ctrl.session.stops.where((s) => s.isCompleted).toList();

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          style: TextStyle(
                              color: AppColors.textTertiary)),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: completed.length,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
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
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final currentStop = _ctrl.session.currentStop;
    final isFinished = _ctrl.session.isFinished;
    final mapStops = _ctrl.session.stops;

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
                label: Text('${_ctrl.session.completedCount}'),
                isLabelVisible: _ctrl.session.completedCount > 0,
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
              _ProgressHeader(session: _ctrl.session),

              // ── Mapa con callout flotante al tocar un marcador ──
              Expanded(
                child: Stack(
                  children: [
                    RouteMap(
                      key: _mapKey,
                      stops: _deliveryToStopInfo(mapStops),
                      highlightedStopIndex:
                          isFinished ? null : _ctrl.session.currentStopIndex,
                      completedIndices: _completedIndices(),
                      deliveryMode: true,
                      segmentGeometry: _ctrl.segmentGeometry,
                      nextStopIndex:
                          isFinished ? null : _ctrl.session.currentStopIndex,
                      onMarkerTapped: _onMarkerTapped,
                    ),
                    if (_selectedStopIndex != null &&
                        _selectedStopIndex! < _ctrl.session.stops.length)
                      Positioned(
                        top: 8,
                        left: 12,
                        right: 12,
                        child: _StopCallout(
                          stop: _ctrl.session.stops[_selectedStopIndex!],
                          onClose: () =>
                              setState(() => _selectedStopIndex = null),
                          onMarkStatus: (status) =>
                              _onMarkStopByIndex(_selectedStopIndex!, status),
                          onRepin: () {
                            final idx = _selectedStopIndex!;
                            final stop = _ctrl.session.stops[idx];
                            setState(() => _selectedStopIndex = null);
                            _repinStop(stop, idx);
                          },
                          onNavigate: () => _openNavigationToStop(
                              _ctrl.session.stops[_selectedStopIndex!]),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Tarjeta de siguiente parada + acciones ──
              if (!isFinished && currentStop != null)
                _NextStopCard(
                  stop: currentStop,
                  pendingCount: _ctrl.session.pendingCount,
                  onDelivered: () =>
                      _onMarkCurrentStop(StopStatus.delivered),
                  onAbsent: () => _onMarkCurrentStop(StopStatus.absent),
                  onNavigate: _openExternalNavigation,
                  onRepin: () => _repinStop(
                      currentStop, _ctrl.session.currentStopIndex),
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
              alias: s.alias,
              label: s.label,
              clientName: s.clientName,
              clientNames: s.clientNames,
              type: s.type,
              lat: s.lat,
              lon: s.lon,
              distanceMeters: s.distanceMeters,
              packageCount: s.packageCount,
              packages: s.packages,
            ))
        .toList();
  }

  /// Índices de paradas completadas para visualizarlas diferente en el mapa.
  Set<int> _completedIndices() {
    final indices = <int>{};
    for (int i = 0; i < _ctrl.session.stops.length; i++) {
      if (_ctrl.session.stops[i].isCompleted) indices.add(i);
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
            '✅ ${_ctrl.session.deliveredCount}  ·  🚫 ${_ctrl.session.absentCount}',
            style: const TextStyle(fontSize: 13, color: AppColors.success),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await _ctrl.clearSession();
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
                  _miniChip(
                      '🚫', '${session.absentCount}', AppColors.absent),
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
  final VoidCallback onNavigate;
  final VoidCallback onRepin;

  const _NextStopCard({
    required this.stop,
    required this.pendingCount,
    required this.onDelivered,
    required this.onAbsent,
    required this.onNavigate,
    required this.onRepin,
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
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
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
                            const Text(
                              'SIGUIENTE PARADA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
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
                        RichText(
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                            children: [
                              TextSpan(text: stop.address),
                              if (stop.alias.isNotEmpty)
                                TextSpan(
                                  text: '  —  ${stop.alias}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.primary.withAlpha(180),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        StopPackagesSection(packages: stop.packages),
                      ],
                    ),
                  ),

                  // ── Botones navegación + re-pin ──
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: AppColors.primarySurface,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          onTap: onNavigate,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.navigation,
                                color: AppColors.primary, size: 24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Material(
                        color: AppColors.warningSurface,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          onTap: onRepin,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.edit_location_alt,
                                color: AppColors.warning, size: 24),
                          ),
                        ),
                      ),
                    ],
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
                        icon: const Icon(Icons.check_circle,
                            size: 24, color: Colors.white),
                        label: const Text('Entregado',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
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
                        icon: const Icon(Icons.person_off,
                            size: 20, color: Colors.white),
                        label: const Text('Ausente',
                            style:
                                TextStyle(fontSize: 14, color: Colors.white)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
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
        title: RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
            children: [
              TextSpan(text: '${stop.order}. ${stop.address}'),
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
            StopPackagesSection(packages: stop.packages, fontSize: 11),
            if (stop.note != null && stop.note!.isNotEmpty)
              Text(
                '📝 ${stop.note}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF64748B)),
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

// ═══════════════════════════════════════════
//  Callout flotante de parada (tap en marcador)
// ═══════════════════════════════════════════

/// Globo/callout que aparece sobre el mapa al tocar un marcador.
///
/// El mapa centra la parada en pantalla (flyToStop) justo antes de mostrar
/// este widget, de modo que el triángulo inferior apunta al pin centrado.
class _StopCallout extends StatelessWidget {
  final DeliveryStop stop;
  final VoidCallback onClose;
  final void Function(StopStatus) onMarkStatus;
  final VoidCallback onRepin;
  final VoidCallback onNavigate;

  const _StopCallout({
    required this.stop,
    required this.onClose,
    required this.onMarkStatus,
    required this.onRepin,
    required this.onNavigate,
  });

  Color get _statusColor => switch (stop.status) {
        StopStatus.pending => AppColors.primary,
        StopStatus.delivered => AppColors.success,
        StopStatus.absent => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Tarjeta ──
        Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          shadowColor: const Color(0x44000000),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabecera
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge número coloreado por estado
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _statusColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${stop.order}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Información de la parada
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Chip de estado
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _statusColor.withAlpha(25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                stop.status.label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),

                            // Dirección
                            Text(
                              stop.address,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),

                            // Alias
                            if (stop.alias.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                stop.alias,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.primary.withAlpha(200),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],

                            // Clientes y paquetes
                            StopPackagesSection(
                                packages: stop.packages, fontSize: 11),
                          ],
                        ),
                      ),

                      // Botón cerrar
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 18),
                        color: AppColors.textTertiary,
                        padding: const EdgeInsets.all(6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

                // Acciones
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: _buildActions(),
                ),
              ],
            ),
          ),
        ),

        // ── Triángulo apuntando al pin ──
        CustomPaint(
          size: const Size(20, 10),
          painter: _DownwardTrianglePainter(),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return switch (stop.status) {
      StopStatus.pending => Row(
          children: [
            Expanded(
              flex: 3,
              child: _ActionButton(
                label: 'Entregada',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                onTap: () => onMarkStatus(StopStatus.delivered),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _ActionButton(
                label: 'Ausente',
                icon: Icons.person_off_outlined,
                color: AppColors.warning,
                onTap: () => onMarkStatus(StopStatus.absent),
              ),
            ),
            const SizedBox(width: 6),
            _ActionIconButton(
              icon: Icons.edit_location_alt,
              color: AppColors.primary,
              tooltip: 'Mover ubicación',
              onTap: onRepin,
            ),
            const SizedBox(width: 4),
            _ActionIconButton(
              icon: Icons.navigation,
              color: AppColors.primary,
              tooltip: 'Google Maps',
              onTap: onNavigate,
            ),
          ],
        ),
      StopStatus.absent => Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Marcar entregada',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                onTap: () => onMarkStatus(StopStatus.delivered),
              ),
            ),
            const SizedBox(width: 6),
            _ActionIconButton(
              icon: Icons.edit_location_alt,
              color: AppColors.primary,
              tooltip: 'Mover ubicación',
              onTap: onRepin,
            ),
            const SizedBox(width: 4),
            _ActionIconButton(
              icon: Icons.navigation,
              color: AppColors.primary,
              tooltip: 'Google Maps',
              onTap: onNavigate,
            ),
          ],
        ),
      StopStatus.delivered => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ActionIconButton(
              icon: Icons.edit_location_alt,
              color: AppColors.primary,
              tooltip: 'Mover ubicación',
              onTap: onRepin,
            ),
            const SizedBox(width: 4),
            _ActionIconButton(
              icon: Icons.navigation,
              color: AppColors.primary,
              tooltip: 'Google Maps',
              onTap: onNavigate,
            ),
          ],
        ),
    };
  }
}

/// Pinta un triángulo apuntando hacia abajo (conector visual al pin del mapa).
class _DownwardTrianglePainter extends CustomPainter {
  const _DownwardTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_DownwardTrianglePainter _) => false;
}

/// Botón de acción con icono y etiqueta (ocupa espacio flexible).
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }
}

/// Botón de acción compacto solo con icono (tamaño fijo 44×44).
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}
