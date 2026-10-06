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
var _root_drop: float = 0.0 ## metres; kept across tick so a planted stance is not popped back up
## Opt-in (player): walking while a combat pose owns the body keeps the walk
## cycle on the legs. Arms / spine / hips stay on the combat additives.
var attack_walk_enabled: bool = false
var _attack_walk_w: float = 0.0 ## 0 = planted combat legs, 1 = walk-cycle legs
var _walk_legs: Dictionary = {} ## "left"/"right" -> Vector2(sole forward m, lift m) from the last tick
const LEG_JOINTS := ["left_thigh", "left_shin", "right_thigh", "right_shin"]
const ATTACK_WALK_BLEND_RATE := 9.0 ## 1/s; ~0.11 s from plant to stride
var _attack_walk_back: bool = false
## Per-joint rotation offset the cycle itself wrote this tick (before combat
## additives). A caller blending its own pose in or out of the plain cycle
## (the player's sprint carry) reads it so the hand-off does not pop.
var _cycle_rot: Dictionary = {}
## The planted stance's root drop is kept while striding (the upper body and
## the shaft stay at the planted height, so clearance is unchanged); a
## two-bone leg solve bends the knees so the soles walk on the ground under
## that drop instead of sinking.
const HIP_TO_SOLE := 0.835 ## rest hip pivot -> sole, metres (kerne mesh builder)
const THIGH_LEN := 0.44
const SHIN_TO_SOLE := 0.395
const ATTACK_WALK_STEP := 0.30 ## sole fore/aft amplitude, metres
const ATTACK_WALK_LIFT := 0.07 ## swing-foot lift, metres
const ATTACK_WALK_CADENCE := 10.0

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


func release_attack_lock() -> void:
	_attack_lock = 0.0


func forget_combat_additive(joint: String) -> void:
	## Drop one override without snapping the joint. The next tick can play a walk on it.
	_combat_overrides.erase(joint)


func set_combat_additive(joint: String, euler: Vector3) -> void:
	_combat_overrides[joint] = euler
	# Apply immediately so charge/aim reads without waiting for the next loco tick.
	var n: Node3D = joints.get(joint) as Node3D
	if n and _rest.has(joint):
		n.rotation = (_rest[joint]["rot"] as Vector3) + _leg_or_combat(joint, euler)


func _leg_or_combat(joint: String, euler: Vector3) -> Vector3:
	## While walking in a combat pose, a leg is the walk stride blended over
	## the planted pose. Every other joint is the combat additive as written.
	if _attack_walk_w <= 0.001 or not (joint in LEG_JOINTS):
		return euler
	return euler.lerp(_walk_leg_euler(joint), _attack_walk_w)


func _walk_leg_euler(joint: String) -> Vector3:
	## Two-bone solve for this leg's stride target at the hip height the kept
	## root drop leaves. Thighs undo the combat hip pitch so a leaning swing
	## does not tip the stride forward / back.
	var side := "left" if joint.begins_with("left") else "right"
	var target: Vector2 = _walk_legs.get(side, Vector2.ZERO)
	var hip_h := HIP_TO_SOLE - _root_drop - target.y
	var ik := _solve_leg(target.x, hip_h)
	if joint.ends_with("thigh"):
		var hips_x := (_combat_overrides.get("hips", Vector3.ZERO) as Vector3).x
		return Vector3(ik.x - hips_x, 0.0, deg_to_rad(-2.0 if side == "left" else 2.0))
	return Vector3(ik.y, 0.0, 0.0)


func attack_walk_weight() -> float:
	return _attack_walk_w

func get_combat_additive(joint: String) -> Vector3:
	return _combat_overrides.get(joint, Vector3.ZERO) as Vector3


func has_combat_additive(joint: String) -> bool:
	return _combat_overrides.has(joint)


