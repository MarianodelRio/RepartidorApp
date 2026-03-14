import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../models/map_edit_models.dart';
import '../services/map_editor_service.dart';

// ── Tipo interno: información de un segmento ──────────────────────────────────
typedef _SegInfo = ({
  int wayId,
  String startRef,
  String endRef,
  int startIdx,
  int endIdx,
});

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



// ═══════════════════════════════════════════════════════════════
//  MapEditorScreen — editor nativo de red viaria
//
//  Flujo (equivalente a osm_app):
//    1. Carga vías del backend (GET /api/editor/geojson)
//    2. Toca una vía → se selecciona; aparecen dots en los nodos interiores
//         · Gris  : nodo disponible para añadir punto de corte (toca para añadir)
//         · Naranja: punto de corte de usuario (toca para eliminar)
//         · Azul  : nodo de intersección con otra vía (toca para gestionar giros)
//         · Rojo  : nodo de intersección con restricción de giro activa
//    3. Al añadir puntos de corte, la vía se divide en segmentos coloreados
//    4. Toca un segmento → panel de edición de ese segmento
//    5. Barra inferior: "Editar toda la vía" cuando hay segmentos
//    6. Guardar → POST /api/editor/save → rebuild automático → recarga mapa
// ═══════════════════════════════════════════════════════════════

class MapEditorScreen extends StatefulWidget {
  const MapEditorScreen({super.key});

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

enum _RebuildState { idle, running, ok, error }

class _MapEditorScreenState extends State<MapEditorScreen> {
  // ── Datos ──
  List<OsmWay> _ways = [];
  bool _loading = true;
  String? _loadError;

  // ── Estado de selección ──
  OsmWay? _selectedWay;
  _SegInfo? _selectedSegment;

  // ── Puntos de corte definidos por usuario: wayId → Set<nodeIdx> ──
  // Equivalente a userSplitIndices en osm_app.
  final Map<int, Set<int>> _userSplits = {};

  // ── Cambios pendientes de vías/segmentos ──
  // Clave: "$wayId" para cambios de vía completa,
  //        "${wayId}_${startRef}_${endRef}" para cambios de segmento.
  final Map<String, PendingWayChange> _pending = {};

  // ── Cambios pendientes de restricciones de giro ──
  // Clave: "${fromWayId}_${viaNodeRef}_${toWayId}"
  final Map<String, PendingRestrictionChange> _restrictionChanges = {};

  // ── Índice nodeRef → vías que contienen ese nodo (para panel de restricciones) ──
  Map<String, List<OsmWay>> _nodeToWays = {};

  // ── Preview de sentido único (mientras el sheet está abierto) ──
  int?    _previewWayId;
  String? _previewOneway; // 'yes' | '-1' | null (doble sentido en preview)

  // ── Estado de guardado ──
  bool _saving = false;

  // ── Estado de rebuild ──
  _RebuildState _rebuildState = _RebuildState.idle;
  String _rebuildMessage = '';
  bool _savedButNotRebuilt = false;

  // ── Mapa ──
  final _mapController = MapController();
  final LayerHitNotifier<OsmWay> _hitNotifier = LayerHitNotifier(null);
  final LayerHitNotifier<_SegInfo> _segHitNotifier = LayerHitNotifier(null);

  /// Flag para evitar que un tap en un dot dispare también _onMapTap.
  bool _consumeNextMapTap = false;

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
        _nodeToWays = _buildNodeToWays(ways);
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
  //  Índice nodeRef → vías (para restricciones de giro)
  // ─────────────────────────────────────────────────

  static Map<String, List<OsmWay>> _buildNodeToWays(List<OsmWay> ways) {
    final map = <String, List<OsmWay>>{};
    for (final way in ways) {
      for (final ref in way.nodeRefs) {
        map.putIfAbsent(ref, () => []).add(way);
      }
    }
    return map;
  }

