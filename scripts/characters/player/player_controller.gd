extends CharacterBody3D
## Third-person controller + hatchet-first combat wiring for the greybox slice.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const ACCEL := 18.0
const DECEL := 22.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var combat: CombatSystem = $CombatSystem
@onready var right_arm: MeshInstance3D = $Visual/RightArm

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _jump_buffered: bool = false
var _arm_base_transform: Transform3D
var _arm_tween: Tween
var _camera_base_pos: Vector3
var _punch_tween: Tween


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var locked := combat != null and not combat.can_move()

	if not locked and (_jump_buffered or Input.is_action_just_pressed("jump")) and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_buffered = false

	var input_dir := _move_vector()
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var want_sprint := Input.is_action_pressed("sprint") and direction != Vector3.ZERO and not locked
	var sprinting := false
	if want_sprint and combat:
		sprinting = combat.try_sprint_drain(delta)
	elif want_sprint and combat == null:
		sprinting = true

	var target_speed := SPRINT_SPEED if sprinting else WALK_SPEED
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
	_update_arm_swing(delta)


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
