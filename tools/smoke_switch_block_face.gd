extends SceneTree
## Smoke: guard face blocks matching strike only; other faces open.


func _initialize() -> void:
	_run()


func _run() -> void:
	var combat_script := load("res://systems/combat/combat_system.gd") as Script
	var body := CharacterBody3D.new()
	root.add_child(body)
	var def: CombatSystem = combat_script.new()
	def.enable_block = true
	def.enable_hit_feedback = false
	body.add_child(def)
	await process_frame

	def.set_blocking(true)
	def.set_guard_direction(CombatSystem.StrikeDirection.TOP)
	var top_block := def.apply_damage(20.0, null, true, CombatSystem.StrikeDirection.TOP)
	if top_block >= 10.0:
		push_error("SMOKE_FAIL TOP guard should block TOP strike (dealt %.1f)" % top_block)
		quit(1)
		return
	print("SMOKE top_guard_blocks_top dealt=", top_block)

	def.health = def.max_health
	def.set_blocking(true)
	def.set_guard_direction(CombatSystem.StrikeDirection.TOP)
	var left_open := def.apply_damage(20.0, null, true, CombatSystem.StrikeDirection.LEFT)
	if left_open < 19.0:
		push_error("SMOKE_FAIL TOP guard should NOT block LEFT (dealt %.1f)" % left_open)
		quit(1)
		return
	print("SMOKE top_guard_open_left dealt=", left_open)

	def.health = def.max_health
	def.set_guard_direction(CombatSystem.StrikeDirection.LEFT)
	def.set_blocking(true)
	var left_block := def.apply_damage(20.0, null, true, CombatSystem.StrikeDirection.LEFT)
	if left_block >= 10.0:
		push_error("SMOKE_FAIL LEFT guard should block LEFT (dealt %.1f)" % left_block)
		quit(1)
		return
	var right_open := def.apply_damage(20.0, null, true, CombatSystem.StrikeDirection.RIGHT)
	if right_open < 19.0:
		push_error("SMOKE_FAIL LEFT guard open to RIGHT (dealt %.1f)" % right_open)
		quit(1)
		return
	print("SMOKE left_guard ok block=", left_block, " right_open=", right_open)

	def.set_guard_direction(CombatSystem.StrikeDirection.RIGHT)
	if def.guard_direction_name() != &"right":
		push_error("SMOKE_FAIL guard name")
		quit(1)
		return

	print("SWITCH_BLOCK_FACE_SMOKE_OK")
	quit(0)
