extends Node
## Character vitals stub — protagonist (Cian Ó Braonáin) + optional companion slot.
##
## Data + signals + clamp/modify API for HUD / feel binding later.
## Not a combat sim (see CombatSystem) and not band upkeep (see BandUpkeep).
## CombatSystem remains the per-entity melee component; this bus is the
## session-level vitals surface Godot gameplay / HUD can connect to.

signal health_changed(current: float, maximum: float)
signal wounds_changed(count: int)
## Named wound tag applied (CombatTags); wound_delta already fed into add_wound when > 0.
signal wound_tag_applied(tag: StringName, wound_delta: int)
## Stagger CC tag applied (CombatTags); duration/interrupt for Godot feel hooks.
signal stagger_applied(tag: StringName, duration_sec: float, interrupt_strength: int)
signal vital_depleted(vital: StringName)
signal vital_restored(vital: StringName)
signal downed_changed(is_downed: bool)
## Stub only — no death scene / load flow yet.
signal died()
signal companion_changed(active: bool, companion_id: StringName)
signal companion_health_changed(current: float, maximum: float)

## Display name for debug / future HUD (protagonist).
const PROTAGONIST_NAME := "Cian Ó Braonáin"
const SLOT_PLAYER := &"player"
const SLOT_COMPANION := &"companion"

## Protagonist vitals (slice defaults).
var max_hp: float = 100.0
var hp: float = 100.0
## No stamina vital (removed game-wide).
## Soft injury counter (0..MAX_WOUNDS). Not a full injury sim.
var wounds: int = 0
const MAX_WOUNDS: int = 5
## Recent named wound tags (CombatTags) — stub list, cleared on restore/clear_wounds.
const MAX_WOUND_TAGS: int = 8
var wound_tags: Array[StringName] = []
var last_wound_tag: StringName = &""
var last_stagger_tag: StringName = &""
var last_stagger_duration_sec: float = 0.0
var last_stagger_interrupt: int = 0

## Bleed / wound decay (WoundDecayTable) — stub timers; wiped by clear/restore.
## Parallel ages for wound_tags (same length). Soft counter decays ALWAYS
## (table OOC gate off by default). See systems/combat/wound_decay_table.gd.
var enable_wound_decay: bool = true
## Godot / combat can set true to pause soft-counter when table OOC-only is on.
var in_combat: bool = false
var wound_tag_ages: Array[float] = []
var _bleed_tick_accum: float = 0.0
var _soft_wound_decay_accum: float = 0.0
var last_bleed_hp: float = 0.0
var last_bleed_rate: float = 0.0

## Death / downed stub — HUD can show "downed"; no fancy scene.
var is_downed: bool = false
var is_dead: bool = false

## Optional single companion slot (not band roster).
var companion_active: bool = false
var companion_id: StringName = &""
var companion_display_name: String = ""
var companion_max_hp: float = 80.0
var companion_hp: float = 80.0
var companion_is_downed: bool = false

## When true, Health debug HUD may poll get_debug_text() cheaply.
var debug_visible: bool = false


func _ready() -> void:
	_emit_all_player()


func _process(delta: float) -> void:
	if not enable_wound_decay:
		return
	if is_dead:
		return
	_tick_wound_decay(delta)


func _emit_all_player() -> void:
	health_changed.emit(hp, max_hp)
	wounds_changed.emit(wounds)


# --- Player HP -----------------------------------------------------------------

func get_hp() -> float:
	return hp


func get_max_hp() -> float:
	return max_hp


func set_max_hp(value: float, fill: bool = false) -> void:
	max_hp = maxf(1.0, value)
	if fill:
		hp = max_hp
	else:
		hp = clampf(hp, 0.0, max_hp)
	health_changed.emit(hp, max_hp)
	_recompute_downed_from_hp()


func set_hp(value: float) -> void:
	var before := hp
	hp = clampf(value, 0.0, max_hp)
	if is_equal_approx(before, hp):
		_recompute_downed_from_hp()
		return
	health_changed.emit(hp, max_hp)
	_notify_vital_edges(&"hp", before, hp, max_hp)
	_recompute_downed_from_hp()


## Positive heals, negative damages. Returns applied delta after clamp.
func modify_hp(amount: float) -> float:
	var before := hp
	set_hp(hp + amount)
	return hp - before


func is_hp_full() -> bool:
	return hp >= max_hp


func is_hp_depleted() -> bool:
	return hp <= 0.0


# --- Wounds --------------------------------------------------------------------

func get_wounds() -> int:
	return wounds


