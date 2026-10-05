extends CharacterBody3D
## Third-person controller. Default feel is the cattle goad.
## With the goad out, mouse look IS the guard (no held key): left, right,
## high, low, or chest when the look is neutral. Sprint or an attack drops it.
## Look-down alone is only the low guard. It does not stab.
## Left click while looking down, or right click at any look, is one uncharged
## point jab. Holding either button does not charge it or fire it again.
## Any other left click is still a charged shaft swing (left/right/top,
## including high-left). Look-down is not a shaft-swing direction.
## Hatchet hold-release is unchanged. Knife stays a tap: left/right cuts,
## neutral/look-up thrust. Knife RMB is not a stab.
const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
## HealthCombatBridge (sibling) mirrors player CombatSystem ↔ CharacterHealth.
## Crouch (Ctrl / C): lower capsule + camera, slower move, quieter footprint.
## Locomotion: procedural kerne joints via KerneLocomotion (walk/run/sprint/crouch/idle).

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.4
const DRAG_SPEED := 1.75
const ACCEL := 18.0
const DECEL := 22.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003

const STAND_CAPSULE_HEIGHT := 1.7
const CROUCH_CAPSULE_HEIGHT := 0.95
const STAND_CAPSULE_Y := 0.85
const CROUCH_CAPSULE_Y := 0.48
const STAND_PIVOT_Y := 1.45
const CROUCH_PIVOT_Y := 0.72
const STAND_VISUAL_Y := 0.0
const CROUCH_VISUAL_Y := -0.55
const CROUCH_LERP := 10.0

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var combat: CombatSystem = $CombatSystem
@onready var health_bridge: HealthCombatBridge = $HealthCombatBridge
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hurtbox_shape: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var visual: Node3D = $Visual
@onready var weapon_visual: Node3D = $WeaponVisual
@onready var locomotion: KerneLocomotion = $KerneLocomotion

var right_arm: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _jump_buffered: bool = false
var _arm_base_rotation: Vector3 = Vector3.ZERO
var _arm_tween: Tween
var _torso_tween: Tween
var _camera_base_pos: Vector3
var _punch_tween: Tween
var _sprinting: bool = false
var _arm_fore_scale: float = 0.35

## Stealth footprint (read by DetectionSensor).
var is_crouching: bool = false
var _noise_level: float = 0.0
var _crouch_blend: float = 0.0
var _capsule_shape: CapsuleShape3D
var _hurt_shape: CapsuleShape3D
var _weapon_base_y: float = 1.05

## FULL bog body-drag: slow move + stamina drain while dragging a corpse.
const DRAG_STAMINA_PER_SEC := 11.0
var dragging_body: Node3D = null
var drag_stamina_exhausted: bool = false

## Horse traversal (greybox mount).
var is_mounted: bool = false
var mounted_horse: Node3D = null

## Directional hatchet: hold LMB to charge; mouse aim (look) picks top|left|right.
var _charge_aim_delta: Vector2 = Vector2.ZERO ## mouse aim offset while holding (not WASD/flick)
var _hatchet_charge_armed: bool = false
const CHARGE_AIM_SIDE_THRESH := 12.0 ## px horizontal aim for left/right
const CHARGE_AIM_TOP_THRESH := 10.0 ## px upward aim for top (also camera pitch)
## Goad aim stick. Full left/right/stab by the time the strike cardinal locks,
## and it keeps tracking back toward center. Not used for guard faces.
const GOAD_AIM_SPAN := 18.0
## Follow-through eases back to the ready pose. Not a hard zero, not a victory hold.
const GOAD_SETTLE_SEC := 0.22
## Guard face changes travel. Short enough to read as a motion, not a lag.
const GUARD_BLEND_SEC := 0.12
## Back seat to the two-hand idle, and the same path home. Not a pop.
const GOAD_DRAW_SEC := 0.36
## Hit flinch: snap in, short hold, ease back to the ready pose. Not a knockdown.
const HURT_FLINCH_IN_SEC := 0.10
const HURT_FLINCH_HOLD_SEC := 0.12
const HURT_FLINCH_OUT_SEC := 0.16
var _hurt_reacting: bool = false
## Light footwork step during charge (does NOT cancel charge). Sprint still cancels.
const CHARGE_STEP_SPEED := 4.4
const CHARGE_STEP_SECS := 0.13
const CHARGE_STEP_COOLDOWN := 0.38
var _charge_step_left: float = 0.0
var _charge_step_cd: float = 0.0
var _charge_step_dir: Vector3 = Vector3.ZERO

## Recent mouse look used to pick a goad/knife tap direction (not hatchet charge).
var _tool_aim_delta: Vector2 = Vector2.ZERO
## Player-space weapon euler while a goad/knife body strike owns the mesh.
var _tool_weapon_euler: Vector3 = Vector3.ZERO
var _tool_root_drop: float = 0.0
## Metres the goad grip slides along the shaft during a bent-elbow guard.
## The mesh shifts back by the same amount, so the shaft stays where it was.
var _goad_grip_slide: float = 0.0
## 0 = full goad on the back seat, 1 = landed in the hands.
var _goad_draw_u: float = 1.0
var _goad_draw_tween: Tween
var _goad_stowing: bool = false
var _back_goad_seat: Transform3D = Transform3D.IDENTITY
var _goad_stow_from: Transform3D = Transform3D.IDENTITY
var _goad_seat_ready: bool = false
var _tool_pose_active: bool = false
## True while the goad shaft-block pose is applied (so sprint/release can drop it).
var _shaft_pose_applied: bool = false
## Face whose seated pose is already on screen. Empty while a blend or a swing owns the body.
var _guard_face_held: StringName = &""
var _guard_blend_active: bool = false
var _guard_blend_u: float = 0.0
var _guard_from_pose: Dictionary = {}
var _guard_to_pose: Dictionary = {}
var _guard_from_xf: Transform3D = Transform3D.IDENTITY
var _guard_to_xf: Transform3D = Transform3D.IDENTITY
## Pose on screen when a goad charge started. Ratio 0 stays here instead of popping to idle.
var _charge_from_pose: Dictionary = {}
var _charge_from_xf: Transform3D = Transform3D.IDENTITY
var _charge_from_ready: bool = false
## Strike and charge plant the shaft between two captured holds. Not a seat search.
var _shaft_xf_blend: bool = false
var _shaft_from_xf: Transform3D = Transform3D.IDENTITY
var _shaft_to_xf: Transform3D = Transform3D.IDENTITY
var _shaft_xf_u: float = 0.0
## Non-jab swings. The jab leaves this clear so its blend is not retuned.
var _swing_arc_live: bool = false
var _swing_arc_aim: Vector2 = Vector2.ZERO
var _swing_from_slide: float = 0.0
var _swing_to_slide: float = 0.0
## Body sample only. The shaft arc is solved after the spine has turned.
var _swing_pose_only: bool = false
var _swing_arc_interior: bool = false
## Stable player frame for one continuous goad swing. Not the jab.
var _swing_frame: Transform3D = Transform3D.IDENTITY
var _swing_keys_butt: PackedVector3Array = PackedVector3Array()
var _swing_keys_tip: PackedVector3Array = PackedVector3Array()
var _swing_key_u: PackedFloat32Array = PackedFloat32Array()
var _swing_start_pose: Dictionary = {}
var _swing_follow_pose: Dictionary = {}
var _swing_strike_u: float = 0.5
## After a shaft swing the follow-through stays. Idle must not stand the stick up.
var _goad_swing_held: bool = false
## While the goad guard is up, look offset is not decayed so a face stays put.
const TOOL_AIM_SIDE := 10.0
const TOOL_AIM_VERT := 8.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if camera:
		_camera_base_pos = camera.position
	if combat:
		combat.attack_performed.connect(_on_attack_performed)
		combat.hit_landed.connect(_on_hit_landed)
		combat.damage_taken.connect(_on_damage_taken)
		combat.died.connect(_on_died)
		combat.weapon_changed.connect(_on_weapon_changed)
		combat.charge_updated.connect(_on_charge_updated)
		combat.charge_cancelled.connect(_on_charge_cancelled)
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		_capsule_shape = collision_shape.shape as CapsuleShape3D
	if hurtbox_shape and hurtbox_shape.shape is CapsuleShape3D:
		_hurt_shape = hurtbox_shape.shape as CapsuleShape3D
	if weapon_visual:
		_weapon_base_y = weapon_visual.position.y
	# Locomotion builds mesh in its _ready; resolve arm after a deferred pass.
	call_deferred("_bind_locomotion_joints")


func _bind_locomotion_joints() -> void:
	if locomotion == null:
		return
	if locomotion.joints.is_empty():
		locomotion.rebuild()
	right_arm = locomotion.get_right_arm()
	if right_arm:
		_arm_base_rotation = right_arm.rotation
	var back_goad := get_node_or_null("Visual")
	if back_goad:
		var seat := (back_goad as Node).find_child("BackGoad", true, false) as Node3D
		if seat:
			_back_goad_seat = seat.transform
			_goad_seat_ready = true
	_goad_draw_u = 0.0 if combat == null or combat.current_weapon != CombatSystem.Weapon.GOAD else 1.0
	_sync_back_goad_visibility()
	_apply_weapon_idle_pose()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_tool_aim_delta += motion.relative
		_tool_aim_delta = _tool_aim_delta.limit_length(96.0)
		if is_mounted and mounted_horse and is_instance_valid(mounted_horse):
			# Yaw the horse; keep rider facing saddle-forward.
			mounted_horse.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
			rotation = Vector3.ZERO
		else:
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-60.0), deg_to_rad(45.0))

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("jump"):
		_jump_buffered = true

	if combat == null or combat.is_dead:
		return
	if dragging_body != null and is_instance_valid(dragging_body):
		return

	# No melee while mounted — dismount to fight (slice rule).
	if is_mounted:
		return

	# Mouse aim while charging selects strike arc (top / left / right).
	if combat.is_charging and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_charge_aim_delta += (event as InputEventMouseMotion).relative
		if combat.current_weapon == CombatSystem.Weapon.GOAD:
			_charge_aim_delta.x = clampf(_charge_aim_delta.x, -GOAD_AIM_SPAN, GOAD_AIM_SPAN)
			_charge_aim_delta.y = clampf(_charge_aim_delta.y, -GOAD_AIM_SPAN, GOAD_AIM_SPAN)
		_apply_charge_direction_from_input()

	if event.is_action_pressed("attack_light"):
		_begin_hatchet_or_light()
	elif event.is_action_released("attack_light"):
		_release_hatchet_or_ignore()
	elif event.is_action_pressed("attack_heavy"):
		# Goad RMB is the uncharged jab. Knife RMB stays heavy. Hatchet ignores RMB.
		_heavy_or_ignore_hatchet()
	elif event.is_action_pressed("cycle_weapon"):
		if combat.is_charging:
			combat.cancel_charge()
		combat.cycle_weapon(1)
	elif event.is_action_pressed("weapon_hatchet"):
		# Key 1 stows. The hatchet is not in this kit.
		combat.set_weapon(CombatSystem.Weapon.UNARMED)
	elif event.is_action_pressed("weapon_knife"):
		combat.set_weapon(CombatSystem.Weapon.KNIFE)
	elif event.is_action_pressed("weapon_goad"):
		combat.set_weapon(CombatSystem.Weapon.GOAD)


