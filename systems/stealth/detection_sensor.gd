extends Node3D
## Greybox detection: vision cone + LOS ray + hearing. States unaware → suspicious → alert.
## Parent should face the look direction (forward = -Z).

enum Awareness { UNAWARE, SUSPICIOUS, ALERT }

signal awareness_changed(prev: Awareness, next: Awareness)
signal alerted(target: Node3D)

@export var view_distance: float = 14.0
@export var view_half_angle_deg: float = 42.0
@export var hearing_range: float = 9.0
@export var eye_height: float = 1.55
@export var suspicious_threshold: float = 0.35
@export var alert_threshold: float = 0.85
@export var raise_rate_seen: float = 1.15
@export var raise_rate_heard: float = 0.55
@export var decay_rate: float = 0.32
@export var show_debug_cone: bool = true
## Seen while still wet and muddy from the bog, inside this range: one meter
## bump per wet spell (scaled by how wet). Target supplies get_wet_suspicion().
@export var wet_suspicion_range: float = 5.0
@export var wet_suspicion_bump: float = 0.3

var awareness: Awareness = Awareness.UNAWARE
var meter: float = 0.0
var last_known_position: Vector3 = Vector3.ZERO

var _player: Node3D
var _label: Label3D
var _cone: MeshInstance3D
var _seeing: bool = false
var _hearing: bool = false
var _wet_bumped: bool = false
var _wet_noticed: bool = false


func _ready() -> void:
	_ensure_indicator()
	if show_debug_cone:
		_ensure_cone()
	_find_player()
	_refresh_indicator()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
	_seeing = false
	_hearing = false
	var stimulus := 0.0
	if _player:
		stimulus = _evaluate_stimulus(_player)
		if stimulus > 0.0:
			last_known_position = _player.global_position
	if stimulus > 0.0:
		meter = minf(1.0, meter + stimulus * delta)
	else:
		meter = maxf(0.0, meter - decay_rate * delta)
	_update_awareness()
	_refresh_indicator()


func get_awareness_name() -> String:
	match awareness:
		Awareness.SUSPICIOUS:
			return "SUSPICIOUS"
		Awareness.ALERT:
			return "ALERT"
		_:
			return "UNAWARE"


func force_awareness(level: Awareness, meter_value: float = -1.0) -> void:
	## Test / screenshot helper.
	if meter_value >= 0.0:
		meter = clampf(meter_value, 0.0, 1.0)
	else:
		match level:
			Awareness.UNAWARE:
				meter = 0.0
			Awareness.SUSPICIOUS:
				meter = (suspicious_threshold + alert_threshold) * 0.5
			Awareness.ALERT:
				meter = 1.0
	_set_awareness(level)


func _evaluate_stimulus(target: Node3D) -> float:
	var eye := global_position + Vector3(0.0, eye_height, 0.0)
	var aim := _visibility_point(target)
	var to_target := aim - eye
	var dist := to_target.length()
	if dist < 0.05:
		return raise_rate_seen * 2.0

	var noise := 0.0
	var vis_factor := 1.0
	if target.has_method("get_noise_level"):
		noise = float(target.call("get_noise_level"))
	if target.has_method("get_visibility_factor"):
		vis_factor = float(target.call("get_visibility_factor"))
	# A loud event (bog gasp) can carry past the footstep hearing range.
	var hear_range := hearing_range
	if target.has_method("get_noise_radius"):
		hear_range = maxf(hearing_range, float(target.call("get_noise_radius")))

	# Hearing (omnidirectional, crouch quiets footprint).
	if dist <= hear_range and noise > 0.12:
		var hear_falloff := 1.0 - (dist / hear_range)
		_hearing = true
		# Pure hearing alone never instantly alerts — feeds meter slowly.
		var heard := raise_rate_heard * noise * hear_falloff
		# Vision check below may stack.
		var seen := _try_vision(eye, aim, to_target, dist, vis_factor)
		return maxf(heard, seen)

	return _try_vision(eye, aim, to_target, dist, vis_factor)


func _try_vision(eye: Vector3, aim: Vector3, to_target: Vector3, dist: float, vis_factor: float) -> float:
	if dist > view_distance:
		return 0.0
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var flat := to_target
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	var ang := rad_to_deg(acos(clampf(forward.dot(flat), -1.0, 1.0)))
	if ang > view_half_angle_deg:
		return 0.0
	if not _has_line_of_sight(eye, aim):
		return 0.0
	_seeing = true
	_check_wet_suspicion(dist)
	var dist_factor := 1.0 - (dist / view_distance)
	var center_bonus := 1.0 - (ang / view_half_angle_deg) * 0.35
	return raise_rate_seen * dist_factor * center_bonus * vis_factor


