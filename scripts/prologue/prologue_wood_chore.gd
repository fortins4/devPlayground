extends Node3D
class_name PrologueWoodChore
## Prologue step 3 (twilight): an armful of split wood for the night's fire, and the hatchet put
## away.
## - Beside the woodpile stands the chopping block with the household hatchet stuck in it, as a
##   farm keeps it by day. It is set dressing only: never an interactable, never selectable
##   (no hatchet anywhere in the prologue kit).
## - E at the woodpile: Cian takes up an armful of split billets (PlayerController.begin_carry: the
##   existing stow puts the goad on his back, the carried walk 1.45 m/s, no sprint), forearms under
##   the load and hands wide (carry_grip()). E at the house door sets it down just inside.
## - While he carries it, the herd-hand (down off the bank, waiting by the byre) goes to the block,
##   works the hatchet out of it, says "Out of the dew." and puts it away through the byre's yard
##   door: iron edge-tools are kept under cover at night. Ambient; no prompt.
## States: waiting → carrying → delivered. Hatchet: in_block → pulled → in_byre.

enum WoodState { WAITING, CARRYING, DELIVERED }
enum HatchetState { IN_BLOCK, FETCHING, PULLED, STOWING, IN_BYRE }

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const SEQ_STEP := &"penning"
const INTERACT_RANGE := 2.0
## Woodpile (OpeningFarmGreybox: a 2.6 × 0.9 × 1.0 log box at (−3.8, 0.45, −6.1)).
const PILE_POS := Vector3(-3.8, 0.0, -6.1)
const PILE_TAKE := Vector3(-3.8, 0.0, -5.15)  ## stand point on the pile's yard (south) side
## Chopping block just east of the pile, on the yard side.
const BLOCK_POS := Vector3(-1.75, 0.0, -5.6)
const BLOCK_H := 0.46
## House door (OpeningFamilyCaller.DOOR_POS) and where the wood goes (just inside, by the jamb).
const DOOR_POS := Vector3(-7.2, 0.0, 1.77)
const DROP_RANGE := 1.8
const DROP_INSIDE := Vector3(-6.55, 0.0, 1.35)
## The byre's yard door: on its west gable (the byre is 7.5 × 4 at (7, −2.2); its main door opens
## onto the night pen).
const BYRE_DOOR := Vector3(3.22, 0.0, -2.2)
const HH_WAIT := Vector3(1.9, 0.0, -3.4)
const HH_BLOCK_STAND := Vector3(-1.2, 0.0, -5.15)
## The herd-hand's way down off the bank (RaidSequence.HH_DOWN without the last leg to the byre).
const HH_DOWN_WAY: Array[Vector3] = [Vector3(1.6, 0.0, 15.2), Vector3(0.9, 0.0, 11.4), Vector3(0.9, 0.0, 0.4)]
const HH_BYRE_STAND := Vector3(2.55, 0.0, -2.2)
const PULL_SECS := 1.2
const STOW_SECS := 0.9
const C_BLOCK := Color(0.45, 0.34, 0.22)
const C_BLOCK_TOP := Color(0.62, 0.52, 0.38)
const C_BILLET := Color(0.5, 0.38, 0.24)
const C_BILLET_SPLIT := Color(0.68, 0.56, 0.4)
const C_HAFT := Color(0.55, 0.42, 0.26)
const C_IRON := Color(0.32, 0.33, 0.34)
const C_DOOR := Color(0.24, 0.17, 0.1)

var _state: WoodState = WoodState.WAITING
var _hatchet_state: HatchetState = HatchetState.IN_BLOCK
var _player: Node3D = null
var _raid: Node = null
var _herd_hand: Node3D = null
var _armful: Node3D = null
var _stack: Node3D = null
var _hatchet: Node3D = null
var _hh_t: float = 0.0
var _mats: Dictionary = {}


func _ready() -> void:
	add_to_group("prologue_chore")
	add_to_group("prologue_wood")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_props()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")


func set_herd_hand(n: Node3D) -> void:
	_herd_hand = n


func wood_state() -> String:
	return ["waiting", "carrying", "delivered"][int(_state)]


func hatchet_state() -> String:
	return ["in_block", "fetching", "pulled", "stowing", "in_byre"][int(_hatchet_state)]


func hatchet_node() -> Node3D:
	return _hatchet


func armful_node() -> Node3D:
	return _armful


func block_pos() -> Vector3:
	return BLOCK_POS


func pile_pos() -> Vector3:
	return PILE_POS


func byre_door_pos() -> Vector3:
	return BYRE_DOOR


func herd_hand_wait_pos() -> Vector3:
	return HH_WAIT


## Load hold for PlayerController._pose_load_arms: an armful rests on both forearms against the
## belly, hands either side of it (Visual frame, rig metres).
func carry_grip() -> Array:
	return [Vector3(0.0, 1.06, -0.36), 0.16]


func _open() -> bool:
	return _raid != null and bool(_raid.call("is_step_active", SEQ_STEP))


func is_active() -> bool:
	return _open() and _state != WoodState.DELIVERED


