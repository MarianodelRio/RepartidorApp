"""
Map Editor Service
==================
Lee y escribe posadas_editado.osm.pbf, el mismo archivo que usa OSRM.
Sirve GeoJSON para el editor nativo de Flutter y persiste los cambios del
usuario de vuelta al PBF.

Conceptos clave:
  - junction_indices: posiciones en la lista de nodos de una vía donde ese
    nodo es compartido por otra vía. Son los puntos de corte válidos.
  - Cambio de segmento: editar solo el tramo entre dos nodos de intersección.
    En save, la vía original se parte en sub-vías; solo el segmento editado
    recibe los nuevos tags.
  - Cambio de vía completa: editar una vía como unidad.
"""

import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path
from typing import Any

from app.core.config import PBF_PATH
from app.core.logging import get_logger

logger = get_logger(__name__)

# ── Tipos de vía (usados para filtrar el GeoJSON) ─────────────────────────────

CAR_TYPES: frozenset[str] = frozenset({
    "motorway", "motorway_link", "trunk", "trunk_link",
    "primary", "primary_link", "secondary", "secondary_link",
    "tertiary", "tertiary_link", "residential", "unclassified",
    "service", "living_street", "road",
})

PED_TYPES: frozenset[str] = frozenset({
    "footway", "pedestrian", "path", "steps",
    "cycleway", "track", "bridleway",
})

# ── Caché en memoria: (mtime, geojson_dict) ───────────────────────────────────
_cache: tuple[float, dict[str, Any]] | None = None


# ── API pública ───────────────────────────────────────────────────────────────

def get_geojson() -> dict[str, Any]:
    """Devuelve todas las vías de carretera como FeatureCollection GeoJSON.

    El resultado se cachea en memoria y se invalida cuando el PBF cambia en
    disco (comprobación de mtime) o tras apply_and_save().
    """
    global _cache

    mtime = PBF_PATH.stat().st_mtime
    if _cache is not None and _cache[0] == mtime:
        return _cache[1]

    logger.info("Parsing PBF → GeoJSON (cache miss)")
    data = _parse_pbf_to_geojson()
    _cache = (mtime, data)
    return data


def apply_and_save(
    changes:             list[dict[str, Any]],
    node_changes:        list[dict[str, Any]] | None = None,
    restriction_changes: list[dict[str, Any]] | None = None,
) -> None:
    """Aplica cambios de tags al PBF y sobreescribe posadas_editado.osm.pbf.

    Formato de los dicts de cambio de vía:
        id      (int)  — ID de la vía OSM
        highway (str)  — nuevo valor del tag highway
        oneway  (str|None) — "yes" | "-1" | None (elimina el tag)
        name    (str|None) — nuevo nombre | None (elimina el tag)
        segment (dict|None) — si está presente, solo se edita ese tramo:
            start_node_ref (str)
            end_node_ref   (str)

    Formato de los dicts de cambio de nodo:
        node_ref (str)      — ID del nodo OSM
        barrier  (str|None) — "bollard" | None (elimina el tag)
        access   (str|None) — "no"      | None (elimina el tag)
    """
    global _cache

    if not changes and not node_changes and not restriction_changes:
        return

    whole_changes: dict[int, dict[str, Any]] = {}
    seg_changes_by_way: dict[int, list[dict[str, Any]]] = defaultdict(list)

    for c in changes:
        way_id = int(c["id"])
        if c.get("segment"):
            seg_changes_by_way[way_id].append(c)
        else:
            whole_changes[way_id] = c

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp        = Path(tmpdir)
        xml_path   = tmp / "posadas.osm"
        new_pbf    = tmp / "posadas_new.osm.pbf"

        _run_osmium(["cat", str(PBF_PATH), "-o", str(xml_path), "--overwrite"])

        ET.register_namespace("", "")
        tree = ET.parse(xml_path)
        root = tree.getroot()

        next_id = _next_available_id(root)

        # Cambios de vía completa
        modified_whole = 0
        for way in root.findall("way"):
            wid = int(way.get("id", 0))
            if wid in whole_changes:
                _apply_tags_to_way(way, whole_changes[wid])
                modified_whole += 1
        logger.info("Whole-way changes applied: %d", modified_whole)

        if seg_changes_by_way:
            next_id = _apply_segment_changes(root, seg_changes_by_way, next_id)

        if node_changes:
            _apply_node_changes(root, node_changes)

        if restriction_changes:
            _apply_restriction_changes(root, restriction_changes, next_id)

        tree.write(str(xml_path), encoding="unicode", xml_declaration=True)
        _run_osmium(["cat", str(xml_path), "-o", str(new_pbf), "--overwrite"])
        shutil.move(str(new_pbf), str(PBF_PATH))

    _cache = None
    logger.info("PBF guardado: %s", PBF_PATH)


