extends CharacterBody3D
## Placeholder cattle for the cattle-raid greybox. Idle wander → driven follow.

const IDLE_SPEED := 0.55
const DRIVE_SPEED := 3.4
const ARRIVE_DIST := 1.35

@export var cow_id: int = 0

var driven: bool = false
var delivered: bool = false
var _home: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _player: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("raid_cattle")
	_home = global_position
	_pick_wander()
	# Unique material so driven/delivered tint does not leak across the herd.
	if mesh:
		var src := mesh.get_active_material(0)
		if src:
			mesh.set_surface_override_material(0, src.duplicate())
		var head := get_node_or_null("Head") as MeshInstance3D
		if head:
			var hsrc := head.get_active_material(0)
			if hsrc:
				head.set_surface_override_material(0, hsrc.duplicate())
	_refresh_visual()


func set_player(player: Node3D) -> void:
	_player = player


func start_driven() -> void:
	if delivered:
		return
	driven = true
	_refresh_visual()


func stop_driven() -> void:
	driven = false
	_refresh_visual()


func mark_delivered() -> void:
	driven = false
	delivered = true
	velocity = Vector3.ZERO
	_refresh_visual()


func reset_to_pen(pen_pos: Vector3) -> void:
	global_position = pen_pos
	_home = pen_pos
	driven = false
	delivered = false
	velocity = Vector3.ZERO
	_pick_wander()
	_refresh_visual()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if delivered:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	if driven and _player != null and is_instance_valid(_player):
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		if dist > ARRIVE_DIST:
			# Trail behind player with a slight lateral offset by cow_id.
			var back := -_player.global_transform.basis.z
			back.y = 0.0
			if back.length_squared() < 0.01:
				back = Vector3.FORWARD
			back = back.normalized()
			var side := _player.global_transform.basis.x
			side.y = 0.0
			side = side.normalized()
			var slot := float((cow_id % 3) - 1) * 1.1
			var follow_pt := _player.global_position + back * (2.2 + float(cow_id) * 0.55) + side * slot
			var desired := follow_pt - global_position
			desired.y = 0.0
			if desired.length() > 0.15:
				desired = desired.normalized() * DRIVE_SPEED
				velocity.x = desired.x
				velocity.z = desired.z
				look_at(global_position + Vector3(desired.x, 0.0, desired.z), Vector3.UP)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 0.4:
			_pick_wander()
		var desired2 := _wander_target - global_position
		desired2.y = 0.0
		if desired2.length() > 0.2:
			desired2 = desired2.normalized() * IDLE_SPEED
			velocity.x = desired2.x
			velocity.z = desired2.z
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()


func _pick_wander() -> void:
	_wander_timer = randf_range(2.0, 4.5)
	var offset := Vector3(randf_range(-2.2, 2.2), 0.0, randf_range(-2.2, 2.2))
	_wander_target = _home + offset


func _refresh_visual() -> void:
	var color := Color(0.55, 0.42, 0.28)
	if delivered:
		color = Color(0.55, 0.72, 0.4)
	elif driven:
		color = Color(0.72, 0.55, 0.28)
	for node_name in ["MeshInstance3D", "Head"]:
		var mi := get_node_or_null(node_name) as MeshInstance3D
		if mi and mi.get_active_material(0) is StandardMaterial3D:
			(mi.get_active_material(0) as StandardMaterial3D).albedo_color = color
	if label:
		if delivered:
			label.text = "delivered"
			label.modulate = Color(0.7, 0.9, 0.55)
		elif driven:
			label.text = "drove"
			label.modulate = Color(0.95, 0.85, 0.45)
		else:
			label.text = "cattle"
			label.modulate = Color(0.85, 0.78, 0.6)
