extends CharacterBody3D
## Stationary watchman greybox: detection by default. Walks to bodies during
## investigation polish. Optional raid-combat chase/ATTACK when RaidHeatBridge
## crosses the hot-heat threshold (raid stays completable).
## Optional patrol: give patrol_points (world XZ) and he walks them while
## UNAWARE, pausing at each. Suspicion stops him and turns him to look.

const MOVE_SPEED := 2.55
const INVESTIGATE_SPEED := 2.05
const INVESTIGATE_STOP_DIST := 2.2
const RETURN_SPEED := 1.85
const ATTACK_RANGE := 1.95
const ATTACK_COOLDOWN := 1.75
const AGGRO_RANGE := 28.0

## World-space waypoints walked in a loop while unaware. Empty = stationary post.
@export var patrol_points: PackedVector3Array = PackedVector3Array()
@export var patrol_speed: float = 1.35
@export var patrol_pause: float = 1.2
## Give him a CombatSystem + hit/hurt boxes at spawn (not raid mode), so player
## strikes land on him. Off by default: stealth-lane sentries stay as they were.
@export var combat_ready: bool = false

@onready var sensor: Node3D = $DetectionSensor
@onready var visual: Node3D = $Visual

var _player: Node3D
var _rest_yaw: float = 0.0
var _rest_position: Vector3 = Vector3.ZERO
var _look_tween: Tween
var _raid_combat: bool = false
var _combat: Node = null
var _attack_cd: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _warn_label: Label3D

## Body investigation (stealth polish)
var _investigate_target: Node3D = null
var _investigate_remaining: float = 0.0
var _returning_to_post: bool = false
var _investigate_label: Label3D
var _telegraph_pulse: float = 0.0

## Patrol
var _patrol_index: int = 0
var _patrol_wait: float = 0.0


func _ready() -> void:
	_rest_yaw = rotation.y
	_rest_position = global_position
	add_to_group("sentry")
	if sensor and sensor.has_signal("awareness_changed"):
		sensor.awareness_changed.connect(_on_awareness_changed)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_ensure_investigate_label()
	if combat_ready:
		ensure_hittable()


## Hit/hurt boxes + a CombatSystem (team 1) without entering raid combat, so a
## player strike can land and stagger. Boxes first, so CombatSystem._ready binds them.
func ensure_hittable() -> Node:
	_ensure_hit_hurt_boxes()
	if _combat == null:
		_combat = get_node_or_null("CombatSystem")
	if _combat == null:
		var cs_script: Script = load("res://systems/combat/combat_system.gd") as Script
		if cs_script:
			_combat = cs_script.new()
			_combat.name = "CombatSystem"
			_combat.set("team", 1)
			_combat.set("starting_weapon", 1)
			_combat.set("show_damage_numbers", true)
			add_child(_combat)
	return _combat


func is_patrolling() -> bool:
	return not patrol_points.is_empty()


func begin_body_investigate(corpse: Node3D, remaining: float = -1.0) -> void:
	## HeatTracker: start walk-to-body + telegraph while the delay ticks.
	if _raid_combat or corpse == null or not is_instance_valid(corpse):
		return
	_investigate_target = corpse
	_returning_to_post = false
	if remaining >= 0.0:
		_investigate_remaining = remaining
	_telegraph_pulse = 0.0
	_ensure_investigate_label()
	_refresh_investigate_label()


func update_body_investigate(remaining: float) -> void:
	if _investigate_target == null:
		return
	_investigate_remaining = remaining
	_refresh_investigate_label()


func cancel_body_investigate() -> void:
	## Lost LOS mid-investigate — abort and amble back toward post.
	_investigate_target = null
	_investigate_remaining = 0.0
	_returning_to_post = true
	if _investigate_label:
		_investigate_label.visible = false


func confirm_body_discovered() -> void:
	## Investigation timer elapsed → ALERT stay near body briefly, then idle alert.
	_investigate_target = null
	_investigate_remaining = 0.0
	_returning_to_post = false
	if _investigate_label:
		_investigate_label.text = "[!] BODY FOUND"
		_investigate_label.modulate = Color(0.98, 0.28, 0.18)
		_investigate_label.visible = true
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_callback(func():
			if _investigate_label and _investigate_target == null and not _raid_combat:
				_investigate_label.visible = false
		)


func is_investigating_body() -> bool:
	return _investigate_target != null and is_instance_valid(_investigate_target)


