extends Node
## Living-history calendar. Major events resolve on this clock (e.g. Bannow Bay).
##
## EventOutcome schema: systems/timeline/event_outcome.gd (+ README).
## Absent player → history-weighted resolve; present → caller-supplied variables.
##
## Day-advance: `advance_day()` increments the calendar then resolves every
## unresolved event with `scheduled_day <= day` (overdue inclusive). Bannow Bay
## is seeded on day 0; the first `advance_day(1)` therefore resolves it.

signal day_advanced(day: int)
signal event_triggered(event_id: StringName)
signal event_resolved(event_id: StringName, outcome: EventOutcome)

## In-game day index from the Norman landing window (1169). Day 0 = landing day.
var day: int = 0

## event_id → EventOutcome (mutable world state for that event).
var events: Dictionary = {}

## Days on which an event id is scheduled to fire. Overdue events still resolve
## on a later advance (see `_resolve_due_events`).
var scheduled_events: Dictionary = {
	0: &"bannow_bay_landing",
}

## Ring buffer of recent resolve summaries for the debug readout.
var recent_resolutions: Array[Dictionary] = []
const MAX_RECENT_RESOLUTIONS: int = 8

## When true, `get_debug_text()` is cheap to poll every frame from a HUD.
var debug_visible: bool = false


func _ready() -> void:
	_seed_bannow_bay()


func _seed_bannow_bay() -> void:
	var outcome := EventOutcome.new()
	outcome.event_id = &"bannow_bay_landing"
	outcome.display_name = "Norman landing at Bannow Bay"
	outcome.scheduled_day = 0
	outcome.historical_bias = 0.8
	# History-leaning defaults (Robert FitzStephen / Diarmait beachhead, 1169).
	outcome.historical_troops = 0.55
	outcome.historical_morale = 0.65
	outcome.historical_supplies = 0.6
	outcome.historical_survivors = {
		&"diarmait_mac_murchada": true,
		&"robert_fitzstephen": true,
	}
	outcome.historical_allegiance = {
		&"wexford_coast": &"anglo_normans",
		&"ui_chennselaig_core": &"ui_chennselaig",
	}
	# Pre-resolve live seeds (player or content can mutate before resolve day).
	outcome.troops = outcome.historical_troops
	outcome.morale = outcome.historical_morale
	outcome.supplies = outcome.historical_supplies
	outcome.key_survivors = outcome.historical_survivors.duplicate(true)
	outcome.clan_allegiance = outcome.historical_allegiance.duplicate(true)
	events[outcome.event_id] = outcome


func get_outcome(event_id: StringName) -> EventOutcome:
	return events.get(event_id) as EventOutcome


## Mark the player as participating so resolve skips history bias.
func set_player_present(event_id: StringName, present: bool) -> void:
	var outcome := get_outcome(event_id)
	if outcome == null or outcome.resolved:
		return
	outcome.player_present = present


## Mutate event variables before resolve (present-player / mission hooks).
func adjust_event_variable(event_id: StringName, key: StringName, value: Variant) -> void:
	var outcome := get_outcome(event_id)
	if outcome == null or outcome.resolved:
		return
	match key:
		&"troops":
			outcome.troops = clampf(float(value), 0.0, 1.0)
		&"morale":
			outcome.morale = clampf(float(value), 0.0, 1.0)
		&"supplies":
			outcome.supplies = clampf(float(value), 0.0, 1.0)
		&"key_survivors":
			if typeof(value) == TYPE_DICTIONARY:
				outcome.key_survivors = (value as Dictionary).duplicate(true)
		&"clan_allegiance":
			if typeof(value) == TYPE_DICTIONARY:
				outcome.clan_allegiance = (value as Dictionary).duplicate(true)


func advance_day(amount: int = 1) -> void:
	for _i in amount:
		day += 1
		day_advanced.emit(day)
		_resolve_due_events()


## Resolve every unresolved event whose scheduled_day has arrived or passed.
func _resolve_due_events() -> void:
	var due_ids: Array[StringName] = []
	for sched_day in scheduled_events.keys():
		if int(sched_day) <= day:
			var eid: StringName = scheduled_events[sched_day]
			if eid not in due_ids:
				due_ids.append(eid)
	for event_id in events.keys():
		var seeded := events[event_id] as EventOutcome
		if seeded == null or seeded.resolved:
			continue
		if seeded.scheduled_day <= day and event_id not in due_ids:
			due_ids.append(event_id)
	for event_id in due_ids:
		_resolve_scheduled_event(event_id)


