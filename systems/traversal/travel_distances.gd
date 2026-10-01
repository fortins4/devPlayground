class_name TravelDistances
extends RefCounted
## Overland travel day stubs between world regions (Leinster → Ireland).
##
## Design source: docs/MAP_SCALE.md (days/tiers) · docs/MAP_REGIONS.md (layout viz).
## Data only — no scene loads.
## Horse days are the primary graph; foot ≈ slower on the same edges.
## Game.current_region should use REGION_IDS values.

## Canonical region ids (slice + full roster). Depth varies per SCOPE.
const REGION_IDS: Array[StringName] = [
	&"leinster",
	&"wexford_waterford",
	&"dublin",
	&"wicklow_glendalough",
	&"midlands_bogs",
	&"clonmacnoise",
	&"munster_fringe",
	&"connacht",
	&"shannon",
]

## Display names for map UI / debug.
const REGION_DISPLAY: Dictionary = {
	&"leinster": "Laigin (Leinster)",
	&"wexford_waterford": "Wexford / Waterford coasts",
	&"dublin": "Áth Cliath (Dublin)",
	&"wicklow_glendalough": "Wicklow / Glendalough",
	&"midlands_bogs": "Midlands bogs",
	&"clonmacnoise": "Clonmacnoise corridor",
	&"munster_fringe": "Munster fringe (east)",
	&"connacht": "Connacht",
	&"shannon": "Shannon / river ways",
}

## Slice-dense regions (authored roam first).
const SLICE_REGIONS: Array[StringName] = [
	&"leinster",
]

## Horseback travel days for undirected edges (min days to commit a gate).
## Missing pair → no direct stub (route via another region).
const HORSE_DAYS: Dictionary = {
	&"leinster|wexford_waterford": 1,
	&"leinster|dublin": 2,
	&"leinster|wicklow_glendalough": 1,
	&"leinster|midlands_bogs": 2,
	&"leinster|munster_fringe": 3,
	&"wexford_waterford|dublin": 3,
	&"wexford_waterford|munster_fringe": 2,
	&"dublin|wicklow_glendalough": 1,
	&"dublin|midlands_bogs": 2,
	&"dublin|connacht": 5,
	&"midlands_bogs|clonmacnoise": 1,
	&"clonmacnoise|shannon": 0, # same-day river embark on horse
	&"clonmacnoise|connacht": 2,
	&"shannon|connacht": 2,
}

## Foot travel days (undirected). Longer than horse; used when mounted=false.
const FOOT_DAYS: Dictionary = {
	&"leinster|wexford_waterford": 2,
	&"leinster|dublin": 4,
	&"leinster|wicklow_glendalough": 2,
	&"leinster|midlands_bogs": 4,
	&"leinster|munster_fringe": 5,
	&"wexford_waterford|dublin": 6,
	&"wexford_waterford|munster_fringe": 4,
	&"dublin|wicklow_glendalough": 2,
	&"dublin|midlands_bogs": 3,
	&"dublin|connacht": 9,
	&"midlands_bogs|clonmacnoise": 2,
	&"clonmacnoise|shannon": 1,
	&"clonmacnoise|connacht": 4,
	&"shannon|connacht": 4,
}


static func is_known_region(region_id: StringName) -> bool:
	return region_id in REGION_IDS


static func display_name(region_id: StringName) -> String:
	return String(REGION_DISPLAY.get(region_id, String(region_id)))


static func _edge_key(a: StringName, b: StringName) -> StringName:
	var sa := String(a)
	var sb := String(b)
	if sa <= sb:
		return StringName("%s|%s" % [sa, sb])
	return StringName("%s|%s" % [sb, sa])


## Direct horse days between two regions, or -1 if no stub edge.
static func horse_days(from_region: StringName, to_region: StringName) -> int:
	if from_region == to_region:
		return 0
	var key := _edge_key(from_region, to_region)
	if not HORSE_DAYS.has(key):
		return -1
	return int(HORSE_DAYS[key])


## Direct foot days between two regions, or -1 if no stub edge.
static func foot_days(from_region: StringName, to_region: StringName) -> int:
	if from_region == to_region:
		return 0
	var key := _edge_key(from_region, to_region)
	if not FOOT_DAYS.has(key):
		return -1
	return int(FOOT_DAYS[key])


