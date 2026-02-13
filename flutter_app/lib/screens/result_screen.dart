import 'package:flutter/material.dart';

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
