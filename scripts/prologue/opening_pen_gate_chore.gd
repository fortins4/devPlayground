extends Node3D
class_name OpeningPenGateChore
## Opening-farm chore: once all six are home, Cian swings the home-pen gate shut and drops the latch.
## The drive step of the set sequence completes on the latch (OpeningDriveDirector.on_pen_latched),
## not on the 6th head crossing — the latch still needs 6/6 and is inert before that.
##
## Interact: E in range (~2.6 m of the gateway), standing on the yard/boreen side (south of the
## fence line, so the gate never shuts him in). States: open → swinging → latching → latched.
## A double leaf (2.3 m each) hung on the EXISTING pen gate posts from OpeningFarmGreybox.
## No HUD of its own: the prompt goes through the drive HUD's chore-prompt chain, and the latch
## itself makes no flash (the walk out stays quiet).

enum GateState { OPEN, SWINGING, LATCHING, LATCHED }

const INTERACT_RANGE := 2.6
const GATE_HALF := 2.3            ## matches OpeningFarmGreybox._build_home_pen gate gap
const PEN_PAD := 0.4              ## matches OpeningFarmGreybox fence padding around HomeZone
const OPEN_ANGLE := deg_to_rad(90.0)
const SWING_SECS := 0.9
const LATCH_SECS := 0.35
const LATCH_UP := deg_to_rad(70.0)
const LEAF_LEN := GATE_HALF - 0.12
const C_RAIL := Color(0.42, 0.31, 0.18)
const C_LATCH := Color(0.24, 0.18, 0.11)

@export var director_path: NodePath = ^"../OpeningDriveDirector"
@export var home_zone_path: NodePath = ^"../HomeZone"

var _state: GateState = GateState.OPEN
var _player: Node3D = null
var _director: Node = null
var _center := Vector3(6.5, 0.0, 9.9)    ## gateway centre on the south fence line (z1)
var _west_pivot: Node3D = null
var _east_pivot: Node3D = null
var _latch_pivot: Node3D = null
var _blocker: StaticBody3D = null
var _blocker_shape: CollisionShape3D = null
var _swing_t: float = 0.0              ## 0 = open, 1 = shut
var _latch_t: float = 0.0              ## 0 = up, 1 = engaged
var _mats: Dictionary = {}


func _ready() -> void:
	add_to_group("opening_pen_gate")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_center = _gate_center()
	_build_props()
	_apply_pose()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	print("OPENING_PEN_GATE_READY center=%s" % _center)


func _process(delta: float) -> void:
	match _state:
		GateState.SWINGING:
			_swing_t = minf(1.0, _swing_t + delta / SWING_SECS)
			_apply_pose()
			if _swing_t >= 1.0:
				_state = GateState.LATCHING
				_set_blocker(true)
		GateState.LATCHING:
			_latch_t = minf(1.0, _latch_t + delta / LATCH_SECS)
			_apply_pose()
			if _latch_t >= 1.0:
				_finish_latch()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries (HUD / smoke / stills)

func interact_prompt() -> String:
	if _state != GateState.OPEN or not _ready_to_latch():
		return ""
	if _player == null or not is_instance_valid(_player):
		return ""
	var p := _player.global_position
	if not _near(p):
		return ""
	if not _outside(p):
		return "Step out through the gateway to shut the gate"
	if _gateway_blocked():
		return "Wait — one's standing in the gateway"
	return "E — swing the gate shut and latch it"


func is_active() -> bool:
	return _state != GateState.LATCHED and _ready_to_latch()


func gate_state() -> String:
	match _state:
		GateState.SWINGING:
			return "swinging"
		GateState.LATCHING:
			return "latching"
		GateState.LATCHED:
			return "latched"
	return "open"


func gate_closed() -> bool:
	return _swing_t >= 1.0


func pen_latched() -> bool:
	return _state == GateState.LATCHED


