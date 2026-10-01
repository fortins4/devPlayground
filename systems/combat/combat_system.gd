class_name CombatSystem
extends Node
## Reusable greybox combat component (hatchet-first cattle-farm kit).
## Attach as child of a CharacterBody3D (player or NPC). Expects optional siblings:
## Hitbox (Area3D), Hurtbox (Area3D), WeaponVisual (Node3D with mesh children).

signal attack_performed(attacker: Node, kind: StringName, weapon: StringName)
signal hit_landed(attacker: Node, target: Node, damage: float, kind: StringName)
signal damage_taken(amount: float, from: Node)
signal stamina_changed(current: float, maximum: float)
signal health_changed(current: float, maximum: float)
signal blocked(defender: Node, attacker: Node, mitigated: float)
signal died(victim: Node)
signal weapon_changed(weapon: StringName)

enum Weapon { HATCHET, KNIFE, GOAD }

const WEAPON_NAMES := {
	Weapon.HATCHET: &"hatchet",
	Weapon.KNIFE: &"knife",
	Weapon.GOAD: &"goad",
}

@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_regen_per_sec: float = 18.0
@export var sprint_stamina_per_sec: float = 22.0
@export var team: int = 0 ## 0 = player allies, 1 = hostiles
@export var starting_weapon: Weapon = Weapon.HATCHET
@export var enable_block: bool = false ## Shield later; off for cattle-farm starter kit
@export var enable_hit_feedback: bool = true
@export var hurt_flash_secs: float = 0.14
@export var knockback_light: float = 2.8
@export var knockback_heavy: float = 4.6
@export var hit_stop_light: float = 0.045
@export var hit_stop_heavy: float = 0.075
@export var show_damage_numbers: bool = true

var health: float = 100.0
var stamina: float = 100.0
var current_weapon: Weapon = Weapon.HATCHET
var is_dead: bool = false
var is_blocking: bool = false
var is_attacking: bool = false
var attack_recovery_left: float = 0.0
var hitbox_active_left: float = 0.0

var _hit_this_swing: Dictionary = {} ## instance_id -> true
var _owner_body: Node3D
var _hitbox: Area3D
var _hurtbox: Area3D
var _weapon_visual: Node3D
var _weapon_rest_transform: Transform3D
var _swing_tween: Tween
var _last_attack_kind: StringName = &"light"
var knockback_vel: Vector3 = Vector3.ZERO
var _hurt_flash_tween: Tween
var _hit_stop_running: bool = false
var _mesh_overlays: Array[MeshInstance3D] = []

# Per-weapon attack profiles: light / heavy
const PROFILES := {
	Weapon.HATCHET: {
		&"light": {"cost": 12.0, "damage": 14.0, "windup": 0.12, "active": 0.14, "recovery": 0.28, "reach": 1.35},
		&"heavy": {"cost": 28.0, "damage": 28.0, "windup": 0.22, "active": 0.18, "recovery": 0.45, "reach": 1.5},
	},
	Weapon.KNIFE: {
		&"light": {"cost": 8.0, "damage": 8.0, "windup": 0.06, "active": 0.1, "recovery": 0.16, "reach": 1.0},
		&"heavy": {"cost": 18.0, "damage": 16.0, "windup": 0.12, "active": 0.12, "recovery": 0.28, "reach": 1.1},
	},
	Weapon.GOAD: {
		&"light": {"cost": 10.0, "damage": 10.0, "windup": 0.14, "active": 0.12, "recovery": 0.26, "reach": 1.7},
		&"heavy": {"cost": 22.0, "damage": 20.0, "windup": 0.2, "active": 0.16, "recovery": 0.4, "reach": 1.85},
	},
}


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	current_weapon = starting_weapon
	_owner_body = get_parent() as Node3D
	_hitbox = get_node_or_null("../Hitbox") as Area3D
	if _hitbox == null:
		_hitbox = get_node_or_null("Hitbox") as Area3D
	_hurtbox = get_node_or_null("../Hurtbox") as Area3D
	if _hurtbox == null:
		_hurtbox = get_node_or_null("Hurtbox") as Area3D
	_weapon_visual = get_node_or_null("../WeaponVisual") as Node3D
	if _weapon_visual == null:
		_weapon_visual = get_node_or_null("WeaponVisual") as Node3D
	if _hitbox:
		_hitbox.monitoring = false
		_hitbox.monitorable = false
		if not _hitbox.body_entered.is_connected(_on_hitbox_body_entered):
			_hitbox.body_entered.connect(_on_hitbox_body_entered)
		if not _hitbox.area_entered.is_connected(_on_hitbox_area_entered):
			_hitbox.area_entered.connect(_on_hitbox_area_entered)
	if _weapon_visual:
		_weapon_rest_transform = _weapon_visual.transform
	_apply_weapon_visual()
	stamina_changed.emit(stamina, max_stamina)
	health_changed.emit(health, max_health)
	weapon_changed.emit(WEAPON_NAMES[current_weapon])


