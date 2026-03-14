"""
OSM Editor Service
==================
Reads posadas_editado.osm.pbf, serves GeoJSON for the map editor,
applies user changes (whole-way and sub-segment), saves back to PBF.

Key concepts:
  - junction_indices: positions in a way's node list where that node is
    shared by another highway way. These are the valid split points.
  - Segment change: edit only the slice of a way between two junction nodes.
    On save, the original way is split into sub-ways; tags are inherited by
    all sub-ways and overridden only for the edited segment.
  - Whole-way change: edit a way as a single unit (existing behaviour).
"""

import logging
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

DATA_DIR = Path(__file__).parent / "data"
PBF_PATH = DATA_DIR / "posadas_editado.osm.pbf"

# Highway tags treated as "car" (driveable by vehicles)
CAR_TYPES: frozenset[str] = frozenset({
    "motorway", "motorway_link", "trunk", "trunk_link",
    "primary", "primary_link", "secondary", "secondary_link",
    "tertiary", "tertiary_link", "residential", "unclassified",
    "service", "living_street", "road",
})

# Highway tags treated as "pedestrian" (non-driveable)
PED_TYPES: frozenset[str] = frozenset({
    "footway", "pedestrian", "path", "steps",
    "cycleway", "track", "bridleway",
})

# In-memory GeoJSON cache: (mtime_float, geojson_dict)
_cache: tuple[float, dict[str, Any]] | None = None


# ── Public API ────────────────────────────────────────────────────────────────

