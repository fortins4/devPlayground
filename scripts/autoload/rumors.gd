extends Node
## World news bus for offscreen events and opportunity hooks.
##
## Priority (high→low sort) + decay (age vs lifetime) keep the bus useful
## (docs/SCOPE.md). Emitters: WorldClock event resolve, Honor swings,
## Faction attitude spikes — see systems/rumors/README.md.

signal rumor_added(rumor_id: StringName)
signal rumor_expired(rumor_id: StringName)
signal rumors_decayed(expired_ids: Array)

## Priority ladder (higher = more urgent). Bus sorts CRITICAL → LOW.
const PRIORITY_LOW: int = 1
const PRIORITY_NORMAL: int = 2
const PRIORITY_HIGH: int = 3
const PRIORITY_CRITICAL: int = 4

const PRIORITY_LABELS := {
	PRIORITY_LOW: "low",
	PRIORITY_NORMAL: "normal",
	PRIORITY_HIGH: "high",
	PRIORITY_CRITICAL: "critical",
}

## Soft cap so the bus cannot grow without bound in long plays.
const MAX_ACTIVE_RUMORS: int = 32

## Active rumor dictionaries (see add_rumor / rumor_schema).
var active_rumors: Array[Dictionary] = []

## Ring of recently expired ids (debug / UI toast hooks).
var recently_expired: Array[StringName] = []
const MAX_RECENTLY_EXPIRED: int = 8

## When true, Rumors debug HUD may poll get_debug_text() cheaply.
var debug_visible: bool = false


func _ready() -> void:
	if WorldClock and not WorldClock.day_advanced.is_connected(_on_day_advanced):
		WorldClock.day_advanced.connect(_on_day_advanced)


func _on_day_advanced(_day: int) -> void:
	tick_decay(1)


## Schema keys for each rumor dict:
##   id, text, source_event, heard, priority, decay_days, age_days, added_day
func rumor_schema_keys() -> PackedStringArray:
	return PackedStringArray([
		"id", "text", "source_event", "heard",
		"priority", "decay_days", "age_days", "added_day",
	])


func priority_label(priority: int) -> String:
	return str(PRIORITY_LABELS.get(priority, "normal"))


func clamp_priority(priority: int) -> int:
	return clampi(priority, PRIORITY_LOW, PRIORITY_CRITICAL)


## Days left before expiry (0 = expires on next tick_decay).
func days_remaining(rumor: Dictionary) -> int:
	var life := maxi(1, int(rumor.get("decay_days", 7)))
	var age := maxi(0, int(rumor.get("age_days", 0)))
	return maxi(0, life - age)


## Add or refresh a rumor. Higher priority wins on refresh; decay_days is lifetime.
## age_days resets to 0 on refresh (word is fresh again).
func add_rumor(
	rumor_id: StringName,
	text: String,
	source_event: StringName = &"",
	priority: int = PRIORITY_NORMAL,
	decay_days: int = 7
) -> void:
	priority = clamp_priority(priority)
	decay_days = maxi(1, decay_days)
	var added_day := _day_stamp()
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			rumor["text"] = text
			rumor["source_event"] = source_event
			rumor["priority"] = maxi(int(rumor.get("priority", PRIORITY_NORMAL)), priority)
			rumor["decay_days"] = maxi(int(rumor.get("decay_days", decay_days)), decay_days)
			rumor["age_days"] = 0
			rumor["added_day"] = added_day
			_sort_by_priority()
			rumor_added.emit(rumor_id)
			return
	var entry := {
		"id": rumor_id,
		"text": text,
		"source_event": source_event,
		"heard": false,
		"priority": priority,
		"decay_days": decay_days,
		"age_days": 0,
		"added_day": added_day,
	}
	active_rumors.append(entry)
	_trim_overflow()
	_sort_by_priority()
	rumor_added.emit(rumor_id)


func mark_heard(rumor_id: StringName) -> bool:
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			rumor["heard"] = true
			return true
	return false


func get_rumor(rumor_id: StringName) -> Dictionary:
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			return rumor.duplicate(true)
	return {}


func has_rumor(rumor_id: StringName) -> bool:
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			return true
	return false


func count_active() -> int:
	return active_rumors.size()


## Advance age; drop rumors where age_days >= decay_days.
## Returns expired ids. Prefer WorldClock.day_advanced wiring; call explicitly for tests.
func tick_decay(days: int = 1) -> Array[StringName]:
	days = maxi(0, days)
	if days == 0:
		return [] as Array[StringName]
	var expired_ids: Array[StringName] = []
	var remaining: Array[Dictionary] = []
	for rumor in active_rumors:
		rumor["age_days"] = int(rumor.get("age_days", 0)) + days
		if int(rumor.get("age_days", 0)) >= int(rumor.get("decay_days", 7)):
			var rid: StringName = rumor.get("id")
			expired_ids.append(rid)
			_record_expired(rid)
			rumor_expired.emit(rid)
		else:
			remaining.append(rumor)
	active_rumors = remaining
	_sort_by_priority()
	if not expired_ids.is_empty():
		rumors_decayed.emit(expired_ids)
	return expired_ids


## Priority-sorted head of the bus (CRITICAL first; fresher wins ties).
func get_top_rumors(limit: int = 5) -> Array[Dictionary]:
	_sort_by_priority()
	return _copy_slice(active_rumors, limit)


## Newest-first list (by added_day desc, then age_days asc) for Godot UI feeds.
func list_recent(limit: int = 10) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = active_rumors.duplicate()
	sorted.sort_custom(func(a, b):
		var da := int(a.get("added_day", 0))
		var db := int(b.get("added_day", 0))
		if da == db:
			return int(a.get("age_days", 0)) < int(b.get("age_days", 0))
		return da > db
	)
	return _copy_slice(sorted, limit)


