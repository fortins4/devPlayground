extends RefCounted
## Full-body strike poses for cattle goad and knife (radians at the call site).
## Authored in degrees. Hatchet chops do NOT use this table.
##
## Goad: top / left / right are shaft swings. Bottom is a point stab (lunge).
## Charge phase is the hold aim. The release continues that pose into the strike. No glow.
## Shaft block is a held guard: both hands on the stick.
## Neutral look keeps the chest shaft. Look left/right/up/down shifts that
## same hold onto the left side, right side, a rising high shaft, or a low
## shaft across the bottom. Not a swing and not a perfect-parry pose.
## Knife: left / right are cuts (blade across). Top is a chest-height thrust
## (point forward) — not the goad's look-down stab, and not a bottom direction.
## No knife charge glow. Reach is longer than the old chest-tuck, shorter than the goad.
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
		if String(k) == "root_drop":
			continue
		var d: Vector3 = spec[k]
		var scale := 1.0
		if heavy and phase != &"idle":
			scale = 1.08 if String(k) == "weapon" else 1.16
		pose[String(k)] = Vector3(deg_to_rad(d.x * scale), deg_to_rad(d.y * scale), deg_to_rad(d.z * scale))
	# Goad strikes sink the hips so a bent knee still reaches the ground.
	# Idle is 0. Knife poses do not carry this key.
	if not is_knife:
		pose["root_drop"] = _goad_root_drop(direction, phase)
	return pose


## Hold windup. ratio 0 = idle, 1 = full 0.75s cock. Mid (~0.53) is the same
## shape but clearly short of the committed full pose. Knife does not charge
## in play (begin_charge refuses it). This helper is goad/hatchet-facing;
## a knife blend stays a short cock, never a goad charge.
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
		if String(k) == "root_drop":
			pose[k] = lerpf(float(idle.get(k, 0.0)), float(full[k]), t)
			continue
		var a: Vector3 = idle.get(k, Vector3.ZERO)
		var b: Vector3 = full[k]
		pose[k] = a.lerp(b, t)
	return pose


## Goad aim while LMB is held, before release.
## aim_x: -1 player's left .. +1 player's right. aim_y: -1 overhead .. +1 look-down stab.
## ratio 0 = idle, 1 = the full charge cock of that aim. Mid ratio is the same
## pose, short of the committed one — not a different stance.
## Neutral / look-up stays the top shaft. Look-down blends into the stab chamber.
static func tool_aim_pose(weapon: int, aim_x: float, aim_y: float, ratio: float) -> Dictionary:
	if weapon != 2:
		var dir := 0
		if aim_x <= -0.35:
			dir = 1
		elif aim_x >= 0.35:
			dir = 2
		return tool_charge_pose(weapon, dir, ratio)
	var aimed := tool_aim_phase_pose(weapon, aim_x, aim_y, &"charge")
	# Full aim is unchanged as a pose. The extra turn is only so the blend
	# from idle rides outside the skull instead of sweeping through it.
	aimed = _charge_lane(aimed, aim_x)
	var idle := tool_strike_pose(weapon, 0, &"idle", false)
	var blend := _charge_blend(ratio)
	var pose := {}
	for k in aimed.keys():
		if String(k) == "root_drop":
			pose[k] = lerpf(float(idle.get(k, 0.0)), float(aimed[k]), blend)
			continue
		var a: Vector3 = idle.get(k, Vector3.ZERO)
		var b: Vector3 = aimed[k]
		var blended: Vector3 = a.lerp(b, blend)
		# Lane adds a full turn. Store the pose, not the extra turn, so a
		# release lerp does not spin the shaft back through the head.
		if String(k) == "weapon" or String(k) == "right_arm":
			blended = Quaternion.from_euler(blended).get_euler()
		pose[k] = blended
	return pose



## Contact / follow / charge for the aim he is already holding.
## Same weights as the hold: top, left, right, and the look-down stab.
## A diagonal is that blend, not a new thrust and not a snapped cardinal.
static func tool_aim_phase_pose(weapon: int, aim_x: float, aim_y: float, phase: StringName) -> Dictionary:
	if weapon != 2:
		var dir := 0
		if aim_x <= -0.35:
			dir = 1
		elif aim_x >= 0.35:
			dir = 2
		return tool_strike_pose(weapon, dir, phase, false)
	var w := _goad_aim_weights(aim_x, aim_y)
	var top := tool_strike_pose(weapon, 0, phase, false)
	var left := tool_strike_pose(weapon, 1, phase, false)
	var right := tool_strike_pose(weapon, 2, phase, false)
	var bottom := tool_strike_pose(weapon, 3, phase, false)
	var aimed := {}
	for k in top.keys():
		if String(k) == "root_drop":
			aimed[k] = float(top.get(k, 0.0)) * w.x + float(left.get(k, 0.0)) * w.y + float(right.get(k, 0.0)) * w.z + float(bottom.get(k, 0.0)) * w.w
			continue
		var v: Vector3 = (top[k] as Vector3) * w.x
		v += (left[k] as Vector3) * w.y
		v += (right[k] as Vector3) * w.z
		v += (bottom[k] as Vector3) * w.w
		aimed[k] = v
	return aimed



## Ease from a goad follow-through back to idle.
## The short quaternion arc swings the shaft across the back of the head.
## A mid-blend bulge holds the grip out to the swing side and forward.
## The spine and legs ease back ahead of that arc so the waist does not
## jackknife and both soles are down at the halfway frame.
## Weight is zero at both ends, so the follow pose and the idle pose stay put.
## t is 0 at follow, 1 at idle. The 0.22s duration is the caller's.
static func tool_goad_settle_pose(from_pose: Dictionary, to_pose: Dictionary, t: float) -> Dictionary:
	var pose := {}
	# Spine and legs return ahead of the arms. A straight slerp of the
	# follow-through jackknifes the waist at the halfway frame and leaves
	# a foot up. The body exponent is steep so halfway is a small lean,
	# not a fold. Ends stay the follow pose and the ready pose.
	var body_t := pow(clampf(t, 0.0, 1.0), 0.15)
	for k in to_pose.keys():
		var u := t
		if String(k) in ["root_drop", "hips", "torso", "head", "left_thigh", "left_shin", "right_thigh", "right_shin"]:
			u = body_t
		if String(k) == "root_drop":
			pose[k] = lerpf(float(from_pose.get(k, 0.0)), float(to_pose[k]), u)
			continue
		var a: Vector3 = from_pose.get(k, Vector3.ZERO)
		var b: Vector3 = to_pose[k]
		pose[k] = Quaternion.from_euler(a).slerp(Quaternion.from_euler(b), u).get_euler()
	var gate := sin(clampf(t, 0.0, 1.0) * PI)
	if gate < 0.001 or not pose.has("right_arm") or not pose.has("weapon"):
		return pose
	var side := 0.0
	if from_pose.has("hips"):
		side = signf((from_pose["hips"] as Vector3).y)
	pose["right_arm"] = (pose["right_arm"] as Vector3) + Vector3(0.0, side * deg_to_rad(80.0) * gate, 0.0)
	var weapon: Vector3 = pose["weapon"]
	weapon.y += -side * deg_to_rad(40.0) * gate
	weapon.z += deg_to_rad(-30.0) * gate
	# Overhead and the stab have no hip yaw. Pitch the shaft forward so it
	# climbs in front of the neck instead of over the back of the head.
	if absf(side) < 0.5:
		weapon.x += deg_to_rad(-36.0) * gate
	pose["weapon"] = weapon
	return pose


static func _charge_lane(aimed: Dictionary, aim_x: float) -> Dictionary:
	## Side chambers: one extra turn on weapon/arm X. Same orientation at full
	## charge, but partial holds no longer drag the shaft through the head.
	if absf(aim_x) < 0.35 or not aimed.has("weapon") or not aimed.has("right_arm"):
		return aimed
	var out := aimed.duplicate(true)
	out["weapon"] = (aimed["weapon"] as Vector3) + Vector3(-TAU, 0.0, 0.0)
	out["right_arm"] = (aimed["right_arm"] as Vector3) + Vector3(TAU, 0.0, 0.0)
	return out


