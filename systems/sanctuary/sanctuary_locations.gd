class_name SanctuaryLocations
extends RefCounted
## Church / monastic sanctuary site registry (data + API stubs).
##
## Locations Godot can query by id, by TravelDistances region, or as a full list.
## Claim gates reuse Honor.can_claim_sanctuary() (church / overall thresholds).
## Breach hooks: report/resolve steel-in-precinct → Honor deltas + tagged Rumors
## (church / sanctuary / breach) for directors / stealth / combat later.
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

## Breach rumor / honor defaults (per-site breach{} may override).
## Church hit is serious under Brehon / monastic custom; overall drifts lighter.
const BREACH_HONOR_CHURCH: float = -12.0
const BREACH_HONOR_OVERALL: float = -6.0
const BREACH_RUMOR_PRIORITY: int = 3  ## Rumors.PRIORITY_HIGH
const BREACH_RUMOR_DECAY_DAYS: int = 12
const BREACH_RUMOR_SOURCE: StringName = &"sanctuary_breach"
## Escalation: each repeat breach at the same site adds this to church magnitude.
const BREACH_ESCALATION_CHURCH: float = -3.0
const BREACH_ESCALATION_OVERALL: float = -1.0

## Authored sanctuary sites. Schema:
##   id, display_name, irish_name, region_id, faction_id, kind,
##   tags, summary,
##   claim{requires_honor_gate, honor_on_claim, notes},
##   breach{honor_on_breach, rumor_priority, rumor_decay_days, notes}
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
		"breach": {
			"honor_on_breach": {"church": BREACH_HONOR_CHURCH, "overall": BREACH_HONOR_OVERALL},
			"rumor_priority": BREACH_RUMOR_PRIORITY,
			"rumor_decay_days": BREACH_RUMOR_DECAY_DAYS,
			"notes": (
				"Steel / blood in the precinct — directors / stealth / combat "
				+ "call report_breach or resolve_breach. Data stub only."
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
		"breach": {
			"honor_on_breach": {"church": BREACH_HONOR_CHURCH, "overall": BREACH_HONOR_OVERALL},
			"rumor_priority": BREACH_RUMOR_PRIORITY,
			"rumor_decay_days": BREACH_RUMOR_DECAY_DAYS,
			"notes": (
				"Same breach honor / rumor defaults as Glendalough. Shannon "
				+ "corridor word travels fast inland."
			),
		},
	},
]

## site_id (String) → breach count this session (escalation / debug).
static var breach_counts: Dictionary = {}
## Last report/resolve payload (F5 / Honor panel Last: when stamped).
static var last_breach_result: Dictionary = {}


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
		"breach": (row.get("breach", {}) as Dictionary).duplicate(true),
		"breach_count": get_breach_count(site_id),
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


## --- Breach hooks (Honor + Rumors) -------------------------------------------

static func get_breach_count(site_id: StringName) -> int:
	return int(breach_counts.get(String(site_id), 0))


static func reset_breach_tracking() -> void:
	breach_counts.clear()
	last_breach_result = {}


## Authored breach rules for a site (defaults filled when row omits keys).
static func breach_rules_for(site_id: StringName) -> Dictionary:
	var row := get_by_id(site_id)
	if row.is_empty():
		return {}
	var rules: Dictionary = (row.get("breach", {}) as Dictionary).duplicate(true)
	var honor_on: Dictionary = rules.get("honor_on_breach", {})
	if honor_on.is_empty():
		honor_on = {"church": BREACH_HONOR_CHURCH, "overall": BREACH_HONOR_OVERALL}
	rules["honor_on_breach"] = honor_on.duplicate(true)
	if not rules.has("rumor_priority"):
		rules["rumor_priority"] = BREACH_RUMOR_PRIORITY
	if not rules.has("rumor_decay_days"):
		rules["rumor_decay_days"] = BREACH_RUMOR_DECAY_DAYS
	return rules


