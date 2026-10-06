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

## FULL bog body-drag: slow move while dragging a corpse. No stamina (removed).
var dragging_body: Node3D = null

## Horse traversal (greybox mount).
var is_mounted: bool = false
var mounted_horse: Node3D = null

## Directional hatchet: hold LMB to charge; mouse aim (look) picks top|left|right.
var _charge_aim_delta: Vector2 = Vector2.ZERO ## mouse aim offset while holding (not WASD/flick)
## Look face snapped at charge begin (guard face is cleared while charging).
var _charge_look_face: StringName = &"chest"
var _hatchet_charge_armed: bool = false
## Shared look deadzone for guard + charge/swing (px). Outside it, equal 90°
## axis-dominant quadrants: left | right | high(top) | low(down). Ties → horizontal.
const LOOK_AIM_DEADZONE := 10.0
## Camera pitch (probed): negative X aims at the ground; positive X aims at the sky.
const LOOK_PITCH_GROUND := -10.0 ## deg: at/below this → low quadrant
const LOOK_PITCH_SKY := 12.0 ## deg: at/above this → high quadrant
## Goad aim stick span (legacy normalize). Cardinal faces snap aim axes directly.
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
## Walk while attacking: WASD keeps moving through charge, release, swing,
## jab and settle at this fraction of WALK_SPEED (replaces the old 0.28 charge
## drift + tap-step and the recovery freeze). Sprint stays refused mid-attack.
const ATTACK_WALK_SCALE := 0.85

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
## True while a goad jab/swing tween (incl. settle) owns the body.
var _goad_release_live: bool = false
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
## Jab thrust rides the LEFT flank (mirrored) when the live start holds the
## butt on the left — e.g. the low guard. Flipping it end-over-end to the
## right flank cut through the chest.
var _jab_mirror: bool = false
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
## Seconds the current continuous swing tween runs (incl. settle). Probe / soak read.
var _swing_arc_total: float = 0.0

## Shaft clearance solver (one pass, last write before the grips). The whole
## segment steps perpendicular to the wood toward the chest face, never along it.
const SHAFT_CLEAR_SAMPLES := 24
const SHAFT_CLEAR_MAX_PUSH := 0.16
const SHAFT_CLEAR_STEP := 0.02
const SHAFT_CLEAR_GRIP_REACH := 0.55
const SHAFT_CLEAR_BOX_GROW := 0.04
## A palm already past reach (authored early-arc) may drift this much further.
const SHAFT_CLEAR_OFF_PALM_SLACK := 0.10
## Fallback only (capped solve left hits): same perpendicular step, further,
## as long as every palm on the wood stays on it.
const SHAFT_CLEAR_FALLBACK_PUSH := 0.30
## Charged side seat: grip mid this far in front of the chest (was 0.30 off the
## root). Palm stations stay inside SHAFT_CLEAR_GRIP_REACH.
const SEAT_SIDE_FORWARD := 0.38
const SHAFT_CLEAR_MESHES := ["TorsoMesh", "TunicSkirt", "Cloak", "HeadMesh", "Belt", "HipsMesh"]
var _clear_meshes: Array = []
## Last solve: hits before / after, push metres, why it stopped. Soak / probe read.
var _clear_last: Dictionary = {}
var _clear_stats: Dictionary = {"calls": 0, "pushed": 0, "residual": 0, "reach_rejected": 0}

## Attack input buffer. A press refused only because a swing is still live is
## held for ATTACK_BUFFER_SEC and fired once the body is free. Never while Shift.
const ATTACK_BUFFER_SEC := 0.18
var _atk_buf_until: float = -1.0
var _atk_buf_action: StringName = &""
var _atk_buf_face: StringName = &""
var _atk_buf_down: bool = false
var _atk_buf_stats: Dictionary = {"armed": 0, "fired": 0, "discarded": 0, "expired": 0}
var _atk_buf_last_fire_frame: int = -1

## Sprint carry (visual only; sprint rules are unchanged). One hand: the right
## palm holds the goad near its balance point and the shaft rides along his
## right side, head forward, butt trailing, off the ground. That arm swings a
## shortened stride; the left arm pumps free. Ending the sprint is the one-hand
## draw's pattern: the right hand brings the shaft forward and the left hand
## meets it on the way, not while it still trails at the side.
const CARRY_IN_SEC := 0.22
const CARRY_OUT_SEC := 0.30
## Palm station on the goad (wood -0.255..1.045, iron head beyond): balance point.
const CARRY_GRIP_SLIDE := 0.42
const CARRY_PITCH_DEG := 8.0 ## tip above level
const CARRY_YAW_IN_DEG := 5.0 ## tip toward the centre line, butt out behind him
const CARRY_SWING_PITCH_DEG := 4.0 ## wrist lag: tip dips as the arm swings forward
const CARRY_ARM_SWING := 0.45 ## share of the sprint arm swing on the carrying arm
## Carrying arm out from the hip (right arm: +Z is away from the body; the
## plain cycle's -10 swings it across). Puts the palm about 0.38 m off centre.
const CARRY_ARM_OUT_DEG := 23.0
const CARRY_ELBOW_DEG := 16.0
const PUMP_ARM_OUT_DEG := 4.0 ## left arm: +Z is toward the body
const PUMP_ELBOW_DEG := 82.0
const PUMP_ELBOW_FWD_DEG := 18.0 ## extra bend on the forward swing
const PUMP_ELBOW_BACK_DEG := 14.0 ## opens a little on the back swing
## Out blend: the left hand stays off the shaft until it has come forward.
const CARRY_MEET_FROM := 0.45
const CARRY_MEET_TO := 0.90
## Mid-blend the carrying hand swings out around the hip, not through the
## front of the skirt (zero at both ends, so neither hold moves).
const CARRY_HIP_BULGE_DEG := 22.0
const CARRY_OUT_BULGE_DEG := 10.0 ## the return rises in front; a smaller swing out
const CARRY_GROUND_CLEAR := 0.16
const CARRY_CLEAR_MARGIN := 0.03
const CARRY_ARM_KEYS := ["right_arm", "right_forearm", "left_arm", "left_forearm"]
const CARRY_BODY_KEYS := ["hips", "torso", "head", "left_thigh", "left_shin", "right_thigh", "right_shin"]
const CARRY_LEG_KEYS := ["left_thigh", "left_shin", "right_thigh", "right_shin"]
enum { CARRY_NONE, CARRY_IN, CARRY_HOLD, CARRY_OUT }
var _carry_state: int = CARRY_NONE
## 0..1 progress into the carry (1 = held). -1 / unused outside IN/HOLD.
var _carry_u: float = 0.0
## 0..1 progress of the return to the two-hand hold; -1 when not returning.
var _carry_out_u: float = -1.0
var _carry_from_pose: Dictionary = {}
var _carry_from_basis: Basis = Basis.IDENTITY ## body-local
var _carry_from_slide: float = 0.0
## Seat offset of the stick from the raw palm (guard seats nudge it), body-local.
var _carry_from_off: Vector3 = Vector3.ZERO
var _carry_to_off: Vector3 = Vector3.ZERO
var _carry_to_pose: Dictionary = {}
var _carry_to_basis: Basis = Basis.IDENTITY ## body-local
var _carry_to_slide: float = 0.0
var _carry_to_face: StringName = &""
var _carry_to_guard: bool = false
var _carry_meshes: Array = []
## How the in blend turns the stick: 0 short arc, 1 long way round, 2 up
## past his right shoulder first. Picked at the start: the one that meets
## the body least (a stick left across his back after a draw needs 1 or 2).
var _carry_in_path: int = 0
var _carry_stats: Dictionary = {"frames": 0, "cleared": 0, "residual": 0, "ground": 0}
## While the goad guard is up, look offset is not decayed so a face stays put.
## Look face / strike cardinals share LOOK_AIM_DEADZONE + equal quadrants.


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
	if locomotion:
		# Walking through charge / release / swing / jab / settle keeps the
		# stride on the legs; the combat pose keeps the arms, spine and shaft.
		locomotion.attack_walk_enabled = true
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
	if event.is_action_pressed("sprint"):
		_discard_attack_buffer(&"sprint")
	if event.is_action_released("attack_light") or event.is_action_released("attack_heavy"):
		_atk_buf_down = false

	if combat == null or combat.is_dead:
		_discard_attack_buffer(&"dead")
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
	_tick_attack_buffer()
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

	# `locked` still gates jump / crouch / sprint exactly as before (recovery
	# refuses them). It no longer stops WASD: only death / stagger do.
	var locked := combat != null and not combat.can_move() and not (combat != null and combat.is_charging)
	var move_locked := combat != null and (combat.is_dead or combat.stagger_left > 0.0)
	# Charge, release, continuous swing, jab and the settle tail all walk.
	var attack_walking := combat != null and not move_locked and (
		combat.is_charging
		or combat.is_attacking
		or combat.attack_recovery_left > 0.0
		or _goad_release_live
		or _swing_arc_live
	)
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
		# No meter. Refused only while dead or mid-attack. A sprint cancels a
		# charge and drops the look-guard inside combat (no attack while sprinting).
		sprinting = combat.try_sprint()
		if sprinting:
			_hatchet_charge_armed = false
	elif want_sprint and combat == null:
		sprinting = true
	_sprinting = sprinting

	var target_speed := WALK_SPEED
	if dragging_body != null and is_instance_valid(dragging_body):
		target_speed = DRAG_SPEED
		sprinting = false
		_sprinting = false
	elif is_crouching:
		target_speed = CROUCH_SPEED
	elif sprinting:
		target_speed = SPRINT_SPEED
	if move_locked:
		target_speed = 0.0
		direction = Vector3.ZERO
	elif attack_walking and not sprinting:
		target_speed = minf(target_speed, WALK_SPEED * ATTACK_WALK_SCALE)

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
	if not is_mounted:
		_expire_hurt_react_if_tween_died()
		_tick_locomotion(delta, horiz.length(), sprinting, move_locked)
		_tick_shaft_block()
		_tick_sprint_carry(delta)
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
		or _goad_release_live
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
		and not _goad_release_live
		and not _swing_arc_live
		and not _hurt_reacting
		and horiz_speed < 0.25
		and not is_mounted
		and not _goad_swing_held
		and _carry_state == CARRY_NONE
		and not _carry_wanted()
	):
		_apply_weapon_idle_pose()
	elif (
		combat
		and not combat.is_attacking
		and not combat.is_charging
		and not combat.is_shaft_blocking
		and not _goad_release_live
		and not _swing_arc_live
		and not _hurt_reacting
		and combat.current_weapon != CombatSystem.Weapon.HATCHET
		and horiz_speed >= 0.25
		and _carry_state == CARRY_NONE
		and not _carry_wanted()
	):
		# Drop full-body tool additives so the walk cycle can move the legs.
		# Never while a goad release/settle still owns the shaft — clearing here
		# left the follow-through stick frozen while the body sprinted.
		_tool_pose_active = false
		_goad_swing_held = false
		if locomotion.has_combat_additive("left_thigh") or locomotion.has_combat_additive("hips"):
			locomotion.clear_combat_additives()


