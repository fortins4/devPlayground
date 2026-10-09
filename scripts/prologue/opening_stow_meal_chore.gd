extends Node3D
class_name OpeningStowMealChore
## Closing morning beat: stow the goad (key 1 / unarmed), then E-eat a greybox meal
## by the house. Additive soft cue; does not gate cattle soft success.
## E: Cian walks to the seat beside the low stool, sits on the ground at it (input locked), eats,
## then rises back into foot loco (PlayerController.begin_seat / end_seat).

enum MealPhase { WAITING, SEATING, EATING, DONE }

const INTERACT_RANGE := 2.5
## Near Máire (−5.2,0.1,3.2) / house door — clear of bucket & hitch.
const MEAL_POS := Vector3(-4.5, 0.0, 2.8)
## Where Cian sits: on the ground just east of the stool, facing it (west, toward the house).
const SEAT_POS := Vector3(-3.8, 0.0, 2.8)
const SEAT_YAW := PI * 0.5
const SEATING_MAX_SECS := 5.0

const C_WOOD := Color(0.40, 0.28, 0.16)
const C_WOOD_DARK := Color(0.28, 0.20, 0.12)
const C_BOWL := Color(0.55, 0.48, 0.38)
const C_STEW := Color(0.48, 0.32, 0.18)
const C_STEW_EMPTY := Color(0.42, 0.36, 0.28)
const C_BREAD := Color(0.72, 0.58, 0.38)
const C_CLOTH := Color(0.62, 0.58, 0.48)

const SEQ_STEP := &"meal"

@export var director_path: NodePath = ^"../OpeningDriveDirector"

var _phase: MealPhase = MealPhase.WAITING
var _player: Node3D = null
var _director: Node = null
var _sequence: Node = null
var _meal_root: Node3D = null
var _stew: MeshInstance3D = null
var _eat_t: float = 0.0
var _mats: Dictionary = {}
const EAT_SECS := 1.4


func _ready() -> void:
	add_to_group("opening_stow_meal")
	_build_props()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	print("OPENING_STOW_MEAL_READY meal=%s" % MEAL_POS)


