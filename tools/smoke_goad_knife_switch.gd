extends SceneTree
## Smoke: goad hold-charge (four directions, 0.75s, light tap vs full);
## knife has no stab and no charge; hatchet hold-charge (top/left/right) remains.

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
		push_error("SMOKE_FAIL expected starting goad, got %s" % combat.weapon_name())
		quit(1)
		return
	if not bool(player.get_node("WeaponVisual/Goad").visible):
		push_error("SMOKE_FAIL goad mesh hidden")
		quit(1)
		return
	if bool(player.get_node("WeaponVisual/Hatchet").visible) or bool(player.get_node("WeaponVisual/Knife").visible):
		push_error("SMOKE_FAIL non-goad mesh visible at start")
		quit(1)
		return
	if not _check_goad_charge(combat):
		quit(1)
		return

	var poses := {}
	for dir_name in ["top", "left", "right", "bottom"]:
		var d := _dir(dir_name)
		var pose: Dictionary = ToolStrikePoses.tool_strike_pose(CombatSystem.Weapon.GOAD, d, &"contact", false)
		poses[dir_name] = pose
		if not pose.has("left_thigh") or not pose.has("hips") or not pose.has("weapon"):
			push_error("SMOKE_FAIL pose missing body joints for " + dir_name)
			quit(1)
			return
	# Shaft strikes load laterally; stab commits forward and must not match them.
	var left_yaw: float = (poses["left"]["hips"] as Vector3).y
	var right_yaw: float = (poses["right"]["hips"] as Vector3).y
	if left_yaw * right_yaw >= 0.0 or absf(left_yaw) < deg_to_rad(20.0):
		push_error("SMOKE_FAIL left/right hips do not oppose")
		quit(1)
		return
	var stab_thigh: float = (poses["bottom"]["left_thigh"] as Vector3).x
	var idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var idle_thigh: float = (idle["left_thigh"] as Vector3).x
	if stab_thigh < deg_to_rad(40.0) or absf(stab_thigh - idle_thigh) < deg_to_rad(30.0):
		push_error("SMOKE_FAIL stab does not lunge the front leg")
		quit(1)
		return
	var top_arm: float = (poses["top"]["right_arm"] as Vector3).x
	var stab_arm: float = (poses["bottom"]["right_arm"] as Vector3).x
	var top_weapon: float = (poses["top"]["weapon"] as Vector3).x
	var stab_weapon: float = (poses["bottom"]["weapon"] as Vector3).x
	if stab_arm <= top_arm or absf(stab_weapon - top_weapon) < deg_to_rad(30.0):
		push_error("SMOKE_FAIL top shaft and stab do not separate")
		quit(1)
		return

	if not combat.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM):
		push_error("SMOKE_FAIL goad stab failed")
		quit(1)
		return
	if combat.is_charging or combat.last_strike_direction() != CombatSystem.StrikeDirection.BOTTOM:
		push_error("SMOKE_FAIL stab was not a bottom tap")
		quit(1)
		return
	combat.is_attacking = false
	combat.attack_recovery_left = 0.0

	combat.set_weapon(CombatSystem.Weapon.KNIFE)
	if combat.weapon_name() != &"knife":
		push_error("SMOKE_FAIL knife switch")
		quit(1)
		return
	if combat.begin_charge():
		push_error("SMOKE_FAIL knife should stay a tap, not a charge")
		quit(1)
		return
	if not combat.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM):
		push_error("SMOKE_FAIL knife attack")
		quit(1)
		return
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL knife accepted a bottom stab")
		quit(1)
		return
	combat.is_attacking = false
	combat.attack_recovery_left = 0.0

	combat.set_weapon(CombatSystem.Weapon.HATCHET)
	if not combat.begin_charge():
		push_error("SMOKE_FAIL hatchet charge missing")
		quit(1)
		return
	if absf(combat.charge_full_secs - 0.75) > 0.001:
		push_error("SMOKE_FAIL hatchet charge timing changed")
		quit(1)
		return
	combat.set_charge_direction(CombatSystem.StrikeDirection.BOTTOM)
	if combat.charge_direction != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL hatchet accepted bottom")
		quit(1)
		return
	combat.cancel_charge()
	var _idle_hatchet: Dictionary = CombatSystem.hatchet_idle_arm_pose()
	var _charge_hatchet: Dictionary = CombatSystem.hatchet_charge_arm_pose(CombatSystem.StrikeDirection.LEFT, 1.0)
	if not combat.try_attack(&"light", CombatSystem.StrikeDirection.BOTTOM):
		push_error("SMOKE_FAIL hatchet tap")
		quit(1)
		return
	if combat.last_strike_direction() != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL hatchet bottom was not clamped to top")
		quit(1)
		return

	combat.is_attacking = false
	combat.attack_recovery_left = 0.0
	combat.set_weapon(CombatSystem.Weapon.GOAD)
	combat.cycle_weapon(1)
	if combat.current_weapon != CombatSystem.Weapon.KNIFE:
		push_error("SMOKE_FAIL Q from goad should land on knife")
		quit(1)
		return

	print("SMOKE_OK goad-knife-switch")
	quit(0)