## Preview honor deltas + rumor tags without mutating Honor / Rumors.
## prior_count: when >= 0, use as the pre-breach tally for escalation math;
## otherwise uses get_breach_count(site_id).
static func probe_breach(site_id: StringName, prior_count: int = -1) -> Dictionary:
	var row := get_by_id(site_id)
	if row.is_empty():
		return {
			"ok": false,
			"reason": &"unknown_site",
			"site_id": String(site_id),
			"can_breach_resolve": false,
		}
	var rules := breach_rules_for(site_id)
	var count := prior_count if prior_count >= 0 else get_breach_count(site_id)
	var deltas := _breach_honor_deltas(rules, count)
	var tags := build_breach_rumor_tags(site_id)
	var church_honor := -1.0
	var overall := -1.0
	if Honor != null:
		church_honor = Honor.get_honor(&"church")
		overall = Honor.get_honor()
	return {
		"ok": true,
		"reason": &"ok",
		"site_id": String(row["id"]),
		"display_name": String(row.get("display_name", "")),
		"irish_name": String(row.get("irish_name", "")),
		"region_id": String(row.get("region_id", "")),
		"faction_id": String(row.get("faction_id", OWNER_FACTION)),
		"kind": String(row.get("kind", "")),
		"can_breach_resolve": true,
		"breach_count": count,
		"escalated": count >= 1,
		"honor_delta_church": float(deltas.get("church", 0.0)),
		"honor_delta_overall": float(deltas.get("overall", 0.0)),
		"church_honor": church_honor,
		"overall_honor": overall,
		"rumor_priority": int(rules.get("rumor_priority", BREACH_RUMOR_PRIORITY)),
		"rumor_decay_days": int(rules.get("rumor_decay_days", BREACH_RUMOR_DECAY_DAYS)),
		"rumor_tags": _tags_as_strings(tags),
		"rumor_source": String(BREACH_RUMOR_SOURCE),
		"breach": rules,
	}


## Tagged rumor vocabulary for a sanctuary breach (church / sanctuary / breach).
static func build_breach_rumor_tags(site_id: StringName = &"") -> Array:
	var tags: Array = []
	if Rumors != null:
		tags.append(Rumors.TAG_CHURCH)
		tags.append(Rumors.TAG_SANCTUARY)
		tags.append(Rumors.TAG_BREACH)
		tags.append(Rumors.TAG_HEAT)
		tags.append(Rumors.TAG_DIRECTION_COLDER)
		tags.append(Rumors.faction_tag(OWNER_FACTION))
	else:
		tags.append(&"church")
		tags.append(&"sanctuary")
		tags.append(&"breach")
		tags.append(&"heat")
		tags.append(&"direction:colder")
		tags.append(&"faction:church")
	if site_id != &"":
		tags.append(StringName("site:%s" % String(site_id)))
	return tags