func _physics_process(delta: float) -> void:
	# Decay strike-aim unless a guard is up. A held face keeps the look that set it.
	if combat == null or not combat.is_shaft_blocking:
		_tool_aim_delta = _tool_aim_delta.move_toward(Vector2.ZERO, 150.0 * delta)
	if combat and combat.is_charging and not is_mounted:
		_apply_charge_direction_from_input()

	if is_mounted:
		# Horse owns world locomotion; keep residual velocity cleared.
		# Rider body uses seated bind pose (KerneLocomotion.tick_mounted) driven by horse.
		velocity = Vector3.ZERO
		_noise_level = 0.35  # mounted presence — audible but not sprint-loud
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var locked := combat != null and not combat.can_move() and not (combat != null and combat.is_charging)
	# Charging: light step footwork (no cancel) + slow drift.
	var charging_move := combat != null and combat.is_charging
	_charge_step_cd = maxf(0.0, _charge_step_cd - delta)
	_charge_step_left = maxf(0.0, _charge_step_left - delta)
	if charging_move and _charge_step_left <= 0.0 and _charge_step_cd <= 0.0 and is_on_floor():
		var step_in := _move_vector()
		if step_in != Vector2.ZERO and (
			Input.is_action_just_pressed("move_left")
			or Input.is_action_just_pressed("move_right")
			or Input.is_action_just_pressed("move_forward")
			or Input.is_action_just_pressed("move_back")
		):
			_charge_step_dir = (transform.basis * Vector3(step_in.x, 0.0, step_in.y)).normalized()
			_charge_step_left = CHARGE_STEP_SECS
			_charge_step_cd = CHARGE_STEP_COOLDOWN
	var want_crouch := Input.is_action_pressed("crouch") and is_on_floor() and not locked
	# Stay crouched mid-air until land if already crouching; no jump while crouched.
	if not is_on_floor() and is_crouching:
		want_crouch = true
	is_crouching = want_crouch
	_apply_crouch_visual(delta)

	var dragging := dragging_body != null and is_instance_valid(dragging_body)
	if not locked and not is_crouching and not dragging and (_jump_buffered or Input.is_action_just_pressed("jump")) and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_buffered = false

	var input_dir := _move_vector()
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var want_sprint := (
		Input.is_action_pressed("sprint")
		and direction != Vector3.ZERO
		and not locked
		and not is_crouching
		and not dragging
	)
	var sprinting := false
	if want_sprint and combat:
		if combat.is_charging:
			combat.cancel_charge()
			_hatchet_charge_armed = false
		# try_sprint_drain also drops a held goad shaft block.
		sprinting = combat.try_sprint_drain(delta)
	elif want_sprint and combat == null:
		sprinting = true
	_sprinting = sprinting

	var target_speed := WALK_SPEED
	if dragging_body != null and is_instance_valid(dragging_body):
		target_speed = DRAG_SPEED * (0.55 if drag_stamina_exhausted else 1.0)
		sprinting = false
		_sprinting = false
	elif is_crouching:
		target_speed = CROUCH_SPEED
	elif sprinting:
		target_speed = SPRINT_SPEED
	if locked:
		target_speed = 0.0
		direction = Vector3.ZERO
	elif charging_move:
		if _charge_step_left > 0.0:
			target_speed = CHARGE_STEP_SPEED
			direction = _charge_step_dir
		else:
			target_speed = WALK_SPEED * 0.28  # light drift; tap WASD for a step

	var target_vel := direction * target_speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if direction != Vector3.ZERO:
		horiz = horiz.move_toward(target_vel, ACCEL * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if combat:
		var kb: Vector3 = combat.consume_knockback()
		velocity += kb

	move_and_slide()
	_update_noise(horiz.length(), sprinting)
	_update_drag_stamina(delta)
	if not is_mounted:
		_expire_hurt_react_if_tween_died()
		_tick_locomotion(delta, horiz.length(), sprinting, locked)
		_tick_shaft_block()
		_sync_weapon_to_hand()


func _process(_delta: float) -> void:
	# CombatSystem charge pose runs in _process; re-glue hatchet to the posed arm after it.
	if is_mounted:
		return
	if combat and combat.is_charging and not combat.is_attacking:
		_sync_weapon_to_hand()


func _tick_locomotion(delta: float, horiz_speed: float, sprinting: bool, locked: bool) -> void:
	if locomotion == null:
		return
	# Charge and a strike plant the feet. A guard does not: walking keeps the
	# walk cycle on the legs while the arms and the shaft stay in the seat.
	var guard_step := _guard_wants_steps(horiz_speed)
	if guard_step:
		locomotion.release_attack_lock()
		_forget_guard_legs()
	var attacking := combat != null and (
		combat.is_attacking
		or combat.is_charging
		or _hurt_reacting
		or (combat.is_shaft_blocking and not guard_step)
	)
	var local_dir := Vector3.ZERO
	var input_dir := _move_vector()
	if not locked:
		local_dir = Vector3(input_dir.x, 0.0, input_dir.y)
	locomotion.tick(delta, horiz_speed, sprinting, is_crouching, attacking, local_dir)
	# Idle ready-hold when standing (not charging / swinging).
	if (
		combat
		and not combat.is_charging
		and not combat.is_attacking
		and not combat.is_shaft_blocking
		and not _hurt_reacting
		and horiz_speed < 0.25
		and not is_mounted
		and not _goad_swing_held
	):
		_apply_weapon_idle_pose()
	elif (
		combat
		and not combat.is_attacking
		and not combat.is_charging
		and not combat.is_shaft_blocking
		and not _hurt_reacting
		and combat.current_weapon != CombatSystem.Weapon.HATCHET
		and horiz_speed >= 0.25
	):
		# Drop full-body tool additives so the walk cycle can move the legs.
		_tool_pose_active = false
		_goad_swing_held = false
		if locomotion.has_combat_additive("left_thigh") or locomotion.has_combat_additive("hips"):
			locomotion.clear_combat_additives()


func _tick_shaft_block() -> void:
	## Goad out: look is the guard. No held button. Sprint and attacks drop it.
	## Not a parry — the face stays up for as long as he is still looking.
	if combat == null:
		return
	if _hurt_reacting:
		# The flinch owns the body. Remember the look, but do not raise the shaft.
		var face := _resolve_shaft_guard_face()
		if combat.is_shaft_blocking:
			combat.set_shaft_block(false)
		combat.set_shaft_guard_face(face)
		return
	var want := (
		combat.current_weapon == CombatSystem.Weapon.GOAD
		and not _sprinting
		and not combat.is_attacking
		and not combat.is_charging
		and not combat.is_dead
		and not is_mounted
		and not is_dragging()
	)
	combat.set_shaft_block(want)
	if combat.is_shaft_blocking:
		combat.set_shaft_guard_face(_resolve_shaft_guard_face())
		_apply_shaft_block_pose()
		_shaft_pose_applied = true
	elif _shaft_pose_applied:
		_shaft_pose_applied = false
		if not combat.is_attacking and not combat.is_charging:
			if combat.current_weapon == CombatSystem.Weapon.GOAD:
				_release_guard_to_idle()
			else:
				_clear_attack_additives()


func _apply_shaft_block_pose() -> void:
	if locomotion == null:
		return
	_goad_swing_held = false
	var stepping := _guard_wants_steps(Vector2(velocity.x, velocity.z).length())
	if stepping:
		locomotion.release_attack_lock()
	else:
		locomotion.lock_attack(0.12)
	var face: StringName = &"chest"
	if combat:
		face = combat.shaft_guard_face
	# The draw owns the body until the shaft is in the hands.
	if _goad_draw_u < 0.999:
		if _arm_tween and _arm_tween.is_valid():
			_arm_tween.kill()
		_guard_blend_active = false
		_apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
		_replay_guard_walk_legs()
		return
	if _guard_blend_active and face == _guard_face_held:
		_replay_guard_walk_legs()
		return
	if not _guard_blend_active and face == _guard_face_held:
		_apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
		_replay_guard_walk_legs()
		return
	var target: Dictionary = ToolStrikePoses.tool_shaft_guard_pose(face)
	var start: Dictionary = _current_tool_pose(target)
	_guard_face_held = face
	_begin_guard_blend(start, target)
	_replay_guard_walk_legs()


func _release_guard_to_idle() -> void:
	## Dropping the guard travels back to the ready pose. Not a bind-pose snap.
	if combat == null or locomotion == null:
		_clear_attack_additives()
		return
	var idle: Dictionary = ToolStrikePoses.tool_idle_pose(combat.current_weapon)
	var start: Dictionary = _current_tool_pose(idle)
	_guard_face_held = &""
	_begin_guard_blend(start, idle)


func _begin_guard_blend(start_pose: Dictionary, target_pose: Dictionary) -> void:
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_guard_blend_active = false
	_shaft_xf_blend = false
	_guard_from_pose = start_pose
	_guard_to_pose = target_pose
	# The stick that is already showing, not a reseat of the start pose.
	_guard_from_xf = weapon_visual.global_transform if weapon_visual else Transform3D.IDENTITY
	_guard_to_xf = _peek_shaft_xf(target_pose)
	_guard_blend_u = 0.0
	_guard_blend_active = true
	_apply_blended_pose(start_pose, target_pose, 0.0, true)
	_arm_tween = create_tween()
	_arm_tween.tween_method(_step_guard_blend, 0.0, 1.0, GUARD_BLEND_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_callback(_finish_guard_blend)


func _step_guard_blend(t: float) -> void:
	_guard_blend_u = clampf(t, 0.0, 1.0)
	_apply_blended_pose(_guard_from_pose, _guard_to_pose, _guard_blend_u, true)
	_replay_guard_walk_legs()


func _guard_wants_steps(horiz_speed: float) -> bool:
	## Walking in a guard steps. A charge, a swing, and standing still do not.
	if combat == null or locomotion == null or not combat.is_shaft_blocking:
		return false
	if combat.is_attacking or combat.is_charging or _hurt_reacting or _sprinting:
		return false
	return horiz_speed > 0.22


func _forget_guard_legs() -> void:
	for joint in ["left_thigh", "left_shin", "right_thigh", "right_shin"]:
		locomotion.forget_combat_additive(joint)


func _replay_guard_walk_legs() -> void:
	## The guard pose just wrote the planted legs. Put the walk cycle back
	## on those four joints without touching the seat on the arms or the shaft.
	var speed := Vector2(velocity.x, velocity.z).length()
	if not _guard_wants_steps(speed):
		return
	locomotion.release_attack_lock()
	_forget_guard_legs()
	var input := _move_vector()
	locomotion.tick(0.0, speed, false, is_crouching, false, Vector3(input.x, 0.0, input.y))


func _finish_guard_blend() -> void:
	_guard_blend_active = false
	_guard_blend_u = 1.0


func _peek_shaft_xf(pose: Dictionary) -> Transform3D:
	## Where this pose seats the stick, without leaving that pose on screen.
	if weapon_visual == null or locomotion == null:
		return Transform3D.IDENTITY
	var saved_xf := weapon_visual.global_transform
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	var saved_goad_pos := goad.position if goad else Vector3.ZERO
	var saved_goad_rot := goad.rotation if goad else Vector3.ZERO
	var saved_drop := _tool_root_drop
	var saved_euler := _tool_weapon_euler
	var saved_slide := _goad_grip_slide
	var saved_pose := _current_tool_pose(pose)
	var was_guard := _guard_blend_active
	var was_shaft := _shaft_xf_blend
	_guard_blend_active = false
	_shaft_xf_blend = false
	_apply_tool_pose(pose)
	var xf := weapon_visual.global_transform
	_guard_blend_active = was_guard
	_shaft_xf_blend = was_shaft
	_tool_root_drop = saved_drop
	locomotion.set_root_drop(saved_drop)
	_tool_weapon_euler = saved_euler
	_goad_grip_slide = saved_slide
	for k in saved_pose.keys():
		var key := String(k)
		if key == "weapon" or key == "root_drop" or key == "grip_slide":
			continue
		locomotion.set_combat_additive(key, saved_pose[k])
	weapon_visual.global_transform = saved_xf
	if goad:
		goad.position = saved_goad_pos
		goad.rotation = saved_goad_rot
	return xf


func _guard_line(xf: Transform3D, slide: float) -> PackedVector3Array:
	## Wood ends in world space. slide is the goad grip offset on this hold.
	var butt := xf * Vector3(0.0, -0.255 - slide, 0.0)
	var tip := xf * Vector3(0.0, 1.045 - slide, 0.0)
	return PackedVector3Array([butt, tip])


func _guard_shaft_beside(from_xf: Transform3D, to_xf: Transform3D, u: float) -> Transform3D:
	## Side guards are both vertical, so a quaternion slerp flips the shaft
	## up behind the skull. Lerp the wood ends, then carry that line around
	## the face side of the head. Ends are the captured seats.
	if u <= 0.001:
		return from_xf
	if u >= 0.999:
		return to_xf
	if locomotion == null:
		return from_xf.interpolate_with(to_xf, u)
	var head := locomotion.get_joint("head") as Node3D
	if head == null:
		return from_xf.interpolate_with(to_xf, u)
	var from_slide := float(_guard_from_pose.get("grip_slide", 0.0))
	var to_slide := float(_guard_to_pose.get("grip_slide", 0.0))
	var slide := lerpf(from_slide, to_slide, u)
	var from_line := _guard_line(from_xf, from_slide)
	var to_line := _guard_line(to_xf, to_slide)
	var butt := from_line[0].lerp(to_line[0], u)
	var tip := from_line[1].lerp(to_line[1], u)
	var from_anchor: Vector3 = head.to_local(from_line[0].lerp(from_line[1], 0.55))
	var to_anchor: Vector3 = head.to_local(to_line[0].lerp(to_line[1], 0.55))
	var anchor := butt.lerp(tip, 0.55)
	var anchor_l: Vector3 = head.to_local(anchor)
	var from_ang := atan2(from_anchor.z, from_anchor.x)
	var to_ang := atan2(to_anchor.z, to_anchor.x)
	var sweep := _guard_face_sweep(from_ang, to_ang)
	# Stay beside the ear through the middle of the blend. The cross
	# in front of the cheeks is the late part, not the shortest flip.
	var arc_u := pow(u, 1.75)
	var ang := from_ang + sweep * arc_u
	var from_r := Vector2(from_anchor.x, from_anchor.z).length()
	var to_r := Vector2(to_anchor.x, to_anchor.z).length()
	var radius := maxf(lerpf(from_r, to_r, u), 0.38)
	var desired := Vector3(cos(ang) * radius, lerpf(from_anchor.y, to_anchor.y, u), sin(ang) * radius)
	var delta: Vector3 = head.global_transform.basis * (desired - anchor_l)
	butt += delta
	tip += delta
	var axis := tip - butt
	if axis.length_squared() < 0.0001:
		return from_xf.interpolate_with(to_xf, u)
	axis = axis.normalized()
	var origin := butt - axis * (-0.255 - slide)
	var carry := from_xf.interpolate_with(to_xf, u)
	var x := carry.basis.x
	x = x - axis * x.dot(axis)
	if x.length_squared() < 0.0001:
		x = carry.basis.z.cross(axis)
	x = x.normalized()
	var z := x.cross(axis).normalized()
	return Transform3D(Basis(x, axis, z), origin)


func _guard_face_sweep(from_ang: float, to_ang: float) -> float:
	## Head-local atan2(z, x). Negative Z is the face. Pick the arc whose
	## middle is in front of the cheeks, not the one behind the hair.
	var short := wrapf(to_ang - from_ang, -PI, PI)
	var long := short - TAU if short > 0.0 else short + TAU
	var mid_short := from_ang + short * 0.5
	var mid_long := from_ang + long * 0.5
	if sin(mid_long) < sin(mid_short):
		return long
	return short


func _plant_shaft_between(from_xf: Transform3D, to_xf: Transform3D, u: float) -> void:
	## Shaft rides between two holds. Hands stay on it. A sample that would
	## meet the skull bows out, the same way the stow does. End poses are the
	## captured seats, not a new one.
	if weapon_visual == null:
		return
	var along := clampf(u, 0.0, 1.0)
	if _guard_blend_active:
		weapon_visual.global_transform = _guard_shaft_beside(from_xf, to_xf, along)
	else:
		weapon_visual.global_transform = from_xf.interpolate_with(to_xf, along)
	var shaft: Node3D = weapon_visual
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	if goad:
		# Bow writes a global nudge. Reset it so the next frame does not stack.
		goad.position = Vector3(0.0, -_goad_grip_slide, 0.0)
		goad.rotation = Vector3.ZERO
		shaft = goad
	_bow_stow_off_the_head(shaft)
	if _swing_arc_live and _swing_arc_interior:
		# Face side, not the cloak. The sideways stow push leaves a
		# horizontal shaft through the skull. This one walks it clear.
		_bow_swing_off_the_chest(shaft)
		_pull_shaft_into_reach(shaft)
		_bow_swing_clear_of_body(shaft)
	_grip_shaft_with(shaft, "right_arm", "right_forearm", 0.30)
	_grip_shaft_with(shaft, "left_arm", "left_forearm", 0.24)


## Look picks the guard face. No button. Horizontal look wins over vertical.
## Camera pitch counts as up/down when the mouse offset is quiet.
##   look left  → left    look right → right
##   look up    → high    look down  → low (guard only, not a jab)
##   centered   → chest
func _resolve_shaft_guard_face() -> StringName:
	var mx := _tool_aim_delta.x
	var my := _tool_aim_delta.y
	var pitch_up := pivot != null and pivot.rotation.x <= deg_to_rad(-10.0)
	var pitch_down := pivot != null and pivot.rotation.x >= deg_to_rad(12.0)
	if absf(mx) >= TOOL_AIM_SIDE and absf(mx) >= absf(my) * 0.85:
		if mx < 0.0:
			return &"left"
		return &"right"
	var down_bias := 12.0 if pitch_down else 0.0
	if (my >= TOOL_AIM_VERT or pitch_down) and absf(my) + down_bias >= absf(mx) * 0.75:
		return &"low"
	var up_bias := 12.0 if pitch_up else 0.0
	if (my <= -TOOL_AIM_VERT or pitch_up) and absf(my) + up_bias >= absf(mx) * 0.75:
		return &"high"
	return &"chest"


func _apply_crouch_visual(delta: float) -> void:
	var target := 1.0 if is_crouching else 0.0
	_crouch_blend = move_toward(_crouch_blend, target, CROUCH_LERP * delta)
	var h := lerpf(STAND_CAPSULE_HEIGHT, CROUCH_CAPSULE_HEIGHT, _crouch_blend)
	var cy := lerpf(STAND_CAPSULE_Y, CROUCH_CAPSULE_Y, _crouch_blend)
	if _capsule_shape:
		_capsule_shape.height = h
	if collision_shape:
		collision_shape.position.y = cy
	if _hurt_shape:
		_hurt_shape.height = h + 0.05
	if hurtbox_shape:
		hurtbox_shape.position.y = cy
	if pivot:
		pivot.position.y = lerpf(STAND_PIVOT_Y, CROUCH_PIVOT_Y, _crouch_blend)
	if visual:
		visual.position.y = lerpf(STAND_VISUAL_Y, CROUCH_VISUAL_Y, _crouch_blend)
	if weapon_visual:
		weapon_visual.position.y = lerpf(_weapon_base_y, _weapon_base_y + CROUCH_VISUAL_Y, _crouch_blend)


func _update_noise(speed: float, sprinting: bool) -> void:
	# Footprint for DetectionSensor hearing. Still = silent; crouch walk quiet; sprint loud.
	if speed < 0.15:
		_noise_level = 0.0
	elif dragging_body != null and is_instance_valid(dragging_body):
		_noise_level = 0.4 + clampf(speed / DRAG_SPEED, 0.0, 1.0) * 0.25
	elif is_crouching:
		_noise_level = 0.18 + clampf(speed / CROUCH_SPEED, 0.0, 1.0) * 0.22
	elif sprinting:
		_noise_level = 0.85 + clampf(speed / SPRINT_SPEED, 0.0, 1.0) * 0.15
	else:
		_noise_level = 0.45 + clampf(speed / WALK_SPEED, 0.0, 1.0) * 0.25


## Used by DetectionSensor LOS aim (chest/head height).
func get_visibility_point() -> Vector3:
	var height := lerpf(1.45, 0.72, _crouch_blend)
	return global_position + Vector3(0.0, height, 0.0)


func get_noise_level() -> float:
	return _noise_level


## Visual silhouette factor: crouch is harder to spot at range.
func get_visibility_factor() -> float:
	return lerpf(1.0, 0.55, _crouch_blend)


func _move_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		v.y -= 1.0
	if Input.is_action_pressed("move_back"):
		v.y += 1.0
	if Input.is_action_pressed("move_left"):
		v.x -= 1.0
	if Input.is_action_pressed("move_right"):
		v.x += 1.0
	return v.normalized()


func _begin_hatchet_or_light() -> void:
	if combat == null:
		return
	var hatchet := combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet
	var goad := combat.current_weapon == CombatSystem.Weapon.GOAD
	# Already looking down: one uncharged jab. Do not start a shaft charge.
	if goad and _resolve_shaft_guard_face() == &"low":
		_fire_goad_jab()
		return
	if hatchet or goad:
		# Goad keeps the look you already had; hatchet aim starts neutral (top).
		_charge_aim_delta = _tool_aim_delta if goad else Vector2.ZERO
		_hatchet_charge_armed = true
		if not combat.begin_charge():
			_hatchet_charge_armed = false
			var fallback := _resolve_tool_strike_direction() if goad else CombatSystem.StrikeDirection.TOP
			combat.try_attack(&"light", fallback)
		else:
			_apply_charge_direction_from_input()
	else:
		combat.try_attack(&"light", _resolve_tool_strike_direction())
		_tool_aim_delta = Vector2.ZERO


func _release_hatchet_or_ignore() -> void:
	if combat == null:
		return
	if not _hatchet_charge_armed and not combat.is_charging:
		return
	_hatchet_charge_armed = false
	if combat.is_charging:
		_apply_charge_direction_from_input()
		combat.release_charged_attack()


func _heavy_or_ignore_hatchet() -> void:
	if combat == null:
		return
	# Hatchet: hold-release only — RMB does not instant full-power.
	if combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet:
		return
	# Goad RMB is the same uncharged point jab at any look. Not a heavy swing.
	if combat.current_weapon == CombatSystem.Weapon.GOAD:
		_fire_goad_jab()
		return
	if combat.is_charging:
		combat.cancel_charge()
		_hatchet_charge_armed = false
	combat.try_attack(&"heavy", _resolve_tool_strike_direction())
	_tool_aim_delta = Vector2.ZERO


func _fire_goad_jab() -> void:
	## One uncharged point. Press only — the caller is an action press, so a
	## held button does not charge or repeat. Look is left alone so the low
	## guard can return after the jab.
	if combat == null or combat.current_weapon != CombatSystem.Weapon.GOAD:
		return
	if combat.is_charging:
		combat.cancel_charge()
		_hatchet_charge_armed = false
	combat.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM)


func _resolve_tool_strike_direction() -> CombatSystem.StrikeDirection:
	## Knife tap, and the goad fallback if a charge cannot start.
	## Look-down is not a strike direction here — that click is the jab.
	## Knife top is a thrust. Knife and hatchet have no bottom.
	var mx := _tool_aim_delta.x
	var my := _tool_aim_delta.y
	if absf(mx) >= TOOL_AIM_SIDE and absf(mx) >= absf(my) * 0.85:
		if mx < 0.0:
			return CombatSystem.StrikeDirection.LEFT
		return CombatSystem.StrikeDirection.RIGHT
	return CombatSystem.StrikeDirection.TOP


func _apply_charge_direction_from_input() -> void:
	if combat == null or not combat.is_charging:
		return
	combat.set_charge_direction(_resolve_strike_direction())


func _resolve_strike_direction() -> CombatSystem.StrikeDirection:
	## Mouse aim while a shaft is charging. Left/right/up, including diagonals.
	## Look-down is not a shaft direction. Hatchet never stabs.
	var mx := _charge_aim_delta.x
	var my := _charge_aim_delta.y
	var pitch_up := pivot != null and pivot.rotation.x <= deg_to_rad(-10.0)

	if absf(mx) >= CHARGE_AIM_SIDE_THRESH and absf(mx) >= absf(my) * 0.9:
		if mx < 0.0:
			return CombatSystem.StrikeDirection.LEFT
		return CombatSystem.StrikeDirection.RIGHT

	if my <= -CHARGE_AIM_TOP_THRESH or pitch_up:
		return CombatSystem.StrikeDirection.TOP
	return CombatSystem.StrikeDirection.TOP


func _on_charge_updated(ratio: float, direction: StringName) -> void:
	## Goad: whole-body windup. Hatchet: arm + torso cock (unchanged).
	if combat == null or not combat.is_charging or combat.is_attacking:
		return
	if combat.current_weapon == CombatSystem.Weapon.GOAD:
		_apply_goad_charge_pose(ratio, direction)
		return
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	var dir_enum := CombatSystem.StrikeDirection.TOP
	match direction:
		&"left":
			dir_enum = CombatSystem.StrikeDirection.LEFT
		&"right":
			dir_enum = CombatSystem.StrikeDirection.RIGHT
		_:
			dir_enum = CombatSystem.StrikeDirection.TOP
	var pose: Dictionary = CombatSystem.hatchet_charge_arm_pose(dir_enum, ratio)
	_arm_fore_scale = float(pose.get("fore_scale", 0.4))
	_apply_arm_additive(pose["right_arm"] as Vector3)
	# Forearm uses explicit pose (not only scale-from-arm) for a clearer cock.
	if locomotion:
		locomotion.set_combat_additive("right_forearm", pose["right_forearm"] as Vector3)
	_apply_torso_additive(pose["torso"] as Vector3)
	if locomotion:
		locomotion.lock_attack(0.05)


func _apply_goad_charge_pose(ratio: float, _direction: StringName) -> void:
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_guard_blend_active = false
	# Cardinal direction still picks the strike on release. The body tracks
	# the mouse continuously so the weapon is already on that side.
	var aim := _shaft_aim_axes()
	var full: Dictionary = ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, 1.0)
	if not _charge_from_ready:
		_charge_from_pose = _current_tool_pose(full)
		_charge_from_xf = weapon_visual.global_transform if weapon_visual else Transform3D.IDENTITY
		_charge_from_ready = true
		_guard_face_held = &""
	var blend := ToolStrikePoses._charge_blend(ratio)
	_shaft_from_xf = _charge_from_xf
	_shaft_to_xf = _peek_shaft_xf(full)
	# Top hold is a bar over the head in the committed pose. The authored
	# cock reads as the right chamber. Left and right charges keep the peek.
	# Measure after the body is in that pose, or the bar is built on the old head.
	if _is_top_goad_charge(aim):
		_apply_tool_pose(full)
		_shaft_to_xf = _overhead_charge_xf()
	_shaft_xf_u = blend
	_shaft_xf_blend = true
	_apply_blended_pose(_charge_from_pose, full, blend, false)
	_shaft_xf_blend = false
	if locomotion:
		locomotion.lock_attack(0.08)