  // ─────────────────────────────────────────────────
  //  Lógica de segmentos (equivalente a computeSegments en osm_app)
  // ─────────────────────────────────────────────────

  /// Combina junction_indices automáticos con los puntos de corte del usuario
  /// para calcular los segmentos de una vía. Devuelve lista vacía si no hay
  /// divisiones internas (solo los dos extremos).
  List<_SegInfo> _computeSegments(OsmWay way) {
    final combined = {
      ...way.junctionIndices,
      ...(_userSplits[way.id] ?? <int>{}),
    }.toList()
      ..sort();

    if (combined.length <= 2) return [];

    final result = <_SegInfo>[];
    for (int i = 0; i < combined.length - 1; i++) {
      final si = combined[i];
      final ei = combined[i + 1];
      result.add((
        wayId: way.id,
        startRef: way.nodeRefs[si],
        endRef: way.nodeRefs[ei],
        startIdx: si,
        endIdx: ei,
      ));
    }
    return result;
  }

  /// Añade o elimina el nodo [nodeIdx] como punto de corte de usuario en [way].
  void _toggleUserSplit(OsmWay way, int nodeIdx) {
    _consumeNextMapTap = true; // el GestureDetector del dot también dispara onTap del mapa
    setState(() {
      final splits = _userSplits.putIfAbsent(way.id, () => {});
      if (splits.contains(nodeIdx)) {
        splits.remove(nodeIdx);
        if (splits.isEmpty) _userSplits.remove(way.id);
      } else {
        splits.add(nodeIdx);
      }
      // Si el segmento activo ya no existe, deseleccionarlo
      if (_selectedSegment != null) {
        final segs = _computeSegments(way);
        if (!segs.any((s) =>
            s.startRef == _selectedSegment!.startRef &&
            s.endRef == _selectedSegment!.endRef)) {
          _selectedSegment = null;
        }
      }
    });
  }

  // ─────────────────────────────────────────────────
  //  Helpers de clave para _pending
  // ─────────────────────────────────────────────────

  static String _pendingKey(int wayId, [SegmentRef? seg]) =>
      seg != null ? '${wayId}_${seg.startRef}_${seg.endRef}' : '$wayId';

  bool _wayHasPending(int wayId) {
    final prefix = '$wayId';
    return _pending.containsKey(prefix) ||
        _pending.keys.any((k) => k.startsWith('${prefix}_'));
  }

  // ─────────────────────────────────────────────────
  //  Interacción con el mapa
  // ─────────────────────────────────────────────────

  void _onMapTap(LatLng tapCoord) {
    if (_consumeNextMapTap) {
      _consumeNextMapTap = false;
      return;
    }

    // 1. ¿Se tocó un segmento de la vía seleccionada?
    final segHit = _segHitNotifier.value;
    if (segHit != null && segHit.hitValues.isNotEmpty) {
      final seg = segHit.hitValues.first;
      setState(() => _selectedSegment = seg);
      _showEditSheet(_selectedWay!, seg: seg);
      return;
    }

    // 2. ¿Se tocó una vía?
    final hit = _hitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) {
      if (_selectedWay != null) {
        setState(() {
          _selectedWay = null;
          _selectedSegment = null;
        });
      }
      return;
    }

    final tapped = hit.hitValues.first;

    // Misma vía sin segmentos → abrir panel de vía completa
    if (_selectedWay?.id == tapped.id) {
      if (_computeSegments(tapped).isEmpty) {
        _showEditSheet(tapped);
      }
      return;
    }

    // Nueva vía → seleccionar
    setState(() {
      _selectedWay = tapped;
      _selectedSegment = null;
    });
    // Sin segmentos → abrir panel directamente (comportamiento original)
    if (_computeSegments(tapped).isEmpty) {
      _showEditSheet(tapped);
    }
  }

  // ─────────────────────────────────────────────────
  //  Panel de edición
  // ─────────────────────────────────────────────────

