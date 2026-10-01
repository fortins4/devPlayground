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


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if right_arm:
		_arm_base_transform = right_arm.transform
	if combat:
		combat.attack_performed.connect(_on_attack_performed)
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


func _on_attack_performed(_attacker: Node, kind: StringName, _weapon: StringName) -> void:
	# Brief arm raise for greybox readability
	if right_arm == null:
		return
	var lift := -0.9 if kind == &"heavy" else -0.55
	right_arm.rotation.z = lift


func _update_arm_swing(delta: float) -> void:
	if right_arm == null:
		return
	right_arm.rotation.z = move_toward(right_arm.rotation.z, 0.0, 3.5 * delta)


func _on_died(_victim: Node) -> void:
	# Keep camera; player ragdoll deferred — just stop combat inputs via combat.is_dead
	pass
