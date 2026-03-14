import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../models/map_edit_models.dart';
import '../services/map_editor_service.dart';

// ── Utilidades de geometría ───────────────────────────────────────────────────

/// Ángulo en radianes desde el norte (sentido horario) entre dos coordenadas.
double _computeBearing(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLon = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return math.atan2(y, x);
}

/// Distancia cuadrática aproximada (grados²). Válida para búsqueda del nodo más cercano.
double _distSq(LatLng a, LatLng b) {
  final dlat = a.latitude - b.latitude;
  final dlon = a.longitude - b.longitude;
  return dlat * dlat + dlon * dlon;
}

/// Índice del nodo de [points] más cercano a [tap].
int _closestNodeIndex(List<LatLng> points, LatLng tap) {
  var minDist = double.infinity;
  var minIdx = 0;
  for (int i = 0; i < points.length; i++) {
    final d = _distSq(points[i], tap);
    if (d < minDist) {
      minDist = d;
      minIdx = i;
    }
  }
  return minIdx;
}

/// Devuelve el segmento (entre nodos de intersección) que contiene [nodeIdx].
/// Devuelve null si la vía no tiene intersecciones (no tiene tramos editables por separado).
SegmentRef? _segmentContaining(OsmWay way, int nodeIdx) {
  // El backend siempre incluye [0, last] en junctionIndices.
  // Solo hay tramos editables cuando existen nodos intermedios (length > 2).
  if (way.junctionIndices.length <= 2) return null;

  // junctionIndices ya contiene 0 y last: usarlo directamente como boundaries
  for (int i = 0; i < way.junctionIndices.length - 1; i++) {
    final start = way.junctionIndices[i];
    final end = way.junctionIndices[i + 1];
    if (nodeIdx >= start && nodeIdx <= end) {
      return (
        startRef: way.nodeRefs[start],
        endRef: way.nodeRefs[end],
      );
    }
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════
//  MapEditorScreen — editor nativo de red viaria
//
//  Flujo:
//    1. Carga vías del backend (GET /api/editor/geojson)
//    2. Renderiza polylines coloreadas por tipo de vía
//    3. Usuario toca una vía → bottom sheet con controles de edición
//    4. Cambios se acumulan localmente (Map<int, PendingWayChange>)
//    5. "Guardar cambios" → POST /api/editor/save → recarga mapa
// ═══════════════════════════════════════════════════════════════

class MapEditorScreen extends StatefulWidget {
  const MapEditorScreen({super.key});

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

// Estado posible del rebuild
enum _RebuildState { idle, running, ok, error }

class _MapEditorScreenState extends State<MapEditorScreen> {
  // ── Datos ──
  List<OsmWay> _ways = [];
  bool _loading = true;
  String? _loadError;

  // ── Estado de edición ──
  OsmWay? _selectedWay;
  final Map<int, PendingWayChange> _pending = {};

  // ── Estado de guardado ──
  bool _saving = false;

  // ── Estado de rebuild ──
  _RebuildState _rebuildState = _RebuildState.idle;
  String _rebuildMessage = '';
  // Indica que hay cambios guardados pendientes de rebuild
  bool _savedButNotRebuilt = false;

  // ── Mapa ──
  final _mapController = MapController();
  // LayerHitNotifier<T>: el valor se actualiza cuando el puntero toca una
  // polyline con hitValue. Lo leemos en onTap del GestureDetector externo.
  final LayerHitNotifier<OsmWay> _hitNotifier = LayerHitNotifier(null);

  // Centro inicial — Posadas, Córdoba
  static const _center = LatLng(37.805503, -5.099805);

  // ─────────────────────────────────────────────────
  //  Ciclo de vida
  // ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadWays();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────
  //  Carga de datos
  // ─────────────────────────────────────────────────

  Future<void> _loadWays() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final ways = await MapEditorService.getWays();
      if (!mounted) return;
      setState(() {
        _ways = ways;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  // ─────────────────────────────────────────────────
  //  Interacción con el mapa
  // ─────────────────────────────────────────────────

  void _onMapTap(LatLng tapCoord) {
    final hit = _hitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) {
      // Toque en zona sin vía → deseleccionar
      if (_selectedWay != null) setState(() => _selectedWay = null);
      return;
    }

    // La vía más cercana al toque está primera en hitValues
    final tapped = hit.hitValues.first;
    setState(() => _selectedWay = tapped);
    _showEditSheet(tapped, tapCoord);
  }

  // ─────────────────────────────────────────────────
  //  Bottom sheet de edición
  // ─────────────────────────────────────────────────

  void _showEditSheet(OsmWay way, LatLng tapCoord) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WayEditSheet(
        way: way,
        pendingChange: _pending[way.id],
        tappedSegment: _segmentContaining(way, _closestNodeIndex(way.points, tapCoord)),
        onApply: (change) {
          setState(() {
            _pending[way.id] = change;
            _selectedWay = null;
          });
          Navigator.pop(context);
        },
        onRevert: () {
          setState(() {
            _pending.remove(way.id);
            _selectedWay = null;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Guardar cambios
  // ─────────────────────────────────────────────────

  Future<void> _saveChanges() async {
    if (_pending.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await MapEditorService.saveChanges(_pending.values.toList());
      if (!mounted) return;
      setState(() {
        _pending.clear();
        _selectedWay = null;
        _saving = false;
        _savedButNotRebuilt = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cambios guardados. Lanza el rebuild para aplicarlos al routing.'),
          backgroundColor: AppColors.success,
        ),
      );
      // Recarga la red viaria para reflejar los cambios en el mapa
      await _loadWays();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────
  //  Rebuild del grafo de routing
  // ─────────────────────────────────────────────────

  Future<void> _confirmAndRebuild() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.construction_rounded, color: AppColors.warning, size: 22),
            SizedBox(width: 8),
            Text('Reconstruir mapa',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Este proceso tarda varios minutos y durante ese tiempo '
              'el routing no estará disponible.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 12),
            Text(
              'Pasos: extract → partition → customize → reinicio OSRM',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.construction_rounded, size: 18),
            label: const Text('Reconstruir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _startRebuild();
  }

  Future<void> _startRebuild() async {
    setState(() {
      _rebuildState = _RebuildState.running;
      _rebuildMessage = 'Iniciando rebuild…';
    });

    try {
      await MapEditorService.startRebuild();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rebuildState = _RebuildState.error;
        _rebuildMessage = e.toString();
      });
      return;
    }

    // Polling hasta que el rebuild termine
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!mounted) break;
      try {
        final status = await MapEditorService.getRebuildStatus();
        final serverStatus = status['status'] as String? ?? 'running';
        final msg = status['message'] as String? ?? '';

        setState(() => _rebuildMessage = msg);

        if (serverStatus == 'ok') {
          setState(() {
            _rebuildState = _RebuildState.ok;
            _savedButNotRebuilt = false;
          });
          break;
        } else if (serverStatus == 'error') {
          setState(() => _rebuildState = _RebuildState.error);
          break;
        }
        // Si sigue 'running', continuar polling
      } catch (_) {
        // Error de red puntual — seguir intentando
      }
    }
  }

  // ─────────────────────────────────────────────────
  //  Helpers de estilo
  // ─────────────────────────────────────────────────

  Color _wayColor(OsmWay way) {
    if (_selectedWay?.id == way.id) return const Color(0xFFFFC107); // ámbar
    if (_pending.containsKey(way.id)) return const Color(0xFFFF6F00); // naranja
    return _highwayBaseColor(way.highway);
  }

  double _wayWidth(OsmWay way) {
    final selected = _selectedWay?.id == way.id;
    if (selected) return 7;
    return switch (way.highway) {
      'motorway' || 'trunk' || 'primary' => 5,
      'secondary' || 'tertiary' => 4,
      'residential' || 'unclassified' || 'living_street' || 'road' => 3,
      'service' => 2.5,
      'footway' || 'pedestrian' || 'path' || 'steps' || 'cycleway' => 2,
      _ => 2.5,
    };
  }

  static Color _highwayBaseColor(String highway) => switch (highway) {
        'motorway' || 'motorway_link' || 'trunk' || 'trunk_link' =>
          const Color(0xFFE53935),  // rojo
        'primary' || 'primary_link' =>
          const Color(0xFFFF7043),  // naranja oscuro
        'secondary' || 'secondary_link' =>
          const Color(0xFFFFB300),  // ámbar
        'tertiary' || 'tertiary_link' =>
          const Color(0xFFAFB42B),  // oliva
        'residential' || 'living_street' || 'unclassified' || 'road' =>
          const Color(0xFF78909C),  // azul grisáceo
        'service' =>
          const Color(0xFFB0BEC5),  // azul grisáceo claro
        'footway' || 'pedestrian' || 'path' || 'steps' =>
          const Color(0xFF43A047),  // verde
        'cycleway' =>
          const Color(0xFF1E88E5),  // azul
        _ =>
          const Color(0xFF9E9E9E),  // gris
      };

  // ─────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar mapa'),
        actions: [
          if (_pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _saving ? null : _saveChanges,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded,
                        color: Colors.white, size: 20),
                label: Text(
                  'Guardar (${_pending.length})',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Banner de estado rebuild (visible cuando corresponde)
          if (_rebuildState != _RebuildState.idle || _savedButNotRebuilt)
            _buildRebuildBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando red viaria…',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadWays,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildMap();
  }

  Widget _buildMap() {
    // Una polyline por vía con hitValue adjunto
    final polylines = _ways
        .map(
          (way) => Polyline<OsmWay>(
            points: way.points,
            color: _wayColor(way),
            strokeWidth: _wayWidth(way),
            hitValue: way,
          ),
        )
        .toList();

    // Marcadores de sentido único: múltiples flechas rotadas por vía
    final onewayMarkers = _ways
        .where((w) => w.oneway != null)
        .expand(_buildOnewayMarkers)
        .toList();

    return FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: 14,
          minZoom: 11,
          maxZoom: 19,
          // onTap garantiza que _hitNotifier ya está actualizado cuando se dispara
          onTap: (_, latLng) => _onMapTap(latLng),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.posadas.repartir_app',
          ),
          PolylineLayer<OsmWay>(
            polylines: polylines,
            hitNotifier: _hitNotifier,
          ),
          if (onewayMarkers.isNotEmpty)
            MarkerLayer(markers: onewayMarkers),
          // Leyenda fija en esquina inferior izquierda
          const _MapLegendOverlay(),
        ],
    );
  }

  /// Genera una o varias flechas a lo largo de [way] con la orientación geográfica real.
  ///
  /// Coloca hasta 4 flechas distribuidas uniformemente. Cada flecha se rota según
  /// el bearing del segmento en que aparece. Para sentido '-1' (contrario al orden
  /// de nodos) se invierte el bearing 180°.
  List<Marker> _buildOnewayMarkers(OsmWay way) {
    final pts = way.points;
    if (pts.length < 2) return [];

    final isReverse = way.oneway == '-1';
    final n = pts.length;

    // Entre 1 y 4 flechas según longitud de la vía
    final numArrows = math.max(1, math.min(4, n ~/ 4));
    final step = math.max(1, (n - 1) ~/ numArrows);

    final markers = <Marker>[];
    // Empezamos en la mitad del primer intervalo para centrar visualmente
    for (int i = step ~/ 2; i < n - 1; i += step) {
      final from = isReverse ? pts[i + 1] : pts[i];
      final to = isReverse ? pts[i] : pts[i + 1];
      final bearing = _computeBearing(from, to);

      markers.add(Marker(
        point: pts[i],
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(172),
            shape: BoxShape.circle,
          ),
          child: Transform.rotate(
            angle: bearing,
            child: const Icon(
              Icons.arrow_upward_rounded,
              size: 14,
              color: Colors.white,
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  // ─────────────────────────────────────────────────
  //  Banner de estado del rebuild
  // ─────────────────────────────────────────────────

  Widget _buildRebuildBanner() {
    final (Color bg, Color fg, IconData icon, String title) = switch (_rebuildState) {
      _RebuildState.running => (
          const Color(0xFFFFF8E1),
          const Color(0xFFE65100),
          Icons.hourglass_top_rounded,
          'Reconstruyendo mapa…',
        ),
      _RebuildState.ok => (
          AppColors.successSurface,
          AppColors.success,
          Icons.check_circle_outline_rounded,
          'Mapa actualizado correctamente',
        ),
      _RebuildState.error => (
          AppColors.errorSurface,
          AppColors.error,
          Icons.error_outline_rounded,
          'Error en el rebuild',
        ),
      _ => (  // idle + savedButNotRebuilt
          const Color(0xFFFFF3E0),
          const Color(0xFFFF6F00),
          Icons.construction_rounded,
          'Cambios guardados — rebuild pendiente',
        ),
    };

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _rebuildState == _RebuildState.running
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: fg),
                )
              : Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: fg)),
                if (_rebuildMessage.isNotEmpty)
                  Text(_rebuildMessage,
                      style: TextStyle(
                          fontSize: 11, color: fg.withAlpha(200))),
              ],
            ),
          ),
          // Botón "Reconstruir" solo cuando es relevante
          if (_rebuildState == _RebuildState.idle && _savedButNotRebuilt)
            TextButton(
              onPressed: _confirmAndRebuild,
              style: TextButton.styleFrom(foregroundColor: fg),
              child: const Text('Reconstruir',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (_rebuildState == _RebuildState.error)
            TextButton(
              onPressed: _startRebuild,
              style: TextButton.styleFrom(foregroundColor: fg),
              child: const Text('Reintentar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (_rebuildState == _RebuildState.ok)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: fg,
              onPressed: () =>
                  setState(() => _rebuildState = _RebuildState.idle),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Bottom navigation — cambios pendientes o rebuild
  // ─────────────────────────────────────────────────

  Widget? _buildBottomNav() {
    // Hay cambios por guardar: mostrar barra de guardado
    if (_pending.isNotEmpty) return _buildBottomBar();

    // No hay cambios, pero sí hay rebuild pendiente: botón rebuild
    if (_savedButNotRebuilt && _rebuildState == _RebuildState.idle) {
      return _buildRebuildBar();
    }

    return null;
  }

  Widget _buildRebuildBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(18),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SizedBox(
        height: 44,
        child: ElevatedButton.icon(
          onPressed: _confirmAndRebuild,
          icon: const Icon(Icons.construction_rounded, size: 18),
          label: const Text('Reconstruir grafo de routing',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Bottom bar: resumen de cambios pendientes
  // ─────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(18),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF6F00).withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pending_actions_rounded,
                    size: 15, color: Color(0xFFFF6F00)),
                const SizedBox(width: 5),
                Text(
                  '${_pending.length} cambio${_pending.length > 1 ? 's' : ''} pendiente${_pending.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6F00)),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveChanges,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 17),
              label: Text(
                _saving ? 'Guardando…' : 'Guardar cambios',
                style: const TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  _WayEditSheet — panel de edición de una vía
// ═══════════════════════════════════════════════════════════════

class _WayEditSheet extends StatefulWidget {
  final OsmWay way;
  final PendingWayChange? pendingChange;
  /// Tramo de la vía donde el usuario tocó. Null si la vía no tiene intersecciones.
  final SegmentRef? tappedSegment;
  final ValueChanged<PendingWayChange> onApply;
  final VoidCallback onRevert;

  const _WayEditSheet({
    required this.way,
    required this.pendingChange,
    required this.tappedSegment,
    required this.onApply,
    required this.onRevert,
  });

  @override
  State<_WayEditSheet> createState() => _WayEditSheetState();
}

class _WayEditSheetState extends State<_WayEditSheet> {
  late String _highway;
  late String? _oneway;
  late TextEditingController _nameCtrl;
  // null = toda la vía; non-null = solo el tramo tocado
  late SegmentRef? _segment;

  // Tipos de vía editables (los más frecuentes en contexto urbano)
  static const _highwayOptions = [
    ('residential', 'Residencial'),
    ('service', 'Servicio / acceso'),
    ('tertiary', 'Terciaria'),
    ('secondary', 'Secundaria'),
    ('primary', 'Principal'),
    ('living_street', 'Zona 20 / patio'),
    ('unclassified', 'Sin clasificar'),
    ('footway', 'Peatonal'),
    ('pedestrian', 'Peatonal / plaza'),
    ('path', 'Camino'),
    ('cycleway', 'Carril bici'),
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.pendingChange;
    _highway = p?.highway ?? widget.way.highway;
    _oneway  = p?.oneway  ?? widget.way.oneway;

    final currentName = (p != null && p.nameChanged) ? p.name : widget.way.name;
    _nameCtrl = TextEditingController(text: currentName ?? '');

    // Si ya había una edición guardada, respetamos su alcance;
    // si no, pre-seleccionamos el tramo tocado cuando la vía tiene intersecciones.
    _segment = p?.segment ?? widget.tappedSegment;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final change = PendingWayChange(
      wayId: widget.way.id,
      originalHighway: widget.way.highway,
      originalOneway: widget.way.oneway,
      originalName: widget.way.name,
    );
    change.highway = _highway;
    change.oneway  = _oneway;
    change.segment = _segment;

    final newName = _nameCtrl.text.trim();
    final resolvedName = newName.isEmpty ? null : newName;
    change.name = resolvedName;
    change.nameChanged = resolvedName != widget.way.name;

    widget.onApply(change);
  }

  @override
  Widget build(BuildContext context) {
    final hasEdit = widget.pendingChange != null;
    final displayName = widget.way.name ?? '(sin nombre)';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Encabezado ───────────────────────────────
          Row(
            children: [
              const Icon(Icons.edit_road, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasEdit)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'editado',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFF6F00),
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'ID ${widget.way.id}  ·  ${widget.way.highway}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 20),

          // ── Nombre ───────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre de la calle',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),

          // ── Tipo de vía ──────────────────────────────
          const Text(
            'Tipo de vía',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _highwayOptions.any((t) => t.$1 == _highway)
                ? _highway
                : 'residential',
            items: _highwayOptions
                .map(
                  (t) => DropdownMenuItem(
                    value: t.$1,
                    child: Text(t.$2,
                        style: const TextStyle(fontSize: 14)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _highway = v!),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.signpost),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 16),

          // ── Sentido ──────────────────────────────────
          const Text(
            'Sentido de circulación',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _OnewayChip(
                label: '↔  Doble sentido',
                value: null,
                selected: _oneway == null,
                onTap: () => setState(() => _oneway = null),
              ),
              const SizedBox(width: 6),
              _OnewayChip(
                label: '→  Avance',
                value: 'yes',
                selected: _oneway == 'yes',
                onTap: () => setState(() => _oneway = 'yes'),
              ),
              const SizedBox(width: 6),
              _OnewayChip(
                label: '←  Retroceso',
                value: '-1',
                selected: _oneway == '-1',
                onTap: () => setState(() => _oneway = '-1'),
              ),
            ],
          ),
          // ── Alcance ──────────────────────────────────
          // Solo visible cuando la vía tiene intersecciones y hay tramo identificado
          if (widget.tappedSegment != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Alcance del cambio',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _OnewayChip(
                  label: 'Toda la vía',
                  value: null,
                  selected: _segment == null,
                  onTap: () => setState(() => _segment = null),
                ),
                const SizedBox(width: 6),
                _OnewayChip(
                  label: '✂  Solo este tramo',
                  value: 'segment',
                  selected: _segment != null,
                  onTap: () =>
                      setState(() => _segment = widget.tappedSegment),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // ── Botones de acción ────────────────────────
          Row(
            children: [
              if (hasEdit)
                OutlinedButton.icon(
                  onPressed: widget.onRevert,
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('Revertir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Aplicar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  _OnewayChip — selector de sentido
// ─────────────────────────────────────────────────

class _OnewayChip extends StatelessWidget {
  final String label;
  final String? value;
  final bool selected;
  final VoidCallback onTap;

  const _OnewayChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.scaffoldLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
              color: selected
                  ? Colors.white
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  _MapLegendOverlay — leyenda fija sobre el mapa
// ─────────────────────────────────────────────────

class _MapLegendOverlay extends StatelessWidget {
  const _MapLegendOverlay();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(230),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(25),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendRow(color: Color(0xFFE53935), label: 'Autovía / troncal'),
              _LegendRow(color: Color(0xFFFF7043), label: 'Principal'),
              _LegendRow(color: Color(0xFFFFB300), label: 'Secundaria'),
              _LegendRow(color: Color(0xFF78909C), label: 'Residencial'),
              _LegendRow(color: Color(0xFF43A047), label: 'Peatonal'),
              _LegendRow(color: Color(0xFFFFC107), label: 'Seleccionada'),
              _LegendRow(color: Color(0xFFFF6F00), label: 'Con cambios'),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