func _tick_shaft_block() -> void:
	## Goad out: look is the guard. No held button. Sprint held and attacks drop it.
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
		and not Input.is_action_pressed("sprint")
		and not combat.is_attacking
		and not combat.is_charging
		and not _goad_release_live
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
		if _carry_wanted() or _carry_state != CARRY_NONE:
			pass  # Sprint carry takes the body from the guard (_tick_sprint_carry).
		elif not combat.is_attacking and not combat.is_charging:
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
	# Coming out of the sprint carry: that blend owns the body until the
	# shaft is back in both hands (it starts / finishes in _tick_sprint_carry).
	if _carry_state != CARRY_NONE and not _carry_must_abort():
		return
	var face: StringName = &"chest"
	if combat:
		face = combat.shaft_guard_face
	# The draw owns the body until the shaft is in the hands.
	if _goad_draw_u < 0.999:
		if _goad_release_live or _swing_arc_live:
			return
		if _arm_tween and _arm_tween.is_valid():
			_abort_goad_release_tween()
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
	# Guard blend must not cut a charged continuous swing or jab settle short.
	if _goad_release_live or _swing_arc_live:
		return
	if _arm_tween and _arm_tween.is_valid():
		_abort_goad_release_tween()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_guard_blend_active = false
	_shaft_xf_blend = false
	_guard_from_pose = start_pose
	_guard_to_pose = target_pose
	# The stick that is already showing, not a reseat of the start pose.
	# Body-local holds: a blend that starts while walking must not leave the
	# shaft at the world spot the blend began from.
	_guard_from_xf = _to_body(weapon_visual.global_transform if weapon_visual else global_transform)
	_guard_to_xf = _to_body(_peek_shaft_xf(target_pose))
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
	if combat.is_attacking or combat.is_charging or _goad_release_live or _hurt_reacting or _sprinting:
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


# --- Sprint carry -----------------------------------------------------------


func _carry_wanted() -> bool:
	## Visual only: the same sprint that already dropped the guard. No new gate.
	return (
		combat != null and locomotion != null and weapon_visual != null
		and _sprinting
		and not _carry_must_abort()
	)


func _carry_must_abort() -> bool:
	## Anything that owns the body or the shaft ends the carry on the spot.
	## Its own blend then starts from the pose already on screen.
	if combat == null or locomotion == null or weapon_visual == null:
		return true
	return (
		combat.current_weapon != CombatSystem.Weapon.GOAD
		or combat.is_attacking
		or combat.is_charging
		or combat.is_dead
		or _goad_release_live
		or _swing_arc_live
		or _hurt_reacting
		or is_mounted
		or _goad_stowing
		or _goad_draw_u < 0.999
	)


func _tick_sprint_carry(delta: float) -> void:
	if _carry_state != CARRY_NONE and _carry_must_abort():
		_carry_abort()
		return
	var want := _carry_wanted()
	match _carry_state:
		CARRY_NONE:
			if not want:
				return
			_carry_begin_in()
		CARRY_IN, CARRY_HOLD:
			if not want:
				_carry_begin_out()
			elif _carry_state == CARRY_IN:
				_carry_u = minf(1.0, _carry_u + delta / CARRY_IN_SEC)
				if _carry_u >= 1.0:
					_carry_state = CARRY_HOLD
		CARRY_OUT:
			if want:
				# Sprint again mid-return: carry back in from where it is.
				_carry_begin_in()
			else:
				_carry_out_u = minf(1.0, _carry_out_u + delta / CARRY_OUT_SEC)
	_carry_write_pose()
	_sync_weapon_to_hand()
	if _carry_state == CARRY_OUT and _carry_out_u >= 1.0:
		_carry_finish_out()


func _carry_abort() -> void:
	_carry_state = CARRY_NONE
	_carry_u = 0.0
	_carry_out_u = -1.0


func _carry_capture_pose() -> Dictionary:
	## What is on screen now: combat additives where they exist, otherwise the
	## offset the plain cycle wrote (so a walking leg is not frozen at rest).
	var pose := {}
	for k in CARRY_ARM_KEYS + CARRY_BODY_KEYS:
		if locomotion.has_combat_additive(k):
			pose[k] = locomotion.get_combat_additive(k)
		else:
			pose[k] = locomotion.cycle_offset(k)
	pose["root_drop"] = _tool_root_drop
	return pose


func _carry_live_slide() -> float:
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	return -goad.position.y if goad else _goad_grip_slide


func _carry_body_basis(world_basis: Basis) -> Basis:
	return (global_transform.basis.inverse() * world_basis).orthonormalized()


func _carry_palm() -> Vector3:
	var fore := locomotion.get_joint("right_forearm") as Node3D
	return fore.to_global(Vector3(0.0, -0.22, 0.0)) if fore else weapon_visual.global_position


func _carry_station_of(xf: Transform3D, slide: float, palm: Vector3) -> Array:
	## The palm's station on this stick (the slide that puts that point of the
	## wood at the weapon origin) and what is left over across the shaft, in
	## body axes. Re-expressing a hold this way changes nothing on screen.
	var axis := xf.basis.y.normalized()
	var along := (palm - xf.origin).dot(axis)
	var on_line := xf.origin + axis * along
	return [slide + along, global_transform.basis.inverse() * (on_line - palm)]


func _carry_palm_for(pose: Dictionary) -> Vector3:
	## Right palm if this pose were on screen. Leaves the screen as it was.
	var saved := {}
	for k in pose.keys():
		var key := String(k)
		if key == "weapon" or key == "root_drop" or key == "grip_slide":
			continue
		saved[key] = [locomotion.has_combat_additive(key), locomotion.get_combat_additive(key)]
		locomotion.set_combat_additive(key, pose[k])
	var saved_drop := _tool_root_drop
	locomotion.set_root_drop(float(pose.get("root_drop", 0.0)))
	var palm := _carry_palm()
	for key in saved.keys():
		if saved[key][0]:
			locomotion.set_combat_additive(key, saved[key][1])
		else:
			locomotion.set_combat_additive(key, locomotion.cycle_offset(key))
			locomotion.forget_combat_additive(key)
	locomotion.set_root_drop(saved_drop)
	return palm


func _carry_begin_in() -> void:
	# The guard blend tween (not a release) would keep writing the guard.
	if _arm_tween and _arm_tween.is_valid() and not _goad_release_live and not _swing_arc_live:
		_arm_tween.kill()
	_guard_blend_active = false
	_shaft_xf_blend = false
	_guard_face_held = &""
	_carry_from_pose = _carry_capture_pose()
	_carry_from_basis = _carry_body_basis(weapon_visual.global_transform.basis)
	var st_in := _carry_station_of(weapon_visual.global_transform, _carry_live_slide(), _carry_palm())
	_carry_from_slide = st_in[0]
	_carry_from_off = st_in[1]
	_carry_stats["from_off_max"] = maxf(float(_carry_stats.get("from_off_max", 0.0)), _carry_from_off.length())
	_carry_u = 0.0
	_carry_out_u = -1.0
	_carry_state = CARRY_IN
	_carry_in_path = _carry_pick_in_path()
	_tool_pose_active = false
	# The guard's planted lock would hold the stride back for a beat.
	locomotion.release_attack_lock()


func _carry_begin_out() -> void:
	_carry_to_guard = combat.is_shaft_blocking
	_carry_to_face = combat.shaft_guard_face if _carry_to_guard else &""
	if _carry_to_guard:
		_carry_to_pose = ToolStrikePoses.tool_shaft_guard_pose(_carry_to_face)
	else:
		_carry_to_pose = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	_carry_from_pose = _carry_capture_pose()
	_carry_from_basis = _carry_body_basis(weapon_visual.global_transform.basis)
	var st_out := _carry_station_of(weapon_visual.global_transform, _carry_live_slide(), _carry_palm())
	_carry_from_slide = st_out[0]
	_carry_from_off = st_out[1]
	# Where the two-hand hold seats the stick, without leaving it on screen.
	var st := _carry_state
	_carry_state = CARRY_NONE
	var xf := _peek_shaft_xf(_carry_to_pose)
	_carry_state = st
	var to_slide := float(_carry_to_pose.get("grip_slide", 0.0))
	var st_to := _carry_station_of(xf, to_slide, _carry_palm_for(_carry_to_pose))
	_carry_to_slide = st_to[0]
	_carry_to_off = st_to[1]
	_carry_stats["to_off_max"] = maxf(float(_carry_stats.get("to_off_max", 0.0)), _carry_to_off.length())
	_carry_to_basis = _carry_body_basis(xf.basis)
	_carry_out_u = 0.0
	_carry_state = CARRY_OUT


func _carry_finish_out() -> void:
	_carry_abort()
	if combat.current_weapon != CombatSystem.Weapon.GOAD:
		return
	if _carry_to_guard and combat.is_shaft_blocking:
		# Seated: hand the body to the guard exactly where the blend ended.
		_guard_blend_active = false
		_guard_face_held = _carry_to_face
		_apply_tool_pose(_carry_to_pose)
		_replay_guard_walk_legs()
		_shaft_pose_applied = true
	else:
		_apply_tool_pose(_carry_to_pose)
		_tool_pose_active = false
		_sync_weapon_to_hand()


func _carry_hold_pose() -> Dictionary:
	## Arms only. Built on the live cycle so the swing stays on the stride.
	var r: Vector3 = locomotion.cycle_offset("right_arm")
	var l: Vector3 = locomotion.cycle_offset("left_arm")
	var carry_swing := r.x * CARRY_ARM_SWING
	var fwd := clampf(l.x / 0.95, 0.0, 1.0)
	var back := clampf(-l.x / 0.95, 0.0, 1.0)
	return {
		"right_arm": Vector3(carry_swing + deg_to_rad(4.0), 0.0, deg_to_rad(CARRY_ARM_OUT_DEG)),
		"right_forearm": Vector3(deg_to_rad(CARRY_ELBOW_DEG) + maxf(0.0, carry_swing) * 0.5, 0.0, 0.0),
		"left_arm": Vector3(l.x, 0.0, deg_to_rad(PUMP_ARM_OUT_DEG)),
		"left_forearm": Vector3(deg_to_rad(PUMP_ELBOW_DEG + PUMP_ELBOW_FWD_DEG * fwd - PUMP_ELBOW_BACK_DEG * back), 0.0, 0.0),
	}


func _carry_slerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Quaternion.from_euler(a).slerp(Quaternion.from_euler(b), clampf(t, 0.0, 1.0)).get_euler()


func _carry_stepping() -> bool:
	return _guard_wants_steps(Vector2(velocity.x, velocity.z).length())