func enter_raid_combat() -> void:
	## Hot-heat / RAID ALARM: chase and ATTACK the player. Does not fail the raid.
	if _raid_combat:
		return
	_raid_combat = true
	_investigate_target = null
	_returning_to_post = false
	if _investigate_label:
		_investigate_label.visible = false
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

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if _investigate_target != null and is_instance_valid(_investigate_target):
		_investigate_tick(delta)
		move_and_slide()
		return

	if _returning_to_post:
		_return_to_post_tick(delta)
		move_and_slide()
		return

	var aw = sensor.get("awareness") if sensor else null
	var staggered := _combat != null and _combat.has_method("is_staggered") and bool(_combat.call("is_staggered"))
	if is_patrolling() and aw != null and int(aw) == 0 and not staggered:
		_patrol_tick(delta)
		move_and_slide()
		return

	velocity.x = move_toward(velocity.x, 0.0, INVESTIGATE_SPEED * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, INVESTIGATE_SPEED * 6.0 * delta)
	move_and_slide()

	if aw == null:
		return
	# Soft face last-known / player when suspicious or alert.
	if int(aw) >= 1 and _player:
		var to_p := _player.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.01:
			var target_yaw := atan2(-to_p.x, -to_p.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 2.2 * delta)
	elif int(aw) == 0 and not is_patrolling():
		rotation.y = lerp_angle(rotation.y, _rest_yaw, 1.2 * delta)


func _patrol_tick(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait = maxf(0.0, _patrol_wait - delta)
		velocity.x = move_toward(velocity.x, 0.0, patrol_speed * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, patrol_speed * 6.0 * delta)
		# Look along the next leg while paused.
		var nxt := patrol_points[_patrol_index] - global_position
		nxt.y = 0.0
		if nxt.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-nxt.x, -nxt.z), 2.0 * delta)
		return
	_patrol_index = clampi(_patrol_index, 0, patrol_points.size() - 1)
	var to_pt := patrol_points[_patrol_index] - global_position
	to_pt.y = 0.0
	var dist := to_pt.length()
	if dist < 0.3:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_patrol_wait = patrol_pause
		return
	var dir := to_pt / dist
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 5.0 * delta)
	velocity.x = dir.x * patrol_speed
	velocity.z = dir.z * patrol_speed


func _investigate_tick(delta: float) -> void:
	_telegraph_pulse += delta
	var to_body := _investigate_target.global_position - global_position
	to_body.y = 0.0
	var dist := to_body.length()
	var dir := to_body.normalized() if dist > 0.05 else Vector3.FORWARD
	if dist > 0.05:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 5.5 * delta)

	if dist > INVESTIGATE_STOP_DIST:
		velocity.x = dir.x * INVESTIGATE_SPEED
		velocity.z = dir.z * INVESTIGATE_SPEED
	else:
		# Hold stand-off: look / lean in place (telegraph readable).
		velocity.x = move_toward(velocity.x, 0.0, INVESTIGATE_SPEED * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, INVESTIGATE_SPEED * 8.0 * delta)
		# Subtle head bob via visual pitch-ish scale pulse (greybox read).
		if visual:
			var bob := 1.0 + sin(_telegraph_pulse * 6.0) * 0.015
			visual.scale = Vector3(bob, 1.0, bob)

	_refresh_investigate_label()


func _return_to_post_tick(delta: float) -> void:
	var to_rest := _rest_position - global_position
	to_rest.y = 0.0
	var dist := to_rest.length()
	if dist < 0.35:
		_returning_to_post = false
		velocity.x = 0.0
		velocity.z = 0.0
		rotation.y = lerp_angle(rotation.y, _rest_yaw, 3.0 * delta)
		if visual:
			visual.scale = Vector3.ONE
		return
	var dir := to_rest.normalized()
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 4.0 * delta)
	velocity.x = dir.x * RETURN_SPEED
	velocity.z = dir.z * RETURN_SPEED


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


func _ensure_investigate_label() -> void:
	if _investigate_label and is_instance_valid(_investigate_label):
		return
	_investigate_label = get_node_or_null("InvestigateTelegraph") as Label3D
	if _investigate_label:
		return
	_investigate_label = Label3D.new()
	_investigate_label.name = "InvestigateTelegraph"
	_investigate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_investigate_label.font_size = 36
	_investigate_label.outline_size = 8
	_investigate_label.outline_modulate = Color(0.08, 0.06, 0.02, 0.9)
	_investigate_label.position = Vector3(0.0, 2.75, 0.0)
	_investigate_label.visible = false
	add_child(_investigate_label)


func _refresh_investigate_label() -> void:
	if _investigate_label == null:
		return
	if _investigate_target == null or not is_instance_valid(_investigate_target):
		if not _raid_combat:
			# Keep BODY FOUND flash handled elsewhere; hide idle.
			pass
		return
	var secs := maxf(0.0, _investigate_remaining)
	var pulse := 0.72 + 0.28 * (0.5 + 0.5 * sin(_telegraph_pulse * 7.5))
	_investigate_label.visible = true
	_investigate_label.text = "[?] INVESTIGATING\n%.1fs" % secs
	_investigate_label.modulate = Color(0.98, 0.86, 0.28, pulse)


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
	if _investigate_target != null:
		sm.albedo_color = Color(0.72, 0.58, 0.18)
		return
	match next:
		1:
			sm.albedo_color = Color(0.65, 0.5, 0.2)
		2:
			sm.albedo_color = Color(0.7, 0.18, 0.15)
		_:
			sm.albedo_color = Color(0.25, 0.32, 0.45)