static func _goad_aim_weights(aim_x: float, aim_y: float) -> Vector4:
	## x = top, y = player's left, z = player's right, w = look-down stab.
	var ax := clampf(aim_x, -1.0, 1.0)
	var ay := clampf(aim_y, -1.0, 1.0)
	var w_left := clampf(-ax, 0.0, 1.0)
	var w_right := clampf(ax, 0.0, 1.0)
	var w_down := clampf(ay, 0.0, 1.0)
	var off := w_left + w_right + w_down
	if off > 1.0:
		var s := 1.0 / off
		w_left *= s
		w_right *= s
		w_down *= s
		off = 1.0
	return Vector4(1.0 - off, w_left, w_right, w_down)


## Held goad guard. Not a swing, not a stab chamber, not idle.
## Degrees are authored so both forearm tips meet the shaft across the chest.
## This is the neutral / chest face. Look faces live in tool_shaft_guard_pose.
static func tool_shaft_block_pose() -> Dictionary:
	# Right elbow sits out in front of the chest. grip_slide keeps that hand on the shaft.
	var pose := _deg_pose(_pack(
		Vector3(2, -8, 2), Vector3(-2, 6, -3), Vector3(2, 2, 0),
		Vector3(95, 35, 45), Vector3(-60, 10, 8),
		Vector3(72.7, 22.1, 40.2), Vector3(4.7, -81.0, 62.4),
		Vector3(22, 6, -10), Vector3(20, 0, 0),
		Vector3(-8, -2, 10), Vector3(22, 0, 0),
		Vector3(18, -8, 72)
	))
	pose["grip_slide"] = 0.058
	return pose


## Short hit flinch. Torso, head, and both arms recoil. The stick stays in
## the right hand and, for the goad, rises out to his right, off the face and off the back of the head.
## Knees soften and the soles stay down. Not a knockdown.
static func tool_hurt_flinch_pose(weapon: int) -> Dictionary:
	var pose := _deg_pose(_pack(
		Vector3(2, -14, 4), Vector3(14, -24, 16), Vector3(10, -26, 12),
		Vector3(78, 24, 36), Vector3(-46, 0, 0),
		Vector3(58, -12, 16), Vector3(-54, 0, 0),
		Vector3(4, 0, -2), Vector3(-8, 0, 0),
		Vector3(5, 0, 2), Vector3(-10, 0, 0),
		Vector3(-38, -44, -2)
	))
	if weapon == 2:
		pose["root_drop"] = 0.04
	elif weapon == 1:
		var idle_w: Vector3 = tool_idle_pose(1)["weapon"]
		pose["weapon"] = idle_w + Vector3(deg_to_rad(-14.0), deg_to_rad(12.0), deg_to_rad(10.0))
	else:
		pose.erase("weapon")
	return pose


## Short blend into and out of the goad flinch.
## A plain lerp swings the shaft across the face. A mid-blend turn
## holds it out to his right and forward of the skull. Weight is zero at both ends, so the
## flinch pose and the ready pose stay put. Not the settle blend.
static func tool_goad_flinch_blend(from_pose: Dictionary, to_pose: Dictionary, t: float, use_slerp: bool) -> Dictionary:
	var pose := {}
	for k in to_pose.keys():
		if String(k) == "root_drop" or String(k) == "grip_slide":
			pose[k] = lerpf(float(from_pose.get(k, 0.0)), float(to_pose[k]), t)
			continue
		var a: Vector3 = from_pose.get(k, Vector3.ZERO)
		var b: Vector3 = to_pose[k]
		if use_slerp:
			pose[k] = Quaternion.from_euler(a).slerp(Quaternion.from_euler(b), t).get_euler()
		else:
			pose[k] = a.lerp(b, t)
	var gate := sin(clampf(t, 0.0, 1.0) * PI)
	if gate < 0.001 or not pose.has("weapon"):
		return pose
	pose["weapon"] = (pose["weapon"] as Vector3) + Vector3(deg_to_rad(8.0), deg_to_rad(4.0), deg_to_rad(-22.0)) * gate
	return pose


## face: chest | left | right | high | low.
## chest is the existing diagonal shaft across the body.
## left/right hold the shaft out beside that side of the head, not in front of the face. high raises it overhead.
## low drops it across the thighs so a front stab meets the stick, not a lunge.
static func tool_shaft_guard_pose(face: StringName) -> Dictionary:
	match face:
		&"left":
			# Shaft stands on the player's left, beside the head, not down the nose.
			# Right elbow bends forward. The hand slides along the shaft so the stick stays.
			var left := _deg_pose(_pack(
				Vector3(0, 10, -4), Vector3(-8, 8, 16), Vector3(2, 8, 0),
				Vector3(40, -16, 86), Vector3(-36, 0, 0),
				Vector3(-3.1, -52.7, -88.1), Vector3(-29.6, -79.6, 86.8),
				Vector3(6, 2, -4), Vector3(8, 0, 0),
				Vector3(4, -2, 4), Vector3(8, 0, 0),
				Vector3(0, 0, 14)
			))
			left["grip_slide"] = -0.04
			return left
		&"right":
			# Shaft on the player's right, beside the head, not across the face.
			# Elbow folds so the palm capsule wraps the shaft. grip_slide keeps
			# the stick on that line instead of riding out with the forearm.
			var right := _deg_pose(_pack(
				Vector3(0, -10, 4), Vector3(0, -8, 2), Vector3(2, -8, 0),
				Vector3(36, 18, -20), Vector3(-28, 0, 0),
				Vector3(-1.6, 14.8, 59.3), Vector3(-40.7, 21.2, 88.9),
				Vector3(4, 2, -4), Vector3(8, 0, 0),
				Vector3(6, -2, 4), Vector3(8, 0, 0),
				Vector3(3.0, 0.0, -17.0)
			))
			right["grip_slide"] = -0.05
			return right
		&"high":
			# Shaft across the face, both hands up. Left elbow folds. Not the overhead chop.
			var high := _deg_pose(_pack(
				Vector3(-6, 0, 0), Vector3(-12, 0, 0), Vector3(-8, 0, 0),
				Vector3(-31.0, 66.0, 108.5), Vector3(7.0, -82.7, 46.4),
				Vector3(150, -28, 6), Vector3(-62, 4, 6),
				Vector3(4, 0, -3), Vector3(6, 0, 0),
				Vector3(4, 0, 3), Vector3(6, 0, 0),
				Vector3(30, -15, 75)
			))
			high["grip_slide"] = 0.0
			return high
		&"low":
			# Hips drop, knees fold, shaft across the front of the thighs (not
			# through them). The pitch still meets an incoming point. Guard, not a stab.
			var low := _deg_pose(_pack(
				Vector3(12, 0, 0), Vector3(16, 0, 0), Vector3(-6, 0, 0),
				Vector3(8, -4, -38), Vector3(28, 0, 0),
				Vector3(28.0, 6.0, 18.0), Vector3(6.0, -70.0, 28.0),
				Vector3(42, 0, -38), Vector3(-70, 0, 0),
				Vector3(42, 0, 38), Vector3(-70, 0, 0),
				Vector3(18, 8, 98)
			))
			low["root_drop"] = 0.28
			low["grip_slide"] = 0.08
			return low
		_:
			return tool_shaft_block_pose()



## Metres to sink the skeleton so the goad stance's bent knees still meet the ground.
## Keyed by the caller's strike direction (before the left/right authoring swap).
## 0 on idle. Not a glow and not a parry.
static func _goad_root_drop(direction: int, phase: StringName) -> float:
	if phase == &"idle":
		return 0.0
	var table := {
		"charge_0": 0.04, "charge_1": 0.12, "charge_2": 0.12, "charge_3": 0.20,
		"windup_0": 0.10, "windup_1": 0.12, "windup_2": 0.12, "windup_3": 0.12,
		"contact_0": 0.13, "contact_1": 0.12, "contact_2": 0.12, "contact_3": 0.11,
		"follow_0": 0.16, "follow_1": 0.20, "follow_2": 0.20, "follow_3": 0.10,
	}
	return float(table.get("%s_%d" % [phase, direction], 0.0))


