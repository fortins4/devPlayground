class_name CombatSystem
extends Node
## Reusable greybox combat component (hatchet-first cattle-farm kit).
## Attach as child of a CharacterBody3D (player or NPC). Expects optional siblings:
## Hitbox (Area3D), Hurtbox (Area3D), WeaponVisual (Node3D with mesh children).

signal attack_performed(attacker: Node, kind: StringName, weapon: StringName)
signal hit_landed(attacker: Node, target: Node, damage: float, kind: StringName)
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
var _swing_flash_left: float = 0.0

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
	_apply_weapon_visual()
	stamina_changed.emit(stamina, max_stamina)
	health_changed.emit(health, max_health)
	weapon_changed.emit(WEAPON_NAMES[current_weapon])


func _physics_process(delta: float) -> void:
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

	if _swing_flash_left > 0.0:
		_swing_flash_left = maxf(0.0, _swing_flash_left - delta)
		_update_swing_visual()

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
	_swing_flash_left = windup + active + 0.05
	_update_swing_visual()
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


func _update_swing_visual() -> void:
	if _weapon_visual == null:
		return
	var t := 0.0
	if _swing_flash_left > 0.0:
		t = sin((1.0 - clampf(_swing_flash_left / 0.4, 0.0, 1.0)) * PI)
	# Arc swing: rotate weapon visual around local Y/Z for greybox readability
	var angle := deg_to_rad(-70.0 * t) if current_weapon != Weapon.GOAD else deg_to_rad(-40.0 * t)
	_weapon_visual.rotation_degrees = Vector3(angle * 0.3, 0.0, angle)
