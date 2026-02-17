import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_theme.dart';
import '../models/route_models.dart';

/// Widget de mapa con ruta, marcadores numerados y GPS en tiempo real.
///
/// Dos modos de uso:
///   • **Preview** (por defecto): Dibuja toda la polilínea de la ruta completa.
///   • **Delivery** (`deliveryMode: true`): Solo dibuja el segmento GPS → siguiente parada.
///     El segmento se pasa desde fuera via [segmentGeometry].
///     El marcador de la siguiente parada [nextStopIndex] se dibuja más grande.
class RouteMap extends StatefulWidget {
  final List<StopInfo> stops;
  final Map<String, dynamic> geometry;
  final int? highlightedStopIndex;
  final ValueChanged<int>? onMarkerTapped;
  final Set<int>? completedIndices;

  /// Modo reparto: no dibuja la polilínea completa, solo el segmento.
  final bool deliveryMode;

  /// Geometría GeoJSON del tramo actual (GPS → siguiente parada). Solo en deliveryMode.
  final Map<String, dynamic>? segmentGeometry;

  /// Índice de la siguiente parada (marcador destacado). Solo en deliveryMode.
  final int? nextStopIndex;

  const RouteMap({
    super.key,
    required this.stops,
    required this.geometry,
    this.highlightedStopIndex,
    this.onMarkerTapped,
    this.completedIndices,
    this.deliveryMode = false,
    this.segmentGeometry,
    this.nextStopIndex,
  });

  @override
  State<RouteMap> createState() => RouteMapState();
}

