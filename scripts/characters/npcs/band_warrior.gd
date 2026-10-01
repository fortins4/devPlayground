extends CharacterBody3D
## Greybox warrior follower — stands at muster or follows Cian. No combat AI yet.

const FOLLOW_SPEED := 4.6
const HOLD_SPEED := 3.8
const ARRIVE_DIST := 0.55
const FOLLOW_STOP := 1.15

enum Mode { FOLLOW, HOLD }

var mode: Mode = Mode.FOLLOW
var follow_target: Node3D = null
var hold_position: Vector3 = Vector3.ZERO
var follow_offset: Vector3 = Vector3(0.0, 0.0, 1.6)
var display_name: String = "Kerne"

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_refresh_label()


func set_follow(target: Node3D, offset: Vector3) -> void:
	follow_target = target
	follow_offset = offset
	mode = Mode.FOLLOW


func set_hold(world_pos: Vector3) -> void:
	hold_position = world_pos
	mode = Mode.HOLD


func set_display_name(n: String) -> void:
	display_name = n
	_refresh_label()


func _refresh_label() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label:
		label.text = display_name


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var goal := global_position
	var speed := FOLLOW_SPEED
	match mode:
		Mode.FOLLOW:
			if follow_target and is_instance_valid(follow_target):
				var basis := follow_target.global_transform.basis
				goal = follow_target.global_position + basis * follow_offset
			speed = FOLLOW_SPEED
		Mode.HOLD:
			goal = hold_position
			speed = HOLD_SPEED

	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var stop := FOLLOW_STOP if mode == Mode.FOLLOW else ARRIVE_DIST
	if dist > stop:
		var dir := to_goal.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 2.0 * delta)
		if mode == Mode.FOLLOW and follow_target and is_instance_valid(follow_target):
			var face := follow_target.global_position - global_position
			face.y = 0.0
			if face.length() > 0.1:
				look_at(global_position + face.normalized(), Vector3.UP)

	move_and_slide()
