extends CharacterBody3D
## Third-person controller + hatchet-first combat wiring for the greybox slice.
## Crouch (Ctrl / C): lower capsule + camera, slower move, quieter footprint.

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
@onready var right_arm: MeshInstance3D = $Visual/RightArm
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hurtbox_shape: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var visual: Node3D = $Visual
@onready var weapon_visual: Node3D = $WeaponVisual

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _jump_buffered: bool = false
var _arm_base_transform: Transform3D
var _arm_tween: Tween
var _camera_base_pos: Vector3
var _punch_tween: Tween

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


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if right_arm:
		_arm_base_transform = right_arm.transform
	if camera:
		_camera_base_pos = camera.position
	if combat:
		combat.attack_performed.connect(_on_attack_performed)
		combat.hit_landed.connect(_on_hit_landed)
		combat.damage_taken.connect(_on_damage_taken)
		combat.died.connect(_on_died)
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		_capsule_shape = collision_shape.shape as CapsuleShape3D
	if hurtbox_shape and hurtbox_shape.shape is CapsuleShape3D:
		_hurt_shape = hurtbox_shape.shape as CapsuleShape3D
	if weapon_visual:
		_weapon_base_y = weapon_visual.position.y


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

	if event.is_action_pressed("attack_light"):
		combat.try_attack(&"light")
	elif event.is_action_pressed("attack_heavy"):
		combat.try_attack(&"heavy")
	elif event.is_action_pressed("cycle_weapon"):
		combat.cycle_weapon(1)
	elif event.is_action_pressed("weapon_hatchet"):
		combat.set_weapon(CombatSystem.Weapon.HATCHET)
	elif event.is_action_pressed("weapon_knife"):
		combat.set_weapon(CombatSystem.Weapon.KNIFE)
	elif event.is_action_pressed("weapon_goad"):
		combat.set_weapon(CombatSystem.Weapon.GOAD)


func _physics_process(delta: float) -> void:
	if is_mounted:
		# Horse owns locomotion; keep residual velocity cleared.
		velocity = Vector3.ZERO
		_noise_level = 0.35  # mounted presence — audible but not sprint-loud
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var locked := combat != null and not combat.can_move()
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

	var target_speed := WALK_SPEED
	if dragging_body != null and is_instance_valid(dragging_body):
		target_speed = DRAG_SPEED * (0.55 if drag_stamina_exhausted else 1.0)
		sprinting = false
	elif is_crouching:
		target_speed = CROUCH_SPEED
	elif sprinting:
		target_speed = SPRINT_SPEED
	if locked:
		target_speed = 0.0
		direction = Vector3.ZERO

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
	_update_arm_swing(delta)
	_update_drag_stamina(delta)


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


func _on_attack_performed(_attacker: Node, kind: StringName, weapon: StringName) -> void:
	# Arm follows weapon swing phases for readable greybox attacks.
	if right_arm == null or combat == null:
		return
	var profile: Dictionary = CombatSystem.PROFILES[combat.current_weapon].get(
		kind, CombatSystem.PROFILES[combat.current_weapon][&"light"]
	)
	var windup: float = profile["windup"]
	var active: float = profile["active"]
	var recovery: float = profile["recovery"]
	var heavy := kind == &"heavy"
	var base_rot := _arm_base_transform.basis.get_euler()
	# Deltas on top of rest pose; heavy = higher cock + deeper follow-through.
	var windup_delta := Vector3(deg_to_rad(-25.0 if heavy else -12.0), 0.0, deg_to_rad(-0.55 if heavy else -0.35))
	var contact_delta := Vector3(deg_to_rad(20.0 if heavy else 10.0), 0.0, deg_to_rad(0.55 if heavy else 0.35))
	var follow_delta := Vector3(deg_to_rad(45.0 if heavy else 28.0), 0.0, deg_to_rad(0.95 if heavy else 0.65))
	if weapon == &"goad":
		windup_delta = Vector3(deg_to_rad(-40.0 if heavy else -22.0), 0.0, deg_to_rad(-0.35 if heavy else -0.2))
		contact_delta = Vector3(deg_to_rad(30.0 if heavy else 18.0), 0.0, deg_to_rad(0.25 if heavy else 0.15))
		follow_delta = Vector3(deg_to_rad(50.0 if heavy else 30.0), 0.0, deg_to_rad(0.45 if heavy else 0.3))
	elif weapon == &"knife":
		windup_delta = Vector3(deg_to_rad(-15.0 if heavy else -8.0), 0.0, deg_to_rad(-0.45 if heavy else -0.28))
		contact_delta = Vector3(deg_to_rad(10.0 if heavy else 5.0), 0.0, deg_to_rad(0.55 if heavy else 0.35))
		follow_delta = Vector3(deg_to_rad(25.0 if heavy else 15.0), 0.0, deg_to_rad(0.85 if heavy else 0.55))

	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	right_arm.transform = _arm_base_transform
	_arm_tween = create_tween()
	_arm_tween.tween_property(right_arm, "rotation", base_rot + windup_delta, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_property(right_arm, "rotation", base_rot + contact_delta, active * 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_arm_tween.tween_property(right_arm, "rotation", base_rot + follow_delta, active * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_property(right_arm, "rotation", base_rot, recovery).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _update_arm_swing(_delta: float) -> void:
	# Arm motion is tween-driven during attacks; idle keeps base pose.
	if right_arm == null:
		return
	if combat and combat.is_attacking:
		return


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


func clear_mount() -> void:
	is_mounted = false
	mounted_horse = null
	velocity = Vector3.ZERO


func set_mounted_velocity_zero() -> void:
	velocity = Vector3.ZERO
