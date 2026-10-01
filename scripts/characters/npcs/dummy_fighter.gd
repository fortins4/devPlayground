extends CharacterBody3D
## Greybox dummy: faces the player, takes hits, weakly counters when close.

const MOVE_SPEED := 1.6
const AGGRO_RANGE := 12.0
const ATTACK_RANGE := 1.8
const ATTACK_COOLDOWN := 1.6

@onready var combat: CombatSystem = $CombatSystem
@onready var visual: Node3D = $Visual

var _player: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _attack_cd: float = 1.0
var _death_timer: float = -1.0


func _ready() -> void:
	if combat:
		combat.team = 1
		combat.starting_weapon = CombatSystem.Weapon.HATCHET
		combat.set_weapon(CombatSystem.Weapon.HATCHET)
		combat.died.connect(_on_died)
	_find_player()


func _physics_process(delta: float) -> void:
	if _death_timer >= 0.0:
		_death_timer -= delta
		rotation.z = move_toward(rotation.z, deg_to_rad(85.0), 2.5 * delta)
		if _death_timer <= 0.0:
			queue_free()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _player == null or not is_instance_valid(_player):
		_find_player()
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist < AGGRO_RANGE and dist > 0.05:
		var dir := to_player.normalized()
		# Face player
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)

		if combat and combat.can_move() and dist > ATTACK_RANGE * 0.85:
			velocity.x = dir.x * MOVE_SPEED
			velocity.z = dir.z * MOVE_SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED * 4.0 * delta)

		_attack_cd = maxf(0.0, _attack_cd - delta)
		if combat and dist <= ATTACK_RANGE and _attack_cd <= 0.0 and combat.can_move():
			if combat.try_attack(&"light"):
				_attack_cd = ATTACK_COOLDOWN
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)

	move_and_slide()


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _on_died(_victim: Node) -> void:
	_death_timer = 2.2
	collision_layer = 0
	collision_mask = 0
