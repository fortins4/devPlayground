extends Node
## Town / settlement NPC crowd presence stub (density + tier API).
##
## Data: systems/crowd/crowd_sites.gd (CrowdSites). Visuals bind later via
## get_density / get_tier / get_effective_density + density_changed / tier_changed.
## No crowd AI, pathfinding, or scene spawns — presence numbers only.
##
## Soft optional: WorldClock season (get_season_id) and day_advanced / season_changed
## when present on a merged branch. Absent season → effective density == stored.

signal density_changed(site_id: StringName, density: float, previous: float)
signal tier_changed(site_id: StringName, tier: int, previous: int)
signal site_registered(site_id: StringName)
## Fired after day/season soft hooks so visuals can re-sample effective density.
signal presence_refreshed(reason: StringName)

## site_id → current density 0..1 (seeded from CrowdSites.base_density).
var _densities: Dictionary = {}

## Runtime-registered extras (id → metadata dict); seeded sites stay in CrowdSites.
var _runtime_sites: Dictionary = {}

## Last set / register payload for Remote / HUD.
var last_result: Dictionary = {}

## HUD poll flag (mirrors WorldClock / Honor / Rumors / TravelGate).
var debug_visible: bool = false

## When true, get_effective_density applies soft season bias if WorldClock exposes season.
var season_bias_enabled: bool = true


func _ready() -> void:
	_seed_from_sites()
	_connect_world_clock_soft()


func _seed_from_sites() -> void:
	_densities.clear()
	for sid in CrowdSites.SITE_IDS:
		_densities[sid] = CrowdSites.base_density(sid)


func _connect_world_clock_soft() -> void:
	if WorldClock == null:
		return
	if WorldClock.has_signal("day_advanced"):
		if not WorldClock.day_advanced.is_connected(_on_day_advanced):
			WorldClock.day_advanced.connect(_on_day_advanced)
	if WorldClock.has_signal("season_changed"):
		if not WorldClock.season_changed.is_connected(_on_season_changed):
			WorldClock.season_changed.connect(_on_season_changed)


func _on_day_advanced(_day: int) -> void:
	# Soft hook — no stored mutation; visuals rebind via presence_refreshed.
	presence_refreshed.emit(&"day_advanced")


func _on_season_changed(_season: Variant, _previous: Variant) -> void:
	presence_refreshed.emit(&"season_changed")


# --- Query / list -------------------------------------------------------------

func list_site_ids() -> Array[StringName]:
	var out: Array[StringName] = CrowdSites.list_site_ids()
	for rid in _runtime_sites.keys():
		var id: StringName = rid
		if id not in out:
			out.append(id)
	return out


func list_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = CrowdSites.list_sites()
	for rid in _runtime_sites.keys():
		out.append((_runtime_sites[rid] as Dictionary).duplicate(true))
	# Attach live density / tier for callers that want one-shot rows.
	for i in out.size():
		var row: Dictionary = out[i]
		var sid: StringName = row.get("id", &"")
		row["density"] = get_density(sid)
		row["tier"] = int(get_tier(sid))
		row["tier_id"] = String(CrowdSites.tier_id(get_tier(sid)))
		row["effective_density"] = get_effective_density(sid)
		out[i] = row
	return out