# ── Cambios en nodos ──────────────────────────────────────────────────────────

def _apply_node_changes(
    root: ET.Element, node_changes: list[dict[str, Any]]
) -> None:
    by_ref: dict[str, dict[str, Any]] = {c["node_ref"]: c for c in node_changes}

    for node in root.findall("node"):
        ref = node.get("id", "")
        if ref not in by_ref:
            continue
        change = by_ref[ref]
        for tag in [t for t in node.findall("tag") if t.get("k") in ("barrier", "access")]:
            node.remove(tag)
        if change.get("barrier"):
            ET.SubElement(node, "tag", k="barrier", v=change["barrier"])
        if change.get("access"):
            ET.SubElement(node, "tag", k="access", v=change["access"])

    logger.info("Node changes applied: %d", len(by_ref))


# ── Restricciones de giro ─────────────────────────────────────────────────────

def _apply_restriction_changes(
    root: ET.Element,
    restriction_changes: list[dict[str, Any]],
    next_id: int,
) -> int:
    for change in restriction_changes:
        from_id  = str(change["from_way_id"])
        via_ref  = str(change["via_node_ref"])
        to_id    = str(change["to_way_id"])
        restrict = bool(change.get("restrict", True))

        existing = _find_restriction_relation(root, from_id, via_ref, to_id)

        if restrict and existing is None:
            rel = ET.SubElement(root, "relation", id=str(next_id), version="1")
            next_id += 1
            ET.SubElement(rel, "member", type="way",  ref=from_id, role="from")
            ET.SubElement(rel, "member", type="node", ref=via_ref,  role="via")
            ET.SubElement(rel, "member", type="way",  ref=to_id,    role="to")
            ET.SubElement(rel, "tag", k="type",        v="restriction")
            ET.SubElement(rel, "tag", k="restriction", v="no_straight_on")
            logger.info("Restriction added: %s → %s → %s", from_id, via_ref, to_id)

        elif not restrict and existing is not None:
            root.remove(existing)
            logger.info("Restriction removed: %s → %s → %s", from_id, via_ref, to_id)

    return next_id


def _find_restriction_relation(
    root: ET.Element, from_id: str, via_ref: str, to_id: str
) -> ET.Element | None:
    for rel in root.findall("relation"):
        rtags = {t.get("k"): t.get("v") for t in rel.findall("tag")}
        if rtags.get("type") != "restriction":
            continue
        members = rel.findall("member")
        froms = {m.get("ref") for m in members if m.get("role") == "from" and m.get("type") == "way"}
        vias  = {m.get("ref") for m in members if m.get("role") == "via"  and m.get("type") == "node"}
        tos   = {m.get("ref") for m in members if m.get("role") == "to"   and m.get("type") == "way"}
        if from_id in froms and via_ref in vias and to_id in tos:
            return rel
    return None


# ── Corte de segmentos ────────────────────────────────────────────────────────

def _apply_segment_changes(
    root: ET.Element,
    seg_changes_by_way: dict[int, list[dict[str, Any]]],
    next_id: int,
) -> int:
    ways_by_id: dict[str, ET.Element] = {
        w.get("id", ""): w for w in root.findall("way")
    }

    for way_id_int, seg_changes in seg_changes_by_way.items():
        way_id_str = str(way_id_int)
        way = ways_by_id.get(way_id_str)
        if way is None:
            logger.warning("Way %s not found for segment change — skipped", way_id_str)
            continue

        nd_refs = [nd.get("ref", "") for nd in way.findall("nd")]
        if len(nd_refs) < 2:
            logger.warning("Way %s has < 2 nodes — skipped", way_id_str)
            continue

        change_map: dict[tuple[str, str], dict[str, Any]] = {
            (c["segment"]["start_node_ref"], c["segment"]["end_node_ref"]): c
            for c in seg_changes
        }

        split_refs: set[str] = {r for pair in change_map for r in pair}
        ref_to_idx = {ref: i for i, ref in enumerate(nd_refs)}
        boundaries = sorted({0, *(ref_to_idx[r] for r in split_refs if r in ref_to_idx), len(nd_refs) - 1})

        orig_tags: list[tuple[str, str]] = [
            (t.get("k", ""), t.get("v", "")) for t in way.findall("tag")
        ]

        new_ways: list[ET.Element] = []
        for i in range(len(boundaries) - 1):
            si, ei = boundaries[i], boundaries[i + 1]
            piece_refs = nd_refs[si : ei + 1]
            matched = change_map.get((nd_refs[si], nd_refs[ei]))
            piece_tags = _build_patched_tags(orig_tags, matched) if matched else list(orig_tags)
            piece_id = way_id_str if i == 0 else str(next_id)
            if i > 0:
                next_id += 1
            new_ways.append(_make_sub_way(way, piece_id, piece_refs, piece_tags))

        way_index = list(root).index(way)
        root.remove(way)
        for j, nw in enumerate(new_ways):
            root.insert(way_index + j, nw)

        _update_relations_after_split(root, way_id_str, new_ways, nd_refs)
        logger.info("Way %s split into %d sub-ways", way_id_str, len(new_ways))

    return next_id


