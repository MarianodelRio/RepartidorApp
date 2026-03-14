import 'package:latlong2/latlong.dart';

// ─────────────────────────────────────────────────────────────
//  Modelos para el editor de mapa nativo
// ─────────────────────────────────────────────────────────────

/// Tipos de vía considerados vehiculares por OSRM.
const _carHighways = {
  'motorway', 'motorway_link', 'trunk', 'trunk_link',
  'primary', 'primary_link', 'secondary', 'secondary_link',
  'tertiary', 'tertiary_link', 'residential', 'unclassified',
  'service', 'living_street', 'road',
};

/// Tipos de vía peatonales (no enrutables por coche).
const _pedHighways = {
  'footway', 'pedestrian', 'path', 'steps',
  'cycleway', 'track', 'bridleway',
};

// ─────────────────────────────────────────────────────────────
//  OsmWay — una vía del grafo
// ─────────────────────────────────────────────────────────────

class OsmWay {
  final int id;
  final String highway;
  final String? oneway;   // "yes" | "-1" | null (bidireccional)
  final String? name;
  final List<LatLng> points;
  final List<String> nodeRefs;
  final List<int> junctionIndices;
  final Map<String, String> nodeBarriers; // nodeRef → tipo de barrera

  const OsmWay({
    required this.id,
    required this.highway,
    this.oneway,
    this.name,
    required this.points,
    required this.nodeRefs,
    required this.junctionIndices,
    required this.nodeBarriers,
  });

  factory OsmWay.fromGeoJson(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>;

    // GeoJSON: coordenadas en [lon, lat] → convertir a LatLng(lat, lon)
    final coords = (feature['geometry']['coordinates'] as List)
        .cast<List<dynamic>>()
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    final barriers = <String, String>{};
    (props['node_barriers'] as Map<String, dynamic>? ?? {})
        .forEach((k, v) => barriers[k] = v as String);

    final rawName = props['name'] as String?;

    return OsmWay(
      id: props['id'] as int,
      highway: props['highway'] as String? ?? 'unclassified',
      oneway: props['oneway'] as String?,
      name: (rawName == null || rawName.isEmpty) ? null : rawName,
      points: coords,
      nodeRefs: (props['node_refs'] as List).cast<String>(),
      junctionIndices: (props['junction_indices'] as List).cast<int>(),
      nodeBarriers: barriers,
    );
  }

  bool get isCar => _carHighways.contains(highway);
  bool get isPedestrian => _pedHighways.contains(highway);
  bool get isOneWay => oneway != null;
}

// ─────────────────────────────────────────────────────────────
//  PendingWayChange — cambio pendiente de guardar
// ─────────────────────────────────────────────────────────────

class PendingWayChange {
  final int wayId;

  // Valores originales (para poder revertir visualmente)
  final String originalHighway;
  final String? originalOneway;
  final String? originalName;

  // Valores editados
  String highway;
  String? oneway;       // null = bidireccional, "yes" = directo, "-1" = inverso
  String? name;         // null = sin nombre / eliminar tag
  bool nameChanged;     // true si el usuario tocó el campo nombre

  PendingWayChange({
    required this.wayId,
    required this.originalHighway,
    required this.originalOneway,
    required this.originalName,
  })  : highway = originalHighway,
        oneway = originalOneway,
        name = originalName,
        nameChanged = false;

  /// Serialización para el body del POST /api/editor/save
  Map<String, dynamic> toJson() => {
        'id': wayId,
        'highway': highway,
        'oneway': oneway,
        if (nameChanged) 'name': name,
      };
}