## Drop the skeleton root for a crouched guard or a planted goad stance.
## 0 restores the authored rest. The value survives tick(); the walk bob stacks on top.
func set_root_drop(drop: float) -> void:
	_root_drop = maxf(drop, 0.0)
	var n: Node3D = joints.get("root") as Node3D
	if n == null or not _rest.has("root"):
		return
	var rest_pos: Vector3 = _rest["root"]["pos"]
	n.position = rest_pos + Vector3(0.0, -_root_drop, 0.0)
	if _attack_walk_w > 0.001:
		# Knees re-solve for the new hip height so the soles stay down.
		for key in LEG_JOINTS:
			var ln: Node3D = joints.get(key) as Node3D
			if ln == null or not _rest.has(key):
				continue
			var base: Vector3 = _combat_overrides.get(key, Vector3.ZERO)
			ln.rotation = (_rest[key]["rot"] as Vector3) + base.lerp(_walk_leg_euler(key), _attack_walk_w)


func clear_combat_additives() -> void:
	# Snap overridden joints back to rest before clearing so we don't freeze mid-pose.
	for key in _combat_overrides.keys():
		var n: Node3D = joints.get(key) as Node3D
		if n and _rest.has(key):
			n.rotation = _rest[key]["rot"] as Vector3
	_combat_overrides.clear()
	set_root_drop(0.0)


## Snap all joints back to authored rest (used on dismount).
func reset_to_rest() -> void:
	_phase = 0.0
	_breath = 0.0
	_turn_blend = 0.0
	_attack_lock = 0.0
	_combat_overrides.clear()
	_root_drop = 0.0
	_attack_walk_w = 0.0
	_walk_legs.clear()
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
	_root_drop = 0.0
	_attack_walk_w = 0.0
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

	# Walking inside a combat pose: stride on the legs, combat owns the rest.
	var attack_walk := (
		attack_walk_enabled
		and _state == &"attack"
		and not crouching
		and horiz_speed > 0.15
	)
	if move_dir_local.length_squared() > 0.01:
		_attack_walk_back = move_dir_local.z > 0.3
	if _state != &"attack":
		# Out of the combat pose the plain walk cycle owns the legs again.
		_attack_walk_w = 0.0
	else:
		_attack_walk_w = move_toward(_attack_walk_w, 1.0 if attack_walk else 0.0, delta * ATTACK_WALK_BLEND_RATE)

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
			# Hold near rest; combat additives applied below. Walking keeps
			# the walk cadence for the legs only (blended by _attack_walk_w).
			if _attack_walk_w > 0.001:
				cadence = ATTACK_WALK_CADENCE
		_:
			pass

	if cadence > 0.0:
		_phase += delta * cadence
	elif _state == &"idle" or _state == &"crouch_idle":
		_phase = move_toward(_phase, 0.0, delta * 4.0)

	var s := sin(_phase)
	var c := cos(_phase)
	var breath := sin(_breath * 1.7) * 0.012

	# Attack walk adds no body bob: the leg solve keeps the soles down and the
	# upper body (and shaft) stays at the planted height.
	_apply_joint("root", Vector3(0.0, bob * absf(s) - crouch_sink - _root_drop, 0.0), Vector3.ZERO)

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
	if _state == &"attack":
		# Stride targets per leg: sole fore/aft on the stride, lifted on the
		# swing. The knee solve itself runs against the live root drop and hip
		# pitch (_walk_leg_euler), so a pose written after this tick (the
		# settle's idle seat) cannot leave the knees bent for the old drop.
		var legs := {"left": _phase, "right": _phase + PI}
		for side in legs:
			var ph: float = legs[side]
			var swing := cos(ph)
			if _attack_walk_back:
				swing = -swing
			_walk_legs[side] = Vector2(ATTACK_WALK_STEP * sin(ph), ATTACK_WALK_LIFT * maxf(0.0, swing))
	var thigh_f := s * stride
	var thigh_b := -s * stride
	_apply_joint("left_thigh", Vector3.ZERO, Vector3(thigh_f, 0.0, deg_to_rad(-2.0)))
	_apply_joint("right_thigh", Vector3.ZERO, Vector3(thigh_b, 0.0, deg_to_rad(2.0)))
	# Shin bend on forward swing (positive thigh pitch → less bend; backward → more)
	_apply_joint("left_shin", Vector3.ZERO, Vector3(maxf(0.0, -thigh_f) * 0.9 + 0.05, 0.0, 0.0))
	_apply_joint("right_shin", Vector3.ZERO, Vector3(maxf(0.0, -thigh_b) * 0.9 + 0.05, 0.0, 0.0))

	# Arms opposite to legs (unless attacking — additives may override).
	# Z abduction: left -Z / right +Z swing NEXT TO the torso. The old +10/-10
	# signs pulled empty arms through the chest; sprint needs more clearance.
	var arm_l := -s * arm_amp
	var arm_r := s * arm_amp
	if _state == &"idle" or _state == &"crouch_idle":
		arm_l = breath * 0.8
		arm_r = -breath * 0.8
	var arm_out := deg_to_rad(22.0 if _state == &"sprint" else 14.0)
	_apply_joint("left_arm", Vector3.ZERO, Vector3(arm_l, 0.0, -arm_out))
	_apply_joint("right_arm", Vector3.ZERO, Vector3(arm_r, 0.0, arm_out))
	_apply_joint("left_forearm", Vector3.ZERO, Vector3(maxf(0.0, -arm_l) * 0.4, 0.0, 0.0))
	_apply_joint("right_forearm", Vector3.ZERO, Vector3(maxf(0.0, -arm_r) * 0.4, 0.0, 0.0))

	# Combat additives on top
	for key in _combat_overrides:
		var n: Node3D = joints.get(key) as Node3D
		if n and _rest.has(key):
			n.rotation = (_rest[key]["rot"] as Vector3) + _leg_or_combat(String(key), _combat_overrides[key] as Vector3)
	# Walking in a combat pose with no leg additive: the stride still shows.
	if _state == &"attack" and _attack_walk_w > 0.001:
		for key in LEG_JOINTS:
			if _combat_overrides.has(key):
				continue
			var ln: Node3D = joints.get(key) as Node3D
			if ln and _rest.has(key):
				ln.rotation = (_rest[key]["rot"] as Vector3) + _walk_leg_euler(key) * _attack_walk_w

	# Slight yaw lean into move direction
	if move_dir_local.length_squared() > 0.01 and _state != &"attack":
		var lean := clampf(move_dir_local.x, -1.0, 1.0) * deg_to_rad(4.0)
		var torso_n: Node3D = joints.get("torso") as Node3D
		if torso_n:
			torso_n.rotation.z += lean


