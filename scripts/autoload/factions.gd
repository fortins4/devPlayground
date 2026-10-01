extends Node
## Faction registry, attitudes, goals/needs, relationship graph, and quest stubs.
##
## Full roster (historically truer): Uí Chennselaig, Anglo-Normans, English crown,
## High Kingship, Norse Dublin, Norse Wexford/Waterford, Church, local clans, fían.
## Leinster slice ACTIVE (quest gen): ui_chennselaig, anglo_normans,
## norse_wexford_waterford. english_crown stays inactive until late / 1171 pressure.
##
## Diplomatic coupling: meaningful attitude / graph swings auto-seed Rumors tags
## (faction pair + warmer/colder). Callers use modify_attitude / set_relationship /
## modify_relationship_strength — no second rumor call required.
##
## Need-pressure tick: hunger / security (+ related needs) evolve on
## WorldClock.day_advanced via apply_need_pressure_tick() — missions need no
## separate call. Tunable rates + thresholds in NEED_* constants / need_daily_rates.
##
## Quest hook board: quest-threshold crosses (and sync/query) land concrete stubs
## on offered_quest_stubs for directors to list / pick_up — see offer_quest_stub.
##
## Graph → timeline unlock stubs: relationship-edge thresholds unlock (or gate)
## living-history event ids + content flags. Registry:
## systems/timeline/graph_timeline_unlocks.gd (class_name GraphTimelineUnlocks).
## Re-evaluated on relationship_changed; directors query list_open_timeline_unlocks /
## is_timeline_event_unlocked / is_content_flag_unlocked.

signal attitude_changed(faction_id: StringName, value: float)
signal need_changed(faction_id: StringName, need_id: StringName)
signal need_threshold_crossed(faction_id: StringName, need_id: StringName, threshold_kind: StringName, pressure: float)
signal need_pressure_ticked(day: int, report: Dictionary)
signal quest_stub_generated(faction_id: StringName, quest: Dictionary)
signal quest_stub_offered(faction_id: StringName, quest: Dictionary)
signal quest_stub_status_changed(quest_id: StringName, status: StringName, quest: Dictionary)
signal relationship_changed(from_id: StringName, to_id: StringName, edge: Dictionary)
signal timeline_unlocks_changed(report: Dictionary)

const FACTION_IDS: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"english_crown",
	&"high_kingship",
	&"norse_dublin",
	&"norse_wexford_waterford",
	&"church",
	&"local_clans",
	&"fian",
]

## Vertical-slice active set in Leinster (quest generation only).
const LEINSTER_ACTIVE: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"norse_wexford_waterford",
]

## Directed relationship edge kinds (faction↔faction, not player attitude).
const REL_ALLIANCE: StringName = &"alliance"
const REL_HOSTILITY: StringName = &"hostility"
const REL_OBLIGATION: StringName = &"obligation"
const REL_PATRONAGE: StringName = &"patronage"
const REL_RIVALRY: StringName = &"rivalry"
const REL_TRADE: StringName = &"trade"
const REL_KINSHIP: StringName = &"kinship"
const REL_FEUD: StringName = &"feud"

const RELATIONSHIP_KINDS: Array[StringName] = [
	REL_ALLIANCE,
	REL_HOSTILITY,
	REL_OBLIGATION,
	REL_PATRONAGE,
	REL_RIVALRY,
	REL_TRADE,
	REL_KINSHIP,
	REL_FEUD,
]

## Kinds where higher strength means warmer diplomacy (alliance / trade / etc.).
const REL_AMICABLE_KINDS: Array[StringName] = [
	REL_ALLIANCE,
	REL_OBLIGATION,
	REL_PATRONAGE,
	REL_TRADE,
	REL_KINSHIP,
]

## --- Rumors ↔ graph coupling thresholds (documented in systems/*/README) ---
## |delta| on player attitude that auto-seeds a tagged rumor.
const RUMOR_ATTITUDE_THRESHOLD: float = 10.0
## |strength delta| on a graph edge that auto-seeds a tagged rumor.
const RUMOR_GRAPH_DELTA_THRESHOLD: float = 15.0
## |strength delta| that elevates graph rumor to PRIORITY_HIGH.
const RUMOR_GRAPH_HIGH_DELTA: float = 30.0
const RUMOR_ATTITUDE_DECAY_DAYS: int = 5
const RUMOR_GRAPH_DECAY_DAYS: int = 6

## --- Need-pressure tick (hunger / security + related) -----------------------
## Canonical categories polished for the Leinster day tick.
const NEED_HUNGER: StringName = &"hunger"
const NEED_SECURITY: StringName = &"security"

## Pressure floor that surfaces quest stubs (matches generate_quest_stubs).
const NEED_QUEST_THRESHOLD: float = 0.4
## Crossing seeds a need-pressure rumor (latched until pressure clears).
const NEED_RUMOR_THRESHOLD: float = 0.75
## Extreme pressure: mild attitude chill (latched) — faction grows wary of the player.
const NEED_ATTITUDE_THRESHOLD: float = 0.9
const NEED_ATTITUDE_DELTA: float = -3.0
const NEED_RUMOR_DECAY_DAYS: int = 5
## Re-arm threshold hooks when pressure falls below (threshold - gap).
const NEED_HOOK_CLEAR_GAP: float = 0.15

## Quest stub board statuses (data-only — no quest UI).
const QUEST_STATUS_AVAILABLE: StringName = &"available"
const QUEST_STATUS_PICKED_UP: StringName = &"picked_up"
const QUEST_STATUS_DISMISSED: StringName = &"dismissed"
## Soft cap so long need climbs cannot flood the board.
const MAX_OFFERED_QUEST_STUBS: int = 24

## Attitude toward the player: -100 hostile … +100 allied.
var attitudes: Dictionary = {}
## faction_id → { display_name, goals: Array, needs: Array, resources: Dictionary, ... }
var profiles: Dictionary = {}
## Directed edges: Array of { from, to, kind, strength (−100…+100), note }.
## Multiple kinds allowed between the same pair (e.g. alliance + obligation).
var relationship_edges: Array[Dictionary] = []
## faction_id → { need_id: per-day pressure delta }. Tunable Leinster rates.
var need_daily_rates: Dictionary = {}
## Latch keys "faction|need|quest|rumor|attitude" → true while above clear line.
var _need_hook_latched: Dictionary = {}
var _last_need_tick_day: int = -1
var _last_need_tick_report: Dictionary = {}
## Concrete stubs directors can list / pick_up (need-threshold → quest hook).
var offered_quest_stubs: Array[Dictionary] = []
## Last GraphTimelineUnlocks.evaluate_registry report (cached for debug / signals).
var _timeline_unlock_report: Dictionary = {}
var _timeline_unlock_signature: String = ""


