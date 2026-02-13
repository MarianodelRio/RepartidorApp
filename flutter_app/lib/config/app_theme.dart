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

  // ── Neutros (Modo Oscuro) ──
  static const Color scaffoldDark = Color(0xFF121212);         // Negro mate
  static const Color cardDark = Color(0xFF1E1E1E);             // Gris carbono
  static const Color surfaceDark = Color(0xFF2C2C2C);          // Elevación 1
  static const Color textPrimaryDark = Color(0xFFECEFF1);      // Casi blanco
  static const Color textSecondaryDark = Color(0xFFB0BEC5);    // Gris claro
  static const Color borderDark = Color(0xFF424242);
  static const Color primaryDark = Color(0xFF448AFF);          // Azul eléctrico

  // ── Mapa ──
  static const Color polylineNav = Color(0xFF2979FF);          // Azul eléctrico
  static const Color polylineBorder = Color(0xB3FFFFFF);       // Blanco 70%
  static const Color markerCompleted = Color(0xFF9E9E9E);      // Gris piedra
  static const Color markerCompletedCheck = Color(0xFF2E7D32); // Check esmeralda
  static const Color markerOrigin = Color(0xFFE65100);         // Ámbar intenso
  static const Color markerNext = Color(0xFF003399);           // Azul profundo
  static const Color markerDefault = Color(0xFF003399);

  // ── GPS Marker ──
  static const Color gps = Color(0xFF2979FF);                  // Azul eléctrico

  // ── Entregado / Ausente / Incidencia (iconos de estado) ──
  static const Color delivered = success;
  static const Color absent = warning;
  static const Color incident = error;
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

// ═══════════════════════════════════════════════════════════════
//  ThemeData — Modo Oscuro (Zerity Style)
// ═══════════════════════════════════════════════════════════════

final ThemeData appDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Roboto',

  colorScheme: const ColorScheme.dark(
    primary: AppColors.primaryDark,
    onPrimary: Colors.white,
    secondary: AppColors.primaryDark,
    onSecondary: Colors.white,
    error: AppColors.errorLight,
    onError: Colors.white,
    surface: AppColors.cardDark,
    onSurface: AppColors.textPrimaryDark,
  ),

  scaffoldBackgroundColor: AppColors.scaffoldDark,

  appBarTheme: const AppBarTheme(
    centerTitle: true,
    elevation: 0,
    backgroundColor: AppColors.cardDark,
    foregroundColor: AppColors.textPrimaryDark,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimaryDark,
      fontFamily: 'Roboto',
    ),
  ),

  cardTheme: CardThemeData(
    color: AppColors.cardDark,
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
    ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primaryDark,
      side: const BorderSide(color: AppColors.primaryDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),

  dividerTheme: const DividerThemeData(
    color: AppColors.borderDark,
    thickness: 1,
  ),

  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.surfaceDark,
    contentTextStyle: const TextStyle(color: AppColors.textPrimaryDark),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    behavior: SnackBarBehavior.floating,
  ),

  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.cardDark,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);
