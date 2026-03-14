import 'dart:ui';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/persistence_service.dart';
import 'delivery_screen.dart';
import 'import_screen.dart';
import 'map_editor_screen.dart';

/// Pantalla de inicio: punto de entrada tras el splash.
/// Muestra las dos acciones principales de la app (ruta y editor de mapa)
/// más una tarjeta condicional para reanudar un reparto activo.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── Animaciones de entrada ────────────────────────────────────────────────

  late AnimationController _animController;

  // Hero: 0 % → 45 %
  late Animation<double> _fade0;
  late Animation<double> _slide0;
  // Tarjeta 1: 15 % → 62 %
  late Animation<double> _fade1;
  late Animation<double> _slide1;
  // Tarjeta 2: 30 % → 82 %
  late Animation<double> _fade2;
  late Animation<double> _slide2;

  // ── Estado ────────────────────────────────────────────────────────────────

  bool _serverOnline     = false;
  bool _isCheckingServer = true;
  bool _hasActiveSession = false;

  // Gradiente idéntico al splash para continuidad visual.
  static const _kGradient = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [Color(0xFF001A4D), AppColors.primary, Color(0xFF1A56DB)],
    stops:  [0.0, 0.5, 1.0],
  );

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _fade0 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );
    _slide0 = Tween<double>(begin: 22.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _fade1 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.15, 0.62, curve: Curves.easeOut),
      ),
    );
    _slide1 = Tween<double>(begin: 28.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.15, 0.62, curve: Curves.easeOutCubic),
      ),
    );

    _fade2 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.30, 0.82, curve: Curves.easeOut),
      ),
    );
    _slide2 = Tween<double>(begin: 28.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.30, 0.82, curve: Curves.easeOutCubic),
      ),
    );

    _animController.forward();
    _checkStatus();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Lógica ────────────────────────────────────────────────────────────────

  Future<void> _checkStatus() async {
    setState(() => _isCheckingServer = true);

    final results = await Future.wait([
      ApiService.healthCheck(),
      PersistenceService.hasActiveSession(),
    ]);

    if (!mounted) return;
    setState(() {
      _serverOnline     = results[0];
      _isCheckingServer = false;
      _hasActiveSession = results[1];
    });
  }

  Future<void> _resumeDelivery() async {
    final session = await PersistenceService.loadSession();
    if (!mounted || session == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeliveryScreen(session: session)),
    );
    if (mounted) _checkStatus();
  }

  Future<void> _discardSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Descartar reparto?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: const Text(
          'Se perderá el progreso del reparto en curso.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await PersistenceService.clearSession();
    if (mounted) setState(() => _hasActiveSession = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width:  double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: _kGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) => _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar: logo + nombre + chip servidor ────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/icon.png',
              width:  42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Repartidor',
                  style: TextStyle(
                    fontSize:    18,
                    fontWeight:  FontWeight.w800,
                    color:       Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Posadas, Córdoba',
                  style: TextStyle(
                    fontSize: 11,
                    color:    Colors.white.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          _buildServerChip(),
        ],
      ),
    );
  }

  Widget _buildServerChip() {
    if (_isCheckingServer) {
      return SizedBox(
        width:  18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white.withAlpha(180),
        ),
      );
    }
    return GestureDetector(
      onTap: _checkStatus,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size:  8,
              color: _serverOnline ? AppColors.successLight : AppColors.errorLight,
            ),
            const SizedBox(width: 5),
            Text(
              _serverOnline ? 'Online' : 'Offline',
              style: const TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w600,
                color:      Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contenido principal con stagger ──────────────────────────────────────

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Spacer(),

          // Hero
          Transform.translate(
            offset: Offset(0, _slide0.value),
            child: Opacity(
              opacity: _fade0.value,
              child: _buildHeroSection(),
            ),
          ),

          const SizedBox(height: 32),

          // Tarjeta 1: Iniciar ruta (acción principal)
          Transform.translate(
            offset: Offset(0, _slide1.value),
            child: Opacity(
              opacity: _fade1.value,
              child: _ActionCard(
                icon:      Icons.local_shipping_rounded,
                iconColor: const Color(0xFF1B8A4C),
                title:    'Iniciar ruta',
                subtitle: 'Carga tu CSV y calcula la ruta óptima de reparto',
                primary:  true,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ImportScreen()))
                    .then((_) { if (mounted) _checkStatus(); }),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Tarjeta 2: Editar mapa (acción secundaria)
          Transform.translate(
            offset: Offset(0, _slide2.value),
            child: Opacity(
              opacity: _fade2.value,
              child: _ActionCard(
                icon:      Icons.edit_road_rounded,
                iconColor: const Color(0xFF2E4A7A),
                title:    'Editar mapa',
                subtitle: 'Modifica calles y accesos de Posadas',
                primary:  false,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MapEditorScreen())),
              ),
            ),
          ),

          // Tarjeta 3: Continuar reparto (condicional)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end:   Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                )),
                child: child,
              ),
            ),
            child: _hasActiveSession
                ? Padding(
                    key: const ValueKey('resume'),
                    padding: const EdgeInsets.only(top: 12),
                    child: _ResumeCard(
                      onResume:  _resumeDelivery,
                      onDiscard: _discardSession,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),

          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      children: [
        Container(
          width:  68,
          height: 68,
          decoration: BoxDecoration(
            color:  Colors.white.withAlpha(22),
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white.withAlpha(55)),
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            size:  34,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '¿Qué hacemos hoy?',
          style: TextStyle(
            fontSize:    22,
            fontWeight:  FontWeight.w800,
            color:       Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Selecciona una opción para empezar',
          style: TextStyle(
            fontSize: 13,
            color:    Colors.white.withAlpha(150),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
//  Tarjeta de acción (glassmorphism real)
// ═══════════════════════════════════════════

class _ActionCard extends StatelessWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       title;
  final String       subtitle;
  final bool         primary;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconBoxSize  = primary ? 60.0 : 50.0;
    final iconSize     = primary ? 28.0 : 23.0;
    final iconRadius   = primary ? 16.0 : 13.0;
    final titleSize    = primary ? 17.0 : 15.0;
    final subtitleSize = primary ? 12.0 : 11.0;
    final padding      = primary ? 20.0 : 16.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color:        Colors.white.withAlpha(primary ? 42 : 26),
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(
              color: Colors.white.withAlpha(primary ? 80 : 50),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:          onTap,
              borderRadius:   BorderRadius.circular(20),
              splashColor:    Colors.white.withAlpha(30),
              highlightColor: Colors.white.withAlpha(15),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Row(
                  children: [
                    // Contenedor del icono
                    Container(
                      width:  iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color:        iconColor,
                        borderRadius: BorderRadius.circular(iconRadius),
                        boxShadow: primary
                            ? [
                                BoxShadow(
                                  color:      iconColor.withAlpha(120),
                                  blurRadius: 14,
                                  offset:     const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(icon, color: Colors.white, size: iconSize),
                    ),
                    const SizedBox(width: 16),
                    // Texto
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize:    titleSize,
                              fontWeight:  FontWeight.w700,
                              color:       Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize:   subtitleSize,
                              color:      Colors.white.withAlpha(
                                  primary ? 185 : 155),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withAlpha(primary ? 140 : 110),
                      size:  primary ? 15 : 13,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Tarjeta de reanudación de reparto
// ═══════════════════════════════════════════

class _ResumeCard extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  const _ResumeCard({required this.onResume, required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color:        AppColors.warning.withAlpha(48),
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: AppColors.warning.withAlpha(130)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:          onResume,
              borderRadius:   BorderRadius.circular(20),
              splashColor:    AppColors.warning.withAlpha(50),
              highlightColor: AppColors.warning.withAlpha(25),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width:  52,
                      height: 52,
                      decoration: BoxDecoration(
                        color:        AppColors.warning,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color:      AppColors.warning.withAlpha(110),
                            blurRadius: 12,
                            offset:     const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size:  28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Continuar reparto',
                            style: TextStyle(
                              fontSize:    16,
                              fontWeight:  FontWeight.w700,
                              color:       Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Tienes un reparto en curso',
                            style: TextStyle(
                              fontSize: 12,
                              color:    Colors.white.withAlpha(175),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onDiscard,
                      child: Container(
                        width:  28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.white.withAlpha(200),
                          size:  15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