func _ready() -> void:
	for id in FACTION_IDS:
		attitudes[id] = 0.0
	_seed_profiles()
	_seed_leinster_attitudes()
	_seed_relationship_graph()
	_seed_need_daily_rates()
	_latch_seed_need_thresholds()
	if not relationship_changed.is_connected(_on_relationship_changed_for_unlocks):
		relationship_changed.connect(_on_relationship_changed_for_unlocks)
	refresh_timeline_unlocks(false)
	if WorldClock and not WorldClock.day_advanced.is_connected(_on_world_day_advanced):
		WorldClock.day_advanced.connect(_on_world_day_advanced)


func _seed_profiles() -> void:
	profiles[&"ui_chennselaig"] = {
		"display_name": "Uí Chennselaig / Diarmait",
		"active_in_leinster": true,
		"goals": [
			&"retake_leinster",
			&"use_norman_allies",
			&"secure_diarmait_kingship",
		],
		"needs": [
			{"id": NEED_HUNGER, "priority": 3, "pressure": 0.45},
			{"id": NEED_SECURITY, "priority": 3, "pressure": 0.5},
			{"id": &"cattle_tribute", "priority": 2, "pressure": 0.6},
			{"id": &"warrior_host", "priority": 2, "pressure": 0.7},
		],
		"resources": {"cattle": 40, "warriors": 25, "silver": 10},
	}
	profiles[&"anglo_normans"] = {
		"display_name": "Strongbow & adventurers",
		"active_in_leinster": true,
		"goals": [
			&"gain_land",
			&"hold_bannow_beachhead",
			&"expand_from_wexford",
		],
		"needs": [
			{"id": NEED_HUNGER, "priority": 3, "pressure": 0.55},
			{"id": NEED_SECURITY, "priority": 3, "pressure": 0.6},
			{"id": &"supplies_landing", "priority": 3, "pressure": 0.8},
			{"id": &"local_guides", "priority": 2, "pressure": 0.5},
		],
		"resources": {"troops": 30, "ships": 5, "silver": 40},
	}
	# Inactive until late / 1171 pressure — registered for honor + attitude tables.
	profiles[&"english_crown"] = {
		"display_name": "Henry II / English crown",
		"active_in_leinster": false,
		"inactive_until_late": true,
		"goals": [
			&"control_barons",
			&"claim_overlordship",
		],
		"needs": [],
		"resources": {},
	}
	profiles[&"high_kingship"] = {
		"display_name": "Ruaidrí / Connacht (High Kingship)",
		"active_in_leinster": false,
		"goals": [&"resist_invasion", &"hold_ireland"],
		"needs": [],
		"resources": {},
	}
	profiles[&"norse_dublin"] = {
		"display_name": "Norse-Gaelic Dublin",
		"active_in_leinster": false,
		"goals": [
			&"protect_trade",
			&"hold_ath_cliath",
			&"preserve_autonomy",
		],
		"needs": [],
		"resources": {"ships": 20, "trade_goods": 40, "silver": 50},
	}
	# Slice coastal actor (replaces monolithic norse_gaelic for Leinster).
	profiles[&"norse_wexford_waterford"] = {
		"display_name": "Norse-Gaelic Wexford/Waterford",
		"active_in_leinster": true,
		"goals": [
			&"protect_trade",
			&"hold_wexford_waterford",
			&"preserve_autonomy",
		],
		"needs": [
			{"id": NEED_HUNGER, "priority": 2, "pressure": 0.4},
			{"id": NEED_SECURITY, "priority": 3, "pressure": 0.7},
			{"id": &"harbor_defense", "priority": 3, "pressure": 0.75},
			{"id": &"trade_cattle", "priority": 2, "pressure": 0.55},
		],
		"resources": {"ships": 12, "trade_goods": 20, "silver": 35},
	}
	profiles[&"church"] = {
		"display_name": "The Church",
		"active_in_leinster": false,
		"goals": [&"protect_monasteries", &"political_influence", &"reform"],
		"needs": [],
		"resources": {},
	}
	profiles[&"local_clans"] = {
		"display_name": "Local Leinster túatha / rival clans",
		"active_in_leinster": false,
		"goals": [&"survival", &"feuds", &"shifting_loyalty"],
		"needs": [],
		"resources": {},
	}
	profiles[&"fian"] = {
		"display_name": "Fían / outlaw bands",
		"active_in_leinster": false,
		"goals": [&"survival", &"opportunity", &"wilderness_raids"],
		"needs": [],
		"resources": {},
	}


func _seed_leinster_attitudes() -> void:
	# Cian is Gaelic cattle-stock: mild kinship with Uí Chennselaig, distrust of Normans.
	attitudes[&"ui_chennselaig"] = 10.0
	attitudes[&"anglo_normans"] = -25.0
	attitudes[&"norse_wexford_waterford"] = 0.0
	attitudes[&"english_crown"] = 0.0
	attitudes[&"high_kingship"] = 5.0
	attitudes[&"norse_dublin"] = 0.0
	attitudes[&"church"] = 5.0
	attitudes[&"local_clans"] = 0.0
	attitudes[&"fian"] = -5.0


func is_leinster_active(faction_id: StringName) -> bool:
	return faction_id in LEINSTER_ACTIVE


func get_attitude(faction_id: StringName) -> float:
	return float(attitudes.get(faction_id, 0.0))


## Change player attitude. When |delta| >= RUMOR_ATTITUDE_THRESHOLD and seed_rumor,
## auto-seeds a Rumors entry tagged with faction + direction (warmer/colder).
## Pass seed_rumor=false for silent nudges (e.g. reverse rumor→attitude coupling).
func modify_attitude(faction_id: StringName, delta: float, seed_rumor: bool = true) -> void:
	var value := clampf(get_attitude(faction_id) + delta, -100.0, 100.0)
	attitudes[faction_id] = value
	attitude_changed.emit(faction_id, value)
	if seed_rumor and absf(delta) >= RUMOR_ATTITUDE_THRESHOLD:
		_seed_attitude_rumor(faction_id, delta)


func get_goals(faction_id: StringName) -> Array:
	var profile: Dictionary = profiles.get(faction_id, {})
	return profile.get("goals", [])