func _resolve_scheduled_event(event_id: StringName) -> void:
	event_triggered.emit(event_id)
	var outcome := get_outcome(event_id)
	if outcome == null:
		outcome = EventOutcome.new()
		outcome.event_id = event_id
		outcome.scheduled_day = day
		events[event_id] = outcome
	if outcome.resolved:
		return
	_resolve_outcome(outcome)
	event_resolved.emit(event_id, outcome)
	_broadcast_outcome(outcome)
	_record_resolution(outcome)


## Debug / content: resolve an unresolved event immediately (ignores calendar).
func force_resolve(event_id: StringName) -> EventOutcome:
	var outcome := get_outcome(event_id)
	if outcome == null:
		return null
	if outcome.resolved:
		return outcome
	event_triggered.emit(event_id)
	_resolve_outcome(outcome)
	event_resolved.emit(event_id, outcome)
	_broadcast_outcome(outcome)
	_record_resolution(outcome)
	return outcome


func _resolve_outcome(outcome: EventOutcome) -> void:
	if not outcome.player_present:
		outcome.apply_history_weight()
	# Simple slice heuristic: strong Norman beachhead if troops+morale+supplies high.
	var pressure := (outcome.troops + outcome.morale + outcome.supplies) / 3.0
	if pressure >= 0.55:
		outcome.result_tag = &"norman_foothold"
		outcome.result_summary = "%s — Normans secure a foothold; Wexford coast under pressure." % outcome.display_name
	elif pressure >= 0.35:
		outcome.result_tag = &"contested_landing"
		outcome.result_summary = "%s — landing contested; beachhead fragile." % outcome.display_name
	else:
		outcome.result_tag = &"landing_checked"
		outcome.result_summary = "%s — Gaelic resistance checks the landing." % outcome.display_name
	outcome.resolved = true


func _broadcast_outcome(outcome: EventOutcome) -> void:
	_ripple_attitudes(outcome)
	_ripple_need_pressures(outcome)
	_emit_outcome_rumors(outcome)


func _ripple_attitudes(outcome: EventOutcome) -> void:
	if Factions == null:
		return
	match outcome.result_tag:
		&"norman_foothold":
			Factions.modify_attitude(&"anglo_normans", 8.0)
			Factions.modify_attitude(&"ui_chennselaig", 4.0) # Diarmait invited them
			Factions.modify_attitude(&"norse_wexford_waterford", -12.0)
			Factions.modify_attitude(&"local_clans", -4.0)
			Factions.modify_attitude(&"high_kingship", -3.0)
		&"contested_landing":
			Factions.modify_attitude(&"anglo_normans", 2.0)
			Factions.modify_attitude(&"norse_wexford_waterford", -4.0)
			Factions.modify_attitude(&"ui_chennselaig", 1.0)
		&"landing_checked":
			Factions.modify_attitude(&"anglo_normans", -6.0)
			Factions.modify_attitude(&"norse_wexford_waterford", 6.0)
			Factions.modify_attitude(&"ui_chennselaig", -2.0)
			Factions.modify_attitude(&"local_clans", 3.0)
	# Clan allegiance soft ripples (slice-scale: map allegiance tags → faction nudges).
	for _clan in outcome.clan_allegiance.keys():
		var alleg: StringName = outcome.clan_allegiance[_clan]
		match alleg:
			&"anglo_normans":
				Factions.modify_attitude(&"anglo_normans", 1.0)
			&"ui_chennselaig":
				Factions.modify_attitude(&"ui_chennselaig", 1.0)
			&"norse_wexford_waterford":
				Factions.modify_attitude(&"norse_wexford_waterford", 1.0)


func _ripple_need_pressures(outcome: EventOutcome) -> void:
	if Factions == null:
		return
	match outcome.result_tag:
		&"norman_foothold":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.35)
			Factions.set_need_pressure(&"anglo_normans", &"local_guides", 0.4)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.95)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.55)
		&"contested_landing":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.7)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.85)
		&"landing_checked":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.9)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.5)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.8)