static func _deg_pose(spec: Dictionary) -> Dictionary:
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
	# direction 0 = thrust: arm punches forward, point leads at chest height.
	# direction 1 / 2 = cuts: arm out, blade across (not a jab).
	# Bottom is rewritten to top before this runs. Not the goad look-down lunge.
	match phase:
		&"idle":
			return _pack(Vector3(0, 2, 0), Vector3(4, 4, -2), Vector3(-2, 0, 0),
				Vector3(-10, -8, 14), Vector3(22, 0, 0),
				Vector3(-24, 16, -22), Vector3(-48, 0, 0),
				Vector3(4, 0, -3), Vector3(6, 0, 0),
				Vector3(3, 0, 3), Vector3(6, 0, 0),
				Vector3(-28, 16, -36))
		&"windup":
			match direction:
				1:
					return _pack(Vector3(4, -18, 4), Vector3(-4, -12, 3), Vector3(2, 6, 0),
						Vector3(8, 14, -12), Vector3(12, 0, 0),
						Vector3(20, 10, -8), Vector3(-42, 0, 0),
						Vector3(-8, 0, 4), Vector3(16, 0, 0),
						Vector3(12, 0, -4), Vector3(10, 0, 0),
						Vector3(-40, 20, 40))
				2:
					return _pack(Vector3(4, 16, -4), Vector3(-4, 12, -3), Vector3(2, -6, 0),
						Vector3(6, -10, 12), Vector3(10, 0, 0),
						Vector3(18, 24, 6), Vector3(-40, 0, 0),
						Vector3(10, 0, -4), Vector3(8, 0, 0),
						Vector3(-8, 0, 4), Vector3(18, 0, 0),
						Vector3(-40, -20, -40))
				_:
					return _pack(Vector3(-6, 0, 0), Vector3(-8, -2, 0), Vector3(4, 0, 0),
						Vector3(6, 8, 10), Vector3(8, 0, 0),
						Vector3(10, 8, 6), Vector3(-50, 0, 0),
						Vector3(-4, 0, -2), Vector3(12, 0, 0),
						Vector3(10, 0, 2), Vector3(14, 0, 0),
						Vector3(-50, 30, 20))
		&"follow":
			match direction:
				1:
					return _pack(Vector3(4, 22, -4), Vector3(6, 16, -4), Vector3(-2, -6, 0),
						Vector3(10, -16, -10), Vector3(14, 0, 0),
						Vector3(48, -10, 6), Vector3(8, 0, 0),
						Vector3(20, 0, -6), Vector3(6, 0, 0),
						Vector3(-12, 0, 4), Vector3(24, 0, 0),
						Vector3(-170, 8, 90))
				2:
					return _pack(Vector3(4, -24, 4), Vector3(6, -18, 4), Vector3(-2, 6, 0),
						Vector3(8, 14, 10), Vector3(12, 0, 0),
						Vector3(58, -62, 8), Vector3(6, 0, 0),
						Vector3(-10, 0, 4), Vector3(22, 0, 0),
						Vector3(18, 0, -6), Vector3(8, 0, 0),
						Vector3(-170, -8, -90))
				_:
					return _pack(Vector3(14, 0, 0), Vector3(14, 0, 0), Vector3(-6, 0, 0),
						Vector3(-22, 14, 14), Vector3(16, 0, 0),
						Vector3(84, -4, 10), Vector3(2, 0, 0),
						Vector3(36, 0, -2), Vector3(6, 0, 0),
						Vector3(-18, 0, 4), Vector3(22, 0, 0),
						Vector3(-180, -90, 120))
		_:
			# contact
			match direction:
				1: # left cut — blade across the chest, edge leading left
					return _pack(Vector3(4, 18, -4), Vector3(4, 14, -4), Vector3(-2, -4, 0),
						Vector3(8, -12, -10), Vector3(14, 0, 0),
						Vector3(55, -22, 8), Vector3(8, 0, 0),
						Vector3(18, 0, -6), Vector3(6, 0, 0),
						Vector3(-12, 0, 4), Vector3(22, 0, 0),
						Vector3(-180, 0, 90))
				2: # right cut — arm extended to the open side, blade horizontal
					return _pack(Vector3(4, -18, 4), Vector3(4, -14, 4), Vector3(-2, 4, 0),
						Vector3(6, 12, 10), Vector3(12, 0, 0),
						Vector3(65, -50, 10), Vector3(8, 0, 0),
						Vector3(-10, 0, 4), Vector3(20, 0, 0),
						Vector3(16, 0, -6), Vector3(8, 0, 0),
						Vector3(-180, 0, -90))
				_: # thrust — punch forward, point up-forward, feet stay under (not a goad lunge)
					return _pack(Vector3(6, 0, 0), Vector3(8, 0, 0), Vector3(-2, 0, 0),
						Vector3(-16, 10, 10), Vector3(10, 0, 0),
						Vector3(80, 0, 12), Vector3(4, 0, 0),
						Vector3(8, 0, -2), Vector3(12, 0, 0),
						Vector3(-8, 0, 2), Vector3(14, 0, 0),
						Vector3(-180, -90, 120))