def get_geojson() -> dict[str, Any]:
    """Return all highway ways as a GeoJSON FeatureCollection.

    Result is cached in memory and invalidated when the PBF changes on
    disk (mtime check) or after apply_and_save() is called.
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
    changes: list[dict[str, Any]],
    node_changes: list[dict[str, Any]] | None = None,
    restriction_changes: list[dict[str, Any]] | None = None,
) -> None:
    """Apply tag changes to the PBF and overwrite posadas_editado.osm.pbf.

    Way change dict:
        id      (int)            — OSM way ID
        highway (str)            — new highway tag value
        oneway  (str|None)       — "yes" | "-1" | None (removes the tag)
        name    (str|None)       — new name | None (removes the tag)
        segment (dict|None)      — if present, only this slice is changed:
            start_node_ref (str) — ref of the first node in the segment
            end_node_ref   (str) — ref of the last node in the segment

    Node change dict:
        node_ref (str)           — OSM node ID
        barrier  (str|None)      — "bollard" | None (None removes the tag)
        access   (str|None)      — "no"      | None (None removes the tag)
    """
    global _cache

    if not changes and not node_changes and not restriction_changes:
        return

    # Separate whole-way changes from segment changes
    whole_changes: dict[int, dict[str, Any]] = {}
    seg_changes_by_way: dict[int, list[dict[str, Any]]] = defaultdict(list)

    for c in changes:
        way_id = int(c["id"])
        if c.get("segment"):
            seg_changes_by_way[way_id].append(c)
        else:
            whole_changes[way_id] = c

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        xml_path = tmp / "posadas.osm"
        new_pbf_path = tmp / "posadas_new.osm.pbf"

        _run_osmium(["cat", str(PBF_PATH), "-o", str(xml_path), "--overwrite"])

        ET.register_namespace("", "")
        tree = ET.parse(xml_path)
        root = tree.getroot()

        # ── Compute next available ID for new sub-ways ─────────────────────
        next_id = _next_available_id(root)

        # ── Process whole-way changes (existing behaviour) ─────────────────
        modified_whole = 0
        for way in root.findall("way"):
            way_id = int(way.get("id", 0))
            if way_id in whole_changes:
                _apply_tags_to_way(way, whole_changes[way_id])
                modified_whole += 1

        logger.info("Whole-way changes applied: %d", modified_whole)

        # ── Process segment changes (split + apply) ────────────────────────
        if seg_changes_by_way:
            next_id = _apply_segment_changes(root, seg_changes_by_way, next_id)

        # ── Process node changes (barrier / access tags) ────────────────────
        if node_changes:
            _apply_node_changes(root, node_changes)

        # ── Process restriction changes (turn restrictions) ─────────────────
        if restriction_changes:
            _apply_restriction_changes(root, restriction_changes, next_id)

        # ── Write XML → PBF → replace source ──────────────────────────────
        tree.write(str(xml_path), encoding="unicode", xml_declaration=True)
        _run_osmium(["cat", str(xml_path), "-o", str(new_pbf_path), "--overwrite"])
        shutil.move(str(new_pbf_path), str(PBF_PATH))

    _cache = None
    logger.info("PBF saved: %s", PBF_PATH)


# ── Node tag editing ─────────────────────────────────────────────────────────

def _apply_node_changes(root: ET.Element, node_changes: list[dict[str, Any]]) -> None:
    """Apply barrier / access tag changes to OSM nodes in place."""
    if not node_changes:
        return

    by_ref: dict[str, dict[str, Any]] = {c["node_ref"]: c for c in node_changes}

    for node in root.findall("node"):
        ref = node.get("id", "")
        if ref not in by_ref:
            continue

        change = by_ref[ref]

        # Remove any existing barrier and access tags
        for tag in [t for t in node.findall("tag") if t.get("k") in ("barrier", "access")]:
            node.remove(tag)

        if change.get("barrier"):
            t = ET.SubElement(node, "tag")
            t.set("k", "barrier")
            t.set("v", change["barrier"])

        if change.get("access"):
            t = ET.SubElement(node, "tag")
            t.set("k", "access")
            t.set("v", change["access"])

    logger.info("Node changes applied: %d", len(by_ref))


# ── Turn restriction relations ───────────────────────────────────────────────

def _apply_restriction_changes(
    root: ET.Element,
    restriction_changes: list[dict[str, Any]],
    next_id: int,
) -> int:
    """Add or remove OSM turn restriction relations."""
    for change in restriction_changes:
        from_id  = str(change["from_way_id"])
        via_ref  = str(change["via_node_ref"])
        to_id    = str(change["to_way_id"])
        restrict = bool(change.get("restrict", True))

        existing = _find_restriction_relation(root, from_id, via_ref, to_id)

        if restrict and existing is None:
            # Create new restriction relation
            rel = ET.SubElement(root, "relation")
            rel.set("id", str(next_id))
            rel.set("version", "1")
            next_id += 1

            from_m = ET.SubElement(rel, "member")
            from_m.set("type", "way"); from_m.set("ref", from_id); from_m.set("role", "from")
            via_m = ET.SubElement(rel, "member")
            via_m.set("type", "node"); via_m.set("ref", via_ref); via_m.set("role", "via")
            to_m = ET.SubElement(rel, "member")
            to_m.set("type", "way"); to_m.set("ref", to_id); to_m.set("role", "to")

            for k, v in [("type", "restriction"), ("restriction", "no_straight_on")]:
                t = ET.SubElement(rel, "tag"); t.set("k", k); t.set("v", v)

            logger.info("Restriction added: %s → %s → %s", from_id, via_ref, to_id)

        elif not restrict and existing is not None:
            root.remove(existing)
            logger.info("Restriction removed: %s → %s → %s", from_id, via_ref, to_id)

    return next_id


def _find_restriction_relation(
    root: ET.Element, from_id: str, via_ref: str, to_id: str
) -> ET.Element | None:
    """Return the restriction relation matching from/via/to, or None."""
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


# ── Segment split logic ───────────────────────────────────────────────────────

def _apply_segment_changes(
    root: ET.Element,
    seg_changes_by_way: dict[int, list[dict[str, Any]]],
    next_id: int,
) -> int:
    """Split ways that have segment changes and apply the new tags.

    Returns the updated next_id counter.
    """
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

        # Build a lookup: (start_ref, end_ref) → change dict
        change_map: dict[tuple[str, str], dict[str, Any]] = {}
        for c in seg_changes:
            seg = c["segment"]
            key = (seg["start_node_ref"], seg["end_node_ref"])
            change_map[key] = c

        # Collect all split indices (boundaries of all edited segments)
        split_refs: set[str] = set()
        for (sr, er) in change_map:
            split_refs.add(sr)
            split_refs.add(er)

        # Map each split ref to its index in nd_refs
        ref_to_idx: dict[str, int] = {ref: i for i, ref in enumerate(nd_refs)}
        split_indices = sorted(
            {ref_to_idx[r] for r in split_refs if r in ref_to_idx}
        )

        # Boundaries always include 0 and last
        boundaries: list[int] = sorted({0, *split_indices, len(nd_refs) - 1})

        # Collect original tags (all of them, preserving order)
        orig_tags: list[tuple[str, str]] = [
            (t.get("k", ""), t.get("v", "")) for t in way.findall("tag")
        ]

        # Build the sub-ways
        new_ways: list[ET.Element] = []
        id_for_piece: list[str] = []

        for i in range(len(boundaries) - 1):
            si = boundaries[i]
            ei = boundaries[i + 1]
            piece_refs = nd_refs[si : ei + 1]  # inclusive on both ends
            start_r = nd_refs[si]
            end_r = nd_refs[ei]

            # Determine tags for this piece
            matched_change = change_map.get((start_r, end_r))
            if matched_change is not None:
                piece_tags = _build_patched_tags(orig_tags, matched_change)
            else:
                piece_tags = list(orig_tags)

            # ID assignment: first piece keeps the original ID
            if i == 0:
                piece_id = way_id_str
            else:
                piece_id = str(next_id)
                next_id += 1

            id_for_piece.append(piece_id)
            new_ways.append(_make_sub_way(way, piece_id, piece_refs, piece_tags))

        # Replace original way in the tree
        parent = root  # <osm> is the direct parent of <way>
        way_index = list(root).index(way)
        root.remove(way)
        for j, nw in enumerate(new_ways):
            root.insert(way_index + j, nw)

        # Update relations that referenced the original way
        _update_relations_after_split(root, way_id_str, new_ways, nd_refs)

        logger.info(
            "Way %s split into %d sub-ways", way_id_str, len(new_ways)
        )

    return next_id


def _make_sub_way(
    original: ET.Element,
    new_id: str,
    nd_refs: list[str],
    tags: list[tuple[str, str]],
) -> ET.Element:
    """Create a new <way> element inheriting attributes from the original."""
    w = ET.Element("way")
    # Copy all attributes from original (version, timestamp, uid…) except id
    for k, v in original.attrib.items():
        if k != "id":
            w.set(k, v)
    w.set("id", new_id)

    for ref in nd_refs:
        nd = ET.SubElement(w, "nd")
        nd.set("ref", ref)

    for k, v in tags:
        tag = ET.SubElement(w, "tag")
        tag.set("k", k)
        tag.set("v", v)

    return w


def _build_patched_tags(
    orig_tags: list[tuple[str, str]],
    change: dict[str, Any],
) -> list[tuple[str, str]]:
    """Return a copy of orig_tags with the change applied."""
    # Start with all original tags
    result: dict[str, str] = dict(orig_tags)

    # highway: always overwrite
    if "highway" in change and change["highway"] is not None:
        result["highway"] = change["highway"]

    # oneway: remove if None, set if value
    if "oneway" in change:
        result.pop("oneway", None)
        if change["oneway"]:
            result["oneway"] = change["oneway"]

    # name: remove if None, set if value
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
    """Update relations that reference original_id to reference the new sub-ways.

    Turn restrictions: replace `from`/`to` member with the sub-way that
    contains the restriction's `via` node.
    Route/boundary relations: replace the original member with all sub-ways
    in order.
    """
    # Build lookup: nd_ref → sub-way id
    ref_to_new_id: dict[str, str] = {}
    for nw in new_ways:
        nw_id = nw.get("id", "")
        for nd in nw.findall("nd"):
            ref_to_new_id[nd.get("ref", "")] = nw_id

    for relation in root.findall("relation"):
        members = relation.findall("member")
        target_members = [
            m for m in members
            if m.get("type") == "way" and m.get("ref") == original_id
        ]
        if not target_members:
            continue

        rel_tags = {t.get("k"): t.get("v") for t in relation.findall("tag")}
        is_restriction = rel_tags.get("type") == "restriction"

        if is_restriction:
            # Find the via node
            via_nodes = [
                m.get("ref", "")
                for m in members
                if m.get("type") == "node" and m.get("role") == "via"
            ]
            via_ref = via_nodes[0] if via_nodes else ""

            for tm in target_members:
                # The correct sub-way is the one that contains the via node
                new_id = ref_to_new_id.get(via_ref)
                if new_id:
                    tm.set("ref", new_id)
                else:
                    # Fallback: use the first new sub-way
                    tm.set("ref", new_ways[0].get("id", original_id))

        else:
            # Route, boundary, etc.: replace member with all sub-ways in order
            for tm in target_members:
                idx = list(relation).index(tm)
                role = tm.get("role", "")
                relation.remove(tm)
                for j, nw in enumerate(new_ways):
                    new_member = ET.Element("member")
                    new_member.set("type", "way")
                    new_member.set("ref", nw.get("id", ""))
                    new_member.set("role", role)
                    relation.insert(idx + j, new_member)


def _next_available_id(root: ET.Element) -> int:
    """Return max existing element ID + 1 for assigning new way IDs."""
    max_id = max(
        (int(elem.get("id", 0)) for elem in root.iter() if elem.get("id")),
        default=1_000_000,
    )
    return max_id + 1


# ── Whole-way tag editing ─────────────────────────────────────────────────────

def _apply_tags_to_way(way: ET.Element, change: dict[str, Any]) -> None:
    """Mutate a <way> element's highway, oneway and name tags in place."""
    new_highway: str | None = change.get("highway")
    if new_highway is not None:
        for tag in way.findall("tag"):
            if tag.get("k") == "highway":
                tag.set("v", new_highway)
                break

    new_oneway: str | None = change.get("oneway")
    for tag in [t for t in way.findall("tag") if t.get("k") == "oneway"]:
        way.remove(tag)
    if new_oneway:
        tag = ET.SubElement(way, "tag")
        tag.set("k", "oneway")
        tag.set("v", new_oneway)

    if "name" in change:
        new_name: str | None = change.get("name")
        for tag in [t for t in way.findall("tag") if t.get("k") == "name"]:
            way.remove(tag)
        if new_name:
            tag = ET.SubElement(way, "tag")
            tag.set("k", "name")
            tag.set("v", new_name)