func _carry_write_pose() -> void:
	if _carry_state == CARRY_NONE:
		return
	var hold := _carry_hold_pose()
	if _carry_state == CARRY_OUT:
		var e := smoothstep(0.0, 1.0, _carry_out_u)
		var meet := smoothstep(CARRY_MEET_FROM, CARRY_MEET_TO, _carry_out_u)
		var stepping := _carry_stepping()
		for k in CARRY_ARM_KEYS + CARRY_BODY_KEYS:
			var to: Vector3 = _carry_to_pose.get(k, Vector3.ZERO)
			if k in CARRY_LEG_KEYS:
				if stepping:
					locomotion.forget_combat_additive(k)
					continue
				locomotion.set_combat_additive(k, _carry_slerp(locomotion.cycle_offset(k), to, e))
				continue
			var w := meet if k.begins_with("left_") else e
			var v := _carry_slerp(_carry_from_pose[k], to, w)
			if k == "right_arm":
				v.z += deg_to_rad(CARRY_OUT_BULGE_DEG) * sin(PI * e)
			locomotion.set_combat_additive(k, v)
		var drop := lerpf(float(_carry_from_pose.get("root_drop", 0.0)), float(_carry_to_pose.get("root_drop", 0.0)), e)
		_tool_root_drop = drop
		locomotion.set_root_drop(drop)
		return
	var s := 1.0 if _carry_state == CARRY_HOLD else smoothstep(0.0, 1.0, _carry_u)
	var bulge := deg_to_rad(CARRY_HIP_BULGE_DEG) * sin(PI * s)
	for k in CARRY_ARM_KEYS:
		var a: Vector3 = _carry_from_pose.get(k, hold[k]) if s < 1.0 else hold[k]
		var v := _carry_slerp(a, hold[k], s)
		if k == "right_arm":
			v.z += bulge
		locomotion.set_combat_additive(k, v)
	for k in CARRY_BODY_KEYS:
		if s >= 1.0:
			# Equal to the cycle now: let the run own the spine and the legs.
			locomotion.forget_combat_additive(k)
		else:
			locomotion.set_combat_additive(k, _carry_slerp(_carry_from_pose[k], locomotion.cycle_offset(k), s))
	var d := lerpf(float(_carry_from_pose.get("root_drop", 0.0)), 0.0, s)
	_tool_root_drop = d
	locomotion.set_root_drop(d)


func _carry_hold_basis() -> Basis:
	## Body-local: shaft along +Y of the weapon, pointing forward (-Z),
	## tip a little up and in. The wrist keeps it near level through the swing.
	var swing := clampf(locomotion.cycle_offset("right_arm").x / 0.95, -1.0, 1.0)
	var pitch := deg_to_rad(CARRY_PITCH_DEG - CARRY_SWING_PITCH_DEG * swing)
	var axis := Basis(Vector3.UP, deg_to_rad(CARRY_YAW_IN_DEG)) * (Basis(Vector3.RIGHT, pitch) * Vector3(0.0, 0.0, -1.0))
	axis = axis.normalized()
	var x := axis.cross(Vector3.UP).normalized()
	var z := x.cross(axis).normalized()
	return Basis(x, axis, z)


func _carry_swing_path(from_b: Basis, to_b: Basis, t: float, long_way: bool) -> Basis:
	## Turn the shaft's direction along one arc (short or long way round),
	## then settle its roll about the wood. Exact at both ends.
	t = clampf(t, 0.0, 1.0)
	if t >= 1.0:
		return to_b
	var a := from_b.y.normalized()
	var b := to_b.y.normalized()
	var n := a.cross(b)
	var theta := acos(clampf(a.dot(b), -1.0, 1.0))
	if n.length() < 1e-4:
		n = from_b.x.normalized()
	n = n.normalized()
	var full := theta
	if long_way:
		n = -n
		full = TAU - theta
	var mid := Basis(n, full * t) * from_b
	var end_b := Basis(n, full) * from_b
	var ex := end_b.x - b * end_b.x.dot(b)
	var tx := to_b.x - b * to_b.x.dot(b)
	var roll := 0.0
	if ex.length() > 1e-4 and tx.length() > 1e-4:
		roll = ex.normalized().signed_angle_to(tx.normalized(), b)
	return (Basis(mid.y.normalized(), roll * t) * mid).orthonormalized()


func _carry_in_basis(hold_b: Basis, s: float, path: int) -> Basis:
	if path != 2:
		return _carry_swing_path(_carry_from_basis, hold_b, s, path == 1)
	# Up beside the right shoulder, then down along the side.
	var up := Vector3(0.55, 0.80, -0.15).normalized()
	var x := up.cross(Vector3(0.0, 0.0, -1.0)).normalized()
	var w := Basis(x, up, x.cross(up).normalized())
	if s < 0.5:
		return _carry_swing_path(_carry_from_basis, w, s * 2.0, false)
	return _carry_swing_path(w, hold_b, (s - 0.5) * 2.0, false)


func _carry_pick_in_path() -> int:
	## Sample each path along the coming blend (palm eased toward the carry
	## hold) and keep the one that meets the body least. Short arc on a tie.
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	if goad == null:
		return 0
	var saved_xf := weapon_visual.global_transform
	var saved_goad := goad.position
	var palm_now := _carry_palm()
	var palm_hold := _carry_palm_for(_carry_hold_pose())
	var hold_b := _carry_hold_basis()
	var hits := [0, 0, 0]
	for i in 3:
		for t in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
			var sm := smoothstep(0.0, 1.0, t)
			var b := _carry_in_basis(hold_b, sm, i)
			weapon_visual.global_transform = Transform3D(global_transform.basis * b, palm_now.lerp(palm_hold, sm))
			goad.position = Vector3(0.0, -lerpf(_carry_from_slide, CARRY_GRIP_SLIDE, sm), 0.0)
			hits[i] += _carry_shaft_hits(goad, _carry_clear_meshes(sm >= 0.5))
	weapon_visual.global_transform = saved_xf
	goad.position = saved_goad
	var best := 0
	for i in 3:
		if hits[i] < hits[best]:
			best = i
	return best


func _carry_quat_lerp(a: Basis, b: Basis, t: float) -> Basis:
	return Basis(Quaternion(a.orthonormalized()).slerp(Quaternion(b.orthonormalized()), clampf(t, 0.0, 1.0)))


func _place_carry_shaft() -> void:
	## Palm-pinned: the weapon origin is already on the right palm (sync).
	## Only the stick's direction and the palm's station along it blend.
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	if goad == null:
		return
	var basis_l: Basis
	var slide: float
	var off := Vector3.ZERO
	var left_free := true
	if _carry_state == CARRY_OUT:
		var e := smoothstep(0.0, 1.0, _carry_out_u)
		basis_l = _carry_quat_lerp(_carry_from_basis, _carry_to_basis, e)
		slide = lerpf(_carry_from_slide, _carry_to_slide, e)
		off = _carry_from_off.lerp(_carry_to_off, e)
		left_free = _carry_out_u < CARRY_MEET_FROM
	else:
		var s := 1.0 if _carry_state == CARRY_HOLD else smoothstep(0.0, 1.0, _carry_u)
		basis_l = _carry_in_basis(_carry_hold_basis(), s, _carry_in_path)
		slide = lerpf(_carry_from_slide, CARRY_GRIP_SLIDE, s)
		off = _carry_from_off.lerp(Vector3.ZERO, s)
		# The left hand is still letting go early in the blend; it is not
		# an obstacle for the wood it was just holding.
		left_free = s >= 0.5
	var origin := _carry_palm() + global_transform.basis * off
	weapon_visual.global_transform = Transform3D(global_transform.basis * basis_l, origin)
	goad.position = Vector3(0.0, -slide, 0.0)
	goad.rotation = Vector3.ZERO
	_goad_grip_slide = slide
	_carry_stats["frames"] = int(_carry_stats["frames"]) + 1
	_carry_clear_shaft(goad, left_free)
	if _carry_state == CARRY_OUT and _carry_out_u >= CARRY_MEET_FROM:
		# The left hand meets the wood as it comes forward. The blended arm is
		# the reach; the grip solve lands the palm on the nearest point.
		var meet := smoothstep(CARRY_MEET_FROM, CARRY_MEET_TO, _carry_out_u)
		var reach_arm := locomotion.get_combat_additive("left_arm")
		var reach_fore := locomotion.get_combat_additive("left_forearm")
		_grip_shaft_with(goad, "left_arm", "left_forearm", 0.24)
		locomotion.set_combat_additive("left_arm", _carry_slerp(reach_arm, locomotion.get_combat_additive("left_arm"), meet))
		locomotion.set_combat_additive("left_forearm", _carry_slerp(reach_fore, locomotion.get_combat_additive("left_forearm"), meet))


func _carry_clear_meshes(left_free: bool) -> Array:
	if _carry_meshes.is_empty():
		var visual_node := get_node_or_null("Visual") as Node3D
		if visual_node:
			for mn in ["TorsoMesh", "TunicSkirt", "Cloak", "HeadMesh", "Belt", "HipsMesh", "ShoulderL", "ShoulderR"]:
				var m := visual_node.find_child(mn, true, false) as MeshInstance3D
				if m:
					_carry_meshes.append([mn, m])
		for jn in ["left_thigh", "right_thigh", "left_shin", "right_shin", "left_arm", "left_forearm"]:
			var j := locomotion.get_joint(jn)
			if j == null:
				continue
			for c in j.get_children():
				if c is MeshInstance3D:
					_carry_meshes.append([jn, c])
	if left_free:
		return _carry_meshes
	var out: Array = []
	for pair in _carry_meshes:
		if not String(pair[0]).begins_with("left_arm") and not String(pair[0]).begins_with("left_forearm"):
			out.append(pair)
	return out


func _carry_shaft_hits(goad: Node3D, meshes: Array) -> int:
	var butt := goad.to_global(Vector3(0.0, -0.255, 0.0))
	var tip := goad.to_global(Vector3(0.0, 1.13, 0.0))
	var hits := 0
	for pair in meshes:
		var mi: MeshInstance3D = pair[1]
		if not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.get_aabb().grow(CARRY_CLEAR_MARGIN)
		var inv := mi.global_transform.affine_inverse()
		for i in 28:
			if box.has_point(inv * butt.lerp(tip, float(i) / 27.0)):
				hits += 1
				break
	return hits


func _carry_low_point(goad: Node3D) -> float:
	var butt := goad.to_global(Vector3(0.0, -0.255, 0.0))
	var tip := goad.to_global(Vector3(0.0, 1.13, 0.0))
	return minf(butt.y, tip.y) - global_position.y