static func _goad_spec(direction: int, phase: StringName) -> Dictionary:
	# direction 3 = bottom stab. Others are shaft strikes that load the feet.
	# Shin pitch is negative so the knee folds and the sole stays down. A positive shin kicks the foot up.
	# root_drop (applied in tool_strike_pose) lowers the hips into that bend. Not a stiff A-pose.
	# Blocks 1 and 2 were authored mirrored against look direction: block 1
	# plants the shaft on the player's right, block 2 on the player's left.
	# Mouse-left is StrikeDirection.LEFT and must swing FROM the player's left,
	# so the side blocks are swapped here. Top and stab are unchanged.
	# Guard faces are not in this table. Knife cuts are not in this table.
	if direction == 1:
		direction = 2
	elif direction == 2:
		direction = 1
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
			# Full 0.75s hold. Weight steps into the strike, not a flat squat.
			# Lead hip drops, lead knee folds, trail leg stays long and planted.
			# Arms and shaft are unchanged so the stick stays outside the body.
			match direction:
				1: # player's right — mouse-right. Shaft outside the right shoulder.
					# Arm/weapon X is wrapped +360/-360 so the charge blend does not sweep through the skull.
					return _pack(Vector3(-8, -52, -16), Vector3(-24, -46, -32), Vector3(2, 20, -12),
						Vector3(-22, 40, 32), Vector3(22, 0, 0),
						Vector3(-120, 74, -188), Vector3(-55, 0, 0),
						Vector3(12, -2, -6), Vector3(-20, 0, 0),
						Vector3(58, -4, 24), Vector3(-64, 0, 0),
						Vector3(-116, 72, -164))
				2: # player's left — mouse-left. Mirror of the right chamber, shaft outside the skull.
					return _pack(Vector3(-8, 52, 16), Vector3(-24, 46, 32), Vector3(2, -20, 12),
						Vector3(16, -28, -24), Vector3(18, 0, 0),
						Vector3(-116, -76, 186), Vector3(-50, 0, 0),
						Vector3(58, 4, -24), Vector3(-64, 0, 0),
						Vector3(12, 2, 6), Vector3(-20, 0, 0),
						Vector3(-112, -70, 162))
				3: # stab aim — rear foot planted, front foot out, point leads.
					# Positive hip pitch is the load back. Contact is the lunge.
					return _pack(Vector3(22, 0, 0), Vector3(6, 0, 0), Vector3(-4, 0, 0),
						Vector3(-18, 16, 18), Vector3(16, 0, 0),
						Vector3(-36, 6, -10), Vector3(-12, 0, 0),
						Vector3(66, 0, -4), Vector3(-72, 0, 0),
						Vector3(16, 0, 4), Vector3(-26, 0, 0),
						Vector3(-72, 4, -6))
				_: # overhead — upright with a slight rock back. Bar is over the head.
					# Not a dive over the front foot. Arms are rewritten by the grip.
					return _pack(Vector3(8, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 0),
						Vector3(-44, 28, 26), Vector3(22, 0, 0),
						Vector3(-188, -14, -16), Vector3(-52, 0, 0),
						Vector3(16, 0, -4), Vector3(-26, 0, 0),
						Vector3(10, 0, 4), Vector3(-20, 0, 0),
						Vector3(30, 18, -22))
		&"windup":
			match direction:
				1: # player's right — step onto the right, shaft cocked on the right
					return _pack(Vector3(-6, -36, -22), Vector3(-4, -24, -16), Vector3(4, 10, 0),
						Vector3(-10, 24, 18), Vector3(12, 0, 0),
						Vector3(-36, 40, -62), Vector3(-18, 0, 0),
						Vector3(8, 2, -6), Vector3(-16, 0, 0),
						Vector3(46, -4, 24), Vector3(-52, 0, 0),
						Vector3(-24, 18, -78))
				2: # player's left — step onto the left, shaft cocked on the left
					return _pack(Vector3(-6, 36, 22), Vector3(-4, 24, 16), Vector3(4, -10, 0),
						Vector3(8, -16, -14), Vector3(10, 0, 0),
						Vector3(-34, -42, 64), Vector3(-16, 0, 0),
						Vector3(46, 4, -24), Vector3(-52, 0, 0),
						Vector3(8, -2, 6), Vector3(-16, 0, 0),
						Vector3(-22, -16, 76))
				3: # stab chamber — front foot out, rear foot planted
					return _pack(Vector3(12, 0, 0), Vector3(4, 0, 0), Vector3(-4, 0, 0),
						Vector3(-6, 10, 16), Vector3(14, 0, 0),
						Vector3(-28, 4, -10), Vector3(-6, 0, 0),
						Vector3(42, 0, -2), Vector3(-48, 0, 0),
						Vector3(12, 0, 2), Vector3(-18, 0, 0),
						Vector3(-62, 2, -4))
				_: # overhead — front foot under the cock, not both knees
					return _pack(Vector3(-8, 0, 0), Vector3(-6, 0, 0), Vector3(10, 4, 0),
						Vector3(-24, 16, 14), Vector3(8, 0, 0),
						Vector3(-108, -6, -18), Vector3(-22, 0, 0),
						Vector3(44, 0, -6), Vector3(-50, 0, 0),
						Vector3(10, 0, 4), Vector3(-16, 0, 0),
						Vector3(28, 8, -12))
		&"follow":
			match direction:
				1:
					return _pack(Vector3(-8, 44, 30), Vector3(12, 28, 20), Vector3(-4, -8, 4),
						Vector3(22, -36, -30), Vector3(16, 0, 0),
						Vector3(24, -18, 70), Vector3(18, 0, 0),
						Vector3(14, 0, -10), Vector3(-22, 0, 0),
						Vector3(58, -4, 28), Vector3(-62, 0, 0),
						Vector3(-8, -12, 96))
				2:
					# Left follow: both soles stay down. The left foot may step.
					# Arms and shaft are unchanged.
					return _pack(Vector3(-8, -44, -30), Vector3(12, -28, -20), Vector3(-4, 8, -4),
						Vector3(18, 28, 24), Vector3(14, 0, 0),
						Vector3(22, 16, -68), Vector3(16, 0, 0),
						Vector3(35, 45, 25), Vector3(-45, 0, 0),
						Vector3(83, -9, 27), Vector3(-59, 0, 0),
						Vector3(-6, 14, -94))
				3:
					return _pack(Vector3(-18, 0, 0), Vector3(-16, 0, 0), Vector3(10, 0, 0),
						Vector3(6, -30, -28), Vector3(22, 0, 0),
						Vector3(48, 0, -4), Vector3(-4, 0, 0),
						Vector3(52, 0, -4), Vector3(-36, 0, 0),
						Vector3(18, 0, 4), Vector3(-22, 0, 0),
						Vector3(-98, 0, 2))
				_:
					return _pack(Vector3(-8, 0, 0), Vector3(8, 4, 0), Vector3(-4, 0, 0),
						Vector3(28, -18, -22), Vector3(12, 0, 0),
						Vector3(64, 8, 24), Vector3(16, 0, 0),
						Vector3(52, 0, -6), Vector3(-48, 0, 0),
						Vector3(14, 0, 6), Vector3(-22, 0, 0),
						Vector3(-108, 6, 16))
		_:
			# contact
			match direction:
				1: # player's right contact — weight has stepped through onto the right
					return _pack(Vector3(-12, -46, -18), Vector3(-8, -36, -24), Vector3(-4, -12, 8),
						Vector3(16, -28, -24), Vector3(14, 0, 0),
						Vector3(12, -6, 58), Vector3(14, 0, 0),
						Vector3(12, 0, -4), Vector3(-18, 0, 0),
						Vector3(56, -4, 22), Vector3(-62, 0, 0),
						Vector3(-12, -6, 82))
				2: # player's left contact — weight has stepped through onto the left
					return _pack(Vector3(-12, 46, 18), Vector3(-8, 36, 24), Vector3(-4, 12, -8),
						Vector3(14, 24, 20), Vector3(12, 0, 0),
						Vector3(14, 8, -56), Vector3(12, 0, 0),
						Vector3(56, 4, -22), Vector3(-62, 0, 0),
						Vector3(12, 0, 4), Vector3(-18, 0, 0),
						Vector3(-10, 8, -80))
				3: # bottom stab — chest and front foot drive forward, rear foot stays down
					return _pack(Vector3(-22, 0, 0), Vector3(-16, 0, 0), Vector3(10, 0, 0),
						Vector3(4, -22, -22), Vector3(18, 0, 0),
						Vector3(36, 2, -6), Vector3(-6, 0, 0),
						Vector3(58, 0, -3), Vector3(-64, 0, 0),
						Vector3(20, 0, 3), Vector3(-42, 0, 0),
						Vector3(-92, 0, 2))
				_: # overhead coming down — front foot under the shaft, rear foot braced
					return _pack(Vector3(-24, 0, 0), Vector3(-16, 2, 0), Vector3(8, 0, 0),
						Vector3(-8, -20, -18), Vector3(8, 0, 0),
						Vector3(-28, 8, 16), Vector3(-8, 0, 0),
						Vector3(58, 0, -4), Vector3(-64, 0, 0),
						Vector3(12, 0, 4), Vector3(-34, 0, 0),
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


## Keep the off hand on the goad and the shaft outside the body.
## The right hand already owns the stick. This aims that stick, when needed,
## onto a point the left hand can reach, then bends the left elbow so the
## palm capsule meets the shaft. Weight is a correction on the live pose:
## it does not retune guard tables or the settle curve. Not a parry.
static func seat_goad_off_hand(loco: Object, weapon_visual: Node3D) -> void:
	if loco == null or weapon_visual == null or not weapon_visual.is_inside_tree():
		return
	var goad := weapon_visual.get_node_or_null("Goad") as Node3D
	var left_arm := loco.get_joint("left_arm") as Node3D
	var left_fore := loco.get_joint("left_forearm") as Node3D
	var torso := loco.get_joint("torso") as Node3D
	var head := loco.get_joint("head") as Node3D
	if goad == null or left_arm == null or left_fore == null or torso == null or head == null:
		return
	var right_arm_early := loco.get_joint("right_arm") as Node3D
	var right_fore_early := loco.get_joint("right_forearm") as Node3D
	if right_arm_early != null and right_fore_early != null and _is_authored_left_guard(loco, weapon_visual):
		_seat_left_guard_beside(loco, weapon_visual, goad, left_arm, left_fore, right_arm_early, right_fore_early, torso, head)
		return
	if right_arm_early != null and right_fore_early != null and _is_authored_right_guard(loco, weapon_visual):
		_seat_right_guard_beside(loco, weapon_visual, goad, left_arm, left_fore, right_arm_early, right_fore_early, torso, head)
		return
	if right_arm_early != null and right_fore_early != null and _is_authored_high_guard(loco, weapon_visual):
		_seat_high_guard_overhead(loco, weapon_visual, goad, left_arm, left_fore, right_arm_early, right_fore_early, torso, head)
		return
	if right_arm_early != null and right_fore_early != null and _is_authored_low_guard(loco, weapon_visual):
		_seat_low_guard_in_front(loco, weapon_visual, goad, left_arm, left_fore, right_arm_early, right_fore_early, torso, head)
		return
	if right_arm_early != null and right_fore_early != null and _host_flinching(loco) and _flinch_needs_face_clear(weapon_visual, goad, head):
		_seat_flinch_below_chin(loco, weapon_visual, goad, left_arm, left_fore, right_arm_early, right_fore_early, torso, head)
		return
	var shoulder: Vector3 = left_arm.global_position
	var right_arm := loco.get_joint("right_arm") as Node3D
	var right_fore := loco.get_joint("right_forearm") as Node3D
	if right_arm != null and right_fore != null and _point_in_body(weapon_visual.global_position, torso, head, loco):
		_extrude_right_hand(loco, right_arm, right_fore, torso, weapon_visual.global_position)
		var tip: Vector3 = right_fore.to_global(Vector3(0.0, -0.28, 0.05))
		weapon_visual.global_position = tip
	var origin: Vector3 = weapon_visual.global_position
	var axis: Vector3 = weapon_visual.global_transform.basis.y.normalized()
	var slide := -goad.position.y
	if _palm_meets(left_fore, origin, axis, _shaft_span(slide)) and _shaft_is_clear(origin, axis, slide, torso, head, loco):
		return
	var best_grip := Vector3.INF
	var best_axis := axis
	var best_slide := slide
	var best_cost := 999.0
	var dirs: Array[Vector3] = [axis, -axis]
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.001:
		side = axis.cross(Vector3.FORWARD)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var pitches: Array[float] = [-75.0, -45.0, -20.0, 0.0, 20.0, 45.0, 75.0]
	var yaws: Array[float] = [-110.0, -70.0, -35.0, 0.0, 35.0, 70.0, 110.0]
	for pitch in pitches:
		for yaw in yaws:
			dirs.append(axis.rotated(side, deg_to_rad(pitch)).rotated(up, deg_to_rad(yaw)).normalized())
	for local_pt in [Vector3(0.0, 0.36, -0.42), Vector3(0.22, 0.40, -0.40), Vector3(-0.18, 0.38, -0.40), Vector3(0.12, 0.16, -0.42), Vector3(0.0, 0.58, -0.46), Vector3(0.28, 0.22, -0.36)]:
		var world_pt: Vector3 = torso.to_global(local_pt)
		var to_pt := world_pt - origin
		if to_pt.length() > 0.05:
			dirs.append(to_pt.normalized())
			dirs.append(-to_pt.normalized())
	for dir in dirs:
		var found := _shaft_grip_point(shoulder, origin, dir, torso, head, loco)
		if found == Vector3.INF:
			continue
		var t_off := (found - origin).dot(dir)
		var use_slide := _slide_for(slide, 0.0, t_off)
		if not _shaft_is_clear(origin, dir, use_slide, torso, head, loco):
			continue
		var ang := rad_to_deg(acos(clampf(axis.dot(dir), -1.0, 1.0)))
		var cost := ang + absf(use_slide - slide) * 30.0
		if cost < best_cost:
			best_cost = cost
			best_axis = dir
			best_grip = found
			best_slide = use_slide
	if best_grip == Vector3.INF or best_cost >= 999.0:
		if right_arm != null and right_fore != null:
			_extrude_right_hand(loco, right_arm, right_fore, torso, weapon_visual.global_position)
			weapon_visual.global_position = right_fore.to_global(Vector3(0.0, -0.22, 0.0))
			origin = weapon_visual.global_position
			var retry := _shaft_grip_point(shoulder, origin, -torso.global_transform.basis.z, torso, head, loco)
			if retry == Vector3.INF:
				retry = _shaft_grip_point(shoulder, origin, torso.global_transform.basis.y, torso, head, loco)
			if retry == Vector3.INF:
				return
			best_grip = retry
			best_axis = (retry - origin).normalized()
			best_slide = _slide_for(slide, 0.0, (retry - origin).dot(best_axis))
			if not _shaft_is_clear(origin, best_axis, best_slide, torso, head, loco):
				return
		else:
			return
	_aim_weapon_y(weapon_visual, best_axis)
	goad.position.y = -best_slide
	var radial := shoulder - best_grip
	radial = radial - best_axis * radial.dot(best_axis)
	if radial.length() < 0.001:
		radial = -torso.global_transform.basis.z
	radial = radial.normalized()
	var palm_target: Vector3 = best_grip
	var pole: Vector3 = shoulder - torso.global_transform.basis.x * 0.45 + torso.global_transform.basis.y * -0.25
	_ik_left(loco, left_arm, left_fore, shoulder, pole, palm_target)




## Left guard only. The generic seat pulls this shaft forward of the chest.
## Keep it beside the left ear, off the neck, and bend the near arm
## so the shoulder, elbow, and hand are one limb. Other faces do not use this.
static func _is_authored_left_guard(loco: Object, weapon_visual: Node3D) -> bool:
	var pose := tool_shaft_guard_pose(&"left")
	# Look-left. Hips, chest, and head stay on this face. The beside-head
	# seat rewrites both arms and the weapon euler, and the frame syncs
	# again — those three must not be what identifies it, or the second
	# sync drops the shaft back in front of the face. Other faces are not this look.
	for joint in ["hips", "torso", "head"]:
		var have: Vector3 = loco.get_combat_additive(joint)
		if have.distance_to(pose[joint]) > deg_to_rad(5.0):
			return false
	return weapon_visual != null


static func _in_front_of_cheek(head: Node3D, p: Vector3) -> bool:
	var h: Vector3 = head.to_local(p)
	return h.z < -0.02 or h.x > -0.20


static func _seat_left_guard_beside(loco: Object, weapon_visual: Node3D, goad: Node3D, left_arm: Node3D, left_fore: Node3D, right_arm: Node3D, right_fore: Node3D, torso: Node3D, head: Node3D) -> void:
	# One vertical line outside the left ear. The low grip used to sit in
	# front of the chest, so the short shaft crossed the tunic and the cheek.
	# Both hands stay on that line. It does not cross the chest or the face.
	var up := head.global_transform.basis.y.normalized()
	var origin: Vector3 = head.to_global(Vector3(-0.50, -0.06, 0.0))
	var high: Vector3 = origin + up * 0.22
	var low: Vector3 = origin - up * 0.16
	var l_shoulder: Vector3 = left_arm.global_position
	var side := -torso.global_transform.basis.x
	var l_pole: Vector3 = l_shoulder + side * 0.55 + torso.global_transform.basis.y * -0.42 + torso.global_transform.basis.z * 0.08
	_ik_left(loco, left_arm, left_fore, l_shoulder, l_pole, high)
	var r_shoulder: Vector3 = right_arm.global_position
	var r_pole: Vector3 = r_shoulder + torso.global_transform.basis.x * 0.2 + torso.global_transform.basis.y * -0.45 + torso.global_transform.basis.z * -0.15
	_ik_right(loco, right_arm, right_fore, r_shoulder, r_pole, low)
	var l_palm: Vector3 = left_fore.to_global(Vector3(0.0, -0.22, 0.0))
	var r_palm: Vector3 = right_fore.to_global(Vector3(0.0, -0.22, 0.0))
	# A hand that lands in front of the cheek does not get to drag the stick
	# with it. A hand that is already outside the ear keeps the grip.
	if _in_front_of_cheek(head, l_palm):
		l_palm = high
	if _in_front_of_cheek(head, r_palm):
		r_palm = low
	var axis: Vector3 = (l_palm - r_palm)
	if axis.length() < 0.05:
		axis = up
	else:
		axis = axis.normalized()
	weapon_visual.global_position = r_palm
	_aim_weapon_y(weapon_visual, axis)
	var t_off := (l_palm - r_palm).dot(weapon_visual.global_transform.basis.y.normalized())
	goad.position.y = -_slide_for(-goad.position.y, 0.0, t_off)





## Right guard only. Same rule as the left: both grips on a line outside
## this ear, off the neck. A hand in front of the cheek does not drag the
## stick across the face. Left, high, and low do not use this.
static func _is_authored_right_guard(loco: Object, weapon_visual: Node3D) -> bool:
	var pose := tool_shaft_guard_pose(&"right")
	for joint in ["hips", "torso", "head"]:
		var have: Vector3 = loco.get_combat_additive(joint)
		if have.distance_to(pose[joint]) > deg_to_rad(5.0):
			return false
	return weapon_visual != null


static func _in_front_of_right_cheek(head: Node3D, p: Vector3) -> bool:
	var h: Vector3 = head.to_local(p)
	return h.z < -0.02 or h.x < 0.20


static func _seat_right_guard_beside(loco: Object, weapon_visual: Node3D, goad: Node3D, left_arm: Node3D, left_fore: Node3D, right_arm: Node3D, right_fore: Node3D, torso: Node3D, head: Node3D) -> void:
	# One line outside the right ear. The near arm is the right arm, bent
	# as one limb. The shaft does not cross the chest or sit in front of the nose.
	var up := head.global_transform.basis.y.normalized()
	# Vertical line outside the right ear. The low grip is as far right as the
	# left hand can reach without crossing the chest. Length runs upward.
	var origin: Vector3 = head.to_global(Vector3(0.24, -0.32, 0.0))
	var high: Vector3 = origin + up * 0.46
	var low: Vector3 = origin
	var basis := torso.global_transform.basis
	var r_shoulder: Vector3 = right_arm.global_position
	var r_pole: Vector3 = r_shoulder + basis.x * 0.55 + basis.y * -0.42 + basis.z * 0.08
	_ik_right(loco, right_arm, right_fore, r_shoulder, r_pole, high)
	var l_shoulder: Vector3 = left_arm.global_position
	var l_pole: Vector3 = l_shoulder - basis.x * 0.20 + basis.y * -0.45 + basis.z * -0.15
	_ik_left(loco, left_arm, left_fore, l_shoulder, l_pole, low)
	var r_palm: Vector3 = right_fore.to_global(Vector3(0.0, -0.22, 0.0))
	var l_palm: Vector3 = left_fore.to_global(Vector3(0.0, -0.22, 0.0))
	# A hand in front of the cheek, or short of the ear line, does not drag the stick.
	var line_x := 0.24
	var rh: Vector3 = head.to_local(r_palm)
	var lh: Vector3 = head.to_local(l_palm)
	# Inward of the ear line, or in front of the cheek, the hand does not drag the stick.
	if _in_front_of_right_cheek(head, r_palm) or rh.x < line_x:
		r_palm = high
	if _in_front_of_right_cheek(head, l_palm) or lh.x < line_x:
		l_palm = low
	var axis: Vector3 = r_palm - l_palm
	if axis.length() < 0.05:
		axis = up
	else:
		axis = axis.normalized()
	weapon_visual.global_position = l_palm
	_aim_weapon_y(weapon_visual, axis)
	# Butt at the low grip, so the rest of the shaft rises beside the ear.
	goad.position.y = 0.255


## High guard only. Look-up. The shaft is held over the head so it covers a
## strike from above. Off the face, off the neck, out of the body.
## Does not touch the left-guard seat or the flinch seat.
static func _is_authored_high_guard(loco: Object, weapon_visual: Node3D) -> bool:
	var pose := tool_shaft_guard_pose(&"high")
	var arm: Vector3 = loco.get_combat_additive("right_arm")
	var fore: Vector3 = loco.get_combat_additive("right_forearm")
	if arm.distance_to(pose["right_arm"]) > deg_to_rad(6.0):
		return false
	if fore.distance_to(pose["right_forearm"]) > deg_to_rad(8.0):
		return false
	if weapon_visual.rotation.distance_to(pose["weapon"]) > deg_to_rad(12.0):
		return false
	return true


static func _seat_high_guard_overhead(loco: Object, weapon_visual: Node3D, goad: Node3D, left_arm: Node3D, left_fore: Node3D, right_arm: Node3D, right_fore: Node3D, torso: Node3D, head: Node3D) -> void:
	# Bar over the skull, not beside the ear and not across the eyes.
	var right_pt: Vector3 = head.to_global(Vector3(0.18, 0.30, 0.04))
	var left_pt: Vector3 = head.to_global(Vector3(-0.16, 0.28, 0.06))
	var basis := torso.global_transform.basis
	var r_shoulder: Vector3 = right_arm.global_position
	var r_pole: Vector3 = r_shoulder + basis.x * 0.36 + basis.y * 0.22 + basis.z * 0.08
	_ik_right(loco, right_arm, right_fore, r_shoulder, r_pole, right_pt)
	var l_shoulder: Vector3 = left_arm.global_position
	var l_pole: Vector3 = l_shoulder - basis.x * 0.36 + basis.y * 0.22 + basis.z * 0.08
	_ik_left(loco, left_arm, left_fore, l_shoulder, l_pole, left_pt)
	var r_palm: Vector3 = right_fore.to_global(Vector3(0.0, -0.22, 0.0))
	var l_palm: Vector3 = left_fore.to_global(Vector3(0.0, -0.22, 0.0))
	var axis: Vector3 = (l_palm - r_palm)
	if axis.length() < 0.05:
		axis = basis.x
	else:
		axis = axis.normalized()
	weapon_visual.global_position = r_palm
	_aim_weapon_y(weapon_visual, axis)
	var t_off := (l_palm - r_palm).dot(weapon_visual.global_transform.basis.y.normalized())
	goad.position.y = -_slide_for(-goad.position.y, 0.0, t_off)


## Low guard only. Generic seat leaves the across-thighs shaft through both
## legs. Keep a near-horizontal bar in front of the thighs/knees so wood meets
## an incoming point without clipping. Left/right/high seats do not use this.
static func _is_authored_low_guard(loco: Object, weapon_visual: Node3D) -> bool:
	var pose := tool_shaft_guard_pose(&"low")
	# Crouch body owns identity. Seat rewrites arms + weapon every sync the
	# same way left/right keep hips/torso/head as the face key.
	# Do not key off thighs: walk-guard forgets leg additives each frame.
	for joint in ["hips", "torso", "head"]:
		var have: Vector3 = loco.get_combat_additive(joint)
		if have.distance_to(pose[joint]) > deg_to_rad(6.0):
			return false
	return weapon_visual != null


static func _seat_low_guard_in_front(loco: Object, weapon_visual: Node3D, goad: Node3D, left_arm: Node3D, left_fore: Node3D, right_arm: Node3D, right_fore: Node3D, torso: Node3D, head: Node3D) -> void:
	var left_thigh := loco.get_joint("left_thigh") as Node3D
	var right_thigh := loco.get_joint("right_thigh") as Node3D
	if left_thigh == null or right_thigh == null:
		return
	var mid: Vector3 = (left_thigh.global_position + right_thigh.global_position) * 0.5
	var face: Vector3 = -torso.global_transform.basis.z
	face.y = 0.0
	if face.length() < 0.001:
		face = -torso.global_transform.basis.z
	face = face.normalized()
	var side: Vector3 = torso.global_transform.basis.x
	side.y = 0.0
	if side.length() < 0.001:
		side = torso.global_transform.basis.x
	side = side.normalized()
	var up := Vector3.UP
	# Fixed clear bar first. Hands IK onto it — do not let palm drift retarget the wood into a thigh.
	var center: Vector3 = mid + face * 0.22 + up * 0.36
	var axis := side
	var origin: Vector3 = center - axis * 0.16
	weapon_visual.global_position = origin
	_aim_weapon_y(weapon_visual, axis)
	goad.position = Vector3.ZERO
	goad.rotation = Vector3.ZERO
	var r_shoulder: Vector3 = right_arm.global_position
	var l_shoulder: Vector3 = left_arm.global_position
	var r_grip := _low_guard_grip_on_shaft(origin, axis, r_shoulder)
	var l_grip := _low_guard_grip_on_shaft(origin, axis, l_shoulder)
	var r_pole: Vector3 = r_shoulder + side * 0.18 + up * -0.38 + face * 0.14
	var l_pole: Vector3 = l_shoulder - side * 0.18 + up * -0.38 + face * 0.14
	_ik_right(loco, right_arm, right_fore, r_shoulder, r_pole, r_grip)
	_ik_left(loco, left_arm, left_fore, l_shoulder, l_pole, l_grip)
	# Keep the clear bar. Slide only so both grip stations sit on the mesh.
	var t_off := (l_grip - origin).dot(axis)
	goad.position.y = -_slide_for(0.0, 0.0, t_off)


## Nearest point on the low-guard shaft a shoulder can still reach.
static func _low_guard_grip_on_shaft(origin: Vector3, axis: Vector3, shoulder: Vector3) -> Vector3:
	var best := origin
	var best_cost := 999.0
	for i in 17:
		var t := lerpf(-0.05, 0.55, float(i) / 16.0)
		var p: Vector3 = origin + axis * t
		var d := shoulder.distance_to(p)
		if d < 0.14 or d > 0.55:
			continue
		var cost := absf(d - 0.42) + absf(t - 0.22) * 0.15
		if cost < best_cost:
			best_cost = cost
			best = p
	return best



## Flinch only. The generic seat aims a clipping shaft across the chest, which
## carries it over the eyes and the mouth. Drop that line below the chin.
## Guards and the left-guard seat do not use this.
static func _host_flinching(loco: Object) -> bool:
	var host := loco.get_parent() as Node
	if host == null or not host.has_method("is_hurt_flinching"):
		return false
	return bool(host.call("is_hurt_flinching"))


static func _weapon_is_ready_pose(weapon_visual: Node3D) -> bool:
	var live: Vector3 = weapon_visual.rotation
	var ready: Array[Vector3] = [tool_idle_pose(2)["weapon"]]
	for face in ["chest", "left", "right", "high", "low"]:
		ready.append(tool_shaft_guard_pose(StringName(face))["weapon"])
	for euler in ready:
		if live.distance_to(euler) < deg_to_rad(14.0):
			return true
	return false


static func _flinch_needs_face_clear(weapon_visual: Node3D, goad: Node3D, head: Node3D) -> bool:
	# The hold and the blend are not a guard or the idle. The ends of the
	# blend stay on those ready poses and keep their own seat.
	if not _weapon_is_ready_pose(weapon_visual):
		return true
	var origin: Vector3 = weapon_visual.global_position
	var axis: Vector3 = weapon_visual.global_transform.basis.y.normalized()
	var span := _shaft_span(-goad.position.y)
	for i in 24:
		var t := lerpf(span.x, span.y, float(i) / 23.0)
		var hl: Vector3 = head.to_local(origin + axis * t)
		if hl.length() < 0.19:
			return true
		if absf(hl.y) < 0.28 and absf(hl.x) < 0.22 and (hl.z > 0.07 or hl.z < -0.09):
			return true
	return false


static func _flinch_from_name(loco: Object) -> StringName:
	var host := loco.get_parent() as Node
	if host != null and "flinch_from" in host:
		var named: StringName = host.get("flinch_from")
		if named in [&"right", &"left", &"top", &"low"]:
			return named
	return &"top"


static func _apply_flinch_lean(loco: Object, kind: StringName) -> void:
	# Torso and head only. Hips and thighs stay on the shared flinch so the
	# soles stay down. Not a guard pose and not a hatchet retune.
	var torso := Vector3.ZERO
	var head := Vector3.ZERO
	match kind:
		&"right":
			# Hit from the player's right: bend toward his left (-X). Face stays readable.
			torso = Vector3(deg_to_rad(6.0), deg_to_rad(14.0), deg_to_rad(28.0))
			head = Vector3(deg_to_rad(0.0), deg_to_rad(8.0), deg_to_rad(14.0))
		&"left":
			# Shared flinch hips already yaw left. Roll, not a spin, so the
			# chest bends to the player's right and the face stays forward.
			torso = Vector3(deg_to_rad(6.0), deg_to_rad(-6.0), deg_to_rad(-44.0))
			head = Vector3(deg_to_rad(0.0), deg_to_rad(-4.0), deg_to_rad(-18.0))
		&"low":
			# Rising hit: fold the chest back (+X sends the head toward +Z).
			torso = Vector3(deg_to_rad(24.0), 0.0, 0.0)
			head = Vector3(deg_to_rad(14.0), 0.0, 0.0)
		_:
			# Overhead: fold the chest down toward the face.
			torso = Vector3(deg_to_rad(-46.0), 0.0, 0.0)
			head = Vector3(deg_to_rad(-22.0), 0.0, 0.0)
	loco.set_combat_additive("torso", torso)
	loco.set_combat_additive("head", head)


static func _seat_flinch_below_chin(loco: Object, weapon_visual: Node3D, goad: Node3D, left_arm: Node3D, left_fore: Node3D, right_arm: Node3D, right_fore: Node3D, torso: Node3D, head: Node3D) -> void:
	var kind := _flinch_from_name(loco)
	_apply_flinch_lean(loco, kind)
	# Shaft stays off the eyes and the mouth. The line moves with the lean
	# so a side hit is not the same bar as a duck or a lean-back.
	# Head -Z is the face. The bar stays in front of the chest, under the chin.
	var right_local := Vector3(0.20, -0.55, -0.62)
	var left_local := Vector3(-0.20, -0.58, -0.66)
	var r_pole_local := Vector3(0.32, -0.28, -0.4)
	var l_pole_local := Vector3(-0.32, -0.28, -0.4)
	match kind:
		&"right":
			right_local = Vector3(-0.08, -0.42, -0.62)
			left_local = Vector3(-0.52, -0.30, -0.58)
			r_pole_local = Vector3(-0.1, -0.2, -0.45)
			l_pole_local = Vector3(-0.5, -0.12, -0.4)
		&"left":
			right_local = Vector3(0.58, -0.28, -0.60)
			left_local = Vector3(0.12, -0.40, -0.64)
			r_pole_local = Vector3(0.55, -0.10, -0.42)
			l_pole_local = Vector3(0.16, -0.18, -0.48)
		&"low":
			# Chest open, bar still in front and under the chin. Not over the skull.
			right_local = Vector3(0.22, -0.82, -0.62)
			left_local = Vector3(-0.22, -0.86, -0.66)
			r_pole_local = Vector3(0.34, -0.3, -0.4)
			l_pole_local = Vector3(-0.34, -0.3, -0.4)
		_:
			pass
	var right_pt: Vector3 = head.to_global(right_local)
	var left_pt: Vector3 = head.to_global(left_local)
	var basis := torso.global_transform.basis
	var r_shoulder: Vector3 = right_arm.global_position
	var r_pole: Vector3 = r_shoulder + basis * r_pole_local
	_ik_right(loco, right_arm, right_fore, r_shoulder, r_pole, right_pt)
	var l_shoulder: Vector3 = left_arm.global_position
	var l_pole: Vector3 = l_shoulder + basis * l_pole_local
	_ik_left(loco, left_arm, left_fore, l_shoulder, l_pole, left_pt)
	var r_palm: Vector3 = right_fore.to_global(Vector3(0.0, -0.22, 0.0))
	var l_palm: Vector3 = left_fore.to_global(Vector3(0.0, -0.22, 0.0))
	var axis: Vector3 = l_palm - r_palm
	if axis.length() < 0.05:
		axis = basis.x
	else:
		axis = axis.normalized()
	weapon_visual.global_position = r_palm
	_aim_weapon_y(weapon_visual, axis)
	var t_off := (l_palm - r_palm).dot(weapon_visual.global_transform.basis.y.normalized())
	goad.position.y = -_slide_for(-goad.position.y, 0.0, t_off)


static func _extrude_right_hand(loco: Object, arm: Node3D, fore: Node3D, torso: Node3D, origin: Vector3) -> void:
	var lp: Vector3 = torso.to_local(origin)
	var out := lp
	out.z = minf(out.z, -0.38)
	if absf(out.x) < 0.34:
		var side := signf(out.x) if absf(out.x) > 0.04 else -1.0
		out.x = side * 0.42
	out.y = clampf(out.y, 0.08, 0.62)
	var world: Vector3 = torso.to_global(out)
	var shoulder: Vector3 = arm.global_position
	var pole: Vector3 = shoulder + torso.global_transform.basis.x * signf(out.x) * 0.35 + torso.global_transform.basis.y * -0.2
	_ik_right(loco, arm, fore, shoulder, pole, world)


static func _ik_right(loco: Object, arm: Node3D, fore: Node3D, shoulder: Vector3, pole: Vector3, palm_target: Vector3) -> void:
	var l1 := 0.30
	var l2 := 0.28
	var dist := clampf(shoulder.distance_to(palm_target), 0.12, l1 + l2 - 0.015)
	var dir := (palm_target - shoulder).normalized()
	var pole_v := pole - shoulder
	var proj := pole_v - dir * pole_v.dot(dir)
	if proj.length() < 0.001:
		proj = dir.cross(Vector3.UP)
	proj = proj.normalized()
	var along := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)
	var lat := sqrt(maxf(0.0, l1 * l1 - along * along))
	var elbow := shoulder + dir * along + proj * lat
	_store_aim(loco, arm, "right_arm", elbow - shoulder)
	_store_aim(loco, fore, "right_forearm", palm_target - elbow)


