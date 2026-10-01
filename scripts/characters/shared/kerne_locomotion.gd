class_name KerneLocomotion
extends Node
## Procedural locomotion + idle breathe for modular kerne joints.
## Driven each physics frame from player/NPC controllers (speed / crouch / sprint).

signal pose_updated(state: StringName)

@export var visual_path: NodePath = ^"../Visual"
@export var build_on_ready: bool = true
@export var hostile_palette: bool = false
@export var include_kit_props: bool = true

var joints: Dictionary = {}
var _rest: Dictionary = {}
var _phase: float = 0.0
var _breath: float = 0.0
var _turn_blend: float = 0.0
var _last_yaw: float = 0.0
var _state: StringName = &"idle"
var _attack_lock: float = 0.0
var _combat_overrides: Dictionary = {} ## joint_name -> Vector3 euler additive

# Cached owner body for yaw delta
var _body: Node3D


func _ready() -> void:
	_body = get_parent() as Node3D
	if _body:
		_last_yaw = _body.rotation.y
	if build_on_ready:
		rebuild()


func rebuild() -> void:
	var visual := get_node_or_null(visual_path) as Node3D
	if visual == null:
		return
	var palette := KerneMeshBuilder.PALETTE_HOSTILE if hostile_palette else KerneMeshBuilder.PALETTE_PLAYER
	joints = KerneMeshBuilder.build(visual, palette, include_kit_props)
	_rest.clear()
	for key in joints:
		var n: Node3D = joints[key]
		if n:
			_rest[key] = {
				"pos": n.position,
				"rot": n.rotation,
			}
	# Compatibility aliases for old capture tools / controller paths
	_ensure_compat_aliases(visual)


func _ensure_compat_aliases(visual: Node3D) -> void:
	# Expose Visual/RightArm as the joint Node3D (not a MeshInstance) for scripts
	# that still look up that path — already named RightArm under Torso.
	# Also create flat legacy MeshInstance stubs? No — update callers.
	# Ensure path Visual/Root/Hips/Torso/RightArm exists (it does).
	# Old path Visual/RightArm: add a NodePath-friendly remote? Simpler: duplicate ref as child of Visual.
	if visual.get_node_or_null("RightArm") == null and joints.has("right_arm"):
		# Marker only — RemoteTransform would fight animation. Scripts should use joints.
		pass


func get_right_arm() -> Node3D:
	return joints.get("right_arm") as Node3D


func get_joint(name: String) -> Node3D:
	return joints.get(name) as Node3D


func lock_attack(duration: float) -> void:
	_attack_lock = maxf(_attack_lock, duration)


func set_combat_additive(joint: String, euler: Vector3) -> void:
	_combat_overrides[joint] = euler


func clear_combat_additives() -> void:
	_combat_overrides.clear()


## Snap all joints back to authored rest (used on dismount).
func reset_to_rest() -> void:
	_phase = 0.0
	_breath = 0.0
	_turn_blend = 0.0
	_attack_lock = 0.0
	_combat_overrides.clear()
	_state = &"idle"
	for key in joints:
		var n: Node3D = joints[key] as Node3D
		if n == null or not _rest.has(key):
			continue
		n.position = _rest[key]["pos"] as Vector3
		n.rotation = _rest[key]["rot"] as Vector3
	pose_updated.emit(_state)


