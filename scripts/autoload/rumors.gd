extends Node
## World news bus for offscreen events and opportunity hooks.
##
## Priority / severity (high→low sort) + decay (age vs lifetime) keep the bus
## useful (docs/SCOPE.md). Severity is an alias of priority. Default lifetimes
## and half-lives live in DEFAULT_DECAY_DAYS_BY_PRIORITY — high-severity rumors
## linger; low ones fade. Emitters: WorldClock event resolve, Honor swings,
## Faction attitude / relationship-graph / cattle-raid heat / sanctuary-breach
## swings — see systems/rumors/README.md. Optional light reverse: high-priority faction-tagged
## rumors can nudge attitudes.

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

## Severity is a documented alias of priority (same ints / ladder).
const SEVERITY_LOW: int = PRIORITY_LOW
const SEVERITY_NORMAL: int = PRIORITY_NORMAL
const SEVERITY_HIGH: int = PRIORITY_HIGH
const SEVERITY_CRITICAL: int = PRIORITY_CRITICAL

## Default full lifetime (days on the bus) by priority/severity.
## Callers may still pass an explicit decay_days; pass 0 / omit to use this table.
## High severity lingers; low severity fades. Half-life ≈ ceil(lifetime / 2).
const DEFAULT_DECAY_DAYS_BY_PRIORITY := {
	PRIORITY_LOW: 4,
	PRIORITY_NORMAL: 7,
	PRIORITY_HIGH: 12,
	PRIORITY_CRITICAL: 18,
}

## Documented half-life (days) by priority — informational midpoint, not a second
## drop timer. Hard drop remains age_days >= decay_days on tick_decay.
const DEFAULT_HALF_LIFE_DAYS_BY_PRIORITY := {
	PRIORITY_LOW: 2,
	PRIORITY_NORMAL: 4,
	PRIORITY_HIGH: 6,
	PRIORITY_CRITICAL: 9,
}

## Soft cap so the bus cannot grow without bound in long plays.
const MAX_ACTIVE_RUMORS: int = 32

## Active rumor dictionaries (see add_rumor / rumor_schema).
var active_rumors: Array[Dictionary] = []

## Ring of recently expired ids (debug / UI toast hooks).
var recently_expired: Array[StringName] = []
const MAX_RECENTLY_EXPIRED: int = 8

## Tag vocabulary for diplomatic / faction / raid-heat / sanctuary coupling
## (see systems/rumors/README.md).
const TAG_ATTITUDE: StringName = &"attitude"
const TAG_GRAPH: StringName = &"graph"
const TAG_RAID: StringName = &"raid"
const TAG_HEAT: StringName = &"heat"
const TAG_RETALIATION: StringName = &"retaliation"
const TAG_CHURCH: StringName = &"church"
const TAG_SANCTUARY: StringName = &"sanctuary"
const TAG_BREACH: StringName = &"breach"
const TAG_DIRECTION_WARMER: StringName = &"direction:warmer"
const TAG_DIRECTION_COLDER: StringName = &"direction:colder"
const TAG_FACTION_PREFIX: String = "faction:"

## Light reverse coupling: HIGH+ faction-tagged rumors may nudge player attitudes.
## Skipped for sources that Factions / raid / sanctuary themselves seed (avoids loops).
const FACTION_NUDGE_MIN_PRIORITY: int = PRIORITY_HIGH
const FACTION_NUDGE_AMOUNT: float = 2.0
const FACTION_NUDGE_SKIP_SOURCES: Array[StringName] = [
	&"faction", &"faction_graph", &"raid", &"sanctuary_breach",
]

## When true, Rumors debug HUD may poll get_debug_text() cheaply.
var debug_visible: bool = false
## Gate for reverse attitude nudge (Lead can flip off if noisy).
var faction_nudge_enabled: bool = true


func _ready() -> void:
	if WorldClock and not WorldClock.day_advanced.is_connected(_on_day_advanced):
		WorldClock.day_advanced.connect(_on_day_advanced)


func _on_day_advanced(_day: int) -> void:
	tick_decay(1)


## Schema keys for each rumor dict:
##   id, text, source_event, heard, priority, decay_days, age_days, added_day, tags
func rumor_schema_keys() -> PackedStringArray:
	return PackedStringArray([
		"id", "text", "source_event", "heard",
		"priority", "decay_days", "age_days", "added_day", "tags",
	])


## Build a `faction:<id>` tag for diplomatic coupling.
func faction_tag(faction_id: StringName) -> StringName:
	return StringName("%s%s" % [TAG_FACTION_PREFIX, String(faction_id)])


