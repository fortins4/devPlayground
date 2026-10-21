extends Node3D
class_name PrologueKnifePeg
## Raid day, step 6: the household knife on its peg by the roundhouse door (Decision 18: sheathed,
## hung by the sheath thong from a peg driven into the wattle at shoulder height, left of the
## doorway). This is the first knife in the game: until Cian takes it, CombatSystem.knife_in_kit
## (the spec's `knife_carried`) is false, so key 2 and Q never draw it and set_weapon(KNIFE) is
## refused. E by the door (only once Máire has shouted for it): he steps to the jamb, reaches up
## and lifts it off by the thong (~1 s, PlayerController hand work: the goad goes on his back
## meanwhile and comes back after), and belts it at his right hip. Then knife_in_kit = true, key 2
## draws it, and the sheath shows on his belt (the in-hand knife is the rig's WeaponVisual).
## The greybox roundhouse is a solid drum with no interior (conflict 6.15: doorway framing), so the
## peg is on the west door jamb, at the face of the doorway.

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const SEQ_STEP := &"knife"
const DOOR_POS := Vector3(-7.2, 0.0, 1.77)
## World: driven into the front face of the west door jamb (jamb x −7.87…−7.73, face z 1.91),
## shoulder height for Cian (1.70 m).
const PEG_POS := Vector3(-7.8, 1.42, 1.95)
const STAND := Vector3(-7.62, 0.0, 2.42)
const STAND_YAW := 0.25                         ## facing the jamb (north, a touch west)
const INTERACT_RANGE := 1.6
const TAKE_SECS := 1.0
const C_PEG := Color(0.4, 0.29, 0.17)
const C_SHEATH := Color(0.32, 0.2, 0.11)
const C_HILT := Color(0.52, 0.4, 0.26)
const C_THONG := Color(0.25, 0.16, 0.09)

enum State { HANGING, TAKING, TAKEN }

var _state: State = State.HANGING
var _player: Node3D = null
var _raid: Node = null
var _t: float = 0.0
var _on_peg: Node3D = null
var _belt: Node3D = null
var _belt_hilt: Node3D = null


func _ready() -> void:
	add_to_group("prologue_chore")
	add_to_group("prologue_knife_peg")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_peg()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")


func knife_state() -> String:
	return ["hanging", "taking", "taken"][int(_state)]


func is_taken() -> bool:
	return _state == State.TAKEN


func peg_pos() -> Vector3:
	return _peg_world()


func _open() -> bool:
	return _raid != null and bool(_raid.call("is_step_active", SEQ_STEP))


func is_active() -> bool:
	return _open() and _state != State.TAKEN


func interact_prompt() -> String:
	if not _open() or _state != State.HANGING or _player == null:
		return ""
	if _near(_player.global_position, STAND, INTERACT_RANGE):
		return "E — take the knife off the peg"
	return ""


func objective_text() -> String:
	if _state == State.TAKEN:
		return ""
	return "Take the knife off the peg by the door."


## _input, not _unhandled_input: Máire stands beside the door and her talk node takes any E near her
## (she has nothing more to say by now), which would swallow this one.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_E:
		if try_interact():
			get_viewport().set_input_as_handled()


func try_interact() -> bool:
	if not _open() or _state != State.HANGING:
		return false
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or not _near(_player.global_position, STAND, INTERACT_RANGE):
		return false
	if bool(_player.call("is_leading")) or bool(_player.call("is_hand_working")) or bool(_player.call("is_carrying")):
		return false
	_state = State.TAKING
	_t = 0.0
	_player.call("begin_hand_work", self, Terrain.surface_point(STAND, 0.0), STAND_YAW)
	print("PROLOGUE_KNIFE_REACH")
	return true


## Hand-work grips: right hand up at the peg on the thong, left on the sheath below it.
func hand_work_grips() -> Array:
	var peg := _peg_world()
	return [peg + Vector3(0.12, -0.3, 0.1), peg + Vector3(0.03, -0.1, 0.08)]


func _peg_world() -> Vector3:
	return Vector3(PEG_POS.x, Terrain.surface_y(PEG_POS.x, PEG_POS.z) + PEG_POS.y, PEG_POS.z)


func _process(delta: float) -> void:
	if _state != State.TAKING or _player == null:
		return
	if not bool(_player.call("hand_work_ready")):
		return
	_t += delta
	if _t >= TAKE_SECS * 0.6 and _on_peg.visible:
		_on_peg.visible = false  # lifted off by the thong
	if _t >= TAKE_SECS:
		_take()


func _take() -> void:
	_state = State.TAKEN
	_on_peg.visible = false
	_player.call("end_hand_work", self)
	var combat := _player.get_node_or_null("CombatSystem")
	if combat:
		combat.set("knife_in_kit", true)
	_belt_on()
	print("PROLOGUE_KNIFE_TAKEN knife_in_kit=%s" % (combat.get("knife_in_kit") if combat else "?"))
	if _raid and _raid.has_method("report_knife_taken"):
		_raid.call("report_knife_taken")


## Smoke / capture: straight to taken.
func force_taken() -> void:
	if _state == State.TAKEN:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_state = State.TAKING
	_take()


func _physics_process(_delta: float) -> void:
	if _belt_hilt and _player and is_instance_valid(_player):
		var combat := _player.get_node_or_null("CombatSystem")
		# The hilt shows in the sheath unless the knife is out in his hand.
		_belt_hilt.visible = combat == null or int(combat.get("current_weapon")) != 1


func _belt_on() -> void:
	var loco: Node = _player.get("locomotion")
	var hips: Node3D = loco.call("get_joint", "hips") if loco else null
	if hips == null:
		return
	# Sheathed at the right hip, hilt forward-up, hanging from the belt (rig: right = +X, front −Z).
	_belt = Node3D.new()
	_belt.name = "BeltKnife"
	_belt.position = Vector3(0.19, 0.0, -0.08)
	_belt.rotation = Vector3(deg_to_rad(-20.0), 0.0, deg_to_rad(8.0))
	hips.add_child(_belt)
	_box(_belt, Vector3(0.0, -0.11, 0.0), Vector3(0.045, 0.2, 0.022), C_SHEATH)
	_belt_hilt = _box(_belt, Vector3(0.0, 0.05, 0.0), Vector3(0.03, 0.1, 0.03), C_HILT)


func belt_node() -> Node3D:
	return _belt


func _build_peg() -> void:
	var w := _peg_world()
	_box(self, w, Vector3(0.03, 0.03, 0.09), C_PEG)
	_on_peg = Node3D.new()
	_on_peg.name = "KnifeOnPeg"
	add_child(_on_peg)
	_on_peg.position = w
	_box(_on_peg, Vector3(0.0, -0.07, 0.03), Vector3(0.006, 0.12, 0.006), C_THONG)
	_box(_on_peg, Vector3(0.0, -0.25, 0.03), Vector3(0.05, 0.22, 0.022), C_SHEATH)
	_box(_on_peg, Vector3(0.0, -0.1, 0.03), Vector3(0.03, 0.09, 0.03), C_HILT)


func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= r
