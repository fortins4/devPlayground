extends RefCounted
## Full-body strike poses for cattle goad and knife (radians at the call site).
## Authored in degrees. Hatchet chops do NOT use this table.
##
## Goad: top / left / right are shaft swings. Bottom is a point stab (lunge).
## Charge phase is the hold windup (bigger than the swing windup). No glow.
## Shaft block is a held guard: both hands on the stick, stick across the body.
## Knife: top / left / right only, shorter reach, still a weight shift.
## Keys are KerneLocomotion joint names plus "weapon" (player-space euler for the mesh).


static func tool_idle_pose(weapon: int) -> Dictionary:
	return tool_strike_pose(weapon, 0, &"idle", false)


static func tool_strike_pose(weapon: int, direction: int, phase: StringName, heavy: bool = false) -> Dictionary:
	# CombatSystem.Weapon: HATCHET=0, KNIFE=1, GOAD=2
	# CombatSystem.StrikeDirection: TOP=0, LEFT=1, RIGHT=2, BOTTOM=3
	var is_knife := weapon == 1
	if is_knife and direction == 3:
		direction = 0
	var spec: Dictionary = _knife_spec(direction, phase) if is_knife else _goad_spec(direction, phase)
	var pose := {}
	for k in spec.keys():
		var d: Vector3 = spec[k]
		var scale := 1.0
		if heavy and phase != &"idle":
			scale = 1.08 if String(k) == "weapon" else 1.16
		pose[String(k)] = Vector3(deg_to_rad(d.x * scale), deg_to_rad(d.y * scale), deg_to_rad(d.z * scale))
	return pose


## Hold windup. ratio 0 = idle, 1 = full 0.75s cock. Mid (~0.53) is the same
## shape but clearly short of the committed full pose. Knife is a shorter
## windup only — no knife stab, and not the goad charge.
static func tool_charge_pose(weapon: int, direction: int, ratio: float) -> Dictionary:
	var is_knife := weapon == 1
	if is_knife and direction == 3:
		direction = 0
	var idle := tool_strike_pose(weapon, direction, &"idle", false)
	var full: Dictionary = tool_strike_pose(weapon, direction, &"windup", false) if is_knife else tool_strike_pose(weapon, direction, &"charge", false)
	var t := _charge_blend(ratio)
	if is_knife:
		t *= 0.55
	var pose := {}
	for k in full.keys():
		var a: Vector3 = idle.get(k, Vector3.ZERO)
		var b: Vector3 = full[k]
		pose[k] = a.lerp(b, t)
	return pose



## Held goad guard. Not a swing, not a stab chamber, not idle.
## Degrees are authored so both forearm tips meet the shaft across the chest.
static func tool_shaft_block_pose() -> Dictionary:
	var spec := _pack(
		Vector3(2, -8, 2), Vector3(-2, 6, -3), Vector3(2, 2, 0),
		Vector3(95, 35, 45), Vector3(-60, 10, 8),
		Vector3(70, -6, 22), Vector3(-42, 12, -6),
		Vector3(22, 6, -10), Vector3(20, 0, 0),
		Vector3(-8, -2, 10), Vector3(22, 0, 0),
		Vector3(18, -8, 72)
	)
	var pose := {}
	for k in spec.keys():
		var d: Vector3 = spec[k]
		pose[String(k)] = Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))
	return pose


static func _charge_blend(ratio: float) -> float:
	# 0.40s / 0.75s ≈ 0.53 lands near half the cock. The last third of the
	# hold adds the committed lean so full still reads heavier than mid.
	var t := clampf(ratio, 0.0, 1.0)
	return t * (0.72 + 0.28 * t)


