extends SceneTree
## Smoke: hatchet hold-to-charge + top/left/right strike directions + power scaling.


func _initialize() -> void:
	_run()


func _run() -> void:
	var combat_script := load("res://systems/combat/combat_system.gd") as Script
	if combat_script == null:
		push_error("SMOKE_FAIL missing combat_system.gd")
		quit(1)
		return

	var host := CharacterBody3D.new()
	host.name = "SmokeHost"
	root.add_child(host)

	var combat: CombatSystem = combat_script.new()
	combat.name = "CombatSystem"
	combat.starting_weapon = CombatSystem.Weapon.HATCHET
	combat.enable_hit_feedback = false
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	host.add_child(combat)

	var weapon_visual := Node3D.new()
	weapon_visual.name = "WeaponVisual"
	host.add_child(weapon_visual)
	var hatchet := MeshInstance3D.new()
	hatchet.name = "Hatchet"
	weapon_visual.add_child(hatchet)

	await process_frame
	await process_frame

	if combat.current_weapon != CombatSystem.Weapon.HATCHET:
		push_error("SMOKE_FAIL expected hatchet")
		quit(1)
		return

	# --- Charge begins ---
	if not combat.begin_charge():
		push_error("SMOKE_FAIL begin_charge failed")
		quit(1)
		return
	if not combat.is_charging:
		push_error("SMOKE_FAIL not charging after begin")
		quit(1)
		return
	print("SMOKE charge_started ok")

	# Simulate hold to mid charge
	for _i in 20:
		await physics_frame
	var mid_ratio := combat.get_charge_ratio()
	print("SMOKE mid_charge_ratio=", mid_ratio)
	if mid_ratio < 0.2:
		push_error("SMOKE_FAIL charge did not build (ratio=%.3f)" % mid_ratio)
		quit(1)
		return

	# Direction switching while charging
	combat.set_charge_direction(CombatSystem.StrikeDirection.LEFT)
	if combat.charge_direction != CombatSystem.StrikeDirection.LEFT:
		push_error("SMOKE_FAIL set LEFT failed")
		quit(1)
		return
	combat.set_charge_direction(CombatSystem.StrikeDirection.RIGHT)
	if combat.direction_name() != &"right":
		push_error("SMOKE_FAIL expected right dir name")
		quit(1)
		return
	combat.set_charge_direction(CombatSystem.StrikeDirection.TOP)
	print("SMOKE directions ok top/left/right")

	# Hold to near-full then release
	for _i in 40:
		await physics_frame
	var full_ratio := combat.get_charge_ratio()
	print("SMOKE full_charge_ratio=", full_ratio)
	if full_ratio < 0.85:
		push_error("SMOKE_FAIL expected near-full charge, got %.3f" % full_ratio)
		quit(1)
		return

	var sta_before := combat.stamina
	if not combat.release_charged_attack():
		push_error("SMOKE_FAIL release_charged_attack failed")
		quit(1)
		return
	if combat.is_charging:
		push_error("SMOKE_FAIL still charging after release")
		quit(1)
		return
	if not combat.is_attacking:
		push_error("SMOKE_FAIL expected is_attacking after release")
		quit(1)
		return
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL last direction not TOP")
		quit(1)
		return
	if combat.stamina >= sta_before:
		push_error("SMOKE_FAIL stamina not spent on charged strike")
		quit(1)
		return
	print("SMOKE charged_top_release ok sta=", combat.stamina)

	# Wait out recovery
	for _i in 90:
		await physics_frame
	if combat.is_attacking:
		# allow a little more
		for _j in 60:
			await physics_frame

	# Left light via try_attack
	if not combat.try_attack(&"light", CombatSystem.StrikeDirection.LEFT, 0.0):
		push_error("SMOKE_FAIL left light failed")
		quit(1)
		return
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.LEFT:
		push_error("SMOKE_FAIL last dir not LEFT")
		quit(1)
		return
	var left_poses: Dictionary = combat.call("_swing_poses", &"light", CombatSystem.StrikeDirection.LEFT)
	var top_poses: Dictionary = combat.call("_swing_poses", &"light", CombatSystem.StrikeDirection.TOP)
	var right_poses: Dictionary = combat.call("_swing_poses", &"heavy", CombatSystem.StrikeDirection.RIGHT)
	if left_poses["windup_rot"] == top_poses["windup_rot"]:
		push_error("SMOKE_FAIL left/top windup poses identical")
		quit(1)
		return
	if right_poses["windup_rot"] == top_poses["windup_rot"]:
		push_error("SMOKE_FAIL right/top windup poses identical")
		quit(1)
		return
	print("SMOKE directional_poses distinct ok")

	for _i in 80:
		await physics_frame

	# Power scaling: damage meta via profile lerp — compare costs by attempting mid vs full
	combat.stamina = combat.max_stamina
	var light_cost: float = float(CombatSystem.PROFILES[CombatSystem.Weapon.HATCHET][&"light"]["cost"])
	var heavy_cost: float = float(CombatSystem.PROFILES[CombatSystem.Weapon.HATCHET][&"heavy"]["cost"])
	var mid_power := 0.5
	var expected_mid := lerpf(light_cost, heavy_cost, mid_power)
	var sta0 := combat.stamina
	if not combat.try_attack(&"heavy", CombatSystem.StrikeDirection.RIGHT, mid_power):
		push_error("SMOKE_FAIL mid power attack failed")
		quit(1)
		return
	var spent := sta0 - combat.stamina
	print("SMOKE mid_power_cost spent=", spent, " expected~", expected_mid)
	if absf(spent - expected_mid) > 0.6:
		push_error("SMOKE_FAIL power cost mismatch spent=%.2f expected=%.2f" % [spent, expected_mid])
		quit(1)
		return
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.RIGHT:
		push_error("SMOKE_FAIL mid power dir not RIGHT")
		quit(1)
		return

	# Cancel charge path
	for _i in 80:
		await physics_frame
	combat.stamina = combat.max_stamina
	if not combat.begin_charge():
		push_error("SMOKE_FAIL begin_charge for cancel")
		quit(1)
		return
	combat.cancel_charge()
	if combat.is_charging:
		push_error("SMOKE_FAIL cancel_charge left charging")
		quit(1)
		return
	print("SMOKE cancel_charge ok")

	print("DIRECTIONAL_HATCHET_SMOKE_OK")
	quit(0)
