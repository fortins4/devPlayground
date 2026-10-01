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

## When true, Honor debug HUD may poll `get_debug_text()` cheaply.
var debug_visible: bool = false
## Last law-gate sample result (set by LawGateSample / debug HUD).
var last_law_result: Dictionary = {}


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


## Site-aware claim: known SanctuaryLocations id + can_claim_sanctuary().
## Sites: systems/sanctuary/sanctuary_locations.gd (Glendalough / Clonmacnoise).
func can_claim_sanctuary_at(site_id: StringName) -> bool:
	return SanctuaryLocations.can_claim(site_id)


## Band recruitment uses overall enech (0..100) via BandUpkeep.RECRUIT_POOL /
## CattleEconomy — same scale as this autoload. See systems/economy/README.md.

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


func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


func set_debug_visible(visible: bool) -> void:
	debug_visible = visible


func to_debug_dict() -> Dictionary:
	_ensure_faction_table()
	var options: Array = []
	for opt in available_law_options():
		options.append(String(opt))
	var sanctuary_ids: Array = []
	for sid in SanctuaryLocations.list_site_ids():
		sanctuary_ids.append(String(sid))
	return {
		"overall": overall,
		"church": get_honor(&"church"),
		"eraic_min": ERAIC_MIN_OVERALL,
		"sanctuary_min_church": SANCTUARY_MIN_CHURCH,
		"sanctuary_min_overall": SANCTUARY_MIN_OVERALL,
		"can_choose_eraic": can_choose_eraic(),
		"can_claim_sanctuary": can_claim_sanctuary(),
		"sanctuary_site_ids": sanctuary_ids,
		"available_law_options": options,
		"debug_visible": debug_visible,
		"last_law_result": last_law_result.duplicate(true),
	}


func get_debug_text() -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Honor / law-gate debug ===")
	lines.append(
		"Overall: %.1f   Church: %.1f   (H toggle · [ / ] overall ±5 · ; / ' church ±5)" % [
			float(d["overall"]), float(d["church"]),
		]
	)
	lines.append(
		"Gates: eraic=%s (min %.0f)  sanctuary=%s (church≥%.0f or overall≥%.0f)" % [
			str(d["can_choose_eraic"]),
			float(d["eraic_min"]),
			str(d["can_claim_sanctuary"]),
			float(d["sanctuary_min_church"]),
			float(d["sanctuary_min_overall"]),
		]
	)
	var opts: Array = d["available_law_options"]
	if opts.is_empty():
		lines.append("Open options: (none — raise enech)")
	else:
		lines.append("Open options: %s" % ", ".join(PackedStringArray(opts)))
	lines.append("E attempt éraic · R attempt sanctuary (refuge)")
	if not last_law_result.is_empty():
		lines.append(
			"Last: ok=%s option=%s  %s" % [
				str(last_law_result.get("ok", false)),
				str(last_law_result.get("option", "")),
				str(last_law_result.get("summary", "")),
			]
		)
	return "\n".join(lines)
