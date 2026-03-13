import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';
import '../services/persistence_service.dart';
import '../widgets/route_map.dart';
import '../widgets/stats_banner.dart';
import '../widgets/stop_packages_section.dart';
import '../widgets/stops_list.dart';
import 'delivery_screen.dart';
import 'loading_order_screen.dart';

/// Pantalla de resultados: mapa + lista de paradas.
class ResultScreen extends StatefulWidget {
  final OptimizeResponse response;

  const ResultScreen({super.key, required this.response});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GlobalKey<RouteMapState> _mapKey = GlobalKey<RouteMapState>();
  int? _highlightedStop;
  StopInfo? _selectedStop;

  /// Al tocar una parada en la lista, centra el mapa, resalta y cierra callout.
  void _onStopTapped(int index) {
    setState(() {
      _highlightedStop = index;
      _selectedStop = null;
    });
    _mapKey.currentState?.flyToStop(index);
  }

  /// Al tocar un marcador en el mapa, centra, resalta y muestra callout.
  void _onMarkerTapped(int index) {
    final stop = widget.response.stops[index];
    if (stop.isOrigin) return;
    _mapKey.currentState?.flyToStop(index);
    setState(() {
      _highlightedStop = index;
      _selectedStop = stop;
    });
  }

  @override
  Widget build(BuildContext context) {
    final response = widget.response;

    return Scaffold(
      backgroundColor: AppColors.scaffoldLight,
      appBar: AppBar(
        title: const Text('Ruta Optimizada'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // ── Botón de Exportar CSV ──
          IconButton(
            onPressed: () => _exportCsv(context),
            icon: const Icon(Icons.share),
            tooltip: 'Exportar ruta CSV',
          ),
          // ── Botón de Ordenar Paquetes ──
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LoadingOrderScreen(stops: response.stops),
                ),
              );
            },
            icon: const Icon(Icons.local_shipping),
            tooltip: 'Ordenar Paquetes (LIFO)',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Resumen ──
            StatsBanner(
              items: [
                StatItem(
                  label: 'Paradas',
                  value: '${response.summary.totalStops}',
                  icon: Icons.pin_drop,
                ),
                if (response.summary.totalPackages > response.summary.totalStops)
                  StatItem(
                    label: 'Paquetes',
                    value: '${response.summary.totalPackages}',
                    icon: Icons.inventory_2,
                  ),
                StatItem(
                  label: 'Distancia',
                  value: response.summary.totalDistanceDisplay,
                  icon: Icons.straighten,
                ),
              ],
            ),

            // ── Tiempo de cálculo ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.successSurface,
              child: Text(
                '⚡ Calculado en ${response.summary.computingTimeMs.toStringAsFixed(0)} ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ),

            // ── Mapa con callout al tocar marcador ──
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.35,
              child: Stack(
                children: [
                  RouteMap(
                    key: _mapKey,
                    stops: response.stops,
                    highlightedStopIndex: _highlightedStop,
                    onMarkerTapped: _onMarkerTapped,
                  ),
                  if (_selectedStop != null)
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: _StopCallout(
                        stop: _selectedStop!,
                        onClose: () =>
                            setState(() => _selectedStop = null),
                      ),
                    ),
                ],
              ),
            ),

            // ── Lista de paradas ──
            Expanded(
              child: StopsList(
                stops: response.stops,
                highlightedIndex: _highlightedStop,
                onStopTapped: _onStopTapped,
              ),
            ),
          ],
        ),
      ),

      // ── Botón: Iniciar Reparto ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _startDelivery(context),
              icon: const Icon(Icons.play_arrow, size: 24),
              label: const Text(
                '🚀  Iniciar Reparto',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    // ── Confirmación ──
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.share, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Exportar ruta CSV',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'Se generará el fichero ruta_optimizada.csv y podrás guardarlo donde quieras (Descargas, Drive, WhatsApp…).',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Compartir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // ── Generar CSV ──
    final stops = widget.response.stops.where((s) => !s.isOrigin).toList();
    final buffer = StringBuffer();
    buffer.writeln('orden,direccion,alias,num_paquetes,paquetes');
    for (final stop in stops) {
      buffer.writeln(
        '${stop.order},'
        '${_csvEscape(stop.address)},'
        '${_csvEscape(stop.alias)},'
        '${stop.packageCount},'
        '${_csvEscape(_buildPaquetesCell(stop))}',
      );
    }

    // ── Compartir / guardar CSV via sistema ──
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ruta_optimizada.csv');
      await file.writeAsString(buffer.toString(), encoding: utf8);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: 'ruta_optimizada.csv')],
        subject: 'Ruta optimizada',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Construye el contenido de la columna "paquetes" para una parada.
  ///
  /// 1 paquete  → "Juan García - nota - agencia"  (sin número)
  /// N paquetes → "1. Juan García - nota - agencia | 2. María López - SEUR | ..."
  ///
  /// Los campos vacíos se omiten, nunca quedan guiones solos.
  String _buildPaquetesCell(StopInfo stop) {
    if (stop.packages.isEmpty) return '';

    String formatPackage(Package p) {
      return [p.clientName, p.nota, p.agencia]
          .where((s) => s.isNotEmpty)
          .join(' - ');
    }

    if (stop.packages.length == 1) {
      return formatPackage(stop.packages.first);
    }

    return stop.packages
        .asMap()
        .entries
        .map((e) {
          final detail = formatPackage(e.value);
          return '${e.key + 1}. $detail';
        })
        .join(' | ');
  }

  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('|')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _startDelivery(BuildContext context) async {
    final session = PersistenceService.createSession(widget.response);
    await PersistenceService.saveSession(session);

    if (!context.mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DeliveryScreen(session: session),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Callout flotante de parada (tap en marcador)
// ═══════════════════════════════════════════

/// Globo informativo que aparece sobre el mapa al tocar un marcador.
class _StopCallout extends StatelessWidget {
  final StopInfo stop;
  final VoidCallback onClose;

  const _StopCallout({required this.stop, required this.onClose});

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toInt()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge con número
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
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

                  // Información
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            children: [
                              TextSpan(text: stop.address),
                              if (stop.alias.isNotEmpty)
                                TextSpan(
                                  text: '  —  ${stop.alias}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.primary.withAlpha(200),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        StopPackagesSection(packages: stop.packages),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _InfoChip(
                              icon: Icons.straighten,
                              label: _formatDistance(stop.distanceMeters),
                              color: AppColors.textSecondary,
                            ),
                            if (stop.hasMultiplePackages) ...[
                              const SizedBox(width: 6),
                              _InfoChip(
                                icon: Icons.inventory_2,
                                label: '×${stop.packageCount}',
                                color: AppColors.warning,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Cerrar
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
          ),
        ),

        // ── Triángulo apuntando al marcador ──
        CustomPaint(
          size: const Size(20, 10),
          painter: _TrianglePainter(),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TrianglePainter _) => false;
}