static func _shaft_span(slide: float) -> Vector2:
	# 1.30 shaft. Wood runs local y -0.255 .. 1.045. Center sits at 0.395.
	var center := 0.395 - slide
	return Vector2(center - 0.65, center + 0.65)


static func _slide_for(current: float, t_hand: float, t_off: float) -> float:
	var lo := minf(t_hand, t_off) - 0.06
	var hi := maxf(t_hand, t_off) + 0.06
	# Segment is [-0.255 - slide, 1.045 - slide].
	var slide_min := -0.255 - lo
	var slide_max := 1.045 - hi
	if slide_min > slide_max:
		return current
	return clampf(current, slide_min, slide_max)


static func _shaft_grip_point(shoulder: Vector3, origin: Vector3, axis: Vector3, torso: Node3D, head: Node3D, loco: Object) -> Vector3:
	var best := Vector3.INF
	var best_score := 999.0
	for i in 25:
		var t := lerpf(-0.20, 1.00, float(i) / 24.0)
		if absf(t) < 0.18:
			continue
		var p: Vector3 = origin + axis * t
		var dist := p.distance_to(shoulder)
		if dist < 0.16 or dist > 0.54:
			continue
		if _point_in_body(p, torso, head, loco):
			continue
		var score := absf(absf(t) - 0.36) + dist * 0.15
		if score < best_score:
			best_score = score
			best = p
	return best