func _physics_process(delta: float) -> void:
	if knockback_vel.length_squared() > 0.0001:
		knockback_vel = knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)
	else:
		knockback_vel = Vector3.ZERO

	if is_dead:
		return

	if attack_recovery_left > 0.0:
		attack_recovery_left = maxf(0.0, attack_recovery_left - delta)
		if attack_recovery_left <= 0.0:
			is_attacking = false

	if hitbox_active_left > 0.0:
		hitbox_active_left = maxf(0.0, hitbox_active_left - delta)
		if hitbox_active_left <= 0.0 and _hitbox:
			_hitbox.monitoring = false

	var regenerating := not is_attacking and not is_blocking
	if regenerating and stamina < max_stamina:
		stamina = minf(max_stamina, stamina + stamina_regen_per_sec * delta)
		stamina_changed.emit(stamina, max_stamina)

	if is_blocking and enable_block:
		var block_drain := 8.0 * delta
		if stamina >= block_drain:
			stamina -= block_drain
			stamina_changed.emit(stamina, max_stamina)
		else:
			is_blocking = false


func weapon_name() -> StringName:
	return WEAPON_NAMES[current_weapon]


func can_move() -> bool:
	return not is_dead and attack_recovery_left <= 0.05


func is_in_recovery() -> bool:
	return attack_recovery_left > 0.0


func set_weapon(weapon: Weapon) -> void:
	if is_attacking:
		return
	current_weapon = weapon
	_apply_weapon_visual()
	weapon_changed.emit(WEAPON_NAMES[current_weapon])


func cycle_weapon(direction: int = 1) -> void:
	var values: Array = [Weapon.HATCHET, Weapon.KNIFE, Weapon.GOAD]
	var idx := values.find(current_weapon)
	idx = (idx + direction) % values.size()
	if idx < 0:
		idx += values.size()
	set_weapon(values[idx])


func try_sprint_drain(delta: float) -> bool:
	if is_dead or is_attacking:
		return false
	var cost := sprint_stamina_per_sec * delta
	if stamina < cost * 0.5:
		return false
	stamina = maxf(0.0, stamina - cost)
	stamina_changed.emit(stamina, max_stamina)
	return stamina > 0.0


func try_attack(kind: StringName = &"light") -> bool:
	if is_dead or is_attacking:
		return false
	var profile: Dictionary = PROFILES[current_weapon].get(kind, PROFILES[current_weapon][&"light"])
	var cost: float = profile["cost"]
	if stamina < cost:
		return false
	stamina -= cost
	stamina_changed.emit(stamina, max_stamina)
	is_attacking = true
	is_blocking = false
	_hit_this_swing.clear()
	var windup: float = profile["windup"]
	var active: float = profile["active"]
	var recovery: float = profile["recovery"]
	attack_recovery_left = windup + active + recovery
	_last_attack_kind = kind
	_play_weapon_swing(kind, windup, active, recovery)
	attack_performed.emit(_owner_body, kind, WEAPON_NAMES[current_weapon])
	_activate_hitbox_after(windup, active, profile["reach"], profile["damage"], kind)
	return true


func set_blocking(holding: bool) -> void:
	if not enable_block or is_dead or is_attacking:
		is_blocking = false
		return
	is_blocking = holding and stamina > 5.0


func apply_damage(amount: float, from: Node = null, frontal: bool = true) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var mitigated := 0.0
	if enable_block and is_blocking and frontal and stamina > 0.0:
		mitigated = amount * 0.75
		amount -= mitigated
		stamina = maxf(0.0, stamina - 12.0)
		stamina_changed.emit(stamina, max_stamina)
		blocked.emit(_owner_body, from, mitigated)
		if amount <= 0.01:
			return 0.0
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	damage_taken.emit(amount, from)
	if enable_hit_feedback:
		_play_hurt_feedback(amount, from)
	if health <= 0.0:
		_die()
	return amount


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	is_attacking = false
	is_blocking = false
	if _hitbox:
		_hitbox.monitoring = false
	reset_weapon_pose()
	died.emit(_owner_body)


