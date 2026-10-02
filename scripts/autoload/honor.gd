extends Node
## Enech (honor) — reputation and social standing under Brehon law.
##
## Per-faction + overall tables. Law / dialogue gates are data-side stubs
## (e.g. min honor to choose éraic or claim sanctuary). Sanctuary breach
## facades forward to SanctuaryLocations.report/resolve_breach.
##
## Prestige ↔ Rumors: |delta| >= RUMOR_HONOR_THRESHOLD seeds tagged rumors
## (honor / prestige / enech + direction:* + optional faction:*). Large swings
## (|delta| >= RUMOR_HONOR_HIGH_THRESHOLD) elevate to PRIORITY_HIGH. Callers may
## pass seed_rumor=false to silence (used by Rumors reverse nudge — no loops).

signal honor_changed(faction_id: StringName, value: float)

## Overall honor-price standing (0..100).
var overall: float = 50.0
## faction_id → honor with that faction (0..100).
var by_faction: Dictionary = {}

## Slice law / dialogue gates (tune with content).
const ERAIC_MIN_OVERALL: float = 40.0
const SANCTUARY_MIN_CHURCH: float = 30.0
const SANCTUARY_MIN_OVERALL: float = 35.0

## --- Rumors ↔ prestige coupling (mirrors Factions attitude/graph thresholds) ---
## |delta| that auto-seeds a tagged prestige rumor (avoid spam on tiny ticks).
const RUMOR_HONOR_THRESHOLD: float = 8.0
## |delta| that elevates the honor rumor to PRIORITY_HIGH (prestige-relevant).
const RUMOR_HONOR_HIGH_THRESHOLD: float = 15.0
const RUMOR_HONOR_DECAY_DAYS: int = 7
const RUMOR_HONOR_HIGH_DECAY_DAYS: int = 12
const RUMOR_HONOR_SOURCE: StringName = &"honor"

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


## Change honor. When |amount| >= RUMOR_HONOR_THRESHOLD and seed_rumor, auto-seeds
## a prestige-tagged Rumors entry (HIGH when |amount| >= RUMOR_HONOR_HIGH_THRESHOLD).
## Pass seed_rumor=false to mute (Rumors reverse nudge / callers that seed richer tags).
func modify_honor(amount: float, faction_id: StringName = &"", seed_rumor: bool = true) -> void:
	_ensure_faction_table()
	if faction_id == &"":
		var before := overall
		overall = clampf(overall + amount, 0.0, 100.0)
		honor_changed.emit(&"", overall)
		if seed_rumor:
			_maybe_rumor_honor(&"", before, overall, amount)
	else:
		var current := float(by_faction.get(faction_id, overall))
		var before := current
		current = clampf(current + amount, 0.0, 100.0)
		by_faction[faction_id] = current
		honor_changed.emit(faction_id, current)
		if seed_rumor:
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


## Preview sanctuary breach honor / rumor payload (no mutate).
func probe_sanctuary_breach(site_id: StringName) -> Dictionary:
	return SanctuaryLocations.probe_breach(site_id)


