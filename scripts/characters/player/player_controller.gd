extends CharacterBody3D
## Third-person controller + hatchet-first combat wiring for the greybox slice.
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

## Directional hatchet: hold LMB to charge; mouse flick / WASD picks top|left|right.
var _charge_mouse_accum: Vector2 = Vector2.ZERO
var _hatchet_charge_armed: bool = false
const CHARGE_DIR_MOUSE_THRESH := 28.0 ## px of relative mouse during hold


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
	_sync_back_goad_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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

	# Accumulate mouse delta while charging so flick direction can pick the arc.
	if combat.is_charging and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_charge_mouse_accum += (event as InputEventMouseMotion).relative
		_apply_charge_direction_from_input()

	if event.is_action_pressed("attack_light"):
		_begin_hatchet_or_light()
	elif event.is_action_released("attack_light"):
		_release_hatchet_or_ignore()
	elif event.is_action_pressed("attack_heavy"):
		# RMB: instant full-power strike in current aimed direction (no hold).
		_instant_power_strike()
	elif event.is_action_pressed("cycle_weapon"):
		if combat.is_charging:
			combat.cancel_charge()
		combat.cycle_weapon(1)
	elif event.is_action_pressed("weapon_hatchet"):
		combat.set_weapon(CombatSystem.Weapon.HATCHET)
	elif event.is_action_pressed("weapon_knife"):
		combat.set_weapon(CombatSystem.Weapon.KNIFE)
	elif event.is_action_pressed("weapon_goad"):
		combat.set_weapon(CombatSystem.Weapon.GOAD)


func _physics_process(delta: float) -> void:
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
	# Charging allows half-speed footwork so direction + spacing stay readable.
	var charging_move := combat != null and combat.is_charging
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
		target_speed = WALK_SPEED * 0.45

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
		_tick_locomotion(delta, horiz.length(), sprinting, locked)
		_sync_weapon_to_hand()


func _tick_locomotion(delta: float, horiz_speed: float, sprinting: bool, locked: bool) -> void:
	if locomotion == null:
		return
	var attacking := combat != null and combat.is_attacking
	var local_dir := Vector3.ZERO
	var input_dir := _move_vector()
	if not locked:
		local_dir = Vector3(input_dir.x, 0.0, input_dir.y)
	locomotion.tick(delta, horiz_speed, sprinting, is_crouching, attacking, local_dir)


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
	if combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet:
		_charge_mouse_accum = Vector2.ZERO
		_hatchet_charge_armed = true
		if not combat.begin_charge():
			_hatchet_charge_armed = false
			combat.try_attack(&"light", CombatSystem.StrikeDirection.TOP)
		else:
			_apply_charge_direction_from_input()
	else:
		combat.try_attack(&"light")


func _release_hatchet_or_ignore() -> void:
	if combat == null:
		return
	if not _hatchet_charge_armed and not combat.is_charging:
		return
	_hatchet_charge_armed = false
	if combat.is_charging:
		_apply_charge_direction_from_input()
		combat.release_charged_attack()


func _instant_power_strike() -> void:
	if combat == null:
		return
	if combat.is_charging:
		combat.cancel_charge()
		_hatchet_charge_armed = false
	if combat.current_weapon == CombatSystem.Weapon.HATCHET and combat.enable_directional_hatchet:
		var direction := _resolve_strike_direction(true)
		combat.try_attack(&"heavy", direction, 1.0)
	else:
		combat.try_attack(&"heavy")


func _apply_charge_direction_from_input() -> void:
	if combat == null or not combat.is_charging:
		return
	combat.set_charge_direction(_resolve_strike_direction(false))


func _resolve_strike_direction(instant: bool) -> CombatSystem.StrikeDirection:
	## Priority: WASD lateral (A/D) → mouse flick during charge → camera pitch (up = top).
	## Neutral defaults to TOP (classic hatchet overhead).
	var move := _move_vector()
	if move.x <= -0.45:
		return CombatSystem.StrikeDirection.LEFT
	if move.x >= 0.45:
		return CombatSystem.StrikeDirection.RIGHT
	if move.y <= -0.45:
		return CombatSystem.StrikeDirection.TOP

	var mx := _charge_mouse_accum.x
	var my := _charge_mouse_accum.y
	if not instant and _charge_mouse_accum.length() >= CHARGE_DIR_MOUSE_THRESH:
		if absf(my) > absf(mx) * 0.85 and my < 0.0:
			return CombatSystem.StrikeDirection.TOP
		if mx <= -CHARGE_DIR_MOUSE_THRESH * 0.55:
			return CombatSystem.StrikeDirection.LEFT
		if mx >= CHARGE_DIR_MOUSE_THRESH * 0.55:
			return CombatSystem.StrikeDirection.RIGHT

	# Camera pitched up favors overhead even without a flick.
	if pivot and pivot.rotation.x <= deg_to_rad(-12.0):
		return CombatSystem.StrikeDirection.TOP
	return CombatSystem.StrikeDirection.TOP


