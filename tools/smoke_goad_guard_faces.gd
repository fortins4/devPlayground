extends SceneTree
## Smoke: goad guard faces. Look is the guard (no F). Chest stops every frontal
## hit and still lets a rear hit through. Low stops a front stab and is not a
## timing window. High and the side faces do not stop that stab.
## Look-down alone does not stab. LMB-while-low and RMB are the same uncharged jab.
## No charge glow, no perfect-parry. A shaft charge is not the jab.

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	if packed == null:
		push_error("SMOKE_FAIL player scene")
		quit(1)
		return
	var player := packed.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var combat := player.get_node("CombatSystem") as CombatSystem
	if combat.current_weapon != CombatSystem.Weapon.GOAD:
		push_error("SMOKE_FAIL expected goad")
		quit(1)
		return
	if not _check_faces_selected(player):
		quit(1)
		return
	if not _check_poses_differ():
		quit(1)
		return
	if not _check_coverage(combat):
		quit(1)
		return
	if not _check_charge_still(combat):
		quit(1)
		return
	if not _check_mouse_lock(player, combat):
		quit(1)
		return
	print("SMOKE_OK goad-guard-faces low-stops-stab high-does-not chest-still-frontal")
	quit(0)


func _check_faces_selected(player: Node) -> bool:
	# Scheme: look offset only. No F. Neutral = chest. Down = low guard, not a jab.
	player._tool_aim_delta = Vector2.ZERO
	player.pivot.rotation.x = 0.0
	if player._resolve_shaft_guard_face() != &"chest":
		push_error("SMOKE_FAIL neutral look was not chest")
		return false
	player._tool_aim_delta = Vector2(-40.0, 0.0)
	if player._resolve_shaft_guard_face() != &"left":
		push_error("SMOKE_FAIL look left")
		return false
	player._tool_aim_delta = Vector2(40.0, 2.0)
	if player._resolve_shaft_guard_face() != &"right":
		push_error("SMOKE_FAIL look right")
		return false
	player._tool_aim_delta = Vector2(0.0, -30.0)
	if player._resolve_shaft_guard_face() != &"high":
		push_error("SMOKE_FAIL look up")
		return false
	player._tool_aim_delta = Vector2(0.0, 30.0)
	if player._resolve_shaft_guard_face() != &"low":
		push_error("SMOKE_FAIL look down")
		return false
	player._tool_aim_delta = Vector2.ZERO
	player.pivot.rotation.x = deg_to_rad(18.0)
	if player._resolve_shaft_guard_face() != &"low":
		push_error("SMOKE_FAIL camera down was not low")
		return false
	player.pivot.rotation.x = deg_to_rad(-18.0)
	if player._resolve_shaft_guard_face() != &"high":
		push_error("SMOKE_FAIL camera up was not high")
		return false
	player.pivot.rotation.x = 0.0
	return true