func interact_prompt() -> String:
	if not _open() or _player == null:
		return ""
	var p := _player.global_position
	match _state:
		WoodState.WAITING:
			if _near(p, PILE_TAKE, INTERACT_RANGE):
				return "E — take an armful of wood"
		WoodState.CARRYING:
			if _near(p, DOOR_POS, DROP_RANGE):
				return "E — set the wood down inside the door"
	return ""


func objective_text() -> String:
	match _state:
		WoodState.WAITING:
			return "Bring in an armful for the fire: take it from the woodpile behind the house."
		WoodState.CARRYING:
			return "Carry the wood to the house door."
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_E:
		if try_interact():
			get_viewport().set_input_as_handled()


func try_interact() -> bool:
	if not _open():
		return false
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	if bool(_player.call("is_leading")) or bool(_player.call("is_hand_working")):
		return false
	var p := _player.global_position
	match _state:
		WoodState.WAITING:
			if not _near(p, PILE_TAKE, INTERACT_RANGE):
				return false
			_state = WoodState.CARRYING
			_player.call("begin_carry", self)
			_armful.visible = true
			print("PROLOGUE_WOOD_TAKEN")
			if _hatchet_state == HatchetState.IN_BLOCK:
				_start_fetch()
			return true
		WoodState.CARRYING:
			if not _near(p, DOOR_POS, DROP_RANGE):
				return false
			_deliver()
			return true
	return false


func _deliver() -> void:
	_state = WoodState.DELIVERED
	_player.call("end_carry", self)
	_armful.visible = false
	_stack.visible = true
	print("PROLOGUE_WOOD_DELIVERED")
	if _raid and _raid.has_method("report_wood_in"):
		_raid.call("report_wood_in")


## Smoke / capture: "carrying" (armful in his arms) / "delivered" / hatchet "in_byre".
func force_state(state_name: String) -> void:
	match state_name:
		"carrying":
			_state = WoodState.CARRYING
			_armful.visible = true
			if _player:
				_player.call("begin_carry", self)
		"delivered":
			if _state == WoodState.CARRYING:
				_deliver()
			else:
				_state = WoodState.DELIVERED
				_stack.visible = true
				if _raid and _raid.has_method("report_wood_in"):
					_raid.call("report_wood_in")
		"in_byre":
			_hatchet_state = HatchetState.IN_BYRE
			_hatchet.visible = false


func _process(delta: float) -> void:
	if _state == WoodState.CARRYING and _player and is_instance_valid(_player):
		var w := float(_player.call("carry_hold_weight"))
		var vis := (_player as Node3D).get_node_or_null("Visual") as Node3D
		if vis:
			var g: Array = carry_grip()
			var xf := vis.global_transform
			# On the forearms, just behind the hands and a little above them.
			var c: Vector3 = xf * (g[0] + Vector3(0.0, 0.07, 0.07))
			_armful.global_transform = Transform3D(xf.basis.orthonormalized(), c)
			_armful.visible = w > 0.6
	_tick_hatchet(delta)


# ---------------------------------------------------------------- the herd-hand puts it away

## The herd-hand starts for the block (from wherever he is: by the byre, or still on his way down).
func _start_fetch() -> void:
	if _herd_hand == null:
		return
	_hatchet_state = HatchetState.FETCHING
	# Still up on the bank or on his way down: keep to his way down the west side of the pen (not
	# across the yard through the milk cow), then cut across behind the house to the block.
	var route: Array = []
	var hz: float = _herd_hand.global_position.z
	for q in HH_DOWN_WAY:
		if q.z < hz - 0.3:
			route.append(q)
	route.append(HH_BLOCK_STAND)
	_herd_hand.call("walk_path", route)
	print("PROLOGUE_HATCHET_FETCH")


func _tick_hatchet(delta: float) -> void:
	if _herd_hand == null:
		return
	match _hatchet_state:
		HatchetState.FETCHING:
			if not bool(_herd_hand.call("is_walking")):
				_herd_hand.call("face_point", BLOCK_POS)
				_hh_t += delta
				var w := clampf(_hh_t / 0.4, 0.0, 1.0)
				_herd_hand.call("reach_right", _hatchet_grip_world(), w)
				if _hh_t > 0.45:
					# Works it loose with a couple of rocks of the haft, then lifts it clear.
					var u := clampf((_hh_t - 0.45) / PULL_SECS, 0.0, 1.0)
					_hatchet.rotation.z = sin(u * TAU * 2.0) * 0.12 * (1.0 - u)
					_hatchet.position.y = BLOCK_H + smoothstep(0.7, 1.0, u) * 0.06
				if _hh_t >= 0.45 + PULL_SECS:
					_hatchet_state = HatchetState.PULLED
					_hh_t = 0.0
					_herd_hand.call("reach_right", Vector3.ZERO, 0.0)
					_herd_hand.call("hold_right", true)
					_herd_hand.call("say", "Out of the dew.", 3.0)
					_herd_hand.call("walk_path", [HH_BYRE_STAND])
					print("PROLOGUE_HATCHET_PULLED")
		HatchetState.PULLED:
			_carry_hatchet_in_hand()
			if not bool(_herd_hand.call("is_walking")):
				_hatchet_state = HatchetState.STOWING
				_hh_t = 0.0
		HatchetState.STOWING:
			_herd_hand.call("face_point", BYRE_DOOR + Vector3(1.0, 0.0, 0.0))
			_hh_t += delta
			_herd_hand.call("hold_right", false)
			_herd_hand.call("reach_right", BYRE_DOOR + Vector3(0.4, 0.9, 0.0), clampf(_hh_t / 0.4, 0.0, 1.0))
			_carry_hatchet_in_hand()
			if _hh_t >= STOW_SECS:
				_hatchet_state = HatchetState.IN_BYRE
				_hatchet.visible = false
				_herd_hand.call("reach_right", Vector3.ZERO, 0.0)
				_herd_hand.call("face_point", BLOCK_POS)
				print("PROLOGUE_HATCHET_IN_BYRE")
				if _raid and _raid.has_method("report_hatchet_stowed"):
					_raid.call("report_hatchet_stowed")