func get_needs(faction_id: StringName) -> Array:
	var profile: Dictionary = profiles.get(faction_id, {})
	return profile.get("needs", [])


func set_need_pressure(faction_id: StringName, need_id: StringName, pressure: float) -> void:
	var profile: Dictionary = profiles.get(faction_id, {})
	if profile.is_empty():
		return
	var needs: Array = profile.get("needs", [])
	for need in needs:
		if need.get("id") == need_id:
			var clamped := clampf(pressure, 0.0, 1.0)
			need["pressure"] = clamped
			need_changed.emit(faction_id, need_id)
			_evaluate_need_thresholds(faction_id, need_id, clamped)
			return
	# Unknown need id on a known profile — append so event ripples / ticks can land.
	needs.append({"id": need_id, "priority": 1, "pressure": clampf(pressure, 0.0, 1.0)})
	profile["needs"] = needs
	profiles[faction_id] = profile
	need_changed.emit(faction_id, need_id)
	_evaluate_need_thresholds(faction_id, need_id, clampf(pressure, 0.0, 1.0))


func get_need_pressure(faction_id: StringName, need_id: StringName) -> float:
	for need in get_needs(faction_id):
		if need.get("id") == need_id:
			return float(need.get("pressure", 0.0))
	return 0.0


## Add delta to a need (creates the need entry if missing). Returns new pressure.
func modify_need_pressure(faction_id: StringName, need_id: StringName, delta: float) -> float:
	var next := clampf(get_need_pressure(faction_id, need_id) + delta, 0.0, 1.0)
	set_need_pressure(faction_id, need_id, next)
	return next


func get_need_daily_rate(faction_id: StringName, need_id: StringName) -> float:
	var rates: Dictionary = need_daily_rates.get(faction_id, {})
	return float(rates.get(need_id, 0.0))


func set_need_daily_rate(faction_id: StringName, need_id: StringName, rate: float) -> void:
	if faction_id not in need_daily_rates:
		need_daily_rates[faction_id] = {}
	need_daily_rates[faction_id][need_id] = rate


## WorldClock day commit hook — missions do not need a separate call.
func _on_world_day_advanced(day: int) -> void:
	apply_need_pressure_tick(1, day)


## Apply per-day need pressure for Leinster-active factions (hunger/security + related).
## Idempotent for the same calendar day when skip_if_same_day is true.
func apply_need_pressure_tick(
	days: int = 1,
	day: int = -1,
	skip_if_same_day: bool = true
) -> Dictionary:
	var clock_day := day
	if clock_day < 0:
		clock_day = WorldClock.day if WorldClock else _last_need_tick_day
	if skip_if_same_day and clock_day >= 0 and clock_day == _last_need_tick_day and days == 1:
		return _last_need_tick_report.duplicate(true)

	var steps := maxi(days, 0)
	var changes: Array[Dictionary] = []
	var crossed: Array[Dictionary] = []
	for _i in steps:
		for faction_id in LEINSTER_ACTIVE:
			var rates: Dictionary = need_daily_rates.get(faction_id, {})
			for need_id in rates.keys():
				var rate := float(rates[need_id])
				if is_zero_approx(rate):
					continue
				var before := get_need_pressure(faction_id, need_id as StringName)
				var after := modify_need_pressure(faction_id, need_id as StringName, rate)
				if not is_equal_approx(before, after):
					changes.append({
						"faction_id": faction_id,
						"need_id": need_id,
						"before": before,
						"after": after,
						"delta": after - before,
					})
	# Collect latch state for debug (hooks already fired inside set_need_pressure).
	for key in _need_hook_latched.keys():
		if _need_hook_latched[key]:
			var parts: PackedStringArray = String(key).split("|")
			if parts.size() >= 3:
				crossed.append({
					"faction_id": StringName(parts[0]),
					"need_id": StringName(parts[1]),
					"threshold_kind": StringName(parts[2]),
					"pressure": get_need_pressure(StringName(parts[0]), StringName(parts[1])),
				})

	var report := {
		"day": clock_day,
		"days_applied": steps,
		"changes": changes,
		"latched_hooks": crossed,
		"leinster_needs": to_needs_debug_dict(),
	}
	_last_need_tick_day = clock_day
	_last_need_tick_report = report
	need_pressure_ticked.emit(clock_day, report)
	return report.duplicate(true)


func _seed_need_daily_rates() -> void:
	# Differentiated Leinster trio — do not starve all factions identically.
	# Uí Chennselaig: exile cattle shortfall + rebuilding host (steady hunger).
	need_daily_rates[&"ui_chennselaig"] = {
		NEED_HUNGER: 0.035,
		NEED_SECURITY: 0.028,
		&"cattle_tribute": 0.03,
		&"warrior_host": 0.025,
	}
	# Anglo-Normans: beachhead supplies burn fast; coastal security pressure.
	need_daily_rates[&"anglo_normans"] = {
		NEED_HUNGER: 0.055,
		NEED_SECURITY: 0.045,
		&"supplies_landing": 0.05,
		&"local_guides": 0.02,
	}
	# Norse Wexford/Waterford: harbor threat leads; trade hunger slower.
	need_daily_rates[&"norse_wexford_waterford"] = {
		NEED_HUNGER: 0.025,
		NEED_SECURITY: 0.065,
		&"harbor_defense": 0.06,
		&"trade_cattle": 0.022,
	}


## Quietly latch hooks for seed pressures already at/above thresholds so the
## first day tick only fires on real crossings (not boot values).
func _latch_seed_need_thresholds() -> void:
	for faction_id in LEINSTER_ACTIVE:
		for need in get_needs(faction_id):
			var need_id: StringName = need.get("id")
			var pressure := float(need.get("pressure", 0.0))
			for kind_thresh in [
				[&"quest", NEED_QUEST_THRESHOLD],
				[&"rumor", NEED_RUMOR_THRESHOLD],
				[&"attitude", NEED_ATTITUDE_THRESHOLD],
			]:
				var kind: StringName = kind_thresh[0]
				var thresh := float(kind_thresh[1])
				if pressure >= thresh:
					_need_hook_latched[_hook_key(faction_id, need_id, kind)] = true


## Latch-aware threshold hooks: quest signal, rumor seed, mild attitude chill.
func _evaluate_need_thresholds(
	faction_id: StringName,
	need_id: StringName,
	pressure: float
) -> void:
	_maybe_cross_need_threshold(
		faction_id, need_id, pressure, NEED_QUEST_THRESHOLD, &"quest"
	)
	_maybe_cross_need_threshold(
		faction_id, need_id, pressure, NEED_RUMOR_THRESHOLD, &"rumor"
	)
	_maybe_cross_need_threshold(
		faction_id, need_id, pressure, NEED_ATTITUDE_THRESHOLD, &"attitude"
	)