## Seated mounted bind pose (C2). Replaces on-foot walk cycles while is_mounted.
## hips down, legs astride, spine slight forward; optional light bob from gait.
func tick_mounted(delta: float, horiz_speed: float, galloping: bool = false) -> void:
	if joints.is_empty():
		return

	_attack_lock = 0.0
	_combat_overrides.clear()
	_breath += delta

	var target_state: StringName = &"mounted_idle"
	if horiz_speed > 0.4:
		target_state = &"mounted_gallop" if galloping else &"mounted_trot"
	_state = target_state
	pose_updated.emit(_state)

	# Cadence / bob amplitude by gait
	var cadence := 0.0
	var bob_amp := 0.0
	var lean_extra := 0.0
	match _state:
		&"mounted_trot":
			cadence = 6.5
			bob_amp = 0.018
			lean_extra = deg_to_rad(2.0)
		&"mounted_gallop":
			cadence = 9.0
			bob_amp = 0.032
			lean_extra = deg_to_rad(5.0)
		_:
			cadence = 0.0
			bob_amp = 0.0

	if cadence > 0.0:
		_phase += delta * cadence
	else:
		_phase = move_toward(_phase, 0.0, delta * 5.0)

	var s := sin(_phase)
	var breath := sin(_breath * 1.5) * 0.01
	var bob_y := bob_amp * absf(s) if cadence > 0.0 else 0.0

	# Sink hips into the saddle + light vertical bob
	_apply_joint("root", Vector3(0.0, -0.08 + bob_y, 0.02), Vector3.ZERO)
	_apply_joint("hips", Vector3.ZERO, Vector3(deg_to_rad(6.0), 0.0, 0.0))

	# Spine slight forward lean (more at gallop)
	var torso_pitch := deg_to_rad(10.0) + lean_extra + breath * 0.4
	_apply_joint("torso", Vector3.ZERO, Vector3(torso_pitch, 0.0, 0.0))
	_apply_joint("head", Vector3.ZERO, Vector3(-torso_pitch * 0.35 - breath * 0.3, 0.0, 0.0))

	# Legs astride: thighs open + knees forward along the barrel
	var thigh_pitch := deg_to_rad(68.0)
	var thigh_open := deg_to_rad(32.0)
	var shin_bend := deg_to_rad(55.0)
	# Subtle post bounce on shins while moving
	var shin_bob := deg_to_rad(4.0) * s if cadence > 0.0 else 0.0
	_apply_joint("left_thigh", Vector3.ZERO, Vector3(thigh_pitch, 0.0, -thigh_open))
	_apply_joint("right_thigh", Vector3.ZERO, Vector3(thigh_pitch, 0.0, thigh_open))
	_apply_joint("left_shin", Vector3.ZERO, Vector3(shin_bend + shin_bob, 0.0, 0.0))
	_apply_joint("right_shin", Vector3.ZERO, Vector3(shin_bend - shin_bob, 0.0, 0.0))

	# Quiet rein / rest arms (slight forward, elbows soft)
	var arm_pitch := deg_to_rad(28.0)
	var arm_bob := deg_to_rad(3.0) * s if cadence > 0.0 else breath * 0.6
	_apply_joint("left_arm", Vector3.ZERO, Vector3(arm_pitch + arm_bob, deg_to_rad(-8.0), deg_to_rad(18.0)))
	_apply_joint("right_arm", Vector3.ZERO, Vector3(arm_pitch - arm_bob, deg_to_rad(8.0), deg_to_rad(-18.0)))
	_apply_joint("left_forearm", Vector3.ZERO, Vector3(deg_to_rad(35.0), 0.0, 0.0))
	_apply_joint("right_forearm", Vector3.ZERO, Vector3(deg_to_rad(35.0), 0.0, 0.0))


