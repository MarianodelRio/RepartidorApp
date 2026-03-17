import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';
import 'result_screen.dart';

/// Pantalla de selección de ruta (modo 2 rutas).
///
/// Muestra dos tarjetas — Express y Normal — con el resumen de cada una.
/// Al tocar una tarjeta, navega a [ResultScreen] con esa ruta.
class RouteSelectionScreen extends StatelessWidget {
  final OptimizeResponse expressRoute;
  final OptimizeResponse normalRoute;

  const RouteSelectionScreen({
    super.key,
    required this.expressRoute,
    required this.normalRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldLight,
      appBar: AppBar(
        title: const Text('Seleccionar Ruta'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Elige la ruta que deseas iniciar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              _RouteCard(
                routeLabel: 'Ruta Express',
                summary: expressRoute.summary,
                accentColor: AppColors.warning,
                surfaceColor: AppColors.warningSurface,
                icon: Icons.bolt,
                onTap: () => _openRoute(context, expressRoute, 'Express'),
              ),
              const SizedBox(height: 16),
              _RouteCard(
                routeLabel: 'Ruta Normal',
                summary: normalRoute.summary,
                accentColor: AppColors.primary,
                surfaceColor: AppColors.primarySurface,
                icon: Icons.local_shipping,
                onTap: () => _openRoute(context, normalRoute, 'Normal'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRoute(
    BuildContext context,
    OptimizeResponse response,
    String routeType,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          response: response,
          routeType: routeType,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Tarjeta de ruta
// ═══════════════════════════════════════════

class _RouteCard extends StatelessWidget {
  final String routeLabel;
  final RouteSummary summary;
  final Color accentColor;
  final Color surfaceColor;
  final IconData icon;
  final VoidCallback onTap;

  const _RouteCard({
    required this.routeLabel,
    required this.summary,
    required this.accentColor,
    required this.surfaceColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardLight,
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: accentColor.withAlpha(100), width: 1.5),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Icono
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 16),

              // Información
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routeLabel,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _StatChip(
                          icon: Icons.pin_drop,
                          label: '${summary.totalStops} paradas',
                          color: accentColor,
                        ),
                        _StatChip(
                          icon: Icons.inventory_2,
                          label: '${summary.totalPackages} paquetes',
                          color: accentColor,
                        ),
                        _StatChip(
                          icon: Icons.straighten,
                          label: summary.totalDistanceDisplay,
                          color: accentColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Flecha
              Icon(
                Icons.chevron_right,
                color: accentColor.withAlpha(180),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
