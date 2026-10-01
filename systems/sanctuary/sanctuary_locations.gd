class_name SanctuaryLocations
extends RefCounted
## Church / monastic sanctuary site registry (data + API stubs).
##
## Locations Godot can query by id, by TravelDistances region, or as a full list.
## Claim gates reuse Honor.can_claim_sanctuary() (church / overall thresholds).
## Owning faction is Factions id &"church". No level geometry here.
##
## Design: docs/MAP_SCALE.md · docs/SCOPE.md (Glendalough / Clonmacnoise).
## Region ids must match TravelDistances.REGION_IDS.

## Canonical site ids (extend by appending SITES rows).
const SITE_IDS: Array[StringName] = [
	&"glendalough",
	&"clonmacnoise",
]

## Church faction that owns / guards monastic precincts.
const OWNER_FACTION: StringName = &"church"

## Authored sanctuary sites. Schema:
##   id, display_name, irish_name, region_id, faction_id, kind,
##   tags, summary, claim{requires_honor_gate, honor_on_claim, notes}
const SITES: Array[Dictionary] = [
	{
		"id": &"glendalough",
		"display_name": "Glendalough",
		"irish_name": "Gleann Dá Loch",
		"region_id": &"wicklow_glendalough",
		"faction_id": OWNER_FACTION,
		"kind": &"monastic_sanctuary",
		"tags": [&"pilgrimage", &"highland", &"wicklow"],
		"summary": (
			"Twin-lough monastic city in the Wicklow highlands. "
			+ "Church precinct offers sanctuary from feud and raid steel; "
			+ "pilgrimage and reform politics meet highland cover."
		),
		"claim": {
			"requires_honor_gate": true,
			"claimant": &"player",
			"honor_on_claim": {"church": 3.0},
			"notes": (
				"Honor.can_claim_sanctuary() — church≥SANCTUARY_MIN_CHURCH "
				+ "or overall≥SANCTUARY_MIN_OVERALL. Present in region when "
				+ "travel gates exist; data stub only for now."
			),
		},
	},
	{
		"id": &"clonmacnoise",
		"display_name": "Clonmacnoise",
		"irish_name": "Cluain Mhic Nóis",
		"region_id": &"clonmacnoise",
		"faction_id": OWNER_FACTION,
		"kind": &"monastic_sanctuary",
		"tags": [&"pilgrimage", &"shannon", &"midlands"],
		"summary": (
			"Shannon monastic center on the Clonmacnoise corridor. "
			+ "Sanctuary and Church influence along river approaches; "
			+ "pilgrimage spine toward Connacht pressure."
		),
		"claim": {
			"requires_honor_gate": true,
			"claimant": &"player",
			"honor_on_claim": {"church": 3.0},
			"notes": (
				"Same Honor sanctuary gate as Glendalough. Region id "
				+ "clonmacnoise matches TravelDistances / MAP_SCALE."
			),
		},
	},
]


static func is_known_site(site_id: StringName) -> bool:
	return site_id in SITE_IDS


static func list_site_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in SITE_IDS:
		out.append(id)
	return out


## Full registry rows (duplicate so callers can mutate safely).
static func list_sanctuaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in SITES:
		out.append(row.duplicate(true))
	return out


static func get_by_id(site_id: StringName) -> Dictionary:
	for row in SITES:
		if row.get("id", &"") == site_id:
			return row.duplicate(true)
	return {}


