extends CharacterBody3D
## Sparring foe: faces player, BLOCKS frontal hits, open to flanks; telegraphs + weak counters.

const CorpseSpawnerScript := preload("res://systems/stealth/corpse_spawner.gd")

const MOVE_SPEED := 1.55
const AGGRO_RANGE := 12.0
const ATTACK_RANGE := 1.85
const ATTACK_COOLDOWN := 2.05
const COUNTER_COOLDOWN := 2.35
const TELEGRAPH_TIME := 0.48
const COUNTER_TELEGRAPH_TIME := 0.38
const STAGGER_TIME := 0.35

enum State { IDLE, CHASE, TELEGRAPH, RECOVER, STAGGER }

@onready var combat: CombatSystem = $CombatSystem
@onready var visual: Node3D = $Visual
@onready var weapon_visual: Node3D = $WeaponVisual
@onready var locomotion: KerneLocomotion = $KerneLocomotion

var _player: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _attack_cd: float = 1.2
var _counter_cd: float = 0.0
var _death_timer: float = -1.0
var _state: State = State.IDLE
var _state_time: float = 0.0
var _pending_attack_kind: StringName = &"light"
var _is_counter: bool = false
var _weapon_rest: Transform3D
var _telegraph_meshes: Array[MeshInstance3D] = []
var _warn_label: Label3D


func _ready() -> void:
	if weapon_visual:
		_weapon_rest = weapon_visual.transform
	if combat:
		combat.team = 1
		combat.starting_weapon = CombatSystem.Weapon.HATCHET
		combat.set_weapon(CombatSystem.Weapon.HATCHET)
		combat.enable_block = true  # Face-block sparring (flanks still hurt)
		combat.died.connect(_on_died)
		combat.damage_taken.connect(_on_damage_taken)
		combat.attack_performed.connect(_on_attack_performed)
	_ensure_warn_label()
	_find_player()


func _physics_process(delta: float) -> void:
	if _death_timer >= 0.0:
		_death_timer -= delta
		rotation.z = move_toward(rotation.z, deg_to_rad(85.0), 2.5 * delta)
		if _death_timer <= 0.0:
			_death_timer = -1.0
			_spawn_corpse_on_death()
			queue_free()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if combat:
		var kb: Vector3 = combat.consume_knockback()
		velocity.x += kb.x
		velocity.z += kb.z
		velocity.y += kb.y

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_counter_cd = maxf(0.0, _counter_cd - delta)

	if _player == null or not is_instance_valid(_player):
		_find_player()
		_set_state(State.IDLE)
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.05 else Vector3.FORWARD

	if dist < AGGRO_RANGE and dist > 0.05:
		var target_yaw := atan2(-dir.x, -dir.z)
		var turn_rate := 8.0 if _state == State.TELEGRAPH else 6.0
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_rate * delta)

	# Hold block while facing the player and not mid-swing — flanks still connect.
	if combat and not combat.is_dead:
		var can_block := (
			_state != State.TELEGRAPH
			and _state != State.RECOVER
			and _state != State.STAGGER
			and not combat.is_attacking
			and dist < AGGRO_RANGE
		)
		combat.set_blocking(can_block)

	_state_time += delta
	match _state:
		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 6.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED * 6.0 * delta)
			if _state_time >= STAGGER_TIME:
				_set_state(State.CHASE)
		State.TELEGRAPH:
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED * 8.0 * delta)
			var need := COUNTER_TELEGRAPH_TIME if _is_counter else TELEGRAPH_TIME
			if _state_time >= need:
				_release_attack()
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED * 4.0 * delta)
			if combat == null or combat.can_move():
				_set_state(State.CHASE)
		State.CHASE, State.IDLE:
			if dist >= AGGRO_RANGE:
				_set_state(State.IDLE)
				velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
				velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)
			else:
				_set_state(State.CHASE)
				if combat and combat.can_move() and dist > ATTACK_RANGE * 0.85:
					velocity.x = dir.x * MOVE_SPEED
					velocity.z = dir.z * MOVE_SPEED
				else:
					velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED * 4.0 * delta)
					velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED * 4.0 * delta)
				# Opportunistic (non-counter) swing — readable telegraph first.
				if (
					combat
					and dist <= ATTACK_RANGE
					and _attack_cd <= 0.0
					and combat.can_move()
					and _state != State.TELEGRAPH
				):
					_begin_telegraph(&"light", false)

	move_and_slide()
	_tick_locomotion(delta)


func _tick_locomotion(delta: float) -> void:
	if locomotion == null:
		return
	var hs := Vector3(velocity.x, 0.0, velocity.z).length()
	var attacking := combat != null and combat.is_attacking
	locomotion.tick(delta, hs, false, false, attacking, Vector3.ZERO)