func _check_goad_charge(combat: CombatSystem) -> bool:
	combat.stamina = combat.max_stamina
	if absf(combat.charge_full_secs - 0.75) > 0.001:
		push_error("SMOKE_FAIL charge_full_secs is not 0.75")
		return false
	if not combat.begin_charge():
		push_error("SMOKE_FAIL goad charge did not start")
		return false
	combat.set_charge_direction(CombatSystem.StrikeDirection.LEFT)
	if combat.charge_direction != CombatSystem.StrikeDirection.LEFT:
		push_error("SMOKE_FAIL goad charge ignored left")
		return false
	combat.set_charge_direction(CombatSystem.StrikeDirection.BOTTOM)
	if combat.charge_direction != CombatSystem.StrikeDirection.BOTTOM:
		push_error("SMOKE_FAIL goad charge rejected stab")
		return false
	# Direction can change again during the hold.
	combat.set_charge_direction(CombatSystem.StrikeDirection.RIGHT)
	combat.set_charge_direction(CombatSystem.StrikeDirection.TOP)
	if combat.charge_direction != CombatSystem.StrikeDirection.TOP:
		push_error("SMOKE_FAIL goad charge direction stuck")
		return false
	combat.charge_time = 0.05
	combat.charge_ratio = combat.charge_time / combat.charge_full_secs
	combat.set_charge_direction(CombatSystem.StrikeDirection.LEFT)
	if not combat.release_charged_attack():
		push_error("SMOKE_FAIL early goad release failed")
		return false
	if combat.is_charging:
		push_error("SMOKE_FAIL early release left goad charging")
		return false
	var light_t: Dictionary = combat.last_attack_timings()
	if light_t["kind"] != &"light" or light_t["direction"] != &"left":
		push_error("SMOKE_FAIL early release was not a left light")
		return false
	var light_reach := combat._last_attack_reach
	_reset_attack(combat)

	if not combat.begin_charge():
		push_error("SMOKE_FAIL mid charge restart failed")
		return false
	combat.charge_time = 0.40
	combat.charge_ratio = combat.charge_time / combat.charge_full_secs
	combat.set_charge_direction(CombatSystem.StrikeDirection.BOTTOM)
	if not combat.release_charged_attack():
		push_error("SMOKE_FAIL mid goad release failed")
		return false
	var mid_reach := combat._last_attack_reach
	if mid_reach <= light_reach + 0.02:
		push_error("SMOKE_FAIL mid charge reach did not sit above light")
		return false
	if combat.last_attack_power < 0.4 or combat.last_attack_power > 0.7:
		push_error("SMOKE_FAIL mid power not between light and full")
		return false
	_reset_attack(combat)

	if not combat.begin_charge():
		push_error("SMOKE_FAIL full charge restart failed")
		return false
	combat.charge_time = 0.75
	combat.charge_ratio = 1.0
	combat.set_charge_direction(CombatSystem.StrikeDirection.BOTTOM)
	if not combat.release_charged_attack():
		push_error("SMOKE_FAIL full goad release failed")
		return false
	if combat.is_charging:
		push_error("SMOKE_FAIL full release stuck in windup")
		return false
	var full_t: Dictionary = combat.last_attack_timings()
	if full_t["kind"] != &"heavy" or full_t["direction"] != &"bottom":
		push_error("SMOKE_FAIL full release was not a heavy stab")
		return false
	if combat._last_attack_reach <= mid_reach + 0.02:
		push_error("SMOKE_FAIL full reach did not exceed mid")
		return false
	if combat.last_attack_power < 0.95:
		push_error("SMOKE_FAIL full power not at the top of the charge")
		return false
	_reset_attack(combat)

	if not combat.begin_charge():
		push_error("SMOKE_FAIL charge before hit-stun failed")
		return false
	combat.apply_damage(1.0, null)
	if combat.is_charging:
		push_error("SMOKE_FAIL hit-stun did not cancel goad charge")
		return false
	if not combat.begin_charge():
		push_error("SMOKE_FAIL charge before sprint failed")
		return false
	if not combat.try_sprint_drain(0.05):
		push_error("SMOKE_FAIL sprint drain failed")
		return false
	if combat.is_charging:
		push_error("SMOKE_FAIL sprint did not cancel goad charge")
		return false

	var shaft_mid: Dictionary = ToolStrikePoses.tool_charge_pose(CombatSystem.Weapon.GOAD, CombatSystem.StrikeDirection.LEFT, 0.40 / 0.75)
	var shaft_full: Dictionary = ToolStrikePoses.tool_charge_pose(CombatSystem.Weapon.GOAD, CombatSystem.StrikeDirection.LEFT, 1.0)
	var hip_gap := absf((shaft_full["hips"] as Vector3).y) - absf((shaft_mid["hips"] as Vector3).y)
	if hip_gap < deg_to_rad(12.0):
		push_error("SMOKE_FAIL shaft mid/full hips too similar")
		return false
	var stab_mid: Dictionary = ToolStrikePoses.tool_charge_pose(CombatSystem.Weapon.GOAD, CombatSystem.StrikeDirection.BOTTOM, 0.40 / 0.75)
	var stab_full: Dictionary = ToolStrikePoses.tool_charge_pose(CombatSystem.Weapon.GOAD, CombatSystem.StrikeDirection.BOTTOM, 1.0)
	var thigh_gap := (stab_full["left_thigh"] as Vector3).x - (stab_mid["left_thigh"] as Vector3).x
	var lean_gap := (stab_full["hips"] as Vector3).x - (stab_mid["hips"] as Vector3).x
	if thigh_gap < deg_to_rad(10.0) or lean_gap < deg_to_rad(8.0):
		push_error("SMOKE_FAIL stab mid/full not more committed")
		return false
	# Full stab windup must move more than a static idle hold.
	var idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	if absf((stab_full["left_thigh"] as Vector3).x - (idle["left_thigh"] as Vector3).x) < deg_to_rad(25.0):
		push_error("SMOKE_FAIL full stab charge does not plant the front foot")
		return false
	if absf((shaft_full["right_arm"] as Vector3).z - (idle["right_arm"] as Vector3).z) < deg_to_rad(40.0):
		push_error("SMOKE_FAIL full shaft charge does not cock the arm")
		return false
	return true


func _reset_attack(combat: CombatSystem) -> void:
	combat.is_attacking = false
	combat.attack_recovery_left = 0.0
	combat.stamina = combat.max_stamina


func _dir(name: String) -> int:
	match name:
		"left":
			return CombatSystem.StrikeDirection.LEFT
		"right":
			return CombatSystem.StrikeDirection.RIGHT
		"bottom":
			return CombatSystem.StrikeDirection.BOTTOM
		_:
			return CombatSystem.StrikeDirection.TOP