class RouteMapState extends State<RouteMap> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  LatLng? _currentPosition;
  bool _followGps = true;
  bool _gpsActive = false;

  /// Posición GPS actual expuesta para que DeliveryScreen pueda usarla.
  LatLng? get currentPosition => _currentPosition;

  @override
  void initState() {
    super.initState();
    _startGpsTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedStopIndex != oldWidget.highlightedStopIndex &&
        widget.highlightedStopIndex != null) {
      _flyToStop(widget.highlightedStopIndex!);
    }
    // Si cambiamos la siguiente parada en modo reparto, re-encuadrar GPS+destino.
    if (widget.deliveryMode &&
        widget.nextStopIndex != oldWidget.nextStopIndex) {
      // Pequeño delay para asegurar que _currentPosition esté actualizado si viene de fuera.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitGpsAndNextStop();
      });
    }
  }

  /// Centra el mapa en una parada específica.
  void flyToStop(int index) => _flyToStop(index);

  void _flyToStop(int index) {
    if (index < 0 || index >= widget.stops.length) return;
    final stop = widget.stops[index];
    _mapController.move(LatLng(stop.lat, stop.lon), 17.0);
    setState(() => _followGps = false);
  }

  /// Centra el mapa para ver toda la ruta.
  void fitRoute() {
    final bounds = _getRouteBounds();
    if (bounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
      setState(() => _followGps = false);
    }
  }

  /// Encuadra GPS actual + siguiente parada en un bounding box.
  /// Si no hay GPS, hace flyToStop del destino.
  void fitGpsAndNextStop() {
    final nextIdx = widget.nextStopIndex;
    if (nextIdx == null || nextIdx < 0 || nextIdx >= widget.stops.length) {
      fitRoute();
      return;
    }

    final stop = widget.stops[nextIdx];
    final destPoint = LatLng(stop.lat, stop.lon);

    if (_currentPosition == null) {
      // Sin GPS: centrar solo en el destino
      _mapController.move(destPoint, 16.0);
      setState(() => _followGps = false);
      return;
    }

    final gps = _currentPosition!;

    // Calcular bounding box que incluya GPS + destino
    final minLat = gps.latitude < destPoint.latitude ? gps.latitude : destPoint.latitude;
    final maxLat = gps.latitude > destPoint.latitude ? gps.latitude : destPoint.latitude;
    final minLon = gps.longitude < destPoint.longitude ? gps.longitude : destPoint.longitude;
    final maxLon = gps.longitude > destPoint.longitude ? gps.longitude : destPoint.longitude;

    final bounds = LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
      ),
    );
    setState(() => _followGps = false);
  }

  /// Centra el mapa en la posición GPS actual.
  void centerOnGps() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 17.0);
      setState(() => _followGps = true);
    }
  }

  Future<void> _startGpsTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      setState(() => _gpsActive = true);

      // Obtener posición inicial
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (mounted) {
          setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));
        }
      } catch (_) {}

      // Stream continuo de posición (optimizado para batería 8-10h)
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 15, // Actualizar cada 15 metros (ahorro ~60% batería)
        ),
      ).listen((pos) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(pos.latitude, pos.longitude);
          });
          // En modo reparto siempre mostrar el recuadro que encuadra GPS + siguiente parada.
          if (widget.deliveryMode) {
            fitGpsAndNextStop();
          } else if (_followGps) {
            _mapController.move(_currentPosition!, _mapController.camera.zoom);
          }
        }
      });
    } catch (_) {}
  }

  LatLngBounds? _getRouteBounds() {
    final coords = widget.geometry['coordinates'] as List?;
    if (coords == null || coords.isEmpty) return null;

    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final c in coords) {
      final lon = (c as List)[0] as num;
      final lat = c[1] as num;
      if (lat < minLat) minLat = lat.toDouble();
      if (lat > maxLat) maxLat = lat.toDouble();
      if (lon < minLon) minLon = lon.toDouble();
      if (lon > maxLon) maxLon = lon.toDouble();
    }

    return LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
  }

  /// Convierte el segmento GeoJSON (GPS → siguiente parada) a puntos.
  List<LatLng> _getSegmentPolyline() {
    final geo = widget.segmentGeometry;
    if (geo == null) return [];
    final coords = geo['coordinates'] as List?;
    if (coords == null) return [];
    return coords.map((c) {
      final list = c as List;
      return LatLng((list[1] as num).toDouble(), (list[0] as num).toDouble());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Preview: solo marcadores, sin polilínea.
    // Delivery: dibuja el segmento GPS → siguiente parada.
    final List<LatLng> polylinePoints;
    final Color polyColor;
    if (widget.deliveryMode) {
      polylinePoints = _getSegmentPolyline();
      polyColor = AppColors.polylineNav; // Azul eléctrico
    } else {
      // Preview limpio: sin camino, solo puntos
      polylinePoints = [];
      polyColor = Colors.transparent;
    }
    final bounds = _getRouteBounds();

    return Stack(
      children: [
        // ── Mapa ──
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: bounds != null
                ? LatLng(
                    (bounds.north + bounds.south) / 2,
                    (bounds.east + bounds.west) / 2,
                  )
                : const LatLng(37.802, -5.105),
            initialZoom: 15,
            onMapReady: () {
              if (bounds != null) {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(50),
                  ),
                );
              }
            },
          ),
          children: [
            // ── Tiles OSM ──
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.posadas.repartir_app',
              maxZoom: 19,
            ),

            // ── Polilínea de la ruta (completa o segmento) ──
            if (polylinePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  // Borde blanco
                  Polyline(
                    points: polylinePoints,
                    color: AppColors.polylineBorder,
                    strokeWidth: 10,
                  ),
                  // Línea principal azul eléctrico
                  Polyline(
                    points: polylinePoints,
                    color: polyColor,
                    strokeWidth: 6,
                  ),
                ],
              ),

            // ── Marcadores de paradas ──
            MarkerLayer(
              markers: _buildStopMarkers(),
            ),

            // ── Marcador GPS posición actual ──
            if (_currentPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition!,
                    width: 28,
                    height: 28,
                    child: const _GpsMarker(),
                  ),
                ],
              ),
          ],
        ),

        // Controles flotantes eliminados: el mapa en modo reparto siempre muestra
        // el recuadro que encuadra GPS + siguiente parada.
      ],
    );
  }

  List<Marker> _buildStopMarkers() {
    final completed = widget.completedIndices ?? <int>{};
    final isDelivery = widget.deliveryMode;
    final nextIdx = widget.nextStopIndex;

    return List.generate(widget.stops.length, (index) {
      final stop = widget.stops[index];
      final isOrigin = stop.isOrigin;
      final isHighlighted = widget.highlightedStopIndex == index;
      final isCompleted = completed.contains(index);
      final isNextStop = isDelivery && index == nextIdx;

      // En deliveryMode: siguiente parada grande, resto pequeños
      double size;
      if (isNextStop) {
        size = 50; // Significativamente más grande
      } else if (isHighlighted) {
        size = 44;
      } else if (isOrigin) {
        size = 40;
      } else if (isDelivery) {
        size = 24; // Más pequeños en modo reparto
      } else {
        size = 34;
      }

      return Marker(
        point: LatLng(stop.lat, stop.lon),
        width: size,
        height: size,
        child: GestureDetector(
          onTap: () => widget.onMarkerTapped?.call(index),
          child: _StopMarkerIcon(
            order: stop.order,
            isOrigin: isOrigin,
            isHighlighted: isHighlighted || isNextStop,
            isCompleted: isCompleted,
            isNextStop: isNextStop,
            isSmall: isDelivery && !isNextStop && !isOrigin && !isCompleted,
          ),
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════
//  Sub-widgets del mapa
// ═══════════════════════════════════════════

/// Marcador numerado para una parada.
class _StopMarkerIcon extends StatelessWidget {
  final int order;
  final bool isOrigin;
  final bool isHighlighted;
  final bool isCompleted;
  final bool isNextStop;
  final bool isSmall;

  const _StopMarkerIcon({
    required this.order,
    required this.isOrigin,
    required this.isHighlighted,
    this.isCompleted = false,
    this.isNextStop = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    // Tamaño del contenedor interno
    final double size;
    if (isNextStop) {
      size = 46.0;
    } else if (isSmall) {
      size = 20.0;
    } else if (isHighlighted) {
      size = 40.0;
    } else if (isOrigin) {
      size = 36.0;
    } else {
      size = 30.0;
    }

    Color bgColor;
    if (isCompleted) {
      bgColor = AppColors.markerCompleted; // Gris piedra para completadas
    } else if (isNextStop) {
      bgColor = AppColors.markerNext; // Azul profundo para siguiente parada
    } else if (isOrigin) {
      bgColor = AppColors.markerOrigin;
    } else if (isSmall) {
      bgColor = AppColors.markerCompleted.withAlpha(180); // Gris claro para las demás
    } else {
      bgColor = AppColors.markerDefault;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: isNextStop ? 3.5 : (isHighlighted ? 3 : 2),
        ),
        boxShadow: [
          BoxShadow(
            color: bgColor.withAlpha(isNextStop ? 180 : (isHighlighted ? 150 : 80)),
            blurRadius: isNextStop ? 16 : (isHighlighted ? 12 : 6),
            spreadRadius: isNextStop ? 4 : (isHighlighted ? 2 : 0),
          ),
        ],
      ),
      child: Center(
        child: isCompleted
            ? Icon(Icons.check, size: isSmall ? 12 : (isHighlighted ? 20 : 16), color: AppColors.markerCompletedCheck)
            : isOrigin
                ? Icon(Icons.home, size: isHighlighted ? 20 : 16, color: Colors.white)
                : isSmall
                    ? Text(
                        '$order',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      )
                    : Text(
                        '$order',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: isNextStop ? 20 : (isHighlighted ? 16 : 13),
                        ),
                      ),
      ),
    );
  }
}

/// Marcador de posición GPS actual con pulso animado.
class _GpsMarker extends StatefulWidget {
  const _GpsMarker();

  @override
  State<_GpsMarker> createState() => _GpsMarkerState();
}

class _GpsMarkerState extends State<_GpsMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gps.withAlpha(
              (40 * _animation.value).round(),
            ),
          ),
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gps,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gps.withAlpha(100),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Botón flotante sobre el mapa.
class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : (isDark ? AppColors.cardDark : Colors.white),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 22,
            color: isActive
                ? Colors.white
                : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
