extends Node
## Enech (honor) — reputation and social standing under Brehon law.
##
## Per-faction + overall tables. Law / dialogue gates are data-side stubs
## (e.g. min honor to choose éraic or claim sanctuary).

signal honor_changed(faction_id: StringName, value: float)

## Overall honor-price standing (0..100).
var overall: float = 50.0
## faction_id → honor with that faction (0..100).
var by_faction: Dictionary = {}

## Slice law / dialogue gates (tune with content).
const ERAIC_MIN_OVERALL: float = 40.0
const SANCTUARY_MIN_CHURCH: float = 30.0
const SANCTUARY_MIN_OVERALL: float = 35.0
## Delta magnitude that spawns a rumor (avoid spam on tiny ticks).
const RUMOR_HONOR_THRESHOLD: float = 8.0


func _ready() -> void:
	_ensure_faction_table()


func _ensure_faction_table() -> void:
	for id in Factions.FACTION_IDS:
		if not by_faction.has(id):
			by_faction[id] = overall


func get_honor(faction_id: StringName = &"") -> float:
	if faction_id == &"":
		return overall
	_ensure_faction_table()
	return float(by_faction.get(faction_id, overall))


func modify_honor(amount: float, faction_id: StringName = &"") -> void:
	_ensure_faction_table()
	if faction_id == &"":
		var before := overall
		overall = clampf(overall + amount, 0.0, 100.0)
		honor_changed.emit(&"", overall)
		_maybe_rumor_honor(&"", before, overall, amount)
	else:
		var current := float(by_faction.get(faction_id, overall))
		var before := current
		current = clampf(current + amount, 0.0, 100.0)
		by_faction[faction_id] = current
		honor_changed.emit(faction_id, current)
		_maybe_rumor_honor(faction_id, before, current, amount)
		# Overall drifts slightly with faction-specific hits.
		overall = clampf(overall + amount * 0.25, 0.0, 100.0)


## Data-side gate: may the player offer / accept éraic (honor-price) instead of blood?
func can_choose_eraic(faction_id: StringName = &"") -> bool:
	if faction_id == &"":
		return overall >= ERAIC_MIN_OVERALL
	return get_honor(faction_id) >= ERAIC_MIN_OVERALL and overall >= ERAIC_MIN_OVERALL * 0.75


## Data-side gate: may the player claim monastic / Church sanctuary?
func can_claim_sanctuary() -> bool:
	return get_honor(&"church") >= SANCTUARY_MIN_CHURCH or overall >= SANCTUARY_MIN_OVERALL


## Dialogue / UI helper — which law options are currently open.
func available_law_options() -> Array[StringName]:
	var options: Array[StringName] = []
	if can_choose_eraic():
		options.append(&"eraic")
	if can_claim_sanctuary():
		options.append(&"sanctuary")
	return options


func _maybe_rumor_honor(faction_id: StringName, before: float, after: float, amount: float) -> void:
	if Rumors == null:
		return
	if absf(amount) < RUMOR_HONOR_THRESHOLD:
		return
	var who := "overall" if faction_id == &"" else String(faction_id)
	var direction := "risen" if after > before else "fallen"
	var rumor_id := StringName("honor_%s_%s_%d" % [who, direction, day_stamp()])
	Rumors.add_rumor(
		rumor_id,
		"Word spreads that Cian's enech has %s among %s." % [direction, who],
		&"honor",
		Rumors.PRIORITY_NORMAL,
		7
	)


func day_stamp() -> int:
	if WorldClock:
		return WorldClock.day
	return 0
