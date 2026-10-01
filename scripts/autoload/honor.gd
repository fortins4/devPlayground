extends Node
## Enech (honor) — reputation and social standing under Brehon law.

signal honor_changed(faction_id: StringName, value: float)

## Overall honor-price standing. Faction-specific values live in the map below.
var overall: float = 50.0
var by_faction: Dictionary = {}


func get_honor(faction_id: StringName = &"") -> float:
	if faction_id == &"":
		return overall
	return float(by_faction.get(faction_id, overall))


func modify_honor(amount: float, faction_id: StringName = &"") -> void:
	if faction_id == &"":
		overall = clampf(overall + amount, 0.0, 100.0)
		honor_changed.emit(&"", overall)
	else:
		var current := float(by_faction.get(faction_id, overall))
		current = clampf(current + amount, 0.0, 100.0)
		by_faction[faction_id] = current
		honor_changed.emit(faction_id, current)