func set_wounds(count: int) -> void:
	var next := clampi(count, 0, MAX_WOUNDS)
	if next == wounds:
		return
	wounds = next
	wounds_changed.emit(wounds)


func modify_wounds(delta: int) -> int:
	var before := wounds
	set_wounds(wounds + delta)
	return wounds - before


func add_wound(count: int = 1) -> int:
	return modify_wounds(count)


func clear_wounds() -> void:
	set_wounds(0)
	clear_wound_tags()


# --- Named combat tags (CombatTags stub) --------------------------------------

func get_wound_tags() -> Array[StringName]:
	return wound_tags.duplicate()


func clear_wound_tags() -> void:
	wound_tags.clear()
	wound_tag_ages.clear()
	_bleed_tick_accum = 0.0
	_soft_wound_decay_accum = 0.0
	last_bleed_hp = 0.0
	last_bleed_rate = 0.0
	last_wound_tag = &""
	last_stagger_tag = &""
	last_stagger_duration_sec = 0.0
	last_stagger_interrupt = 0


## Apply a CombatTags wound tag: optional soft-counter tick + list/signal.
## Returns applied wound delta (after clamp via add_wound).
func apply_wound_tag(tag: StringName) -> int:
	var entry: Dictionary = CombatTags.wound_entry(tag)
	if entry.is_empty():
		push_warning("CharacterHealth.apply_wound_tag: unknown wound tag %s" % String(tag))
		return 0
	var delta := int(entry.get("wound_delta", 0))
	var applied := 0
	if delta != 0:
		applied = add_wound(delta)
	last_wound_tag = tag
	wound_tags.append(tag)
	wound_tag_ages.append(0.0)
	while wound_tags.size() > MAX_WOUND_TAGS:
		wound_tags.pop_front()
		if wound_tag_ages.size() > 0:
			wound_tag_ages.pop_front()
	_sync_wound_tag_ages()
	wound_tag_applied.emit(tag, delta)
	return applied


## Record a CombatTags stagger for HUD / feel listeners (no full CC sim here).
func apply_stagger_tag(tag: StringName) -> Dictionary:
	var entry: Dictionary = CombatTags.stagger_entry(tag)
	if entry.is_empty():
		push_warning("CharacterHealth.apply_stagger_tag: unknown stagger tag %s" % String(tag))
		return {}
	last_stagger_tag = tag
	last_stagger_duration_sec = float(entry.get("duration_sec", 0.0))
	last_stagger_interrupt = int(entry.get("interrupt_strength", 0))
	stagger_applied.emit(tag, last_stagger_duration_sec, last_stagger_interrupt)
	return entry


## Apply a mixed list of CombatTags ids (wound and/or stagger).
func apply_combat_tags(tags: Array) -> Dictionary:
	var wounds_applied := 0
	var staggers: Array[StringName] = []
	var wound_names: Array[StringName] = []
	for item in tags:
		var tag: StringName = item as StringName if typeof(item) == TYPE_STRING_NAME else StringName(str(item))
		if CombatTags.is_wound(tag):
			wounds_applied += apply_wound_tag(tag)
			wound_names.append(tag)
		elif CombatTags.is_stagger(tag):
			apply_stagger_tag(tag)
			staggers.append(tag)
	return {
		"wound_tags": wound_names,
		"stagger_tags": staggers,
		"wounds_applied": wounds_applied,
	}


# --- Downed / death stub -------------------------------------------------------

func get_is_downed() -> bool:
	return is_downed


func get_is_dead() -> bool:
	return is_dead


func is_alive() -> bool:
	return not is_dead and not is_downed


## Force downed/dead flags (slice / scripted beats). HP left as-is unless zeroed.
func set_downed(downed: bool, mark_dead: bool = false) -> void:
	var was_downed := is_downed
	var was_dead := is_dead
	is_downed = downed
	if mark_dead:
		is_dead = true
		is_downed = true
	elif not downed:
		is_dead = false
	if is_downed != was_downed:
		downed_changed.emit(is_downed)
	if is_dead and not was_dead:
		died.emit()


## Clear downed/dead and optionally refill vitals (sanctuary / rest beat later).
func revive(fill_vitals: bool = true) -> void:
	var was_downed := is_downed
	is_dead = false
	is_downed = false
	if fill_vitals:
		set_hp(max_hp)
		clear_wounds()
	elif hp <= 0.0:
		set_hp(maxf(1.0, max_hp * 0.25))
	if was_downed:
		downed_changed.emit(false)
		vital_restored.emit(&"hp")


func restore_full() -> void:
	set_hp(max_hp)
	clear_wounds()
	if is_downed or is_dead:
		revive(false)


