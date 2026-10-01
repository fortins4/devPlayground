extends Node
## Living-history calendar. Major events resolve on this clock (e.g. Bannow Bay).
##
## EventOutcome schema: systems/timeline/event_outcome.gd (+ README).
## Absent player → history-weighted resolve; present → caller-supplied variables.
##
## Day-advance: `advance_day()` increments the calendar then resolves every
## unresolved event with `scheduled_day <= day` (overdue inclusive). Bannow Bay
## is seeded on day 0; the first `advance_day(1)` therefore resolves it.
## Event #2 (Wexford/Waterford struggle) is scheduled on day 14.
## Event #3 (Aífe / Strongbow marriage) is scheduled on day 28.
## Event #4a (Dublin approaches) is scheduled on day 42.
## Event #4b (Dublin siege) is scheduled on day 56.
##
## Listeners on `day_advanced` (auto): Rumors.tick_decay, Factions need-pressure
## tick (hunger/security). CattleEconomy may also subscribe when owned by a scene.

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
	14: &"wexford_waterford_struggle",
	28: &"aife_strongbow_marriage",
	42: &"dublin_approaches",
	56: &"dublin_siege",
}

## Ring buffer of recent resolve summaries for the debug readout.
var recent_resolutions: Array[Dictionary] = []
const MAX_RECENT_RESOLUTIONS: int = 8

## When true, `get_debug_text()` is cheap to poll every frame from a HUD.
var debug_visible: bool = false


func _ready() -> void:
	_seed_bannow_bay()
	_seed_wexford_waterford()
	_seed_aife_strongbow_marriage()
	_seed_dublin_approaches()
	_seed_dublin_siege()


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


func _seed_wexford_waterford() -> void:
	var outcome := EventOutcome.new()
	outcome.event_id = &"wexford_waterford_struggle"
	outcome.display_name = "Struggle for Wexford and Waterford"
	outcome.scheduled_day = 14
	outcome.historical_bias = 0.75
	# History-leaning: FitzStephen / Diarmait pressure on the Norse ports (1169).
	outcome.historical_troops = 0.6
	outcome.historical_morale = 0.58
	outcome.historical_supplies = 0.55
	outcome.historical_survivors = {
		&"robert_fitzstephen": true,
		&"diarmait_mac_murchada": true,
		&"wexford_norse_jarl": false,
	}
	outcome.historical_allegiance = {
		&"wexford_town": &"anglo_normans",
		&"waterford_approaches": &"norse_wexford_waterford",
		&"ui_chennselaig_core": &"ui_chennselaig",
	}
	outcome.troops = outcome.historical_troops
	outcome.morale = outcome.historical_morale
	outcome.supplies = outcome.historical_supplies
	outcome.key_survivors = outcome.historical_survivors.duplicate(true)
	outcome.clan_allegiance = outcome.historical_allegiance.duplicate(true)
	events[outcome.event_id] = outcome



func _seed_aife_strongbow_marriage() -> void:
	var outcome := EventOutcome.new()
	outcome.event_id = &"aife_strongbow_marriage"
	outcome.display_name = "Marriage of Aífe and Strongbow"
	outcome.scheduled_day = 28
	outcome.historical_bias = 0.78
	# History-leaning: Richard de Clare (Strongbow) marries Aífe after Waterford (1170).
	outcome.historical_troops = 0.62
	outcome.historical_morale = 0.7
	outcome.historical_supplies = 0.58
	outcome.historical_survivors = {
		&"aife_ingen_diarmata": true,
		&"richard_de_clare": true,
		&"diarmait_mac_murchada": true,
	}
	outcome.historical_allegiance = {
		&"waterford_town": &"anglo_normans",
		&"ui_chennselaig_core": &"ui_chennselaig",
		&"strongbow_host": &"anglo_normans",
	}
	outcome.troops = outcome.historical_troops
	outcome.morale = outcome.historical_morale
	outcome.supplies = outcome.historical_supplies
	outcome.key_survivors = outcome.historical_survivors.duplicate(true)
	outcome.clan_allegiance = outcome.historical_allegiance.duplicate(true)
	events[outcome.event_id] = outcome