def _make_sub_way(
    original: ET.Element,
    new_id: str,
    nd_refs: list[str],
    tags: list[tuple[str, str]],
) -> ET.Element:
    w = ET.Element("way", {k: v for k, v in original.attrib.items() if k != "id"})
    w.set("id", new_id)
    for ref in nd_refs:
        ET.SubElement(w, "nd", ref=ref)
    for k, v in tags:
        ET.SubElement(w, "tag", k=k, v=v)
    return w


def _build_patched_tags(
    orig_tags: list[tuple[str, str]],
    change: dict[str, Any],
) -> list[tuple[str, str]]:
    """Devuelve una copia de orig_tags con el cambio aplicado."""
    result: dict[str, str] = dict(orig_tags)

    if change.get("highway") is not None:
        result["highway"] = change["highway"]

    if "oneway" in change:
        result.pop("oneway", None)
        if change["oneway"]:
            result["oneway"] = change["oneway"]

    if "name" in change:
        result.pop("name", None)
        if change["name"]:
            result["name"] = change["name"]

    return list(result.items())


def _update_relations_after_split(
    root: ET.Element,
    original_id: str,
    new_ways: list[ET.Element],
    original_nd_refs: list[str],
) -> None:
    ref_to_new_id: dict[str, str] = {
        nd.get("ref", ""): nw.get("id", "")
        for nw in new_ways
        for nd in nw.findall("nd")
    }

    for relation in root.findall("relation"):
        members = relation.findall("member")
        targets = [m for m in members if m.get("type") == "way" and m.get("ref") == original_id]
        if not targets:
            continue

        rel_tags = {t.get("k"): t.get("v") for t in relation.findall("tag")}
        is_restriction = rel_tags.get("type") == "restriction"

        if is_restriction:
            via_nodes = [
                m.get("ref", "")
                for m in members
                if m.get("type") == "node" and m.get("role") == "via"
            ]
            via_ref = via_nodes[0] if via_nodes else ""
            for tm in targets:
                tm.set("ref", ref_to_new_id.get(via_ref) or new_ways[0].get("id", original_id))
        else:
            for tm in targets:
                idx = list(relation).index(tm)
                role = tm.get("role", "")
                relation.remove(tm)
                for j, nw in enumerate(new_ways):
                    m = ET.Element("member", type="way", ref=nw.get("id", ""), role=role)
                    relation.insert(idx + j, m)


def _next_available_id(root: ET.Element) -> int:
    """Devuelve el ID máximo de los elementos del árbol + 1."""
    return max(
        (int(e.get("id", 0)) for e in root.iter() if e.get("id")),
        default=1_000_000,
    ) + 1


# ── Tags de vía completa ──────────────────────────────────────────────────────

def _apply_tags_to_way(way: ET.Element, change: dict[str, Any]) -> None:
    """Muta los tags highway, oneway y name de un elemento <way> in-place."""
    if change.get("highway") is not None:
        for tag in way.findall("tag"):
            if tag.get("k") == "highway":
                tag.set("v", change["highway"])
                break

    for tag in [t for t in way.findall("tag") if t.get("k") == "oneway"]:
        way.remove(tag)
    if change.get("oneway"):
        ET.SubElement(way, "tag", k="oneway", v=change["oneway"])

    if "name" in change:
        for tag in [t for t in way.findall("tag") if t.get("k") == "name"]:
            way.remove(tag)
        if change["name"]:
            ET.SubElement(way, "tag", k="name", v=change["name"])


# ── Generación de GeoJSON ─────────────────────────────────────────────────────

def _parse_pbf_to_geojson() -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmpdir:
        xml_path = Path(tmpdir) / "posadas.osm"
        _run_osmium(["cat", str(PBF_PATH), "-o", str(xml_path), "--overwrite"])
        return _xml_to_geojson(xml_path)


