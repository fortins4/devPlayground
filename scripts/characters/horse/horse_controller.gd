extends CharacterBody3D
## Greybox Irish pony / hobby horse for open-world traversal feel.
## E (interact) to mount/dismount when near. Shift gallops. Combat blocked while mounted.

const WALK_SPEED := 7.5
const GALLOP_SPEED := 14.0
const ACCEL := 12.0
const DECEL := 16.0
const TURN_RATE := 4.2
const JUMP_VELOCITY := 4.0
const MOUNT_COOLDOWN := 0.4
const DISMOUNT_SIDE := 1.35

@onready var mount_seat: Marker3D = $MountSeat
@onready var mount_zone: Area3D = $MountZone
@onready var prompt: Label3D = $PromptLabel
@onready var status_label: Label3D = $StatusLabel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var rider: CharacterBody3D = null
var _player_near: CharacterBody3D = null
var _cooldown: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rider_cam: Camera3D = null
var _rider_cam_base: Vector3 = Vector3.ZERO
var _mounted_cam_offset := Vector3(0.9, 0.95, 5.6)


func _ready() -> void:
	add_to_group("horse")
	if mount_zone:
		mount_zone.body_entered.connect(_on_zone_entered)
		mount_zone.body_exited.connect(_on_zone_exited)
		mount_zone.monitoring = true
		mount_zone.monitorable = false
	_refresh_prompt()
	if status_label:
		status_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _cooldown > 0.0:
		return
	if not event.is_action_pressed("interact"):
		return
	if rider:
		dismount()
		get_viewport().set_input_as_handled()
	elif _player_near and is_instance_valid(_player_near):
		mount(_player_near)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if rider == null:
		# Idle: settle and face rest.
		var horiz := Vector3(velocity.x, 0.0, velocity.z)
		horiz = horiz.move_toward(Vector3.ZERO, DECEL * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z
		move_and_slide()
		return

	if not is_instance_valid(rider):
		rider = null
		_refresh_prompt()
		return

	# Keep rider glued to seat (reparented, but clear residual velocity).
	if rider.has_method("set_mounted_velocity_zero"):
		rider.call("set_mounted_velocity_zero")

	var input_dir := _move_vector()
	# Mouse yaws the horse while mounted; WASD is horse-local (forward = -Z).
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var gallop := (
		Input.is_action_pressed("sprint")
		and direction != Vector3.ZERO
	)
	var target_speed := GALLOP_SPEED if gallop else WALK_SPEED
	if direction == Vector3.ZERO:
		target_speed = 0.0

	# Optional gentle align when pressing forward with strafe (keeps nose into travel).
	if direction != Vector3.ZERO and absf(input_dir.y) > 0.1:
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_RATE * 0.65 * delta)

	var target_vel := direction * target_speed
	var horiz2 := Vector3(velocity.x, 0.0, velocity.z)
	if direction != Vector3.ZERO:
		horiz2 = horiz2.move_toward(target_vel, ACCEL * delta)
	else:
		horiz2 = horiz2.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = horiz2.x
	velocity.z = horiz2.z

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	var ride_speed := horiz2.length()
	_update_status(gallop, ride_speed)
	# Drive rider seated pose + optional trot/gallop bob.
	if rider.has_method("tick_mounted_rider_pose"):
		rider.call("tick_mounted_rider_pose", delta, ride_speed, gallop)


func mount(player: CharacterBody3D) -> void:
	if rider or player == null:
		return
	if player.has_method("is_mounted_on_horse") and player.call("is_mounted_on_horse"):
		return
	rider = player
	_cooldown = MOUNT_COOLDOWN

	# Clear crouch / foot movement before seating.
	if player.has_method("prepare_for_mount"):
		player.call("prepare_for_mount", self)

	var seat: Node3D = mount_seat if mount_seat else self
	player.get_parent().remove_child(player)
	seat.add_child(player)
	# Sink so seated hips land on the blanket (player origin is at feet).
	# Joint seated pose (KerneLocomotion.tick_mounted) handles astride legs + lean;
	# this Y offset is no longer a stand-in for the bind pose.
	player.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.88, 0.06))
	if player.has_node("CollisionShape3D"):
		(player.get_node("CollisionShape3D") as CollisionShape3D).disabled = true
	if player.has_node("Hurtbox/CollisionShape3D"):
		(player.get_node("Hurtbox/CollisionShape3D") as CollisionShape3D).disabled = true

	_rider_cam = player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if _rider_cam:
		_rider_cam_base = _rider_cam.position
		_rider_cam.position = _mounted_cam_offset
		_rider_cam.current = true

	if player.has_method("tick_mounted_rider_pose"):
		player.call("tick_mounted_rider_pose", 0.0, 0.0, false)

	_refresh_prompt()
	if status_label:
		status_label.visible = true
		status_label.text = "Mounted · E dismount · Shift gallop"


func dismount() -> void:
	if rider == null:
		return
	var player := rider
	rider = null
	_cooldown = MOUNT_COOLDOWN

	if _rider_cam:
		_rider_cam.position = _rider_cam_base
		_rider_cam = null

	var world := get_tree().current_scene
	if world == null:
		world = get_parent()
	var side := global_transform.basis.x * DISMOUNT_SIDE
	var drop_pos := global_position + side + Vector3(0.0, 0.1, 0.0)

	var seat_parent := player.get_parent()
	if seat_parent:
		seat_parent.remove_child(player)
	world.add_child(player)
	player.global_position = drop_pos
	player.rotation.y = rotation.y

	if player.has_node("CollisionShape3D"):
		(player.get_node("CollisionShape3D") as CollisionShape3D).disabled = false
	if player.has_node("Hurtbox/CollisionShape3D"):
		(player.get_node("Hurtbox/CollisionShape3D") as CollisionShape3D).disabled = false

	if player.has_method("clear_mount"):
		player.call("clear_mount")

	_refresh_prompt()
	if status_label:
		status_label.visible = false


func is_mounted() -> bool:
	return rider != null


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



func _on_zone_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body is CharacterBody3D:
		_player_near = body as CharacterBody3D
		_refresh_prompt()


func _on_zone_exited(body: Node3D) -> void:
	if body == _player_near:
		_player_near = null
		_refresh_prompt()


func _refresh_prompt() -> void:
	if prompt == null:
		return
	if rider:
		prompt.visible = false
		return
	if _player_near:
		prompt.text = "E  Mount horse"
		prompt.visible = true
	else:
		prompt.visible = false


func _update_status(gallop: bool, speed: float) -> void:
	if status_label == null or not status_label.visible:
		return
	var gait := "idle"
	if speed > 0.4:
		gait = "gallop" if gallop else "trot"
	status_label.text = "Mounted · %s · E dismount · Shift gallop" % gait