func _seed_dublin_approaches() -> void:
	var outcome := EventOutcome.new()
	outcome.event_id = &"dublin_approaches"
	outcome.display_name = "Approaches on Dublin"
	outcome.scheduled_day = 42
	outcome.historical_bias = 0.76
	# History-leaning: Norman–Diarmait host pushes north toward Áth Cliath (1170–71).
	outcome.historical_troops = 0.64
	outcome.historical_morale = 0.66
	outcome.historical_supplies = 0.57
	outcome.historical_survivors = {
		&"richard_de_clare": true,
		&"diarmait_mac_murchada": true,
		&"ascall_mac_ragnaill": true,
	}
	outcome.historical_allegiance = {
		&"dublin_approaches": &"anglo_normans",
		&"leinster_north_road": &"ui_chennselaig",
		&"dublin_walls": &"norse_dublin",
	}
	outcome.troops = outcome.historical_troops
	outcome.morale = outcome.historical_morale
	outcome.supplies = outcome.historical_supplies
	outcome.key_survivors = outcome.historical_survivors.duplicate(true)
	outcome.clan_allegiance = outcome.historical_allegiance.duplicate(true)
	events[outcome.event_id] = outcome


func _seed_dublin_siege() -> void:
	var outcome := EventOutcome.new()
	outcome.event_id = &"dublin_siege"
	outcome.display_name = "Siege of Dublin"
	outcome.scheduled_day = 56
	outcome.historical_bias = 0.78
	# History-leaning: Áth Cliath falls / is held under Norman pressure; Ruaidrí reacts (1171).
	outcome.historical_troops = 0.68
	outcome.historical_morale = 0.62
	outcome.historical_supplies = 0.54
	outcome.historical_survivors = {
		&"richard_de_clare": true,
		&"ascall_mac_ragnaill": false,
		&"ruaidri_ua_conchobair": true,
	}
	outcome.historical_allegiance = {
		&"dublin_town": &"anglo_normans",
		&"dublin_harbor": &"norse_dublin",
		&"high_king_host": &"high_kingship",
	}
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
	match outcome.event_id:
		&"wexford_waterford_struggle":
			_resolve_wexford_waterford(outcome)
		&"aife_strongbow_marriage":
			_resolve_aife_strongbow_marriage(outcome)
		&"dublin_approaches":
			_resolve_dublin_approaches(outcome)
		&"dublin_siege":
			_resolve_dublin_siege(outcome)
		_:
			_resolve_bannow_bay(outcome)
	outcome.resolved = true


func _resolve_bannow_bay(outcome: EventOutcome) -> void:
	# Strong Norman beachhead if troops+morale+supplies high.
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


func _resolve_wexford_waterford(outcome: EventOutcome) -> void:
	# Port-town struggle: high pressure → towns fall to Norman/Diarmait axis.
	var pressure := (outcome.troops + outcome.morale + outcome.supplies) / 3.0
	if pressure >= 0.55:
		outcome.result_tag = &"towns_fall"
		outcome.result_summary = (
			"%s — Wexford yields; Waterford approaches buckle under Norman and Diarmait pressure."
			% outcome.display_name
		)
	elif pressure >= 0.35:
		outcome.result_tag = &"towns_contested"
		outcome.result_summary = (
			"%s — harbor fighting stalls; neither side holds both ports cleanly."
			% outcome.display_name
		)
	else:
		outcome.result_tag = &"towns_hold"
		outcome.result_summary = (
			"%s — Norse-Gaelic defenses hold the ports; the inland advance slows."
			% outcome.display_name
		)



func _resolve_aife_strongbow_marriage(outcome: EventOutcome) -> void:
	# Dynastic seal: high pressure → marriage seals Norman claim through Aífe.
	var pressure := (outcome.troops + outcome.morale + outcome.supplies) / 3.0
	if pressure >= 0.55:
		outcome.result_tag = &"marriage_sealed"
		outcome.result_summary = (
			"%s — Aífe weds Strongbow; Norman claim to Leinster hardens through Diarmait's line."
			% outcome.display_name
		)
	elif pressure >= 0.35:
		outcome.result_tag = &"marriage_contested"
		outcome.result_summary = (
			"%s — vows are spoken under protest; lords argue whether the match binds the túatha."
			% outcome.display_name
		)
	else:
		outcome.result_tag = &"marriage_blocked"
		outcome.result_summary = (
			"%s — the match fails or is delayed; Strongbow's inheritance through Aífe stays uncertain."
			% outcome.display_name
		)