func _carry_clear_shaft(goad: Node3D, left_free: bool) -> void:
	## The carry is authored clear of the body and legs. If a stride or a
	## blend still meets one, turn the stick about the palm (the grip stays)
	## by the smallest yaw / pitch that clears; keep the butt off the ground.
	var meshes := _carry_clear_meshes(left_free)
	var low := _carry_low_point(goad)
	if low < CARRY_GROUND_CLEAR:
		var axis := weapon_visual.global_transform.basis.y.normalized()
		var side := axis.cross(Vector3.UP)
		if side.length() > 0.01:
			var lift := (CARRY_GROUND_CLEAR - low) / 0.70
			var sgn := 1.0 if axis.y >= 0.0 else -1.0
			# Raise whichever end is low (butt when the tip points up).
			var ang := -sgn * clampf(lift, 0.0, 0.5)
			weapon_visual.global_basis = Basis(side.normalized(), ang) * weapon_visual.global_basis
			_carry_stats["ground"] = int(_carry_stats["ground"]) + 1
	if _carry_shaft_hits(goad, meshes) == 0:
		return
	var base := weapon_visual.global_basis
	var up := Vector3.UP
	var right := global_transform.basis.x.normalized()
	var best := base
	var found := false
	for mag in [4.0, 8.0, 12.0, 16.0, 22.0, 28.0, 36.0, 45.0]:
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]:
			var yaw := deg_to_rad(mag * dir.x)
			var pitch := deg_to_rad(mag * dir.y)
			var cand := Basis(up, yaw) * Basis(right, pitch) * base
			weapon_visual.global_basis = cand
			if _carry_low_point(goad) < CARRY_GROUND_CLEAR * 0.5:
				continue
			if _carry_shaft_hits(goad, meshes) == 0:
				best = cand
				found = true
				break
		if found:
			break
	weapon_visual.global_basis = best
	if not found:
		# The palm itself is against the body mid-blend: no turn about it
		# clears. Ease the stick out and forward a few cm and let the right
		# hand follow it, rather than leave wood in the skirt.
		var base_pos := weapon_visual.global_position
		var out_x := global_transform.basis.x.normalized()
		var fwd := -global_transform.basis.z.normalized()
		for mag in [0.03, 0.06, 0.09, 0.12, 0.15]:
			for d in [out_x, (out_x + fwd).normalized(), fwd]:
				weapon_visual.global_position = base_pos + d * mag
				if _carry_shaft_hits(goad, meshes) == 0:
					found = true
					break
			if found:
				break
		if found:
			_grip_shaft_at_y(goad, "right_arm", "right_forearm", _goad_grip_slide)
		else:
			weapon_visual.global_position = base_pos
	if found:
		_carry_stats["cleared"] = int(_carry_stats["cleared"]) + 1
	else:
		_carry_stats["residual"] = int(_carry_stats["residual"]) + 1


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


func _to_body(xf: Transform3D) -> Transform3D:
	## World hold -> player-local, so a shaft blend rides along while walking.
	return global_transform.affine_inverse() * xf


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
	# Holds are stored body-local (see _to_body); walk them with the body.
	from_xf = global_transform * from_xf
	to_xf = global_transform * to_xf
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
	# Shared clearance solver (same as the swing). Charge plant grips are the
	# spaced palm stations; guard blends grip the nearest point.
	var charging_plant := combat != null and combat.is_charging and not combat.is_attacking
	var stations := Vector2(0.14, 0.46) if charging_plant else Vector2(NAN, NAN)
	_clear_shaft_node(shaft, stations, charging_plant and _is_top_goad_charge(_shaft_aim_axes()))
	if _swing_arc_live and _swing_arc_interior and int(_clear_last.get("after", 0)) > 0:
		# Fallback only: per-face bows when the solver could not clear.
		_bow_swing_off_the_chest(shaft)
		_pull_shaft_into_reach(shaft)
		_bow_swing_clear_of_body(shaft)
	# Charged wind-up: spaced palms. Guard look keeps nearest-point grip.
	if charging_plant:
		_grip_shaft_at_y(shaft, "right_arm", "right_forearm", 0.14)
		_grip_shaft_at_y(shaft, "left_arm", "left_forearm", 0.46)
	else:
		_grip_shaft_with(shaft, "right_arm", "right_forearm", 0.30)
		_grip_shaft_with(shaft, "left_arm", "left_forearm", 0.24)


## Look stick with camera pitch folded in. Mouse left (−X) = player left.
## Pitch signs follow the camera: negative X = ground → low; positive X = sky → high.
func _look_stick_from(delta: Vector2) -> Vector2:
	var mx := delta.x
	var my := delta.y
	if pivot:
		var pitch_deg := rad_to_deg(pivot.rotation.x)
		if pitch_deg <= LOOK_PITCH_GROUND:
			# Looking at the ground. Keep mouse-down (+my); deepen so residual mx
			# cannot steal right/left while the camera is aimed at the dirt.
			var depth := clampf((-pitch_deg + LOOK_PITCH_GROUND) / 50.0, 0.0, 1.0)
			my = maxf(my, lerpf(LOOK_AIM_DEADZONE, 56.0, depth))
		elif pitch_deg >= LOOK_PITCH_SKY:
			var depth_up := clampf((pitch_deg - LOOK_PITCH_SKY) / 33.0, 0.0, 1.0)
			my = minf(my, -lerpf(LOOK_AIM_DEADZONE, 56.0, depth_up))
	return Vector2(mx, my)


## Equal 90° axis-dominant quadrants outside a shared square deadzone.
## Center → chest. |mx| >= |my| → left/right; else high/low. Ties → horizontal.
func _resolve_look_face_from(delta: Vector2) -> StringName:
	var stick := _look_stick_from(delta)
	var mx := stick.x
	var my := stick.y
	if absf(mx) < LOOK_AIM_DEADZONE and absf(my) < LOOK_AIM_DEADZONE:
		return &"chest"
	if absf(mx) >= absf(my):
		if mx < 0.0:
			return &"left"
		return &"right"
	if my < 0.0:
		return &"high"
	return &"low"


## Look picks the guard face. No button. Same zones as charge/swing.
##   look left  → left    look right → right
##   look up    → high    look down  → low (guard only, not a jab)
##   centered   → chest
func _resolve_shaft_guard_face() -> StringName:
	return _resolve_look_face_from(_tool_aim_delta)


## Cardinal aim axes for a look face. High is pure overhead (−Y).
func _aim_axes_for_look_face(face: StringName) -> Vector2:
	match face:
		&"left":
			return Vector2(-1.0, 0.0)
		&"right":
			return Vector2(1.0, 0.0)
		&"high":
			return Vector2(0.0, -1.0)
		&"low":
			return Vector2(0.0, 1.0)
		_:
			return Vector2.ZERO


## Continuous release axes from the strike that was actually committed.
## Ignores live look so a pitch fold cannot zero a left/top shaft swing.
func _aim_axes_for_strike(direction: CombatSystem.StrikeDirection) -> Vector2:
	match direction:
		CombatSystem.StrikeDirection.LEFT:
			return Vector2(-1.0, 0.0)
		CombatSystem.StrikeDirection.RIGHT:
			return Vector2(1.0, 0.0)
		CombatSystem.StrikeDirection.BOTTOM:
			return Vector2(0.0, 1.0)
		_:
			return Vector2(0.0, -1.0)


func _strike_direction_for_look_face(face: StringName) -> CombatSystem.StrikeDirection:
	match face:
		&"left":
			return CombatSystem.StrikeDirection.LEFT
		&"right":
			return CombatSystem.StrikeDirection.RIGHT
		&"low":
			# Shaft swings never jab; low press is handled before charge.
			return CombatSystem.StrikeDirection.TOP
		_:
			return CombatSystem.StrikeDirection.TOP


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
	if _sprinting:
		return
	var hatchet := combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet
	var goad := combat.current_weapon == CombatSystem.Weapon.GOAD
	# Already looking down: one uncharged jab. Do not start a shaft charge.
	if goad and _resolve_shaft_guard_face() == &"low":
		_fire_goad_jab(&"light")
		return
	if hatchet or goad:
		# Goad keeps the look you already had; hatchet aim starts neutral (top).
		_charge_aim_delta = _tool_aim_delta if goad else Vector2.ZERO
		_charge_look_face = _resolve_look_face_from(_charge_aim_delta) if goad else &"chest"
		_hatchet_charge_armed = true
		if not combat.begin_charge():
			_hatchet_charge_armed = false
			var fallback := _resolve_tool_strike_direction() if goad else CombatSystem.StrikeDirection.TOP
			if not combat.try_attack(&"light", fallback):
				_arm_attack_buffer(&"light", _resolve_look_face_from(_tool_aim_delta) if goad else &"chest")
		else:
			_apply_charge_direction_from_input()
	else:
		var face := _resolve_look_face_from(_tool_aim_delta)
		if not combat.try_attack(&"light", _resolve_tool_strike_direction()):
			_arm_attack_buffer(&"light", face)
		_tool_aim_delta = Vector2.ZERO


func _release_hatchet_or_ignore() -> void:
	_atk_buf_down = false
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
	if _sprinting:
		return
	# Hatchet: hold-release only — RMB does not instant full-power.
	if combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet:
		return
	# Goad RMB is the same uncharged point jab at any look. Not a heavy swing.
	if combat.current_weapon == CombatSystem.Weapon.GOAD:
		_fire_goad_jab(&"heavy")
		return
	if combat.is_charging:
		combat.cancel_charge()
		_hatchet_charge_armed = false
	var face := _resolve_look_face_from(_tool_aim_delta)
	if not combat.try_attack(&"heavy", _resolve_tool_strike_direction()):
		_arm_attack_buffer(&"heavy", face)
	_tool_aim_delta = Vector2.ZERO


func _fire_goad_jab(action: StringName = &"heavy") -> void:
	## One uncharged point. Press only — the caller is an action press, so a
	## held button does not charge or repeat. Look is left alone so the low
	## guard can return after the jab.
	if combat == null or combat.current_weapon != CombatSystem.Weapon.GOAD:
		return
	if _sprinting:
		return
	if combat.is_charging:
		combat.cancel_charge()
		_hatchet_charge_armed = false
	if not combat.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM):
		_arm_attack_buffer(action, &"low" if action == &"light" else _resolve_look_face_from(_tool_aim_delta))


# --- Attack input buffer ---------------------------------------------------

func _attack_swing_live() -> bool:
	return combat != null and (combat.is_attacking or _goad_release_live)


func _arm_attack_buffer(action: StringName, face: StringName) -> void:
	## Only a press refused because the previous swing is still live. Not while
	## sprinting or with Shift held. A newer press replaces the older one.
	if combat == null or combat.is_dead or is_mounted or is_dragging():
		return
	if _sprinting or Input.is_action_pressed("sprint"):
		return
	if not _attack_swing_live():
		return
	_atk_buf_until = _now_sec() + ATTACK_BUFFER_SEC
	_atk_buf_action = action
	_atk_buf_face = face
	_atk_buf_down = true
	_atk_buf_stats["armed"] = int(_atk_buf_stats["armed"]) + 1


