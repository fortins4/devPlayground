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
	# a foot up. Ends stay the follow pose and the ready pose.
	var body_t := pow(clampf(t, 0.0, 1.0), 0.42)
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
			# Hips drop, knees fold, shaft across the thighs. The pitch meets an
			# incoming point so the sticks touch. Still the low guard, not a stab.
			var low := _deg_pose(_pack(
				Vector3(12, 0, 0), Vector3(16, 0, 0), Vector3(-6, 0, 0),
				Vector3(0, -6, -42), Vector3(30, 0, 0),
				Vector3(34.7, 0.1, 12.5), Vector3(8.6, -84.6, 32.4),
				Vector3(42, 0, -38), Vector3(-70, 0, 0),
				Vector3(42, 0, 38), Vector3(-70, 0, 0),
				Vector3(24, 4, 102)
			))
			low["root_drop"] = 0.28
			low["grip_slide"] = 0.114
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
		"charge_0": 0.12, "charge_1": 0.12, "charge_2": 0.12, "charge_3": 0.20,
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
				_: # overhead — chest and front foot under the shaft, not a two-knee squat
					return _pack(Vector3(-26, 0, 0), Vector3(-22, 0, 0), Vector3(16, 2, 0),
						Vector3(-44, 28, 26), Vector3(22, 0, 0),
						Vector3(-188, -14, -16), Vector3(-52, 0, 0),
						Vector3(62, 0, -4), Vector3(-68, 0, 0),
						Vector3(10, 0, 4), Vector3(-34, 0, 0),
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
					return _pack(Vector3(-8, -44, -30), Vector3(12, -28, -20), Vector3(-4, 8, -4),
						Vector3(18, 28, 24), Vector3(14, 0, 0),
						Vector3(22, 16, -68), Vector3(16, 0, 0),
						Vector3(58, 4, -28), Vector3(-62, 0, 0),
						Vector3(14, 0, 10), Vector3(-22, 0, 0),
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