## Extract roster faction ids from a tags array (unknown strings ignored).
func faction_ids_from_tags(tags: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for tag in tags:
		var s := String(tag)
		if not s.begins_with(TAG_FACTION_PREFIX):
			continue
		var fid := StringName(s.substr(TAG_FACTION_PREFIX.length()))
		if fid == &"":
			continue
		if fid not in out:
			out.append(fid)
	return out


func rumor_has_tag(rumor: Dictionary, tag: StringName) -> bool:
	var tags: Array = rumor.get("tags", [])
	for t in tags:
		if t == tag or String(t) == String(tag):
			return true
	return false


## Direction tag helper — warmer / colder / empty.
func direction_from_tags(tags: Array) -> StringName:
	for tag in tags:
		if tag == TAG_DIRECTION_WARMER or String(tag) == String(TAG_DIRECTION_WARMER):
			return TAG_DIRECTION_WARMER
		if tag == TAG_DIRECTION_COLDER or String(tag) == String(TAG_DIRECTION_COLDER):
			return TAG_DIRECTION_COLDER
	return &""


func priority_label(priority: int) -> String:
	return str(PRIORITY_LABELS.get(priority, "normal"))


## Alias of priority_label — severity and priority share the same ladder.
func severity_label(severity: int) -> String:
	return priority_label(severity)


func clamp_priority(priority: int) -> int:
	return clampi(priority, PRIORITY_LOW, PRIORITY_CRITICAL)


func clamp_severity(severity: int) -> int:
	return clamp_priority(severity)


## Table default full lifetime for a priority/severity. Unknown → NORMAL row.
func default_decay_days(priority: int) -> int:
	priority = clamp_priority(priority)
	return int(DEFAULT_DECAY_DAYS_BY_PRIORITY.get(priority, DEFAULT_DECAY_DAYS_BY_PRIORITY[PRIORITY_NORMAL]))


## Table default half-life (informational) for a priority/severity.
func default_half_life_days(priority: int) -> int:
	priority = clamp_priority(priority)
	return int(DEFAULT_HALF_LIFE_DAYS_BY_PRIORITY.get(priority, DEFAULT_HALF_LIFE_DAYS_BY_PRIORITY[PRIORITY_NORMAL]))


## Resolve lifetime: override <= 0 → table default for priority; else max(1, override).
func resolve_decay_days(priority: int, decay_days_override: int = 0) -> int:
	if decay_days_override <= 0:
		return default_decay_days(priority)
	return maxi(1, decay_days_override)


## Snapshot of the severity → lifetime / half-life table (docs + remote probe).
func decay_table() -> Dictionary:
	var rows: Array = []
	for p in [PRIORITY_LOW, PRIORITY_NORMAL, PRIORITY_HIGH, PRIORITY_CRITICAL]:
		var life := default_decay_days(p)
		rows.append({
			"priority": p,
			"severity": p,
			"label": priority_label(p),
			"decay_days": life,
			"half_life_days": default_half_life_days(p),
			"per_day_rate": 1.0 / float(life),
		})
	return {
		"rows": rows,
		"note": "Hard drop when age_days >= decay_days. Half-life is midpoint only.",
	}


## Days left before expiry (0 = expires on next tick_decay).
func days_remaining(rumor: Dictionary) -> int:
	var life := maxi(1, int(rumor.get("decay_days", default_decay_days(PRIORITY_NORMAL))))
	var age := maxi(0, int(rumor.get("age_days", 0)))
	return maxi(0, life - age)


## Informational half-life for a rumor dict (ceil(decay_days / 2), min 1).
func half_life_days(rumor: Dictionary) -> int:
	var life := maxi(1, int(rumor.get("decay_days", default_decay_days(PRIORITY_NORMAL))))
	return maxi(1, int(ceili(float(life) / 2.0)))


## Fraction of lifetime consumed (0.0 fresh → 1.0+ expired/at drop).
func decay_progress(rumor: Dictionary) -> float:
	var life := maxi(1, int(rumor.get("decay_days", default_decay_days(PRIORITY_NORMAL))))
	var age := maxi(0, int(rumor.get("age_days", 0)))
	return float(age) / float(life)


## True once age has reached or passed the half-life midpoint (still on the bus).
func is_past_half_life(rumor: Dictionary) -> bool:
	return int(rumor.get("age_days", 0)) >= half_life_days(rumor)


## Per-day life consumption rate (1 / decay_days).
func decay_rate_per_day(rumor: Dictionary) -> float:
	var life := maxi(1, int(rumor.get("decay_days", default_decay_days(PRIORITY_NORMAL))))
	return 1.0 / float(life)


## Severity / priority int on a rumor dict (clamped).
func rumor_severity(rumor: Dictionary) -> int:
	return clamp_priority(int(rumor.get("priority", PRIORITY_NORMAL)))


## Add or refresh a rumor. Higher priority wins on refresh; decay_days is lifetime.
## Pass decay_days <= 0 to use DEFAULT_DECAY_DAYS_BY_PRIORITY for the priority.
## age_days resets to 0 on refresh (word is fresh again).
## tags: optional StringName list (e.g. faction:*, direction:*, graph, attitude, raid, heat,
## church, sanctuary, breach).
func add_rumor(
	rumor_id: StringName,
	text: String,
	source_event: StringName = &"",
	priority: int = PRIORITY_NORMAL,
	decay_days: int = 0,
	tags: Array = []
) -> void:
	priority = clamp_priority(priority)
	decay_days = resolve_decay_days(priority, decay_days)
	var normalized_tags := _normalize_tags(tags)
	var added_day := _day_stamp()
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			rumor["text"] = text
			rumor["source_event"] = source_event
			rumor["priority"] = maxi(int(rumor.get("priority", PRIORITY_NORMAL)), priority)
			rumor["decay_days"] = maxi(int(rumor.get("decay_days", decay_days)), decay_days)
			rumor["age_days"] = 0
			rumor["added_day"] = added_day
			if not normalized_tags.is_empty():
				rumor["tags"] = _merge_tags(rumor.get("tags", []), normalized_tags)
			_sort_by_priority()
			rumor_added.emit(rumor_id)
			# Reverse nudge only on first add — refresh must not re-nudge.
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
		"tags": normalized_tags,
	}
	active_rumors.append(entry)
	_trim_overflow()
	_sort_by_priority()
	rumor_added.emit(rumor_id)
	_maybe_nudge_factions_from_rumor(entry)


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


