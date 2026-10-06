extends SceneTree
## Smoke: hatchet hold-to-charge + top/left/right strike directions + power scaling.

const HatchetAttackTable := preload("res://systems/combat/hatchet_attack_table.gd")


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
	if absf(combat.charge_full_secs - 0.75) > 0.001:
		push_error("SMOKE_FAIL charge_full_secs expected 0.75 got %.3f" % combat.charge_full_secs)
		quit(1)
		return
	# Table damage for top tap
	var table_dmg := HatchetAttackTable.damage(&"top", &"tap")
	if table_dmg < 10.0:
		push_error("SMOKE_FAIL HatchetAttackTable missing")
		quit(1)
		return
	print("SMOKE charge_full=", combat.charge_full_secs, " table_top_tap=", table_dmg)

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

	# Simulate hold to mid charge (~0.35s of 0.75s full)
	for _i in 25:
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

	# Hold to near-full then release (charge_full=0.75s)
	for _i in 55:
		await physics_frame
	var full_ratio := combat.get_charge_ratio()
	print("SMOKE full_charge_ratio=", full_ratio)
	if full_ratio < 0.85:
		push_error("SMOKE_FAIL expected near-full charge, got %.3f" % full_ratio)
		quit(1)
		return

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
	print("SMOKE charged_top_release ok (no stamina)")

	# Wait out recovery (charged top ~1.1s total @ 60Hz ≈ 66 frames; pad heavily)
	for _i in 120:
		await physics_frame
	if combat.is_attacking:
		for _j in 90:
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

	# Timing polish (#2): light vs charged + top/left/right must differ.
	var light_top: Dictionary = combat.resolved_hatchet_timings(&"light", CombatSystem.StrikeDirection.TOP)
	var heavy_top: Dictionary = combat.resolved_hatchet_timings(&"heavy", CombatSystem.StrikeDirection.TOP)
	var light_left: Dictionary = combat.resolved_hatchet_timings(&"light", CombatSystem.StrikeDirection.LEFT)
	var heavy_right: Dictionary = combat.resolved_hatchet_timings(&"heavy", CombatSystem.StrikeDirection.RIGHT)
	print(
		"SMOKE timings light_top=%.0f/%.0f/%.0f ms heavy_top=%.0f/%.0f/%.0f ms" % [
			float(light_top["windup"]) * 1000.0, float(light_top["active"]) * 1000.0, float(light_top["recovery"]) * 1000.0,
			float(heavy_top["windup"]) * 1000.0, float(heavy_top["active"]) * 1000.0, float(heavy_top["recovery"]) * 1000.0,
		]
	)
	if float(heavy_top["windup"]) <= float(light_top["windup"]) + 0.05:
		push_error("SMOKE_FAIL charged windup not clearly longer than light")
		quit(1)
		return
	if float(heavy_top["recovery"]) <= float(light_top["recovery"]) + 0.08:
		push_error("SMOKE_FAIL charged recovery not clearly longer than light")
		quit(1)
		return
	if absf(float(light_top["windup"]) - float(light_left["windup"])) < 0.01:
		push_error("SMOKE_FAIL top/left light windup identical (expected dir scale)")
		quit(1)
		return
	if float(light_left["windup"]) >= float(light_top["windup"]):
		push_error("SMOKE_FAIL left windup should be snappier than top")
		quit(1)
		return
	if float(heavy_top["windup"]) < 0.28 or float(heavy_top["recovery"]) < 0.5:
		push_error("SMOKE_FAIL heavy top telegraph/recover too short")
		quit(1)
		return
	var phases: Dictionary = combat.swing_phase_durations(&"heavy", float(heavy_top["windup"]), float(heavy_top["active"]), float(heavy_top["recovery"]))
	if float(phases["windup_hold"]) < 0.04:
		push_error("SMOKE_FAIL heavy windup hold missing")
		quit(1)
		return
	if float(phases["contact_hold"]) < 0.02:
		push_error("SMOKE_FAIL heavy contact hold missing")
		quit(1)
		return
	print("SMOKE timing_polish ok left_w=%.0fms right_heavy_r=%.0fms" % [
		float(light_left["windup"]) * 1000.0, float(heavy_right["recovery"]) * 1000.0,
	])

	for _i in 100:
		await physics_frame

	# Power scaling: a mid-power commit always goes through (no stamina cost).
	var mid_power := 0.5
	if not combat.try_attack(&"heavy", CombatSystem.StrikeDirection.RIGHT, mid_power):
		push_error("SMOKE_FAIL mid power attack failed")
		quit(1)
		return
	print("SMOKE mid_power ok power=", combat.last_attack_power)
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.RIGHT:
		push_error("SMOKE_FAIL mid power dir not RIGHT")
		quit(1)
		return

	# Cancel charge path
	for _i in 120:
		await physics_frame
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

	# Hit-stun cancels charge
	if not combat.begin_charge():
		push_error("SMOKE_FAIL begin_charge for hitstun")
		quit(1)
		return
	combat.apply_damage(5.0, null, true)
	if combat.is_charging:
		push_error("SMOKE_FAIL apply_damage did not cancel charge")
		quit(1)
		return
	print("SMOKE hitstun_cancel ok")

	# Sprint cancels charge
	if not combat.begin_charge():
		push_error("SMOKE_FAIL begin_charge for sprint")
		quit(1)
		return
	var sprinted := combat.try_sprint()
	if not sprinted:
		push_error("SMOKE_FAIL sprint refused")
		quit(1)
		return
	if combat.is_charging:
		push_error("SMOKE_FAIL sprint did not cancel charge")
		quit(1)
		return
	print("SMOKE sprint_cancel ok")

	print("DIRECTIONAL_HATCHET_SMOKE_OK")
	quit(0)
