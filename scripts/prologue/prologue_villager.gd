extends Node3D
class_name PrologueVillager
## Prologue (raid beat, after the opening's meal): a household / neighbour figure on the kerne rig
## (KerneMeshBuilder + KerneLocomotion, its own palette, no kit props), scaled to a real stature.
## Walks a list of waypoints over the terrain at a real walking pace, turns to face things, and
## speaks lines as a bark over the head plus the HUD flash (like Máire's lines). No collider and
## no AI: the raid sequence drives it. Right-hand pose hooks let a source hold a prop
## (`hold_right(on)`), and `reach_right(world_point, w)` points the right arm at a spot (pulling the
## hatchet from the block, handing over a dish).

signal arrived

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
## The kerne rig is modelled at 1.84 m (see PlayerController.CIAN_SCALE).
const RIG_STATURE := 1.84
const TURN_RATE := 5.0
const ARRIVE := 0.08

@export var display_name: String = ""
@export var stature_m: float = 1.65
@export var walk_speed: float = 1.2
## Palette keys as KerneMeshBuilder.PALETTE_PLAYER.
var palette: Dictionary = {}

var _visual: Node3D = null
var _loco: KerneLocomotion = null
var _label: Label3D = null
var _bark: Label3D = null
var _bark_t: float = 0.0
var _path: Array[Vector3] = []
var _speed_now: float = 0.0
var _face_yaw: float = NAN
var _director: Node = null
var _hold_w: float = 0.0
var _hold_on: bool = false
var _reach_point: Vector3 = Vector3.ZERO
var _reach_w: float = 0.0
var _right_hand: Node3D = null


func _ready() -> void:
	add_to_group("prologue_villager")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_loco = KerneLocomotion.new()
	_loco.name = "Locomotion"
	_loco.build_on_ready = false
	_loco.include_kit_props = false
	_loco.palette_override = palette
	add_child(_loco)
	_loco.rebuild()
	var s := stature_m / RIG_STATURE
	_visual.scale = Vector3.ONE * s
	_loco.body_scale = s
	var fore := _loco.get_joint("right_forearm")
	if fore:
		_right_hand = Node3D.new()
		_right_hand.name = "RightHand"
		_right_hand.position = Vector3(0.0, -0.26, 0.0)
		fore.add_child(_right_hand)
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 36
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(0.92, 0.86, 0.7)
	_label.outline_size = 10
	_label.outline_modulate = Color(0.05, 0.05, 0.04, 0.85)
	_label.position = Vector3(0.0, stature_m + 0.22, 0.0)
	_label.visible = display_name != ""
	add_child(_label)
	_bark = Label3D.new()
	_bark.name = "Bark"
	_bark.font_size = 30
	_bark.pixel_size = 0.0085
	_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark.modulate = Color(1.0, 0.96, 0.82)
	_bark.outline_size = 12
	_bark.outline_modulate = Color(0.08, 0.06, 0.04, 0.92)
	_bark.position = Vector3(0.0, stature_m + 0.42, 0.0)
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark.width = 560.0
	_bark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_bark.visible = false
	add_child(_bark)
	call_deferred("_bind")


func _bind() -> void:
	_director = get_tree().get_first_node_in_group("opening_drive")
	snap_to_ground()


# ---------------------------------------------------------------- driving

## Walk through `points` (world, y ignored) in order at walk_speed (or `speed` if > 0).
func walk_path(points: Array, speed: float = -1.0) -> void:
	_path.clear()
	for p in points:
		_path.append(Vector3(p.x, 0.0, p.z))
	if speed > 0.0:
		walk_speed = speed
	_face_yaw = NAN


func stop() -> void:
	_path.clear()


func is_walking() -> bool:
	return not _path.is_empty()


func place(p: Vector3, yaw: float) -> void:
	global_position = Terrain.surface_point(p, 0.0)
	rotation.y = yaw
	_path.clear()
	_face_yaw = NAN


func face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_face_yaw = atan2(-d.x, -d.z)


func face_yaw(yaw: float) -> void:
	_face_yaw = yaw


func say(line: String, secs: float = 5.0) -> void:
	_bark.text = line
	_bark.visible = true
	_bark_t = secs
	if _director == null:
		_director = get_tree().get_first_node_in_group("opening_drive")
	if _director and _director.has_method("flash"):
		_director.call("flash", "%s: %s" % [display_name, line], secs - 0.5)
	print("PROLOGUE_LINE speaker=%s line=%s" % [display_name, line])


func is_bark_visible() -> bool:
	return _bark.visible


func right_hand() -> Node3D:
	return _right_hand


## Forearm raised a little in front, as when carrying a dish or a tool by the handle.
func hold_right(on: bool) -> void:
	_hold_on = on


## Point the right arm at a world spot (weight w 0..1, eased by the caller).
func reach_right(world_point: Vector3, w: float) -> void:
	_reach_point = world_point
	_reach_w = clampf(w, 0.0, 1.0)


func snap_to_ground() -> void:
	if is_inside_tree():
		global_position.y = Terrain.surface_y(global_position.x, global_position.z)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	var speed := 0.0
	if not _path.is_empty():
		var tgt := _path[0]
		var to := Vector3(tgt.x - global_position.x, 0.0, tgt.z - global_position.z)
		var d := to.length()
		if d <= ARRIVE:
			_path.remove_at(0)
			if _path.is_empty():
				arrived.emit()
		else:
			var want := atan2(-to.x, -to.z)
			rotation.y = rotate_toward(rotation.y, want, TURN_RATE * delta)
			var aligned := absf(angle_difference(rotation.y, want)) < 0.7
			speed = walk_speed if aligned else walk_speed * 0.3
			var step := minf(d, speed * delta)
			global_position += to / d * step
	elif not is_nan(_face_yaw):
		rotation.y = rotate_toward(rotation.y, _face_yaw, TURN_RATE * 0.6 * delta)
	_speed_now = lerpf(_speed_now, speed, clampf(delta * 8.0, 0.0, 1.0))
	snap_to_ground()
	if _loco:
		_loco.tick(delta, _speed_now, false, false, false, Vector3(0, 0, -1) if _speed_now > 0.05 else Vector3.ZERO)
		_pose_right_arm(delta)
	if _bark_t > 0.0:
		_bark_t -= delta
		if _bark_t <= 0.0:
			_bark.visible = false


func _pose_right_arm(delta: float) -> void:
	var arm := _loco.get_joint("right_arm")
	var fore := _loco.get_joint("right_forearm")
	if arm == null or fore == null:
		return
	_hold_w = move_toward(_hold_w, 1.0 if _hold_on else 0.0, delta * 3.0)
	if _hold_w > 0.0:
		# Upper arm down by the side, forearm forward (elbow ~80°): a dish or tool held in front.
		arm.rotation = arm.rotation.lerp(Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-6.0)), _hold_w)
		fore.rotation = fore.rotation.lerp(Vector3(deg_to_rad(78.0), 0.0, 0.0), _hold_w)
	if _reach_w > 0.0:
		var sh := arm.global_position
		var dir := (_reach_point - sh)
		if dir.length() > 0.05:
			var local := (arm.get_parent() as Node3D).global_transform.basis.orthonormalized().inverse() * dir.normalized()
			# Arm hangs along its −Y: aim −Y at the target.
			var b := Basis.looking_at(local, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
			var cur := arm.basis.orthonormalized()
			arm.basis = cur.slerp(b.orthonormalized(), _reach_w)
			fore.rotation = fore.rotation.lerp(Vector3(deg_to_rad(15.0), 0.0, 0.0), _reach_w)