static func _shaft_is_clear(origin: Vector3, axis: Vector3, slide: float, torso: Node3D, head: Node3D, loco: Object) -> bool:
	var span := _shaft_span(slide)
	for i in 24:
		var t := lerpf(span.x, span.y, float(i) / 23.0)
		var p: Vector3 = origin + axis * t
		if _point_in_body(p, torso, head, loco):
			return false
		var hp: Vector3 = head.to_local(p)
		if absf(hp.y) < 0.22 and Vector2(hp.x, hp.z).length() < 0.22:
			return false
	return true


static func _point_in_body(p: Vector3, torso: Node3D, head: Node3D, loco: Object) -> bool:
	var lp: Vector3 = torso.to_local(p)
	if absf(lp.x) < 0.25 and absf(lp.y - 0.28) < 0.27 and absf(lp.z) < 0.16:
		return true
	if absf(lp.x) < 0.28 and absf(lp.y - 0.02) < 0.17 and absf(lp.z) < 0.18:
		return true
	if head.to_local(p).length() < 0.17:
		return true
	for leg_name in ["left_thigh", "left_shin", "right_thigh", "right_shin"]:
		var leg := loco.get_joint(leg_name) as Node3D
		if leg == null:
			continue
		var ll: Vector3 = leg.to_local(p)
		if ll.y < 0.04 and ll.y > -0.42 and Vector2(ll.x, ll.z).length() < 0.08:
			return true
	return false


