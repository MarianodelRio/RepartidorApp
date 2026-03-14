import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/route_models.dart';
import 'stop_packages_section.dart';

/// Lista de paradas ordenadas con distancia y nombre del cliente.
class StopsList extends StatelessWidget {
  final List<StopInfo> stops;
  final int? highlightedIndex;
  final ValueChanged<int>? onStopTapped;

  const StopsList({
    super.key,
    required this.stops,
    this.highlightedIndex,
    this.onStopTapped,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: stops.length,
      itemBuilder: (context, index) {
        final stop = stops[index];
        return _StopTile(
          stop: stop,
          isLast: index == stops.length - 1,
          isHighlighted: index == highlightedIndex,
          onTap: () => onStopTapped?.call(index),
        );
      },
    );
  }
}

class _StopTile extends StatelessWidget {
  final StopInfo stop;
  final bool isLast;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const _StopTile({
    required this.stop,
    required this.isLast,
    this.isHighlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOrigin = stop.isOrigin;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isHighlighted ? AppColors.primarySurface : AppColors.cardLight,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: isHighlighted
              ? Border.all(color: AppColors.primary, width: 2)
              : isOrigin
                  ? Border.all(color: AppColors.warning, width: 1.5)
                  : null,
          boxShadow: [
            BoxShadow(
              color: isHighlighted
                  ? AppColors.primary.withAlpha(25)
                  : Colors.black.withAlpha(10),
              blurRadius: isHighlighted ? 8 : 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isOrigin ? AppColors.warning : AppColors.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: isOrigin
                  ? const Icon(Icons.home, size: 18, color: Colors.white)
                  : Text(
                      '${stop.order}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          title: isOrigin
              ? Text(
                  stop.label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                )
              : RichText(
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOrigin)
                Text(
                  stop.address,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              else ...[
                StopPackagesSection(packages: stop.packages, fontSize: 11),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      _InfoChip(
                        icon: Icons.straighten,
                        text: _formatDistance(stop.distanceMeters),
                        color: AppColors.textSecondary,
                      ),
                      if (stop.hasMultiplePackages) ...[
                        const SizedBox(width: 6),
                        _InfoChip(
                          icon: Icons.inventory_2,
                          text: '×${stop.packageCount}',
                          color: AppColors.warning,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toInt()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
