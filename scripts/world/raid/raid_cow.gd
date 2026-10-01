extends CharacterBody3D
## Raid cattle with hybrid goad physics: light path bias + goad / proximity authority.
## Idle wander → herded (raid on) → driven (prodded / pressured) → delivered.

const IDLE_SPEED := 0.55
const DRIVE_SPEED := 2.85
const PATH_BIAS_SPEED := 1.75
const SOFT_FOLLOW_SPEED := 0.95
const ARRIVE_DIST := 1.35
const GOAD_IMPULSE := 7.2
const GOAD_LATERAL := 1.35
const PROXIMITY_RADIUS := 3.4
const PROXIMITY_FORCE := 3.1
const PROXIMITY_DRIVE_TIME := 0.45
const SEPARATION_RADIUS := 1.6
const SEPARATION_FORCE := 1.8
const GOAD_VEL_DAMP := 3.6
const DRIVEN_HOLD := 7.5

@export var cow_id: int = 0

var herded: bool = false
var driven: bool = false
var delivered: bool = false

var _home: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _player: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _goad_vel: Vector3 = Vector3.ZERO
var _driven_timer: float = 0.0
var _react_timer: float = 0.0
var _prox_accum: float = 0.0
var _path_points: Array[Vector3] = []
var _home_pens: Vector3 = Vector3.ZERO
var _has_home_pens: bool = false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("raid_cattle")
	_home = global_position
	_pick_wander()
	# Unique material so driven/delivered/react tint does not leak across the herd.
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


func set_path_bias(points: Array, home_pens: Vector3) -> void:
	_path_points.clear()
	for p in points:
		if p is Vector3:
			_path_points.append(p)
	_home_pens = home_pens
	_has_home_pens = true


## Raid started — cows are cut out but wait for goad / proximity pressure.
func begin_herd() -> void:
	if delivered:
		return
	herded = true
	driven = false
	_driven_timer = 0.0
	_prox_accum = 0.0
	_refresh_visual()


## Compat + debug: mark immediately driven (force-deliver / smoke).
func start_driven() -> void:
	if delivered:
		return
	herded = true
	driven = true
	_driven_timer = DRIVEN_HOLD
	_refresh_visual()


func stop_driven() -> void:
	driven = false
	herded = false
	_driven_timer = 0.0
	_goad_vel = Vector3.ZERO
	_prox_accum = 0.0
	_refresh_visual()


func mark_delivered() -> void:
	driven = false
	herded = false
	delivered = true
	velocity = Vector3.ZERO
	_goad_vel = Vector3.ZERO
	_refresh_visual()


func reset_to_pen(pen_pos: Vector3) -> void:
	global_position = pen_pos
	_home = pen_pos
	driven = false
	herded = false
	delivered = false
	velocity = Vector3.ZERO
	_goad_vel = Vector3.ZERO
	_driven_timer = 0.0
	_prox_accum = 0.0
	_react_timer = 0.0
	_pick_wander()
	_refresh_visual()