func _hook_key(faction_id: StringName, need_id: StringName, kind: StringName) -> String:
	return "%s|%s|%s" % [String(faction_id), String(need_id), String(kind)]


func _maybe_cross_need_threshold(
	faction_id: StringName,
	need_id: StringName,
	pressure: float,
	threshold: float,
	kind: StringName
) -> void:
	var key := _hook_key(faction_id, need_id, kind)
	var latched := bool(_need_hook_latched.get(key, false))
	var clear_line := threshold - NEED_HOOK_CLEAR_GAP
	if pressure < clear_line:
		_need_hook_latched[key] = false
		return
	if pressure < threshold or latched:
		return
	_need_hook_latched[key] = true
	need_threshold_crossed.emit(faction_id, need_id, kind, pressure)
	match kind:
		&"quest":
			# Land the crossed need on the director-facing board (idempotent).
			offer_quest_stub(faction_id, need_id, &"threshold_cross")
		&"rumor":
			_seed_need_pressure_rumor(faction_id, need_id, pressure)
		&"attitude":
			# Mild chill; |delta| < RUMOR_ATTITUDE_THRESHOLD so no attitude rumor spam.
			modify_attitude(faction_id, NEED_ATTITUDE_DELTA, false)


func _seed_need_pressure_rumor(
	faction_id: StringName,
	need_id: StringName,
	pressure: float
) -> void:
	if Rumors == null:
		return
	var day := WorldClock.day if WorldClock else 0
	var tags: Array = [
		&"need_pressure",
		Rumors.faction_tag(faction_id),
		StringName("need:%s" % String(need_id)),
	]
	var body := "%s feel the squeeze — %s pressure is critical." % [
		_display_name(faction_id),
		String(need_id).replace("_", " "),
	]
	Rumors.add_rumor(
		StringName("need_%s_%s_%d" % [String(faction_id), String(need_id), day]),
		body,
		&"faction_need",
		Rumors.PRIORITY_HIGH if pressure >= NEED_ATTITUDE_THRESHOLD else Rumors.PRIORITY_NORMAL,
		NEED_RUMOR_DECAY_DAYS,
		tags
	)


func to_needs_debug_dict() -> Dictionary:
	var out: Dictionary = {}
	for faction_id in LEINSTER_ACTIVE:
		var needs_out: Array = []
		for need in get_needs(faction_id):
			var nid: StringName = need.get("id")
			needs_out.append({
				"id": nid,
				"pressure": float(need.get("pressure", 0.0)),
				"priority": int(need.get("priority", 0)),
				"daily_rate": get_need_daily_rate(faction_id, nid),
			})
		out[String(faction_id)] = needs_out
	return out


func get_needs_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Needs (Leinster tick · hunger/security):")
	lines.append(
		"  thresholds quest=%.2f rumor=%.2f attitude=%.2f" % [
			NEED_QUEST_THRESHOLD, NEED_RUMOR_THRESHOLD, NEED_ATTITUDE_THRESHOLD,
		]
	)
	for faction_id in LEINSTER_ACTIVE:
		var parts: PackedStringArray = PackedStringArray()
		for need in get_needs(faction_id):
			var nid: StringName = need.get("id")
			if nid != NEED_HUNGER and nid != NEED_SECURITY:
				# Compact: show canonical + any related at/above quest floor.
				if float(need.get("pressure", 0.0)) < NEED_QUEST_THRESHOLD:
					continue
			parts.append(
				"%s=%.2f(+%.3f/d)" % [
					String(nid),
					float(need.get("pressure", 0.0)),
					get_need_daily_rate(faction_id, nid),
				]
			)
		lines.append("  %s: %s" % [String(faction_id), ", ".join(parts)])
	if not _last_need_tick_report.is_empty():
		lines.append(
			"  last tick: day=%s changes=%d" % [
				str(_last_need_tick_report.get("day", "?")),
				(_last_need_tick_report.get("changes", []) as Array).size(),
			]
		)
	lines.append(get_quest_stubs_debug_text())
	return "\n".join(lines)


## Greybox / F5 helper — force a multi-day need climb without calendar events.
func demo_need_pressure_surge(days: int = 5) -> Dictionary:
	var before := to_needs_debug_dict()
	var report := apply_need_pressure_tick(days, WorldClock.day if WorldClock else -1, false)
	# Seed-latched needs never "cross" on surge alone — sync so directors see board.
	var synced := sync_offered_quest_stubs()
	return {
		"days": days,
		"before": before,
		"report": report,
		"after": to_needs_debug_dict(),
		"quest_stubs": generate_quest_stubs(),
		"offered_quest_stubs": list_offered_quest_stubs(),
		"synced_count": synced.size(),
	}


# --- Quest stub hook board (need pressure → director pickup) -----------------

## Schema keys for each stub dict on offered_quest_stubs.
func quest_stub_schema_keys() -> PackedStringArray:
	return PackedStringArray([
		"id", "faction_id", "need_id", "title",
		"pressure", "priority", "status", "offered_day", "source",
	])


## Stable stub id: "<faction>_<need>".
func quest_stub_id(faction_id: StringName, need_id: StringName) -> StringName:
	return StringName("%s_%s" % [String(faction_id), String(need_id)])


## Pure builder — empty dict when faction inactive, need missing, or below quest floor.
func build_quest_stub(faction_id: StringName, need_id: StringName) -> Dictionary:
	if not is_leinster_active(faction_id):
		return {}
	var pressure := get_need_pressure(faction_id, need_id)
	if pressure < NEED_QUEST_THRESHOLD:
		return {}
	var priority := 1
	var found := false
	for need in get_needs(faction_id):
		if need.get("id") == need_id:
			priority = int(need.get("priority", 1))
			found = true
			break
	if not found:
		return {}
	var day := WorldClock.day if WorldClock else 0
	return {
		"id": quest_stub_id(faction_id, need_id),
		"faction_id": faction_id,
		"need_id": need_id,
		"title": _quest_title(faction_id, need_id),
		"pressure": pressure,
		"priority": priority,
		"status": QUEST_STATUS_AVAILABLE,
		"offered_day": day,
		"source": &"build",
	}