func _resolve_dublin_approaches(outcome: EventOutcome) -> void:
	# Northern push: high pressure → roads open toward Áth Cliath.
	var pressure := (outcome.troops + outcome.morale + outcome.supplies) / 3.0
	if pressure >= 0.55:
		outcome.result_tag = &"approaches_open"
		outcome.result_summary = (
			"%s — Norman and Diarmait columns clear the north road; Dublin's walls come into view."
			% outcome.display_name
		)
	elif pressure >= 0.35:
		outcome.result_tag = &"approaches_contested"
		outcome.result_summary = (
			"%s — skirmishes stall the columns; neither side owns the approaches cleanly."
			% outcome.display_name
		)
	else:
		outcome.result_tag = &"approaches_checked"
		outcome.result_summary = (
			"%s — Norse-Gaelic riders and local túatha check the advance short of the Liffey."
			% outcome.display_name
		)


func _resolve_dublin_siege(outcome: EventOutcome) -> void:
	# Siege set piece: high pressure → city falls / Norman hold firms (history lean).
	var pressure := (outcome.troops + outcome.morale + outcome.supplies) / 3.0
	if pressure >= 0.55:
		outcome.result_tag = &"dublin_falls"
		outcome.result_summary = (
			"%s — Áth Cliath yields under Norman pressure; Ascall's hold breaks and the harbor changes hands."
			% outcome.display_name
		)
	elif pressure >= 0.35:
		outcome.result_tag = &"dublin_contested"
		outcome.result_summary = (
			"%s — walls crack and hold by turns; Ruaidrí's host and Norman steel trade the streets."
			% outcome.display_name
		)
	else:
		outcome.result_tag = &"dublin_holds"
		outcome.result_summary = (
			"%s — Norse-Gaelic Dublin holds the walls; the siege stalls and Henry's landing grows likelier."
			% outcome.display_name
		)


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
		&"towns_fall":
			Factions.modify_attitude(&"anglo_normans", 10.0)
			Factions.modify_attitude(&"ui_chennselaig", 6.0)
			Factions.modify_attitude(&"norse_wexford_waterford", -18.0)
			Factions.modify_attitude(&"norse_dublin", -6.0)
			Factions.modify_attitude(&"local_clans", -5.0)
			Factions.modify_attitude(&"high_kingship", -5.0)
		&"towns_contested":
			Factions.modify_attitude(&"anglo_normans", 3.0)
			Factions.modify_attitude(&"norse_wexford_waterford", -8.0)
			Factions.modify_attitude(&"ui_chennselaig", 2.0)
		&"towns_hold":
			Factions.modify_attitude(&"anglo_normans", -8.0)
			Factions.modify_attitude(&"norse_wexford_waterford", 12.0)
			Factions.modify_attitude(&"norse_dublin", 4.0)
			Factions.modify_attitude(&"ui_chennselaig", -3.0)
			Factions.modify_attitude(&"local_clans", 4.0)
		&"marriage_sealed":
			Factions.modify_attitude(&"anglo_normans", 14.0)
			Factions.modify_attitude(&"ui_chennselaig", 8.0)
			Factions.modify_attitude(&"high_kingship", -10.0)
			Factions.modify_attitude(&"norse_dublin", -8.0)
			Factions.modify_attitude(&"norse_wexford_waterford", -4.0)
			Factions.modify_attitude(&"local_clans", -6.0)
			Factions.modify_attitude(&"church", 2.0)
		&"marriage_contested":
			Factions.modify_attitude(&"anglo_normans", 5.0)
			Factions.modify_attitude(&"ui_chennselaig", 3.0)
			Factions.modify_attitude(&"high_kingship", -4.0)
			Factions.modify_attitude(&"norse_dublin", -3.0)
			Factions.modify_attitude(&"local_clans", -2.0)
		&"marriage_blocked":
			Factions.modify_attitude(&"anglo_normans", -10.0)
			Factions.modify_attitude(&"ui_chennselaig", -4.0)
			Factions.modify_attitude(&"high_kingship", 6.0)
			Factions.modify_attitude(&"norse_dublin", 4.0)
			Factions.modify_attitude(&"local_clans", 5.0)
		&"approaches_open":
			Factions.modify_attitude(&"anglo_normans", 10.0)
			Factions.modify_attitude(&"ui_chennselaig", 5.0)
			Factions.modify_attitude(&"norse_dublin", -14.0)
			Factions.modify_attitude(&"high_kingship", -8.0)
			Factions.modify_attitude(&"local_clans", -4.0)
			Factions.modify_attitude(&"english_crown", 2.0)
		&"approaches_contested":
			Factions.modify_attitude(&"anglo_normans", 3.0)
			Factions.modify_attitude(&"norse_dublin", -6.0)
			Factions.modify_attitude(&"ui_chennselaig", 2.0)
			Factions.modify_attitude(&"high_kingship", -3.0)
		&"approaches_checked":
			Factions.modify_attitude(&"anglo_normans", -8.0)
			Factions.modify_attitude(&"norse_dublin", 12.0)
			Factions.modify_attitude(&"high_kingship", 5.0)
			Factions.modify_attitude(&"ui_chennselaig", -3.0)
			Factions.modify_attitude(&"local_clans", 4.0)
		&"dublin_falls":
			Factions.modify_attitude(&"anglo_normans", 16.0)
			Factions.modify_attitude(&"ui_chennselaig", 6.0)
			Factions.modify_attitude(&"norse_dublin", -22.0)
			Factions.modify_attitude(&"high_kingship", -12.0)
			Factions.modify_attitude(&"english_crown", 6.0)
			Factions.modify_attitude(&"local_clans", -7.0)
			Factions.modify_attitude(&"norse_wexford_waterford", -5.0)
			Factions.modify_attitude(&"church", 1.0)
		&"dublin_contested":
			Factions.modify_attitude(&"anglo_normans", 6.0)
			Factions.modify_attitude(&"norse_dublin", -10.0)
			Factions.modify_attitude(&"high_kingship", -5.0)
			Factions.modify_attitude(&"english_crown", 3.0)
			Factions.modify_attitude(&"ui_chennselaig", 2.0)
		&"dublin_holds":
			Factions.modify_attitude(&"anglo_normans", -12.0)
			Factions.modify_attitude(&"norse_dublin", 16.0)
			Factions.modify_attitude(&"high_kingship", 8.0)
			Factions.modify_attitude(&"english_crown", 4.0)  # Henry's intervention pressure rises
			Factions.modify_attitude(&"ui_chennselaig", -5.0)
			Factions.modify_attitude(&"local_clans", 5.0)
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
			&"norse_dublin":
				Factions.modify_attitude(&"norse_dublin", 1.0)
			&"high_kingship":
				Factions.modify_attitude(&"high_kingship", 1.0)


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
		&"towns_fall":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.25)
			Factions.set_need_pressure(&"anglo_normans", &"local_guides", 0.35)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.4)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"trade_cattle", 0.8)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.45)
		&"towns_contested":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.65)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.9)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.65)
		&"towns_hold":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.85)
			Factions.set_need_pressure(&"anglo_normans", &"local_guides", 0.7)
			Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.55)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.75)
		&"marriage_sealed":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.2)
			Factions.set_need_pressure(&"anglo_normans", &"local_guides", 0.3)
			Factions.set_need_pressure(&"anglo_normans", &"leinster_claim", 0.85)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.4)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.9)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.8)
		&"marriage_contested":
			Factions.set_need_pressure(&"anglo_normans", &"leinster_claim", 0.55)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.6)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.7)
		&"marriage_blocked":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.75)
			Factions.set_need_pressure(&"anglo_normans", &"leinster_claim", 0.35)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.7)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.5)
		&"approaches_open":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.3)
			Factions.set_need_pressure(&"anglo_normans", &"dublin_siege_train", 0.75)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.95)
			Factions.set_need_pressure(&"norse_dublin", &"wall_repair", 0.85)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.85)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.5)
		&"approaches_contested":
			Factions.set_need_pressure(&"anglo_normans", &"dublin_siege_train", 0.55)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.8)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.7)
		&"approaches_checked":
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.8)
			Factions.set_need_pressure(&"anglo_normans", &"dublin_siege_train", 0.35)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.55)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.55)
		&"dublin_falls":
			Factions.set_need_pressure(&"anglo_normans", &"dublin_siege_train", 0.25)
			Factions.set_need_pressure(&"anglo_normans", &"harbor_garrison", 0.8)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.35)
			Factions.set_need_pressure(&"norse_dublin", &"exile_host", 0.9)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.95)
			Factions.set_need_pressure(&"english_crown", &"intervene_ireland", 0.7)
			Factions.set_need_pressure(&"ui_chennselaig", &"warrior_host", 0.35)
		&"dublin_contested":
			Factions.set_need_pressure(&"anglo_normans", &"dublin_siege_train", 0.7)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.9)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.85)
			Factions.set_need_pressure(&"english_crown", &"intervene_ireland", 0.55)
		&"dublin_holds":
			Factions.set_need_pressure(&"anglo_normans", &"dublin_siege_train", 0.9)
			Factions.set_need_pressure(&"anglo_normans", &"supplies_landing", 0.75)
			Factions.set_need_pressure(&"norse_dublin", &"harbor_defense", 0.5)
			Factions.set_need_pressure(&"high_kingship", &"resist_invasion", 0.6)
			Factions.set_need_pressure(&"english_crown", &"intervene_ireland", 0.8)


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
	var place := "Bannow"
	if outcome.event_id == &"wexford_waterford_struggle":
		place = "Wexford"
	elif outcome.event_id == &"aife_strongbow_marriage":
		place = "Waterford"
	elif outcome.event_id == &"dublin_approaches":
		place = "Dublin approaches"
	elif outcome.event_id == &"dublin_siege":
		place = "Dublin"
	var fallen: Array[String] = []
	for who in outcome.key_survivors.keys():
		if not bool(outcome.key_survivors[who]):
			fallen.append(String(who).replace("_", " "))
	if not fallen.is_empty():
		Rumors.add_rumor(
			StringName("rumor_%s_survivors" % String(outcome.event_id)),
			"Word from %s: %s did not survive the fighting." % [place, ", ".join(fallen)],
			outcome.event_id,
			Rumors.PRIORITY_HIGH,
			10
		)
	else:
		var ok_text := "Messengers say Diarmait and FitzStephen still live after the landing."
		if outcome.event_id == &"wexford_waterford_struggle":
			ok_text = "Messengers say Diarmait and FitzStephen still live after the port struggle."
		elif outcome.event_id == &"aife_strongbow_marriage":
			ok_text = "Messengers say Aífe, Strongbow, and Diarmait still live after the wedding feast."
		elif outcome.event_id == &"dublin_approaches":
			ok_text = "Messengers say Strongbow, Diarmait, and Ascall still live as the columns near Dublin."
		elif outcome.event_id == &"dublin_siege":
			ok_text = "Messengers say Strongbow and Ruaidrí still live after the fighting at Áth Cliath."
		Rumors.add_rumor(
			StringName("rumor_%s_survivors" % String(outcome.event_id)),
			ok_text,
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
		&"towns_fall":
			Rumors.add_rumor(
				&"rumor_wexford_ports_fall",
				"Wexford's gates open to Diarmait's allies; Waterford merchants fear they are next.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				12
			)
			Rumors.add_rumor(
				&"rumor_wexford_trade_shock",
				"Cattle-for-harbor trade stalls while Norse captains argue over terms.",
				outcome.event_id,
				Rumors.PRIORITY_NORMAL,
				8
			)
		&"towns_contested":
			Rumors.add_rumor(
				&"rumor_wexford_ports_contested",
				"Smoke over the harbors — neither Norman nor Norse holds both ports cleanly.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				10
			)
		&"towns_hold":
			Rumors.add_rumor(
				&"rumor_wexford_ports_hold",
				"Norse-Gaelic walls hold; word spreads that the inland advance has slowed.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				10
			)
		&"marriage_sealed":
			Rumors.add_rumor(
				&"rumor_aife_marriage_sealed",
				"At Waterford, Aífe weds Strongbow — Norman steel now claims Leinster through Diarmait's daughter.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				14
			)
			Rumors.add_rumor(
				&"rumor_aife_marriage_dublin_watch",
				"Dublin's Norse captains watch the feast with dread; Ruaidrí's riders carry the news west.",
				outcome.event_id,
				Rumors.PRIORITY_NORMAL,
				10
			)
		&"marriage_contested":
			Rumors.add_rumor(
				&"rumor_aife_marriage_contested",
				"Vows at Waterford draw protest — some túatha refuse to treat Strongbow as Diarmait's heir.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				12
			)
		&"marriage_blocked":
			Rumors.add_rumor(
				&"rumor_aife_marriage_blocked",
				"The match with Aífe falters; Strongbow's host holds ports but not a clear Leinster claim.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				12
			)
		&"approaches_open":
			Rumors.add_rumor(
				&"rumor_dublin_approaches_open",
				"Dust on the north road — Norman banners and Diarmait's kernes close on Áth Cliath.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				12
			)
			Rumors.add_rumor(
				&"rumor_dublin_approaches_walls",
				"Dublin's Norse captains man the walls; cattle and silver vanish into the harbor ships.",
				outcome.event_id,
				Rumors.PRIORITY_NORMAL,
				9
			)
		&"approaches_contested":
			Rumors.add_rumor(
				&"rumor_dublin_approaches_contested",
				"Skirmish smoke on the Liffey approaches — neither host owns the road to Dublin.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				10
			)
		&"approaches_checked":
			Rumors.add_rumor(
				&"rumor_dublin_approaches_checked",
				"Word from the marches: Norse-Gaelic riders turned the columns back short of Dublin.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				10
			)
		&"dublin_falls":
			Rumors.add_rumor(
				&"rumor_dublin_siege_falls",
				"Áth Cliath's gates yield — Ascall's hold breaks and Norman steel takes the harbor.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				14
			)
			Rumors.add_rumor(
				&"rumor_dublin_siege_henry_watch",
				"Across the sea, Henry's clerks note Strongbow's prize; an English landing grows from rumor to plan.",
				outcome.event_id,
				Rumors.PRIORITY_NORMAL,
				12
			)
		&"dublin_contested":
			Rumors.add_rumor(
				&"rumor_dublin_siege_contested",
				"Street fighting in Dublin — Ruaidrí's host and Strongbow's knights trade the walls by night.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				12
			)
		&"dublin_holds":
			Rumors.add_rumor(
				&"rumor_dublin_siege_holds",
				"Dublin's walls hold; some say only the English king can break the deadlock now.",
				outcome.event_id,
				Rumors.PRIORITY_HIGH,
				12
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
				"priority_label": Rumors.priority_label(int(rumor.get("priority", Rumors.PRIORITY_NORMAL))),
				"age_days": rumor.get("age_days"),
				"days_remaining": Rumors.days_remaining(rumor),
			})
	var needs: Dictionary = {}
	if Factions:
		needs = Factions.to_needs_debug_dict()
	return {
		"day": day,
		"debug_visible": debug_visible,
		"events": event_debug,
		"leinster_attitudes": attitudes,
		"leinster_needs": needs,
		"top_rumors": rumors,
		"recent_resolutions": recent_resolutions.duplicate(true),
	}