## Advance age by `days`; drop rumors where age_days >= decay_days (hard cut).
## Half-life is informational only — no probabilistic drop at midpoint.
## Wired on WorldClock.day_advanced (1 day). Returns expired ids.
## Emits rumor_expired per id, then rumors_decayed(expired_ids) if any dropped.
func tick_decay(days: int = 1) -> Array[StringName]:
	days = maxi(0, days)
	if days == 0:
		return [] as Array[StringName]
	var expired_ids: Array[StringName] = []
	var remaining: Array[Dictionary] = []
	for rumor in active_rumors:
		rumor["age_days"] = int(rumor.get("age_days", 0)) + days
		var life := maxi(1, int(rumor.get("decay_days", default_decay_days(PRIORITY_NORMAL))))
		if int(rumor.get("age_days", 0)) >= life:
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
## require_tag: when non-empty, rumor must carry that tag.
func filter_rumors(
	min_priority: int = 0,
	source_event: StringName = &"",
	unheard_only: bool = false,
	heard_only: bool = false,
	require_tag: StringName = &""
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
		if require_tag != &"" and not rumor_has_tag(rumor, require_tag):
			continue
		out.append(rumor.duplicate(true))
	return out


## Convenience: all active rumors tagged with a given faction id.
func filter_by_faction(faction_id: StringName, min_priority: int = 0) -> Array[Dictionary]:
	return filter_rumors(min_priority, &"", false, false, faction_tag(faction_id))


## Active rumors at or above a severity/priority floor (inclusive). Alias of filter_rumors.
func filter_by_severity(min_severity: int = SEVERITY_LOW) -> Array[Dictionary]:
	return filter_rumors(clamp_severity(min_severity))


## Active rumors by severity. exact=true → that rung only; false → severity >= floor.
func get_active_by_severity(severity: int, exact: bool = false) -> Array[Dictionary]:
	severity = clamp_severity(severity)
	_sort_by_priority()
	var out: Array[Dictionary] = []
	for rumor in active_rumors:
		var p := rumor_severity(rumor)
		if exact:
			if p != severity:
				continue
		elif p < severity:
			continue
		out.append(rumor.duplicate(true))
	return out


## Count active rumors per severity rung (keys: low/normal/high/critical + total).
func severity_counts() -> Dictionary:
	var counts := {
		"low": 0,
		"normal": 0,
		"high": 0,
		"critical": 0,
		"total": count_active(),
	}
	for rumor in active_rumors:
		var label := priority_label(rumor_severity(rumor))
		counts[label] = int(counts.get(label, 0)) + 1
	return counts


## Rumors that will hard-drop within `within_days` more tick_decay days (inclusive).
## within_days=0 → already at left=0 (expire on next tick). Sorted priority-first.
func peek_expiring(within_days: int = 1) -> Array[Dictionary]:
	within_days = maxi(0, within_days)
	_sort_by_priority()
	var out: Array[Dictionary] = []
	for rumor in active_rumors:
		if days_remaining(rumor) <= within_days:
			out.append(rumor.duplicate(true))
	return out


func clear_all() -> void:
	active_rumors.clear()


## Greybox helper — one line per severity rung using table default lifetimes.
## Pass decay_days=0 so DEFAULT_DECAY_DAYS_BY_PRIORITY applies (low fades, critical lingers).
func seed_demo_rumors() -> void:
	add_rumor(
		&"demo_market_whisper",
		"Cattle buyers at the crossroads mutter about thin herds inland.",
		&"demo",
		PRIORITY_LOW,
		0
	)
	add_rumor(
		&"demo_fian_sighting",
		"A fían band was seen near the bog road at dusk.",
		&"demo",
		PRIORITY_NORMAL,
		0
	)
	add_rumor(
		&"demo_church_bell",
		"Word of sanctuary: the monastery will shelter the desperate — for a price in penance.",
		&"demo",
		PRIORITY_HIGH,
		0
	)
	add_rumor(
		&"demo_bannow_landing_echo",
		"Couriers still carry word of the strangers' landing — the beachhead rumor will not die quickly.",
		&"demo",
		PRIORITY_CRITICAL,
		0
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
		"faction_nudge_enabled": faction_nudge_enabled,
		"severity_counts": severity_counts(),
		"decay_table": decay_table(),
		"top": top,
		"recent": recent,
		"recently_expired": expired,
		"peek_expiring_1": _debug_rows(peek_expiring(1)),
		"day": _day_stamp(),
	}


func get_debug_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Rumors bus debug ===")
	var counts := severity_counts()
	lines.append(
		"Active: %d   Day: %d   (N toggle · M seed · , decay · . diplomatic)" % [
			count_active(), _day_stamp(),
		]
	)
	lines.append(
		"Severity counts: L%d N%d H%d C%d · Decay: age≥life → drop (half-life = midpoint)" % [
			int(counts["low"]), int(counts["normal"]),
			int(counts["high"]), int(counts["critical"]),
		]
	)
	lines.append(
		"Default life/half: L %d/%d · N %d/%d · H %d/%d · C %d/%d" % [
			default_decay_days(PRIORITY_LOW), default_half_life_days(PRIORITY_LOW),
			default_decay_days(PRIORITY_NORMAL), default_half_life_days(PRIORITY_NORMAL),
			default_decay_days(PRIORITY_HIGH), default_half_life_days(PRIORITY_HIGH),
			default_decay_days(PRIORITY_CRITICAL), default_half_life_days(PRIORITY_CRITICAL),
		]
	)
	var top := get_top_rumors(6)
	if top.is_empty():
		lines.append("Top: (none — Y resolve Bannow, or M seed demo)")
	else:
		lines.append("Top (severity):")
		for rumor in top:
			lines.append("  %s" % _format_rumor_line(rumor))
	var expiring := peek_expiring(1)
	if not expiring.is_empty():
		var bits: PackedStringArray = PackedStringArray()
		for rumor in expiring:
			bits.append(String(rumor.get("id", &"")))
		lines.append("Expiring next tick: %s" % ", ".join(bits))
	if not recently_expired.is_empty():
		var ids: PackedStringArray = PackedStringArray()
		for rid in recently_expired:
			ids.append(String(rid))
		lines.append("Expired lately: %s" % ", ".join(ids))
	return "\n".join(lines)


func _format_rumor_line(rumor: Dictionary) -> String:
	var tag_bits := _tags_debug_suffix(rumor.get("tags", []))
	var past_hl := " hl+" if is_past_half_life(rumor) else ""
	return "[%s P%d left=%d a%d life=%d%s%s%s] %s" % [
		priority_label(rumor_severity(rumor)),
		rumor_severity(rumor),
		days_remaining(rumor),
		int(rumor.get("age_days", 0)),
		int(rumor.get("decay_days", 0)),
		past_hl,
		" heard" if bool(rumor.get("heard", false)) else "",
		tag_bits,
		str(rumor.get("text", "")),
	]


func _rumor_debug_row(rumor: Dictionary) -> Dictionary:
	var tag_strings: Array = []
	for t in rumor.get("tags", []):
		tag_strings.append(String(t))
	var sev := rumor_severity(rumor)
	return {
		"id": rumor.get("id"),
		"text": rumor.get("text"),
		"source_event": rumor.get("source_event"),
		"priority": sev,
		"severity": sev,
		"priority_label": priority_label(sev),
		"severity_label": severity_label(sev),
		"decay_days": rumor.get("decay_days"),
		"half_life_days": half_life_days(rumor),
		"decay_progress": decay_progress(rumor),
		"decay_rate_per_day": decay_rate_per_day(rumor),
		"past_half_life": is_past_half_life(rumor),
		"age_days": rumor.get("age_days"),
		"days_remaining": days_remaining(rumor),
		"heard": rumor.get("heard"),
		"added_day": rumor.get("added_day"),
		"tags": tag_strings,
	}


func _debug_rows(rumors: Array) -> Array:
	var out: Array = []
	for rumor in rumors:
		out.append(_rumor_debug_row(rumor))
	return out


## Remote / F5 probe — decay table, severity counts, optional demo seed, tick notes.
## seed_if_empty: when true and bus empty, calls seed_demo_rumors() first.
func probe_decay(seed_if_empty: bool = false) -> Dictionary:
	if seed_if_empty and count_active() == 0:
		seed_demo_rumors()
	var by_severity := {
		"low": _debug_rows(get_active_by_severity(SEVERITY_LOW, true)),
		"normal": _debug_rows(get_active_by_severity(SEVERITY_NORMAL, true)),
		"high": _debug_rows(get_active_by_severity(SEVERITY_HIGH, true)),
		"critical": _debug_rows(get_active_by_severity(SEVERITY_CRITICAL, true)),
	}
	return {
		"ok": true,
		"day": _day_stamp(),
		"active_count": count_active(),
		"severity_counts": severity_counts(),
		"decay_table": decay_table(),
		"by_severity": by_severity,
		"peek_expiring_1": _debug_rows(peek_expiring(1)),
		"tick_behavior": {
			"hard_drop": "age_days >= decay_days",
			"half_life": "informational midpoint only (no stochastic drop)",
			"wiring": "WorldClock.day_advanced → tick_decay(1)",
			"manual": "tick_decay(n) / F5 comma key",
		},
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


func _normalize_tags(tags: Array) -> Array:
	var out: Array = []
	for tag in tags:
		var sn: StringName
		if typeof(tag) == TYPE_STRING_NAME:
			sn = tag
		else:
			sn = StringName(str(tag))
		if sn == &"":
			continue
		var already := false
		for existing in out:
			if existing == sn:
				already = true
				break
		if not already:
			out.append(sn)
	return out


func _merge_tags(existing: Array, incoming: Array) -> Array:
	var merged := _normalize_tags(existing)
	for tag in _normalize_tags(incoming):
		var already := false
		for e in merged:
			if e == tag:
				already = true
				break
		if not already:
			merged.append(tag)
	return merged


func _tags_debug_suffix(tags: Array) -> String:
	if tags.is_empty():
		return ""
	var bits: PackedStringArray = PackedStringArray()
	for t in tags:
		bits.append(String(t))
	return " {%s}" % ",".join(bits)


## Optional reverse: HIGH+ faction-tagged rumor lightly nudges player attitudes.
## Gated; skips Factions-seeded sources so graph/attitude → rumor cannot loop.
func _maybe_nudge_factions_from_rumor(rumor: Dictionary) -> void:
	if not faction_nudge_enabled:
		return
	if Factions == null:
		return
	var priority := int(rumor.get("priority", PRIORITY_NORMAL))
	if priority < FACTION_NUDGE_MIN_PRIORITY:
		return
	var source: StringName = rumor.get("source_event", &"")
	if source in FACTION_NUDGE_SKIP_SOURCES:
		return
	var tags: Array = rumor.get("tags", [])
	var faction_ids := faction_ids_from_tags(tags)
	if faction_ids.is_empty():
		return
	var direction := direction_from_tags(tags)
	if direction == &"":
		return
	var delta := FACTION_NUDGE_AMOUNT if direction == TAG_DIRECTION_WARMER else -FACTION_NUDGE_AMOUNT
	for fid in faction_ids:
		# seed_rumor=false — nudge stays below attitude rumor threshold anyway,
		# but keep the path silent so Lead can raise nudge later without loops.
		Factions.modify_attitude(fid, delta, false)


func _day_stamp() -> int:
	if WorldClock:
		return WorldClock.day
	return 0