# ── GeoJSON generation ────────────────────────────────────────────────────────

def _parse_pbf_to_geojson() -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmpdir:
        xml_path = Path(tmpdir) / "posadas.osm"
        _run_osmium(["cat", str(PBF_PATH), "-o", str(xml_path), "--overwrite"])
        return _xml_to_geojson(xml_path)


def _xml_to_geojson(xml_path: Path) -> dict[str, Any]:
    """Parse OSM XML → GeoJSON FeatureCollection with junction metadata."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    # ── Node coordinates + tags ────────────────────────────────────────────
    nodes: dict[int, list[float]] = {}
    node_tags_map: dict[str, dict[str, str]] = {}
    for node in root.findall("node"):
        nid_str = node.get("id", "")
        nid_int = int(nid_str) if nid_str else 0
        nodes[nid_int] = [float(node.get("lon", 0)), float(node.get("lat", 0))]
        tags: dict[str, str] = {}
        for t in node.findall("tag"):
            k, v = t.get("k"), t.get("v")
            if k is not None and v is not None:
                tags[k] = v
        if tags:
            node_tags_map[nid_str] = tags

    # ── node_way_count: how many highway ways reference each node ──────────
    node_way_count: dict[str, int] = defaultdict(int)
    for way in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in way.findall("tag")}  # type: ignore[misc]
        if "highway" not in tags:
            continue
        for nd in way.findall("nd"):
            node_way_count[nd.get("ref", "")] += 1

    # ── Turn restrictions: from_way → {via_node → [to_way]} ───────────────
    # Used to expose existing restrictions per feature.
    restrictions_by_from: dict[str, dict[str, list[str]]] = defaultdict(
        lambda: defaultdict(list)
    )
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
            from_id, via_ref, to_id = froms[0], vias[0], tos[0]
            restrictions_by_from[from_id][via_ref].append(to_id)
            all_restrictions.append({"from_way_id": from_id, "via_node_ref": via_ref, "to_way_id": to_id})

    # ── Build features ─────────────────────────────────────────────────────
    features: list[dict[str, Any]] = []

    for way in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in way.findall("tag")}  # type: ignore[misc]
        highway = tags.get("highway")
        if not highway:
            continue

        nd_elements = way.findall("nd")
        nd_refs: list[str] = [nd.get("ref", "") for nd in nd_elements]

        coords: list[list[float]] = []
        for ref in nd_refs:
            ref_int = int(ref) if ref else 0
            if ref_int in nodes:
                coords.append(nodes[ref_int])

        if len(coords) < 2:
            continue

        # ── Junction indices ───────────────────────────────────────────────
        junction_indices: list[int] = [0]
        for i, ref in enumerate(nd_refs[1:-1], start=1):
            if node_way_count.get(ref, 0) > 1:
                junction_indices.append(i)
        last = len(nd_refs) - 1
        if junction_indices[-1] != last:
            junction_indices.append(last)

        # ── Barrier tags on this way's nodes ───────────────────────────────
        node_barriers: dict[str, str] = {}
        for ref in nd_refs:
            ntags = node_tags_map.get(ref, {})
            btype = _barrier_type(ntags)
            if btype:
                node_barriers[ref] = btype

        way_id = int(way.get("id", 0))
        oneway = tags.get("oneway")
        if oneway == "no":
            oneway = None

        # Restrictions FROM this way: {via_node_ref: [to_way_id, ...]}
        way_id_str = str(way_id)
        restrictions_from = {
            via: list(tos)
            for via, tos in restrictions_by_from.get(way_id_str, {}).items()
        }

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
                "restrictions_from": restrictions_from,
            },
        })

    # ── Global barrier_nodes list ─────────────────────────────────────────
    all_highway_refs: set[str] = {
        ref for f in features for ref in f["properties"]["node_refs"]
    }
    barrier_nodes: list[dict[str, Any]] = []
    for ref, ntags in node_tags_map.items():
        if ref not in all_highway_refs:
            continue
        btype = _barrier_type(ntags)
        if not btype:
            continue
        ref_int = int(ref) if ref else 0
        if ref_int in nodes:
            lon, lat = nodes[ref_int]
            barrier_nodes.append({"ref": ref, "lat": lat, "lon": lon, "type": btype})

    logger.info("Parsed %d highway ways, %d barrier nodes, %d restrictions from OSM XML",
                len(features), len(barrier_nodes), len(all_restrictions))
    return {
        "type": "FeatureCollection",
        "features":     features,
        "barrier_nodes": barrier_nodes,
        "restrictions":  all_restrictions,
    }


def _barrier_type(node_tags: dict[str, str]) -> str | None:
    """Return display barrier type for a node's tags, or None if no routing barrier."""
    barrier = node_tags.get("barrier", "")
    if barrier in ("bollard", "block", "jersey_barrier", "log", "planter"):
        return "bollard"
    if barrier in ("gate", "lift_gate", "swing_gate"):
        return "gate"
    if node_tags.get("access") == "no":
        return "noaccess"
    return None


# ── osmium wrapper ────────────────────────────────────────────────────────────

def _run_osmium(args: list[str]) -> None:
    cmd = ["osmium"] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"osmium {args[0]} failed:\n{result.stderr.strip()}")