func _recompute_downed_from_hp() -> void:
	if hp <= 0.0:
		if not is_downed:
			is_downed = true
			downed_changed.emit(true)
		if not is_dead:
			is_dead = true
			died.emit()
	# Hitting 0 always marks dead stub; revive() is the only clear path.


func _notify_vital_edges(vital: StringName, before: float, after: float, maximum: float) -> void:
	if before > 0.0 and after <= 0.0:
		vital_depleted.emit(vital)
	elif before < maximum and is_equal_approx(after, maximum):
		vital_restored.emit(vital)
	elif before <= 0.0 and after > 0.0:
		vital_restored.emit(vital)


# --- Companion slot (optional, single) -----------------------------------------

func has_companion() -> bool:
	return companion_active and companion_id != &""


func set_companion(
	id: StringName,
	display_name: String = "",
	max_health: float = 80.0,
	current_hp: float = -1.0
) -> void:
	companion_id = id
	companion_display_name = display_name if display_name != "" else String(id)
	companion_max_hp = maxf(1.0, max_health)
	if current_hp < 0.0:
		companion_hp = companion_max_hp
	else:
		companion_hp = clampf(current_hp, 0.0, companion_max_hp)
	companion_active = id != &""
	companion_is_downed = companion_hp <= 0.0
	companion_changed.emit(companion_active, companion_id)
	companion_health_changed.emit(companion_hp, companion_max_hp)


func clear_companion() -> void:
	companion_active = false
	companion_id = &""
	companion_display_name = ""
	companion_hp = 0.0
	companion_max_hp = 80.0
	companion_is_downed = false
	companion_changed.emit(false, &"")
	companion_health_changed.emit(companion_hp, companion_max_hp)


func get_companion_hp() -> float:
	return companion_hp


func modify_companion_hp(amount: float) -> float:
	if not companion_active:
		return 0.0
	var before := companion_hp
	companion_hp = clampf(companion_hp + amount, 0.0, companion_max_hp)
	if not is_equal_approx(before, companion_hp):
		companion_health_changed.emit(companion_hp, companion_max_hp)
	companion_is_downed = companion_hp <= 0.0
	return companion_hp - before


# --- Bleed / wound decay (WoundDecayTable) ------------------------------------

func set_in_combat(active: bool) -> void:
	in_combat = active


func get_wound_decay_debug_text() -> String:
	return WoundDecayTable.get_debug_text(
		wound_tags, wounds, _bleed_tick_accum, _soft_wound_decay_accum
	)


func dump_wound_decay_table() -> void:
	print(get_wound_decay_debug_text())
	print(
		"CharacterHealth decay: enable=%s in_combat=%s bleed_rate=%.2f last_bleed=%.2f ages=%s" % [
			str(enable_wound_decay),
			str(in_combat),
			last_bleed_rate,
			last_bleed_hp,
			str(wound_tag_ages),
		]
	)


func _sync_wound_tag_ages() -> void:
	## Keep ages array length-matched to wound_tags (pad/truncate).
	while wound_tag_ages.size() < wound_tags.size():
		wound_tag_ages.append(0.0)
	while wound_tag_ages.size() > wound_tags.size():
		wound_tag_ages.pop_back()


func _tick_wound_decay(delta: float) -> void:
	_sync_wound_tag_ages()
	var has_tags := wound_tags.size() > 0
	var has_wounds := wounds > 0
	if not has_tags and not has_wounds:
		_bleed_tick_accum = 0.0
		_soft_wound_decay_accum = 0.0
		last_bleed_rate = 0.0
		return

	# Age tags + clear expired.
	if has_tags:
		var keep_tags: Array[StringName] = []
		var keep_ages: Array[float] = []
		for i in range(wound_tags.size()):
			var age := wound_tag_ages[i] + delta if i < wound_tag_ages.size() else delta
			var tag: StringName = wound_tags[i]
			var max_age := WoundDecayTable.decay_sec(tag)
			if max_age > 0.0 and age >= max_age:
				continue  # tag softens / clears
			keep_tags.append(tag)
			keep_ages.append(age)
		wound_tags = keep_tags
		wound_tag_ages = keep_ages
		if wound_tags.is_empty():
			last_wound_tag = &""

	# Bleed HP from active tags (sum rates), applied on tick interval.
	last_bleed_rate = WoundDecayTable.total_bleed_hp_per_sec(wound_tags)
	if last_bleed_rate > 0.0 and hp > 0.0:
		var interval := WoundDecayTable.resolve_tick_interval(wound_tags)
		_bleed_tick_accum += delta
		if _bleed_tick_accum >= interval:
			var elapsed := _bleed_tick_accum
			_bleed_tick_accum = 0.0
			var dmg := last_bleed_rate * elapsed
			last_bleed_hp = dmg
			modify_hp(-dmg)
	else:
		_bleed_tick_accum = 0.0
		last_bleed_hp = 0.0

	# Soft wound counter decay (ALWAYS unless table OOC-only + in_combat).
	if wounds > 0:
		var ooc_only := WoundDecayTable.soft_wound_decay_out_of_combat_only()
		var allow_soft := (not ooc_only) or (not in_combat)
		if allow_soft:
			_soft_wound_decay_accum += delta
			var need := WoundDecayTable.soft_wound_decay_sec()
			while wounds > 0 and _soft_wound_decay_accum >= need:
				_soft_wound_decay_accum -= need
				modify_wounds(-1)
		# else: paused in combat — leave accum (or freeze); freeze for clarity
		elif ooc_only and in_combat:
			pass
	else:
		_soft_wound_decay_accum = 0.0


