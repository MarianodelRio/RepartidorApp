import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Modos de selección de origen.
enum OriginMode {
  defaultAddress,
  manual,
  gps,
}

/// Selector del punto de inicio de la ruta.
class OriginSelector extends StatelessWidget {
  final OriginMode mode;
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
  Widget build(BuildContext context) {
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
            subtitle: 'C/ Callejón de Jesús 1, Posadas',
            isSelected: mode == OriginMode.defaultAddress,
            onTap: () => onModeChanged(OriginMode.defaultAddress),
          ),

          const SizedBox(height: 8),

          // ── Opción: Mi ubicación GPS ──
          _OriginOption(
            icon: Icons.my_location,
            title: 'Mi ubicación actual',
            subtitle: 'Usar GPS del dispositivo',
            isSelected: mode == OriginMode.gps,
            onTap: () => onModeChanged(OriginMode.gps),
          ),

          const SizedBox(height: 8),

          // ── Opción: Dirección manual ──
          _OriginOption(
            icon: Icons.edit_location_alt,
            title: 'Dirección manual',
            subtitle: 'Escribir una dirección personalizada',
            isSelected: mode == OriginMode.manual,
            onTap: () => onModeChanged(OriginMode.manual),
          ),

          // ── Campo de texto para dirección manual ──
          if (mode == OriginMode.manual) ...[
            const SizedBox(height: 12),
            TextField(
              onChanged: onAddressChanged,
              decoration: InputDecoration(
                hintText: 'Ej: Calle Mayor 5, Posadas',
                hintStyle:
                    TextStyle(fontSize: 13, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.scaffoldLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: Icon(Icons.search,
                    size: 18, color: AppColors.textTertiary),
              ),
              style: const TextStyle(fontSize: 14),
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