func _discard_attack_buffer(reason: StringName = &"") -> void:
	if _atk_buf_until < 0.0:
		return
	_atk_buf_until = -1.0
	_atk_buf_action = &""
	_atk_buf_face = &""
	if reason == &"timeout":
		_atk_buf_stats["expired"] = int(_atk_buf_stats["expired"]) + 1
	else:
		_atk_buf_stats["discarded"] = int(_atk_buf_stats["discarded"]) + 1


func has_buffered_attack() -> bool:
	return _atk_buf_until >= 0.0


func _now_sec() -> float:
	# Physics time, not wall time: the window must not shrink under frame catch-up.
	return float(Engine.get_physics_frames()) / float(maxi(Engine.physics_ticks_per_second, 1))


func _tick_attack_buffer() -> void:
	## Top of _physics_process. Fires once neither the combat swing nor the
	## goad release is live and recovery is (nearly) spent.
	if _atk_buf_until < 0.0:
		return
	if combat == null or combat.is_dead:
		_discard_attack_buffer(&"dead")
		return
	if is_mounted:
		_discard_attack_buffer(&"mount")
		return
	if is_dragging():
		_discard_attack_buffer(&"drag")
		return
	if _sprinting or Input.is_action_pressed("sprint"):
		_discard_attack_buffer(&"sprint")
		return
	if combat.is_attacking or _goad_release_live or _swing_arc_live or combat.attack_recovery_left > 0.05:
		if _now_sec() > _atk_buf_until:
			_discard_attack_buffer(&"timeout")
		return
	if combat.is_charging:
		# A fresh press already started a charge in the settle tail.
		_discard_attack_buffer(&"superseded")
		return
	var action := _atk_buf_action
	var face := _atk_buf_face
	var held := _atk_buf_down
	_atk_buf_until = -1.0
	_atk_buf_action = &""
	_atk_buf_face = &""
	_atk_buf_stats["fired"] = int(_atk_buf_stats["fired"]) + 1
	_atk_buf_last_fire_frame = Engine.get_physics_frames()
	_fire_buffered_attack(action, face, held)


func _aim_delta_for_look_face(face: StringName) -> Vector2:
	match face:
		&"left":
			return Vector2(-48.0, 0.0)
		&"right":
			return Vector2(48.0, 0.0)
		&"high":
			return Vector2(0.0, -48.0)
		&"low":
			return Vector2(0.0, 48.0)
	return Vector2.ZERO


func _fire_buffered_attack(action: StringName, face: StringName, held: bool) -> void:
	## Resolve from the face captured at the press, not the look now.
	var goad := combat.current_weapon == CombatSystem.Weapon.GOAD
	var hatchet := combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet
	if goad and (action == &"heavy" or action == &"jab" or face == &"low"):
		combat.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM)
		return
	if goad or hatchet:
		if held:
			_charge_aim_delta = _aim_delta_for_look_face(face) if goad else Vector2.ZERO
			_charge_look_face = face if goad else &"chest"
			_hatchet_charge_armed = true
			if combat.begin_charge():
				_apply_charge_direction_from_input()
				return
			_hatchet_charge_armed = false
		var dir := _strike_direction_for_look_face(face) if goad else CombatSystem.StrikeDirection.TOP
		combat.try_attack(&"light", dir)
		return
	combat.try_attack(action if action == &"heavy" else &"light", _strike_direction_for_look_face(face))


func _resolve_tool_strike_direction() -> CombatSystem.StrikeDirection:
	## Knife tap, and the goad fallback if a charge cannot start.
	## Same equal zones as look-guard. Look-down jab is handled before charge.
	return _strike_direction_for_look_face(_resolve_look_face_from(_tool_aim_delta))


func _apply_charge_direction_from_input() -> void:
	if combat == null or not combat.is_charging:
		return
	_charge_look_face = _resolve_look_face_from(_charge_aim_delta)
	combat.set_charge_direction(_resolve_strike_direction())


func _resolve_strike_direction() -> CombatSystem.StrikeDirection:
	## Same equal look zones as the shaft guard. Low is not a shaft cardinal.
	return _strike_direction_for_look_face(_resolve_look_face_from(_charge_aim_delta))


func _on_charge_updated(ratio: float, direction: StringName) -> void:
	## Goad: whole-body windup. Hatchet: arm + torso cock (unchanged).
	if combat == null or not combat.is_charging or combat.is_attacking:
		return
	if combat.current_weapon == CombatSystem.Weapon.GOAD:
		_apply_goad_charge_pose(ratio, direction)
		return
	if _arm_tween and _arm_tween.is_valid():
		_abort_goad_release_tween()
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
	# Release owns the body. Killing the arc tween here left _swing_arc_live /
	# _goad_release_live set, so the wind-up froze and sync skipped seating
	# (shaft clipped on move). Charge updates must not interrupt a swing.
	if _goad_release_live or _swing_arc_live:
		return
	if combat and combat.is_attacking:
		return
	if _arm_tween and _arm_tween.is_valid():
		_abort_goad_release_tween()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_guard_blend_active = false
	# Cardinal direction still picks the strike on release. The body tracks
	# the mouse continuously so the weapon is already on that side.
	var aim := _shaft_aim_axes()
	var full: Dictionary = ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, 1.0)
	if not _charge_from_ready:
		_charge_from_pose = _current_tool_pose(full)
		_charge_from_xf = _to_body(weapon_visual.global_transform if weapon_visual else global_transform)
		_charge_from_ready = true
		_guard_face_held = &""
	var blend := ToolStrikePoses._charge_blend(ratio)
	_shaft_from_xf = _charge_from_xf
	_shaft_to_xf = _to_body(_peek_shaft_xf(full))
	# Top hold is a bar over the head in the committed pose. The authored
	# cock reads as the right chamber. Left and right charges keep the peek.
	# Measure after the body is in that pose, or the bar is built on the old head.
	if _is_top_goad_charge(aim):
		_apply_tool_pose(full)
		_shaft_to_xf = _to_body(_overhead_charge_xf())
	_shaft_xf_u = blend
	_shaft_xf_blend = true
	_apply_blended_pose(_charge_from_pose, full, blend, false)
	_shaft_xf_blend = false
	if locomotion:
		locomotion.lock_attack(0.08)


func _is_top_goad_charge(_aim: Vector2) -> bool:
	## Overhead bar when the shared look face is high (not a thin |aim.x| band).
	return _resolve_look_face_from(_charge_aim_delta) == &"high"


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
	var bar := mid + Vector3.UP * 0.62 + face * 0.18
	# Never closer than a hand over the skull.
	var crown_clear := head.global_position.y + 0.48
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
	## Shaft charge/swing: same equal look face as the guard, snapped to cardinals.
	## High → pure overhead (−Y). Look-down is clamped off for shaft holds.
	var face := _resolve_look_face_from(_charge_aim_delta)
	var aim := _aim_axes_for_look_face(face)
	aim.y = minf(aim.y, 0.0)
	return aim


func _goad_aim_axes() -> Vector2:
	## Cardinal axes from the shared look-face zones (left = local −X).
	return _aim_axes_for_look_face(_resolve_look_face_from(_charge_aim_delta))


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
	# A swap in the goad settle tail (is_attacking already false) left the arc
	# tween writing the old shaft, and a later bare kill stuck its flags.
	_abort_goad_release_tween()
	_discard_attack_buffer(&"weapon")
	_carry_abort()
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
		_abort_goad_release_tween()
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
	# Goad settle is visual past combat recovery — keep the plant through it.
	var goad_lock := windup + active + recovery
	if combat.current_weapon == CombatSystem.Weapon.GOAD:
		goad_lock += GOAD_SETTLE_SEC
	locomotion.lock_attack(goad_lock)
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
		_abort_goad_release_tween()
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
	# Abort any prior release BEFORE arming live flags (abort clears them).
	if _arm_tween and _arm_tween.is_valid():
		_abort_goad_release_tween()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()
	_goad_release_live = true
	# Committed strike owns the arc. Re-resolving look on release let camera
	# pitch fold left/top into low, clamp aim to (0,0), and drop the swing.
	var jab := combat.last_strike_direction() == CombatSystem.StrikeDirection.BOTTOM
	var aim := _aim_axes_for_strike(combat.last_strike_direction())
	if jab:
		aim = Vector2(0.0, 1.0)
	_swing_arc_aim = aim
	var pose_idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var pose_windup: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"windup")
	var pose_follow: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"follow")
	# Uncharged taps start from the live ready/guard, not a cocked pose — that
	# cock is what made the first continuous sample look like a teleport.
	var start_pose: Dictionary = _current_tool_pose(pose_idle if kind == &"light" and not jab else pose_windup)
	if jab:
		start_pose = _current_tool_pose(pose_idle)
	var phases: Dictionary = combat.swing_phase_durations(kind, windup, active, GOAD_SETTLE_SEC)
	_tool_pose_active = true
	# Every goad strike — charged, uncharged L/R/top, and jab — rides one
	# continuous shaft curve so mid-arc / mid-thrust reads. Charged stays snappy
	# (half phases). Light/jab keep readable travel floors so they do not snap.
	_swing_arc_live = true
	var windup_move: float
	var to_contact: float
	var follow_move: float
	if kind == &"heavy":
		windup_move = float(phases["windup_move"]) * 0.5
		to_contact = float(phases["to_contact"]) * 0.5
		follow_move = float(phases["follow"]) * 0.5
	else:
		windup_move = maxf(0.14, float(phases["windup_move"]) + float(phases["windup_hold"]) * 0.35)
		to_contact = maxf(0.14, float(phases["to_contact"]) + float(phases["contact_hold"]) * 0.35)
		follow_move = maxf(0.12, float(phases["follow"]))
		if jab:
			windup_move = maxf(0.12, windup_move)
			to_contact = maxf(0.16, to_contact)
			follow_move = maxf(0.12, follow_move)
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
	# The guard may sit behind the ear. Side swings lift onto the face side.
	# A top charge is already a bar over the skull — that lift shoved it
	# forward of the hands and the first sample fell to chest height.
	# Pure top aim (high face) keeps the overhead bar; do not face-lift it away.
	var overhead_start := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y < -0.5
	var jab_start := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y > 0.5
	_jab_mirror = jab_start and live_butt.x < 0.0
	var bar_high := minf(live_butt.y, live_tip.y) > 1.55 and absf(live_butt.y - live_tip.y) < 0.20
	# Jab keeps the live chamber; a face-lift turned the thrust into a side sweep.
	if not (overhead_start or bar_high or jab_start):
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
	# Bare kill on purpose: _play_goad_release already aborted the previous
	# release and has just armed this one's flags; abort would clear them.
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	_swing_arc_total = total
	_arm_tween = create_tween()
	# Survive process-mode blips while sprinting out of the swing.
	_arm_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_arm_tween.tween_method(_sample_continuous_goad_swing, 0.0, 1.0, total)
	_arm_tween.tween_callback(_finish_goad_return)