func _activate_hitbox_after(windup: float, active: float, reach: float, damage: float, kind: StringName) -> void:
	await get_tree().create_timer(windup).timeout
	if is_dead or not is_instance_valid(self):
		return
	if _hitbox:
		_position_hitbox(reach)
		_hitbox.set_meta("damage", damage)
		_hitbox.set_meta("kind", kind)
		_hitbox.monitoring = true
		hitbox_active_left = active
		# Immediate overlap check (bodies already inside)
		for body in _hitbox.get_overlapping_bodies():
			_try_damage_target(body, damage, kind)
		for area in _hitbox.get_overlapping_areas():
			_on_hitbox_area_entered(area)


func _position_hitbox(reach: float) -> void:
	if _hitbox == null or _owner_body == null:
		return
	# Local -Z is facing forward for CharacterBody3D yaw
	_hitbox.position = Vector3(0.0, 1.0, -reach * 0.55)
	var shape_node := _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node and shape_node.shape is BoxShape3D:
		var box := (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
		box.size = Vector3(0.55, 0.7, reach * 0.9)
		shape_node.shape = box


func _on_hitbox_body_entered(body: Node) -> void:
	if not _hitbox or not _hitbox.monitoring:
		return
	var damage: float = float(_hitbox.get_meta("damage", 10.0))
	var kind: StringName = _hitbox.get_meta("kind", &"light")
	_try_damage_target(body, damage, kind)


func _on_hitbox_area_entered(area: Area3D) -> void:
	if not _hitbox or not _hitbox.monitoring:
		return
	var target := area.get_parent()
	if target == null:
		return
	var damage: float = float(_hitbox.get_meta("damage", 10.0))
	var kind: StringName = _hitbox.get_meta("kind", &"light")
	_try_damage_target(target, damage, kind)


func _try_damage_target(target: Node, damage: float, kind: StringName) -> void:
	if target == null or target == _owner_body:
		return
	var id := target.get_instance_id()
	if _hit_this_swing.has(id):
		return
	var other: CombatSystem = _find_combat(target)
	if other == null:
		# Hurtbox parent may be the combatant
		if target is Area3D:
			other = _find_combat(target.get_parent())
	if other == null or other == self or other.is_dead:
		return
	if other.team == team:
		return
	_hit_this_swing[id] = true
	var facing_ok := _is_frontal(other)
	var dealt := other.apply_damage(damage, _owner_body, facing_ok)
	if dealt > 0.0:
		hit_landed.emit(_owner_body, other.get_parent(), dealt, kind)
		if enable_hit_feedback:
			_play_hit_confirm(kind)


func _is_frontal(other: CombatSystem) -> bool:
	var defender_body := other.get_parent() as Node3D
	if defender_body == null or _owner_body == null:
		return true
	var to_attacker: Vector3 = _owner_body.global_position - defender_body.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		return true
	var defender_fwd: Vector3 = -defender_body.global_transform.basis.z
	defender_fwd.y = 0.0
	if defender_fwd.length_squared() < 0.001:
		return true
	return defender_fwd.normalized().dot(to_attacker.normalized()) > 0.25


func _find_combat(node: Node) -> CombatSystem:
	if node == null:
		return null
	if node is CombatSystem:
		return node
	var child := node.get_node_or_null("CombatSystem")
	if child is CombatSystem:
		return child
	return null


func _apply_weapon_visual() -> void:
	if _weapon_visual == null:
		return
	for child in _weapon_visual.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	var wname := String(WEAPON_NAMES[current_weapon]).capitalize()
	# Expect Hatchet / Knife / Goad mesh children
	var mesh := _weapon_visual.get_node_or_null(wname)
	if mesh is Node3D:
		(mesh as Node3D).visible = true
	else:
		# fallback: show first child
		if _weapon_visual.get_child_count() > 0 and _weapon_visual.get_child(0) is Node3D:
			(_weapon_visual.get_child(0) as Node3D).visible = true


func _play_weapon_swing(kind: StringName, windup: float, active: float, recovery: float) -> void:
	if _weapon_visual == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_weapon_visual.transform = _weapon_rest_transform

	var poses := _swing_poses(kind)
	var windup_rot: Vector3 = poses["windup_rot"]
	var contact_rot: Vector3 = poses["contact_rot"]
	var follow_rot: Vector3 = poses["follow_rot"]
	var windup_pos: Vector3 = poses["windup_pos"]
	var contact_pos: Vector3 = poses["contact_pos"]
	var follow_pos: Vector3 = poses["follow_pos"]
	var rest_rot := Vector3(
		rad_to_deg(_weapon_rest_transform.basis.get_euler().x),
		rad_to_deg(_weapon_rest_transform.basis.get_euler().y),
		rad_to_deg(_weapon_rest_transform.basis.get_euler().z)
	)

	_swing_tween = create_tween()
	_swing_tween.set_parallel(false)
	# Windup: cock back/up before hit frames
	var tw := _swing_tween.tween_property(_weapon_visual, "rotation_degrees", windup_rot, windup)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", windup_pos, windup)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Active: accelerate through the strike (synced with hitbox window)
	tw = _swing_tween.tween_property(_weapon_visual, "rotation_degrees", contact_rot, active * 0.55)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", contact_pos, active * 0.55)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw = _swing_tween.tween_property(_weapon_visual, "rotation_degrees", follow_rot, active * 0.45)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", follow_pos, active * 0.45)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Recovery: return to rest
	tw = _swing_tween.tween_property(_weapon_visual, "rotation_degrees", rest_rot, recovery)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", _weapon_rest_transform.origin, recovery)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _swing_poses(kind: StringName) -> Dictionary:
	## Degrees + local positions; heavy = bigger arc / higher cock than light.
	var rest_pos := _weapon_rest_transform.origin
	var heavy := kind == &"heavy"
	match current_weapon:
		Weapon.KNIFE:
			if heavy:
				return {
					"windup_rot": Vector3(-25.0, 35.0, 55.0),
					"contact_rot": Vector3(15.0, -50.0, -95.0),
					"follow_rot": Vector3(25.0, -70.0, -130.0),
					"windup_pos": rest_pos + Vector3(0.05, 0.12, 0.08),
					"contact_pos": rest_pos + Vector3(0.02, 0.02, -0.28),
					"follow_pos": rest_pos + Vector3(-0.08, -0.05, -0.18),
				}
			return {
				"windup_rot": Vector3(-10.0, 20.0, 35.0),
				"contact_rot": Vector3(8.0, -30.0, -70.0),
				"follow_rot": Vector3(12.0, -40.0, -95.0),
				"windup_pos": rest_pos + Vector3(0.03, 0.06, 0.04),
				"contact_pos": rest_pos + Vector3(0.0, 0.0, -0.18),
				"follow_pos": rest_pos + Vector3(-0.04, -0.02, -0.1),
			}
		Weapon.GOAD:
			if heavy:
				return {
					"windup_rot": Vector3(-55.0, 25.0, 40.0),
					"contact_rot": Vector3(35.0, -15.0, -55.0),
					"follow_rot": Vector3(50.0, -25.0, -75.0),
					"windup_pos": rest_pos + Vector3(0.08, 0.22, 0.12),
					"contact_pos": rest_pos + Vector3(0.05, 0.05, -0.45),
					"follow_pos": rest_pos + Vector3(-0.05, -0.08, -0.35),
				}
			return {
				"windup_rot": Vector3(-30.0, 10.0, 20.0),
				"contact_rot": Vector3(20.0, -5.0, -25.0),
				"follow_rot": Vector3(30.0, -10.0, -40.0),
				"windup_pos": rest_pos + Vector3(0.04, 0.1, 0.06),
				"contact_pos": rest_pos + Vector3(0.02, 0.02, -0.35),
				"follow_pos": rest_pos + Vector3(0.0, -0.04, -0.22),
			}
		_:
			# Hatchet diagonal chop; heavy is a larger overhead arc
			if heavy:
				return {
					"windup_rot": Vector3(-70.0, 45.0, 85.0),
					"contact_rot": Vector3(25.0, -35.0, -100.0),
					"follow_rot": Vector3(55.0, -55.0, -145.0),
					"windup_pos": rest_pos + Vector3(0.12, 0.28, 0.1),
					"contact_pos": rest_pos + Vector3(0.05, 0.05, -0.32),
					"follow_pos": rest_pos + Vector3(-0.12, -0.15, -0.22),
				}
			return {
				"windup_rot": Vector3(-35.0, 25.0, 50.0),
				"contact_rot": Vector3(15.0, -20.0, -75.0),
				"follow_rot": Vector3(30.0, -35.0, -105.0),
				"windup_pos": rest_pos + Vector3(0.06, 0.14, 0.06),
				"contact_pos": rest_pos + Vector3(0.02, 0.02, -0.22),
				"follow_pos": rest_pos + Vector3(-0.06, -0.08, -0.14),
			}