## Land (or refresh pressure on) a stub on the board. Idempotent by stub id —
## does not clobber picked_up / dismissed status. Returns the board row (or {}).
func offer_quest_stub(
	faction_id: StringName,
	need_id: StringName,
	source: StringName = &"threshold_cross"
) -> Dictionary:
	var built := build_quest_stub(faction_id, need_id)
	if built.is_empty():
		return {}
	built["source"] = source
	var qid: StringName = built["id"]
	var idx := _find_quest_stub_index(qid)
	if idx >= 0:
		var existing: Dictionary = offered_quest_stubs[idx]
		# Refresh live pressure / title; keep director status + offered_day.
		existing["pressure"] = built["pressure"]
		existing["priority"] = built["priority"]
		existing["title"] = built["title"]
		offered_quest_stubs[idx] = existing
		quest_stub_generated.emit(faction_id, existing.duplicate(true))
		return existing.duplicate(true)
	_trim_offered_quest_stubs_if_needed()
	offered_quest_stubs.append(built)
	quest_stub_generated.emit(faction_id, built.duplicate(true))
	quest_stub_offered.emit(faction_id, built.duplicate(true))
	return built.duplicate(true)


## Query path: offer a stub for every Leinster need currently at/above quest floor.
## Seed-latched boot pressures never "cross" — call this (or generate_quest_stubs)
## so directors still see concrete stubs without waiting for a re-cross.
func sync_offered_quest_stubs(faction_id: StringName = &"") -> Array[Dictionary]:
	var offered: Array[Dictionary] = []
	var targets: Array[StringName] = []
	if faction_id != &"":
		targets.append(faction_id)
	else:
		targets.append_array(LEINSTER_ACTIVE)
	for id in targets:
		if not is_leinster_active(id):
			continue
		for need in get_needs(id):
			var nid: StringName = need.get("id")
			if float(need.get("pressure", 0.0)) < NEED_QUEST_THRESHOLD:
				continue
			var row := offer_quest_stub(id, nid, &"sync_query")
			if not row.is_empty():
				offered.append(row)
	return offered


## Build 1–2 dynamic quest stubs per faction from current needs (priority desc).
## When land_on_board is true (default), each stub is offered onto the board.
func generate_quest_stubs(
	faction_id: StringName = &"",
	land_on_board: bool = true
) -> Array[Dictionary]:
	var stubs: Array[Dictionary] = []
	var targets: Array[StringName] = []
	if faction_id != &"":
		targets.append(faction_id)
	else:
		targets.append_array(LEINSTER_ACTIVE)
	for id in targets:
		if not is_leinster_active(id):
			continue
		var needs := get_needs(id)
		needs.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
		var count := 0
		for need in needs:
			if count >= 2:
				break
			var nid: StringName = need.get("id")
			if float(need.get("pressure", 0.0)) < NEED_QUEST_THRESHOLD:
				continue
			var quest: Dictionary
			if land_on_board:
				quest = offer_quest_stub(id, nid, &"generate")
			else:
				quest = build_quest_stub(id, nid)
				if not quest.is_empty():
					quest_stub_generated.emit(id, quest)
			if quest.is_empty():
				continue
			stubs.append(quest)
			count += 1
	return stubs


