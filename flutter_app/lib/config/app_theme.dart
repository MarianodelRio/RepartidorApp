import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
//  Paleta de colores de la app — Alto Contraste / Wolt-style
// ═══════════════════════════════════════════════════════════════
//
//  Regla de Oro: Texto sobre color → blanco.
//               Texto sobre fondo claro → azul profundo o gris oscuro.
//               NUNCA gris claro sobre fondo claro.

abstract final class AppColors {
  // ── Primario — Azul Profundo / Medianoche ──
  static const Color primary = Color(0xFF003399);
  static const Color primaryLight = Color(0xFF1A56DB);
  static const Color primarySurface = Color(0xFFE8EEFB); // tint para selección

  // ── Éxito — Verde Esmeralda Sólido ──
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFF4CAF50);
  static const Color successSurface = Color(0xFFE8F5E9);

  // ── Advertencia — Ámbar Intenso (GLS) ──
  static const Color warning = Color(0xFFE65100);
  static const Color warningLight = Color(0xFFF57C00);
  static const Color warningSurface = Color(0xFFFFF3E0);

  // ── Error — Rojo Carmesí ──
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFE53935);
  static const Color errorSurface = Color(0xFFFFEBEE);

  // ── Neutros (Modo Claro) ──
  static const Color scaffoldLight = Color(0xFFF5F5F5);       // Gris humo
  static const Color cardLight = Color(0xFFFFFFFF);            // Blanco puro
  static const Color textPrimary = Color(0xFF0D1B2A);         // Casi negro
  static const Color textSecondary = Color(0xFF475569);        // Gris oscuro
  static const Color textTertiary = Color(0xFF78909C);         // Gris medio
  static const Color border = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFEEEEEE);

  // ── Mapa ──
  static const Color polylineNav = Color(0xFF2979FF);          // Azul eléctrico
  static const Color polylineBorder = Color(0xB3FFFFFF);       // Blanco 70%
  static const Color markerCompleted = Color(0xFF9E9E9E);      // Gris piedra
  static const Color markerOrigin = Color(0xFFE65100);         // Ámbar intenso
  static const Color markerNext = Color(0xFF003399);           // Azul profundo
  static const Color markerDefault = Color(0xFF003399);

  // ── GPS Marker ──
  static const Color gps = Color(0xFF2979FF);                  // Azul eléctrico

  // ── Pin manual (re-pin de usuario) ──
  static const Color manualPin = warning;  // ámbar intenso — mismo valor, nombre semántico

  // ── Activo / En curso (sesión de reparto abierta) ──
  static const Color active        = Color(0xFF00897B); // Teal
  static const Color activeSurface = Color(0xFFE0F2F1); // Teal muy claro

  // ── Entregado / Ausente (iconos de estado) ──
  static const Color delivered = success;
  static const Color absent = warning;
}

// ═══════════════════════════════════════════════════════════════
//  Sistema de radios — usar siempre estos valores para coherencia
// ═══════════════════════════════════════════════════════════════

abstract final class AppRadius {
  static const double card    = 16; // cards, sheets, mapa
  static const double button  = 12; // botones, chips acción
  static const double chip    =  8; // chips informativos
  static const double dialog  = 20; // diálogos modales
  static const double badge   = 10; // badges / números
}

// ═══════════════════════════════════════════════════════════════
//  Sistema de sombras — 3 niveles de elevación
// ═══════════════════════════════════════════════════════════════

abstract final class AppShadows {
  /// Nivel 1 — cards y contenedores sobre scaffold
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14000000), blurRadius: 8,  offset: Offset(0, 2)),
  ];

  /// Nivel 2 — bottom sheets y paneles flotantes
  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, -4)),
  ];

  /// Nivel 3 — FABs y elementos sobre el mapa
  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

// ═══════════════════════════════════════════════════════════════
//  ThemeData — Modo Claro
// ═══════════════════════════════════════════════════════════════

final ThemeData appLightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  fontFamily: 'Roboto',

  // Colores del sistema
  colorScheme: const ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.primaryLight,
    onSecondary: Colors.white,
    error: AppColors.error,
    onError: Colors.white,
    surface: AppColors.cardLight,
    onSurface: AppColors.textPrimary,
  ),

  scaffoldBackgroundColor: AppColors.scaffoldLight,

  appBarTheme: const AppBarTheme(
    centerTitle: true,
    elevation: 0,
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      fontFamily: 'Roboto',
    ),
  ),

  cardTheme: CardThemeData(
    color: AppColors.cardLight,
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
    ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),

  dividerTheme: const DividerThemeData(
    color: AppColors.divider,
    thickness: 1,
  ),

  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.primary,
    contentTextStyle: const TextStyle(color: Colors.white),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    behavior: SnackBarBehavior.floating,
  ),

  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);

