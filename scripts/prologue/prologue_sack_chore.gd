extends Node3D
class_name PrologueSackChore
## Raid day, step 7 (optional): the sack of meal and seed-corn by the quern — next year's sowing and
## the winter's porridge. E beside it takes it up in both arms (begin_carry: the goad goes on his
## back, he walks no faster than 1.45 m/s and can't sprint); E again sets it down where he stands.
## Taking it up lets go of his sister's hand (she keeps at his heel), and her hand can't be taken
## again while he carries it. Carried into the wood → `sack_saved`.

const SEQ_STEP := &"out"
const QUERN_POS := Vector3(-4.2, 0.0, 4.75)
const SACK_AT := Vector3(-4.75, 0.0, 5.0)  ## the greybox sack's place (QUERN_POS + (−0.55, 0, 0.25))
const INTERACT_RANGE := 1.5
const C_SACK := Color(0.48, 0.41, 0.29)

enum State { WAITING, CARRYING, DROPPED }

var _state: State = State.WAITING
var _player: Node3D = null
var _raid: Node = null
var _sack: Node3D = null
var _rest: Vector3 = SACK_AT


func _ready() -> void:
	add_to_group("prologue_chore")
	add_to_group("prologue_sack")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")
	# Stand in for the greybox sack (same place, same look).
	var gb := get_tree().get_first_node_in_group("opening_farm_greybox")
	var old: Node = null
	if gb:
		old = gb.find_child("QuernSack", true, false)
	if old == null:
		old = get_tree().root.find_child("QuernSack", true, false)
	if old is Node3D:
		(old as Node3D).visible = false
	_rest = Vector3(SACK_AT.x, OpeningTerrain.surface_y(SACK_AT.x, SACK_AT.z), SACK_AT.z)
	_sack.global_position = _rest + Vector3(0, 0.25, 0)


func _build() -> void:
	_sack = Node3D.new()
	_sack.name = "MealSack"
	add_child(_sack)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	body.mesh = sm
	body.scale = Vector3(0.9, 1.15, 0.85)
	var m := StandardMaterial3D.new()
	m.albedo_color = C_SACK
	m.roughness = 1.0
	body.material_override = m
	_sack.add_child(body)
	# The neck, tied off with a thong.
	var neck := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.05
	nm.bottom_radius = 0.08
	nm.height = 0.1
	neck.mesh = nm
	neck.material_override = m
	neck.position = Vector3(0, 0.3, 0)
	_sack.add_child(neck)


func state_name() -> String:
	return ["waiting", "carrying", "dropped"][int(_state)]


func is_carried() -> bool:
	return _state == State.CARRYING


func sack_node() -> Node3D:
	return _sack


func _open() -> bool:
	return _raid != null and bool(_raid.call("is_step_active", SEQ_STEP))


func is_active() -> bool:
	return _open()


func carry_grip() -> Array:
	return [Vector3(0.0, 1.1, -0.32), 0.2]


func interact_prompt() -> String:
	if not _open() or _player == null:
		return ""
	match _state:
		State.WAITING, State.DROPPED:
			if _near(_player.global_position, _sack.global_position, INTERACT_RANGE) and not bool(_player.call("is_carrying")):
				return "E — take up the sack of meal and seed-corn"
		State.CARRYING:
			return "E — set the sack down"
	return ""


func objective_text() -> String:
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_E:
		if try_interact():
			get_viewport().set_input_as_handled()


func try_interact() -> bool:
	if not _open() or _player == null:
		return false
	match _state:
		State.WAITING, State.DROPPED:
			if not _near(_player.global_position, _sack.global_position, INTERACT_RANGE):
				return false
			if bool(_player.call("is_carrying")) or bool(_player.call("is_hand_working")):
				return false
			take()
			return true
		State.CARRYING:
			drop()
			return true
	return false


func take() -> void:
	var hh := get_tree().get_first_node_in_group("prologue_hand_hold")
	if hh and bool(hh.call("is_in_hand")):
		hh.call("let_go")
	_state = State.CARRYING
	_player.call("begin_carry", self)
	print("PROLOGUE_SACK_TAKEN")


func drop() -> void:
	if _state != State.CARRYING:
		return
	_state = State.DROPPED
	_player.call("end_carry", self)
	var p := _player.global_position + (_player.global_transform.basis.z * -0.6)
	_rest = Vector3(p.x, OpeningTerrain.surface_y(p.x, p.z), p.z)
	_sack.global_transform = Transform3D(Basis.IDENTITY, _rest + Vector3(0, 0.25, 0))
	print("PROLOGUE_SACK_DROPPED")


## Raid sequence: the sack can't be taken after the step (it stays where it lies).
func release_if_carried() -> void:
	if _state == State.CARRYING:
		drop()


func _process(_delta: float) -> void:
	if _state == State.CARRYING and _player and is_instance_valid(_player):
		var w := float(_player.call("carry_hold_weight"))
		var vis := _player.get_node_or_null("Visual") as Node3D
		if vis:
			var g: Array = carry_grip()
			var xf := vis.global_transform
			var c: Vector3 = xf * (g[0] + Vector3(0.0, 0.02, 0.06))
			_sack.global_transform = Transform3D(xf.basis.orthonormalized(), c)
		_sack.visible = w > 0.4 or w == 0.0
		if w < 0.4:
			_sack.global_position = _rest + Vector3(0, 0.25, 0)


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= r