func _check_poses_differ() -> bool:
	var faces := ["chest", "left", "right", "high", "low"]
	var poses := {}
	for face in faces:
		var pose: Dictionary = ToolStrikePoses.tool_shaft_guard_pose(StringName(face))
		poses[face] = pose
		if not pose.has("left_arm") or not pose.has("right_arm") or not pose.has("left_thigh") or not pose.has("weapon"):
			push_error("SMOKE_FAIL pose missing body for " + face)
			return false
	var chest: Dictionary = ToolStrikePoses.tool_shaft_block_pose()
	if (poses["chest"]["weapon"] as Vector3).distance_to(chest["weapon"] as Vector3) > 0.001:
		push_error("SMOKE_FAIL chest face is not the existing shaft block")
		return false
	for i in faces.size():
		for j in range(i + 1, faces.size()):
			var a: Dictionary = poses[faces[i]]
			var b: Dictionary = poses[faces[j]]
			var weapon_gap := (a["weapon"] as Vector3).distance_to(b["weapon"] as Vector3)
			var arm_gap := (a["right_arm"] as Vector3).distance_to(b["right_arm"] as Vector3)
			var hip_gap := (a["hips"] as Vector3).distance_to(b["hips"] as Vector3)
			# Shaft angle OR the arm that places it must differ. Two upright
			# shafts can share a near-vertical euler and still sit on different sides.
			if weapon_gap < deg_to_rad(18.0) and arm_gap < deg_to_rad(35.0):
				push_error("SMOKE_FAIL faces %s and %s look too alike (weapon %.1f arm %.1f hip %.1f deg)" % [
					faces[i], faces[j], rad_to_deg(weapon_gap), rad_to_deg(arm_gap), rad_to_deg(hip_gap)
				])
				return false
			if hip_gap < deg_to_rad(4.0) and arm_gap < deg_to_rad(15.0) and weapon_gap < deg_to_rad(15.0):
				push_error("SMOKE_FAIL faces %s and %s are the same pose" % [faces[i], faces[j]])
				return false
	# None of the guards may collapse into a strike contact.
	var strikes := {
		"top": CombatSystem.StrikeDirection.TOP,
		"left": CombatSystem.StrikeDirection.LEFT,
		"right": CombatSystem.StrikeDirection.RIGHT,
		"bottom": CombatSystem.StrikeDirection.BOTTOM,
	}
	for face in faces:
		var guard: Dictionary = poses[face]
		for sname in strikes.keys():
			var strike: Dictionary = ToolStrikePoses.tool_strike_pose(
				CombatSystem.Weapon.GOAD, strikes[sname], &"contact", false
			)
			if (guard["weapon"] as Vector3).distance_to(strike["weapon"] as Vector3) < deg_to_rad(25.0):
				push_error("SMOKE_FAIL %s guard matches %s strike" % [face, sname])
				return false
	# Low is a crouch across the bottom, not the stab's single-leg lunge.
	# Shin pitch is negative so the knee folds and the foot stays planted
	# once root_drop sinks the hips. A positive shin kicks the foot up.
	var stab: Dictionary = ToolStrikePoses.tool_strike_pose(
		CombatSystem.Weapon.GOAD, CombatSystem.StrikeDirection.BOTTOM, &"contact", false
	)
	var low: Dictionary = poses["low"]
	if (low["left_thigh"] as Vector3).x > (stab["left_thigh"] as Vector3).x - deg_to_rad(8.0):
		push_error("SMOKE_FAIL low guard is a stab lunge")
		return false
	if (low["left_thigh"] as Vector3).x < deg_to_rad(20.0):
		push_error("SMOKE_FAIL low guard thighs do not pitch into a crouch")
		return false
	if absf((low["hips"] as Vector3).x) > deg_to_rad(20.0):
		push_error("SMOKE_FAIL low guard hips fold the body over")
		return false
	if (low["left_shin"] as Vector3).x > deg_to_rad(-40.0) or (low["right_shin"] as Vector3).x > deg_to_rad(-40.0):
		push_error("SMOKE_FAIL low guard knees are not bent")
		return false
	if not low.has("root_drop") or float(low["root_drop"]) < 0.12:
		push_error("SMOKE_FAIL low guard does not drop the hips")
		return false
	if absf((low["weapon"] as Vector3).z) < deg_to_rad(80.0):
		push_error("SMOKE_FAIL low shaft is not across the bottom")
		return false
	return true


