import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';

/// Pantalla de selección de ubicación en el mapa.
///
/// El usuario toca cualquier punto del mapa para colocar un pin.
/// Al confirmar, hace pop con el [LatLng] seleccionado.
/// Al cancelar (botón X), hace pop con null.
class MapPickerScreen extends StatefulWidget {
  final String address;

  const MapPickerScreen({super.key, required this.address});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _center = LatLng(37.805503, -5.099805); // Taller Posadas

  LatLng? _selected;

  void _onMapTap(TapPosition _, LatLng latLng) {
    setState(() => _selected = latLng);
  }

  void _confirm() {
    if (_selected != null) {
      Navigator.of(context).pop(_selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Situar parada',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            Text(
              widget.address,
              style:
                  const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // ── Mapa ──────────────────────────────────────────────
          FlutterMap(
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_app',
              ),
              if (hasSelection)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 40,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        color: AppColors.error,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Instrucción flotante (arriba) ─────────────────────
          if (!hasSelection)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(30),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Toca el mapa para situar la parada',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Panel inferior con coordenadas y botón Confirmar ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: hasSelection
                  ? _ConfirmPanel(
                      key: const ValueKey('confirm'),
                      latLng: _selected!,
                      onConfirm: _confirm,
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Panel de confirmación ─────────────────────────────────────────

class _ConfirmPanel extends StatelessWidget {
  final LatLng latLng;
  final VoidCallback onConfirm;

  const _ConfirmPanel({super.key, required this.latLng, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 12,
              offset: const Offset(0, -3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coordenadas seleccionadas
          Row(
            children: [
              const Icon(Icons.location_on, size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lat: ${latLng.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary),
                  ),
                  Text(
                    'Lon: ${latLng.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Toca de nuevo\npara mover',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Botón Confirmar
          ElevatedButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar ubicación'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