func _begin_telegraph(kind: StringName, is_counter: bool) -> void:
	if combat == null or combat.is_dead or combat.is_attacking:
		return
	if _state == State.TELEGRAPH or _state == State.STAGGER:
		return
	_pending_attack_kind = kind
	_is_counter = is_counter
	_set_state(State.TELEGRAPH)
	_show_telegraph_visual(true, is_counter)
	# Cock weapon into windup pose so the swing is readable in greybox.
	if weapon_visual and combat:
		var poses: Dictionary = combat.call("_swing_poses", kind)
		weapon_visual.rotation_degrees = poses["windup_rot"]
		weapon_visual.position = poses["windup_pos"]


func _release_attack() -> void:
	_show_telegraph_visual(false, false)
	if combat == null or combat.is_dead:
		_set_state(State.CHASE)
		return
	# Let CombatSystem drive the actual Tween swing + hitbox.
	if weapon_visual:
		weapon_visual.transform = _weapon_rest
	var ok: bool = combat.try_attack(_pending_attack_kind)
	if ok:
		_attack_cd = ATTACK_COOLDOWN
		if _is_counter:
			_counter_cd = COUNTER_COOLDOWN
		_set_state(State.RECOVER)
	else:
		_set_state(State.CHASE)
	_is_counter = false


func _on_damage_taken(_amount: float, from: Node) -> void:
	# Hit during telegraph cancels the swing — player can interrupt by pressing.
	if _state == State.TELEGRAPH:
		_cancel_telegraph_stagger()
		return
	# Reactive weak counter if close enough and off cooldown.
	if _counter_cd > 0.0 or combat == null or combat.is_dead:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if from != null and from != _player:
		# Only counter the player for this greybox slice.
		pass
	var dist := global_position.distance_to(_player.global_position)
	if dist <= ATTACK_RANGE * 1.15 and combat.can_move() and _state != State.RECOVER:
		# Slight delay so the hurt flash reads before the counter telegraph.
		_counter_cd = COUNTER_COOLDOWN
		await get_tree().create_timer(0.12).timeout
		if not is_instance_valid(self) or combat == null or combat.is_dead:
			return
		if _state == State.STAGGER:
			return
		var still_close := global_position.distance_to(_player.global_position) <= ATTACK_RANGE * 1.25
		if still_close and combat.can_move():
			_begin_telegraph(&"light", true)


func _cancel_telegraph_stagger() -> void:
	_show_telegraph_visual(false, false)
	if weapon_visual:
		weapon_visual.transform = _weapon_rest
	_is_counter = false
	_set_state(State.STAGGER)
	_attack_cd = maxf(_attack_cd, 0.55)


func _on_attack_performed(_attacker: Node, _kind: StringName, _weapon: StringName) -> void:
	# After CombatSystem starts its swing tween, stay in recover until can_move.
	if _state != State.RECOVER:
		_set_state(State.RECOVER)


func _set_state(next: State) -> void:
	if _state == next:
		if next != State.TELEGRAPH:
			return
	_state = next
	_state_time = 0.0


func _show_telegraph_visual(on: bool, is_counter: bool) -> void:
	if _warn_label:
		_warn_label.visible = on
		if on:
			_warn_label.text = "!" if is_counter else "..."
			_warn_label.modulate = Color(1.0, 0.55, 0.15, 1.0) if is_counter else Color(1.0, 0.9, 0.35, 1.0)
	# Warm tint on body during telegraph so intent reads without animations.
	if not on:
		for mesh in _telegraph_meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = null
		_telegraph_meshes.clear()
		return
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.albedo_color = Color(1.0, 0.55, 0.2, 0.55) if is_counter else Color(1.0, 0.85, 0.25, 0.4)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_meshes.clear()
	if visual:
		_gather_meshes(visual, _telegraph_meshes)
	for mesh in _telegraph_meshes:
		mesh.material_overlay = tint


func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather_meshes(child, out)


func _ensure_warn_label() -> void:
	_warn_label = Label3D.new()
	_warn_label.name = "TelegraphWarn"
	_warn_label.text = "!"
	_warn_label.font_size = 64
	_warn_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warn_label.no_depth_test = true
	_warn_label.pixel_size = 0.005
	_warn_label.position = Vector3(0.0, 2.15, 0.0)
	_warn_label.visible = false
	add_child(_warn_label)
	var hint := Label3D.new()
	hint.name = "SparringHint"
	hint.text = "BLOCKS FACE — flank me"
	hint.font_size = 28
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.no_depth_test = true
	hint.pixel_size = 0.004
	hint.position = Vector3(0.0, 2.45, 0.0)
	hint.modulate = Color(0.75, 0.9, 1.0, 1.0)
	add_child(hint)


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _on_died(_victim: Node) -> void:
	_show_telegraph_visual(false, false)
	# Tip over briefly, then leave a draggable corpse (FULL bog-drag combat hook).
	_death_timer = 0.95
	collision_layer = 0
	collision_mask = 0


func _spawn_corpse_on_death() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var corpse: Node3D = CorpseSpawnerScript.spawn_from_combatant(self) as Node3D
	if corpse == null:
		return
	# Slightly offset so it reads as fallen beside the dummy tip-over.
	corpse.global_position = global_position + Vector3(0.15, 0.05, 0.1)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