## Goad hit / prod — impulse peel + driven authority.
func apply_goad(from_pos: Vector3, forward: Vector3, strength: float = 1.0, kind: StringName = &"light") -> void:
	if delivered:
		return
	herded = true
	var push := forward
	push.y = 0.0
	if push.length_squared() < 0.01:
		push = global_position - from_pos
		push.y = 0.0
	if push.length_squared() < 0.01:
		push = Vector3.FORWARD
	push = push.normalized()
	# Lateral peel by cow_id so herd fans instead of stacking.
	var side := Vector3(-push.z, 0.0, push.x)
	var peel := float((cow_id % 3) - 1) * GOAD_LATERAL * (0.65 + 0.35 * strength)
	var mag := GOAD_IMPULSE * strength * (1.4 if kind == &"heavy" else 1.0)
	_goad_vel += push * mag + side * peel
	driven = true
	_driven_timer = DRIVEN_HOLD * (1.15 if kind == &"heavy" else 1.0)
	_prox_accum = 0.0
	_flash_react(kind)
	_spawn_prod_vfx(push)
	_notify_goaded(kind)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if delivered:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	if _react_timer > 0.0:
		_react_timer -= delta
		if _react_timer <= 0.0:
			_refresh_visual()

	# Decay goad impulse.
	if _goad_vel.length_squared() > 0.0001:
		_goad_vel = _goad_vel.move_toward(Vector3.ZERO, GOAD_VEL_DAMP * delta * 2.4)
	else:
		_goad_vel = Vector3.ZERO

	if driven:
		_driven_timer = maxf(0.0, _driven_timer - delta)
		# Once cut into the drove, stay driven until deliver / fail / reset.
		# Timer only gates how "fresh" the goad impulse feels (HUD label stays "drove").

	var horiz := Vector3.ZERO

	if herded or driven:
		_apply_proximity_pressure(delta)
		horiz += _goad_vel
		if driven:
			horiz += _path_bias_velocity()
			horiz += _soft_follow_velocity() * 0.55
			horiz += _separation_velocity()
		elif herded:
			# Loose milling near home until goaded.
			horiz += _wander_velocity() * 0.7
			horiz += _separation_velocity() * 0.5
	else:
		horiz += _wander_velocity()

	# Cap horizontal speed.
	var max_spd := DRIVE_SPEED if driven else (IDLE_SPEED * 1.4 if herded else IDLE_SPEED)
	var h2 := Vector3(horiz.x, 0.0, horiz.z)
	if h2.length() > max_spd:
		h2 = h2.normalized() * max_spd
	velocity.x = h2.x
	velocity.z = h2.z

	if h2.length() > 0.18:
		look_at(global_position + h2, Vector3.UP)

	move_and_slide()