## Call from CharacterBody3D._physics_process after move_and_slide.
func tick(
	delta: float,
	horiz_speed: float,
	sprinting: bool,
	crouching: bool,
	attacking: bool,
	move_dir_local: Vector3 = Vector3.ZERO
) -> void:
	if joints.is_empty():
		return

	_attack_lock = maxf(0.0, _attack_lock - delta)
	_breath += delta

	var yaw_delta := 0.0
	if _body:
		yaw_delta = wrapf(_body.rotation.y - _last_yaw, -PI, PI)
		_last_yaw = _body.rotation.y
	var turning := absf(yaw_delta) > 0.002 and horiz_speed < 0.35
	_turn_blend = move_toward(_turn_blend, 1.0 if turning else 0.0, delta * 6.0)

	var target_state: StringName = &"idle"
	if attacking or _attack_lock > 0.0:
		target_state = &"attack"
	elif crouching and horiz_speed > 0.15:
		target_state = &"crouch_walk"
	elif crouching:
		target_state = &"crouch_idle"
	elif sprinting and horiz_speed > 0.5:
		target_state = &"sprint"
	elif horiz_speed > 0.15:
		target_state = &"walk"
	elif _turn_blend > 0.35:
		target_state = &"turn"
	_state = target_state
	pose_updated.emit(_state)

	var cadence := 0.0
	var stride := 0.0
	var arm_amp := 0.0
	var bob := 0.0
	var crouch_sink := 0.0

	match _state:
		&"walk":
			cadence = 7.2
			stride = 0.85
			arm_amp = 0.65
			bob = 0.03
		&"sprint":
			cadence = 10.5
			stride = 1.05
			arm_amp = 0.95
			bob = 0.05
		&"crouch_walk":
			cadence = 5.0
			stride = 0.55
			arm_amp = 0.35
			bob = 0.015
			crouch_sink = 0.12
		&"crouch_idle":
			crouch_sink = 0.14
		&"turn":
			cadence = 4.0
			stride = 0.22
			arm_amp = 0.15
		&"attack":
			# Hold near rest; combat additives applied below
			pass
		_:
			pass

	if cadence > 0.0:
		_phase += delta * cadence
	elif _state == &"idle" or _state == &"crouch_idle":
		_phase = move_toward(_phase, 0.0, delta * 4.0)

	var s := sin(_phase)
	var c := cos(_phase)
	var breath := sin(_breath * 1.7) * 0.012

	_apply_joint("root", Vector3(0.0, bob * absf(s) - crouch_sink, 0.0), Vector3.ZERO)

	var hip_sway := Vector3(0.0, s * stride * 0.08, 0.0)
	if _state == &"turn":
		hip_sway.y = sign(yaw_delta) * _turn_blend * 0.25
	_apply_joint("hips", Vector3.ZERO, hip_sway)

	var torso_breath := Vector3(breath * 0.35, 0.0, 0.0)
	if _state == &"sprint":
		torso_breath.x += deg_to_rad(8.0)
	elif _state == &"crouch_walk" or _state == &"crouch_idle":
		torso_breath.x += deg_to_rad(12.0)
	elif _state == &"walk":
		torso_breath.x += deg_to_rad(3.0)
	torso_breath.y += s * stride * 0.06
	_apply_joint("torso", Vector3.ZERO, torso_breath)

	_apply_joint("head", Vector3.ZERO, Vector3(-breath * 0.5 - torso_breath.x * 0.3, -hip_sway.y * 0.5, 0.0))

	# Legs: opposite phase
	var thigh_f := s * stride
	var thigh_b := -s * stride
	_apply_joint("left_thigh", Vector3.ZERO, Vector3(thigh_f, 0.0, deg_to_rad(-2.0)))
	_apply_joint("right_thigh", Vector3.ZERO, Vector3(thigh_b, 0.0, deg_to_rad(2.0)))
	# Shin bend on forward swing (positive thigh pitch → less bend; backward → more)
	_apply_joint("left_shin", Vector3.ZERO, Vector3(maxf(0.0, -thigh_f) * 0.9 + 0.05, 0.0, 0.0))
	_apply_joint("right_shin", Vector3.ZERO, Vector3(maxf(0.0, -thigh_b) * 0.9 + 0.05, 0.0, 0.0))

	# Arms opposite to legs (unless attacking — additives may override)
	var arm_l := -s * arm_amp
	var arm_r := s * arm_amp
	if _state == &"idle" or _state == &"crouch_idle":
		arm_l = breath * 0.8
		arm_r = -breath * 0.8
	_apply_joint("left_arm", Vector3.ZERO, Vector3(arm_l, 0.0, deg_to_rad(10.0)))
	_apply_joint("right_arm", Vector3.ZERO, Vector3(arm_r, 0.0, deg_to_rad(-10.0)))
	_apply_joint("left_forearm", Vector3.ZERO, Vector3(maxf(0.0, -arm_l) * 0.4, 0.0, 0.0))
	_apply_joint("right_forearm", Vector3.ZERO, Vector3(maxf(0.0, -arm_r) * 0.4, 0.0, 0.0))

	# Combat additives on top
	for key in _combat_overrides:
		var n: Node3D = joints.get(key) as Node3D
		if n and _rest.has(key):
			n.rotation = (_rest[key]["rot"] as Vector3) + (_combat_overrides[key] as Vector3)

	# Slight yaw lean into move direction
	if move_dir_local.length_squared() > 0.01 and _state != &"attack":
		var lean := clampf(move_dir_local.x, -1.0, 1.0) * deg_to_rad(4.0)
		var torso_n: Node3D = joints.get("torso") as Node3D
		if torso_n:
			torso_n.rotation.z += lean


func _apply_joint(key: String, pos_off: Vector3, rot_off: Vector3) -> void:
	var n: Node3D = joints.get(key) as Node3D
	if n == null or not _rest.has(key):
		return
	# Don't overwrite joints that combat is actively driving via additive this frame
	# (additive applied after). Base pose always set first.
	n.position = (_rest[key]["pos"] as Vector3) + pos_off
	n.rotation = (_rest[key]["rot"] as Vector3) + rot_off


func current_state() -> StringName:
	return _state
