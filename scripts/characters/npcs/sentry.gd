extends CharacterBody3D
## Stationary watchman greybox: detection by default. Optional raid-combat chase/ATTACK
## when RaidHeatBridge crosses the hot-heat threshold (raid stays completable).

const MOVE_SPEED := 2.55
const ATTACK_RANGE := 1.95
const ATTACK_COOLDOWN := 1.75
const AGGRO_RANGE := 28.0

@onready var sensor: Node3D = $DetectionSensor
@onready var visual: Node3D = $Visual

var _player: Node3D
var _rest_yaw: float = 0.0
var _look_tween: Tween
var _raid_combat: bool = false
var _combat: Node = null
var _attack_cd: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _warn_label: Label3D


func _ready() -> void:
	_rest_yaw = rotation.y
	add_to_group("sentry")
	if sensor and sensor.has_signal("awareness_changed"):
		sensor.awareness_changed.connect(_on_awareness_changed)
	_player = get_tree().get_first_node_in_group("player") as Node3D


func enter_raid_combat() -> void:
	## Hot-heat / RAID ALARM: chase and ATTACK the player. Does not fail the raid.
	if _raid_combat:
		return
	_raid_combat = true
	_ensure_combat()
	_attack_cd = 0.35
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 2, 1.0)
	_on_awareness_changed(0, 2)
	_ensure_warn_label()
	if _warn_label:
		_warn_label.text = "ATTACK"
		_warn_label.visible = true
		_warn_label.modulate = Color(0.98, 0.3, 0.22)


func exit_raid_combat() -> void:
	_raid_combat = false
	velocity = Vector3.ZERO
	if _warn_label:
		_warn_label.visible = false


func is_raid_combat_active() -> bool:
	return _raid_combat


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if _raid_combat:
		_raid_combat_tick(delta)
		return

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


func _raid_combat_tick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _player == null or not is_instance_valid(_player):
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.05 else Vector3.FORWARD
	if dist > 0.05:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 7.0 * delta)

	var can_move := true
	if _combat and _combat.has_method("can_move"):
		can_move = bool(_combat.call("can_move"))

	if dist > ATTACK_RANGE * 0.9 and dist < AGGRO_RANGE and can_move:
		velocity.x = dir.x * MOVE_SPEED
		velocity.z = dir.z * MOVE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED * 6.0 * delta)

	if (
		dist <= ATTACK_RANGE
		and _attack_cd <= 0.0
		and _combat
		and _combat.has_method("try_attack")
	):
		if bool(_combat.call("try_attack", &"light")):
			_attack_cd = ATTACK_COOLDOWN
	elif dist <= ATTACK_RANGE and _attack_cd <= 0.0 and _combat == null:
		# Fallback poke if CombatSystem wiring failed.
		_poke_player(10.0)
		_attack_cd = ATTACK_COOLDOWN

	move_and_slide()


func _poke_player(amount: float) -> void:
	if _player == null:
		return
	var pc := _player.get_node_or_null("CombatSystem")
	if pc and pc.has_method("apply_damage"):
		pc.call("apply_damage", amount, self, true)


func _ensure_combat() -> void:
	_combat = get_node_or_null("CombatSystem")
	if _combat == null:
		var cs_script: Script = load("res://systems/combat/combat_system.gd") as Script
		if cs_script:
			_combat = cs_script.new()
			_combat.name = "CombatSystem"
			add_child(_combat)
	if _combat:
		if "team" in _combat:
			_combat.set("team", 1)
		if "starting_weapon" in _combat and _combat.get("Weapon"):
			pass
		if _combat.has_method("set_weapon") and _combat.get("Weapon") != null:
			# Weapon.SPEAR unavailable — use HATCHET (0) / KNIFE (1).
			_combat.call("set_weapon", 1)  # knife — lighter greybox poke
		elif "starting_weapon" in _combat:
			_combat.set("starting_weapon", 1)
	_ensure_hit_hurt_boxes()


func _ensure_hit_hurt_boxes() -> void:
	if get_node_or_null("Hitbox") == null:
		var hit := Area3D.new()
		hit.name = "Hitbox"
		hit.collision_layer = 8
		hit.collision_mask = 2
		hit.monitoring = false
		hit.monitorable = false
		var hit_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.5, 0.65, 1.1)
		hit_shape.shape = box
		hit.add_child(hit_shape)
		add_child(hit)
	if get_node_or_null("Hurtbox") == null:
		var hurt := Area3D.new()
		hurt.name = "Hurtbox"
		hurt.collision_layer = 4
		hurt.collision_mask = 0
		hurt.monitoring = false
		hurt.monitorable = true
		var hurt_shape := CollisionShape3D.new()
		hurt_shape.position = Vector3(0, 0.85, 0)
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.7
		hurt_shape.shape = cap
		hurt.add_child(hurt_shape)
		add_child(hurt)


func _ensure_warn_label() -> void:
	if _warn_label and is_instance_valid(_warn_label):
		return
	_warn_label = get_node_or_null("AttackWarn") as Label3D
	if _warn_label:
		return
	_warn_label = Label3D.new()
	_warn_label.name = "AttackWarn"
	_warn_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warn_label.font_size = 28
	_warn_label.position = Vector3(0, 2.35, 0)
	_warn_label.visible = false
	add_child(_warn_label)


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
	if _raid_combat:
		sm.albedo_color = Color(0.85, 0.12, 0.1)
		return
	match next:
		1:
			sm.albedo_color = Color(0.65, 0.5, 0.2)
		2:
			sm.albedo_color = Color(0.7, 0.18, 0.15)
		_:
			sm.albedo_color = Color(0.25, 0.32, 0.45)