func _carry_hatchet_in_hand() -> void:
	var hand: Node3D = _herd_hand.call("right_hand")
	if hand == null:
		return
	# Held by the haft just under the head, head up, edge forward.
	var yaw: float = _herd_hand.global_rotation.y
	var b := Basis(Vector3.UP, yaw)
	_hatchet.global_transform = Transform3D(b, hand.global_position - b * Vector3(0.0, 0.33, 0.0))


func _hatchet_grip_world() -> Vector3:
	return Terrain.surface_point(BLOCK_POS, BLOCK_H + 0.3)


# ---------------------------------------------------------------- props

func _build_props() -> void:
	var g := Terrain.surface_point(BLOCK_POS, 0.0)
	var block := Node3D.new()
	block.name = "ChoppingBlock"
	block.position = g
	add_child(block)
	# A sawn round of oak, set on end: ~0.46 m tall, ~0.5 m across, top scarred by the axe.
	_cyl(block, Vector3(0.0, BLOCK_H * 0.5, 0.0), 0.24, 0.26, BLOCK_H, C_BLOCK)
	_cyl(block, Vector3(0.0, BLOCK_H + 0.003, 0.0), 0.235, 0.235, 0.006, C_BLOCK_TOP)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.26
	shape.height = BLOCK_H
	cs.shape = shape
	cs.position = Vector3(0.0, BLOCK_H * 0.5, 0.0)
	body.add_child(cs)
	block.add_child(body)
	# The hatchet: its bit sunk in the block's top, haft rising at a slant toward the yard.
	_hatchet = Node3D.new()
	_hatchet.name = "Hatchet"
	_hatchet.top_level = true
	add_child(_hatchet)
	_hatchet.global_transform = Transform3D(Basis(Vector3.UP, 0.3), g + Vector3(0.0, BLOCK_H, 0.0))
	var haft := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.032, 0.46, 0.026)
	haft.mesh = hm
	haft.material_override = _mat(C_HAFT)
	# Haft from the head (0.04 above the wood) out and up at ~35° from vertical.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-35.0))
	haft.transform = Transform3D(tilt, Vector3(0.0, 0.04, 0.0) + tilt * Vector3(0.0, 0.23, 0.0))
	_hatchet.add_child(haft)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.035, 0.07, 0.15)
	head.mesh = hb
	head.material_override = _mat(C_IRON)
	head.material_override.set("metallic", 0.4)
	# Bit end down in the wood (only the poll and cheeks show).
	head.transform = Transform3D(tilt, Vector3(0.0, 0.02, 0.0))
	_hatchet.add_child(head)
	# The byre's yard door on its west gable (planked, shut).
	var door := _box(self, Terrain.surface_point(BYRE_DOOR, 0.8), Vector3(0.08, 1.6, 1.0), C_DOOR)
	door.name = "ByreYardDoor"
	# Armful (hidden until taken): six split billets ~0.42 m long laid across his forearms.
	_armful = Node3D.new()
	_armful.name = "Armful"
	_armful.top_level = true
	add_child(_armful)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1169
	for i in 6:
		var row := i / 3
		var col := i % 3
		var b := _box(_armful, Vector3(rng.randf_range(-0.02, 0.02), 0.045 + row * 0.075, (col - 1) * 0.075), Vector3(0.42, 0.07, 0.07), C_BILLET if (i % 2) == 0 else C_BILLET_SPLIT)
		b.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.08, 0.08), 0.0)
	for c in _armful.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_armful.visible = false
	# Set down just inside the door (hidden until delivered).
	_stack = Node3D.new()
	_stack.name = "WoodInside"
	add_child(_stack)
	_stack.position = Terrain.surface_point(DROP_INSIDE, 0.0)
	for i in 6:
		_box(_stack, Vector3((i % 3 - 1) * 0.08, 0.035 + (i / 3) * 0.07, 0.0), Vector3(0.07, 0.07, 0.42), C_BILLET if (i % 2) == 0 else C_BILLET_SPLIT)
	_stack.visible = false


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= r


func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, pos: Vector3, top: float, bottom: float, h: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 14
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
