import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';
import '../widgets/stop_packages_section.dart';

/// Pantalla de ayuda para ordenar paquetes en la furgoneta.
/// Lógica LIFO: muestra la lista en orden inverso (de N a 1).
/// El paquete de la última parada va al fondo, el de la primera junto a la puerta.
class LoadingOrderScreen extends StatelessWidget {
  final List<StopInfo> stops;

  const LoadingOrderScreen({super.key, required this.stops});

  @override
  Widget build(BuildContext context) {
    // Filtrar solo paradas (sin origen) y ordenar de N a 1 (LIFO)
    final deliveryStops =
        stops.where((s) => !s.isOrigin).toList().reversed.toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldLight,
      appBar: AppBar(
        title: const Text('Ordenar Paquetes'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Cabecera explicativa ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_shipping, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Orden de Carga (LIFO)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Carga en este orden: el primer paquete de la '
                          'lista va al FONDO de la furgoneta, el último '
                          'queda junto a la PUERTA.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Indicador visual fondo/puerta ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppColors.warningSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_downward,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      'FONDO de la furgoneta',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Última entrega primero',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          // ── Lista de paquetes LIFO ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: deliveryStops.length,
              itemBuilder: (context, index) {
                final stop = deliveryStops[index];
                final isFirst = index == 0;
                final isLast = index == deliveryStops.length - 1;

                return _PackageTile(
                  stop: stop,
                  loadPosition: index + 1,
                  totalPackages: deliveryStops.length,
                  positionLabel: isFirst
                      ? '📦 AL FONDO'
                      : isLast
                          ? '📦 JUNTO A LA PUERTA'
                          : null,
                );
              },
            ),
          ),

          // ── Indicador visual puerta ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppColors.successSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_upward,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      'PUERTA de la furgoneta',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Primera entrega al alcance',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.success,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile de un paquete en la lista LIFO.
class _PackageTile extends StatelessWidget {
  final StopInfo stop;
  final int loadPosition;
  final int totalPackages;
  final String? positionLabel;

  const _PackageTile({
    required this.stop,
    required this.loadPosition,
    required this.totalPackages,
    this.positionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isFondo = loadPosition == 1;
    final isPuerta = loadPosition == totalPackages;

    Color bgColor = AppColors.cardLight;
    if (isFondo) bgColor = AppColors.warningSurface;
    if (isPuerta) bgColor = AppColors.successSurface;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFondo
              ? AppColors.warning
              : isPuerta
                  ? AppColors.success
                  : AppColors.border,
          width: (isFondo || isPuerta) ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // ── Número de parada (grande y claro) ──
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(50),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${stop.order}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // ── Info de la parada ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (positionLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        positionLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isFondo
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (stop.hasMultiplePackages)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppColors.warning, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2,
                                  size: 14, color: AppColors.warning),
                              const SizedBox(width: 3),
                              Text(
                                '×${stop.packageCount}',
                                style: TextStyle(
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
                  const SizedBox(height: 2),
                  StopPackagesSection(packages: stop.packages),
                ],
              ),
            ),

            // ── Indicador de carga ──
            Column(
              children: [
                Text(
                  '$loadPosition',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning,
                  ),
                ),
                Text(
                  'de $totalPackages',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  'cargar',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