func _continuous_swing_keys(aim: Vector2) -> Array:
	## Later samples of one face-side arc. The live guard is the first sample.
	## Left sweeps to the player's right, right sweeps to the player's left,
	## top chops straight down from the overhead bar. Look-down jab is a forward
	## point thrust (bottom weight). A diagonal is the blend.
	var w_left := clampf(-aim.x, 0.0, 1.0)
	var w_right := clampf(aim.x, 0.0, 1.0)
	var w_top := clampf(-aim.y, 0.0, 1.0)
	var w_bot := clampf(aim.y, 0.0, 1.0)
	var sum := w_left + w_right + w_top + w_bot
	if sum < 0.001:
		w_top = 1.0
		sum = 1.0
	w_left /= sum
	w_right /= sum
	w_top /= sum
	w_bot /= sum
	# Side arcs stay in front of the torso (−Z). Mid keys used to park the
	# butt on the centerline so the tip chord cut through the chest.
	var left: Array = [
		_swing_line(Vector3(-0.24, 1.32, -0.52), Vector3(-0.70, 0.52, -0.58)),
		_swing_line(Vector3(-0.16, 1.22, -0.78), Vector3(0.55, 0.18, -0.98)),
		_swing_line(Vector3(-0.06, 1.14, -0.72), Vector3(0.60, -0.30, -0.88)),
		_swing_line(Vector3(0.02, 1.14, -0.58), Vector3(0.50, -0.48, -0.68)),
	]
	var right: Array = [
		_swing_line(Vector3(0.24, 1.32, -0.52), Vector3(0.70, 0.52, -0.58)),
		_swing_line(Vector3(0.16, 1.22, -0.78), Vector3(-0.55, 0.18, -0.98)),
		_swing_line(Vector3(0.06, 1.14, -0.72), Vector3(-0.60, -0.30, -0.88)),
		_swing_line(Vector3(-0.02, 1.14, -0.58), Vector3(-0.50, -0.48, -0.68)),
	]
	# Overhead chop. Key 0 stays a high bar (matches the charge hold). Mid/end
	# leave the sagittal centerline — past the face/right of the skull — so
	# the tip does not drop through the head and torso.
	var top: Array = [
		_swing_line(Vector3(0.22, 1.70, -0.28), Vector3(0.55, 0.04, -0.55)),
		_swing_line(Vector3(0.30, 1.52, -0.55), Vector3(0.14, -0.52, -0.90)),
		_swing_line(Vector3(0.26, 1.36, -0.62), Vector3(0.10, -0.85, -0.68)),
		_swing_line(Vector3(0.18, 1.26, -0.52), Vector3(0.06, -0.98, -0.40)),
	]
	# Uncharged / look-down jab: chamber → mid-thrust → extend → recover.
	# Spear thrust: the butt rides OUTSIDE the right flank and the tip finishes
	# on the centre line. The chest turns right (_jab_chest_yaw) so the left
	# palm reaches the wood. The old keys ran the wood straight down the body
	# centreline, out of reach of both palms (~0.53 m arms): grips skipped,
	# hands stayed at the body and the shaft read as threading the tunic.
	var jab_dir := Vector3(-0.35, -0.10, -0.93)
	var bottom: Array = [
		_swing_line(Vector3(0.53, 1.30, 0.36), jab_dir),
		_swing_line(Vector3(0.48, 1.28, 0.25), jab_dir),
		_swing_line(Vector3(0.45, 1.27, 0.18), jab_dir),
		_swing_line(Vector3(0.40, 1.00, -0.36), Vector3(-0.92, 0.20, -0.33)),
	]
	if _jab_mirror:
		var flip := Vector3(-1.0, 1.0, 1.0)
		for k in bottom.size():
			bottom[k] = [(bottom[k][0] as Vector3) * flip, (bottom[k][1] as Vector3) * flip]
	var out: Array = []
	for i in 4:
		var butt: Vector3 = (left[i][0] as Vector3) * w_left + (right[i][0] as Vector3) * w_right + (top[i][0] as Vector3) * w_top + (bottom[i][0] as Vector3) * w_bot
		var tip: Vector3 = (left[i][1] as Vector3) * w_left + (right[i][1] as Vector3) * w_right + (top[i][1] as Vector3) * w_top + (bottom[i][1] as Vector3) * w_bot
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
	# The arc is authored in player space. Re-anchor it to the body every
	# sample so walking (or turning) through the swing carries the wood along
	# instead of leaving it at the world spot the release began.
	_swing_frame = global_transform
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
	# Side swings pull the wood into reach after they leave the guard.
	# Top keeps the overhead bar up at the first samples — a pull toward the
	# shoulders was dropping it onto the chest. Later samples may pull, but
	# only sideways / forward, never lowering the high end of the shaft.
	var overhead := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y < -0.5
	var jabbing := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y > 0.5
	if u > 0.02 and not jabbing:
		var high_before := maxf(butt_w.y, tip_w.y)
		var held: Array = _bring_shaft_to_both_hands(butt_w, tip_w)
		if overhead:
			var high_after := maxf((held[0] as Vector3).y, (held[1] as Vector3).y)
			if high_after + 0.04 >= high_before:
				butt_w = held[0]
				tip_w = held[1]
			# else keep the high line; grip still reaches for it
		else:
			butt_w = held[0]
			tip_w = held[1]
	# Jab keys are authored clear of the flank (see _continuous_swing_keys).
	# The generic slide's neck zone caught the flank line and shoved it wide.
	if not jabbing:
		var cleared: Array = _slide_line_off_body(butt_w, tip_w)
		butt_w = cleared[0]
		tip_w = cleared[1]
	# Side: seat at shoulders. Top: high seat LAST along the clear-key axis —
	# a follow-up body slide shoved stations back out of reach.
	if overhead:
		var seated_top: Array = _seat_overhead_shaft_at_shoulders(butt_w, tip_w)
		butt_w = seated_top[0]
		tip_w = seated_top[1]
		var head := locomotion.get_joint("head") as Node3D if locomotion else null
		if head:
			var face_h := -_swing_frame.basis.z
			face_h.y = 0.0
			if face_h.length_squared() > 0.0001:
				face_h = face_h.normalized()
			var need := 0.0
			for i in 12:
				var p: Vector3 = butt_w.lerp(tip_w, float(i) / 11.0)
				var hd := p.distance_to(head.global_position)
				if hd < 0.38:
					need = maxf(need, 0.38 - hd)
			if need > 0.001:
				butt_w += face_h * minf(need, 0.08)
				tip_w += face_h * minf(need, 0.08)
	elif jabbing:
		# No shoulder seat (bent it into a sweep) and no body slide (shoved it
		# wide). The authored flank line already clears the tunic.
		pass
	else:
		var seated: Array = _seat_charged_shaft_at_shoulders(butt_w, tip_w)
		butt_w = seated[0]
		tip_w = seated[1]
	var goad := _place_continuous_shaft(butt_w, tip_w)
	if goad:
		if jabbing and _jab_mirror:
			# Mirrored thrust: the left hand is the rear (butt) hand.
			_grip_shaft_at_y(goad, "left_arm", "left_forearm", 0.14)
			_grip_shaft_at_y(goad, "right_arm", "right_forearm", 0.46)
		else:
			_grip_shaft_at_y(goad, "right_arm", "right_forearm", 0.14)
			_grip_shaft_at_y(goad, "left_arm", "left_forearm", 0.46)


func _continuous_line_at(u: float) -> Array:
	var i := 0
	var last := _swing_key_u.size() - 2
	while i < last and u > _swing_key_u[i + 1]:
		i += 1
	var span := maxf(_swing_key_u[i + 1] - _swing_key_u[i], 0.0001)
	var t := clampf((u - _swing_key_u[i]) / span, 0.0, 1.0)
	# Top: bow past the face of the skull (not a centerline drop). Sides keep
	# the existing face-quad. L/R keys are untouched.
	var overhead := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y < -0.5
	var butt: Vector3
	var tip: Vector3
	if overhead:
		butt = _overhead_clear_quad(_swing_keys_butt[i], _swing_keys_butt[i + 1], t)
		tip = _overhead_clear_quad(_swing_keys_tip[i], _swing_keys_tip[i + 1], t)
	elif absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y > 0.5:
		# Jab: straight travel along the thrust. The face-quad bowed the butt
		# toward the centre line and back into the tunic.
		var s := t * t * (3.0 - 2.0 * t)
		butt = _swing_keys_butt[i].lerp(_swing_keys_butt[i + 1], s)
		# Turn the wood (slerp) instead of sliding the tip — a tip lerp
		# shortened the chord and let the palm stations drift off the hands.
		var d0: Vector3 = (_swing_keys_tip[i] - _swing_keys_butt[i]).normalized()
		var d1: Vector3 = (_swing_keys_tip[i + 1] - _swing_keys_butt[i + 1]).normalized()
		tip = butt + d0.slerp(d1, s) * 1.30
	else:
		butt = _face_quad(_swing_keys_butt[i], _swing_keys_butt[i + 1], t)
		tip = _face_quad(_swing_keys_tip[i], _swing_keys_tip[i + 1], t)
	var axis := tip - butt
	if axis.length_squared() > 0.0001:
		tip = butt + axis.normalized() * 1.30
	return [butt, tip]


func _overhead_clear_quad(a: Vector3, b: Vector3, t: float) -> Vector3:
	## Charged top only. Ends stay on the authored keys; the mid control sits
	## past the face and off the sagittal plane so the chop misses the skull.
	var mid := a.lerp(b, 0.5)
	mid.z = minf(mid.z, -0.58)
	if absf(mid.x) < 0.30:
		mid.x = 0.30 if mid.x >= 0.0 else -0.30
	if mid.y > 1.55:
		mid.y = 1.55
	return _quad_bez(a, mid, b, t)


func _face_quad(a: Vector3, b: Vector3, t: float) -> Vector3:
	## The chord from a guard behind the shoulder would cross the skull.
	## The control sits on the face side. Ends of the segment stay put.
	var mid := a.lerp(b, 0.5)
	if mid.z > -0.36:
		mid.z = -0.55
	# Side mid-arc: keep the bezier in front of the chest, not through it.
	if absf(_swing_arc_aim.x) > 0.35 and mid.y > 0.75 and mid.y < 1.48:
		mid.z = minf(mid.z, -0.78)
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
	# Jab is a point thrust — hip yaw spun it into a side sweep.
	if absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y > 0.5:
		return 0.0
	var a := 0.0
	var b := 0.0
	if _swing_start_pose.has("hips"):
		a = (_swing_start_pose["hips"] as Vector3).y
	if _swing_follow_pose.has("hips"):
		b = (_swing_follow_pose["hips"] as Vector3).y
	return (b - a) * 0.55 * clampf(u, 0.0, 1.0)


