extends SceneTree
## Smoke: player starts on the cattle goad; four goad directions; knife has no stab;
## hatchet hold-charge (top/left/right, 0.75s) still exists.

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
	if combat.begin_charge():
		push_error("SMOKE_FAIL goad should not enter hatchet charge")
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