## Days for a mode: &"horse" (default) or &"foot". -1 if no edge.
static func travel_days(
	from_region: StringName,
	to_region: StringName,
	mode: StringName = &"horse"
) -> int:
	match mode:
		&"foot":
			return foot_days(from_region, to_region)
		_:
			return horse_days(from_region, to_region)


## Neighbours with a direct stub edge from region_id.
static func list_connections(region_id: StringName, mode: StringName = &"horse") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_known_region(region_id):
		return out
	for other in REGION_IDS:
		if other == region_id:
			continue
		var days := travel_days(region_id, other, mode)
		if days < 0:
			continue
		out.append({
			"to": other,
			"display_name": display_name(other),
			"days": days,
			"mode": String(mode),
		})
	return out


## BFS shortest path in horse-days (unweighted hops use day costs as edge weights).
## Returns {ok, days, path: Array[StringName]} or ok=false if unreachable.
static func shortest_horse_path(from_region: StringName, to_region: StringName) -> Dictionary:
	if not is_known_region(from_region) or not is_known_region(to_region):
		return {"ok": false, "reason": &"unknown_region", "days": -1, "path": []}
	if from_region == to_region:
		return {"ok": true, "days": 0, "path": [from_region]}
	# Dijkstra on small graph.
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var pending: Array[StringName] = []
	for id in REGION_IDS:
		dist[id] = 999999
		pending.append(id)
	dist[from_region] = 0
	while not pending.is_empty():
		var u: StringName = pending[0]
		var best_i := 0
		for i in pending.size():
			if int(dist[pending[i]]) < int(dist[u]):
				u = pending[i]
				best_i = i
		pending.remove_at(best_i)
		if u == to_region:
			break
		if int(dist[u]) >= 999999:
			break
		for conn in list_connections(u, &"horse"):
			var v: StringName = conn["to"]
			var alt := int(dist[u]) + int(conn["days"])
			if alt < int(dist[v]):
				dist[v] = alt
				prev[v] = u
	if int(dist.get(to_region, 999999)) >= 999999:
		return {"ok": false, "reason": &"unreachable", "days": -1, "path": []}
	var path: Array[StringName] = []
	var cur: StringName = to_region
	path.insert(0, cur)
	while cur != from_region:
		if not prev.has(cur):
			return {"ok": false, "reason": &"path_broken", "days": -1, "path": []}
		cur = prev[cur]
		path.insert(0, cur)
	return {"ok": true, "days": int(dist[to_region]), "path": path}


static func to_debug_dict() -> Dictionary:
	var edges: Array = []
	for key in HORSE_DAYS.keys():
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() != 2:
			continue
		var a := StringName(parts[0])
		var b := StringName(parts[1])
		edges.append({
			"a": String(a),
			"b": String(b),
			"horse_days": int(HORSE_DAYS[key]),
			"foot_days": foot_days(a, b),
		})
	return {
		"region_count": REGION_IDS.size(),
		"slice_regions": _names_to_strings(SLICE_REGIONS),
		"edge_count": HORSE_DAYS.size(),
		"edges": edges,
		"sample_leinster_to_dublin_horse": horse_days(&"leinster", &"dublin"),
		"sample_leinster_to_connacht_path": shortest_horse_path(&"leinster", &"connacht"),
	}


static func get_debug_text() -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== TravelDistances / map scale ===")
	lines.append("Regions: %d (slice: %s)" % [
		int(d["region_count"]),
		", ".join(PackedStringArray(d["slice_regions"])),
	])
	lines.append("Edges: %d  ·  leinster→dublin horse=%d d" % [
		int(d["edge_count"]),
		int(d["sample_leinster_to_dublin_horse"]),
	])
	var path_info: Dictionary = d["sample_leinster_to_connacht_path"]
	if path_info.get("ok", false):
		var hops: Array = []
		for p in path_info["path"]:
			hops.append(String(p))
		lines.append("leinster→connacht shortest: %d horse-days via %s" % [
			int(path_info["days"]),
			" → ".join(PackedStringArray(hops)),
		])
	lines.append("See docs/MAP_SCALE.md")
	return "\n".join(lines)


static func _names_to_strings(names: Array) -> Array:
	var out: Array = []
	for n in names:
		out.append(String(n))
	return out