# --- Snapshot / debug ----------------------------------------------------------

func to_debug_dict() -> Dictionary:
	return {
		"protagonist": PROTAGONIST_NAME,
		"hp": hp,
		"max_hp": max_hp,
		"wounds": wounds,
		"max_wounds": MAX_WOUNDS,
		"is_downed": is_downed,
		"is_dead": is_dead,
		"is_alive": is_alive(),
		"companion_active": companion_active,
		"companion_id": String(companion_id),
		"companion_name": companion_display_name,
		"companion_hp": companion_hp,
		"companion_max_hp": companion_max_hp,
		"companion_is_downed": companion_is_downed,
		"wound_tags": _wound_tags_as_strings(),
		"last_wound_tag": String(last_wound_tag),
		"last_stagger_tag": String(last_stagger_tag),
		"last_stagger_duration_sec": last_stagger_duration_sec,
		"last_stagger_interrupt": last_stagger_interrupt,
		"enable_wound_decay": enable_wound_decay,
		"in_combat": in_combat,
		"last_bleed_rate": last_bleed_rate,
		"last_bleed_hp": last_bleed_hp,
		"bleed_tick_accum": _bleed_tick_accum,
		"soft_wound_decay_accum": _soft_wound_decay_accum,
		"wound_tag_ages": wound_tag_ages.duplicate(),
		"debug_visible": debug_visible,
	}


func get_debug_text() -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== CharacterHealth / vitals ===")
	lines.append("Protagonist: %s" % str(d["protagonist"]))
	lines.append(
		"HP %.0f/%.0f   Wounds %d/%d" % [
			float(d["hp"]), float(d["max_hp"]),
			int(d["wounds"]), int(d["max_wounds"]),
		]
	)
	lines.append(
		"Flags: downed=%s  dead=%s  alive=%s" % [
			str(d["is_downed"]), str(d["is_dead"]), str(d["is_alive"]),
		]
	)
	if bool(d["companion_active"]):
		lines.append(
			"Companion: %s (%s)  HP %.0f/%.0f  downed=%s" % [
				str(d["companion_name"]),
				str(d["companion_id"]),
				float(d["companion_hp"]),
				float(d["companion_max_hp"]),
				str(d["companion_is_downed"]),
			]
		)
	else:
		lines.append("Companion: (none)")
	var tag_names: PackedStringArray = PackedStringArray()
	for t in wound_tags:
		tag_names.append(String(t))
	lines.append(
		"Tags: wounds=[%s] last_wound=%s  stagger=%s (%.2fs / int=%d)" % [
			", ".join(tag_names),
			String(last_wound_tag) if last_wound_tag != &"" else "-",
			String(last_stagger_tag) if last_stagger_tag != &"" else "-",
			last_stagger_duration_sec,
			last_stagger_interrupt,
		]
	)
	lines.append(
		"Decay: enable=%s in_combat=%s bleed_rate=%.2f hp/s last_bleed=%.2f soft_accum=%.1f" % [
			str(enable_wound_decay),
			str(in_combat),
			last_bleed_rate,
			last_bleed_hp,
			_soft_wound_decay_accum,
		]
	)
	lines.append("V toggle · 9/0 HP ±10 · 6 wound+ · 5 restore · 4 downed stub · F7 tags · F10 decay")
	lines.append("≠ CombatSystem alone (per-entity melee; player bridged). ≠ BandUpkeep (roster).")
	return "\n".join(lines)


func _wound_tags_as_strings() -> Array:
	var out: Array = []
	for t in wound_tags:
		out.append(String(t))
	return out


func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


func set_debug_visible(visible: bool) -> void:
	debug_visible = visible