static func _palm_meets(fore: Node3D, origin: Vector3, axis: Vector3, span: Vector2) -> bool:
	var best := 99.0
	for i in 5:
		var y := -0.27 + float(i) * 0.025
		var p: Vector3 = fore.to_global(Vector3(0.0, y, 0.0))
		var t := clampf((p - origin).dot(axis), span.x, span.y)
		var d := p.distance_to(origin + axis * t) - 0.045 - 0.023
		if d < best:
			best = d
	return best <= 0.012


static func _aim_weapon_y(weapon_visual: Node3D, world_dir: Vector3) -> void:
	var y := world_dir.normalized()
	var parent := weapon_visual.get_parent() as Node3D
	var local_y: Vector3 = parent.global_transform.basis.inverse() * y
	var current := weapon_visual.transform.basis
	var x := current.x
	x = x - local_y * x.dot(local_y)
	if x.length() < 0.001:
		x = local_y.cross(Vector3.UP)
	x = x.normalized()
	var z := x.cross(local_y).normalized()
	x = local_y.cross(z).normalized()
	weapon_visual.basis = Basis(x, local_y, z)


static func _ik_left(loco: Object, arm: Node3D, fore: Node3D, shoulder: Vector3, pole: Vector3, palm_target: Vector3) -> void:
	var l1 := 0.30
	var l2 := 0.24
	var dist := clampf(shoulder.distance_to(palm_target), 0.12, l1 + l2 - 0.015)
	var dir := (palm_target - shoulder).normalized()
	var target := shoulder + dir * dist
	var pole_v := pole - shoulder
	var proj := pole_v - dir * pole_v.dot(dir)
	if proj.length() < 0.001:
		proj = dir.cross(Vector3.UP)
	proj = proj.normalized()
	var along := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)
	var lat := sqrt(maxf(0.0, l1 * l1 - along * along))
	var elbow := shoulder + dir * along + proj * lat
	_store_aim(loco, arm, "left_arm", elbow - shoulder)
	_store_aim(loco, fore, "left_forearm", palm_target - elbow)


static func _store_aim(loco: Object, node: Node3D, joint: String, world_dir: Vector3) -> void:
	var rot_before := node.rotation
	var add_before: Vector3 = loco.get_combat_additive(joint)
	var parent := node.get_parent() as Node3D
	var local_dir: Vector3 = (parent.global_transform.basis.inverse() * world_dir).normalized()
	var y := -local_dir
	var hint := parent.global_transform.basis.inverse() * Vector3.UP
	if absf(y.dot(hint)) > 0.92:
		hint = parent.global_transform.basis.inverse() * Vector3.FORWARD
	var x := hint.cross(y).normalized()
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	node.basis = Basis(x, y, z)
	var rest := rot_before - add_before
	loco.set_combat_additive(joint, node.rotation - rest)