  void _showEditSheet(OsmWay way, {_SegInfo? seg}) {
    final segRef = seg != null
        ? (startRef: seg.startRef, endRef: seg.endRef)
        : null;
    final key = _pendingKey(way.id, segRef);
    final segs = _computeSegments(way);
    final segIdx = seg != null
        ? segs.indexWhere(
            (s) => s.startRef == seg.startRef && s.endRef == seg.endRef)
        : -1;

    // Activar preview con el valor actual (pending si existe, si no el del way)
    final currentOneway = _pending[key]?.oneway ?? way.oneway;
    setState(() {
      _previewWayId  = way.id;
      _previewOneway = currentOneway;
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WayEditSheet(
        way: way,
        pendingChange: _pending[key],
        initialSegment: segRef,
        segIdx: segIdx,
        segTotal: segs.length,
        onPreview: (oneway) {
          if (mounted) setState(() => _previewOneway = oneway);
        },
        onApply: (change) {
          setState(() {
            final changeKey = _pendingKey(change.wayId, change.segment);
            _pending[changeKey] = change;
            _selectedSegment = null;
          });
          Navigator.pop(context);
        },
        onRevert: () {
          setState(() {
            // Eliminar todos los cambios de esta vía
            _pending.removeWhere(
              (k, _) =>
                  k == '${way.id}' || k.startsWith('${way.id}_'),
            );
            _selectedSegment = null;
          });
          Navigator.pop(context);
        },
      ),
    ).whenComplete(() {
      // Limpiar preview al cerrar el sheet (por cualquier vía)
      if (mounted) setState(() { _previewWayId = null; _previewOneway = null; });
    });
  }

  // ─────────────────────────────────────────────────
  //  Panel de restricciones de giro
  // ─────────────────────────────────────────────────

  void _showRestrictionSheet(
    OsmWay way,
    int nodeIdx,
    String nodeRef,
    List<OsmWay> connectedWays,
  ) {
    final existingRestrictions = way.restrictionsFrom[nodeRef]?.toSet() ?? {};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RestrictionSheet(
        way: way,
        nodeRef: nodeRef,
        connectedWays: connectedWays,
        existingRestrictions: existingRestrictions,
        pendingChanges: Map.of(_restrictionChanges),
        onApply: (changes) {
          setState(() {
            for (final change in changes) {
              _restrictionChanges[change.key] = change;
            }
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
    if ((_pending.isEmpty && _restrictionChanges.isEmpty) || _saving) return;
    setState(() => _saving = true);
    try {
      await MapEditorService.saveChanges(
        _pending.values.toList(),
        restrictionChanges: _restrictionChanges.values.toList(),
      );
      if (!mounted) return;
      setState(() {
        _pending.clear();
        _restrictionChanges.clear();
        _selectedWay = null;
        _selectedSegment = null;
        _userSplits.clear();
        _saving = false;
        _savedButNotRebuilt = false;
      });
      await _loadWays();
      if (!mounted) return;
      await _startRebuild();
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
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────────
  //  Helpers de estilo
  // ─────────────────────────────────────────────────

  Color _wayColor(OsmWay way) {
    if (_selectedWay?.id == way.id) return const Color(0xFFFFC107);
    if (_wayHasPending(way.id)) return const Color(0xFFFF6F00);
    return _highwayBaseColor(way.highway);
  }

  Color _segmentColor(_SegInfo seg) {
    final isSelected = _selectedSegment?.startRef == seg.startRef &&
        _selectedSegment?.endRef == seg.endRef;
    if (isSelected) return const Color(0xFFFFC107); // ámbar
    final key = _pendingKey(
        seg.wayId, (startRef: seg.startRef, endRef: seg.endRef));
    if (_pending.containsKey(key)) return const Color(0xFF22C55E); // verde
    return const Color(0xFF93C5FD); // azul claro
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
          const Color(0xFFE53935),
        'primary' || 'primary_link' => const Color(0xFFFF7043),
        'secondary' || 'secondary_link' => const Color(0xFFFFB300),
        'tertiary' || 'tertiary_link' => const Color(0xFFAFB42B),
        'residential' || 'living_street' || 'unclassified' || 'road' =>
          const Color(0xFF78909C),
        'service' => const Color(0xFFB0BEC5),
        'footway' || 'pedestrian' || 'path' || 'steps' =>
          const Color(0xFF43A047),
        'cycleway' => const Color(0xFF1E88E5),
        _ => const Color(0xFF9E9E9E),
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
    final mainPolylines = <Polyline<OsmWay>>[];
    final segPolylines = <Polyline<_SegInfo>>[];
    final splitDotMarkers = <Marker>[];
    final onewayMarkers = <Marker>[];

    for (final way in _ways) {
      final isSelected = _selectedWay?.id == way.id;

      if (isSelected) {
        final segs = _computeSegments(way);
        if (segs.isNotEmpty) {
          // Segmentos individuales reemplazan la polyline principal
          for (final seg in segs) {
            segPolylines.add(Polyline<_SegInfo>(
              points: way.points.sublist(seg.startIdx, seg.endIdx + 1),
              color: _segmentColor(seg),
              strokeWidth: _selectedSegment?.startRef == seg.startRef &&
                      _selectedSegment?.endRef == seg.endRef
                  ? 7
                  : 4,
              hitValue: seg,
            ));
          }
        } else {
          // Sin segmentos: vía completa resaltada
          mainPolylines.add(Polyline<OsmWay>(
            points: way.points,
            color: const Color(0xFFFFC107),
            strokeWidth: 7,
            hitValue: way,
          ));
        }
        // Dots de nodos para la vía seleccionada
        splitDotMarkers.addAll(_buildSplitDots(way));
      } else {
        mainPolylines.add(Polyline<OsmWay>(
          points: way.points,
          color: _wayColor(way),
          strokeWidth: _wayWidth(way),
          hitValue: way,
        ));
      }

      final isPreviewWay = _previewWayId == way.id;
      final displayOneway = isPreviewWay ? _previewOneway : way.oneway;
      if (displayOneway != null) {
        onewayMarkers.addAll(_buildOnewayMarkers(way,
            overrideOneway: displayOneway, isPreview: isPreviewWay));
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 14,
        minZoom: 11,
        maxZoom: 19,
        onTap: (_, latLng) => _onMapTap(latLng),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.posadas.repartir_app',
        ),
        PolylineLayer<OsmWay>(
          polylines: mainPolylines,
          hitNotifier: _hitNotifier,
        ),
        if (segPolylines.isNotEmpty)
          PolylineLayer<_SegInfo>(
            polylines: segPolylines,
            hitNotifier: _segHitNotifier,
          ),
        if (splitDotMarkers.isNotEmpty) MarkerLayer(markers: splitDotMarkers),
        if (onewayMarkers.isNotEmpty) MarkerLayer(markers: onewayMarkers),
        const _MapLegendOverlay(),
      ],
    );
  }

  /// Construye los marcadores de nodos para la vía seleccionada.
  ///
  /// · Rojo   — nodo de intersección con restricción de giro activa
  /// · Azul   — nodo de intersección interior (toca para gestionar restricciones)
  /// · Naranja — punto de corte de usuario (toca para eliminar)
  /// · Gris   — nodo interior disponible (toca para añadir como punto de corte)
  List<Marker> _buildSplitDots(OsmWay way) {
    final markers = <Marker>[];
    final jSet = way.junctionIndices.toSet();
    final uSet = _userSplits[way.id] ?? const <int>{};
    final last = way.points.length - 1;

    for (int i = 0; i < way.points.length; i++) {
      final isEndpoint = i == 0 || i == last;
      final isJunction = jSet.contains(i);
      final isUserSplit = uSet.contains(i);

      if (isJunction && !isEndpoint) {
        final nodeRef = way.nodeRefs[i];
        final connectedWays = (_nodeToWays[nodeRef] ?? [])
            .where((w) => w.id != way.id)
            .toList();
        if (connectedWays.isEmpty) continue; // nodo sin conexiones reales

        // Determinar si hay restricciones activas en este nodo
        final existingRestrictions =
            way.restrictionsFrom[nodeRef]?.toSet() ?? {};
        final pendingAdds = _restrictionChanges.values
            .where((r) =>
                r.fromWayId == way.id &&
                r.viaNodeRef == nodeRef &&
                r.restrict)
            .map((r) => '${r.toWayId}')
            .toSet();
        final pendingRemoves = _restrictionChanges.values
            .where((r) =>
                r.fromWayId == way.id &&
                r.viaNodeRef == nodeRef &&
                !r.restrict)
            .map((r) => '${r.toWayId}')
            .toSet();
        final effectiveRestrictions = {
          ...existingRestrictions,
          ...pendingAdds,
        }..removeAll(pendingRemoves);

        final hasRestriction = effectiveRestrictions.isNotEmpty;

        markers.add(Marker(
          point: way.points[i],
          width: 14,
          height: 14,
          child: GestureDetector(
            onTap: () {
              _consumeNextMapTap = true;
              _showRestrictionSheet(way, i, nodeRef, connectedWays);
            },
            child: Container(
              decoration: BoxDecoration(
                color: hasRestriction ? Colors.red.shade600 : Colors.blue.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ));
      } else if (!isEndpoint && !isJunction) {
        if (isUserSplit) {
          // Punto de corte de usuario — naranja (toca para eliminar)
          markers.add(Marker(
            point: way.points[i],
            width: 14,
            height: 14,
            child: GestureDetector(
              onTap: () => _toggleUserSplit(way, i),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ));
        } else {
          // Nodo disponible — gris pequeño (toca para añadir)
          markers.add(Marker(
            point: way.points[i],
            width: 10,
            height: 10,
            child: GestureDetector(
              onTap: () => _toggleUserSplit(way, i),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ));
        }
      }
    }
    return markers;
  }

  /// Genera flechas de sentido único distribuidas a lo largo de [way].
  /// [overrideOneway] reemplaza el valor real (usado para preview).
  /// [isPreview] usa color amber y tamaño mayor para indicar previsualización.
  List<Marker> _buildOnewayMarkers(OsmWay way,
      {required String overrideOneway, bool isPreview = false}) {
    final pts = way.points;
    if (pts.length < 2) return [];

    final isReverse = overrideOneway == '-1';
    final n = pts.length;
    final numArrows = math.max(1, math.min(4, n ~/ 4));
    final step = math.max(1, (n - 1) ~/ numArrows);

    final bgColor = isPreview
        ? AppColors.warning.withAlpha(220)
        : Colors.black.withAlpha(172);
    final size = isPreview ? 26.0 : 22.0;
    final iconSize = isPreview ? 17.0 : 14.0;

    final markers = <Marker>[];
    for (int i = step ~/ 2; i < n - 1; i += step) {
      final from = isReverse ? pts[i + 1] : pts[i];
      final to = isReverse ? pts[i] : pts[i + 1];
      final bearing = _computeBearing(from, to);

      markers.add(Marker(
        point: pts[i],
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Transform.rotate(
            angle: bearing,
            child: Icon(
              Icons.arrow_upward_rounded,
              size: iconSize,
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
    final (Color bg, Color fg, IconData icon, String title) =
        switch (_rebuildState) {
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
      _ => (
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
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: fg),
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
                      style:
                          TextStyle(fontSize: 11, color: fg.withAlpha(200))),
              ],
            ),
          ),
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
  //  Bottom navigation
  // ─────────────────────────────────────────────────

  Widget? _buildBottomNav() {
    if (_pending.isNotEmpty) return _buildBottomBar();
    if (_savedButNotRebuilt && _rebuildState == _RebuildState.idle) {
      return _buildRebuildBar();
    }
    // Vía seleccionada con segmentos → barra de selección
    if (_selectedWay != null &&
        _computeSegments(_selectedWay!).isNotEmpty) {
      return _buildSelectionBar();
    }
    return null;
  }

  /// Barra inferior cuando hay una vía seleccionada con segmentos.
  /// Permite editar la vía completa o ver el conteo de segmentos.
  Widget _buildSelectionBar() {
    final segs = _computeSegments(_selectedWay!);
    final wayName = _selectedWay!.name ?? 'ID ${_selectedWay!.id}';
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wayName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${segs.length} tramo${segs.length > 1 ? 's' : ''} — toca uno para editar',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: () => _showEditSheet(_selectedWay!),
              icon: const Icon(Icons.edit_road, size: 16),
              label: const Text('Toda la vía',
                  style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildBottomBar() {
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
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFFF6F00).withAlpha(80)),
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
//  _WayEditSheet — panel de edición de una vía o segmento
// ═══════════════════════════════════════════════════════════════

class _WayEditSheet extends StatefulWidget {
  final OsmWay way;
  final PendingWayChange? pendingChange;
  /// Segmento pre-seleccionado (de haber tocado un segmento específico).
  final SegmentRef? initialSegment;
  /// Índice del segmento dentro del total (-1 si no aplica).
  final int segIdx;
  final int segTotal;
  final void Function(String?)? onPreview;
  final ValueChanged<PendingWayChange> onApply;
  final VoidCallback onRevert;

  const _WayEditSheet({
    required this.way,
    required this.pendingChange,
    required this.initialSegment,
    required this.segIdx,
    required this.segTotal,
    this.onPreview,
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
  late SegmentRef? _segment;

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
    _oneway = p?.oneway ?? widget.way.oneway;
    final currentName =
        (p != null && p.nameChanged) ? p.name : widget.way.name;
    _nameCtrl = TextEditingController(text: currentName ?? '');
    _segment = p?.segment ?? widget.initialSegment;
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
    change.oneway = _oneway;
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
    final isSegment = widget.segIdx >= 0;

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
              Icon(
                isSegment ? Icons.content_cut_rounded : Icons.edit_road,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isSegment)
                      Text(
                        'Tramo ${widget.segIdx + 1} de ${widget.segTotal}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ),
              if (hasEdit)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('editado',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFF6F00),
                          fontWeight: FontWeight.w600)),
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
          const Text('Tipo de vía',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _highwayOptions.any((t) => t.$1 == _highway)
                ? _highway
                : 'residential',
            items: _highwayOptions
                .map((t) => DropdownMenuItem(
                      value: t.$1,
                      child: Text(t.$2,
                          style: const TextStyle(fontSize: 14)),
                    ))
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
          const Text('Sentido de circulación',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _OnewayChip(
                label: '↔  Doble sentido',
                value: null,
                selected: _oneway == null,
                onTap: () {
                  setState(() => _oneway = null);
                  widget.onPreview?.call(null);
                },
              ),
              const SizedBox(width: 6),
              _OnewayChip(
                label: '→  Normal',
                value: 'yes',
                selected: _oneway == 'yes',
                onTap: () {
                  setState(() => _oneway = 'yes');
                  widget.onPreview?.call('yes');
                },
              ),
              const SizedBox(width: 6),
              _OnewayChip(
                label: '←  Invertido',
                value: '-1',
                selected: _oneway == '-1',
                onTap: () {
                  setState(() => _oneway = '-1');
                  widget.onPreview?.call('-1');
                },
              ),
            ],
          ),

          // ── Alcance del cambio ───────────────────────
          // Solo visible cuando se editó desde un segmento concreto
          if (widget.initialSegment != null) ...[
            const SizedBox(height: 16),
            const Text('Alcance del cambio',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
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
                      setState(() => _segment = widget.initialSegment),
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

// ═══════════════════════════════════════════════════════════════
//  _RestrictionSheet — panel de restricciones de giro en un nodo
// ═══════════════════════════════════════════════════════════════

class _RestrictionSheet extends StatefulWidget {
  final OsmWay way;
  final String nodeRef;
  final List<OsmWay> connectedWays;
  final Set<String> existingRestrictions; // toWayId como String
  final Map<String, PendingRestrictionChange> pendingChanges;
  final ValueChanged<List<PendingRestrictionChange>> onApply;

  const _RestrictionSheet({
    required this.way,
    required this.nodeRef,
    required this.connectedWays,
    required this.existingRestrictions,
    required this.pendingChanges,
    required this.onApply,
  });

  @override
  State<_RestrictionSheet> createState() => _RestrictionSheetState();
}

class _RestrictionSheetState extends State<_RestrictionSheet> {
  /// restricted[wayId] = true → no se puede girar hacia esa vía
  late Map<int, bool> _restricted;

  @override
  void initState() {
    super.initState();
    _restricted = {};
    for (final w in widget.connectedWays) {
      final key =
          PendingRestrictionChange(
            fromWayId: widget.way.id,
            viaNodeRef: widget.nodeRef,
            toWayId: w.id,
            restrict: true,
          ).key;
      // Estado efectivo: existente + cambios pendientes
      final existingRestricted =
          widget.existingRestrictions.contains('${w.id}');
      final pending = widget.pendingChanges[key];
      if (pending != null) {
        _restricted[w.id] = pending.restrict;
      } else {
        _restricted[w.id] = existingRestricted;
      }
    }
  }

  void _apply() {
    final changes = <PendingRestrictionChange>[];
    for (final w in widget.connectedWays) {
      final isRestricted = _restricted[w.id] ?? false;
      final wasRestricted =
          widget.existingRestrictions.contains('${w.id}');
      // Solo generar cambio si difiere del estado base Y del pendiente previo
      final pendingKey = PendingRestrictionChange(
        fromWayId: widget.way.id,
        viaNodeRef: widget.nodeRef,
        toWayId: w.id,
        restrict: isRestricted,
      ).key;
      final prevPending = widget.pendingChanges[pendingKey];
      final effectiveBase = prevPending?.restrict ?? wasRestricted;
      if (isRestricted != effectiveBase) {
        changes.add(PendingRestrictionChange(
          fromWayId: widget.way.id,
          viaNodeRef: widget.nodeRef,
          toWayId: w.id,
          restrict: isRestricted,
        ));
      }
    }
    widget.onApply(changes);
  }

  @override
  Widget build(BuildContext context) {
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
          // Handle
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

          // Encabezado
          const Row(
            children: [
              Icon(Icons.do_not_disturb_on_rounded,
                  color: AppColors.error, size: 20),
              SizedBox(width: 8),
              Text(
                'Restricciones de giro',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Desde ${widget.way.name ?? 'ID ${widget.way.id}'} en nodo ${widget.nodeRef}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Activa las vías hacia las que NO se puede girar.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Lista de vías conectadas
          ...widget.connectedWays.map((w) {
            final isRestricted = _restricted[w.id] ?? false;
            final label = w.name ?? 'ID ${w.id}  (${w.highway})';
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(w.highway,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
              value: isRestricted,
              activeColor: AppColors.error,
              onChanged: (v) =>
                  setState(() => _restricted[w.id] = v ?? false),
            );
          }),
          const SizedBox(height: 16),

          // Botones
          Row(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
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
//  _OnewayChip — selector genérico de opción
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
            color: selected ? AppColors.primary : AppColors.scaffoldLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
              color:
                  selected ? Colors.white : AppColors.textSecondary,
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
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              _LegendRow(color: Color(0xFF93C5FD), label: 'Tramo disponible'),
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