def _xml_to_geojson(xml_path: Path) -> dict[str, Any]:
    """Convierte OSM XML en un FeatureCollection GeoJSON con metadatos de intersección."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    # Coordenadas y tags de nodos
    nodes: dict[int, list[float]] = {}
    node_tags_map: dict[str, dict[str, str]] = {}
    for node in root.findall("node"):
        nid = node.get("id", "")
        nodes[int(nid)] = [float(node.get("lon", 0)), float(node.get("lat", 0))]
        tags = {t.get("k"): t.get("v") for t in node.findall("tag") if t.get("k") and t.get("v")}
        if tags:
            node_tags_map[nid] = tags  # type: ignore[assignment]

    # Cuántas vías de carretera referencian cada nodo (para detectar intersecciones)
    node_way_count: dict[str, int] = defaultdict(int)
    for way in root.findall("way"):
        if any(t.get("k") == "highway" for t in way.findall("tag")):
            for nd in way.findall("nd"):
                node_way_count[nd.get("ref", "")] += 1

    # Restricciones de giro agrupadas por vía origen
    restrictions_by_from: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    all_restrictions: list[dict[str, str]] = []
    for rel in root.findall("relation"):
        rtags = {t.get("k"): t.get("v") for t in rel.findall("tag")}
        if rtags.get("type") != "restriction":
            continue
        members = rel.findall("member")
        froms = [m.get("ref", "") for m in members if m.get("role") == "from" and m.get("type") == "way"]
        vias  = [m.get("ref", "") for m in members if m.get("role") == "via"  and m.get("type") == "node"]
        tos   = [m.get("ref", "") for m in members if m.get("role") == "to"   and m.get("type") == "way"]
        if froms and vias and tos:
            fid, via, tid = froms[0], vias[0], tos[0]
            restrictions_by_from[fid][via].append(tid)
            all_restrictions.append({"from_way_id": fid, "via_node_ref": via, "to_way_id": tid})

    # Features de vías
    features: list[dict[str, Any]] = []
    for way in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
        highway = tags.get("highway")
        if not highway:
            continue

        nd_refs = [nd.get("ref", "") for nd in way.findall("nd")]
        coords = [nodes[int(r)] for r in nd_refs if int(r) in nodes]
        if len(coords) < 2:
            continue

        # Índices de intersección (nodos compartidos con otras vías)
        junction_indices: list[int] = [0]
        for i, ref in enumerate(nd_refs[1:-1], start=1):
            if node_way_count.get(ref, 0) > 1:
                junction_indices.append(i)
        last = len(nd_refs) - 1
        if junction_indices[-1] != last:
            junction_indices.append(last)

        # Barreras en nodos de esta vía
        node_barriers: dict[str, str] = {}
        for ref in nd_refs:
            btype = _barrier_type(node_tags_map.get(ref, {}))
            if btype:
                node_barriers[ref] = btype

        way_id = int(way.get("id", 0))
        oneway = tags.get("oneway")
        if oneway == "no":
            oneway = None

        features.append({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": coords},
            "properties": {
                "id":                way_id,
                "name":              tags.get("name", ""),
                "highway":           highway,
                "oneway":            oneway,
                "node_refs":         nd_refs,
                "junction_indices":  junction_indices,
                "node_barriers":     node_barriers,
                "restrictions_from": {
                    via: list(tos)
                    for via, tos in restrictions_by_from.get(str(way_id), {}).items()
                },
            },
        })

    # Nodos barrera en la red viaria
    all_highway_refs = {ref for f in features for ref in f["properties"]["node_refs"]}
    barrier_nodes: list[dict[str, Any]] = []
    for ref, ntags in node_tags_map.items():
        if ref not in all_highway_refs:
            continue
        btype = _barrier_type(ntags)
        if not btype:
            continue
        ref_int = int(ref)
        if ref_int in nodes:
            lon, lat = nodes[ref_int]
            barrier_nodes.append({"ref": ref, "lat": lat, "lon": lon, "type": btype})

    logger.info(
        "Parsed %d highway ways, %d barrier nodes, %d restrictions",
        len(features), len(barrier_nodes), len(all_restrictions),
    )
    return {
        "type":          "FeatureCollection",
        "features":      features,
        "barrier_nodes": barrier_nodes,
        "restrictions":  all_restrictions,
    }


def _barrier_type(node_tags: dict[str, str]) -> str | None:
    """Devuelve el tipo de barrera de un nodo, o None si no bloquea el routing."""
    barrier = node_tags.get("barrier", "")
    if barrier in ("bollard", "block", "jersey_barrier", "log", "planter"):
        return "bollard"
    if barrier in ("gate", "lift_gate", "swing_gate"):
        return "gate"
    if node_tags.get("access") == "no":
        return "noaccess"
    return None


# ── Wrapper de osmium ─────────────────────────────────────────────────────────

def _run_osmium(args: list[str]) -> None:
    cmd = ["osmium", *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"osmium {args[0]} failed:\n{result.stderr.strip()}")