func list_by_region(region_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in list_sites():
		if row.get("region_id", &"") == region_id:
			out.append(row)
	return out


func is_known_site(site_id: StringName) -> bool:
	return CrowdSites.is_known_site(site_id) or _runtime_sites.has(site_id)


func get_by_id(site_id: StringName) -> Dictionary:
	if CrowdSites.is_known_site(site_id):
		var row := CrowdSites.get_site_row(site_id)
		row["density"] = get_density(site_id)
		row["tier"] = int(get_tier(site_id))
		row["tier_id"] = String(CrowdSites.tier_id(get_tier(site_id)))
		row["effective_density"] = get_effective_density(site_id)
		row["region_link_ok"] = CrowdSites.region_link_ok(site_id)
		return row
	if _runtime_sites.has(site_id):
		var rt: Dictionary = (_runtime_sites[site_id] as Dictionary).duplicate(true)
		rt["density"] = get_density(site_id)
		rt["tier"] = int(get_tier(site_id))
		rt["tier_id"] = String(CrowdSites.tier_id(get_tier(site_id)))
		rt["effective_density"] = get_effective_density(site_id)
		return rt
	return {}


func display_name(site_id: StringName) -> String:
	if CrowdSites.is_known_site(site_id):
		return CrowdSites.display_name(site_id)
	if _runtime_sites.has(site_id):
		return str((_runtime_sites[site_id] as Dictionary).get("display_name", String(site_id)))
	return String(site_id)


func region_for(site_id: StringName) -> StringName:
	if CrowdSites.is_known_site(site_id):
		return CrowdSites.region_for(site_id)
	if _runtime_sites.has(site_id):
		return (_runtime_sites[site_id] as Dictionary).get("region_id", &"") as StringName
	return &""


# --- Density / tier -----------------------------------------------------------

func get_density(site_id: StringName) -> float:
	if not _densities.has(site_id):
		return 0.0
	return float(_densities[site_id])


func set_density(site_id: StringName, density: float) -> Dictionary:
	if not is_known_site(site_id):
		last_result = {
			"ok": false,
			"reason": &"unknown_site",
			"site_id": site_id,
		}
		return last_result
	var previous := get_density(site_id)
	var next := clampf(density, 0.0, 1.0)
	var prev_tier := get_tier(site_id)
	_densities[site_id] = next
	if not is_equal_approx(previous, next):
		density_changed.emit(site_id, next, previous)
	var new_tier := CrowdSites.tier_for_density(next)
	if int(new_tier) != int(prev_tier):
		tier_changed.emit(site_id, int(new_tier), int(prev_tier))
	last_result = {
		"ok": true,
		"site_id": site_id,
		"density": next,
		"previous_density": previous,
		"tier": int(new_tier),
		"tier_id": String(CrowdSites.tier_id(new_tier)),
		"previous_tier": int(prev_tier),
		"effective_density": get_effective_density(site_id),
	}
	return last_result


func adjust_density(site_id: StringName, delta: float) -> Dictionary:
	return set_density(site_id, get_density(site_id) + delta)


func get_tier(site_id: StringName) -> CrowdSites.Tier:
	return CrowdSites.tier_for_density(get_density(site_id))


func set_tier(site_id: StringName, tier: CrowdSites.Tier) -> Dictionary:
	var mid := CrowdSites.density_for_tier(tier)
	var out := set_density(site_id, mid)
	out["set_via"] = &"tier"
	out["requested_tier"] = int(tier)
	last_result = out
	return out


func set_tier_id(site_id: StringName, tier_name: StringName) -> Dictionary:
	return set_tier(site_id, CrowdSites.tier_from_id(tier_name))


func reset_density(site_id: StringName) -> Dictionary:
	if CrowdSites.is_known_site(site_id):
		return set_density(site_id, CrowdSites.base_density(site_id))
	if _runtime_sites.has(site_id):
		var base := float((_runtime_sites[site_id] as Dictionary).get("base_density", 0.0))
		return set_density(site_id, base)
	last_result = {"ok": false, "reason": &"unknown_site", "site_id": site_id}
	return last_result


func reset_all_densities() -> void:
	_seed_from_sites()
	for rid in _runtime_sites.keys():
		var base := float((_runtime_sites[rid] as Dictionary).get("base_density", 0.0))
		_densities[rid] = clampf(base, 0.0, 1.0)
	presence_refreshed.emit(&"reset_all")


# --- Effective density (soft season / day) ------------------------------------

## Visual-bind helper. Stored density + optional soft season bias (does not mutate).
func get_effective_density(site_id: StringName) -> float:
	var base := get_density(site_id)
	if not season_bias_enabled:
		return base
	var bias := _season_bias_for_site(site_id)
	return clampf(base + bias, 0.0, 1.0)


func get_effective_tier(site_id: StringName) -> CrowdSites.Tier:
	return CrowdSites.tier_for_density(get_effective_density(site_id))


func _season_bias_for_site(site_id: StringName) -> float:
	var season_id := _soft_season_id()
	if season_id == &"":
		return 0.0
	var kind := _site_kind(site_id)
	match season_id:
		&"spring":
			match kind:
				&"market", &"monastic_fair":
					return 0.05
				_:
					return 0.02
		&"summer":
			match kind:
				&"town", &"port":
					return 0.1
				&"monastic_fair", &"market":
					return 0.08
				&"camp":
					return 0.04
				_:
					return 0.05
		&"autumn":
			match kind:
				&"market", &"monastic_fair", &"steading":
					return 0.12
				&"town", &"port":
					return 0.04
				_:
					return 0.03
		&"winter":
			match kind:
				&"town", &"port":
					return -0.08
				&"camp", &"river", &"steading":
					return -0.12
				&"monastic_fair":
					return -0.06
				_:
					return -0.05
		_:
			return 0.0


func _soft_season_id() -> StringName:
	if WorldClock == null:
		return &""
	if WorldClock.has_method("get_season_id"):
		return WorldClock.get_season_id() as StringName
	return &""


## Kind metadata only — must NOT call get_by_id / list_sites (those attach
## effective_density via get_effective_density → _season_bias_for_site → here).
func _site_kind(site_id: StringName) -> StringName:
	if CrowdSites.is_known_site(site_id):
		return CrowdSites.kind_for(site_id)
	if _runtime_sites.has(site_id):
		return (_runtime_sites[site_id] as Dictionary).get("kind", &"") as StringName
	return &""


# --- Register -----------------------------------------------------------------

## Runtime register / overwrite a site. region_id should be a TravelDistances id.
func register_site(
	site_id: StringName,
	display: String = "",
	region_id: StringName = &"leinster",
	kind: StringName = &"town",
	base_density: float = 0.3,
	tags: Array = [],
	summary: String = ""
) -> Dictionary:
	if site_id == &"":
		last_result = {"ok": false, "reason": &"empty_id"}
		return last_result
	var meta := {
		"id": site_id,
		"display_name": display if display != "" else String(site_id),
		"irish_name": "",
		"region_id": region_id,
		"kind": kind,
		"base_density": clampf(base_density, 0.0, 1.0),
		"tags": tags.duplicate(),
		"summary": summary,
		"runtime": true,
	}
	var was_known := is_known_site(site_id)
	_runtime_sites[site_id] = meta
	if not _densities.has(site_id):
		_densities[site_id] = meta["base_density"]
	if not was_known or not CrowdSites.is_known_site(site_id):
		site_registered.emit(site_id)
	last_result = {
		"ok": true,
		"site_id": site_id,
		"registered": true,
		"region_id": region_id,
		"density": get_density(site_id),
		"region_known": TravelDistances.is_known_region(region_id),
	}
	return last_result


# --- Debug / probe ------------------------------------------------------------

func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


func set_debug_visible(visible: bool) -> void:
	debug_visible = visible


func to_debug_dict() -> Dictionary:
	var sites: Array = []
	for sid in list_site_ids():
		var row := get_by_id(sid)
		sites.append({
			"id": String(sid),
			"display_name": display_name(sid),
			"region_id": String(region_for(sid)),
			"kind": String(row.get("kind", &"")),
			"density": get_density(sid),
			"effective_density": get_effective_density(sid),
			"tier": int(get_tier(sid)),
			"tier_id": String(CrowdSites.tier_id(get_tier(sid))),
			"effective_tier_id": String(CrowdSites.tier_id(get_effective_tier(sid))),
			"region_link_ok": TravelDistances.is_known_region(region_for(sid)),
		})
	return {
		"site_count": list_site_ids().size(),
		"seeded_count": CrowdSites.SITE_IDS.size(),
		"runtime_count": _runtime_sites.size(),
		"season_bias_enabled": season_bias_enabled,
		"soft_season_id": String(_soft_season_id()),
		"season_api_present": WorldClock != null and WorldClock.has_method("get_season_id"),
		"debug_visible": debug_visible,
		"sites": sites,
		"last_result": last_result.duplicate(true),
	}


func get_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Crowd / town presence stub ===")
	var season_note := String(_soft_season_id())
	if season_note == "":
		season_note = "(no season API — bias idle)"
	lines.append(
		"Sites: %d seeded + %d runtime · season_bias=%s soft_season=%s"
		% [
			CrowdSites.SITE_IDS.size(),
			_runtime_sites.size(),
			str(season_bias_enabled),
			season_note,
		]
	)
	lines.append("Keys: \\ toggle · PgUp/PgDn site · Home/End dens ±0.1 · Ins tier+ · Del reset")
	for sid in list_site_ids():
		var d := get_density(sid)
		var e := get_effective_density(sid)
		var t := get_tier(sid)
		var et := get_effective_tier(sid)
		lines.append(
			"  %s [%s] dens=%.2f eff=%.2f tier=%s%s · %s" % [
				String(sid),
				String(region_for(sid)),
				d,
				e,
				CrowdSites.tier_id(t),
				("→%s" % CrowdSites.tier_id(et)) if int(et) != int(t) else "",
				display_name(sid),
			]
		)
	if not last_result.is_empty():
		lines.append("Last: %s" % str(last_result))
	return "\n".join(lines)


## Remote / headless smoke. Optionally mutates dublin density when live=true.
func probe_remote(live: bool = false) -> Dictionary:
	var ids := list_site_ids()
	var region_ok := true
	for sid in CrowdSites.SITE_IDS:
		if not CrowdSites.region_link_ok(sid):
			region_ok = false
			break
	var out := {
		"ok": ids.size() >= CrowdSites.SITE_IDS.size() and region_ok,
		"site_count": ids.size(),
		"region_links_ok": region_ok,
		"sample_dublin_density": get_density(&"dublin"),
		"sample_dublin_tier": String(CrowdSites.tier_id(get_tier(&"dublin"))),
		"sample_wexford_region": String(region_for(&"wexford")),
		"season_api_present": WorldClock != null and WorldClock.has_method("get_season_id"),
		"soft_season_id": String(_soft_season_id()),
		"effective_dublin": get_effective_density(&"dublin"),
	}
	if live:
		var before := get_density(&"dublin")
		var set_out := set_density(&"dublin", clampf(before + 0.1, 0.0, 1.0))
		out["live_set"] = set_out
		reset_density(&"dublin")
		out["live_reset_density"] = get_density(&"dublin")
	out["debug"] = to_debug_dict()
	return out