func _jab_chest_yaw(u: float) -> float:
	## Degrees. Chest turns right into the thrust so the left shoulder comes
	## forward and both palms stay on the wood beside the flank. Eases in
	## over the chamber and out through the settle.
	const JAB_CHEST_YAW_DEG := -32.0
	var e_in := clampf(u / 0.18, 0.0, 1.0)
	var e_out := clampf((1.0 - u) / 0.30, 0.0, 1.0)
	var env := minf(e_in * e_in * (3.0 - 2.0 * e_in), e_out * e_out * (3.0 - 2.0 * e_out))
	return JAB_CHEST_YAW_DEG * env * (-1.0 if _jab_mirror else 1.0)


func _swing_body_at(u: float) -> Dictionary:
	## Hips, spine, and the step share the shaft's parameter. Arms are
	## overwritten by the two-hand grip. Shin pitch stays negative.
	## A pure top chop keeps the feet down and the chest near upright —
	## the side swings still take the lean and the step.
	var pose := {}
	var step_u := clampf(u / maxf(_swing_strike_u, 0.05), 0.0, 1.0)
	var turn := clampf(u, 0.0, 1.0)
	var lean := sin(turn * PI)
	var overhead := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y < -0.5
	var jabbing := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y > 0.5
	if overhead:
		step_u *= 0.18
		lean *= 0.20
	elif jabbing:
		step_u *= 0.35
		lean *= 0.25
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
			if jabbing and key == "torso":
				v.y += _jab_chest_yaw(u)
			elif jabbing and key == "head":
				# Eyes stay on the target while the chest turns.
				v.y -= _jab_chest_yaw(u)
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
		var overhead_slide := absf(_swing_arc_aim.x) < 0.35 and _swing_arc_aim.y < -0.5
		var head_r := 0.46 if overhead_slide else 0.36
		if hp.length() < head_r:
			push = maxf(push, (head_r + 0.08 - hp.length()) / 0.40)
		if hp.z > -0.28 and hp.length() < 0.62 and absf(hp.y) < 0.52:
			push = maxf(push, (hp.z + 0.42) / along)
		if hp.y < 0.14 and hp.y > -0.52 and hp.z > -0.16 and Vector2(hp.x, hp.z).length() < 0.30:
			push = maxf(push, (hp.z + 0.30) / along)
		var tp: Vector3 = torso.to_local(p)
		# Wider / deeper torso sample so a side chord cannot sit in the chest.
		if absf(tp.x) < 0.44 and tp.y > -0.14 and tp.y < 0.72 and tp.z > -0.30:
			var chest_face := -torso.global_transform.basis.z
			var along_c := 0.35
			if chest_face.length_squared() > 0.0001:
				along_c = maxf(dir.dot(chest_face.normalized()), 0.35)
			push = maxf(push, (tp.z + 0.40) / along_c)
	if push > 0.001:
		var push_cap := 0.78 if absf(_swing_arc_aim.x) > 0.35 else 0.55
		var delta := dir * minf(push, push_cap)
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




func _seat_overhead_shaft_at_shoulders(butt_w: Vector3, tip_w: Vector3) -> Array:
	## Charged top only. Keep the clear-key axis; plant a high grip mid in
	## front of both shoulders so spaced palms reach past the skull.
	if locomotion == null:
		return [butt_w, tip_w]
	var right_arm := locomotion.get_joint("right_arm") as Node3D
	var left_arm := locomotion.get_joint("left_arm") as Node3D
	if right_arm == null or left_arm == null:
		return [butt_w, tip_w]
	var axis := tip_w - butt_w
	if axis.length_squared() < 0.0001:
		return [butt_w, tip_w]
	axis = axis.normalized()
	var face := -_swing_frame.basis.z
	face.y = 0.0
	if face.length_squared() < 0.0001:
		face = Vector3(0.0, 0.0, -1.0)
	else:
		face = face.normalized()
	var r_sh: Vector3 = right_arm.global_position
	var l_sh: Vector3 = left_arm.global_position
	var mid_sh: Vector3 = (r_sh + l_sh) * 0.5
	# High hold in front of the shoulders, biased with the clear-key lateral.
	var lateral := axis
	lateral.y = 0.0
	if lateral.length_squared() > 0.0001:
		lateral = lateral.normalized()
	else:
		lateral = _swing_frame.basis.x
	var grip_mid: Vector3 = mid_sh + face * 0.34 + Vector3.UP * 0.40 + lateral * 0.16
	var spacing := 0.34
	var right_pt: Vector3 = grip_mid - axis * (spacing * 0.5)
	butt_w = right_pt - axis * (0.255 + 0.14)
	tip_w = butt_w + axis * 1.30
	return [butt_w, tip_w]


func _seat_charged_shaft_at_shoulders(butt_w: Vector3, tip_w: Vector3) -> Array:
	## Charged side mid only. Hold the swing-key axis just ahead of both
	## shoulders so fixed palm stations stay in forearm reach.
	if locomotion == null:
		return [butt_w, tip_w]
	var right_arm := locomotion.get_joint("right_arm") as Node3D
	var left_arm := locomotion.get_joint("left_arm") as Node3D
	if right_arm == null or left_arm == null:
		return [butt_w, tip_w]
	var axis := tip_w - butt_w
	if axis.length_squared() < 0.0001:
		return [butt_w, tip_w]
	axis = axis.normalized()
	# In front of the CHEST, not the root. A charged swing yaws the chest far
	# off the start frame; a root-forward offset landed the butt in the waist.
	var face := -_swing_frame.basis.z
	var torso_j := locomotion.get_joint("torso") as Node3D
	if torso_j:
		face = -torso_j.global_transform.basis.z
	face.y = 0.0
	if face.length_squared() < 0.0001:
		face = Vector3(0.0, 0.0, -1.0)
	else:
		face = face.normalized()
	var r_sh: Vector3 = right_arm.global_position
	var l_sh: Vector3 = left_arm.global_position
	var mid_sh: Vector3 = (r_sh + l_sh) * 0.5
	var swing_mid_y := (butt_w.y + tip_w.y) * 0.5
	var grip_mid: Vector3 = mid_sh + face * SEAT_SIDE_FORWARD
	grip_mid.y = clampf(swing_mid_y, mid_sh.y - 0.10, mid_sh.y + 0.40)
	var spacing := 0.36
	var right_pt: Vector3 = grip_mid - axis * (spacing * 0.5)
	butt_w = right_pt - axis * (0.255 + 0.14)
	tip_w = butt_w + axis * 1.30
	return [butt_w, tip_w]


func _shaft_point_in_body(p: Vector3, torso: Node3D, head: Node3D) -> bool:
	## Same body the captures score: ToolStrikePoses._point_in_body plus the
	## torso / skirt / cloak / head / belt / hips mesh boxes, grown a little.
	if ToolStrikePoses._point_in_body(p, torso, head, locomotion):
		return true
	if _clear_meshes.is_empty() or not is_instance_valid(_clear_meshes[0]):
		_clear_meshes = []
		for mn in SHAFT_CLEAR_MESHES:
			var m := find_child(mn, true, false) as MeshInstance3D
			if m:
				_clear_meshes.append(m)
	for m in _clear_meshes:
		var mi := m as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		if mi.get_aabb().grow(SHAFT_CLEAR_BOX_GROW).has_point(mi.global_transform.affine_inverse() * p):
			return true
	return false


func _shaft_body_hits(butt_w: Vector3, tip_w: Vector3, torso: Node3D, head: Node3D) -> int:
	var n := 0
	for i in SHAFT_CLEAR_SAMPLES:
		if _shaft_point_in_body(butt_w.lerp(tip_w, float(i) / float(SHAFT_CLEAR_SAMPLES - 1)), torso, head):
			n += 1
	return n


func _shaft_grip_dists(butt_w: Vector3, tip_w: Vector3, stations: Vector2) -> Vector2:
	## Shoulder → palm distance, right / left. stations = goad-local Y of the
	## palm (origin = butt + 0.255 along the wood); NAN = nearest point.
	var axis := (tip_w - butt_w).normalized()
	var origin := butt_w + axis * 0.255
	var ys := [stations.x, stations.y]
	var arms := ["right_arm", "left_arm"]
	var out := Vector2.ZERO
	for k in 2:
		var arm := locomotion.get_joint(arms[k]) as Node3D
		if arm == null:
			continue
		var sh: Vector3 = arm.global_position
		var grip: Vector3
		if is_nan(float(ys[k])):
			grip = butt_w + axis * clampf((sh - butt_w).dot(axis), 0.0, 1.30)
		else:
			grip = origin + axis * float(ys[k])
		out[k] = sh.distance_to(grip)
	return out


func _shaft_on_palms_stay(butt_w: Vector3, tip_w: Vector3, stations: Vector2, base: Vector2) -> bool:
	## Fallback rule: every palm that is on the wood (<= reach) stays on it.
	## A palm already off the wood is not "taken off" by moving the line.
	var d := _shaft_grip_dists(butt_w, tip_w, stations)
	for k in 2:
		if base[k] <= SHAFT_CLEAR_GRIP_REACH and d[k] > SHAFT_CLEAR_GRIP_REACH:
			return false
	return true


func _shaft_grips_in_reach(butt_w: Vector3, tip_w: Vector3, stations: Vector2, base: Vector2) -> bool:
	## Both hands stay on: a palm within SHAFT_CLEAR_GRIP_REACH must stay
	## within it. A palm already past it (authored early-arc left station)
	## may drift at most SHAFT_CLEAR_OFF_PALM_SLACK further.
	var d := _shaft_grip_dists(butt_w, tip_w, stations)
	for k in 2:
		var limit := SHAFT_CLEAR_GRIP_REACH if base[k] <= SHAFT_CLEAR_GRIP_REACH else base[k] + SHAFT_CLEAR_OFF_PALM_SLACK
		if d[k] > limit:
			return false
	return true