func reset_weapon_pose() -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	if _weapon_visual:
		_weapon_visual.transform = _weapon_rest_transform

func consume_knockback() -> Vector3:
	## Character controllers should add this to velocity each physics frame.
	var v := knockback_vel
	knockback_vel = Vector3.ZERO
	return v


func peek_knockback() -> Vector3:
	return knockback_vel


func _play_hurt_feedback(amount: float, from: Node) -> void:
	_flash_hurt_meshes()
	_apply_knockback_from(from, amount)
	if show_damage_numbers:
		_spawn_damage_number(amount)


func _play_hit_confirm(kind: StringName) -> void:
	# Brief hit-stop so contact reads; ignore_time_scale timer restores scale.
	if _hit_stop_running:
		return
	var dur := hit_stop_heavy if kind == &"heavy" else hit_stop_light
	if dur <= 0.0:
		return
	_hit_stop_running = true
	var prev := Engine.time_scale
	Engine.time_scale = 0.08 if kind == &"heavy" else 0.12
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = prev if prev > 0.01 else 1.0
	_hit_stop_running = false


func _flash_hurt_meshes() -> void:
	if _hurt_flash_tween and _hurt_flash_tween.is_valid():
		_hurt_flash_tween.kill()
	_clear_hurt_flash()
	var meshes := _collect_visual_meshes()
	if meshes.is_empty():
		return
	var flash := StandardMaterial3D.new()
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.albedo_color = Color(1.0, 0.45, 0.35, 0.85)
	flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mesh in meshes:
		mesh.material_overlay = flash
		_mesh_overlays.append(mesh)
	_hurt_flash_tween = create_tween()
	_hurt_flash_tween.tween_interval(hurt_flash_secs)
	_hurt_flash_tween.tween_callback(_clear_hurt_flash)


