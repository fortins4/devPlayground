extends SceneTree
## Smoke: arm charge poses diverge by face; idle hold present; player combat loads.


func _initialize() -> void:
	_run()


func _run() -> void:
	# Load via player scene so autoloads / class cache resolve cleanly.
	var packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	if packed == null:
		push_error("SMOKE_FAIL missing player.tscn")
		quit(1)
		return
	var player := packed.instantiate() as Node3D
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await process_frame
	await process_frame

	var combat := player.get_node_or_null("CombatSystem")
	var loco := player.get_node_or_null("KerneLocomotion")
	if combat == null or loco == null:
		push_error("SMOKE_FAIL missing combat/loco")
		quit(1)
		return
	if loco.has_method("rebuild") and loco.joints.is_empty():
		loco.rebuild()

	var top: Dictionary = CombatSystem.hatchet_charge_arm_pose(CombatSystem.StrikeDirection.TOP, 1.0)
	var left: Dictionary = CombatSystem.hatchet_charge_arm_pose(CombatSystem.StrikeDirection.LEFT, 1.0)
	var right: Dictionary = CombatSystem.hatchet_charge_arm_pose(CombatSystem.StrikeDirection.RIGHT, 1.0)
	var idle: Dictionary = CombatSystem.hatchet_idle_arm_pose()
	var top_arm: Vector3 = top["right_arm"]
	var left_arm: Vector3 = left["right_arm"]
	var right_arm: Vector3 = right["right_arm"]
	print("SMOKE top=", top_arm, " left=", left_arm, " right=", right_arm, " idle=", idle["right_arm"])

	if top_arm.x > -1.5:
		push_error("SMOKE_FAIL top pitch shallow %s" % top_arm)
		quit(1)
		return
	if left_arm.y <= 0.4 or right_arm.y >= -0.4:
		push_error("SMOKE_FAIL left/right yaw not opposed L=%s R=%s" % [left_arm, right_arm])
		quit(1)
		return
	var mid: Dictionary = CombatSystem.hatchet_charge_arm_pose(CombatSystem.StrikeDirection.TOP, 0.35)
	if absf((mid["right_arm"] as Vector3).x) >= absf(top_arm.x) * 0.9:
		push_error("SMOKE_FAIL mid should be weaker than full")
		quit(1)
		return
	if (idle["right_arm"] as Vector3).is_equal_approx(Vector3.ZERO):
		push_error("SMOKE_FAIL idle zero")
		quit(1)
		return

	# Apply charge pose through loco additives and confirm joint moved.
	var arm0: Vector3 = Vector3.ZERO
	var ra = loco.get_right_arm()
	if ra:
		arm0 = ra.rotation
	loco.set_combat_additive("right_arm", top_arm)
	loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	if ra and ra.rotation.is_equal_approx(arm0):
		push_error("SMOKE_FAIL right_arm did not move after additive")
		quit(1)
		return

	if not combat.has_method("set_weapon_rest_transform"):
		push_error("SMOKE_FAIL missing set_weapon_rest_transform")
		quit(1)
		return
	if not combat.begin_charge():
		push_error("SMOKE_FAIL begin_charge")
		quit(1)
		return
	combat.set_charge_direction(CombatSystem.StrikeDirection.RIGHT)
	# Advance charge without depending on many physics frames (script hosts can be flaky).
	combat.charge_time = combat.charge_full_secs
	combat.charge_ratio = 1.0
	if not combat.release_charged_attack():
		push_error("SMOKE_FAIL release")
		quit(1)
		return
	if not combat.is_attacking:
		push_error("SMOKE_FAIL not attacking after release")
		quit(1)
		return

	print("SMOKE_OK hatchet_arm_feel")
	quit(0)
