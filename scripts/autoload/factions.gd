extends Node
## Faction registry and player attitude stubs for the vertical slice.

signal attitude_changed(faction_id: StringName, value: float)

const FACTION_IDS: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"high_kingship",
	&"norse_gaelic",
	&"church",
	&"local_clans",
]

## Attitude toward the player: -100 hostile … +100 allied.
var attitudes: Dictionary = {}


func _ready() -> void:
	for id in FACTION_IDS:
		attitudes[id] = 0.0


func get_attitude(faction_id: StringName) -> float:
	return float(attitudes.get(faction_id, 0.0))


func modify_attitude(faction_id: StringName, delta: float) -> void:
	var value := clampf(get_attitude(faction_id) + delta, -100.0, 100.0)
	attitudes[faction_id] = value
	attitude_changed.emit(faction_id, value)