func _clear_hurt_flash() -> void:
	for mesh in _mesh_overlays:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	_mesh_overlays.clear()


func _collect_visual_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _owner_body == null:
		return out
	var visual := _owner_body.get_node_or_null("Visual")
	if visual == null:
		return out
	_gather_meshes(visual, out)
	return out


func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather_meshes(child, out)


func _apply_knockback_from(from: Node, amount: float) -> void:
	if _owner_body == null:
		return
	var origin := _owner_body.global_position
	var src_pos := origin + Vector3(0.0, 0.0, 1.0)
	if from is Node3D:
		src_pos = (from as Node3D).global_position
	var dir := origin - src_pos
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -_owner_body.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()
	var strength := knockback_light
	if amount >= 22.0:
		strength = knockback_heavy
	elif amount >= 16.0:
		strength = lerpf(knockback_light, knockback_heavy, 0.5)
	# Scale slightly by damage so lights nudge, heavies shove.
	strength *= clampf(amount / 14.0, 0.7, 1.35)
	knockback_vel += dir * strength + Vector3(0.0, 1.1, 0.0) * (0.35 if amount >= 22.0 else 0.15)


func _spawn_damage_number(amount: float) -> void:
	if _owner_body == null:
		return
	var label := Label3D.new()
	label.text = "%d" % int(round(amount))
	label.font_size = 48
	label.modulate = Color(1.0, 0.85, 0.35, 1.0)
	label.outline_modulate = Color(0.1, 0.05, 0.0, 1.0)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0045
	var parent_node: Node = _owner_body.get_parent()
	var anchor := _owner_body.global_position + Vector3(
		randf_range(-0.15, 0.15), 1.55, randf_range(-0.1, 0.1)
	)
	if parent_node:
		parent_node.add_child(label)
	else:
		_owner_body.add_child(label)
	label.global_position = anchor
	var tw := label.create_tween()
	var end_pos := label.global_position + Vector3(0.0, 0.85, 0.0)
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", end_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(label.queue_free)