func _append_event_debug_lines(lines: PackedStringArray, event_id: StringName, label: String) -> void:
	var outcome := get_outcome(event_id)
	if outcome == null:
		lines.append("%s: (missing EventOutcome)" % label)
		return
	lines.append(
		"%s: day=%d resolved=%s tag=%s present=%s" % [
			label,
			outcome.scheduled_day,
			str(outcome.resolved),
			String(outcome.result_tag) if outcome.result_tag != &"" else "(pending)",
			str(outcome.player_present),
		]
	)
	lines.append(
		"  troops=%.2f morale=%.2f supplies=%.2f bias=%.2f" % [
			outcome.troops, outcome.morale, outcome.supplies, outcome.historical_bias,
		]
	)
	if outcome.resolved and outcome.result_summary != "":
		lines.append("  summary: %s" % outcome.result_summary)


func get_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== WorldClock / living-history debug ===")
	lines.append("Day: %d   (T toggle · Y advance · U Bannow · I Wexford · O Marriage · Z Approaches · X Siege · P need surge · / quest stubs)" % day)
	_append_event_debug_lines(lines, &"bannow_bay_landing", "Bannow")
	_append_event_debug_lines(lines, &"wexford_waterford_struggle", "Wexford/Waterford")
	_append_event_debug_lines(lines, &"aife_strongbow_marriage", "Aífe/Strongbow")
	_append_event_debug_lines(lines, &"dublin_approaches", "Dublin approaches")
	_append_event_debug_lines(lines, &"dublin_siege", "Dublin siege")
	if Factions:
		lines.append("Attitudes (Leinster):")
		for fid in Factions.LEINSTER_ACTIVE:
			lines.append("  %s: %.1f" % [String(fid), Factions.get_attitude(fid)])
		lines.append(Factions.get_needs_debug_text())
	if Rumors:
		var top := Rumors.get_top_rumors(4)
		lines.append("Rumors (%d active):" % Rumors.count_active())
		if top.is_empty():
			lines.append("  (none)")
		else:
			for rumor in top:
				lines.append(
					"  [%s P%d left=%d] %s" % [
						Rumors.priority_label(int(rumor.get("priority", Rumors.PRIORITY_NORMAL))),
						int(rumor.get("priority", 0)),
						Rumors.days_remaining(rumor),
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
