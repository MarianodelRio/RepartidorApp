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

  /// Al tocar una parada, centramos el mapa y resaltamos.
  void _onStopTapped(int index) {
    setState(() => _highlightedStop = index);
    _mapKey.currentState?.flyToStop(index);
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
            icon: const Icon(Icons.download),
            tooltip: 'Descargar ruta CSV',
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

            // ── Mapa ──
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.35,
              child: RouteMap(
                key: _mapKey,
                stops: response.stops,
                geometry: response.geometry,
                highlightedStopIndex: _highlightedStop,
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
    final stops = widget.response.stops.where((s) => !s.isOrigin).toList();

    final buffer = StringBuffer();
    buffer.writeln('orden,direccion,alias,num_paquetes,paquetes');

    for (final stop in stops) {
      final direccion = stop.geocodeFailed
          ? '${stop.address} (sin ubicacion)'
          : stop.address;
      buffer.writeln(
        '${stop.order},'
        '${_csvEscape(direccion)},'
        '${_csvEscape(stop.alias)},'
        '${stop.packageCount},'
        '${_csvEscape(_buildPaquetesCell(stop))}',
      );
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ruta_optimizada.csv');
      await file.writeAsString(buffer.toString(), encoding: utf8);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
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
  /// 1 paquete  → "Juan García - nota"  (sin número)
  /// N paquetes → "1. Juan García - nota | 2. María López | 3. Pedro - otra nota"
  ///
  /// Si cliente o nota están vacíos se omiten, nunca quedan guiones solos.
  String _buildPaquetesCell(StopInfo stop) {
    if (stop.packages.isEmpty) return '';

    String formatPackage(Package p) {
      return [p.clientName, p.nota]
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