func _apply_proximity_pressure(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_prox_accum = 0.0
		return
	if not _player_has_goad():
		_prox_accum = 0.0
		return
	var to_cow := global_position - _player.global_position
	to_cow.y = 0.0
	var dist := to_cow.length()
	if dist > PROXIMITY_RADIUS or dist < 0.15:
		_prox_accum = maxf(0.0, _prox_accum - delta)
		return
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return
	fwd = fwd.normalized()
	var away := to_cow.normalized()
	# Facing toward cow (player looking roughly at it) OR standing behind it.
	var facing := fwd.dot(away)
	if facing < 0.15:
		_prox_accum = maxf(0.0, _prox_accum - delta * 0.5)
		return
	var falloff := 1.0 - (dist / PROXIMITY_RADIUS)
	var push_dir := (fwd * 0.7 + away * 0.3).normalized()
	_goad_vel += push_dir * (PROXIMITY_FORCE * falloff * delta * 3.2)
	_prox_accum += delta * (0.7 + falloff)
	if _prox_accum >= PROXIMITY_DRIVE_TIME:
		if not driven:
			driven = true
			_refresh_visual()
		_driven_timer = maxf(_driven_timer, DRIVEN_HOLD * 0.65)


func _player_has_goad() -> bool:
	if _player == null:
		return false
	var combat := _player.get_node_or_null("CombatSystem")
	if combat == null:
		return false
	if combat.has_method("weapon_name"):
		return StringName(combat.call("weapon_name")) == &"goad"
	return int(combat.get("current_weapon")) == 2  # CombatSystem.Weapon.GOAD


func _player_nearby_goad(radius: float) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if not _player_has_goad():
		return false
	var d := global_position.distance_to(_player.global_position)
	return d <= radius


func _path_bias_velocity() -> Vector3:
	var target := _next_path_target()
	var desired := target - global_position
	desired.y = 0.0
	if desired.length() < 0.4:
		return Vector3.ZERO
	return desired.normalized() * PATH_BIAS_SPEED


func _next_path_target() -> Vector3:
	if _has_home_pens:
		# Walk path markers in order, then home pens.
		var best := _home_pens
		var best_score := -1.0
		var pos := global_position
		for i in _path_points.size():
			var pt: Vector3 = _path_points[i]
			var to_home := _home_pens - pt
			to_home.y = 0.0
			var from_cow := pt - pos
			from_cow.y = 0.0
			# Prefer the next unreached marker along the escape (closer to home than cow is).
			var cow_home := _home_pens - pos
			cow_home.y = 0.0
			if from_cow.length() < 2.2:
				continue
			if pt.distance_to(_home_pens) < pos.distance_to(_home_pens) - 0.5:
				var score := 100.0 - from_cow.length() + float(i) * 0.1
				if score > best_score:
					best_score = score
					best = pt
		if best_score < 0.0:
			return _home_pens
		return best
	if _path_points.size() > 0:
		return _path_points[_path_points.size() - 1]
	return _home


func _soft_follow_velocity() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist < ARRIVE_DIST or dist > 14.0:
		return Vector3.ZERO
	# Trail slot — light only; goad + path own authority.
	var back := -_player.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.01:
		back = Vector3.FORWARD
	back = back.normalized()
	var side := _player.global_transform.basis.x
	side.y = 0.0
	side = side.normalized()
	var slot := float((cow_id % 3) - 1) * 1.1
	var follow_pt := _player.global_position + back * (2.4 + float(cow_id) * 0.45) + side * slot
	var desired := follow_pt - global_position
	desired.y = 0.0
	if desired.length() < 0.35:
		return Vector3.ZERO
	return desired.normalized() * SOFT_FOLLOW_SPEED


func _separation_velocity() -> Vector3:
	var push := Vector3.ZERO
	var tree := get_tree()
	if tree == null:
		return push
	for other in tree.get_nodes_in_group("raid_cattle"):
		if other == self or other == null or not is_instance_valid(other):
			continue
		if other is Node3D and bool(other.get("delivered")):
			continue
		var opos: Vector3 = (other as Node3D).global_position
		var delta := global_position - opos
		delta.y = 0.0
		var d := delta.length()
		if d > 0.05 and d < SEPARATION_RADIUS:
			push += delta.normalized() * (SEPARATION_FORCE * (1.0 - d / SEPARATION_RADIUS))
	return push


func _wander_velocity() -> Vector3:
	_wander_timer -= get_physics_process_delta_time()
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 0.4:
		_pick_wander()
	var desired := _wander_target - global_position
	desired.y = 0.0
	if desired.length() > 0.2:
		return desired.normalized() * IDLE_SPEED
	return Vector3.ZERO


func _pick_wander() -> void:
	_wander_timer = randf_range(2.0, 4.5)
	var radius := 2.8 if herded else 2.2
	var offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
	_wander_target = _home + offset


func _flash_react(kind: StringName = &"light") -> void:
	_react_timer = 0.55 if kind == &"heavy" else 0.4
	var flash := Color(0.95, 0.82, 0.35) if kind != &"heavy" else Color(1.0, 0.72, 0.28)
	for node_name in ["MeshInstance3D", "Head"]:
		var mi := get_node_or_null(node_name) as MeshInstance3D
		if mi and mi.get_active_material(0) is StandardMaterial3D:
			(mi.get_active_material(0) as StandardMaterial3D).albedo_color = flash
	if label:
		label.text = "prodded!" if kind != &"heavy" else "drove!"
		label.modulate = Color(1.0, 0.9, 0.4)


func _spawn_prod_vfx(push_dir: Vector3) -> void:
	# Lightweight poke spark — no dependency on kerne mesh builder / unmerged anims.
	var spark := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	spark.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.35, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.set_surface_override_material(0, mat)
	spark.position = Vector3(0.0, 0.85, 0.0) - push_dir.normalized() * 0.35
	add_child(spark)
	var tw := create_tween()
	tw.tween_property(spark, "scale", Vector3(2.2, 2.2, 2.2), 0.28)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.tween_callback(spark.queue_free)



func _notify_goaded(kind: StringName) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var director := tree.get_first_node_in_group("cattle_raid")
	if director and director.has_signal("cow_goaded"):
		director.emit_signal("cow_goaded", cow_id, kind)


func _refresh_visual() -> void:
	if _react_timer > 0.0:
		return
	var color := Color(0.55, 0.42, 0.28)
	if delivered:
		color = Color(0.55, 0.72, 0.4)
	elif driven:
		color = Color(0.72, 0.55, 0.28)
	elif herded:
		color = Color(0.62, 0.48, 0.3)
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
		elif herded:
			label.text = "herd"
			label.modulate = Color(0.9, 0.8, 0.55)
		else:
			label.text = "cattle"
			label.modulate = Color(0.85, 0.78, 0.6)