func list_offered_quest_stubs(
	faction_id: StringName = &"",
	status: StringName = &""
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stub in offered_quest_stubs:
		if faction_id != &"" and stub.get("faction_id") != faction_id:
			continue
		if status != &"" and stub.get("status") != status:
			continue
		out.append(stub.duplicate(true))
	out.sort_custom(func(a, b):
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa > pb
		return float(a.get("pressure", 0.0)) > float(b.get("pressure", 0.0))
	)
	return out


## Directors' pickup queue — available stubs only.
func list_available_quest_stubs(faction_id: StringName = &"") -> Array[Dictionary]:
	return list_offered_quest_stubs(faction_id, QUEST_STATUS_AVAILABLE)


func get_quest_stub(quest_id: StringName) -> Dictionary:
	var idx := _find_quest_stub_index(quest_id)
	if idx < 0:
		return {}
	return offered_quest_stubs[idx].duplicate(true)


func has_quest_stub(quest_id: StringName) -> bool:
	return _find_quest_stub_index(quest_id) >= 0


func count_offered_quest_stubs(status: StringName = &"") -> int:
	if status == &"":
		return offered_quest_stubs.size()
	var n := 0
	for stub in offered_quest_stubs:
		if stub.get("status") == status:
			n += 1
	return n


## Director claims a stub. Returns updated row, or {} if missing / not available.
func pick_up_quest_stub(quest_id: StringName) -> Dictionary:
	var idx := _find_quest_stub_index(quest_id)
	if idx < 0:
		return {}
	var stub: Dictionary = offered_quest_stubs[idx]
	if stub.get("status") != QUEST_STATUS_AVAILABLE:
		return {}
	stub["status"] = QUEST_STATUS_PICKED_UP
	offered_quest_stubs[idx] = stub
	quest_stub_status_changed.emit(quest_id, QUEST_STATUS_PICKED_UP, stub.duplicate(true))
	return stub.duplicate(true)


## Soft-dismiss (keeps history on the board). Returns false if missing.
func dismiss_quest_stub(quest_id: StringName) -> bool:
	var idx := _find_quest_stub_index(quest_id)
	if idx < 0:
		return false
	var stub: Dictionary = offered_quest_stubs[idx]
	stub["status"] = QUEST_STATUS_DISMISSED
	offered_quest_stubs[idx] = stub
	quest_stub_status_changed.emit(quest_id, QUEST_STATUS_DISMISSED, stub.duplicate(true))
	return true


func clear_offered_quest_stubs() -> void:
	offered_quest_stubs.clear()


func to_quest_stubs_debug_dict() -> Dictionary:
	return {
		"threshold": NEED_QUEST_THRESHOLD,
		"offered_count": offered_quest_stubs.size(),
		"available_count": count_offered_quest_stubs(QUEST_STATUS_AVAILABLE),
		"picked_up_count": count_offered_quest_stubs(QUEST_STATUS_PICKED_UP),
		"dismissed_count": count_offered_quest_stubs(QUEST_STATUS_DISMISSED),
		"stubs": list_offered_quest_stubs(),
	}


func get_quest_stubs_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var avail := count_offered_quest_stubs(QUEST_STATUS_AVAILABLE)
	var picked := count_offered_quest_stubs(QUEST_STATUS_PICKED_UP)
	lines.append(
		"Quest stubs (board %d · avail=%d picked=%d · / probe):" % [
			offered_quest_stubs.size(), avail, picked,
		]
	)
	var listed := list_offered_quest_stubs()
	if listed.is_empty():
		lines.append("  (none — sync_offered_quest_stubs / P surge / threshold cross)")
	else:
		for stub in listed:
			lines.append(
				"  [%s] %s p=%.2f pri=%d src=%s" % [
					String(stub.get("status", &"")),
					String(stub.get("id", &"")),
					float(stub.get("pressure", 0.0)),
					int(stub.get("priority", 0)),
					String(stub.get("source", &"")),
				]
			)
	return "\n".join(lines)


## Remote / F5 probe — sync board from current pressures, sample pick_up, report.
func probe_quest_stubs() -> Dictionary:
	var before_count := offered_quest_stubs.size()
	var synced := sync_offered_quest_stubs()
	var available := list_available_quest_stubs()
	var sample_id: StringName = &""
	var picked: Dictionary = {}
	if not available.is_empty():
		sample_id = available[0].get("id", &"")
		picked = pick_up_quest_stub(sample_id)
	return {
		"ok": true,
		"before_count": before_count,
		"synced_count": synced.size(),
		"available_before_pickup": available.size(),
		"sample_id": sample_id,
		"picked": picked,
		"board": to_quest_stubs_debug_dict(),
		"debug_text": get_quest_stubs_debug_text(),
	}


func _find_quest_stub_index(quest_id: StringName) -> int:
	for i in offered_quest_stubs.size():
		if offered_quest_stubs[i].get("id") == quest_id:
			return i
	return -1


func _trim_offered_quest_stubs_if_needed() -> void:
	while offered_quest_stubs.size() >= MAX_OFFERED_QUEST_STUBS:
		# Drop oldest dismissed, else oldest available; never drop picked_up first.
		var drop_idx := -1
		for i in offered_quest_stubs.size():
			if offered_quest_stubs[i].get("status") == QUEST_STATUS_DISMISSED:
				drop_idx = i
				break
		if drop_idx < 0:
			for i in offered_quest_stubs.size():
				if offered_quest_stubs[i].get("status") == QUEST_STATUS_AVAILABLE:
					drop_idx = i
					break
		if drop_idx < 0:
			drop_idx = 0
		offered_quest_stubs.remove_at(drop_idx)


func _quest_title(faction_id: StringName, need_id: Variant) -> String:
	var need := String(need_id) if need_id != null else "aid"
	return "%s seeks help: %s" % [_display_name(faction_id), need.replace("_", " ")]


func _display_name(faction_id: StringName) -> String:
	var profile: Dictionary = profiles.get(faction_id, {})
	return str(profile.get("display_name", String(faction_id)))



# --- Faction↔faction relationship graph --------------------------------------

## Seed historically flavoured directed edges. Leinster-active pairs are denser;
## full roster gets sparse scaffolding so later regions inherit the graph.
func _seed_relationship_graph() -> void:
	relationship_edges.clear()
	# Diarmait invited Strongbow's adventurers — alliance with land-for-service debt.
	_add_edge_raw(&"ui_chennselaig", &"anglo_normans", REL_ALLIANCE, 55.0,
		"Diarmait seeks Norman arms to retake Leinster.")
	_add_edge_raw(&"anglo_normans", &"ui_chennselaig", REL_OBLIGATION, 45.0,
		"Landing terms: land and marriage claims owed for service.")
	# Coastal Norse towns are early Norman targets.
	_add_edge_raw(&"anglo_normans", &"norse_wexford_waterford", REL_HOSTILITY, 70.0,
		"Wexford and Waterford are the beachhead prizes.")
	_add_edge_raw(&"norse_wexford_waterford", &"anglo_normans", REL_HOSTILITY, 65.0,
		"Harbor towns brace against the landing.")
	# Diarmait vs Ruaidrí (exile / High Kingship feud).
	_add_edge_raw(&"ui_chennselaig", &"high_kingship", REL_RIVALRY, 50.0,
		"Exile feud with Ruaidrí / Connacht overlordship.")
	_add_edge_raw(&"high_kingship", &"ui_chennselaig", REL_HOSTILITY, 60.0,
		"High Kingship treats Diarmait's restoration as rebellion.")
	_add_edge_raw(&"high_kingship", &"anglo_normans", REL_HOSTILITY, 45.0,
		"Foreign adventurers threaten Irish overlordship.")
	# Norse kin/trade across the Irish Sea towns.
	_add_edge_raw(&"norse_dublin", &"norse_wexford_waterford", REL_KINSHIP, 40.0,
		"Shared Norse-Gaelic coastal identity.")
	_add_edge_raw(&"norse_wexford_waterford", &"norse_dublin", REL_TRADE, 35.0,
		"Cattle and harbor goods along the east coast.")
	# Baronial patronage under Henry II (latent until 1171 pressure).
	_add_edge_raw(&"anglo_normans", &"english_crown", REL_PATRONAGE, 30.0,
		"Adventurers still owe fealty to Henry II.")
	_add_edge_raw(&"english_crown", &"anglo_normans", REL_PATRONAGE, 50.0,
		"Crown expects to rein in over-mighty barons.")
	# Soft Church / local scaffolding.
	_add_edge_raw(&"church", &"ui_chennselaig", REL_OBLIGATION, 20.0,
		"Sanctuary and reform politics in Leinster.")
	_add_edge_raw(&"local_clans", &"ui_chennselaig", REL_KINSHIP, 25.0,
		"Túatha kinship under shifting kingship claims.")
	_add_edge_raw(&"ui_chennselaig", &"norse_wexford_waterford", REL_RIVALRY, 25.0,
		"Coastal dues and cattle-trade friction.")
	_add_edge_raw(&"fian", &"local_clans", REL_FEUD, 30.0,
		"Outlaw bands prey on túatha herds.")
	_add_edge_raw(&"local_clans", &"fian", REL_HOSTILITY, 35.0,
		"Clan reprisals against fían raiders.")


func _add_edge_raw(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	strength: float,
	note: String = ""
) -> void:
	relationship_edges.append({
		"from": from_id,
		"to": to_id,
		"kind": kind,
		"strength": clampf(strength, -100.0, 100.0),
		"note": note,
	})


func _edge_matches(
	edge: Dictionary,
	from_id: StringName,
	to_id: StringName,
	kind: StringName
) -> bool:
	if from_id != &"" and edge.get("from") != from_id:
		return false
	if to_id != &"" and edge.get("to") != to_id:
		return false
	if kind != &"" and edge.get("kind") != kind:
		return false
	return true


## Upsert a directed edge (match on from+to+kind). Emits relationship_changed.
## When |strength delta| >= RUMOR_GRAPH_DELTA_THRESHOLD and seed_rumor, auto-seeds
## a Rumors entry tagged with both faction ids + warmer/colder direction.
func set_relationship(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	strength: float,
	note: String = "",
	seed_rumor: bool = true
) -> Dictionary:
	if from_id not in FACTION_IDS or to_id not in FACTION_IDS:
		push_warning("Factions.set_relationship: unknown faction id")
		return {}
	if kind not in RELATIONSHIP_KINDS:
		push_warning("Factions.set_relationship: unknown kind %s" % String(kind))
		return {}
	var clamped := clampf(strength, -100.0, 100.0)
	var previous_strength := 0.0
	for i in relationship_edges.size():
		var edge: Dictionary = relationship_edges[i]
		if _edge_matches(edge, from_id, to_id, kind):
			previous_strength = float(edge.get("strength", 0.0))
			edge["strength"] = clamped
			if note != "":
				edge["note"] = note
			relationship_edges[i] = edge
			relationship_changed.emit(from_id, to_id, edge)
			if seed_rumor:
				_maybe_seed_graph_rumor(from_id, to_id, kind, clamped - previous_strength, edge)
			return edge
	var created := {
		"from": from_id,
		"to": to_id,
		"kind": kind,
		"strength": clamped,
		"note": note,
	}
	relationship_edges.append(created)
	relationship_changed.emit(from_id, to_id, created)
	# New edge: treat previous as 0 so a sized create can still seed word.
	if seed_rumor:
		_maybe_seed_graph_rumor(from_id, to_id, kind, clamped - previous_strength, created)
	return created


func modify_relationship_strength(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	delta: float,
	seed_rumor: bool = true
) -> Dictionary:
	var edge := get_relationship(from_id, to_id, kind)
	var current := float(edge.get("strength", 0.0)) if not edge.is_empty() else 0.0
	var note := str(edge.get("note", "")) if not edge.is_empty() else ""
	return set_relationship(from_id, to_id, kind, current + delta, note, seed_rumor)


## First matching edge (optional kind filter). Empty Dictionary if none.
func get_relationship(
	from_id: StringName,
	to_id: StringName,
	kind: StringName = &""
) -> Dictionary:
	for edge in relationship_edges:
		if _edge_matches(edge, from_id, to_id, kind):
			return edge.duplicate(true)
	return {}


## Filter edges by optional from / to / kind (&"" = any).
func list_relationships(
	from_id: StringName = &"",
	to_id: StringName = &"",
	kind: StringName = &""
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in relationship_edges:
		if _edge_matches(edge, from_id, to_id, kind):
			out.append(edge.duplicate(true))
	return out


## Edges touching a faction as either endpoint.
func list_relationships_involving(faction_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in relationship_edges:
		if edge.get("from") == faction_id or edge.get("to") == faction_id:
			out.append(edge.duplicate(true))
	return out


func has_relationship(
	from_id: StringName,
	to_id: StringName,
	kind: StringName = &"",
	min_strength: float = 0.0
) -> bool:
	for edge in list_relationships(from_id, to_id, kind):
		if absf(float(edge.get("strength", 0.0))) >= min_strength:
			return true
	return false


func are_allied(a: StringName, b: StringName, min_strength: float = 25.0) -> bool:
	return (
		has_relationship(a, b, REL_ALLIANCE, min_strength)
		or has_relationship(b, a, REL_ALLIANCE, min_strength)
	)


func are_hostile(a: StringName, b: StringName, min_strength: float = 25.0) -> bool:
	return (
		has_relationship(a, b, REL_HOSTILITY, min_strength)
		or has_relationship(b, a, REL_HOSTILITY, min_strength)
		or has_relationship(a, b, REL_FEUD, min_strength)
		or has_relationship(b, a, REL_FEUD, min_strength)
	)


## Leinster-slice pairs (both endpoints in LEINSTER_ACTIVE).
func list_leinster_relationships() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in relationship_edges:
		var fr: StringName = edge.get("from")
		var to: StringName = edge.get("to")
		if fr in LEINSTER_ACTIVE and to in LEINSTER_ACTIVE:
			out.append(edge.duplicate(true))
	return out


func relationship_count() -> int:
	return relationship_edges.size()


func to_relationship_debug_dict() -> Dictionary:
	var by_kind: Dictionary = {}
	for kind in RELATIONSHIP_KINDS:
		by_kind[String(kind)] = 0
	for edge in relationship_edges:
		var k := String(edge.get("kind", &""))
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	return {
		"edge_count": relationship_edges.size(),
		"by_kind": by_kind,
		"leinster_edges": list_leinster_relationships(),
		"edges": list_relationships(),
	}


# --- Rumors ↔ attitude / graph coupling --------------------------------------

func _seed_attitude_rumor(faction_id: StringName, delta: float) -> void:
	if Rumors == null:
		return
	var direction := "warmer" if delta > 0.0 else "colder"
	var dir_tag: StringName = (
		Rumors.TAG_DIRECTION_WARMER if delta > 0.0 else Rumors.TAG_DIRECTION_COLDER
	)
	var day := WorldClock.day if WorldClock else 0
	var tags: Array = [
		Rumors.TAG_ATTITUDE,
		Rumors.faction_tag(faction_id),
		dir_tag,
	]
	Rumors.add_rumor(
		StringName("attitude_%s_%s_%d" % [String(faction_id), direction, day]),
		"Relations with %s grow %s." % [_display_name(faction_id), direction],
		&"faction",
		Rumors.PRIORITY_NORMAL,
		RUMOR_ATTITUDE_DECAY_DAYS,
		tags
	)


func _maybe_seed_graph_rumor(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	strength_delta: float,
	edge: Dictionary
) -> void:
	if Rumors == null:
		return
	if absf(strength_delta) < RUMOR_GRAPH_DELTA_THRESHOLD:
		return
	var dir_tag := _graph_direction_tag(kind, strength_delta)
	var direction_word := "warmer" if dir_tag == Rumors.TAG_DIRECTION_WARMER else "colder"
	var priority := Rumors.PRIORITY_NORMAL
	if absf(strength_delta) >= RUMOR_GRAPH_HIGH_DELTA:
		priority = Rumors.PRIORITY_HIGH
	var day := WorldClock.day if WorldClock else 0
	var tags: Array = [
		Rumors.TAG_GRAPH,
		Rumors.faction_tag(from_id),
		Rumors.faction_tag(to_id),
		dir_tag,
		StringName("kind:%s" % String(kind)),
	]
	var note := str(edge.get("note", "")).strip_edges()
	var body := "Word spreads: %s and %s grow %s (%s)." % [
		_display_name(from_id),
		_display_name(to_id),
		direction_word,
		String(kind),
	]
	if note != "":
		body = "%s — %s" % [body, note]
	Rumors.add_rumor(
		StringName(
			"graph_%s_%s_%s_%s_%d" % [
				String(from_id), String(to_id), String(kind), direction_word, day,
			]
		),
		body,
		&"faction_graph",
		priority,
		RUMOR_GRAPH_DECAY_DAYS,
		tags
	)


## Amicable kinds: strength up → warmer. Hostile/rival/feud: strength up → colder.
func _graph_direction_tag(kind: StringName, strength_delta: float) -> StringName:
	var amicable := kind in REL_AMICABLE_KINDS
	if amicable:
		return Rumors.TAG_DIRECTION_WARMER if strength_delta > 0.0 else Rumors.TAG_DIRECTION_COLDER
	return Rumors.TAG_DIRECTION_COLDER if strength_delta > 0.0 else Rumors.TAG_DIRECTION_WARMER


# --- Graph → timeline unlock stubs -------------------------------------------

func _on_relationship_changed_for_unlocks(
	_from_id: StringName, _to_id: StringName, _edge: Dictionary
) -> void:
	refresh_timeline_unlocks(true)


## Recompute GraphTimelineUnlocks against the live relationship graph.
## Emits timeline_unlocks_changed when the available set signature changes
## (or when force_emit is true).
func refresh_timeline_unlocks(emit_on_change: bool = true, force_emit: bool = false) -> Dictionary:
	var report := GraphTimelineUnlocks.evaluate_registry(relationship_edges)
	var signature := _timeline_unlock_signature_from_report(report)
	var changed := signature != _timeline_unlock_signature
	_timeline_unlock_report = report
	_timeline_unlock_signature = signature
	if force_emit or (emit_on_change and changed):
		timeline_unlocks_changed.emit(report.duplicate(true))
	return report.duplicate(true)


func _timeline_unlock_signature_from_report(report: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for eid in report.get("available_event_ids", []):
		parts.append("e:%s" % String(eid))
	for fid in report.get("available_content_flags", []):
		parts.append("f:%s" % String(fid))
	for row in report.get("open_unlocks", []):
		parts.append("u:%s" % String(row.get("id", &"")))
	for row in report.get("active_gates", []):
		parts.append("g:%s" % String(row.get("id", &"")))
	parts.sort()
	return "|".join(parts)


func get_timeline_unlock_report() -> Dictionary:
	if _timeline_unlock_report.is_empty():
		return refresh_timeline_unlocks(false)
	return _timeline_unlock_report.duplicate(true)


func list_open_timeline_unlocks() -> Array[Dictionary]:
	return GraphTimelineUnlocks.list_open_unlocks(relationship_edges)


func list_active_timeline_gates() -> Array[Dictionary]:
	var report := GraphTimelineUnlocks.evaluate_registry(relationship_edges)
	var out: Array[Dictionary] = []
	for row in report.get("active_gates", []):
		out.append(row)
	return out


func is_timeline_unlock_open(unlock_id: StringName) -> bool:
	return GraphTimelineUnlocks.is_unlock_open(unlock_id, relationship_edges)


func is_timeline_gate_active(unlock_id: StringName) -> bool:
	return GraphTimelineUnlocks.is_gate_active(unlock_id, relationship_edges)


## True when at least one unlock grants the event and no gate blocks it.
func is_timeline_event_unlocked(event_id: StringName) -> bool:
	return GraphTimelineUnlocks.is_timeline_event_available(event_id, relationship_edges)


func is_content_flag_unlocked(flag: StringName) -> bool:
	return GraphTimelineUnlocks.is_content_flag_available(flag, relationship_edges)


func list_unlocked_timeline_events() -> Array[StringName]:
	return GraphTimelineUnlocks.list_available_timeline_events(relationship_edges)


func list_unlocked_content_flags() -> Array[StringName]:
	return GraphTimelineUnlocks.list_available_content_flags(relationship_edges)


func to_timeline_unlocks_debug_dict() -> Dictionary:
	return GraphTimelineUnlocks.to_debug_dict(relationship_edges)


func get_timeline_unlocks_debug_text() -> String:
	return GraphTimelineUnlocks.get_debug_text(relationship_edges)


## Greybox / F5 / Remote: bump High Kingship hostility so unlock_dublin_road opens,
## then optionally chill the Diarmait–Norman alliance to exercise the marriage gate.
func demo_seed_graph_timeline_unlocks(open_dublin: bool = true, chill_alliance: bool = false) -> Dictionary:
	var before := to_timeline_unlocks_debug_dict()
	if open_dublin:
		modify_relationship_strength(
			&"high_kingship",
			&"anglo_normans",
			REL_HOSTILITY,
			15.0,
			false
		)
	if chill_alliance:
		set_relationship(
			&"ui_chennselaig",
			&"anglo_normans",
			REL_ALLIANCE,
			15.0,
			"F5 chill — marriage gate test",
			false
		)
	var after := refresh_timeline_unlocks(true, true)
	return {
		"before": before,
		"after": after,
		"dublin_road_open": is_timeline_unlock_open(&"unlock_dublin_road"),
		"marriage_available": is_timeline_event_unlocked(&"aife_strongbow_marriage"),
		"marriage_gate_active": is_timeline_gate_active(&"gate_marriage_if_alliance_cold"),
	}


## Greybox / F5 helper — swing Leinster attitude + hostility so the bus shows tags.
func demo_seed_diplomatic_swing() -> Dictionary:
	var before_att := get_attitude(&"anglo_normans")
	modify_attitude(&"anglo_normans", 12.0)
	var edge := modify_relationship_strength(
		&"anglo_normans",
		&"norse_wexford_waterford",
		REL_HOSTILITY,
		18.0
	)
	return {
		"attitude_before": before_att,
		"attitude_after": get_attitude(&"anglo_normans"),
		"hostility_edge": edge.duplicate(true) if not edge.is_empty() else {},
		"rumors_active": Rumors.count_active() if Rumors else 0,
	}
