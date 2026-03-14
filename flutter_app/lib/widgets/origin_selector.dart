import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../models/origin_mode.dart';
import '../screens/map_picker_screen.dart';

/// Selector del punto de inicio de la ruta.
class OriginSelector extends StatefulWidget {
  final OriginMode mode;

  /// Cadena "lat,lon" cuando el usuario ya seleccionó un punto. Vacía si no.
  final String manualAddress;
  final ValueChanged<OriginMode> onModeChanged;
  final ValueChanged<String> onAddressChanged;

  const OriginSelector({
    super.key,
    required this.mode,
    required this.manualAddress,
    required this.onModeChanged,
    required this.onAddressChanged,
  });

  @override
  State<OriginSelector> createState() => _OriginSelectorState();
}

class _OriginSelectorState extends State<OriginSelector> {
  Future<void> _openMapPicker() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            const MapPickerScreen(address: 'Punto de inicio de la ruta'),
      ),
    );
    if (result != null && mounted) {
      widget.onAddressChanged(
          '${result.latitude},${result.longitude}');
    }
  }

  /// Parsea "lat,lon" → (lat, lon) o null si el formato no es válido.
  (double, double)? _parseCoords() {
    final parts = widget.manualAddress.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      if (lat != null && lon != null) return (lat, lon);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final coords = _parseCoords();
    final hasCoords = coords != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trip_origin, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                'Punto de inicio',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '¿Desde dónde empezamos la ruta?',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 14),

          // ── Opción: Dirección predeterminada (taller) ──
          _OriginOption(
            icon: Icons.home,
            title: 'Taller (predeterminado)',
            subtitle: 'Av. de Andalucía, Posadas',
            isSelected: widget.mode == OriginMode.defaultAddress,
            onTap: () => widget.onModeChanged(OriginMode.defaultAddress),
          ),

          const SizedBox(height: 8),

          // ── Opción: Mi ubicación GPS ──
          _OriginOption(
            icon: Icons.my_location,
            title: 'Mi ubicación actual',
            subtitle: 'Usar GPS del dispositivo',
            isSelected: widget.mode == OriginMode.gps,
            onTap: () => widget.onModeChanged(OriginMode.gps),
          ),

          const SizedBox(height: 8),

          // ── Opción: Marcar en el mapa ──
          _OriginOption(
            icon: Icons.add_location_alt,
            title: 'Marcar en el mapa',
            subtitle: hasCoords
                ? '${coords.$1.toStringAsFixed(5)}, ${coords.$2.toStringAsFixed(5)}'
                : 'Toca el mapa para elegir el punto de inicio',
            isSelected: widget.mode == OriginMode.manual,
            onTap: () => widget.onModeChanged(OriginMode.manual),
          ),

          // ── Botón / estado de la selección en mapa ──
          if (widget.mode == OriginMode.manual) ...[
            const SizedBox(height: 10),
            if (!hasCoords)
              // Sin selección: botón para abrir el mapa
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openMapPicker,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Abrir mapa y marcar punto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              )
            else
              // Con selección: mostrar coords + botón de cambiar
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.successSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on,
                        size: 18, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lat: ${coords.$1.toStringAsFixed(6)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary),
                          ),
                          Text(
                            'Lon: ${coords.$2.toStringAsFixed(6)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _openMapPicker,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Cambiar',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _OriginOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _OriginOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.warningSurface
              : AppColors.scaffoldLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.warning
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AppColors.warning
                  : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? AppColors.warningLight
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  size: 20, color: AppColors.warning),
          ],
        ),
      ),
    );
  }
}