## Filter active rumors. Pass defaults to skip a criterion.
## min_priority: inclusive floor (0 = any). source_event empty = any source.
func filter_rumors(
	min_priority: int = 0,
	source_event: StringName = &"",
	unheard_only: bool = false,
	heard_only: bool = false
) -> Array[Dictionary]:
	_sort_by_priority()
	var out: Array[Dictionary] = []
	for rumor in active_rumors:
		if min_priority > 0 and int(rumor.get("priority", PRIORITY_NORMAL)) < min_priority:
			continue
		if source_event != &"" and rumor.get("source_event") != source_event:
			continue
		var heard := bool(rumor.get("heard", false))
		if unheard_only and heard:
			continue
		if heard_only and not heard:
			continue
		out.append(rumor.duplicate(true))
	return out


func clear_all() -> void:
	active_rumors.clear()


## Greybox helper — a few standing lines so F5 can exercise the bus without resolve.
func seed_demo_rumors() -> void:
	add_rumor(
		&"demo_market_whisper",
		"Cattle buyers at the crossroads mutter about thin herds inland.",
		&"demo",
		PRIORITY_LOW,
		5
	)
	add_rumor(
		&"demo_fian_sighting",
		"A fían band was seen near the bog road at dusk.",
		&"demo",
		PRIORITY_NORMAL,
		7
	)
	add_rumor(
		&"demo_church_bell",
		"Word of sanctuary: the monastery will shelter the desperate — for a price in penance.",
		&"demo",
		PRIORITY_HIGH,
		10
	)


func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


func set_debug_visible(visible: bool) -> void:
	debug_visible = visible


func to_debug_dict() -> Dictionary:
	var top: Array = []
	for rumor in get_top_rumors(8):
		top.append(_rumor_debug_row(rumor))
	var recent: Array = []
	for rumor in list_recent(5):
		recent.append(_rumor_debug_row(rumor))
	var expired: Array = []
	for rid in recently_expired:
		expired.append(String(rid))
	return {
		"active_count": count_active(),
		"debug_visible": debug_visible,
		"top": top,
		"recent": recent,
		"recently_expired": expired,
		"day": _day_stamp(),
	}


func get_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Rumors bus debug ===")
	lines.append(
		"Active: %d   Day: %d   (N toggle · M seed demo · , tick_decay 1)" % [
			count_active(), _day_stamp(),
		]
	)
	lines.append("Priority: 1=low 2=normal 3=high 4=critical · Decay: age≥lifetime → drop")
	var top := get_top_rumors(6)
	if top.is_empty():
		lines.append("Top: (none — Y resolve Bannow, or M seed demo)")
	else:
		lines.append("Top (priority):")
		for rumor in top:
			lines.append("  %s" % _format_rumor_line(rumor))
	if not recently_expired.is_empty():
		var ids: PackedStringArray = PackedStringArray()
		for rid in recently_expired:
			ids.append(String(rid))
		lines.append("Expired lately: %s" % ", ".join(ids))
	return "\n".join(lines)


func _format_rumor_line(rumor: Dictionary) -> String:
	return "[%s P%d left=%d a%d%s] %s" % [
		priority_label(int(rumor.get("priority", PRIORITY_NORMAL))),
		int(rumor.get("priority", PRIORITY_NORMAL)),
		days_remaining(rumor),
		int(rumor.get("age_days", 0)),
		" heard" if bool(rumor.get("heard", false)) else "",
		str(rumor.get("text", "")),
	]


func _rumor_debug_row(rumor: Dictionary) -> Dictionary:
	return {
		"id": rumor.get("id"),
		"text": rumor.get("text"),
		"source_event": rumor.get("source_event"),
		"priority": rumor.get("priority"),
		"priority_label": priority_label(int(rumor.get("priority", PRIORITY_NORMAL))),
		"decay_days": rumor.get("decay_days"),
		"age_days": rumor.get("age_days"),
		"days_remaining": days_remaining(rumor),
		"heard": rumor.get("heard"),
		"added_day": rumor.get("added_day"),
	}


func _copy_slice(source: Array, limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := mini(maxi(0, limit), source.size())
	for i in n:
		out.append((source[i] as Dictionary).duplicate(true))
	return out


func _sort_by_priority() -> void:
	active_rumors.sort_custom(func(a, b):
		var pa := int(a.get("priority", PRIORITY_NORMAL))
		var pb := int(b.get("priority", PRIORITY_NORMAL))
		if pa == pb:
			# Fresher (lower age) first; then newer added_day.
			var aa := int(a.get("age_days", 0))
			var ab := int(b.get("age_days", 0))
			if aa == ab:
				return int(a.get("added_day", 0)) > int(b.get("added_day", 0))
			return aa < ab
		return pa > pb
	)


func _trim_overflow() -> void:
	if active_rumors.size() <= MAX_ACTIVE_RUMORS:
		return
	_sort_by_priority()
	while active_rumors.size() > MAX_ACTIVE_RUMORS:
		var dropped: Dictionary = active_rumors.pop_back()
		var rid: StringName = dropped.get("id")
		_record_expired(rid)
		rumor_expired.emit(rid)


func _record_expired(rumor_id: StringName) -> void:
	recently_expired.push_front(rumor_id)
	while recently_expired.size() > MAX_RECENTLY_EXPIRED:
		recently_expired.pop_back()


func _day_stamp() -> int:
	if WorldClock:
		return WorldClock.day
	return 0
