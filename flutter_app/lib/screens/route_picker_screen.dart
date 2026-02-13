import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';
import 'result_screen.dart';

/// Pantalla para elegir entre 2 rutas cuando se usa reparto compartido.
///
/// Diseño centrado en el repartidor: muestra los nombres de los repartidores
/// con un selector claro y confirma antes de continuar.
class RoutePickerScreen extends StatefulWidget {
  final MultiRouteResponse multiResponse;

  const RoutePickerScreen({super.key, required this.multiResponse});

  @override
  State<RoutePickerScreen> createState() => _RoutePickerScreenState();
}

class _RoutePickerScreenState extends State<RoutePickerScreen> {
  int? _selectedIndex;

  static const _drivers = ['Evaristo', 'Juanma'];
  static final _colors = [AppColors.primary, const Color(0xFF7C3AED)];
  static const _emojis = ['🔵', '🟣'];

  @override
  Widget build(BuildContext context) {
    final routes = widget.multiResponse.routes;

    return Scaffold(
      backgroundColor: AppColors.scaffoldLight,
      appBar: AppBar(
        title: const Text('¿Quién eres?'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Encabezado ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withAlpha(50)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.people_alt, size: 44, color: AppColors.primary),
                    const SizedBox(height: 10),
                    Text(
                      'Reparto Compartido',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecciona tu nombre para ver\nla ruta que te corresponde.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Selector de repartidor ──
              ...List.generate(routes.length, (i) {
                final isSelected = _selectedIndex == i;
                final driverName =
                    i < _drivers.length ? _drivers[i] : 'Repartidor ${i + 1}';
                final color = i < _colors.length ? _colors[i] : AppColors.textSecondary;
                final emoji = i < _emojis.length ? _emojis[i] : '📍';
                final deliveryStops =
                    routes[i].stops.where((s) => s.type == 'stop').length;
                final totalPkg = routes[i].summary.totalPackages;
                final hasGrouped = totalPkg > deliveryStops;

                return Padding(
                  padding: EdgeInsets.only(bottom: i < routes.length - 1 ? 12 : 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withAlpha(15) : AppColors.cardLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? color : AppColors.border,
                          width: isSelected ? 2.5 : 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withAlpha(30),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withAlpha(8),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                      child: Row(
                        children: [
                          // ── Avatar ──
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isSelected ? color : color.withAlpha(25),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 26)
                                  : Text(emoji,
                                      style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // ── Info ──
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? color
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$deliveryStops paradas'
                                  '${hasGrouped ? ' ($totalPkg 📦)' : ''}'
                                  ' · ${routes[i].summary.totalDistanceDisplay}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Radio indicator ──
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? color : AppColors.border,
                                width: isSelected ? 2 : 1.5,
                              ),
                              color: isSelected ? color : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const Spacer(),

              // ── Botón Confirmar ──
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _selectedIndex != null ? 1.0 : 0.4,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _selectedIndex != null
                        ? () => _confirmSelection(context, routes[_selectedIndex!])
                        : null,
                    icon: const Icon(Icons.arrow_forward, size: 22),
                    label: Text(
                      _selectedIndex != null
                          ? 'Continuar como ${_selectedIndex! < _drivers.length ? _drivers[_selectedIndex!] : "Repartidor ${_selectedIndex! + 1}"}'
                          : 'Selecciona tu nombre',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _selectedIndex != null
                          ? _colors[_selectedIndex!.clamp(0, _colors.length - 1)]
                          : AppColors.textTertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSelection(BuildContext context, OptimizeResponse route) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(response: route),
      ),
    );
  }
}
