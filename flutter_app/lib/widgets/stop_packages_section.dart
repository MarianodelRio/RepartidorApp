import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';

/// Sección unificada de clientes y paquetes para cualquier contexto de la app.
///
/// Renderiza la lista de paquetes de una parada con formato consistente:
///   - 0 paquetes o todos vacíos → nada
///   - 1 paquete → "clientName · nota · agencia"  en una línea
///   - N paquetes → "· clientName · nota · agencia" por línea (lista sin collapsible)
class StopPackagesSection extends StatelessWidget {
  final List<Package> packages;

  /// Tamaño de fuente. Por defecto 12, algunos contextos pueden reducirlo.
  final double fontSize;

  const StopPackagesSection({
    super.key,
    required this.packages,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final lines = _buildLines();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map((line) => Text(
                line,
                style: TextStyle(
                  fontSize: fontSize,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ))
          .toList(),
    );
  }

  List<String> _buildLines() {
    final filtered = packages
        .where((p) => p.clientName.isNotEmpty || p.nota.isNotEmpty || p.agencia.isNotEmpty)
        .toList();

    if (filtered.isEmpty) return [];

    if (filtered.length == 1) {
      final p = filtered.first;
      final parts = [
        if (p.clientName.isNotEmpty) p.clientName,
        if (p.nota.isNotEmpty) p.nota,
        if (p.agencia.isNotEmpty) p.agencia,
      ];
      return [parts.join(' · ')];
    }

    return filtered.map((p) {
      final parts = [
        if (p.clientName.isNotEmpty) p.clientName,
        if (p.nota.isNotEmpty) p.nota,
        if (p.agencia.isNotEmpty) p.agencia,
      ];
      final content = parts.join(' · ');
      return '· $content';
    }).toList();
  }
}
