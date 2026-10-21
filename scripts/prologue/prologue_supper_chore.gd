extends Node3D
class_name PrologueSupperChore
## Prologue step 2 (twilight, after the boy's news): the herd-hand's supper — a covered wooden
## piggin of buttermilk with his bread tied in the cloth over its mouth — set by the meal stool.
## E at the stool: Cian takes it up by the handle in his right hand (the goad goes on his back
## with the existing stow; a load in the hand walks at the carried pace and blocks sprint and
## strikes — PlayerController.begin_lead with lead_walk_speed()). E beside the herd-hand on the
## bank by the gate: he hands it over, and the herd-hand says his line about the haze to the
## south. Reports to the raid sequence. States: waiting → carrying → given.

enum SupperState { WAITING, CARRYING, GIVEN }

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const INTERACT_RANGE := 2.2
const GIVE_RANGE := 2.0
const SEQ_STEP := &"supper"
## On the ground beside the meal stool, east side (OpeningStowMealChore.MEAL_POS = (−4.5, 0, 2.8)).
const SET_POS := Vector3(-4.5, 0.0, 3.35)
const C_WOOD := Color(0.47, 0.34, 0.2)
const C_HOOP := Color(0.3, 0.22, 0.14)
const C_CLOTH := Color(0.78, 0.74, 0.64)

var _state: SupperState = SupperState.WAITING
var _player: Node3D = null
var _raid: Node = null
var _prop: Node3D = null
var _herd_hand: Node3D = null
var _mats: Dictionary = {}


func _ready() -> void:
	add_to_group("prologue_chore")
	add_to_group("prologue_supper")
	_build_prop()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")
	_place_on_ground()


func set_herd_hand(n: Node3D) -> void:
	_herd_hand = n


func supper_state() -> String:
	return ["waiting", "carrying", "given"][int(_state)]


func prop() -> Node3D:
	return _prop


func lead_walk_speed() -> float:
	return 1.45  # PlayerController.CARRIED_WALK_SPEED: in the hand, he walks at the carried pace


func _process(_delta: float) -> void:
	if _state == SupperState.CARRYING and _player and is_instance_valid(_player):
		# Hangs from his right hand by the stave handle.
		var hp: Vector3 = _player.call("lead_hand_point")
		var yaw := (_player as Node3D).global_rotation.y
		_prop.global_transform = Transform3D(Basis(Vector3.UP, yaw), hp - Vector3(0.0, 0.33, 0.0))
	elif _state == SupperState.GIVEN and _herd_hand and is_instance_valid(_herd_hand):
		var hand: Node3D = _herd_hand.call("right_hand")
		if hand:
			_prop.global_transform = Transform3D(Basis(Vector3.UP, _herd_hand.global_rotation.y), hand.global_position - Vector3(0.0, 0.33, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_E:
		if try_interact():
			get_viewport().set_input_as_handled()


func _open() -> bool:
	return _raid != null and bool(_raid.call("is_step_active", SEQ_STEP))


func is_active() -> bool:
	return _open() and _state != SupperState.GIVEN


func interact_prompt() -> String:
	if not _open() or _player == null:
		return ""
	var p := _player.global_position
	match _state:
		SupperState.WAITING:
			if _near(p, SET_POS, INTERACT_RANGE):
				return "E — take up the herd-hand's supper"
		SupperState.CARRYING:
			if _herd_hand and _near(p, _herd_hand.global_position, GIVE_RANGE):
				return "E — give him his supper"
	return ""


func objective_text() -> String:
	match _state:
		SupperState.WAITING:
			return "Take the herd-hand his supper: it's by the meal stool. He's up on the bank by the gate."
		SupperState.CARRYING:
			return "Carry the supper up to the herd-hand on the bank by the gate."
	return ""


func try_interact() -> bool:
	if not _open():
		return false
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	var p := _player.global_position
	match _state:
		SupperState.WAITING:
			if not _near(p, SET_POS, INTERACT_RANGE):
				return false
			if _player.has_method("is_input_locked") and bool(_player.call("is_input_locked")):
				return false
			_state = SupperState.CARRYING
			_player.call("begin_lead", self)
			print("PROLOGUE_SUPPER_TAKEN")
			return true
		SupperState.CARRYING:
			if _herd_hand == null or not _near(p, _herd_hand.global_position, GIVE_RANGE):
				return false
			_give()
			return true
	return false


func _give() -> void:
	_state = SupperState.GIVEN
	_player.call("end_lead", self)
	if _herd_hand.has_method("hold_right"):
		_herd_hand.call("hold_right", true)
	print("PROLOGUE_SUPPER_GIVEN")
	if _raid and _raid.has_method("report_supper_given"):
		_raid.call("report_supper_given")


func force_state(state_name: String) -> void:
	match state_name:
		"waiting":
			_state = SupperState.WAITING
			_place_on_ground()
		"carrying":
			_state = SupperState.CARRYING
			if _player:
				_player.call("begin_lead", self)
		"given":
			if _state == SupperState.CARRYING or _player != null:
				_state = SupperState.CARRYING
				_give()


func _place_on_ground() -> void:
	if _prop and _prop.get_parent() == self:
		_prop.global_transform = Transform3D(Basis(Vector3.UP, 0.4), Terrain.surface_point(SET_POS, 0.0))


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= r


## Piggin: a small stave-built wooden vessel (~0.2 m tall) with one long stave standing up as the
## handle, a linen cloth tied over the mouth and the bread loaf bulging under it.
func _build_prop() -> void:
	_prop = Node3D.new()
	_prop.name = "Supper"
	add_child(_prop)
	_cyl(_prop, Vector3(0.0, 0.1, 0.0), 0.085, 0.075, 0.2, C_WOOD)
	_cyl(_prop, Vector3(0.0, 0.035, 0.0), 0.081, 0.081, 0.025, C_HOOP)
	_cyl(_prop, Vector3(0.0, 0.165, 0.0), 0.088, 0.088, 0.025, C_HOOP)
	# Handle stave, rising above the rim on one side.
	var h := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.035, 0.32, 0.02)
	h.mesh = hb
	h.material_override = _mat(C_WOOD.darkened(0.1))
	h.position = Vector3(0.0, 0.16 + 0.04, 0.085)
	_prop.add_child(h)
	# Cloth over the mouth with the loaf under it.
	var cloth := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.095
	sm.height = 0.1
	cloth.mesh = sm
	cloth.material_override = _mat(C_CLOTH)
	cloth.position = Vector3(0.0, 0.215, -0.01)
	cloth.scale = Vector3(1.0, 0.9, 1.0)
	_prop.add_child(cloth)
	_cyl(_prop, Vector3(0.0, 0.19, 0.0), 0.093, 0.093, 0.02, C_CLOTH.darkened(0.1))
	for c in _prop.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cyl(parent: Node3D, pos: Vector3, top: float, bottom: float, h: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat(col)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[k] = m
	return _mats[k]


## After he has eaten it on the bank and comes down (prologue step 3): the dish goes with him out
## of sight (into the byre).
func hide_prop() -> void:
	if _prop:
		_prop.visible = false