static func _knife_spec(direction: int, phase: StringName) -> Dictionary:
	# Smaller than the goad, but hips/feet still leave a neutral stance.
	match phase:
		&"idle":
			return _pack(Vector3(0, 2, 0), Vector3(6, 4, -2), Vector3(-2, 0, 0),
				Vector3(-8, -6, 16), Vector3(18, 0, 0),
				Vector3(-46, 22, -40), Vector3(-18, 0, 0),
				Vector3(4, 0, -3), Vector3(6, 0, 0),
				Vector3(3, 0, 3), Vector3(6, 0, 0),
				Vector3(-52, 26, -62))
		&"windup":
			match direction:
				1:
					return _pack(Vector3(4, -16, 6), Vector3(-4, -14, 4), Vector3(2, 8, 0),
						Vector3(12, 18, -22), Vector3(10, 0, 0),
						Vector3(-28, 28, -48), Vector3(-10, 0, 0),
						Vector3(-8, 0, 4), Vector3(16, 0, 0),
						Vector3(14, 0, -4), Vector3(10, 0, 0),
						Vector3(-18, 36, -20))
				2:
					return _pack(Vector3(4, 16, -6), Vector3(-4, 14, -4), Vector3(2, -8, 0),
						Vector3(6, -10, 18), Vector3(8, 0, 0),
						Vector3(-30, -32, 36), Vector3(-12, 0, 0),
						Vector3(12, 0, -4), Vector3(8, 0, 0),
						Vector3(-10, 0, 6), Vector3(18, 0, 0),
						Vector3(-16, -34, 28))
				_:
					return _pack(Vector3(8, -4, 0), Vector3(-12, -4, 0), Vector3(6, 0, 0),
						Vector3(-16, 8, 10), Vector3(6, 0, 0),
						Vector3(-70, 6, -18), Vector3(-16, 0, 0),
						Vector3(-6, 0, -2), Vector3(14, 0, 0),
						Vector3(10, 0, 2), Vector3(18, 0, 0),
						Vector3(-18, 12, -24))
		&"follow":
			match direction:
				1:
					return _pack(Vector3(6, 22, -10), Vector3(8, 16, -8), Vector3(-2, -6, 0),
						Vector3(16, -22, -28), Vector3(14, 0, 0),
						Vector3(18, -8, 48), Vector3(12, 0, 0),
						Vector3(22, 0, -12), Vector3(6, 0, 0),
						Vector3(-16, 0, 6), Vector3(28, 0, 0),
						Vector3(12, -28, 58))
				2:
					return _pack(Vector3(6, -22, 10), Vector3(8, -16, 8), Vector3(-2, 6, 0),
						Vector3(14, 16, 22), Vector3(12, 0, 0),
						Vector3(16, 10, -46), Vector3(10, 0, 0),
						Vector3(-14, 0, 6), Vector3(26, 0, 0),
						Vector3(20, 0, -10), Vector3(8, 0, 0),
						Vector3(10, 30, -52))
				_:
					return _pack(Vector3(-8, 2, 0), Vector3(16, 4, 0), Vector3(-4, 0, 0),
						Vector3(18, -12, -16), Vector3(10, 0, 0),
						Vector3(36, 6, 22), Vector3(14, 0, 0),
						Vector3(28, 0, -4), Vector3(4, 0, 0),
						Vector3(-18, 0, 4), Vector3(32, 0, 0),
						Vector3(22, 4, 16))
		_:
			# contact
			match direction:
				1:
					return _pack(Vector3(4, 16, -8), Vector3(6, 12, -6), Vector3(0, -4, 0),
						Vector3(10, -16, -20), Vector3(12, 0, 0),
						Vector3(8, 4, 36), Vector3(8, 0, 0),
						Vector3(18, 0, -10), Vector3(4, 0, 0),
						Vector3(-12, 0, 5), Vector3(22, 0, 0),
						Vector3(6, -18, 42))
				2:
					return _pack(Vector3(4, -16, 8), Vector3(6, -12, 6), Vector3(0, 4, 0),
						Vector3(8, 14, 18), Vector3(10, 0, 0),
						Vector3(10, -2, -34), Vector3(6, 0, 0),
						Vector3(-10, 0, 5), Vector3(20, 0, 0),
						Vector3(16, 0, -8), Vector3(6, 0, 0),
						Vector3(4, 20, -40))
				_:
					return _pack(Vector3(-6, 0, 0), Vector3(12, 2, 0), Vector3(-2, 0, 0),
						Vector3(12, -8, -12), Vector3(8, 0, 0),
						Vector3(22, 4, 16), Vector3(10, 0, 0),
						Vector3(22, 0, -3), Vector3(2, 0, 0),
						Vector3(-14, 0, 3), Vector3(26, 0, 0),
						Vector3(14, 2, 10))