func _solve_shaft_clearance(butt_w: Vector3, tip_w: Vector3, stations: Vector2, keep_high_y: bool) -> Array:
	## ONE clearance pass for swing, charge plant and guard seat. Samples the
	## 1.30 m wood; if any sample is in the body, the WHOLE segment steps
	## perpendicular to the shaft toward the chest face (flattened torso -Z),
	## never along the wood. Smallest push that clears wins; capped at
	## SHAFT_CLEAR_MAX_PUSH; any push that takes a palm out of reach is rejected.
	## keep_high_y: overhead chop keeps its high end's height (no vertical push).
	_clear_stats["calls"] = int(_clear_stats["calls"]) + 1
	if locomotion == null:
		return [butt_w, tip_w]
	var torso := locomotion.get_joint("torso") as Node3D
	var head := locomotion.get_joint("head") as Node3D
	if torso == null or head == null:
		return [butt_w, tip_w]
	var axis := tip_w - butt_w
	if axis.length_squared() < 0.0001:
		return [butt_w, tip_w]
	axis = axis.normalized()
	var h0 := _shaft_body_hits(butt_w, tip_w, torso, head)
	_clear_last = {"before": h0, "after": h0, "push": 0.0, "why": "clear"}
	if h0 == 0:
		return [butt_w, tip_w]
	var face := -torso.global_transform.basis.z
	face.y = 0.0
	if face.length_squared() < 0.0001:
		face = -global_transform.basis.z
		face.y = 0.0
	face = face.normalized() if face.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	var dir := face - axis * axis.dot(face)
	if keep_high_y:
		dir.y = 0.0
	if dir.length() < 0.2:
		# Wood points at the face: "toward the face" would be along the wood.
		# Step sideways instead, perpendicular to the wood, away from the body
		# centre on the side the hit samples already lean to.
		var side := torso.global_transform.basis.x
		side.y = 0.0
		side = side - axis * axis.dot(side)
		if side.length() < 0.2:
			_clear_last["why"] = "axis_degenerate"
			_clear_stats["residual"] = int(_clear_stats["residual"]) + 1
			return [butt_w, tip_w]
		side = side.normalized()
		var lean := 0.0
		for i in SHAFT_CLEAR_SAMPLES:
			var q := butt_w.lerp(tip_w, float(i) / float(SHAFT_CLEAR_SAMPLES - 1))
			if _shaft_point_in_body(q, torso, head):
				lean += (q - head.global_position).dot(side)
		dir = side if lean >= 0.0 else -side
		_clear_stats["sideways"] = int(_clear_stats.get("sideways", 0)) + 1
	dir = dir.normalized()
	var best_s := 0.0
	var best_h := h0
	var rejected := false
	var base := _shaft_grip_dists(butt_w, tip_w, stations)
	var steps := int(round(SHAFT_CLEAR_MAX_PUSH / SHAFT_CLEAR_STEP))
	for k in range(1, steps + 1):
		var d := dir * (SHAFT_CLEAR_STEP * float(k))
		if not _shaft_grips_in_reach(butt_w + d, tip_w + d, stations, base):
			rejected = true
			break
		var h := _shaft_body_hits(butt_w + d, tip_w + d, torso, head)
		if h < best_h:
			best_h = h
			best_s = SHAFT_CLEAR_STEP * float(k)
		if h == 0:
			break
	if rejected:
		_clear_stats["reach_rejected"] = int(_clear_stats["reach_rejected"]) + 1
	if best_h > 0:
		# Fallback: keep stepping the same way past the cap. Accept the first
		# clear step whose on-wood palms all stay on; otherwise keep the best.
		var fb_steps := int(round(SHAFT_CLEAR_FALLBACK_PUSH / SHAFT_CLEAR_STEP))
		for k in range(steps + 1, fb_steps + 1):
			var sk := SHAFT_CLEAR_STEP * float(k)
			var dk := dir * sk
			if not _shaft_on_palms_stay(butt_w + dk, tip_w + dk, stations, base):
				break
			var hk := _shaft_body_hits(butt_w + dk, tip_w + dk, torso, head)
			if hk < best_h:
				best_h = hk
				best_s = sk
				_clear_stats["fallback_push"] = int(_clear_stats.get("fallback_push", 0)) + 1
			if hk == 0:
				break
	if best_s > 0.0:
		_clear_stats["pushed"] = int(_clear_stats["pushed"]) + 1
		butt_w += dir * best_s
		tip_w += dir * best_s
	if best_h > 0:
		_clear_stats["residual"] = int(_clear_stats["residual"]) + 1
	_clear_last = {"before": h0, "after": best_h, "push": best_s, "why": "reach" if rejected and best_h > 0 else ("cap" if best_h > 0 else "pushed")}
	return [butt_w, tip_w]


func _clear_shaft_node(shaft: Node3D, stations: Vector2, keep_high_y: bool, mover: Node3D = null) -> bool:
	## Node form of the same solver (charge plant / guard seat). Moves `mover`
	## (default the shaft) by the solved offset. Returns true if it moved.
	if shaft == null:
		return false
	var butt := shaft.to_global(Vector3(0.0, -0.255, 0.0))
	var tip := shaft.to_global(Vector3(0.0, 1.045, 0.0))
	var solved: Array = _solve_shaft_clearance(butt, tip, stations, keep_high_y)
	var delta: Vector3 = (solved[0] as Vector3) - butt
	if delta.length_squared() < 1e-8:
		return false
	var target := mover if mover else shaft
	target.global_position += delta
	return true


func _place_continuous_shaft(butt_w: Vector3, tip_w: Vector3) -> Node3D:
	if weapon_visual == null:
		return null
	# Clearance is the LAST write on the line. Jab rides its authored flank.
	var jabbing := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y > 0.5
	if not jabbing:
		var overhead := absf(_swing_arc_aim.x) < 0.05 and _swing_arc_aim.y < -0.5
		var stations := Vector2(0.14, 0.46)
		var base := _shaft_grip_dists(butt_w, tip_w, stations)
		var solved: Array = _solve_shaft_clearance(butt_w, tip_w, stations, overhead)
		butt_w = solved[0]
		tip_w = solved[1]
		var left_hits := int(_clear_last.get("after", 0))
		if left_hits > 0 and not overhead and locomotion:
			# Fallback only: the per-face slide (bigger reach) when the capped
			# solve cannot clear. Kept only if it clears more and no palm that
			# was on the wood comes off it.
			var torso := locomotion.get_joint("torso") as Node3D
			var head := locomotion.get_joint("head") as Node3D
			var slid: Array = _slide_line_off_body(butt_w, tip_w)
			var sh := _shaft_body_hits(slid[0], slid[1], torso, head)
			if sh < left_hits and _shaft_on_palms_stay(slid[0], slid[1], stations, base):
				butt_w = slid[0]
				tip_w = slid[1]
				_clear_last["after"] = sh
				_clear_last["why"] = "fallback_slide"
				_clear_stats["fallback"] = int(_clear_stats.get("fallback", 0)) + 1
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


func _abort_goad_release_tween() -> void:
	## Kill the arc tween and always clear release flags / lean additives.
	## A bare kill left _swing_arc_live set so sync skipped and the stick froze.
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _goad_release_live or _swing_arc_live or _goad_swing_held:
		_finish_goad_return()


func _finish_goad_return() -> void:
	## Jab and continuous shaft swings settle to the ready pose.
	## Continuous placement zeros Goad local + leaves full-body lean additives.
	## Always clear those before re-entering guard/charge, or the body stays
	## folded and the stick seats behind the waist — including if the player
	## already started moving or sprinting during the settle tail.
	_swing_arc_live = false
	_goad_swing_held = false
	_swing_arc_interior = false
	_shaft_xf_blend = false
	_goad_release_live = false
	_jab_mirror = false
	_tool_root_drop = 0.0
	_goad_grip_slide = 0.0
	if locomotion:
		locomotion.clear_combat_additives()
		locomotion.set_root_drop(0.0)
	if weapon_visual:
		var goad_reset := weapon_visual.get_node_or_null("Goad") as Node3D
		if goad_reset:
			goad_reset.rotation = Vector3.ZERO
			goad_reset.position = Vector3.ZERO
	# Always reseat to a ready hold. Do not early-out on shaft_blocking/charge
	# without syncing — that left the follow-through stick out while sprinting.
	if combat == null or locomotion == null:
		_tool_pose_active = false
		_sync_weapon_to_hand()
		return
	if combat.is_charging or combat.is_shaft_blocking:
		_tool_pose_active = false
		_sync_weapon_to_hand()
		return
	_apply_tool_pose(ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD))
	_tool_pose_active = false
	_sync_weapon_to_hand()


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
		var shaft_xf := _to_body(_swing_shaft_on_arc(from_xf, to_xf, u))
		_shaft_from_xf = shaft_xf
		_shaft_to_xf = shaft_xf
		_shaft_xf_u = 1.0
		_shaft_xf_blend = true
		_sync_weapon_to_hand()
		_shaft_xf_blend = false
		_swing_arc_interior = false
		return
	var shaft_xf := _to_body(from_xf.interpolate_with(to_xf, u))
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
		_abort_goad_release_tween()
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
	_discard_attack_buffer(&"dead")



func _sync_weapon_to_hand() -> void:
	## Keep hatchet/knife/goad near the right forearm tip so swings read with the arm.
	if weapon_visual == null or locomotion == null:
		return
	# Continuous goad arc placed the shaft + spaced grips. Do not glue to one hand.
	if _swing_arc_live:
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
		if _carry_state != CARRY_NONE and not _carry_must_abort():
			_place_carry_shaft()
		elif _guard_blend_active:
			_plant_shaft_between(_guard_from_xf, _guard_to_xf, _guard_blend_u)
		elif _shaft_xf_blend:
			_plant_shaft_between(_shaft_from_xf, _shaft_to_xf, _shaft_xf_u)
		elif combat.is_charging and _charge_from_ready and _is_top_goad_charge(_shaft_aim_axes()):
			# The generic seat pulls this hold out beside the right ear.
			_plant_shaft_between(_charge_from_xf, _shaft_to_xf, ToolStrikePoses._charge_blend(combat.charge_ratio))
		else:
			ToolStrikePoses.seat_goad_off_hand(locomotion, weapon_visual)
			# Shared clearance solver on the seated guard. A no-op when the seat
			# is already clear; if it moves, both palms re-take the wood.
			var seated := weapon_visual.get_node_or_null("Goad") as Node3D
			if seated and _clear_shaft_node(seated, Vector2(NAN, NAN), false, weapon_visual):
				_grip_shaft_with(seated, "right_arm", "right_forearm", 0.30)
				_grip_shaft_with(seated, "left_arm", "left_forearm", 0.24)
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


func _grip_shaft_at_y(shaft: Node3D, arm_name: String, fore_name: String, shaft_y: float) -> void:
	## Plant the palm on a fixed station along the goad local Y (butt→tip).
	var arm := locomotion.get_joint(arm_name) as Node3D
	var fore := locomotion.get_joint(fore_name) as Node3D
	if arm == null or fore == null:
		return
	var shoulder: Vector3 = arm.global_position
	var best: Vector3 = shaft.to_global(Vector3(0.0, shaft_y, 0.0))
	var best_d := shoulder.distance_to(best)
	if best_d > 0.90:
		return
	var l1 := 0.32
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
	_discard_attack_buffer(&"drag")
	dragging_body = body


func end_drag() -> void:
	dragging_body = null


func is_dragging() -> bool:
	return dragging_body != null and is_instance_valid(dragging_body)


func get_dragged_body() -> Node3D:
	if is_dragging():
		return dragging_body
	return null


func get_drag_status_text() -> String:
	if not is_dragging():
		return ""
	return "DRAG dragging · speed %.2f" % DRAG_SPEED


## --- Horse mount API (called by HorseController) ---

func is_mounted_on_horse() -> bool:
	return is_mounted


func prepare_for_mount(horse: Node3D) -> void:
	# Drop any corpse drag before seating.
	if is_dragging():
		end_drag()
	_discard_attack_buffer(&"mount")
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