## Report steel-in-precinct at a known sanctuary site → Honor + tagged Rumors.
## Directors / stealth / combat call this (or SanctuaryLocations.report_breach).
func report_sanctuary_breach(
	site_id: StringName,
	kind: StringName = &"steel",
	apply_honor: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	return SanctuaryLocations.report_breach(site_id, kind, apply_honor, spawn_rumor)


## Resolve sanctuary breach (alias path used by directors). Stamps last_law_result.
func resolve_sanctuary_breach(
	site_id: StringName,
	kind: StringName = &"steel",
	apply_honor: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	return SanctuaryLocations.resolve_breach(site_id, kind, apply_honor, spawn_rumor)


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


## Public tag builder — honor / prestige / enech + direction + optional faction:*.
## Matches Rumors tag vocabulary (TAG_HONOR / TAG_PRESTIGE / TAG_ENECH / direction:*).
func build_honor_rumor_tags(faction_id: StringName = &"", amount: float = 0.0) -> Array:
	var tags: Array = []
	if Rumors != null:
		tags.append(Rumors.TAG_HONOR)
		tags.append(Rumors.TAG_PRESTIGE)
		tags.append(Rumors.TAG_ENECH)
		if amount > 0.0:
			tags.append(Rumors.TAG_DIRECTION_WARMER)
		elif amount < 0.0:
			tags.append(Rumors.TAG_DIRECTION_COLDER)
		if faction_id != &"":
			tags.append(Rumors.faction_tag(faction_id))
	else:
		tags.append(&"honor")
		tags.append(&"prestige")
		tags.append(&"enech")
		if amount > 0.0:
			tags.append(&"direction:warmer")
		elif amount < 0.0:
			tags.append(&"direction:colder")
		if faction_id != &"":
			tags.append(StringName("faction:%s" % String(faction_id)))
	return tags


## Snapshot of honor→rumor thresholds (docs + remote probe).
func get_rumor_honor_thresholds() -> Dictionary:
	return {
		"threshold": RUMOR_HONOR_THRESHOLD,
		"high_threshold": RUMOR_HONOR_HIGH_THRESHOLD,
		"decay_days": RUMOR_HONOR_DECAY_DAYS,
		"high_decay_days": RUMOR_HONOR_HIGH_DECAY_DAYS,
		"source": String(RUMOR_HONOR_SOURCE),
	}


## True when |amount| crosses the prestige rumor floor.
func honor_warrants_rumor(amount: float) -> bool:
	return absf(amount) >= RUMOR_HONOR_THRESHOLD


## True when |amount| elevates to HIGH prestige rumor.
func honor_warrants_high_rumor(amount: float) -> bool:
	return absf(amount) >= RUMOR_HONOR_HIGH_THRESHOLD


## Greybox / F5 helper — overall + church swings above high threshold → tagged HIGH rumors.
## Mirrors Factions.demo_seed_diplomatic_swing for prestige coupling smoke.
func demo_seed_prestige_swing() -> Dictionary:
	var before_overall := overall
	var before_church := get_honor(&"church")
	# +16 overall → HIGH prestige rumor (risen / warmer).
	modify_honor(16.0, &"")
	# −16 church → HIGH prestige rumor (fallen / colder) with faction:church.
	modify_honor(-16.0, &"church")
	var rumors_active := Rumors.count_active() if Rumors else 0
	var prestige_rows: Array = []
	if Rumors != null and Rumors.has_method("filter_by_prestige"):
		for row in Rumors.filter_by_prestige():
			prestige_rows.append({
				"id": String(row.get("id", &"")),
				"priority": int(row.get("priority", 0)),
				"tags": _tags_as_strings(row.get("tags", [])),
			})
	return {
		"overall_before": before_overall,
		"overall_after": overall,
		"church_before": before_church,
		"church_after": get_honor(&"church"),
		"rumors_active": rumors_active,
		"prestige_rumors": prestige_rows,
		"thresholds": get_rumor_honor_thresholds(),
	}


func _maybe_rumor_honor(faction_id: StringName, before: float, after: float, amount: float) -> void:
	if Rumors == null:
		return
	if not honor_warrants_rumor(amount):
		return
	var who := "overall" if faction_id == &"" else String(faction_id)
	var risen := after > before
	var direction := "risen" if risen else "fallen"
	var priority := Rumors.PRIORITY_HIGH if honor_warrants_high_rumor(amount) else Rumors.PRIORITY_NORMAL
	var decay := RUMOR_HONOR_HIGH_DECAY_DAYS if priority >= Rumors.PRIORITY_HIGH else RUMOR_HONOR_DECAY_DAYS
	var tags := build_honor_rumor_tags(faction_id, amount)
	var rumor_id := StringName("honor_%s_%s_%d" % [who, direction, day_stamp()])
	var body: String
	if faction_id == &"":
		body = "Word spreads that Cian's enech has %s across the túatha." % direction
	else:
		body = "Word spreads that Cian's enech has %s among %s." % [direction, who]
	if priority >= Rumors.PRIORITY_HIGH:
		body += " Prestige talk hardens — the hall will remember."
	Rumors.add_rumor(
		rumor_id,
		body,
		RUMOR_HONOR_SOURCE,
		priority,
		decay,
		tags
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
		"last_sanctuary_breach": SanctuaryLocations.last_breach_result.duplicate(true),
		"rumor_honor_thresholds": get_rumor_honor_thresholds(),
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
	var thr: Dictionary = d.get("rumor_honor_thresholds", {})
	lines.append(
		"Prestige rumors: |Δ|≥%.0f seed · |Δ|≥%.0f → HIGH  (Remote: Honor.demo_seed_prestige_swing)" % [
			float(thr.get("threshold", RUMOR_HONOR_THRESHOLD)),
			float(thr.get("high_threshold", RUMOR_HONOR_HIGH_THRESHOLD)),
		]
	)
	var opts: Array = d["available_law_options"]
	if opts.is_empty():
		lines.append("Open options: (none — raise enech)")
	else:
		lines.append("Open options: %s" % ", ".join(PackedStringArray(opts)))
	lines.append("E attempt éraic · R sanctuary · D cycle dispute · F dump unlock probe")
	lines.append(
		"Breach: Honor.report_sanctuary_breach(site) / SanctuaryLocations.resolve_breach"
	)
	if not last_law_result.is_empty():
		lines.append(
			"Last: ok=%s option=%s  %s" % [
				str(last_law_result.get("ok", false)),
				str(last_law_result.get("option", "")),
				str(last_law_result.get("summary", "")),
			]
		)
	return "\n".join(lines)


func _tags_as_strings(tags: Array) -> Array:
	var out: Array = []
	for t in tags:
		out.append(String(t))
	return out