## 0 = swung right back, 1 = shut across the gateway.
func swing_fraction() -> float:
	return _swing_t


func latch_fraction() -> float:
	return _latch_t


func blocker_enabled() -> bool:
	return _blocker_shape != null and not _blocker_shape.disabled


func gate_center() -> Vector3:
	return _center


## World point on the boreen side of the gateway, facing the gate (smoke / stills).
func stand_point() -> Vector3:
	return _center + Vector3(0.0, 0.0, 1.6)


func leaf_tip_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for pv in [_west_pivot, _east_pivot]:
		var tip := (pv as Node3D).get_node("Tip") as Node3D
		out.append(tip.global_position)
	return out


## Smoke / capture: force a pose without walking. "mid" = half-swung, "latching" = shut, latch half down.
func force_state(state_name: String) -> void:
	match state_name:
		"open":
			_state = GateState.OPEN
			_swing_t = 0.0
			_latch_t = 0.0
			_set_blocker(false)
		"mid":
			_state = GateState.SWINGING
			_swing_t = 0.5
			_latch_t = 0.0
			_set_blocker(false)
			set_process(false)
		"latching":
			_state = GateState.LATCHING
			_swing_t = 1.0
			_latch_t = 0.5
			_set_blocker(true)
			set_process(false)
		"latched":
			_swing_t = 1.0
			_latch_t = 1.0
			_set_blocker(true)
			_state = GateState.LATCHED
		_:
			push_warning("OpeningPenGateChore.force_state unknown: " + state_name)
			return
	_apply_pose()


## Smoke / capture: shut + latch at once (no walking). Same 6/6 rule as E: inert before it.
func debug_latch() -> bool:
	if _state != GateState.OPEN or not _ready_to_latch():
		return false
	_swing_t = 1.0
	_latch_t = 1.0
	_set_blocker(true)
	_finish_latch()
	return true


# ---------------------------------------------------------------- interact

func try_interact() -> bool:
	return _try_interact()


func _try_interact() -> bool:
	if _state != GateState.OPEN or not _ready_to_latch():
		return false   # inert before 6/6: no prompt, no flash, nothing changes
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	var p := _player.global_position
	if not _near(p) or not _outside(p) or _gateway_blocked():
		return false
	_state = GateState.SWINGING
	set_process(true)
	print("OPENING_PEN_GATE_SWING")
	return true


func _ready_to_latch() -> bool:
	if _director == null:
		_director = get_node_or_null(director_path)
	if _director == null:
		return false
	return bool(_director.get("succeeded"))


func _finish_latch() -> void:
	_state = GateState.LATCHED
	_apply_pose()
	print("OPENING_PEN_LATCHED")
	if _director and _director.has_method("on_pen_latched"):
		_director.call("on_pen_latched")


# ---------------------------------------------------------------- helpers

func _gate_center() -> Vector3:
	var zone := get_node_or_null(home_zone_path) as Node3D
	var c := Vector3(6.5, 0.0, 9.9)
	if zone:
		for ch in zone.get_children():
			if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((ch as CollisionShape3D).shape as BoxShape3D).size
				var gp := (ch as Node3D).global_position
				c = Vector3(gp.x, 0.0, gp.z + size.z * 0.5 + PEN_PAD)
				break
	return c


func _near(p: Vector3) -> bool:
	return Vector2(p.x - _center.x, p.z - _center.z).length() <= INTERACT_RANGE


## Yard / boreen side of the south fence line (the pen is north, z < fence).
func _outside(p: Vector3) -> bool:
	return p.z > _center.z + 0.25


func _gateway_blocked() -> bool:
	if _director == null or not _director.has_method("get_cows"):
		return false
	for n: Node3D in _director.call("get_cows"):
		if n and absf(n.global_position.x - _center.x) < GATE_HALF and absf(n.global_position.z - _center.z) < 0.9:
			return true
	return false


