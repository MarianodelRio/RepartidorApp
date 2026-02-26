import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:typed_data';

import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/csv_data.dart';
import '../services/api_service.dart';
import '../services/csv_service.dart';
import '../services/persistence_service.dart';
import 'delivery_screen.dart';
import 'validation_review_screen.dart';

// ═══════════════════════════════════════════
//  Pantalla de importación
//
//  Flujo:
//    1. Subir CSV (cliente, direccion, ciudad[, nota, alias])
//    2. Validación automática → navega a ValidationReviewScreen
//    3. En ValidationReviewScreen: pin manual + calcular ruta
// ═══════════════════════════════════════════

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // ── Datos importados ──
  CsvData? _csvData;
  String _fileName = '';

  // ── Estado general ──
  bool _isCheckingServer = false;
  String? _error;
  bool _serverOnline = false;
  bool _hasActiveSession = false;

  @override
  void initState() {
    super.initState();
    _checkServer();
    _checkActiveSession();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  Servidor / Sesión
  // ═══════════════════════════════════════════

  Future<void> _checkActiveSession() async {
    final has = await PersistenceService.hasActiveSession();
    if (mounted) setState(() => _hasActiveSession = has);
  }

  Future<void> _discardSession() async {
    await PersistenceService.clearSession();
    if (mounted) setState(() => _hasActiveSession = false);
  }

  Future<void> _resumeDelivery() async {
    final session = await PersistenceService.loadSession();
    if (session == null || !mounted) return;
    Navigator.of(context)
        .push(
            MaterialPageRoute(builder: (_) => DeliveryScreen(session: session)))
        .then((_) => _checkActiveSession());
  }

  Future<void> _checkServer() async {
    setState(() => _isCheckingServer = true);
    final online = await ApiService.healthCheck();
    if (mounted) {
      setState(() {
        _serverOnline = online;
        _isCheckingServer = false;
      });
    }
  }

  void _showError(String msg) {
    if (mounted) setState(() => _error = msg);
  }

  // ═══════════════════════════════════════════
  //  Importar archivo
  // ═══════════════════════════════════════════

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) {
        _showError('No se pudo leer el archivo');
        return;
      }
      final csvData = CsvService.parse(Uint8List.fromList(file.bytes!));
      if (csvData.isEmpty) {
        _showError('El archivo está vacío o no tiene datos válidos');
        return;
      }

      setState(() {
        _csvData = csvData;
        _fileName = file.name;
        _error = null;
      });

      // Auto-trigger validación inmediatamente tras cargar el CSV
      await _validate();
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error al seleccionar archivo: $e');
    }
  }

  void _clearFile() {
    setState(() {
      _csvData = null;
      _fileName = '';
      _error = null;
    });
  }

  // ═══════════════════════════════════════════
  //  Validación automática
  // ═══════════════════════════════════════════

  Future<void> _validate() async {
    if (_csvData == null) return;

    if (!_serverOnline) {
      final online = await ApiService.healthCheck();
      if (mounted) setState(() => _serverOnline = online);
      if (!online) {
        _showError(
            'El servidor no está disponible. Verifica que el backend está activo en ${ApiConfig.baseUrl}');
        return;
      }
    }

    setState(() => _error = null);
    WakelockPlus.enable();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ValidationProgressDialog(),
    );

    try {
      final result = await ApiService.validationStart(csvData: _csvData!);
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar diálogo

      // Navegar a la pantalla de revisión
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ValidationReviewScreen(validationResult: result),
        ),
      );
      // Al volver, refrescar sesión activa por si se completó un reparto
      await _checkActiveSession();
    } on ApiException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e.message);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError('Error de validación: $e');
    } finally {
      WakelockPlus.disable();
    }
  }

  // ═══════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldLight,
      appBar: AppBar(
        title: const Text('Repartidor'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isCheckingServer
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : GestureDetector(
                    onTap: _checkServer,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle,
                            size: 10,
                            color: _serverOnline
                                ? AppColors.success
                                : AppColors.error),
                        const SizedBox(width: 4),
                        Text(_serverOnline ? 'Online' : 'Offline',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              if (_hasActiveSession) ...[
                _buildResumeCard(),
                const SizedBox(height: 16),
              ],
              if (_error != null) _buildErrorBanner(),
              _buildUploadSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Widgets de la UI
  // ═══════════════════════════════════════════

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset('assets/icon.png',
              width: 100, height: 100, fit: BoxFit.cover),
        ),
        const SizedBox(height: 14),
        const Text('Repartidor',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5)),
        const SizedBox(height: 4),
        const Text('Optimización de rutas de reparto',
            style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400)),
      ],
    );
  }

  Widget _buildResumeCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success, AppColors.success.withAlpha(200)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.success.withAlpha(60),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // ── Área principal tappable ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _resumeDelivery,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Continuar Ruta',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text(
                              'Tienes un reparto en curso. Toca para retomarlo.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
          // ── Botón X para descartar ──
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: _discardSession,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!,
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: Icon(Icons.close, size: 18, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadSection() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _csvData != null ? AppColors.success : AppColors.border,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Icon(
              _csvData != null ? Icons.check_circle : Icons.upload_file,
              size: 48,
              color: _csvData != null ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _csvData != null
                  ? 'Archivo cargado'
                  : 'Toca para importar CSV',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _csvData != null
                    ? AppColors.success
                    : AppColors.textPrimary,
              ),
            ),
            if (_csvData == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Formato: .csv (cliente, direccion, ciudad[, nota, alias])',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ),
            if (_csvData != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_fileName,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            if (_csvData != null)
              TextButton.icon(
                onPressed: _clearFile,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Cambiar archivo'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Diálogo de progreso de VALIDACIÓN
// ═══════════════════════════════════════════

class _ValidationProgressDialog extends StatefulWidget {
  const _ValidationProgressDialog();

  @override
  State<_ValidationProgressDialog> createState() =>
      _ValidationProgressDialogState();
}

class _ValidationProgressDialogState
    extends State<_ValidationProgressDialog> {
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _elapsedSeconds++);
      return mounted;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔍', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text('Validando direcciones…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Geocodificando con Google Maps…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text('Tiempo: ${_formatTime(_elapsedSeconds)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.screen_lock_portrait,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text('No cierres la app',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
