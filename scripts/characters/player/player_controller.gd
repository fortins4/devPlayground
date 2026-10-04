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
	# Charge locks walk-arm swing so aim cock reads cleanly; swing uses same path.
	var attacking := combat != null and (combat.is_attacking or combat.is_charging or combat.is_shaft_blocking or _hurt_reacting)
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
			_clear_attack_additives()


func _apply_shaft_block_pose() -> void:
	if locomotion == null:
		return
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	var face: StringName = &"chest"
	if combat:
		face = combat.shaft_guard_face
	_apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
	locomotion.lock_attack(0.12)


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
	# Cardinal direction still picks the strike on release. The body tracks
	# the mouse continuously so the weapon is already on that side.
	var aim := _shaft_aim_axes()
	var pose: Dictionary = ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, ratio)
	_apply_tool_pose(pose)
	if locomotion:
		locomotion.lock_attack(0.08)


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
	if combat and combat.is_attacking:
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
	if locomotion:
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
		# Empty hands. No goad seat and no knife pose.
		_tool_pose_active = false
		_sync_weapon_to_hand()
		return
	# Draw eases the body from empty hands into the existing idle. The idle itself is unchanged.
	if combat.current_weapon == CombatSystem.Weapon.GOAD and _goad_draw_u < 0.999:
		var pose: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
		var u := _goad_draw_smooth()
		for k in pose.keys():
			var key := String(k)
			if key == "weapon" or key == "root_drop" or key == "grip_slide":
				continue
			locomotion.set_combat_additive(key, (pose[k] as Vector3) * u)
		_tool_pose_active = false
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



func _play_goad_release(kind: StringName, windup: float, active: float, from_charge: bool) -> void:
	## Release continues the live aim. Contact and follow use the same blend
	## as the hold, so a high-left chamber stays a high-left swing.
	## No second windup, no cardinal snap, no 1.5x contact pop.
	var aim := _shaft_aim_axes()
	# The jab is the point, at any look. It is not the shaft swing he was aiming.
	if combat.last_strike_direction() == CombatSystem.StrikeDirection.BOTTOM:
		aim = Vector2(0.0, 1.0)
	var pose_idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var pose_contact: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"contact")
	var pose_follow: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"follow")
	var start_pose: Dictionary = _current_tool_pose(pose_idle) if from_charge else ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, 0.28)
	var phases: Dictionary = combat.swing_phase_durations(kind, windup, active, GOAD_SETTLE_SEC)
	var drive := float(phases["to_contact"]) + float(phases["windup_move"]) * (0.35 if kind == &"heavy" else 0.55)
	drive = maxf(0.1, drive)
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_tool_pose_active = true
	_arm_tween = create_tween()
	_arm_tween.tween_method(_lerp_tool_pose.bind(start_pose, pose_contact), 0.0, 1.0, drive).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if float(phases["contact_hold"]) > 0.0:
		_arm_tween.tween_interval(float(phases["contact_hold"]))
	_arm_tween.tween_method(_lerp_tool_pose.bind(pose_contact, pose_follow), 0.0, 1.0, phases["follow"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_method(_slerp_goad_settle.bind(pose_follow, pose_idle), 0.0, 1.0, GOAD_SETTLE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_callback(_finish_goad_return)


func _finish_goad_return() -> void:
	## Already eased to the ready pose. Do not snap additives to bind pose.
	if combat and (combat.is_charging or combat.is_shaft_blocking):
		return
	if combat == null or locomotion == null:
		_tool_pose_active = false
		return
	_apply_tool_pose(ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD))
	_tool_pose_active = false


func _lerp_tool_pose(t: float, from_pose: Dictionary, to_pose: Dictionary) -> void:
	_apply_blended_pose(from_pose, to_pose, t, false)


func _slerp_tool_pose(t: float, from_pose: Dictionary, to_pose: Dictionary) -> void:
	_apply_blended_pose(from_pose, to_pose, t, true)


func _slerp_goad_settle(t: float, from_pose: Dictionary, to_pose: Dictionary) -> void:
	## Same 0.22s ease. The path stays off the back of the head. Not the hurt flinch.
	_apply_tool_pose(ToolStrikePoses.tool_goad_settle_pose(from_pose, to_pose, t))




func _apply_blended_pose(from_pose: Dictionary, to_pose: Dictionary, t: float, use_slerp: bool) -> void:
	var blended := {}
	for k in to_pose.keys():
		if String(k) == "root_drop":
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
	if _tool_pose_active and combat and combat.current_weapon != CombatSystem.Weapon.HATCHET:
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
		weapon_visual.global_transform = seat_xf.interpolate_with(hand_xf, _goad_draw_smooth())
	elif combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
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


func _set_goad_draw_u(u: float) -> void:
	_goad_draw_u = u
	if _goad_stowing:
		_apply_back_goad_carry(u)
		if u <= 0.001:
			_finish_goad_stow()
	elif combat and combat.current_weapon == CombatSystem.Weapon.GOAD:
		_sync_weapon_to_hand()


func _apply_back_goad_carry(u: float) -> void:
	var back := _back_goad_node()
	if back == null:
		return
	var seat_xf := _back_seat_global()
	back.global_transform = seat_xf.interpolate_with(_goad_stow_from, clampf(u, 0.0, 1.0))


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
