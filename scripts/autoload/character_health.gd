extends Node
## Character vitals stub — protagonist (Cian Ó Braonáin) + optional companion slot.
##
## Data + signals + clamp/modify API for HUD / feel binding later.
## Not a combat sim (see CombatSystem) and not band upkeep (see BandUpkeep).
## CombatSystem remains the per-entity melee component; this bus is the
## session-level vitals surface Godot gameplay / HUD can connect to.

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal wounds_changed(count: int)
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
var max_stamina: float = 100.0
var stamina: float = 100.0
## Soft injury counter (0..MAX_WOUNDS). Not a full injury sim.
var wounds: int = 0
const MAX_WOUNDS: int = 5

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


func _emit_all_player() -> void:
	health_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
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


# --- Player stamina ------------------------------------------------------------

func get_stamina() -> float:
	return stamina


func get_max_stamina() -> float:
	return max_stamina


func set_max_stamina(value: float, fill: bool = false) -> void:
	max_stamina = maxf(1.0, value)
	if fill:
		stamina = max_stamina
	else:
		stamina = clampf(stamina, 0.0, max_stamina)
	stamina_changed.emit(stamina, max_stamina)


func set_stamina(value: float) -> void:
	var before := stamina
	stamina = clampf(value, 0.0, max_stamina)
	if is_equal_approx(before, stamina):
		return
	stamina_changed.emit(stamina, max_stamina)
	_notify_vital_edges(&"stamina", before, stamina, max_stamina)


func modify_stamina(amount: float) -> float:
	var before := stamina
	set_stamina(stamina + amount)
	return stamina - before


func is_stamina_depleted() -> bool:
	return stamina <= 0.0


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
		set_stamina(max_stamina)
		clear_wounds()
	elif hp <= 0.0:
		set_hp(maxf(1.0, max_hp * 0.25))
	if was_downed:
		downed_changed.emit(false)
		vital_restored.emit(&"hp")


func restore_full() -> void:
	set_hp(max_hp)
	set_stamina(max_stamina)
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


# --- Snapshot / debug ----------------------------------------------------------

func to_debug_dict() -> Dictionary:
	return {
		"protagonist": PROTAGONIST_NAME,
		"hp": hp,
		"max_hp": max_hp,
		"stamina": stamina,
		"max_stamina": max_stamina,
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
		"debug_visible": debug_visible,
	}


func get_debug_text() -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== CharacterHealth / vitals ===")
	lines.append("Protagonist: %s" % str(d["protagonist"]))
	lines.append(
		"HP %.0f/%.0f   STA %.0f/%.0f   Wounds %d/%d" % [
			float(d["hp"]), float(d["max_hp"]),
			float(d["stamina"]), float(d["max_stamina"]),
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
	lines.append("V toggle · 9/0 HP ±10 · 7/8 STA ±10 · 6 wound+ · 5 restore · 4 downed stub")
	lines.append("≠ CombatSystem alone (per-entity melee; player bridged). ≠ BandUpkeep (roster).")
	return "\n".join(lines)


func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


func set_debug_visible(visible: bool) -> void:
	debug_visible = visible