## Sites whose region_id matches a TravelDistances region.
static func list_by_region(region_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in SITES:
		if row.get("region_id", &"") == region_id:
			out.append(row.duplicate(true))
	return out


static func display_name(site_id: StringName) -> String:
	var row := get_by_id(site_id)
	if row.is_empty():
		return String(site_id)
	return String(row.get("display_name", String(site_id)))


static func region_for(site_id: StringName) -> StringName:
	var row := get_by_id(site_id)
	if row.is_empty():
		return &""
	return row.get("region_id", &"") as StringName


static func owner_faction(site_id: StringName = &"") -> StringName:
	if site_id == &"":
		return OWNER_FACTION
	var row := get_by_id(site_id)
	if row.is_empty():
		return OWNER_FACTION
	return row.get("faction_id", OWNER_FACTION) as StringName


## True when region_id is a known TravelDistances region (soft check).
static func region_link_ok(site_id: StringName) -> bool:
	var rid := region_for(site_id)
	if rid == &"":
		return false
	return TravelDistances.is_known_region(rid)


## Data-side claim gate: known site + Honor.can_claim_sanctuary() when required.
## Does not check player presence / scene (no level geometry yet).
static func can_claim(site_id: StringName) -> bool:
	var row := get_by_id(site_id)
	if row.is_empty():
		return false
	var rules: Dictionary = row.get("claim", {})
	if bool(rules.get("requires_honor_gate", true)):
		if Honor == null:
			return false
		return Honor.can_claim_sanctuary()
	return true


## Probe payload for dialogue / map UI / debug (mirrors Honor law-gate style).
static func probe_claim(site_id: StringName) -> Dictionary:
	var row := get_by_id(site_id)
	if row.is_empty():
		return {
			"ok": false,
			"reason": &"unknown_site",
			"site_id": String(site_id),
			"can_claim": false,
		}
	var honor_ok := false
	var church_honor := -1.0
	var overall := -1.0
	if Honor != null:
		honor_ok = Honor.can_claim_sanctuary()
		church_honor = Honor.get_honor(&"church")
		overall = Honor.get_honor()
	var allowed := can_claim(site_id)
	return {
		"ok": true,
		"site_id": String(row["id"]),
		"display_name": String(row.get("display_name", "")),
		"irish_name": String(row.get("irish_name", "")),
		"region_id": String(row.get("region_id", "")),
		"faction_id": String(row.get("faction_id", OWNER_FACTION)),
		"kind": String(row.get("kind", "")),
		"summary": String(row.get("summary", "")),
		"region_link_ok": region_link_ok(site_id),
		"honor_gate_open": honor_ok,
		"church_honor": church_honor,
		"overall_honor": overall,
		"can_claim": allowed,
		"claim": (row.get("claim", {}) as Dictionary).duplicate(true),
	}


## Stub resolve: claim sanctuary at a known site if Honor gate allows.
## Applies claim.honor_on_claim church delta; stamps Honor.last_law_result.
static func try_claim(site_id: StringName) -> Dictionary:
	var probe := probe_claim(site_id)
	if not bool(probe.get("ok", false)):
		return {
			"ok": false,
			"option": &"sanctuary",
			"site_id": String(site_id),
			"reason": &"unknown_site",
			"summary": "Unknown sanctuary site.",
		}
	if not bool(probe.get("can_claim", false)):
		var fail := {
			"ok": false,
			"option": &"sanctuary",
			"site_id": String(probe["site_id"]),
			"display_name": String(probe["display_name"]),
			"region_id": String(probe["region_id"]),
			"reason": &"honor_gate_closed",
			"summary": (
				"Sanctuary refused at %s — Church and overall enech too low."
				% String(probe["display_name"])
			),
		}
		if Honor != null:
			Honor.last_law_result = fail.duplicate(true)
		return fail
	var church_delta := 0.0
	var claim_rules: Dictionary = probe.get("claim", {})
	var honor_on: Dictionary = claim_rules.get("honor_on_claim", {})
	if honor_on.has("church"):
		church_delta = float(honor_on["church"])
	if Honor != null and church_delta != 0.0:
		Honor.modify_honor(church_delta, &"church")
	var summary := (
		"You claim sanctuary at %s (%s). Steel stays sheathed at the "
		+ "Church precinct; the dispute waits on monastic mediation."
	) % [String(probe["display_name"]), String(probe.get("irish_name", ""))]
	var success := {
		"ok": true,
		"option": &"sanctuary",
		"site_id": String(probe["site_id"]),
		"display_name": String(probe["display_name"]),
		"region_id": String(probe["region_id"]),
		"faction_id": String(probe["faction_id"]),
		"honor_delta_church": church_delta,
		"summary": summary,
	}
	if Honor != null:
		Honor.last_law_result = success.duplicate(true)
	return success


## Sites in (or linked from) the player's current region when Game is present.
static func list_in_current_region() -> Array[Dictionary]:
	if Game == null:
		return []
	return list_by_region(Game.current_region)


static func to_debug_dict() -> Dictionary:
	var rows: Array = []
	for id in SITE_IDS:
		var p := probe_claim(id)
		rows.append({
			"id": String(id),
			"display_name": String(p.get("display_name", "")),
			"region_id": String(p.get("region_id", "")),
			"region_link_ok": bool(p.get("region_link_ok", false)),
			"can_claim": bool(p.get("can_claim", false)),
			"faction_id": String(p.get("faction_id", "")),
		})
	var honor_open := false
	if Honor != null:
		honor_open = Honor.can_claim_sanctuary()
	return {
		"site_count": SITE_IDS.size(),
		"owner_faction": String(OWNER_FACTION),
		"honor_can_claim_sanctuary": honor_open,
		"sites": rows,
		"sample_glendalough": probe_claim(&"glendalough"),
		"sample_clonmacnoise": probe_claim(&"clonmacnoise"),
	}


static func get_debug_text() -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== SanctuaryLocations / Church precincts ===")
	lines.append("Sites: %d  ·  owner=%s  ·  Honor gate open=%s" % [
		int(d["site_count"]),
		String(d["owner_faction"]),
		str(d["honor_can_claim_sanctuary"]),
	])
	for row in d["sites"]:
		lines.append(
			"  %s @ %s  region_ok=%s  can_claim=%s" % [
				String(row["id"]),
				String(row["region_id"]),
				str(row["region_link_ok"]),
				str(row["can_claim"]),
			]
		)
	lines.append("API: get_by_id / list_by_region / list_sanctuaries / can_claim / try_claim")
	return "\n".join(lines)