func _is_top_goad_charge(aim: Vector2) -> bool:
	## Overhead only. A side aim, including a diagonal, keeps its own chamber.
	return absf(aim.x) < 0.35 and aim.y <= 0.05


func _overhead_charge_xf() -> Transform3D:
	## Full top charge. The wood is a bar over the skull, off the face,
	## so a strike from above meets the shaft. Not the right-side cock.
	if weapon_visual == null or locomotion == null:
		return Transform3D.IDENTITY
	var head := locomotion.get_joint("head") as Node3D
	if head == null:
		return weapon_visual.global_transform
	# Measured from the shoulders in world up, not along the head. Straight
	# arms reach ~0.55; this bar sits near that limit over the skull.
	var r_arm := locomotion.get_joint("right_arm") as Node3D
	var l_arm := locomotion.get_joint("left_arm") as Node3D
	if r_arm == null or l_arm == null:
		return weapon_visual.global_transform
	var face := -global_transform.basis.z
	face.y = 0.0
	face = face.normalized() if face.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	var side := global_transform.basis.x
	side.y = 0.0
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3(1.0, 0.0, 0.0)
	var mid := r_arm.global_position.lerp(l_arm.global_position, 0.5)
	var bar := mid + Vector3.UP * 0.56 + face * 0.08
	# Never closer than a hand over the skull.
	var crown_clear := head.global_position.y + 0.36
	if bar.y < crown_clear:
		bar.y = crown_clear
	var right_pt := bar + side * 0.20
	var left_pt := bar - side * 0.20
	var axis := left_pt - right_pt
	if axis.length_squared() < 0.0001:
		return weapon_visual.global_transform
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	var saved_xf := weapon_visual.global_transform
	var saved_pos := goad.position if goad else Vector3.ZERO
	var saved_rot := goad.rotation if goad else Vector3.ZERO
	weapon_visual.global_position = right_pt
	ToolStrikePoses._aim_weapon_y(weapon_visual, axis.normalized())
	if goad:
		goad.position = Vector3.ZERO
		goad.rotation = Vector3.ZERO
	var xf := weapon_visual.global_transform
	weapon_visual.global_transform = saved_xf
	if goad:
		goad.position = saved_pos
		goad.rotation = saved_rot
	return xf


func _shaft_aim_axes() -> Vector2:
	## Shaft charge/swing only. Look-down is clamped off so the hold cannot
	## chamber a jab. High-left and the other up diagonals still track.
	var aim := _goad_aim_axes()
	aim.y = minf(aim.y, 0.0)
	return aim


func _goad_aim_axes() -> Vector2:
	## -1 left / +1 right, -1 up / +1 down.
	## Camera pitch counts when the mouse offset is quiet, same as the guard.
	var ax := clampf(_charge_aim_delta.x / GOAD_AIM_SPAN, -1.0, 1.0)
	var ay := clampf(_charge_aim_delta.y / GOAD_AIM_SPAN, -1.0, 1.0)
	if pivot:
		var pitch_n := clampf(pivot.rotation.x / deg_to_rad(18.0), -1.0, 1.0)
		if pitch_n > 0.0:
			ay = maxf(ay, pitch_n)
		else:
			ay = minf(ay, pitch_n)
	return Vector2(ax, ay)


func _on_charge_cancelled(_weapon: StringName) -> void:
	_charge_from_ready = false
	if combat and combat.is_attacking:
		return
	# The live pose is still the charge. The guard tick blends back from it.
	if combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
		_guard_face_held = &""
		_guard_blend_active = false
		return
	_clear_attack_additives()
	# Snap back toward idle ready if hatchet still drawn.
	if combat and combat.current_weapon == CombatSystem.Weapon.HATCHET:
		_apply_idle_hatchet_hold()


func _apply_idle_hatchet_hold() -> void:
	if locomotion == null:
		return
	if _arm_tween and _arm_tween.is_valid():
		return  # swing owns the arm
	var pose: Dictionary = CombatSystem.hatchet_idle_arm_pose()
	_arm_fore_scale = 0.3
	locomotion.set_combat_additive("right_arm", pose["right_arm"] as Vector3)
	locomotion.set_combat_additive("right_forearm", pose["right_forearm"] as Vector3)
	locomotion.set_combat_additive("torso", pose["torso"] as Vector3)


func _on_weapon_changed(weapon: StringName) -> void:
	_tool_pose_active = false
	# Unarmed stow keeps the goad idle so the hands can carry it back.
	# Clearing here would drop the arms for a frame before the ease.
	var stow_unarmed := weapon == &"unarmed" and _goad_draw_u > 0.01
	if locomotion and not stow_unarmed:
		locomotion.clear_combat_additives()
	_begin_goad_travel(weapon == &"goad")
	_sync_back_goad_visibility()
	if locomotion:
		_apply_weapon_idle_pose()
	# Hide belt knife mesh when knife is drawn as active weapon.
	if locomotion == null:
		return
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node == null:
		return
	var belt_knife := visual_node.find_child("BeltKnife", true, false) as Node3D
	if belt_knife:
		# On the hip whenever the knife is not in the hand.
		belt_knife.visible = weapon != &"knife"


