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
	var hp0 := def.health
	var frontal := def.apply_damage(20.0, attacker_body, true)
	if frontal >= 19.0:
		push_error("SMOKE_FAIL frontal block did not mitigate (dealt %.1f)" % frontal)
		quit(1)
		return
	print("SMOKE frontal_blocked dealt=", frontal, " hp=", def.health)

	def.health = hp0
	def.set_blocking(true)
	var flank := def.apply_damage(20.0, attacker_body, false)
	if flank < 19.0:
		push_error("SMOKE_FAIL flank should be full damage (dealt %.1f)" % flank)
		quit(1)
		return
	print("SMOKE flank_open dealt=", flank)

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

	print("SPARRING_FOE_SMOKE_OK")
	quit(0)
