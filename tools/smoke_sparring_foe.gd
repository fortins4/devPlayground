extends SceneTree
## Smoke: sparring foe face-block vs flank damage.


func _initialize() -> void:
	_run()


func _run() -> void:
	var combat_script := load("res://systems/combat/combat_system.gd") as Script
	if combat_script == null:
		push_error("SMOKE_FAIL missing combat_system")
		quit(1)
		return

	var attacker_body := CharacterBody3D.new()
	attacker_body.name = "Attacker"
	attacker_body.position = Vector3(0, 0, 2)
	root.add_child(attacker_body)
	var atk: CombatSystem = combat_script.new()
	atk.name = "CombatSystem"
	atk.team = 0
	atk.enable_hit_feedback = false
	attacker_body.add_child(atk)

	var defender_body := CharacterBody3D.new()
	defender_body.name = "Defender"
	defender_body.position = Vector3(0, 0, 0)
	defender_body.rotation.y = 0.0  # faces -Z toward attacker at z=2? 
	# Character -Z forward: rotation 0 faces -Z, so attacker at +Z is BEHIND.
	# Put attacker in front: negative Z.
	attacker_body.position = Vector3(0, 0, -2)
	root.add_child(defender_body)
	var def: CombatSystem = combat_script.new()
	def.name = "CombatSystem"
	def.team = 1
	def.enable_block = true
	def.enable_hit_feedback = false
	defender_body.add_child(def)

	await process_frame
	await process_frame

	def.set_blocking(true)
	def.set_guard_direction(CombatSystem.StrikeDirection.TOP)
	var hp0 := def.health
	var blocked := def.apply_damage(20.0, attacker_body, true, CombatSystem.StrikeDirection.TOP)
	if blocked >= 10.0:
		push_error("SMOKE_FAIL matching face block did not mitigate (dealt %.1f)" % blocked)
		quit(1)
		return
	print("SMOKE face_blocked dealt=", blocked, " hp=", def.health)

	def.health = hp0
	def.set_blocking(true)
	def.set_guard_direction(CombatSystem.StrikeDirection.TOP)
	var open_face := def.apply_damage(20.0, attacker_body, true, CombatSystem.StrikeDirection.LEFT)
	if open_face < 19.0:
		push_error("SMOKE_FAIL wrong face should be full damage (dealt %.1f)" % open_face)
		quit(1)
		return
	print("SMOKE wrong_face_open dealt=", open_face)

	# Wider side hitbox sizing
	atk.current_weapon = CombatSystem.Weapon.HATCHET
	var box_host := Area3D.new()
	box_host.name = "Hitbox"
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	box_host.add_child(cs)
	attacker_body.add_child(box_host)
	atk.set("_hitbox", box_host)
	atk.set("_owner_body", attacker_body)
	atk.call("_position_hitbox", 1.5, CombatSystem.StrikeDirection.LEFT)
	var shaped := cs.shape as BoxShape3D
	if shaped.size.x < 1.0:
		push_error("SMOKE_FAIL side hitbox not wide enough (%.2f)" % shaped.size.x)
		quit(1)
		return
	print("SMOKE side_hitbox_width=", shaped.size.x)

	if not await _check_goad_jab():
		quit(1)
		return
	print("SPARRING_FOE_SMOKE_OK")
	quit(0)


func _check_goad_jab() -> bool:
	## Foe attack is the uncharged goad point. Low guard stops it. High does not.
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var foe := (load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene).instantiate()
	root.add_child(foe)
	foe.set_physics_process(false)
	foe.set_process(false)
	await process_frame
	await process_frame
	var pc := player.get_node("CombatSystem") as CombatSystem
	var fc := foe.get_node("CombatSystem") as CombatSystem
	pc.enable_hit_feedback = false
	fc.enable_hit_feedback = false
	fc.hit_stop_light = 0.0
	fc.hit_stop_heavy = 0.0
	if fc.current_weapon != CombatSystem.Weapon.GOAD:
		push_error("SMOKE_FAIL sparring foe is not holding the goad")
		return false
	if not fc.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM):
		push_error("SMOKE_FAIL foe jab did not start")
		return false
	if fc.last_strike_direction() != CombatSystem.StrikeDirection.BOTTOM:
		push_error("SMOKE_FAIL foe jab was not the point")
		return false
	if fc.last_attack_power >= 0.0 or fc.last_attack_timings()["kind"] != &"light":
		push_error("SMOKE_FAIL foe jab was charged or heavy")
		return false
	fc.is_attacking = false
	fc.attack_recovery_left = 0.0
	player._sprinting = false
	player.pivot.rotation.x = 0.0
	player._tool_aim_delta = Vector2(0.0, 40.0)
	player._tick_shaft_block()
	if pc.shaft_guard_face != &"low" or not pc.is_shaft_blocking or pc.is_attacking:
		push_error("SMOKE_FAIL look-down did not hold the low guard")
		return false
	pc.health = pc.max_health
	var stopped := pc.apply_damage(18.0, foe, true, CombatSystem.StrikeDirection.BOTTOM)
	if stopped > 0.01 or pc.health < pc.max_health - 0.01:
		push_error("SMOKE_FAIL low guard did not stop the foe jab")
		return false
	pc.health = pc.max_health
	pc.stamina = pc.max_stamina
	if not pc.set_shaft_block(true):
		push_error("SMOKE_FAIL could not raise guard for a high face")
		return false
	pc.set_shaft_guard_face(&"high")
	var leaked := pc.apply_damage(18.0, foe, true, CombatSystem.StrikeDirection.BOTTOM)
	if leaked < 14.0:
		push_error("SMOKE_FAIL high guard stopped the jab")
		return false
	print("SMOKE goad_jab uncharged low-stops high-open")
	return true