func _check_coverage(combat: CombatSystem) -> bool:
	combat.health = combat.max_health
	combat.stamina = combat.max_stamina
	if not combat.set_shaft_block(true) or combat.shaft_guard_face != &"chest":
		push_error("SMOKE_FAIL chest guard did not raise")
		return false
	# Existing chest catch: frontal left and top, and a frontal stab.
	for dir in [
		CombatSystem.StrikeDirection.LEFT,
		CombatSystem.StrikeDirection.TOP,
		CombatSystem.StrikeDirection.RIGHT,
		CombatSystem.StrikeDirection.BOTTOM,
	]:
		var dealt := combat.apply_damage(16.0, null, true, dir)
		if dealt > 0.01 or combat.health < combat.max_health - 0.01:
			push_error("SMOKE_FAIL chest did not stop frontal %s" % combat.direction_name(dir))
			return false
	if not combat.is_shaft_blocking:
		push_error("SMOKE_FAIL chest dropped without a release")
		return false
	var hp := combat.health
	var rear := combat.apply_damage(10.0, null, false, CombatSystem.StrikeDirection.LEFT)
	if rear < 9.0 or combat.health > hp - 9.0:
		push_error("SMOKE_FAIL chest negated a rear hit")
		return false
	if combat.is_shaft_blocking:
		push_error("SMOKE_FAIL rear hit left the chest guard up")
		return false

	# Low stops a front stab, twice, with no timing window. Guard stays up.
	_reset(combat)
	if not combat.set_shaft_block(true):
		push_error("SMOKE_FAIL could not raise guard for low")
		return false
	combat.set_shaft_guard_face(&"low")
	var stab1 := combat.apply_damage(22.0, null, true, CombatSystem.StrikeDirection.BOTTOM)
	var stab2 := combat.apply_damage(22.0, null, true, CombatSystem.StrikeDirection.BOTTOM)
	if stab1 > 0.01 or stab2 > 0.01 or combat.health < combat.max_health - 0.01:
		push_error("SMOKE_FAIL low guard did not stop a frontal stab")
		return false
	if not combat.is_shaft_blocking or combat.shaft_guard_face != &"low":
		push_error("SMOKE_FAIL low guard dropped like a parry window")
		return false
	# Low does not blanket the other lines.
	hp = combat.health
	var through := combat.apply_damage(14.0, null, true, CombatSystem.StrikeDirection.TOP)
	if through < 13.0 or combat.health > hp - 13.0:
		push_error("SMOKE_FAIL low guard stopped an overhead")
		return false

	# High does NOT stop the stab. Left and right do not either.
	for face in [&"high", &"left", &"right"]:
		_reset(combat)
		if not combat.set_shaft_block(true):
			push_error("SMOKE_FAIL could not raise %s" % face)
			return false
		combat.set_shaft_guard_face(face)
		hp = combat.health
		var leaked := combat.apply_damage(15.0, null, true, CombatSystem.StrikeDirection.BOTTOM)
		if leaked < 14.0 or combat.health > hp - 14.0:
			push_error("SMOKE_FAIL %s stopped a low stab" % face)
			return false
		if combat.is_shaft_blocking:
			push_error("SMOKE_FAIL %s stayed up after a stab it does not cover" % face)
			return false

	# High does stop an overhead. Sides stop their flank. Not a parry.
	_reset(combat)
	combat.set_shaft_block(true)
	combat.set_shaft_guard_face(&"high")
	if combat.apply_damage(18.0, null, true, CombatSystem.StrikeDirection.TOP) > 0.01:
		push_error("SMOKE_FAIL high did not stop an overhead")
		return false
	if combat.apply_damage(18.0, null, true, CombatSystem.StrikeDirection.TOP) > 0.01:
		push_error("SMOKE_FAIL high was a one-shot parry")
		return false
	_reset(combat)
	combat.set_shaft_block(true)
	combat.set_shaft_guard_face(&"left")
	if combat.apply_damage(18.0, null, true, CombatSystem.StrikeDirection.LEFT) > 0.01:
		push_error("SMOKE_FAIL left face did not stop a left hit")
		return false
	hp = combat.health
	if combat.apply_damage(12.0, null, true, CombatSystem.StrikeDirection.RIGHT) < 11.0:
		push_error("SMOKE_FAIL left face stopped a right hit")
		return false
	_reset(combat)
	combat.set_shaft_block(true)
	combat.set_shaft_guard_face(&"right")
	if combat.apply_damage(18.0, null, true, CombatSystem.StrikeDirection.RIGHT) > 0.01:
		push_error("SMOKE_FAIL right face did not stop a right hit")
		return false

	# Open (released) still takes the stab. Sprint still drops the guard.
	_reset(combat)
	combat.set_shaft_block(false)
	if combat.apply_damage(12.0, null, true, CombatSystem.StrikeDirection.BOTTOM) < 11.0:
		push_error("SMOKE_FAIL open guard negated a stab")
		return false
	_reset(combat)
	combat.set_shaft_block(true)
	combat.set_shaft_guard_face(&"low")
	if not combat.try_sprint_drain(0.05) or combat.is_shaft_blocking:
		push_error("SMOKE_FAIL sprint did not drop the faced guard")
		return false
	return true