func _emit_outcome_rumors(outcome: EventOutcome) -> void:
	if Rumors == null:
		return
	Rumors.add_rumor(
		StringName("rumor_%s" % String(outcome.event_id)),
		outcome.result_summary,
		outcome.event_id,
		Rumors.PRIORITY_CRITICAL,
		14
	)
	# Flavor / survivor secondary rumors so the bus shows more than one line.
	var fallen: Array[String] = []
	for who in outcome.key_survivors.keys():
		if not bool(outcome.key_survivors[who]):
			fallen.append(String(who).replace("_", " "))
	if not fallen.is_empty():
		Rumors.add_rumor(
			StringName("rumor_%s_survivors" % String(outcome.event_id)),
			"Word from Bannow: %s did not survive the landing." % ", ".join(fallen),
			outcome.event_id,
			Rumors.PRIORITY_HIGH,
			10
		)
	else:
		Rumors.add_rumor(
			StringName("rumor_%s_survivors" % String(outcome.event_id)),
			"Messengers say Diarmait and FitzStephen still live after the landing.",
			outcome.event_id,
			Rumors.PRIORITY_NORMAL,
			7
		)
	match outcome.result_tag:
		&"norman_foothold":
			Rumors.add_rumor(
				&"rumor_bannow_wexford_pressure",
				"Norse Wexford watches the beachhead; harbor defenses tighten.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				10
			)
		&"landing_checked":
			Rumors.add_rumor(
				&"rumor_bannow_checked_cheer",
				"Coastal túatha cheer — the strangers were driven back into the surf.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				8
			)


func _record_resolution(outcome: EventOutcome) -> void:
	recent_resolutions.push_front({
		"day": day,
		"event_id": outcome.event_id,
		"result_tag": outcome.result_tag,
		"summary": outcome.result_summary,
	})
	while recent_resolutions.size() > MAX_RECENT_RESOLUTIONS:
		recent_resolutions.pop_back()


# --- Debug API ---------------------------------------------------------------

func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


func set_debug_visible(visible: bool) -> void:
	debug_visible = visible


func to_debug_dict() -> Dictionary:
	var event_debug: Dictionary = {}
	for event_id in events.keys():
		var outcome := events[event_id] as EventOutcome
		if outcome:
			event_debug[String(event_id)] = outcome.to_debug_dict()
	var attitudes: Dictionary = {}
	if Factions:
		for fid in Factions.LEINSTER_ACTIVE:
			attitudes[String(fid)] = Factions.get_attitude(fid)
	var rumors: Array = []
	if Rumors:
		for rumor in Rumors.get_top_rumors(5):
			rumors.append({
				"id": rumor.get("id"),
				"text": rumor.get("text"),
				"priority": rumor.get("priority"),
				"age_days": rumor.get("age_days"),
			})
	return {
		"day": day,
		"debug_visible": debug_visible,
		"events": event_debug,
		"leinster_attitudes": attitudes,
		"top_rumors": rumors,
		"recent_resolutions": recent_resolutions.duplicate(true),
	}


func get_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== WorldClock / Bannow debug ===")
	lines.append("Day: %d   (T toggle · Y advance day · U force-resolve Bannow)" % day)
	var bannow := get_outcome(&"bannow_bay_landing")
	if bannow:
		lines.append(
			"Bannow: resolved=%s  tag=%s  present=%s" % [
				str(bannow.resolved),
				String(bannow.result_tag) if bannow.result_tag != &"" else "(pending)",
				str(bannow.player_present),
			]
		)
		lines.append(
			"  troops=%.2f morale=%.2f supplies=%.2f bias=%.2f" % [
				bannow.troops, bannow.morale, bannow.supplies, bannow.historical_bias,
			]
		)
		if bannow.resolved and bannow.result_summary != "":
			lines.append("  summary: %s" % bannow.result_summary)
	else:
		lines.append("Bannow: (missing EventOutcome)")
	if Factions:
		lines.append("Attitudes (Leinster):")
		for fid in Factions.LEINSTER_ACTIVE:
			lines.append("  %s: %.1f" % [String(fid), Factions.get_attitude(fid)])
	if Rumors:
		var top := Rumors.get_top_rumors(4)
		lines.append("Rumors (%d active):" % Rumors.active_rumors.size())
		if top.is_empty():
			lines.append("  (none)")
		else:
			for rumor in top:
				lines.append(
					"  [P%d a%d] %s" % [
						int(rumor.get("priority", 0)),
						int(rumor.get("age_days", 0)),
						str(rumor.get("text", "")),
					]
				)
	if not recent_resolutions.is_empty():
		lines.append("Recent resolves:")
		for entry in recent_resolutions:
			lines.append(
				"  d%d %s → %s" % [
					int(entry.get("day", 0)),
					String(entry.get("event_id", &"")),
					String(entry.get("result_tag", &"")),
				]
			)
	return "\n".join(lines)