## Gameplay / stealth / combat reports steel-in-precinct at a known site.
## Applies Honor deltas and seeds a tagged rumor. Alias of resolve_breach.
static func report_breach(
	site_id: StringName,
	kind: StringName = &"steel",
	apply_honor: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	return resolve_breach(site_id, kind, apply_honor, spawn_rumor)


## Resolve a sanctuary breach: Honor consequences + tagged Rumors seed.
## kind: machine tag for directors (&"steel", &"blood", &"theft", …).
## Stamps last_breach_result and Honor.last_law_result for F5 panels.
static func resolve_breach(
	site_id: StringName,
	kind: StringName = &"steel",
	apply_honor: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	var probe := probe_breach(site_id)
	if not bool(probe.get("ok", false)):
		var denied := {
			"ok": false,
			"option": &"sanctuary_breach",
			"site_id": String(site_id),
			"reason": &"unknown_site",
			"kind": String(kind),
			"summary": "Unknown sanctuary site — cannot resolve breach.",
			"honor_delta_church": 0.0,
			"honor_delta_overall": 0.0,
			"rumor_seeded": false,
			"rumor_id": &"",
		}
		last_breach_result = denied.duplicate(true)
		if Honor != null:
			Honor.last_law_result = denied.duplicate(true)
		return denied

	var prior := get_breach_count(site_id)
	var rules := breach_rules_for(site_id)
	var deltas := _breach_honor_deltas(rules, prior)
	var church_delta := float(deltas.get("church", 0.0))
	var overall_delta := float(deltas.get("overall", 0.0))
	var escalated := prior >= 1

	if apply_honor and Honor != null:
		if church_delta != 0.0:
			Honor.modify_honor(church_delta, &"church")
		if overall_delta != 0.0:
			Honor.modify_honor(overall_delta, &"")

	var key := String(site_id)
	breach_counts[key] = prior + 1
	var new_count: int = int(breach_counts[key])

	var rumor_id: StringName = &""
	var rumor_seeded := false
	if spawn_rumor:
		rumor_id = _spawn_breach_rumor(
			site_id,
			String(probe.get("display_name", "")),
			kind,
			escalated,
			church_delta,
			int(rules.get("rumor_priority", BREACH_RUMOR_PRIORITY)),
			int(rules.get("rumor_decay_days", BREACH_RUMOR_DECAY_DAYS))
		)
		rumor_seeded = rumor_id != &""

	var irish := String(probe.get("irish_name", ""))
	var place := String(probe.get("display_name", String(site_id)))
	var kind_label := String(kind) if kind != &"" else "steel"
	var summary: String
	if escalated:
		summary = (
			"Sanctuary breached again at %s (%s) — %s in the precinct. "
			+ "Church enech hardens; word of the outrage spreads."
		) % [place, irish, kind_label]
	else:
		summary = (
			"Sanctuary breached at %s (%s) — %s in the Church precinct. "
			+ "Steel where guest-right held; monastic word will travel."
		) % [place, irish, kind_label]

	var outcome := {
		"ok": true,
		"option": &"sanctuary_breach",
		"reason": &"breached",
		"site_id": String(probe["site_id"]),
		"display_name": place,
		"irish_name": irish,
		"region_id": String(probe.get("region_id", "")),
		"faction_id": String(probe.get("faction_id", OWNER_FACTION)),
		"kind": kind_label,
		"escalated": escalated,
		"breach_count": new_count,
		"honor_applied": apply_honor,
		"honor_delta_church": church_delta if apply_honor else 0.0,
		"honor_delta_overall": overall_delta if apply_honor else 0.0,
		"rumor_seeded": rumor_seeded,
		"rumor_id": rumor_id,
		"rumor_tags": probe.get("rumor_tags", []),
		"rumor_priority": int(rules.get("rumor_priority", BREACH_RUMOR_PRIORITY)),
		"rumor_decay_days": int(rules.get("rumor_decay_days", BREACH_RUMOR_DECAY_DAYS)),
		"day": _day_stamp(),
		"summary": summary,
	}
	last_breach_result = outcome.duplicate(true)
	if Honor != null:
		Honor.last_law_result = outcome.duplicate(true)
	return outcome


## Sites in (or linked from) the player's current region when Game is present.
static func list_in_current_region() -> Array[Dictionary]:
	if Game == null:
		return []
	return list_by_region(Game.current_region)


static func to_debug_dict() -> Dictionary:
	var rows: Array = []
	for id in SITE_IDS:
		var p := probe_claim(id)
		var b := probe_breach(id)
		rows.append({
			"id": String(id),
			"display_name": String(p.get("display_name", "")),
			"region_id": String(p.get("region_id", "")),
			"region_link_ok": bool(p.get("region_link_ok", false)),
			"can_claim": bool(p.get("can_claim", false)),
			"faction_id": String(p.get("faction_id", "")),
			"breach_count": int(b.get("breach_count", 0)),
			"breach_honor_church": float(b.get("honor_delta_church", 0.0)),
			"breach_honor_overall": float(b.get("honor_delta_overall", 0.0)),
		})
	var honor_open := false
	if Honor != null:
		honor_open = Honor.can_claim_sanctuary()
	return {
		"site_count": SITE_IDS.size(),
		"owner_faction": String(OWNER_FACTION),
		"honor_can_claim_sanctuary": honor_open,
		"breach_defaults": {
			"church": BREACH_HONOR_CHURCH,
			"overall": BREACH_HONOR_OVERALL,
			"rumor_priority": BREACH_RUMOR_PRIORITY,
			"rumor_decay_days": BREACH_RUMOR_DECAY_DAYS,
			"source": String(BREACH_RUMOR_SOURCE),
		},
		"sites": rows,
		"last_breach_result": last_breach_result.duplicate(true),
		"sample_glendalough": probe_claim(&"glendalough"),
		"sample_clonmacnoise": probe_claim(&"clonmacnoise"),
		"sample_breach_glendalough": probe_breach(&"glendalough"),
		"sample_breach_clonmacnoise": probe_breach(&"clonmacnoise"),
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
	var bd: Dictionary = d.get("breach_defaults", {})
	lines.append(
		"Breach defaults: church %+.0f  overall %+.0f  rumor P%d / %dd  src=%s" % [
			float(bd.get("church", 0.0)),
			float(bd.get("overall", 0.0)),
			int(bd.get("rumor_priority", 0)),
			int(bd.get("rumor_decay_days", 0)),
			String(bd.get("source", "")),
		]
	)
	for row in d["sites"]:
		lines.append(
			"  %s @ %s  region_ok=%s  can_claim=%s  breaches=%d" % [
				String(row["id"]),
				String(row["region_id"]),
				str(row["region_link_ok"]),
				str(row["can_claim"]),
				int(row.get("breach_count", 0)),
			]
		)
	if not last_breach_result.is_empty():
		lines.append(
			"Last breach: ok=%s site=%s kind=%s rumor=%s  %s" % [
				str(last_breach_result.get("ok", false)),
				str(last_breach_result.get("site_id", "")),
				str(last_breach_result.get("kind", "")),
				str(last_breach_result.get("rumor_id", "")),
				str(last_breach_result.get("summary", "")),
			]
		)
	lines.append(
		"API: get_by_id / list_by_region / can_claim / try_claim / "
		+ "probe_breach / report_breach / resolve_breach"
	)
	return "\n".join(lines)


## Remote / F5 probe — claim + breach samples without requiring a HUD key.
static func probe_remote(seed_breach: bool = false) -> Dictionary:
	var payload := {
		"ok": true,
		"debug": to_debug_dict(),
		"claim_glendalough": probe_claim(&"glendalough"),
		"breach_preview_glendalough": probe_breach(&"glendalough"),
		"breach_preview_clonmacnoise": probe_breach(&"clonmacnoise"),
		"rumor_tags_sample": _tags_as_strings(build_breach_rumor_tags(&"glendalough")),
	}
	if seed_breach:
		payload["resolve_glendalough"] = resolve_breach(&"glendalough", &"steel")
		payload["rumors_active"] = Rumors.count_active() if Rumors != null else -1
		payload["has_breach_rumor"] = (
			Rumors.has_rumor(payload["resolve_glendalough"].get("rumor_id", &""))
			if Rumors != null else false
		)
	return payload


static func _breach_honor_deltas(rules: Dictionary, prior_count: int) -> Dictionary:
	var honor_on: Dictionary = rules.get("honor_on_breach", {})
	var church := float(honor_on.get("church", BREACH_HONOR_CHURCH))
	var overall := float(honor_on.get("overall", BREACH_HONOR_OVERALL))
	if prior_count >= 1:
		var steps := prior_count  # 1st repeat → +1 escalation step
		church += BREACH_ESCALATION_CHURCH * float(steps)
		overall += BREACH_ESCALATION_OVERALL * float(steps)
	return {"church": church, "overall": overall}


static func _spawn_breach_rumor(
	site_id: StringName,
	place: String,
	kind: StringName,
	escalated: bool,
	church_delta: float,
	priority: int,
	decay_days: int
) -> StringName:
	if Rumors == null or not Rumors.has_method("add_rumor"):
		return &""
	var day := _day_stamp()
	var rumor_id := StringName("sanctuary_breach_%s_%d" % [String(site_id), day])
	var kind_label := String(kind) if kind != &"" else "steel"
	var body: String
	if escalated:
		body = (
			"Again the precinct at %s is stained — %s where sanctuary held. "
			+ "Church enech %+.0f; pilgrims carry colder word."
		) % [place, kind_label, church_delta]
	else:
		body = (
			"Word from %s: sanctuary broken by %s in the Church precinct. "
			+ "Monastic bells and colder enech travel the roads."
		) % [place, kind_label]
	var tags := build_breach_rumor_tags(site_id)
	Rumors.add_rumor(
		rumor_id,
		body,
		BREACH_RUMOR_SOURCE,
		priority,
		decay_days,
		tags
	)
	return rumor_id


static func _tags_as_strings(tags: Array) -> Array:
	var out: Array = []
	for t in tags:
		out.append(String(t))
	return out


static func _day_stamp() -> int:
	if WorldClock:
		return WorldClock.day
	return 0