func _set_blocker(on: bool) -> void:
	if _blocker_shape:
		_blocker_shape.set_deferred("disabled", not on)


func _apply_pose() -> void:
	var a := (1.0 - _swing_t)
	a = a * a * (3.0 - 2.0 * a)   # smoothstep: eases off the stop and into the posts
	if _west_pivot:
		_west_pivot.rotation.y = -OPEN_ANGLE * a
	if _east_pivot:
		_east_pivot.rotation.y = OPEN_ANGLE * a
	if _latch_pivot:
		_latch_pivot.rotation.z = LATCH_UP * (1.0 - _latch_t)


func _build_props() -> void:
	var y := OpeningTerrain.surface_y(_center.x, _center.z)
	var root := Node3D.new()
	root.name = "PenGate"
	add_child(root)
	# West leaf: hinged on the west post, runs +x when shut, swings out to +z (down the boreen).
	_west_pivot = _leaf(root, "WestLeaf", Vector3(_center.x - GATE_HALF, y, _center.z), 1.0)
	# East leaf: hinged on the east post, runs -x when shut.
	_east_pivot = _leaf(root, "EastLeaf", Vector3(_center.x + GATE_HALF, y, _center.z), -1.0)
	# Keeper hook on the east leaf tip; the latch bar on the west leaf tip drops into it.
	_box(_east_pivot, Vector3(-LEAF_LEN + 0.06, 0.92, 0.09), Vector3(0.1, 0.16, 0.06), C_LATCH)
	_latch_pivot = Node3D.new()
	_latch_pivot.name = "Latch"
	_latch_pivot.position = Vector3(LEAF_LEN - 0.18, 0.9, 0.1)
	_west_pivot.add_child(_latch_pivot)
	_box(_latch_pivot, Vector3(0.24, 0.0, 0.0), Vector3(0.5, 0.06, 0.05), C_LATCH)
	# Shut-gate collider: off while open (cattle and Cian walk through), on once shut.
	_blocker = StaticBody3D.new()
	_blocker.name = "GateBlocker"
	_blocker.collision_layer = 1
	_blocker.collision_mask = 0
	_blocker.position = Vector3(_center.x, y + 0.75, _center.z)
	root.add_child(_blocker)
	_blocker_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GATE_HALF * 2.0, 1.5, 0.2)
	_blocker_shape.shape = shape
	_blocker_shape.disabled = true
	_blocker.add_child(_blocker_shape)


func _leaf(parent: Node3D, leaf_name: String, hinge: Vector3, dir: float) -> Node3D:
	var pv := Node3D.new()
	pv.name = leaf_name
	pv.position = hinge
	parent.add_child(pv)
	var mid := dir * (0.12 + LEAF_LEN * 0.5)
	# Two rails, a heel stile at the hinge and a head stile at the free end, one diagonal brace.
	_box(pv, Vector3(mid, 0.35, 0.0), Vector3(LEAF_LEN, 0.1, 0.07), C_RAIL)
	_box(pv, Vector3(mid, 0.95, 0.0), Vector3(LEAF_LEN, 0.1, 0.07), C_RAIL)
	_box(pv, Vector3(dir * 0.18, 0.62, 0.0), Vector3(0.1, 0.85, 0.08), C_RAIL.darkened(0.1))
	_box(pv, Vector3(dir * (0.12 + LEAF_LEN - 0.06), 0.62, 0.0), Vector3(0.1, 0.85, 0.08), C_RAIL.darkened(0.1))
	var brace := _box(pv, Vector3(mid, 0.65, 0.0), Vector3(Vector2(LEAF_LEN - 0.2, 0.6).length(), 0.08, 0.06), C_RAIL)
	brace.rotation.z = dir * atan2(0.6, LEAF_LEN - 0.2)
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(dir * (0.12 + LEAF_LEN), 0.6, 0.0)
	pv.add_child(tip)
	return pv


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	_mats[key] = m
	return m
