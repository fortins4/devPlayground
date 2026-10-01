class_name EventOutcome
extends Resource
## Shared EventOutcome schema for living-history events.
##
## Used by WorldClock (resolve), Factions (attitude / territory ripples),
## and Rumors (offscreen news). Lock this shape before content multiplies —
## see systems/timeline/README.md and docs/SCOPE.md (EventOutcome).
##
## Variables the player (or absent-player sim) can shift:
##   troops, morale, supplies, key_survivors, clan_allegiance
## Resolution:
##   player_present == false → history-weighted sim toward historical_bias
##   player_present == true  → gameplay + world state (caller sets fields)

@export var event_id: StringName = &""
@export var display_name: String = ""

## Calendar day index when the event fires (WorldClock.day).
@export var scheduled_day: int = 0

## True when the player is at the event site / participating.
@export var player_present: bool = false

## Force strength committed (0..1 normalized, or absolute headcount when authored).
@export var troops: float = 0.5
## Fighting spirit / cohesion (0..1).
@export var morale: float = 0.5
## Food, arrows, ships, silver — abstracted (0..1).
@export var supplies: float = 0.5

## Key character id → survived (true) / died or captured (false).
@export var key_survivors: Dictionary = {}

## Clan / minor faction id → allegiance tag (e.g. &"neutral", &"ui_chennselaig", &"anglo_normans").
@export var clan_allegiance: Dictionary = {}

## Weight toward the historical result when the player is absent (0 = pure sim, 1 = railroad history).
@export_range(0.0, 1.0) var historical_bias: float = 0.75

## Authored historical defaults used by absent-player resolve.
@export var historical_troops: float = 0.55
@export var historical_morale: float = 0.6
@export var historical_supplies: float = 0.55
@export var historical_survivors: Dictionary = {}
@export var historical_allegiance: Dictionary = {}

## Filled after resolve: short machine tag for downstream systems.
@export var result_tag: StringName = &""
## Human-readable summary for rumors / UI.
@export var result_summary: String = ""
@export var resolved: bool = false


func duplicate_outcome() -> EventOutcome:
	var copy := duplicate(true) as EventOutcome
	return copy


## Blend live variables toward historical defaults by historical_bias.
func apply_history_weight() -> void:
	var w := clampf(historical_bias, 0.0, 1.0)
	var live := 1.0 - w
	troops = live * troops + w * historical_troops
	morale = live * morale + w * historical_morale
	supplies = live * supplies + w * historical_supplies
	if not historical_survivors.is_empty():
		key_survivors = historical_survivors.duplicate(true)
	if not historical_allegiance.is_empty():
		clan_allegiance = historical_allegiance.duplicate(true)


func to_debug_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"player_present": player_present,
		"troops": troops,
		"morale": morale,
		"supplies": supplies,
		"key_survivors": key_survivors.duplicate(true),
		"clan_allegiance": clan_allegiance.duplicate(true),
		"historical_bias": historical_bias,
		"result_tag": result_tag,
		"result_summary": result_summary,
		"resolved": resolved,
	}