func _on_weapon_changed(weapon: StringName) -> void:
	_sync_back_goad_visibility()
	# Hide belt knife mesh when knife is drawn as active weapon.
	if locomotion == null:
		return
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node == null:
		return
	var belt_knife := visual_node.find_child("BeltKnife", true, false) as Node3D
	if belt_knife:
		belt_knife.visible = weapon != &"knife"


func _sync_back_goad_visibility() -> void:
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node == null or combat == null:
		return
	var back_goad := visual_node.find_child("BackGoad", true, false) as Node3D
	if back_goad:
		back_goad.visible = combat.current_weapon != CombatSystem.Weapon.GOAD


func _on_attack_performed(_attacker: Node, kind: StringName, weapon: StringName) -> void:
	# Body + arm follow weapon swing phases; timings match CombatSystem profiles.
	if combat == null:
		return
	var profile: Dictionary = CombatSystem.PROFILES[combat.current_weapon].get(
		kind, CombatSystem.PROFILES[combat.current_weapon][&"light"]
	)
	var windup: float = profile["windup"]
	var active: float = profile["active"]
	var recovery: float = profile["recovery"]
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
				windup_delta = Vector3(deg_to_rad(-30.0 if heavy else -18.0), deg_to_rad(35.0 if heavy else 22.0), deg_to_rad(-40.0 if heavy else -25.0))
				contact_delta = Vector3(deg_to_rad(15.0 if heavy else 8.0), deg_to_rad(-20.0), deg_to_rad(25.0 if heavy else 15.0))
				follow_delta = Vector3(deg_to_rad(25.0 if heavy else 14.0), deg_to_rad(-45.0), deg_to_rad(40.0 if heavy else 25.0))
				torso_windup = Vector3(deg_to_rad(-4.0), deg_to_rad(18.0 if heavy else 10.0), 0.0)
				torso_contact = Vector3(deg_to_rad(6.0), deg_to_rad(-10.0 if heavy else -6.0), 0.0)
				torso_follow = Vector3(deg_to_rad(8.0), deg_to_rad(-16.0 if heavy else -10.0), 0.0)
			CombatSystem.StrikeDirection.RIGHT:
				windup_delta = Vector3(deg_to_rad(-30.0 if heavy else -18.0), deg_to_rad(-40.0 if heavy else -25.0), deg_to_rad(20.0 if heavy else 12.0))
				contact_delta = Vector3(deg_to_rad(15.0 if heavy else 8.0), deg_to_rad(25.0), deg_to_rad(-15.0 if heavy else -8.0))
				follow_delta = Vector3(deg_to_rad(25.0 if heavy else 14.0), deg_to_rad(50.0), deg_to_rad(-25.0 if heavy else -14.0))
				torso_windup = Vector3(deg_to_rad(-4.0), deg_to_rad(-20.0 if heavy else -12.0), 0.0)
				torso_contact = Vector3(deg_to_rad(6.0), deg_to_rad(12.0 if heavy else 7.0), 0.0)
				torso_follow = Vector3(deg_to_rad(8.0), deg_to_rad(18.0 if heavy else 10.0), 0.0)
			_:
				# TOP overhead — higher cock, steeper drop.
				windup_delta = Vector3(deg_to_rad(-75.0 if heavy else -45.0), deg_to_rad(-8.0), deg_to_rad(-18.0 if heavy else -10.0))
				contact_delta = Vector3(deg_to_rad(35.0 if heavy else 20.0), deg_to_rad(5.0), deg_to_rad(25.0 if heavy else 15.0))
				follow_delta = Vector3(deg_to_rad(70.0 if heavy else 45.0), deg_to_rad(10.0), deg_to_rad(35.0 if heavy else 22.0))
				torso_windup = Vector3(deg_to_rad(-14.0 if heavy else -8.0), deg_to_rad(-6.0), 0.0)
				torso_contact = Vector3(deg_to_rad(16.0 if heavy else 9.0), deg_to_rad(4.0), 0.0)
				torso_follow = Vector3(deg_to_rad(22.0 if heavy else 12.0), deg_to_rad(6.0), 0.0)

	if weapon == &"goad":
		windup_delta = Vector3(deg_to_rad(-70.0 if heavy else -40.0), deg_to_rad(-5.0), deg_to_rad(-10.0))
		contact_delta = Vector3(deg_to_rad(40.0 if heavy else 22.0), deg_to_rad(5.0), deg_to_rad(15.0))
		follow_delta = Vector3(deg_to_rad(60.0 if heavy else 35.0), deg_to_rad(8.0), deg_to_rad(20.0))
		torso_windup = Vector3(deg_to_rad(-12.0 if heavy else -6.0), 0.0, 0.0)
		torso_contact = Vector3(deg_to_rad(16.0 if heavy else 8.0), 0.0, 0.0)
		torso_follow = Vector3(deg_to_rad(20.0 if heavy else 10.0), 0.0, 0.0)
	elif weapon == &"knife":
		windup_delta = Vector3(deg_to_rad(-25.0 if heavy else -14.0), deg_to_rad(-25.0 if heavy else -14.0), deg_to_rad(-40.0 if heavy else -22.0))
		contact_delta = Vector3(deg_to_rad(10.0 if heavy else 5.0), deg_to_rad(20.0), deg_to_rad(55.0 if heavy else 35.0))
		follow_delta = Vector3(deg_to_rad(20.0 if heavy else 10.0), deg_to_rad(30.0), deg_to_rad(70.0 if heavy else 45.0))
		torso_windup = Vector3(0.0, deg_to_rad(-8.0), 0.0)
		torso_contact = Vector3(deg_to_rad(4.0), deg_to_rad(10.0), 0.0)
		torso_follow = Vector3(deg_to_rad(6.0), deg_to_rad(12.0), 0.0)

	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	if _torso_tween and _torso_tween.is_valid():
		_torso_tween.kill()

	_arm_fore_scale = 0.35
	_arm_tween = create_tween()
	_arm_tween.tween_method(_apply_arm_additive, windup_delta * 0.15, windup_delta, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_callback(func() -> void: _arm_fore_scale = 0.45)
	_arm_tween.tween_method(_apply_arm_additive, windup_delta, contact_delta, active * 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_arm_tween.tween_callback(func() -> void: _arm_fore_scale = 0.5)
	_arm_tween.tween_method(_apply_arm_additive, contact_delta, follow_delta, active * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_callback(func() -> void: _arm_fore_scale = 0.25)
	_arm_tween.tween_method(_apply_arm_additive, follow_delta, Vector3.ZERO, recovery).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_callback(_clear_attack_additives)

	_torso_tween = create_tween()
	_torso_tween.tween_method(_apply_torso_additive, torso_windup * 0.2, torso_windup, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_torso_tween.tween_method(_apply_torso_additive, torso_windup, torso_contact, active * 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_torso_tween.tween_method(_apply_torso_additive, torso_contact, torso_follow, active * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
	if locomotion:
		locomotion.clear_combat_additives()


func _on_hit_landed(_attacker: Node, _target: Node, damage: float, kind: StringName) -> void:
	# Screen punch on connecting hits (reads better with hit-stop from CombatSystem).
	var amp := 0.055 if kind == &"heavy" else 0.03
	amp *= clampf(damage / 14.0, 0.75, 1.4)
	_screen_punch(amp)


func _on_damage_taken(amount: float, _from: Node) -> void:
	_screen_punch(0.07 if amount >= 12.0 else 0.045)


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
	if combat and combat.is_attacking:
		return  # CombatSystem owns WeaponVisual transform during swings
	var forearm := locomotion.get_joint("right_forearm")
	if forearm == null:
		return
	# Tip of forearm in player local space
	var tip_global := forearm.to_global(Vector3(0.0, -0.28, 0.05))
	weapon_visual.global_position = tip_global
	# Preserve roughly upright kit rest; yaw follows body
	weapon_visual.rotation = Vector3(deg_to_rad(-10.0), 0.0, deg_to_rad(-8.0))
	_weapon_base_y = weapon_visual.position.y

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