func _sync_back_goad_visibility() -> void:
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node == null or combat == null:
		return
	var back_goad := visual_node.find_child("BackGoad", true, false) as Node3D
	if back_goad:
		# One mesh. The back copy is hidden for the whole draw, including the first step off the seat.
		back_goad.visible = combat.current_weapon != CombatSystem.Weapon.GOAD and not _goad_draw_tween_running_to_hands()
		if combat.current_weapon != CombatSystem.Weapon.GOAD and _goad_stowing:
			back_goad.visible = true


func _on_attack_performed(_attacker: Node, kind: StringName, weapon: StringName) -> void:
	# Goad/knife: whole-body weight shift. Hatchet keeps the arm/torso chop below.
	if weapon != &"hatchet":
		_play_tool_body_strike(kind, weapon)
		return
	# Body + arm follow weapon swing phases; timings match CombatSystem (post dir scale).
	if combat == null:
		return
	var timings: Dictionary = combat.last_attack_timings()
	var windup: float = float(timings.get("windup", 0.16))
	var active: float = float(timings.get("active", 0.12))
	var recovery: float = float(timings.get("recovery", 0.34))
	var heavy := kind == &"heavy"
	if locomotion:
		locomotion.lock_attack(windup + active + recovery)

	if right_arm == null and locomotion:
		right_arm = locomotion.get_right_arm()
	if right_arm == null:
		return

	var direction := CombatSystem.StrikeDirection.TOP
	if combat:
		direction = combat.last_strike_direction()

	# Stronger readable arcs than the old capsule slice.
	var windup_delta := Vector3(deg_to_rad(-55.0 if heavy else -32.0), deg_to_rad(-15.0 if heavy else -8.0), deg_to_rad(-25.0 if heavy else -14.0))
	var contact_delta := Vector3(deg_to_rad(25.0 if heavy else 12.0), deg_to_rad(10.0), deg_to_rad(35.0 if heavy else 22.0))
	var follow_delta := Vector3(deg_to_rad(55.0 if heavy else 35.0), deg_to_rad(18.0), deg_to_rad(50.0 if heavy else 32.0))
	var torso_windup := Vector3(deg_to_rad(-8.0 if heavy else -4.0), deg_to_rad(-12.0 if heavy else -6.0), 0.0)
	var torso_contact := Vector3(deg_to_rad(10.0 if heavy else 5.0), deg_to_rad(8.0 if heavy else 4.0), 0.0)
	var torso_follow := Vector3(deg_to_rad(14.0 if heavy else 8.0), deg_to_rad(12.0 if heavy else 6.0), 0.0)

	if weapon == &"hatchet":
		match direction:
			CombatSystem.StrikeDirection.LEFT:
				windup_delta = Vector3(deg_to_rad(-42.0 if heavy else -24.0), deg_to_rad(48.0 if heavy else 30.0), deg_to_rad(-55.0 if heavy else -34.0))
				contact_delta = Vector3(deg_to_rad(20.0 if heavy else 12.0), deg_to_rad(-28.0), deg_to_rad(34.0 if heavy else 22.0))
				follow_delta = Vector3(deg_to_rad(34.0 if heavy else 20.0), deg_to_rad(-58.0), deg_to_rad(50.0 if heavy else 32.0))
				torso_windup = Vector3(deg_to_rad(-6.0), deg_to_rad(24.0 if heavy else 14.0), 0.0)
				torso_contact = Vector3(deg_to_rad(8.0), deg_to_rad(-14.0 if heavy else -8.0), 0.0)
				torso_follow = Vector3(deg_to_rad(10.0), deg_to_rad(-22.0 if heavy else -14.0), 0.0)
			CombatSystem.StrikeDirection.RIGHT:
				windup_delta = Vector3(deg_to_rad(-48.0 if heavy else -26.0), deg_to_rad(-55.0 if heavy else -34.0), deg_to_rad(28.0 if heavy else 16.0))
				contact_delta = Vector3(deg_to_rad(20.0 if heavy else 12.0), deg_to_rad(34.0), deg_to_rad(-22.0 if heavy else -12.0))
				follow_delta = Vector3(deg_to_rad(34.0 if heavy else 20.0), deg_to_rad(62.0), deg_to_rad(-34.0 if heavy else -20.0))
				torso_windup = Vector3(deg_to_rad(-6.0), deg_to_rad(-26.0 if heavy else -16.0), 0.0)
				torso_contact = Vector3(deg_to_rad(8.0), deg_to_rad(16.0 if heavy else 10.0), 0.0)
				torso_follow = Vector3(deg_to_rad(10.0), deg_to_rad(24.0 if heavy else 14.0), 0.0)
			_:
				# TOP overhead — higher cock, steeper drop (readable arc on greybox kerne).
				windup_delta = Vector3(deg_to_rad(-95.0 if heavy else -58.0), deg_to_rad(-10.0), deg_to_rad(-22.0 if heavy else -14.0))
				contact_delta = Vector3(deg_to_rad(48.0 if heavy else 28.0), deg_to_rad(6.0), deg_to_rad(32.0 if heavy else 20.0))
				follow_delta = Vector3(deg_to_rad(88.0 if heavy else 55.0), deg_to_rad(12.0), deg_to_rad(42.0 if heavy else 28.0))
				torso_windup = Vector3(deg_to_rad(-18.0 if heavy else -10.0), deg_to_rad(-8.0), 0.0)
				torso_contact = Vector3(deg_to_rad(20.0 if heavy else 12.0), deg_to_rad(5.0), 0.0)
				torso_follow = Vector3(deg_to_rad(28.0 if heavy else 16.0), deg_to_rad(8.0), 0.0)

	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()

	var phases: Dictionary = combat.swing_phase_durations(kind, windup, active, recovery)
	var windup_move: float = phases["windup_move"]
	var windup_hold: float = phases["windup_hold"]
	var to_contact: float = phases["to_contact"]
	var contact_hold: float = phases["contact_hold"]
	var follow_dur: float = phases["follow"]

	_arm_fore_scale = 0.35
	# Start from current charge cock (or a light pre-windup) so release feels continuous.
	var arm_from := windup_delta * 0.55
	if locomotion and locomotion.has_combat_additive("right_arm"):
		arm_from = locomotion.get_combat_additive("right_arm")
	_arm_tween = create_tween()
	_arm_tween.tween_method(_apply_arm_additive, arm_from, windup_delta, windup_move).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if windup_hold > 0.0:
		_arm_tween.tween_interval(windup_hold)
	_arm_tween.tween_callback(func() -> void: _arm_fore_scale = 0.45)
	_arm_tween.tween_method(_apply_arm_additive, windup_delta, contact_delta, to_contact).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if contact_hold > 0.0:
		_arm_tween.tween_interval(contact_hold)
	_arm_tween.tween_callback(func() -> void: _arm_fore_scale = 0.5)
	_arm_tween.tween_method(_apply_arm_additive, contact_delta, follow_delta, follow_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_callback(func() -> void: _arm_fore_scale = 0.25)
	_arm_tween.tween_method(_apply_arm_additive, follow_delta, Vector3.ZERO, recovery).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_callback(_clear_attack_additives)

	_torso_tween = create_tween()
	_torso_tween.tween_method(_apply_torso_additive, torso_windup * 0.2, torso_windup, windup_move).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if windup_hold > 0.0:
		_torso_tween.tween_interval(windup_hold)
	_torso_tween.tween_method(_apply_torso_additive, torso_windup, torso_contact, to_contact).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if contact_hold > 0.0:
		_torso_tween.tween_interval(contact_hold)
	_torso_tween.tween_method(_apply_torso_additive, torso_contact, torso_follow, follow_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_torso_tween.tween_method(_apply_torso_additive, torso_follow, Vector3.ZERO, recovery).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply_arm_additive(v: Vector3) -> void:
	if locomotion == null:
		return
	locomotion.set_combat_additive("right_arm", v)
	locomotion.set_combat_additive("right_forearm", Vector3(v.x * _arm_fore_scale, 0.0, 0.0))


func _apply_torso_additive(v: Vector3) -> void:
	if locomotion:
		locomotion.set_combat_additive("torso", v)


func _clear_attack_additives() -> void:
	_tool_pose_active = false
	_tool_root_drop = 0.0
	_goad_grip_slide = 0.0
	if locomotion:
		locomotion.clear_combat_additives()
	if combat and not combat.is_charging and not combat.is_attacking:
		_apply_weapon_idle_pose()


func _apply_weapon_idle_pose() -> void:
	if combat == null or locomotion == null:
		return
	if combat.is_attacking or combat.is_charging or combat.is_shaft_blocking:
		return
	if _arm_tween and _arm_tween.is_valid():
		return
	if combat.current_weapon == CombatSystem.Weapon.HATCHET:
		_apply_idle_hatchet_hold()
		_sync_weapon_to_hand()
		return
	if combat.current_weapon == CombatSystem.Weapon.UNARMED:
		# Stow is the draw run backward: the same idle eases the hands back
		# with the shaft. Empty hands only once it has seated.
		if _goad_stowing:
			_ease_goad_draw_body()
			_sync_weapon_to_hand()
			return
		_tool_pose_active = false
		_sync_weapon_to_hand()
		return
	# One-hand draw. The right hand takes it off the shoulder. The left hand
	# meets it only once the shaft is off the back. The idle itself is unchanged.
	if combat.current_weapon == CombatSystem.Weapon.GOAD and _goad_draw_u < 0.999:
		_ease_one_hand_draw_body()
		_sync_weapon_to_hand()
		return
	_tool_pose_active = false
	_apply_tool_pose(ToolStrikePoses.tool_idle_pose(combat.current_weapon))
	_tool_pose_active = false
	_sync_weapon_to_hand()


func _play_tool_body_strike(kind: StringName, _weapon: StringName) -> void:
	if combat == null or locomotion == null:
		return
	var timings: Dictionary = combat.last_attack_timings()
	var windup: float = float(timings.get("windup", 0.2))
	var active: float = float(timings.get("active", 0.14))
	var recovery: float = float(timings.get("recovery", 0.3))
	locomotion.lock_attack(windup + active + recovery)
	var heavy := kind == &"heavy"
	var direction := combat.last_strike_direction()
	var weapon_id := combat.current_weapon
	var from_charge := _tool_pose_active and weapon_id == CombatSystem.Weapon.GOAD
	if weapon_id == CombatSystem.Weapon.GOAD:
		_play_goad_release(kind, windup, active, from_charge)
		return
	var commit := 1.0
	if weapon_id == CombatSystem.Weapon.GOAD and not from_charge:
		var power := combat.last_attack_power
		if power >= 0.0:
			# Tap stays small. Full hold commits the whole body. Mid is between.
			commit = lerpf(0.82, 1.5, clampf(power, 0.0, 1.0))
		elif heavy:
			commit = 1.28
	# A held goad is already in the aim pose. Do not scale a different contact
	# over it — that restages the body (the pop). The strike continues the aim.
	var pose_scale_heavy := heavy and not from_charge
	var pose_windup: Dictionary = _scale_tool_pose(ToolStrikePoses.tool_strike_pose(weapon_id, direction, &"windup", pose_scale_heavy), commit)
	var pose_contact: Dictionary = _scale_tool_pose(ToolStrikePoses.tool_strike_pose(weapon_id, direction, &"contact", pose_scale_heavy), commit)
	var pose_follow: Dictionary = _scale_tool_pose(ToolStrikePoses.tool_strike_pose(weapon_id, direction, &"follow", pose_scale_heavy), commit)
	var pose_idle: Dictionary = ToolStrikePoses.tool_idle_pose(weapon_id)
	var phases: Dictionary = combat.swing_phase_durations(kind, windup, active, recovery)
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	# Release continues from the live aim. Heavy hold drives into the strike.
	# A tap still takes the short windup, which is the same side as the aim.
	var start_pose: Dictionary = _current_tool_pose(pose_idle) if from_charge else pose_idle
	if from_charge and heavy:
		# Windup key IS the aim the body is already holding, not a second cock.
		pose_windup = start_pose
	_tool_pose_active = true
	_arm_tween = create_tween()
	if from_charge and heavy:
		var drive := maxf(0.18, float(phases["windup_move"]) * 0.85 + float(phases["to_contact"]))
		_arm_tween.tween_method(_lerp_tool_pose.bind(start_pose, pose_contact), 0.0, 1.0, drive).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		_arm_tween.tween_method(_lerp_tool_pose.bind(start_pose, pose_windup), 0.0, 1.0, phases["windup_move"]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if float(phases["windup_hold"]) > 0.0:
			_arm_tween.tween_interval(float(phases["windup_hold"]))
		_arm_tween.tween_method(_lerp_tool_pose.bind(pose_windup, pose_contact), 0.0, 1.0, phases["to_contact"]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if float(phases["contact_hold"]) > 0.0:
		_arm_tween.tween_interval(float(phases["contact_hold"]))
	_arm_tween.tween_method(_lerp_tool_pose.bind(pose_contact, pose_follow), 0.0, 1.0, phases["follow"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_method(_lerp_tool_pose.bind(pose_follow, pose_idle), 0.0, 1.0, recovery).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_callback(_clear_attack_additives)



func _play_goad_release(kind: StringName, windup: float, active: float, _from_charge: bool) -> void:
	## The swing leaves the pose that is already on screen. Windup, contact,
	## and the return connect. The windup is not a pop onto a stored cock.
	## Settle back to the ready pose is still GOAD_SETTLE_SEC.
	_guard_blend_active = false
	_guard_face_held = &""
	_charge_from_ready = false
	var aim := _shaft_aim_axes()
	# The jab is the point, at any look. It is not the shaft swing he was aiming.
	var jab := combat.last_strike_direction() == CombatSystem.StrikeDirection.BOTTOM
	if jab:
		aim = Vector2(0.0, 1.0)
	_swing_arc_live = not jab
	_swing_arc_aim = aim
	var pose_idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var pose_windup: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"windup")
	var pose_contact: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"contact")
	var pose_follow: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"follow")
	var start_pose: Dictionary = _current_tool_pose(pose_windup)
	var start_xf := weapon_visual.global_transform if weapon_visual else Transform3D.IDENTITY
	var windup_xf := _peek_shaft_xf(pose_windup)
	var contact_xf := _peek_shaft_xf(pose_contact)
	var follow_xf := _peek_shaft_xf(pose_follow)
	var phases: Dictionary = combat.swing_phase_durations(kind, windup, active, GOAD_SETTLE_SEC)
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_tool_pose_active = true
	# The jab still visits its own poses at the table times, holds included.
	# Left, top, and right are one arc. Their cock and contact holds are
	# dropped, and the remaining travel is halved, so the stick arrives as
	# a strike. Settle stays GOAD_SETTLE_SEC.
	var windup_move := float(phases["windup_move"]) + float(phases["windup_hold"])
	var to_contact := float(phases["to_contact"]) + float(phases["contact_hold"])
	var follow_move := float(phases["follow"])
	if jab:
		_goad_swing_held = false
		_arm_tween = create_tween()
		_arm_tween.tween_method(_lerp_goad_shaft.bind(start_pose, pose_windup, start_xf, windup_xf), 0.0, 1.0, windup_move).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_arm_tween.tween_method(_lerp_goad_shaft.bind(pose_windup, pose_contact, windup_xf, contact_xf), 0.0, 1.0, to_contact).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_arm_tween.tween_method(_lerp_goad_shaft.bind(pose_contact, pose_follow, contact_xf, follow_xf), 0.0, 1.0, follow_move).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_arm_tween.tween_method(_slerp_goad_settle.bind(pose_follow, pose_idle), 0.0, 1.0, GOAD_SETTLE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_arm_tween.tween_callback(_finish_goad_return)
		return
	windup_move = float(phases["windup_move"]) * 0.5
	to_contact = float(phases["to_contact"]) * 0.5
	follow_move = float(phases["follow"]) * 0.5
	_arm_continuous_goad_swing(start_pose, pose_follow, windup_move, to_contact, follow_move)



func _arm_continuous_goad_swing(start_pose: Dictionary, follow_pose: Dictionary, windup_move: float, to_contact: float, follow_move: float) -> void:
	## One curve for the whole release. Phase time is unchanged. The settle
	## is the tail of that curve, not a new pose standing up in the face.
	var total := windup_move + to_contact + follow_move + GOAD_SETTLE_SEC
	if total < 0.05:
		total = 0.05
	_swing_strike_u = (windup_move + to_contact) / total
	var follow_u := (windup_move + to_contact + follow_move) / total
	var early_u := maxf(0.08, windup_move / total * 0.75)
	if early_u >= _swing_strike_u:
		early_u = _swing_strike_u * 0.45
	_swing_frame = global_transform
	_swing_start_pose = start_pose
	_swing_follow_pose = follow_pose
	_goad_swing_held = true
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D if weapon_visual else null
	var live_butt := Vector3(0.0, 1.1, -0.4)
	var live_tip := Vector3(0.2, 1.6, -0.7)
	if goad:
		live_butt = _swing_frame.affine_inverse() * goad.to_global(Vector3(0.0, -0.255, 0.0))
		live_tip = _swing_frame.affine_inverse() * goad.to_global(Vector3(0.0, 1.045, 0.0))
	# The guard may sit behind the ear. The swing does not. The first sample
	# is already on the face side, so the lift cannot rise behind the hair.
	var faced: Array = _lift_line_onto_the_face(live_butt, live_tip)
	live_butt = faced[0]
	live_tip = faced[1]
	_swing_keys_butt = PackedVector3Array()
	_swing_keys_tip = PackedVector3Array()
	_swing_key_u = PackedFloat32Array()
	_swing_keys_butt.append(live_butt)
	_swing_keys_tip.append(live_tip)
	_swing_key_u.append(0.0)
	var keys: Array = _continuous_swing_keys(_swing_arc_aim)
	var marks: Array = [early_u, _swing_strike_u, follow_u, 1.0]
	for i in keys.size():
		var pair: Array = keys[i]
		_swing_keys_butt.append(pair[0])
		_swing_keys_tip.append(pair[1])
		_swing_key_u.append(float(marks[i]))
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_method(_sample_continuous_goad_swing, 0.0, 1.0, total)
	_arm_tween.tween_callback(_finish_goad_return)


func _continuous_swing_keys(aim: Vector2) -> Array:
	## Later samples of one face-side arc. The live guard is the first sample.
	## Left sweeps to the player's right, right sweeps to the player's left,
	## top chops straight down from the overhead bar. A diagonal is the blend.
	var w_left := clampf(-aim.x, 0.0, 1.0)
	var w_right := clampf(aim.x, 0.0, 1.0)
	var w_top := clampf(-aim.y, 0.0, 1.0)
	var sum := w_left + w_right + w_top
	if sum < 0.001:
		w_top = 1.0
		sum = 1.0
	w_left /= sum
	w_right /= sum
	w_top /= sum
	var left: Array = [
		_swing_line(Vector3(-0.12, 1.28, -0.55), Vector3(-0.72, 0.45, -0.48)),
		_swing_line(Vector3(-0.02, 1.18, -0.58), Vector3(0.70, 0.02, -0.68)),
		_swing_line(Vector3(0.06, 1.14, -0.52), Vector3(0.58, -0.42, -0.58)),
		_swing_line(Vector3(0.08, 1.16, -0.48), Vector3(0.48, -0.50, -0.55)),
	]
	var right: Array = [
		_swing_line(Vector3(0.18, 1.32, -0.55), Vector3(0.62, 0.48, -0.52)),
		_swing_line(Vector3(0.04, 1.18, -0.58), Vector3(-0.68, 0.02, -0.70)),
		_swing_line(Vector3(-0.02, 1.14, -0.52), Vector3(-0.55, -0.42, -0.60)),
		_swing_line(Vector3(0.00, 1.16, -0.48), Vector3(-0.45, -0.52, -0.58)),
	]
	# Overhead chop. Key 0 is the live bar over the head. These keep the
	# hands high and drop the tip straight down the face side — not the
	# chest-height forward shove the side swings use.
	var top: Array = [
		_swing_line(Vector3(0.00, 1.70, -0.18), Vector3(0.06, 0.10, -0.70)),
		_swing_line(Vector3(0.00, 1.55, -0.32), Vector3(0.02, -0.35, -0.92)),
		_swing_line(Vector3(0.00, 1.38, -0.40), Vector3(0.02, -0.78, -0.62)),
		_swing_line(Vector3(0.00, 1.26, -0.38), Vector3(0.02, -0.96, -0.38)),
	]
	var out: Array = []
	for i in 4:
		var butt: Vector3 = (left[i][0] as Vector3) * w_left + (right[i][0] as Vector3) * w_right + (top[i][0] as Vector3) * w_top
		var tip: Vector3 = (left[i][1] as Vector3) * w_left + (right[i][1] as Vector3) * w_right + (top[i][1] as Vector3) * w_top
		var axis := tip - butt
		if axis.length_squared() < 0.0001:
			axis = Vector3(0.0, 0.2, -1.0)
		tip = butt + axis.normalized() * 1.30
		out.append([butt, tip])
	return out


func _swing_line(butt: Vector3, direction: Vector3) -> Array:
	var axis := direction
	if axis.length_squared() < 0.0001:
		axis = Vector3(0.0, 0.0, -1.0)
	return [butt, butt + axis.normalized() * 1.30]


func _sample_continuous_goad_swing(u: float) -> void:
	var line: Array = _continuous_line_at(clampf(u, 0.0, 1.0))
	var butt_l: Vector3 = line[0]
	var tip_l: Vector3 = line[1]
	# The chest turns with the swing. The wood turns with the chest, or the
	# hands finish a step away from a shaft that stayed in the start frame.
	var yaw := _swing_yaw(u)
	var pivot := Vector3(0.0, 0.92, 0.0)
	var spin := Basis(Vector3.UP, yaw)
	butt_l = pivot + spin * (butt_l - pivot)
	tip_l = pivot + spin * (tip_l - pivot)
	var butt_w: Vector3 = _swing_frame * butt_l
	var tip_w: Vector3 = _swing_frame * tip_l
	_swing_pose_only = true
	_apply_tool_pose(_swing_body_at(u))
	_swing_pose_only = false
	# Top chop starts on the overhead bar. Pull the wood into both palms from
	# the first sample so the tip does not leave the hands on the way down.
	if u > 0.02 or (absf(_swing_arc_aim.x) < 0.35 and _swing_arc_aim.y <= 0.05):
		var held: Array = _bring_shaft_to_both_hands(butt_w, tip_w)
		butt_w = held[0]
		tip_w = held[1]
	var cleared: Array = _slide_line_off_body(butt_w, tip_w)
	butt_w = cleared[0]
	tip_w = cleared[1]
	var goad := _place_continuous_shaft(butt_w, tip_w)
	if goad:
		_grip_shaft_with(goad, "right_arm", "right_forearm", 0.30)
		_grip_shaft_with(goad, "left_arm", "left_forearm", 0.24)


func _continuous_line_at(u: float) -> Array:
	var i := 0
	var last := _swing_key_u.size() - 2
	while i < last and u > _swing_key_u[i + 1]:
		i += 1
	var span := maxf(_swing_key_u[i + 1] - _swing_key_u[i], 0.0001)
	var t := clampf((u - _swing_key_u[i]) / span, 0.0, 1.0)
	# A pure top chop is a straight drop from the overhead bar. The face-side
	# quadratic pulls a high tip forward of the hands and leaves the wood.
	var overhead := absf(_swing_arc_aim.x) < 0.35 and _swing_arc_aim.y <= 0.05
	var butt: Vector3
	var tip: Vector3
	if overhead:
		butt = _swing_keys_butt[i].lerp(_swing_keys_butt[i + 1], t)
		tip = _swing_keys_tip[i].lerp(_swing_keys_tip[i + 1], t)
	else:
		butt = _face_quad(_swing_keys_butt[i], _swing_keys_butt[i + 1], t)
		tip = _face_quad(_swing_keys_tip[i], _swing_keys_tip[i + 1], t)
	var axis := tip - butt
	if axis.length_squared() > 0.0001:
		tip = butt + axis.normalized() * 1.30
	return [butt, tip]


func _face_quad(a: Vector3, b: Vector3, t: float) -> Vector3:
	## The chord from a guard behind the shoulder would cross the skull.
	## The control sits on the face side. Ends of the segment stay put.
	var mid := a.lerp(b, 0.5)
	if mid.z > -0.36:
		mid.z = -0.55
	# Do not crest the skull. Overhead stays in front; a side swing stays wide.
	if mid.y > 1.42 and absf(mid.x) < 0.34:
		mid.z = minf(mid.z, -0.64)
		if _swing_arc_aim.x < -0.25:
			mid.x = minf(mid.x, -0.28)
		elif _swing_arc_aim.x > 0.25:
			mid.x = maxf(mid.x, 0.28)
		else:
			mid.y = minf(mid.y, 1.50)
	return _quad_bez(a, mid, b, t)



func _swing_yaw(u: float) -> float:
	## How far the chest has turned from the pose the swing left.
	## The shaft uses the same angle, so the wood stays in the hands.
	var a := 0.0
	var b := 0.0
	if _swing_start_pose.has("hips"):
		a = (_swing_start_pose["hips"] as Vector3).y
	if _swing_follow_pose.has("hips"):
		b = (_swing_follow_pose["hips"] as Vector3).y
	return (b - a) * 0.55 * clampf(u, 0.0, 1.0)


func _swing_body_at(u: float) -> Dictionary:
	## Hips, spine, and the step share the shaft's parameter. Arms are
	## overwritten by the two-hand grip. Shin pitch stays negative.
	## A pure top chop keeps the feet down and the chest near upright —
	## the side swings still take the lean and the step.
	var pose := {}
	var step_u := clampf(u / maxf(_swing_strike_u, 0.05), 0.0, 1.0)
	var turn := clampf(u, 0.0, 1.0)
	var lean := sin(turn * PI)
	var overhead := absf(_swing_arc_aim.x) < 0.35 and _swing_arc_aim.y <= 0.05
	if overhead:
		step_u *= 0.18
		lean *= 0.20
	for k in _swing_start_pose.keys():
		var key := String(k)
		if key == "root_drop" or key == "grip_slide":
			var dest := float(_swing_follow_pose.get(k, _swing_start_pose[k]))
			if key == "grip_slide":
				dest = 0.0
			pose[k] = lerpf(float(_swing_start_pose[k]), dest, step_u)
			continue
		var a: Vector3 = _swing_start_pose[k]
		var b: Vector3 = _swing_follow_pose.get(k, a)
		if key in ["left_thigh", "left_shin", "right_thigh", "right_shin"]:
			pose[k] = a.lerp(b, step_u)
		elif key == "hips" or key == "torso" or key == "head":
			var v := a
			v.y = a.y + _swing_yaw(turn)
			if key != "head":
				var dive := -0.04 * lean if overhead else -0.16 * lean
				v.x = lerpf(a.x, b.x, 0.35 * turn) + dive
				v.z = lerpf(a.z, b.z, 0.25 * turn)
			pose[k] = v
		else:
			pose[k] = a
	for leg in ["left_shin", "right_shin"]:
		if not pose.has(leg):
			continue
		var sv: Vector3 = pose[leg]
		if sv.x > deg_to_rad(-10.0):
			sv.x = deg_to_rad(-26.0)
		pose[leg] = sv
	if overhead:
		for leg in ["left_thigh", "right_thigh"]:
			if not pose.has(leg):
				continue
			var tv: Vector3 = pose[leg]
			# A kicked thigh tips the foot up. Keep the plant from the start.
			if tv.x > deg_to_rad(22.0):
				tv.x = deg_to_rad(18.0)
			pose[leg] = tv
	return pose




func _lift_line_onto_the_face(butt: Vector3, tip: Vector3) -> Array:
	## Player space. Negative Z is the face. A point behind the ear or the
	## neck is slid forward with the whole shaft, not along it.
	var need := 0.0
	for i in 14:
		var p: Vector3 = butt.lerp(tip, float(i) / 13.0)
		var by_body := absf(p.x) < 0.70 and p.y > 0.80 and p.y < 2.15
		if by_body and p.z > -0.36:
			need = maxf(need, p.z + 0.42)
		if p.y > 1.40 and p.z > -0.22 and absf(p.x) < 1.05:
			need = maxf(need, p.z + 0.40)
	if need > 0.001:
		butt.z -= need
		tip.z -= need
	var axis := tip - butt
	if axis.length_squared() > 0.0001:
		tip = butt + axis.normalized() * 1.30
	return [butt, tip]


func _slide_line_off_body(butt_w: Vector3, tip_w: Vector3) -> Array:
	## Any sample in the skull, the neck, or the torso steps toward the face,
	## perpendicular to the shaft. A push along the wood does not count.
	if locomotion == null:
		return [butt_w, tip_w]
	var head := locomotion.get_joint("head") as Node3D
	var torso := locomotion.get_joint("torso") as Node3D
	if head == null or torso == null:
		return [butt_w, tip_w]
	var axis := tip_w - butt_w
	if axis.length_squared() < 0.0001:
		return [butt_w, tip_w]
	axis = axis.normalized()
	var face := -head.global_transform.basis.z
	if face.length_squared() < 0.0001:
		return [butt_w, tip_w]
	face = face.normalized()
	var dir := face - axis * axis.dot(face)
	if dir.length() < 0.28:
		var side := head.global_transform.basis.x
		if _swing_arc_aim.x > 0.25:
			side = -side
		dir = side - axis * axis.dot(side)
	if dir.length_squared() < 0.0001:
		return [butt_w, tip_w]
	dir = dir.normalized()
	if dir.dot(face) < 0.0:
		dir = -dir
	var push := 0.0
	for i in 18:
		var p: Vector3 = butt_w.lerp(tip_w, float(i) / 17.0)
		var hp: Vector3 = head.to_local(p)
		var along := maxf(dir.dot(face), 0.35)
		if hp.length() < 0.36:
			push = maxf(push, (0.42 - hp.length()) / 0.40)
		if hp.z > -0.18 and hp.length() < 0.55 and absf(hp.y) < 0.42:
			push = maxf(push, (hp.z + 0.34) / along)
		if hp.y < 0.14 and hp.y > -0.52 and hp.z > -0.16 and Vector2(hp.x, hp.z).length() < 0.30:
			push = maxf(push, (hp.z + 0.30) / along)
		var tp: Vector3 = torso.to_local(p)
		if absf(tp.x) < 0.36 and tp.y > -0.08 and tp.y < 0.62 and tp.z > -0.10:
			var chest_face := -torso.global_transform.basis.z
			var along_c := 0.35
			if chest_face.length_squared() > 0.0001:
				along_c = maxf(dir.dot(chest_face.normalized()), 0.35)
			push = maxf(push, (tp.z + 0.22) / along_c)
	if push > 0.001:
		var delta := dir * minf(push, 0.55)
		butt_w += delta
		tip_w += delta
		var kept := tip_w - butt_w
		if kept.length_squared() > 0.0001:
			tip_w = butt_w + kept.normalized() * 1.30
	return [butt_w, tip_w]


func _bring_shaft_to_both_hands(butt_w: Vector3, tip_w: Vector3) -> Array:
	## Translate the whole line toward the shoulders when a palm would slip off.
	## Never along the shaft, and never back into the cloak.
	if locomotion == null:
		return [butt_w, tip_w]
	var torso := locomotion.get_joint("torso") as Node3D
	var face := Vector3(0.0, 0.0, -1.0)
	if torso:
		face = -torso.global_transform.basis.z
		if face.length_squared() > 0.0001:
			face = face.normalized()
	for _pass in 5:
		var push := Vector3.ZERO
		var n := 0
		for side in ["right_arm", "left_arm"]:
			var arm := locomotion.get_joint(side) as Node3D
			if arm == null:
				continue
			var shoulder: Vector3 = arm.global_position
			var best := butt_w
			var best_d := 99.0
			for i in 12:
				var p: Vector3 = butt_w.lerp(tip_w, float(i) / 11.0)
				var d := shoulder.distance_to(p)
				if d < best_d:
					best_d = d
					best = p
			if best_d <= 0.42:
				continue
			var step := (shoulder - best).normalized() * minf(best_d - 0.40, 0.14)
			# A step into the cloak is not a grip. Keep the line on the face side.
			var into := -step.dot(face)
			if into > 0.0:
				step += face * into
			if step.length_squared() < 0.0001:
				continue
			push += step
			n += 1
		if n == 0:
			break
		butt_w += push / float(n)
		tip_w += push / float(n)
	var axis := tip_w - butt_w
	if axis.length_squared() > 0.0001:
		tip_w = butt_w + axis.normalized() * 1.30
	return [butt_w, tip_w]


func _place_continuous_shaft(butt_w: Vector3, tip_w: Vector3) -> Node3D:
	if weapon_visual == null:
		return null
	var axis := tip_w - butt_w
	if axis.length_squared() < 0.0001:
		return weapon_visual.get_node_or_null("Goad") as Node3D
	axis = axis.normalized()
	var origin := butt_w - axis * (-0.255)
	var prefer := _swing_frame.basis.x
	var x := prefer - axis * prefer.dot(axis)
	if x.length_squared() < 0.0004:
		x = _swing_frame.basis.z.cross(axis)
	x = x.normalized()
	var z := x.cross(axis).normalized()
	weapon_visual.global_transform = Transform3D(Basis(x, axis, z), origin)
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	if goad:
		goad.position = Vector3.ZERO
		goad.rotation = Vector3.ZERO
	return goad


func _finish_goad_return() -> void:
	## Jab eases to the ready pose. A shaft swing stays on the arc it arrived on.
	## Standing the stick up in front of the face is the snap this replaced.
	_swing_arc_live = false
	if _goad_swing_held:
		return
	if combat and (combat.is_charging or combat.is_shaft_blocking):
		return
	if combat == null or locomotion == null:
		_tool_pose_active = false
		return
	_apply_tool_pose(ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD))
	_tool_pose_active = false


func _lerp_tool_pose(t: float, from_pose: Dictionary, to_pose: Dictionary) -> void:
	_apply_blended_pose(from_pose, to_pose, t, false)


func _lerp_goad_shaft(t: float, from_pose: Dictionary, to_pose: Dictionary, from_xf: Transform3D, to_xf: Transform3D) -> void:
	var u := clampf(t, 0.0, 1.0)
	_swing_from_slide = float(from_pose.get("grip_slide", 0.0))
	_swing_to_slide = float(to_pose.get("grip_slide", 0.0))
	if _swing_arc_live:
		# Turn the spine first, then lay the wood on the face side of that head.
		_swing_pose_only = true
		if u > 0.001 and u < 0.999:
			var mid := _swing_arc_mid(from_pose, to_pose)
			if u <= 0.5:
				_apply_blended_pose(from_pose, mid, u / 0.5, false)
			else:
				_apply_blended_pose(mid, to_pose, (u - 0.5) / 0.5, false)
		else:
			_apply_blended_pose(from_pose, to_pose, u, false)
		_swing_pose_only = false
		# The whole swing, including the seat it arrives on. The guard
		# the player is holding is not this path. Pose tables stay put.
		_swing_arc_interior = true
		var shaft_xf := _swing_shaft_on_arc(from_xf, to_xf, u)
		_shaft_from_xf = shaft_xf
		_shaft_to_xf = shaft_xf
		_shaft_xf_u = 1.0
		_shaft_xf_blend = true
		_sync_weapon_to_hand()
		_shaft_xf_blend = false
		_swing_arc_interior = false
		return
	var shaft_xf := from_xf.interpolate_with(to_xf, u)
	# Jab keeps the old blend. One transform, so the plant cannot slerp off it.
	_shaft_from_xf = shaft_xf
	_shaft_to_xf = shaft_xf
	_shaft_xf_u = 1.0
	_shaft_xf_blend = true
	_apply_blended_pose(from_pose, to_pose, u, false)
	_shaft_xf_blend = false


func _swing_arc_mid(from_pose: Dictionary, to_pose: Dictionary) -> Dictionary:
	## Halfway is not the straight lerp. The chord leaves the chest still
	## while the stick travels. This sample turns hips and spine with that
	## travel. It is only the in-between; the phase poses stay put.
	var mid := {}
	for k in to_pose.keys():
		if String(k) == "root_drop" or String(k) == "grip_slide":
			mid[k] = lerpf(float(from_pose.get(k, 0.0)), float(to_pose[k]), 0.5)
		else:
			var a: Vector3 = from_pose.get(k, Vector3.ZERO)
			var b: Vector3 = to_pose[k]
			var along := 0.5
			# Hips and spine lead, but they do not spin all the way to the
			# contact yaw in the middle. That turn shows the cloak and leaves
			# the stick behind the chest.
			var key := String(k)
			if key == "hips" or key == "torso" or key == "head":
				along = 0.32
			mid[k] = a.lerp(b, along)
	var side := 0.0
	if _swing_arc_aim.x < -0.35:
		side = 1.0
	elif _swing_arc_aim.x > 0.35:
		side = -1.0
	var overhead := 1.0 if _swing_arc_aim.y < -0.35 else 0.0
	if mid.has("hips"):
		mid["hips"] = (mid["hips"] as Vector3) + Vector3(overhead * -0.18, side * 0.14, 0.0)
	if mid.has("torso"):
		mid["torso"] = (mid["torso"] as Vector3) + Vector3(overhead * -0.16, side * 0.12, 0.0)
	if mid.has("head"):
		mid["head"] = (mid["head"] as Vector3) + Vector3(overhead * 0.08, side * 0.05, 0.0)
	if mid.has("right_arm"):
		mid["right_arm"] = (mid["right_arm"] as Vector3) + Vector3(overhead * -0.16, side * 0.2, side * -0.08)
	if mid.has("left_arm"):
		mid["left_arm"] = (mid["left_arm"] as Vector3) + Vector3(overhead * -0.12, side * 0.12, side * 0.06)
	# A positive shin kicks the foot up. The in-between keeps the sole down.
	for leg in ["left_shin", "right_shin"]:
		if not mid.has(leg):
			continue
		var sv: Vector3 = mid[leg]
		if sv.x > deg_to_rad(-12.0):
			sv.x = deg_to_rad(-28.0)
		mid[leg] = sv
	return mid


func _swing_shaft_on_arc(from_xf: Transform3D, to_xf: Transform3D, u: float) -> Transform3D:
	## Wood ends, not a quaternion slerp. The slerp bows the tip behind the
	## skull while the chest stays on the chord. Ends are the phase holds.
	if u <= 0.001:
		return from_xf
	if u >= 0.999:
		return to_xf
	var from_line := _guard_line(from_xf, _swing_from_slide)
	var to_line := _guard_line(to_xf, _swing_to_slide)
	var slide := lerpf(_swing_from_slide, _swing_to_slide, u)
	var mid_butt: Vector3 = from_line[0].lerp(to_line[0], 0.5)
	var mid_tip: Vector3 = from_line[1].lerp(to_line[1], 0.5)
	var bulge := _swing_face_bulge(mid_tip)
	var butt := _quad_bez(from_line[0], mid_butt + bulge, to_line[0], u)
	var tip := _quad_bez(from_line[1], mid_tip + bulge, to_line[1], u)
	var axis := tip - butt
	if axis.length_squared() < 0.0001:
		return from_xf.interpolate_with(to_xf, u)
	axis = axis.normalized()
	var origin := butt - axis * (-0.255 - slide)
	var carry := from_xf.interpolate_with(to_xf, u)
	var x := carry.basis.x
	x = x - axis * x.dot(axis)
	if x.length_squared() < 0.0001:
		x = carry.basis.z.cross(axis)
	x = x.normalized()
	var z := x.cross(axis).normalized()
	return Transform3D(Basis(x, axis, z), origin)


func _swing_face_bulge(mid_tip: Vector3) -> Vector3:
	## The quaternion chord leaves the tip behind the skull. The control is
	## pushed until the middle of the wood is in front of the chest. A side
	## swing also leads across. Negative torso Z is the face.
	if locomotion == null:
		return Vector3.ZERO
	var torso := locomotion.get_joint("torso") as Node3D
	if torso == null:
		return Vector3.ZERO
	var basis := torso.global_transform.basis
	var face := -basis.z
	var side_axis := basis.x
	var swing := 0.0
	if _swing_arc_aim.x < -0.35:
		swing = -1.0
	elif _swing_arc_aim.x > 0.35:
		swing = 1.0
	# Bezier at u=0.5 sits halfway from the chord midpoint to the control,
	# so the push is twice the distance the tip still has to travel.
	var lp: Vector3 = torso.to_local(mid_tip)
	var need := 0.28
	if lp.z > -0.12:
		need = maxf(need, (lp.z + 0.22) * 2.0)
	# Stay between the hands. A longer push parks the wood where one palm slips off.
	var cap := 0.85 if _swing_arc_aim.y < -0.35 else 0.48
	need = clampf(need, 0.22, cap)
	return face * need + side_axis * swing * 0.1


func _quad_bez(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	return ab.lerp(bc, t)


func _slerp_tool_pose(t: float, from_pose: Dictionary, to_pose: Dictionary) -> void:
	_apply_blended_pose(from_pose, to_pose, t, true)


func _slerp_goad_settle(t: float, from_pose: Dictionary, to_pose: Dictionary) -> void:
	## Same 0.22s ease. The path stays off the back of the head. Not the hurt flinch.
	_apply_tool_pose(ToolStrikePoses.tool_goad_settle_pose(from_pose, to_pose, t))




func _apply_blended_pose(from_pose: Dictionary, to_pose: Dictionary, t: float, use_slerp: bool) -> void:
	var blended := {}
	for k in to_pose.keys():
		if String(k) == "root_drop" or String(k) == "grip_slide":
			blended[k] = lerpf(float(from_pose.get(k, 0.0)), float(to_pose[k]), t)
			continue
		var a: Vector3 = from_pose.get(k, Vector3.ZERO)
		var b: Vector3 = to_pose[k]
		if use_slerp:
			blended[k] = Quaternion.from_euler(a).slerp(Quaternion.from_euler(b), t).get_euler()
		else:
			blended[k] = a.lerp(b, t)
	_apply_tool_pose(blended)


func _scale_tool_pose(pose: Dictionary, scale: float) -> Dictionary:
	if absf(scale - 1.0) < 0.001:
		return pose
	var out := {}
	for k in pose.keys():
		if String(k) == "root_drop":
			out[k] = float(pose[k])
			continue
		out[k] = (pose[k] as Vector3) * scale
	return out


func _current_tool_pose(fallback: Dictionary) -> Dictionary:
	var pose := {}
	for k in fallback.keys():
		if String(k) == "root_drop":
			pose[k] = _tool_root_drop
		elif String(k) == "weapon":
			pose[k] = _tool_weapon_euler
		elif String(k) == "grip_slide":
			pose[k] = _goad_grip_slide
		elif locomotion and locomotion.has_combat_additive(String(k)):
			pose[k] = locomotion.get_combat_additive(String(k))
		else:
			pose[k] = fallback[k]
	pose["root_drop"] = _tool_root_drop
	return pose


func _apply_tool_pose(pose: Dictionary) -> void:
	if locomotion == null:
		return
	_tool_pose_active = true
	var drop := 0.0
	if pose.has("root_drop"):
		drop = float(pose["root_drop"])
	_tool_root_drop = drop
	locomotion.set_root_drop(drop)
	_goad_grip_slide = float(pose.get("grip_slide", 0.0))
	for k in pose.keys():
		if String(k) == "weapon":
			_tool_weapon_euler = pose[k]
			continue
		if String(k) == "root_drop" or String(k) == "grip_slide":
			continue
		locomotion.set_combat_additive(String(k), pose[k])
	_sync_weapon_to_hand()


func _on_hit_landed(_attacker: Node, _target: Node, damage: float, kind: StringName) -> void:
	# Screen punch — charged hatchet contact gets extra impact juice (#6).
	var amp := 0.09 if kind == &"heavy" else 0.03
	if kind == &"heavy":
		amp *= clampf(damage / 22.0, 0.9, 1.55)
	else:
		amp *= clampf(damage / 14.0, 0.75, 1.4)
	_screen_punch(amp)


func _on_damage_taken(amount: float, _from: Node) -> void:
	# Hit-stun cancels hatchet charge (USER LOCK).
	if combat and combat.is_charging:
		combat.cancel_charge()
		_hatchet_charge_armed = false
	_screen_punch(0.07 if amount >= 12.0 else 0.045)
	if amount > 0.0:
		_note_flinch_from()
		_play_hurt_flinch()


func _expire_hurt_react_if_tween_died() -> void:
	if not _hurt_reacting:
		return
	if _arm_tween and _arm_tween.is_valid():
		return
	_hurt_reacting = false


func is_hurt_flinching() -> bool:
	return _hurt_reacting


## Incoming hit the flinch leans away from. right / top / low / left.
var flinch_from: StringName = &"top"


func _note_flinch_from() -> void:
	if combat == null:
		flinch_from = &"top"
		return
	match combat.incoming_strike_direction:
		CombatSystem.StrikeDirection.RIGHT:
			flinch_from = &"right"
		CombatSystem.StrikeDirection.BOTTOM:
			flinch_from = &"low"
		CombatSystem.StrikeDirection.LEFT:
			flinch_from = &"left"
		_:
			flinch_from = &"top"




func _play_hurt_flinch() -> void:
	## A landed hit. Charge is already dropped. A swing in progress yields
	## the same way: the pose becomes the flinch, then the ready pose.
	## Does not change attack rules beyond that. Not a knockdown.
	if combat == null or locomotion == null or combat.is_dead:
		return
	if is_mounted:
		return
	var weapon_id := int(combat.current_weapon)
	var pose_idle: Dictionary = ToolStrikePoses.tool_idle_pose(weapon_id)
	var pose_hurt: Dictionary = ToolStrikePoses.tool_hurt_flinch_pose(weapon_id)
	var start_pose: Dictionary = _current_tool_pose(pose_idle)
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_hurt_reacting = true
	_tool_pose_active = true
	_guard_blend_active = false
	_shaft_xf_blend = false
	_arm_tween = create_tween()
	_arm_tween.tween_method(_blend_hurt_flinch.bind(start_pose, pose_hurt, false), 0.0, 1.0, HURT_FLINCH_IN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_interval(HURT_FLINCH_HOLD_SEC)
	_arm_tween.tween_method(_blend_hurt_flinch.bind(pose_hurt, pose_idle, true), 0.0, 1.0, HURT_FLINCH_OUT_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_callback(_finish_hurt_flinch)


func _blend_hurt_flinch(t: float, from_pose: Dictionary, to_pose: Dictionary, use_slerp: bool) -> void:
	## Goad only: the short arc stays off the face. Other weapons keep the plain blend.
	if combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
		_apply_tool_pose(ToolStrikePoses.tool_goad_flinch_blend(from_pose, to_pose, t, use_slerp))
		return
	if use_slerp:
		_slerp_tool_pose(t, from_pose, to_pose)
	else:
		_lerp_tool_pose(t, from_pose, to_pose)


func _finish_hurt_flinch() -> void:
	_hurt_reacting = false
	if combat == null or locomotion == null:
		_tool_pose_active = false
		return
	if combat.is_charging or combat.is_dead:
		return
	if combat.is_attacking:
		# The swing already yielded. Leave the ready pose the tween landed on.
		_apply_tool_pose(ToolStrikePoses.tool_idle_pose(int(combat.current_weapon)))
		_tool_pose_active = false
		return
	_apply_tool_pose(ToolStrikePoses.tool_idle_pose(int(combat.current_weapon)))
	_tool_pose_active = false


func _screen_punch(amount: float) -> void:
	if camera == null:
		return
	if _punch_tween and _punch_tween.is_valid():
		_punch_tween.kill()
		camera.position = _camera_base_pos
	var kick := Vector3(randf_range(-amount, amount), amount * 0.65, amount * 0.35)
	_punch_tween = create_tween()
	_punch_tween.tween_property(camera, "position", _camera_base_pos + kick, 0.035).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(camera, "position", _camera_base_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_died(_victim: Node) -> void:
	# Keep camera; player ragdoll deferred — just stop combat inputs via combat.is_dead
	pass



func _sync_weapon_to_hand() -> void:
	## Keep hatchet/knife/goad near the right forearm tip so swings read with the arm.
	if weapon_visual == null or locomotion == null:
		return
	# Hatchet swing tween owns WeaponVisual. Goad/knife stay glued to the hand.
	if combat and combat.is_attacking and combat.current_weapon == CombatSystem.Weapon.HATCHET:
		return
	var forearm := locomotion.get_joint("right_forearm")
	if forearm == null or not forearm.is_inside_tree():
		return
	# Tip of forearm in player local space
	var tip_global := forearm.to_global(Vector3(0.0, -0.22, 0.0))
	weapon_visual.global_position = tip_global
	# Bent-elbow guards slide the hand along the stick and shift the mesh back,
	# so the shaft line does not follow the elbow.
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	if goad:
		goad.position.y = -_goad_grip_slide

	var rot := _idle_weapon_euler()
	# Stow keeps the goad's hand orientation so the reverse matches the draw.
	if _goad_stowing and combat and combat.current_weapon == CombatSystem.Weapon.UNARMED:
		rot = Vector3(deg_to_rad(6.0), deg_to_rad(-4.0), deg_to_rad(78.0))
	elif _tool_pose_active and combat and combat.current_weapon != CombatSystem.Weapon.HATCHET:
		rot = _tool_weapon_euler
	elif combat and combat.is_charging:
		var t := clampf(combat.charge_ratio, 0.0, 1.0)
		t = t * t
		match combat.charge_direction:
			CombatSystem.StrikeDirection.LEFT:
				rot = Vector3(
					deg_to_rad(lerpf(-12.0, -48.0, t)),
					deg_to_rad(lerpf(6.0, 78.0, t)),
					deg_to_rad(lerpf(-14.0, 36.0, t))
				)
			CombatSystem.StrikeDirection.RIGHT:
				rot = Vector3(
					deg_to_rad(lerpf(-12.0, -52.0, t)),
					deg_to_rad(lerpf(6.0, -68.0, t)),
					deg_to_rad(lerpf(-14.0, -48.0, t))
				)
			_:
				rot = Vector3(
					deg_to_rad(lerpf(-12.0, -118.0, t)),
					deg_to_rad(lerpf(6.0, 18.0, t)),
					deg_to_rad(lerpf(-14.0, 70.0, t))
				)
	weapon_visual.rotation = rot
	_weapon_base_y = weapon_visual.position.y
	var drawing := combat and combat.current_weapon == CombatSystem.Weapon.GOAD and _goad_draw_u < 0.999 and not combat.is_attacking and not combat.is_charging and not combat.is_shaft_blocking
	if drawing:
		var hand_xf := weapon_visual.global_transform
		var seat_xf := _back_seat_global()
		var s := _goad_draw_smooth()
		weapon_visual.global_transform = seat_xf.interpolate_with(hand_xf, s)
		# The straight slide swings wide of the right hand. Bring a point of
		# the shaft back into reach, then bow it off the skull.
		_keep_draw_in_right_reach(weapon_visual)
		_bow_stow_off_the_head(weapon_visual)
		# The slide still crosses the cloak when the left hand arrives.
		_clear_draw_off_the_cloak(weapon_visual, s)
		_bow_stow_off_the_head(weapon_visual)
		_guide_draw_hands(weapon_visual, s)
	elif _goad_stowing:
		_apply_back_goad_carry(_goad_draw_u)
	elif _swing_pose_only:
		pass
	elif combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
		if _guard_blend_active:
			_plant_shaft_between(_guard_from_xf, _guard_to_xf, _guard_blend_u)
		elif _shaft_xf_blend:
			_plant_shaft_between(_shaft_from_xf, _shaft_to_xf, _shaft_xf_u)
		elif combat.is_charging and _charge_from_ready and _is_top_goad_charge(_shaft_aim_axes()):
			# The generic seat pulls this hold out beside the right ear.
			_plant_shaft_between(_charge_from_xf, _shaft_to_xf, ToolStrikePoses._charge_blend(combat.charge_ratio))
		else:
			ToolStrikePoses.seat_goad_off_hand(locomotion, weapon_visual)
	# Keep combat idle rest in sync while not charging so recovery returns to grip.
	# Not the in-between draw pose — recovery must come back to the landed hold.
	if combat and not combat.is_charging and not combat.is_attacking and not drawing:
		combat.set_weapon_rest_transform(weapon_visual.transform)



func _goad_draw_smooth() -> float:
	var u := clampf(_goad_draw_u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _goad_draw_tween_running_to_hands() -> bool:
	return false


func _back_goad_node() -> Node3D:
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node == null:
		return null
	return visual_node.find_child("BackGoad", true, false) as Node3D


func _back_seat_global() -> Transform3D:
	var back := _back_goad_node()
	if back == null or back.get_parent() == null:
		return weapon_visual.global_transform if weapon_visual else Transform3D.IDENTITY
	return (back.get_parent() as Node3D).global_transform * _back_goad_seat


func _begin_goad_travel(to_hands: bool) -> void:
	if not _goad_seat_ready:
		_goad_draw_u = 1.0 if to_hands else 0.0
		return
	if to_hands and _goad_draw_u >= 0.999 and not _goad_stowing:
		return
	if not to_hands and _goad_draw_u <= 0.001 and not _goad_stowing:
		return
	if _goad_draw_tween and _goad_draw_tween.is_valid():
		_goad_draw_tween.kill()
	if to_hands:
		_goad_stowing = false
		var back := _back_goad_node()
		if back:
			back.visible = false
			back.transform = _back_goad_seat
		_goad_draw_u = 0.0
		_goad_draw_tween = create_tween()
		_goad_draw_tween.tween_method(_set_goad_draw_u, 0.0, 1.0, GOAD_DRAW_SEC)
	else:
		if weapon_visual:
			_goad_stow_from = weapon_visual.global_transform
		_goad_stowing = true
		var back := _back_goad_node()
		if back:
			back.visible = true
			_apply_back_goad_carry(1.0)
		_goad_draw_tween = create_tween()
		_goad_draw_tween.tween_method(_set_goad_draw_u, _goad_draw_u if _goad_draw_u > 0.0 else 1.0, 0.0, GOAD_DRAW_SEC)


func _ease_one_hand_draw_body() -> void:
	# u=0 is the short seat. The right arm comes up to take it. The left arm
	# stays down until the shaft has left the back, then it joins the idle.
	var pose: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var s := _goad_draw_smooth()
	var meet := smoothstep(0.50, 0.92, s)
	for k in pose.keys():
		var key := String(k)
		if key == "weapon" or key == "root_drop" or key == "grip_slide":
			continue
		var w := meet if key == "left_arm" or key == "left_forearm" else s
		locomotion.set_combat_additive(key, (pose[k] as Vector3) * w)
	_tool_pose_active = false


func _ease_goad_draw_body() -> void:
	# Stow only. Both arms ease with the idle. The draw does not use this.
	var pose: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var u := _goad_draw_smooth()
	for k in pose.keys():
		var key := String(k)
		if key == "weapon" or key == "root_drop" or key == "grip_slide":
			continue
		locomotion.set_combat_additive(key, (pose[k] as Vector3) * u)
	_tool_pose_active = false


func _set_goad_draw_u(u: float) -> void:
	_goad_draw_u = u
	if _goad_stowing:
		_apply_weapon_idle_pose()
		if u <= 0.001:
			_finish_goad_stow()
	elif combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
		_sync_weapon_to_hand()


func _apply_back_goad_carry(u: float) -> void:
	var back := _back_goad_node()
	if back == null:
		return
	var seat_xf := _back_seat_global()
	back.visible = true
	# Unarmed stow is the draw reversed: the eased hand owns the moving end.
	# The knife keeps its own hand. Both still finish on the short seat, and
	# both bow off the skull on the way there.
	if combat and combat.current_weapon == CombatSystem.Weapon.UNARMED and weapon_visual:
		var s := _goad_draw_smooth()
		back.global_transform = seat_xf.interpolate_with(weapon_visual.global_transform, s)
		# The straight reverse climbs through the face. Bow it out to his
		# right, and only as far as the shaft still meets the skull. Zero
		# when the seat and the hands are already clear.
		_bow_stow_off_the_head(back)
		_guide_stow_hand(back, s)
	else:
		var ku := clampf(u, 0.0, 1.0)
		back.global_transform = seat_xf.interpolate_with(_goad_stow_from, ku)
		# Same bow as the unarmed stow. The knife hand is not pulled onto the shaft.
		_bow_stow_off_the_head(back)


func _pull_shaft_into_reach(shaft: Node3D) -> void:
	## Both hands stay on the wood. If the arc stepped out of reach, bring
	## it back toward the shoulders before the grip solves.
	if locomotion == null:
		return
	var pull := Vector3.ZERO
	var n := 0
	for arm_name in ["right_arm", "left_arm"]:
		var arm := locomotion.get_joint(arm_name) as Node3D
		if arm == null:
			continue
		var shoulder: Vector3 = arm.global_position
		var best_d := 99.0
		var best := Vector3.ZERO
		for i in 12:
			var p: Vector3 = shaft.to_global(Vector3(0.0, lerpf(-0.05, 0.95, float(i) / 11.0), 0.0))
			var d := shoulder.distance_to(p)
			if d < best_d:
				best_d = d
				best = p
		if best_d > 0.50:
			pull += (shoulder - best).normalized() * (best_d - 0.46)
			n += 1
	if n > 0:
		shaft.global_position += pull / float(n)


func _bow_swing_clear_of_body(shaft: Node3D) -> void:
	## Left, top, and right. Slide the wood off the skull, the neck, and the
	## inside of the torso, toward the face and across the shaft, not along it.
	## A push along the shaft leaves a horizontal stick through the head.
	## Pose tables stay put. The jab never sets the swing arc.
	if locomotion == null:
		return
	var head := locomotion.get_joint("head") as Node3D
	var torso := locomotion.get_joint("torso") as Node3D
	if head == null or torso == null:
		return
	for _pass in 6:
		var axis := shaft.global_transform.basis.y
		if axis.length_squared() < 0.0001:
			return
		axis = axis.normalized()
		var face := -head.global_transform.basis.z
		if face.length_squared() < 0.0001:
			return
		face = face.normalized()
		var dir := face - axis * axis.dot(face)
		if dir.length() < 0.28:
			var side := head.global_transform.basis.x
			dir = side - axis * axis.dot(side)
		if dir.length_squared() < 0.0001:
			return
		dir = dir.normalized()
		var push := 0.0
		for i in 24:
			var along := lerpf(-0.22, 1.08, float(i) / 23.0)
			var p: Vector3 = shaft.to_global(Vector3(0.0, along, 0.0))
			var hp: Vector3 = head.to_local(p)
			var dist := hp.length()
			if dist < 0.36:
				var away := 0.35
				if dist > 0.02:
					away = maxf(dir.dot((p - head.global_position).normalized()), 0.35)
				push = maxf(push, (0.40 - dist) / away)
			# Cloak side of the skull, even when the centerline is just outside the sphere.
			if hp.z > -0.06 and dist < 0.50 and absf(hp.y) < 0.38:
				var along_face := maxf(dir.dot(face), 0.35)
				push = maxf(push, (hp.z + 0.28) / along_face)
			if hp.y < 0.12 and hp.y > -0.52 and hp.z > -0.16 and Vector2(hp.x, hp.z).length() < 0.30:
				var along_face_n := maxf(dir.dot(face), 0.35)
				push = maxf(push, (hp.z + 0.24) / along_face_n)
			var tp: Vector3 = torso.to_local(p)
			if absf(tp.x) < 0.34 and tp.y > -0.06 and tp.y < 0.58 and tp.z > -0.05:
				var chest_face := -torso.global_transform.basis.z
				var along_c := 0.35
				if chest_face.length_squared() > 0.0001:
					along_c = maxf(dir.dot(chest_face.normalized()), 0.35)
				push = maxf(push, (tp.z + 0.18) / along_c)
		if push <= 0.004:
			return
		shaft.global_position += dir * minf(push, 0.40)


func _bow_swing_off_the_chest(shaft: Node3D) -> void:
	## A swing sample that would pass through the ribs is carried out in
	## front. Same idea as the stow bow. End poses are not rewritten.
	if locomotion == null:
		return
	var torso := locomotion.get_joint("torso") as Node3D
	if torso == null:
		return
	var face := -torso.global_transform.basis.z
	if face.length_squared() < 0.001:
		return
	face = face.normalized()
	var push := 0.0
	for i in 14:
		var along := lerpf(-0.15, 1.02, float(i) / 13.0)
		var lp: Vector3 = torso.to_local(shaft.to_global(Vector3(0.0, along, 0.0)))
		if absf(lp.x) > 0.36 or lp.y < -0.08 or lp.y > 0.62:
			continue
		if lp.z > -0.06:
			push = maxf(push, lp.z + 0.14)
	if push > 0.001:
		shaft.global_position += face * push


func _bow_stow_off_the_head(back: Node3D) -> void:
	if locomotion == null:
		return
	var head := locomotion.get_joint("head") as Node3D
	var torso := locomotion.get_joint("torso") as Node3D
	if head == null or torso == null:
		return
	var side := torso.global_transform.basis.x
	if side.length_squared() < 0.001:
		return
	side = side.normalized()
	var push := 0.0
	for i in 16:
		var along := lerpf(-0.255, 1.07, float(i) / 15.0)
		var p: Vector3 = back.to_global(Vector3(0.0, along, 0.0))
		var lp: Vector3 = head.to_local(p)
		# Gray head is the tip. The wood is thinner.
		var limit := 0.27 if along > 0.95 else 0.22
		var radial := lp.y * lp.y + lp.z * lp.z
		if lp.length() >= limit or radial >= limit * limit:
			continue
		var need := -lp.x + sqrt(limit * limit - radial)
		if need > push:
			push = need
	if push <= 0.001:
		return
	back.global_position += side * push



func _clear_draw_off_the_cloak(shaft: Node3D, s: float) -> void:
	# Once the shaft has left the seat, the straight path still runs through the
	# cloak. Bring it forward of that slab while the left hand is on it. The
	# back seat and the landed idle are outside this window.
	if s < 0.55 or s > 0.91 or locomotion == null:
		return
	var torso := locomotion.get_joint("torso") as Node3D
	if torso == null:
		return
	var face := torso.global_transform.basis.z
	if face.length_squared() < 0.001:
		return
	face = face.normalized()
	var push := 0.0
	for i in 21:
		var along := lerpf(-0.255, 1.07, float(i) / 20.0)
		var lp: Vector3 = torso.to_local(shaft.to_global(Vector3(0.0, along, 0.0)))
		if absf(lp.x) > 0.32:
			continue
		var through_cloak := absf(lp.y - 0.34) < 0.28 and lp.z < 0.26 and lp.z > -0.02
		var through_torso := lp.y > -0.05 and lp.y < 0.56 and absf(lp.z) < 0.20
		if not through_cloak and not through_torso:
			continue
		var need := 0.30 - lp.z
		if need > push:
			push = need
	if push > 0.001:
		shaft.global_position += face * push


func _keep_draw_in_right_reach(shaft: Node3D) -> void:
	if locomotion == null:
		return
	var arm := locomotion.get_joint("right_arm") as Node3D
	if arm == null:
		return
	var shoulder: Vector3 = arm.global_position
	var best := Vector3.INF
	var best_d := 99.0
	for i in 13:
		var y := lerpf(-0.05, 1.00, i / 12.0)
		var p: Vector3 = shaft.to_global(Vector3(0.0, y, 0.0))
		var d := shoulder.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	if best_d <= 0.50 or best == Vector3.INF:
		return
	shaft.global_position += (shoulder - best).normalized() * (best_d - 0.48)


func _guide_draw_hands(shaft: Node3D, s: float) -> void:
	# Right hand reaches back and takes the shaft off the right shoulder.
	# The left hand stays off it while that shaft is still on the back.
	if locomotion == null:
		return
	var seat_xf := _back_seat_global()
	var on_back := shaft.global_position.distance_to(seat_xf.origin) < 0.28
	if s < 0.90:
		_grip_shaft_with(shaft, "right_arm", "right_forearm", 0.30)
	if on_back or s < 0.36 or s > 0.90:
		return
	_grip_shaft_with(shaft, "left_arm", "left_forearm", 0.24)


func _grip_shaft_with(shaft: Node3D, arm_name: String, fore_name: String, _fore_len: float) -> void:
	var arm := locomotion.get_joint(arm_name) as Node3D
	var fore := locomotion.get_joint(fore_name) as Node3D
	if arm == null or fore == null:
		return
	var shoulder: Vector3 = arm.global_position
	var best := Vector3.INF
	var best_d := 99.0
	for i in 13:
		var y := lerpf(-0.10, 1.02, i / 12.0)
		var p: Vector3 = shaft.to_global(Vector3(0.0, y, 0.0))
		var d := shoulder.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	if best == Vector3.INF or best_d > 0.70:
		return
	var l1 := 0.30
	# The palm sits 0.22 along the forearm, not at the bone tip.
	var palm := 0.22
	var d := clampf(best_d, 0.12, l1 + palm - 0.01)
	var dir := (best - shoulder).normalized()
	var pole := Vector3(0.15, -0.35, 0.4)
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + d * d - palm * palm) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var elbow: Vector3 = shoulder + dir * (l1 * cos_a) + bend * (l1 * sin_a)
	ToolStrikePoses._store_aim(locomotion, arm, arm_name, elbow - shoulder)
	var elbow_now: Vector3 = arm.to_global(Vector3(0.0, -l1, 0.0))
	ToolStrikePoses._store_aim(locomotion, fore, fore_name, best - elbow_now)


func _guide_stow_hand(back: Node3D, s: float) -> void:
	# Right hand stays on the nearest reachable point of the shaft, then lets go
	# as it seats. The left hand keeps the eased draw pose. Not a one-hand draw.
	if s < 0.22 or s > 0.92 or locomotion == null:
		return
	var arm := locomotion.get_joint("right_arm") as Node3D
	var fore := locomotion.get_joint("right_forearm") as Node3D
	if arm == null or fore == null:
		return
	var shoulder: Vector3 = arm.global_position
	var best := Vector3.INF
	var best_d := 99.0
	for i in 13:
		var y := lerpf(-0.15, 1.02, i / 12.0)
		var p: Vector3 = back.to_global(Vector3(0.0, y, 0.0))
		var d := shoulder.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	if best == Vector3.INF or best_d > 0.60:
		return
	var l1 := 0.30
	var l2 := 0.30
	var dir := (best - shoulder).normalized()
	var d := clampf(best_d, 0.12, l1 + l2 - 0.015)
	var pole := Vector3(0.2, -0.2, 0.6)
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var elbow: Vector3 = shoulder + dir * (l1 * cos_a) + bend * (l1 * sin_a)
	_aim_bone_down(arm, shoulder, elbow)
	_aim_bone_down(fore, arm.to_global(Vector3(0.0, -0.30, 0.0)), best)
	locomotion.set_combat_additive("right_arm", arm.rotation - (locomotion._rest["right_arm"]["rot"] as Vector3))
	locomotion.set_combat_additive("right_forearm", fore.rotation - (locomotion._rest["right_forearm"]["rot"] as Vector3))


func _aim_bone_down(bone: Node3D, world_from: Vector3, world_to: Vector3) -> void:
	var aim := world_to - world_from
	if aim.length_squared() < 0.0001:
		return
	var y := -aim.normalized()
	var x := y.cross(Vector3(0.0, 0.0, 1.0))
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3(1.0, 0.0, 0.0))
	x = x.normalized()
	bone.global_basis = Basis(x, y, x.cross(y).normalized())


func _finish_goad_stow() -> void:
	_goad_stowing = false
	_goad_draw_u = 0.0
	var back := _back_goad_node()
	if back:
		back.transform = _back_goad_seat
		back.visible = combat == null or combat.current_weapon != CombatSystem.Weapon.GOAD


## Capture hook. u=0 is the back seat, u=1 is the landed two-hand idle.
func sample_goad_draw(u: float) -> void:
	if _goad_draw_tween and _goad_draw_tween.is_valid():
		_goad_draw_tween.kill()
	_goad_stowing = false
	_goad_draw_u = clampf(u, 0.0, 1.0)
	var back := _back_goad_node()
	if combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
		if back:
			back.visible = false
			back.transform = _back_goad_seat
		if locomotion:
			locomotion.clear_combat_additives()
		_apply_weapon_idle_pose()
	else:
		_goad_draw_u = 0.0
		if back:
			back.visible = true
			back.transform = _back_goad_seat
		if locomotion:
			locomotion.clear_combat_additives()
		_apply_weapon_idle_pose()


func _idle_weapon_euler() -> Vector3:
	if combat == null:
		return Vector3(deg_to_rad(-12.0), deg_to_rad(6.0), deg_to_rad(-14.0))
	match combat.current_weapon:
		CombatSystem.Weapon.GOAD:
			# Across the chest, out in front. Not a vertical pole up the face.
			return Vector3(deg_to_rad(6.0), deg_to_rad(-4.0), deg_to_rad(78.0))
		CombatSystem.Weapon.KNIFE:
			# Matches tool idle: blade up beside the chest, not the strike thrust.
			return Vector3(deg_to_rad(-28.0), deg_to_rad(16.0), deg_to_rad(-36.0))
		_:
			return Vector3(deg_to_rad(-12.0), deg_to_rad(6.0), deg_to_rad(-14.0))

func begin_drag(body: Node3D) -> void:
	if body == null or is_mounted:
		return
	dragging_body = body
	drag_stamina_exhausted = false


func end_drag() -> void:
	dragging_body = null
	drag_stamina_exhausted = false


func is_dragging() -> bool:
	return dragging_body != null and is_instance_valid(dragging_body)


func get_dragged_body() -> Node3D:
	if is_dragging():
		return dragging_body
	return null


func get_drag_status_text() -> String:
	if not is_dragging():
		return ""
	var sta := 0.0
	var mx := 100.0
	if combat:
		sta = combat.stamina
		mx = combat.max_stamina
	var tag := "EXHAUSTED · crawl-drag" if drag_stamina_exhausted else "dragging"
	return "DRAG %s · speed %.2f · STA %d/%d (−%d/s)" % [
		tag, DRAG_SPEED * (0.55 if drag_stamina_exhausted else 1.0),
		int(sta), int(mx), int(DRAG_STAMINA_PER_SEC),
	]


func _update_drag_stamina(delta: float) -> void:
	if not is_dragging() or combat == null or combat.is_dead:
		return
	# Overcome CombatSystem idle regen so the HUD cost is actually readable.
	var cost := (DRAG_STAMINA_PER_SEC + combat.stamina_regen_per_sec) * delta
	if combat.stamina <= DRAG_STAMINA_PER_SEC * delta * 0.5:
		drag_stamina_exhausted = true
		combat.stamina = maxf(0.0, combat.stamina - cost * 0.4)
	else:
		drag_stamina_exhausted = false
		combat.stamina = maxf(0.0, combat.stamina - cost)
	combat.stamina_changed.emit(combat.stamina, combat.max_stamina)


## --- Horse mount API (called by HorseController) ---

func is_mounted_on_horse() -> bool:
	return is_mounted


func prepare_for_mount(horse: Node3D) -> void:
	# Drop any corpse drag before seating.
	if is_dragging():
		end_drag()
	is_mounted = true
	mounted_horse = horse
	is_crouching = false
	_crouch_blend = 0.0
	velocity = Vector3.ZERO
	_jump_buffered = false
	# Snap crouch visuals back to stand while seated.
	_apply_crouch_visual(1.0)
	# Immediate seated bind pose (hips down / legs astride) — skips on-foot loco.
	if locomotion:
		locomotion.tick_mounted(0.0, 0.0, false)


func clear_mount() -> void:
	is_mounted = false
	mounted_horse = null
	velocity = Vector3.ZERO
	# Restore on-foot rest pose so walk cycles resume cleanly.
	if locomotion:
		locomotion.reset_to_rest()


func set_mounted_velocity_zero() -> void:
	velocity = Vector3.ZERO


## Called by HorseController each physics frame while riding.
func tick_mounted_rider_pose(delta: float, horse_speed: float, galloping: bool) -> void:
	if not is_mounted or locomotion == null:
		return
	locomotion.tick_mounted(delta, horse_speed, galloping)
	_sync_weapon_to_hand()
