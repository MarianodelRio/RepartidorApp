import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/route_models.dart';

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
    // Separar paradas optimizadas de las fallidas (no validadas)
    final optimizedStops = stops.where((s) => !s.geocodeFailed).toList();
    final failedStops = stops.where((s) => s.geocodeFailed).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // +1 for the separator if there are failed stops
      itemCount: stops.length + (failedStops.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // Separator between optimized and failed stops
        if (failedStops.isNotEmpty && index == optimizedStops.length) {
          return _UnresolvedSeparator(count: failedStops.length);
        }

        // Adjust index for items after the separator
        final stopIndex = failedStops.isNotEmpty && index > optimizedStops.length
            ? index - 1
            : index;
        final stop = stops[stopIndex];

        return _StopTile(
          stop: stop,
          isLast: stopIndex == stops.length - 1,
          isHighlighted: stopIndex == highlightedIndex,
          onTap: () => onStopTapped?.call(stopIndex),
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
    final isFailed = stop.geocodeFailed;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.primarySurface
              : isFailed
                  ? AppColors.warningSurface
                  : AppColors.cardLight,
          borderRadius: BorderRadius.circular(10),
          border: isHighlighted
              ? Border.all(color: AppColors.primary, width: 2)
              : isOrigin
                  ? Border.all(color: AppColors.warning, width: 1.5)
                  : isFailed
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
            color: isOrigin
                ? AppColors.warning
                : isFailed
                    ? AppColors.warning
                    : AppColors.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: isOrigin
                ? const Icon(Icons.home, size: 18, color: Colors.white)
                : isFailed
                    ? const Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.white)
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
        title: Text(
          stop.clientName.isNotEmpty && !isOrigin
              ? stop.clientName
              : stop.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isFailed ? AppColors.warning : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFailed
                  ? '⚠ Sin ubicación — ${stop.address}'
                  : stop.address,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!isOrigin)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (isFailed) ...[
                      _InfoChip(
                        icon: Icons.warning_amber_rounded,
                        text: 'No validada',
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (!isFailed)
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
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Separador visual entre paradas optimizadas y no validadas.
class _UnresolvedSeparator extends StatelessWidget {
  final int count;

  const _UnresolvedSeparator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pendientes — $count parada${count > 1 ? 's' : ''} no validada${count > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