func _check_wet_suspicion(dist: float) -> void:
	## Wet, muddy clothes on land are a tell up close. One bump per wet spell.
	if _player == null or not _player.has_method("get_wet_suspicion"):
		return
	var wet := float(_player.call("get_wet_suspicion"))
	if wet <= 0.02:
		# Dried off (or back under): the next wet spell can bump again.
		if _player.has_method("get_wet_level") and float(_player.call("get_wet_level")) <= 0.001:
			_wet_bumped = false
		return
	if _wet_bumped or dist > wet_suspicion_range:
		return
	_wet_bumped = true
	_wet_noticed = true
	meter = minf(1.0, meter + wet_suspicion_bump * clampf(wet, 0.0, 1.0))


## True once this sensor has bumped for a wet, muddy target (probe / HUD).
func noticed_wet() -> bool:
	return _wet_noticed


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Hit world (layer 1). Ignore player/enemy/hurtboxes.
	query.collision_mask = 1
	query.exclude = _exclude_rids()
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _exclude_rids() -> Array[RID]:
	var out: Array[RID] = []
	var host := get_parent()
	if host is CollisionObject3D:
		out.append((host as CollisionObject3D).get_rid())
	if _player is CollisionObject3D:
		out.append((_player as CollisionObject3D).get_rid())
	return out


func _visibility_point(target: Node3D) -> Vector3:
	if target.has_method("get_visibility_point"):
		return target.call("get_visibility_point") as Vector3
	return target.global_position + Vector3(0.0, 1.2, 0.0)


func _update_awareness() -> void:
	var next := Awareness.UNAWARE
	if meter >= alert_threshold:
		next = Awareness.ALERT
	elif meter >= suspicious_threshold:
		next = Awareness.SUSPICIOUS
	_set_awareness(next)


func _set_awareness(next: Awareness) -> void:
	if next == awareness:
		return
	var prev := awareness
	awareness = next
	awareness_changed.emit(prev, next)
	if next == Awareness.ALERT and _player:
		alerted.emit(_player)


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _ensure_indicator() -> void:
	_label = get_node_or_null("AwarenessLabel") as Label3D
	if _label:
		return
	_label = Label3D.new()
	_label.name = "AwarenessLabel"
	_label.position = Vector3(0.0, 2.35, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.outline_size = 8
	_label.modulate = Color.WHITE
	add_child(_label)


func _ensure_cone() -> void:
	_cone = get_node_or_null("VisionCone") as MeshInstance3D
	if _cone:
		return
	_cone = MeshInstance3D.new()
	_cone.name = "VisionCone"
	# Thin wedge marker on the ground in look direction (readable greybox, not a full FOV mesh).
	var wedge := ImmediateMesh.new()
	_cone.mesh = wedge
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.85, 0.3, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone.material_override = mat
	add_child(_cone)
	_rebuild_cone_mesh()


func _rebuild_cone_mesh() -> void:
	if _cone == null or not (_cone.mesh is ImmediateMesh):
		return
	var im := _cone.mesh as ImmediateMesh
	im.clear_surfaces()
	var half := deg_to_rad(view_half_angle_deg)
	var reach := minf(view_distance, 8.0)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(0.0, 0.05, 0.0)
	var left := Vector3(-sin(half) * reach, 0.05, -cos(half) * reach)
	var right := Vector3(sin(half) * reach, 0.05, -cos(half) * reach)
	im.surface_add_vertex(origin)
	im.surface_add_vertex(left)
	im.surface_add_vertex(right)
	im.surface_end()


func _refresh_indicator() -> void:
	if _label == null:
		return
	var glyph := "[o]"
	var state := get_awareness_name()
	var color := Color(0.55, 0.75, 0.55)
	match awareness:
		Awareness.SUSPICIOUS:
			color = Color(0.95, 0.82, 0.25)
			glyph = "[?]"
		Awareness.ALERT:
			color = Color(0.95, 0.25, 0.2)
			glyph = "[!]"
		_:
			glyph = "[o]"
	var sense := ""
	if _seeing:
		sense = " [LOS]"
	elif _hearing:
		sense = " [hear]"
	_label.text = "%s %s\n%3d%%%s" % [glyph, state, int(meter * 100.0), sense]
	_label.modulate = color
	if _cone and _cone.material_override is StandardMaterial3D:
		var mat := _cone.material_override as StandardMaterial3D
		var c := color
		c.a = 0.18 if awareness == Awareness.UNAWARE else 0.28
		mat.albedo_color = c