func _solve_leg(fx: float, h: float) -> Vector2:
	## Sagittal two-bone IK. fx: sole forward of the hip (m), h: hip above the
	## sole (m). Returns (thigh pitch, shin pitch); +thigh = forward, -shin =
	## knee bent with the foot behind it (same signs the strike poses use).
	var l1 := THIGH_LEN
	var l2 := SHIN_TO_SOLE
	var d := clampf(sqrt(fx * fx + h * h), 0.05, l1 + l2 - 0.0005)
	var cos_k := clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0)
	var bend := PI - acos(cos_k)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	return Vector2(atan2(fx, h) + acos(cos_a), -bend)


func _apply_joint(key: String, pos_off: Vector3, rot_off: Vector3) -> void:
	var n: Node3D = joints.get(key) as Node3D
	if n == null or not _rest.has(key):
		return
	# Don't overwrite joints that combat is actively driving via additive this frame
	# (additive applied after). Base pose always set first.
	n.position = (_rest[key]["pos"] as Vector3) + pos_off
	n.rotation = (_rest[key]["rot"] as Vector3) + rot_off
	_cycle_rot[key] = rot_off


## Offset the walk / run / sprint cycle wrote on this joint last tick.
func cycle_offset(joint: String) -> Vector3:
	return _cycle_rot.get(joint, Vector3.ZERO) as Vector3


## Stride phase (radians). sin(phase) > 0: left leg forward, right arm forward.
func cycle_phase() -> float:
	return _phase


func current_state() -> StringName:
	return _state
