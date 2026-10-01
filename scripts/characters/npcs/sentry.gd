extends CharacterBody3D
## Stationary watchman greybox: detection only (no combat AI). Turns slightly when suspicious.

@onready var sensor: Node3D = $DetectionSensor
@onready var visual: Node3D = $Visual

var _player: Node3D
var _rest_yaw: float = 0.0
var _look_tween: Tween


func _ready() -> void:
	_rest_yaw = rotation.y
	add_to_group("sentry")
	if sensor and sensor.has_signal("awareness_changed"):
		sensor.awareness_changed.connect(_on_awareness_changed)
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if sensor == null:
		return
	var aw = sensor.get("awareness")
	# Soft face last-known / player when suspicious or alert.
	if aw == null:
		return
	# DetectionSensor.Awareness: UNAWARE=0 SUSPICIOUS=1 ALERT=2
	if int(aw) >= 1 and _player:
		var to_p := _player.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.01:
			var target_yaw := atan2(-to_p.x, -to_p.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 2.2 * delta)
	elif int(aw) == 0:
		rotation.y = lerp_angle(rotation.y, _rest_yaw, 1.2 * delta)


func _on_awareness_changed(_prev: int, next: int) -> void:
	if visual == null:
		return
	# Tint body by awareness for readability at a glance.
	var body := visual.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var mat := body.get_active_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		body.material_override = mat
	if not (mat is StandardMaterial3D):
		return
	var sm := mat as StandardMaterial3D
	match next:
		1:
			sm.albedo_color = Color(0.65, 0.5, 0.2)
		2:
			sm.albedo_color = Color(0.7, 0.18, 0.15)
		_:
			sm.albedo_color = Color(0.25, 0.32, 0.45)