func _process(delta: float) -> void:
	if _phase == MealPhase.SEATING:
		_eat_t += delta
		var st := String(_player.call("seat_state")) if _player and _player.has_method("seat_state") else "seated"
		if st == "seated" or _eat_t > SEATING_MAX_SECS:
			_phase = MealPhase.EATING
			_eat_t = EAT_SECS
			print("OPENING_STOW_MEAL_EATING")
		return
	if _phase != MealPhase.EATING:
		return
	_eat_t -= delta
	if _eat_t <= 0.0:
		_finish_meal(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries

func chore_done() -> bool:
	return _phase == MealPhase.DONE


func meal_state() -> String:
	match _phase:
		MealPhase.WAITING:
			if _player and is_instance_valid(_player) and _near(_player.global_position, MEAL_POS):
				if _is_unarmed():
					return "ready_to_eat"
				return "need_stow"
			return "need_stow"
		MealPhase.SEATING:
			return "sitting"
		MealPhase.EATING:
			return "eating"
		MealPhase.DONE:
			return "done"
	return "unknown"


func meal_pos() -> Vector3:
	return MEAL_POS


func seat_pos() -> Vector3:
	return SEAT_POS


func interact_prompt() -> String:
	if _phase != MealPhase.WAITING:
		return ""
	if _player == null or not is_instance_valid(_player):
		return ""
	if not _near(_player.global_position, MEAL_POS):
		return ""
	if not _gate_open():
		return _not_yet()
	if _is_unarmed():
		return "E — eat the morning meal"
	return "Stow the goad first (1)"


func is_active() -> bool:
	return _phase != MealPhase.DONE


func force_done() -> void:
	_phase = MealPhase.DONE
	_eat_t = 0.0
	if _stew:
		_stew.material_override = _mat(C_STEW_EMPTY)
		# Flatten leftover.
		if _stew.mesh is CylinderMesh:
			(_stew.mesh as CylinderMesh).height = 0.02
	_flash("That's better.", 3.0)
	_report_done()


func force_state(state_name: String) -> void:
	match state_name:
		"need_stow", "waiting":
			_phase = MealPhase.WAITING
			_eat_t = 0.0
			_reset_stew_full()
		"ready_to_eat":
			_phase = MealPhase.WAITING
			_eat_t = 0.0
			_reset_stew_full()
			# Capture helper: ensure player is unarmed if present.
			if _player:
				var combat := _player.get_node_or_null("CombatSystem")
				if combat and combat.has_method("set_weapon"):
					combat.call("set_weapon", 3)  # UNARMED
		"eating":
			_phase = MealPhase.EATING
			_eat_t = EAT_SECS
			_reset_stew_full()
		"done":
			force_done()
		_:
			push_warning("OpeningStowMealChore.force_state unknown: " + state_name)


func debug_set_state(state_name: String) -> void:
	force_state(state_name)


func try_interact() -> bool:
	return _try_interact()


# ---------------------------------------------------------------- interact

func _try_interact() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	if _phase != MealPhase.WAITING:
		return false
	if not _near(_player.global_position, MEAL_POS):
		return false
	if not _gate_open():
		# Out of order: say so, change nothing.
		_flash(_not_yet(), 2.5)
		return true
	if not _is_unarmed():
		_flash("Stow the goad first (1) — sit and eat with empty hands.", 3.5)
		print("OPENING_STOW_MEAL_NEED_STOW")
		return true
	_start_eat()
	return true


func _start_eat() -> void:
	_flash("Morning meal — that's better.", 2.5)
	if _player and _player.has_method("begin_seat") and bool(_player.call("begin_seat", SEAT_POS, SEAT_YAW)):
		# He walks to the seat and sits; the meal timer starts once he is down.
		_phase = MealPhase.SEATING
		_eat_t = 0.0
		print("OPENING_STOW_MEAL_SITTING")
		return
	_phase = MealPhase.EATING
	_eat_t = EAT_SECS
	print("OPENING_STOW_MEAL_EATING")


func _finish_meal(announce: bool) -> void:
	if _phase == MealPhase.DONE:
		return
	_phase = MealPhase.DONE
	if _stew:
		_stew.material_override = _mat(C_STEW_EMPTY)
		if _stew.mesh is CylinderMesh:
			var cm := (_stew.mesh as CylinderMesh).duplicate() as CylinderMesh
			cm.height = 0.02
			_stew.mesh = cm
			_stew.position.y = 0.46
	if announce:
		_flash("That's better.", 3.5)
		print("OPENING_STOW_MEAL_SOFT_SUCCESS")
	_report_done()
	# Up again: the rise blends back into foot loco and frees his input when it lands.
	if _player and is_instance_valid(_player) and _player.has_method("end_seat"):
		_player.call("end_seat")


func _reset_stew_full() -> void:
	if _stew == null:
		return
	_stew.material_override = _mat(C_STEW)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.16
	cm.height = 0.06
	cm.radial_segments = 12
	_stew.mesh = cm
	_stew.position = Vector3(0.0, 0.48, 0.0)


# ---------------------------------------------------------------- geometry

func _build_props() -> void:
	_meal_root = Node3D.new()
	_meal_root.name = "MorningMeal"
	_meal_root.position = MEAL_POS
	add_child(_meal_root)

	# Low stool / table.
	_mesh_cyl(_meal_root, Vector3(0.0, 0.28, 0.0), 0.28, 0.30, 0.08, C_WOOD)
	_mesh_cyl(_meal_root, Vector3(0.0, 0.14, 0.0), 0.06, 0.07, 0.28, C_WOOD_DARK)
	_mesh_box(_meal_root, Vector3(0.0, 0.02, 0.0), Vector3(0.36, 0.04, 0.36), C_WOOD_DARK)
	# Cloth scrap.
	_mesh_box(_meal_root, Vector3(0.0, 0.33, 0.0), Vector3(0.5, 0.02, 0.5), C_CLOTH)
	# Bowl + stew.
	_mesh_cyl(_meal_root, Vector3(0.0, 0.42, 0.0), 0.20, 0.18, 0.14, C_BOWL)
	_stew = _mesh_cyl(_meal_root, Vector3(0.0, 0.48, 0.0), 0.16, 0.16, 0.06, C_STEW)
	_stew.name = "Stew"
	# Bread hunk.
	_mesh_box(_meal_root, Vector3(0.28, 0.40, 0.05), Vector3(0.18, 0.08, 0.12), C_BREAD)
	_mesh_box(_meal_root, Vector3(0.32, 0.44, -0.02), Vector3(0.10, 0.06, 0.08), C_BREAD.darkened(0.08))

	var label := Label3D.new()
	label.text = "Meal"
	label.font_size = 26
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.92, 0.86, 0.68)
	label.outline_size = 8
	label.position = Vector3(0.0, 1.15, 0.0)
	_meal_root.add_child(label)


# ---------------------------------------------------------------- helpers

func _is_unarmed() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var combat := _player.get_node_or_null("CombatSystem")
	if combat == null:
		return false
	# CombatSystem.Weapon.UNARMED = 3
	if "current_weapon" in combat:
		return int(combat.get("current_weapon")) == 3
	if combat.has_method("weapon_name"):
		return String(combat.call("weapon_name")) == "unarmed"
	return false


func _near(a: Vector3, b: Vector3, range_m: float = INTERACT_RANGE) -> bool:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) <= range_m


func _flash(text: String, secs: float = 3.0) -> void:
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)
	elif _director and _director.has_method("_flash"):
		_director.call("_flash", text, secs)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	_mats[key] = m
	return m


func _mesh_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mesh_cyl(parent: Node, pos: Vector3, top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- set sequence gate

func _seq() -> Node:
	if _sequence == null or not is_instance_valid(_sequence):
		_sequence = get_tree().get_first_node_in_group("opening_sequence") if is_inside_tree() else null
	return _sequence


## Open when there is no sequence (other scenes) or this chore's step is the live one.
func _gate_open() -> bool:
	var seq := _seq()
	return seq == null or bool(seq.call("is_step_active", SEQ_STEP))


func _not_yet() -> String:
	var seq := _seq()
	return String(seq.call("not_yet_text")) if seq else ""


func _report_done() -> void:
	var seq := _seq()
	if seq:
		seq.call("complete_step", SEQ_STEP)