func _check_charge_still(combat: CombatSystem) -> bool:
	_reset(combat)
	combat.set_shaft_block(false)
	if absf(combat.charge_full_secs - 0.75) > 0.001:
		push_error("SMOKE_FAIL charge timing changed")
		return false
	if not combat.begin_charge():
		push_error("SMOKE_FAIL goad charge missing")
		return false
	if combat.is_shaft_blocking:
		push_error("SMOKE_FAIL charge left the guard up")
		return false
	combat.set_charge_direction(CombatSystem.StrikeDirection.LEFT)
	combat.set_charge_direction(CombatSystem.StrikeDirection.RIGHT)
	combat.set_charge_direction(CombatSystem.StrikeDirection.TOP)
	combat.set_charge_direction(CombatSystem.StrikeDirection.BOTTOM)
	if combat.charge_direction != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL shaft charge kept the stab")
		return false
	combat.charge_time = combat.charge_full_secs
	combat.charge_ratio = 1.0
	if not combat.release_charged_attack():
		push_error("SMOKE_FAIL full release failed")
		return false
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL full charge released a stab")
		return false
	if combat.last_attack_power < 0.95:
		push_error("SMOKE_FAIL full shaft charge lost its power")
		return false
	combat.is_attacking = false
	combat.attack_recovery_left = 0.0
	# Knife still has no guard and no charge.
	combat.set_weapon(CombatSystem.Weapon.KNIFE)
	if combat.set_shaft_block(true) or combat.begin_charge():
		push_error("SMOKE_FAIL knife gained a guard or a charge")
		return false
	combat.set_weapon(CombatSystem.Weapon.GOAD)
	return true



func _check_mouse_lock(player: Node, combat: CombatSystem) -> bool:
	if not _keys_unbound():
		return false
	_reset(combat)
	player._sprinting = false
	player.pivot.rotation.x = 0.0
	player._tool_aim_delta = Vector2(0.0, 40.0)
	player._tick_shaft_block()
	if player._resolve_shaft_guard_face() != &"low" or combat.shaft_guard_face != &"low":
		push_error("SMOKE_FAIL look-down was not the low guard")
		return false
	if combat.is_attacking or combat.is_charging:
		push_error("SMOKE_FAIL look-down alone stabbed or chambered")
		return false
	var hp := combat.health
	player._begin_hatchet_or_light()
	if combat.is_charging or combat.is_shaft_blocking:
		push_error("SMOKE_FAIL look-down click charged or kept the guard")
		return false
	if not combat.is_attacking or combat.last_strike_direction() != CombatSystem.StrikeDirection.BOTTOM:
		push_error("SMOKE_FAIL look-down click was not the jab")
		return false
	var jab_t: Dictionary = combat.last_attack_timings()
	if jab_t["kind"] != &"light" or combat.last_attack_power >= 0.0:
		push_error("SMOKE_FAIL look-down click was charged")
		return false
	var jab_reach := combat._last_attack_reach
	var recovery := combat.attack_recovery_left
	player._begin_hatchet_or_light()
	if absf(combat.attack_recovery_left - recovery) > 0.0001:
		push_error("SMOKE_FAIL held look-down click repeated the jab")
		return false
	_reset(combat)
	player._tool_aim_delta = Vector2(-40.0, 0.0)
	player._heavy_or_ignore_hatchet()
	if combat.is_charging or combat.last_strike_direction() != CombatSystem.StrikeDirection.BOTTOM:
		push_error("SMOKE_FAIL RMB was not the jab")
		return false
	var rmb_t: Dictionary = combat.last_attack_timings()
	if rmb_t["kind"] != &"light" or combat.last_attack_power >= 0.0:
		push_error("SMOKE_FAIL RMB jab was a heavy or a charge")
		return false
	if absf(combat._last_attack_reach - jab_reach) > 0.001:
		push_error("SMOKE_FAIL RMB jab did not match the look-down jab")
		return false
	if combat.is_shaft_blocking:
		push_error("SMOKE_FAIL jab left the guard up")
		return false
	_reset(combat)
	combat.set_shaft_block(true)
	combat.set_shaft_guard_face(&"low")
	var stopped := combat.apply_damage(22.0, null, true, CombatSystem.StrikeDirection.BOTTOM)
	if stopped > 0.01 or combat.health < hp - 0.01:
		push_error("SMOKE_FAIL low guard did not stop the jab")
		return false
	if not combat.is_shaft_blocking:
		push_error("SMOKE_FAIL low guard dropped on the jab it stopped")
		return false
	return true


func _keys_unbound() -> bool:
	if InputMap.has_action("shaft_block"):
		push_error("SMOKE_FAIL F shaft block is still bound")
		return false
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F:
				push_error("SMOKE_FAIL F is still bound")
				return false
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_R:
				push_error("SMOKE_FAIL R is bound")
				return false
	return true


func _reset(combat: CombatSystem) -> void:
	combat.is_attacking = false
	combat.attack_recovery_left = 0.0
	combat.is_charging = false
	combat.health = combat.max_health
	combat.stamina = combat.max_stamina
	combat.set_shaft_block(false)