static func _goad_spec(direction: int, phase: StringName) -> Dictionary:
	# direction 3 = bottom stab. Others are shaft strikes that load the feet.
	match phase:
		&"idle":
			# Upright prod in the right hand. Feet under the hips — not a lunge.
			return _pack(Vector3(0, 0, 0), Vector3(3, 4, 0), Vector3(-2, 0, 0),
				Vector3(6, 4, 12), Vector3(8, 0, 0),
				Vector3(-22, 8, -16), Vector3(-10, 0, 0),
				Vector3(2, 0, -3), Vector3(4, 0, 0),
				Vector3(2, 0, 3), Vector3(4, 0, 0),
				Vector3(-18, 6, -6))
		&"charge":
			# Full 0.75s hold. Deeper than swing windup so mid vs full stills differ.
			match direction:
				1: # left shaft — hard coil, shaft hauled back, both feet loaded
					return _pack(Vector3(12, -52, -18), Vector3(-14, -36, -14), Vector3(8, 18, 0),
						Vector3(-22, 40, 32), Vector3(22, 0, 0),
						Vector3(-70, 74, -108), Vector3(-42, 0, 0),
						Vector3(-26, 0, 12), Vector3(40, 0, 0),
						Vector3(34, 0, -16), Vector3(46, 0, 0),
						Vector3(-56, 42, -124))
				2: # right shaft
					return _pack(Vector3(12, 52, 18), Vector3(-14, 36, 14), Vector3(8, -18, 0),
						Vector3(16, -28, -24), Vector3(18, 0, 0),
						Vector3(-66, -76, 106), Vector3(-38, 0, 0),
						Vector3(32, 0, -14), Vector3(44, 0, 0),
						Vector3(-24, 0, 14), Vector3(42, 0, 0),
						Vector3(-52, -40, 122))
				3: # stab chamber — lean back, front foot planted, point not yet thrust
					return _pack(Vector3(36, 0, 0), Vector3(28, 0, 0), Vector3(-12, 0, 0),
						Vector3(-32, 22, 28), Vector3(28, 0, 0),
						Vector3(-64, 10, -22), Vector3(-28, 0, 0),
						Vector3(46, 0, -8), Vector3(22, 0, 0),
						Vector3(-22, 0, 6), Vector3(58, 0, 0),
						Vector3(-88, 8, -14))
				_: # top shaft — knees deep, chest back, shaft cocked overhead
					return _pack(Vector3(28, -16, 0), Vector3(-40, -12, 0), Vector3(20, 8, 0),
						Vector3(-44, 28, 26), Vector3(22, 0, 0),
						Vector3(-158, -14, -36), Vector3(-52, 0, 0),
						Vector3(-24, 0, -10), Vector3(48, 0, 0),
						Vector3(34, 0, 10), Vector3(54, 0, 0),
						Vector3(70, 18, -32))
		&"windup":
			match direction:
				1: # left shaft — coil onto the right leg, shaft cocked to the right
					return _pack(Vector3(6, -28, -10), Vector3(-6, -18, -6), Vector3(4, 10, 0),
						Vector3(-10, 24, 18), Vector3(12, 0, 0),
						Vector3(-36, 40, -62), Vector3(-18, 0, 0),
						Vector3(-12, 0, 6), Vector3(22, 0, 0),
						Vector3(18, 0, -8), Vector3(16, 0, 0),
						Vector3(-24, 18, -78))
				2: # right shaft — coil onto the left leg
					return _pack(Vector3(6, 28, 10), Vector3(-6, 18, 6), Vector3(4, -10, 0),
						Vector3(8, -16, -14), Vector3(10, 0, 0),
						Vector3(-34, -42, 64), Vector3(-16, 0, 0),
						Vector3(16, 0, -6), Vector3(14, 0, 0),
						Vector3(-14, 0, 8), Vector3(24, 0, 0),
						Vector3(-22, -16, 76))
				3: # stab chamber — weight back, point not yet committed
					return _pack(Vector3(10, 0, 0), Vector3(6, 0, 0), Vector3(-4, 0, 0),
						Vector3(-6, 10, 16), Vector3(14, 0, 0),
						Vector3(-28, 4, -10), Vector3(-6, 0, 0),
						Vector3(-4, 0, -2), Vector3(10, 0, 0),
						Vector3(8, 0, 2), Vector3(16, 0, 0),
						Vector3(-62, 2, -4))
				_: # top shaft — knees soft, shaft cocked overhead, chest back
					return _pack(Vector3(14, -8, 0), Vector3(-18, -6, 0), Vector3(10, 4, 0),
						Vector3(-24, 16, 14), Vector3(8, 0, 0),
						Vector3(-108, -6, -18), Vector3(-22, 0, 0),
						Vector3(-10, 0, -4), Vector3(20, 0, 0),
						Vector3(16, 0, 4), Vector3(28, 0, 0),
						Vector3(28, 8, -12))
		&"follow":
			match direction:
				1:
					return _pack(Vector3(-4, 40, 16), Vector3(10, 22, 10), Vector3(-4, -8, 0),
						Vector3(22, -36, -30), Vector3(16, 0, 0),
						Vector3(24, -18, 70), Vector3(18, 0, 0),
						Vector3(36, 0, -22), Vector3(6, 0, 0),
						Vector3(-30, 0, 8), Vector3(46, 0, 0),
						Vector3(-8, -12, 96))
				2:
					return _pack(Vector3(-4, -40, -16), Vector3(10, -22, -10), Vector3(-4, 8, 0),
						Vector3(18, 28, 24), Vector3(14, 0, 0),
						Vector3(22, 16, -68), Vector3(16, 0, 0),
						Vector3(-28, 0, 8), Vector3(44, 0, 0),
						Vector3(34, 0, -20), Vector3(8, 0, 0),
						Vector3(-6, 14, -94))
				3:
					return _pack(Vector3(-16, 0, 0), Vector3(-20, 0, 0), Vector3(14, 0, 0),
						Vector3(6, -30, -28), Vector3(22, 0, 0),
						Vector3(48, 0, -4), Vector3(-4, 0, 0),
						Vector3(68, 0, -4), Vector3(-6, 0, 0),
						Vector3(-48, 0, 6), Vector3(62, 0, 0),
						Vector3(-98, 0, 2))
				_:
					return _pack(Vector3(-12, 4, 0), Vector3(20, 6, 0), Vector3(-6, 0, 0),
						Vector3(28, -18, -22), Vector3(12, 0, 0),
						Vector3(64, 8, 24), Vector3(16, 0, 0),
						Vector3(48, 0, -6), Vector3(4, 0, 0),
						Vector3(-36, 0, 6), Vector3(50, 0, 0),
						Vector3(-108, 6, 16))
		_:
			# contact
			match direction:
				1: # left shaft — hips, shoulders, and left foot commit left
					return _pack(Vector3(-2, 32, 14), Vector3(8, 16, 8), Vector3(-2, -6, 0),
						Vector3(16, -28, -24), Vector3(14, 0, 0),
						Vector3(12, -6, 58), Vector3(14, 0, 0),
						Vector3(30, 0, -18), Vector3(4, 0, 0),
						Vector3(-24, 0, 6), Vector3(38, 0, 0),
						Vector3(-12, -6, 82))
				2: # right shaft
					return _pack(Vector3(-2, -32, -14), Vector3(8, -16, -8), Vector3(-2, 6, 0),
						Vector3(14, 24, 20), Vector3(12, 0, 0),
						Vector3(14, 8, -56), Vector3(12, 0, 0),
						Vector3(-22, 0, 6), Vector3(36, 0, 0),
						Vector3(28, 0, -16), Vector3(6, 0, 0),
						Vector3(-10, 8, -80))
				3: # bottom stab — chest and front foot drive forward, point leads
					return _pack(Vector3(-14, 0, 0), Vector3(-18, 0, 0), Vector3(12, 0, 0),
						Vector3(4, -22, -22), Vector3(18, 0, 0),
						Vector3(36, 2, -6), Vector3(-6, 0, 0),
						Vector3(58, 0, -3), Vector3(-4, 0, 0),
						Vector3(-42, 0, 5), Vector3(54, 0, 0),
						Vector3(-92, 0, 2))
				_: # top shaft coming down — hand still high, shaft diagonal, front foot loaded
					return _pack(Vector3(-4, 0, 0), Vector3(-10, 3, 0), Vector3(6, 0, 0),
						Vector3(-8, -20, -18), Vector3(8, 0, 0),
						Vector3(-28, 8, 16), Vector3(-8, 0, 0),
						Vector3(36, 0, -6), Vector3(4, 0, 0),
						Vector3(-26, 0, 6), Vector3(40, 0, 0),
						Vector3(-42, 6, 18))


## hips, torso, head, left_arm, left_forearm, right_arm, right_forearm,
## left_thigh, left_shin, right_thigh, right_shin, weapon. Degrees.
static func _pack(
	hips: Vector3, torso: Vector3, head: Vector3,
	left_arm: Vector3, left_forearm: Vector3,
	right_arm: Vector3, right_forearm: Vector3,
	left_thigh: Vector3, left_shin: Vector3,
	right_thigh: Vector3, right_shin: Vector3,
	weapon: Vector3
) -> Dictionary:
	return {
		"hips": hips,
		"torso": torso,
		"head": head,
		"left_arm": left_arm,
		"left_forearm": left_forearm,
		"right_arm": right_arm,
		"right_forearm": right_forearm,
		"left_thigh": left_thigh,
		"left_shin": left_shin,
		"right_thigh": right_thigh,
		"right_shin": right_shin,
		"weapon": weapon,
	}
