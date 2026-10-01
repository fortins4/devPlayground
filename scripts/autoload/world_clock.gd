extends Node
## Living-history calendar. Major events resolve on this clock (e.g. Bannow Bay).
##
## EventOutcome schema: systems/timeline/event_outcome.gd (+ README).
## Absent player → history-weighted resolve; present → caller-supplied variables.

signal day_advanced(day: int)
signal event_triggered(event_id: StringName)
signal event_resolved(event_id: StringName, outcome: EventOutcome)

## In-game day index from the Norman landing window (1169).
var day: int = 0

## event_id → EventOutcome (mutable world state for that event).
var events: Dictionary = {}

## Days on which an event id fires. Expanded from the old flat schedule map.
var scheduled_events: Dictionary = {
	0: &"bannow_bay_landing",
}


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
		_resolve_events_for_day(day)


func _resolve_events_for_day(d: int) -> void:
	if not scheduled_events.has(d):
		return
	var event_id: StringName = scheduled_events[d]
	event_triggered.emit(event_id)
	var outcome := get_outcome(event_id)
	if outcome == null:
		outcome = EventOutcome.new()
		outcome.event_id = event_id
		outcome.scheduled_day = d
		events[event_id] = outcome
	if outcome.resolved:
		return
	_resolve_outcome(outcome)
	event_resolved.emit(event_id, outcome)
	_broadcast_outcome(outcome)


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
	# Attitude ripples (slice-scale stubs).
	if Factions:
		match outcome.result_tag:
			&"norman_foothold":
				Factions.modify_attitude(&"anglo_normans", 8.0)
				Factions.modify_attitude(&"ui_chennselaig", 4.0) # Diarmait invited them
				Factions.modify_attitude(&"norse_gaelic", -12.0)
			&"contested_landing":
				Factions.modify_attitude(&"anglo_normans", 2.0)
				Factions.modify_attitude(&"norse_gaelic", -4.0)
			&"landing_checked":
				Factions.modify_attitude(&"anglo_normans", -6.0)
				Factions.modify_attitude(&"norse_gaelic", 6.0)
				Factions.modify_attitude(&"ui_chennselaig", -2.0)
	if Rumors:
		Rumors.add_rumor(
			StringName("rumor_%s" % String(outcome.event_id)),
			outcome.result_summary,
			outcome.event_id,
			Rumors.PRIORITY_CRITICAL,
			14
		)
