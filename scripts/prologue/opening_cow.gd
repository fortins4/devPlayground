extends "res://scripts/world/raid/raid_cow.gd"
## Opening-morning cow: reuses raid_cow.gd goad / proximity / path-bias AI unchanged and only
## layers tutorial feel on top (raid_cow.gd itself is untouched so the F5 raid lane is unaffected).
##
## - Idle grazing until goaded (base behaviour: proximity pressure only after herded/driven).
## - "Fresh" drive: path bias + soft follow fade out a few seconds after the last goad /
##   proximity push, so the herd stalls and grazes unless the player keeps walking behind it.
## - Bog: a bogged cow loses drive freshness quickly → has to be goaded back out.
## - Delivered: ambles to an assigned pen slot instead of freezing on the gate line.
## - Terrain: a physics body on the shared OpeningTerrain heightfield (scene floor_* overrides
##   let it walk up / over the rolls and berms). A teleport that lands it under the surface is
##   lifted back onto the ground so it can never end up walking flat under a hill.
## - Gait (visual only): procedural four-beat walk → two-beat diagonal trot on the stubby legs,
##   driven by REAL horizontal ground speed (position delta per physics tick), swung in the
##   slope-leaned body frame. Legs stand still at idle / while bogged and ease back to neutral
##   (the bogged chore cow walks while she's being goaded out).

signal goaded(cow: Node3D, kind: StringName)
## Goad landed while goad_locked (set sequence: this cow's step isn't live yet).
signal goad_blocked(cow: Node3D, kind: StringName)

## Seconds of full path bias after the last push (DRIVEN_HOLD 7.5 → 4.5 s full, ~3 s fade).
const FRESH_FULL_SECS := 4.5
const BOG_DRAIN := 2.6
const BOG_BIAS_SCALE := 0.35
const SLOT_WALK_SPEED := 1.3
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
## Below the walk surface by more than this (m) → snap back onto it (teleport guard).
const SINK_GUARD := 0.25
## Visual-only: body / head / legs lean with the ground under the cow (collider stays upright).
const SLOPE_TILT_MAX_DEG := 24.0
const SLOPE_TILT_RATE := 8.0
const _TILT_NODES := ["MeshInstance3D", "Head", "LegFL", "LegFR", "LegBL", "LegBR"]

## --- Gait (visual only; never touches velocity / colliders / AI).
const _LEG_NODES := ["LegBL", "LegFL", "LegBR", "LegFR"]  # LH, LF, RH, RF
## Phase offsets (fraction of a cycle). Walk = lateral four-beat LH→LF→RH→RF (¼ apart);
## trot = diagonal pairs together (LH+RF, RH+LF ½ apart). Blended by trot weight.
const GAIT_WALK_OFFSETS := [0.0, 0.25, 0.5, 0.75]
const GAIT_TROT_OFFSETS := [0.0, 0.5, 0.5, 1.0]
## Fraction of the cycle each hoof is planted (walk 0.75 → trot 0.5).
const GAIT_WALK_DUTY := 0.75
const GAIT_TROT_DUTY := 0.5
## Metres travelled per full cycle (cadence = speed / stride).
const GAIT_WALK_STRIDE := 0.55
const GAIT_TROT_STRIDE := 0.9
## Peak hip swing either side of plumb (deg).
const GAIT_WALK_AMP_DEG := 20.0
const GAIT_TROT_AMP_DEG := 30.0
## Trot blend: pure walk below TROT_START, pure trot above TROT_FULL (m/s).
const GAIT_TROT_START := 1.45
const GAIT_TROT_FULL := 2.2
## Below this the gait envelope eases to 0 (legs settle plumb); full swing above MOVE_FULL.
const GAIT_STILL_SPEED := 0.06
const GAIT_MOVE_FULL := 0.35
const GAIT_ENV_RATE := 6.0
const GAIT_SPEED_SMOOTH := 12.0
## Swing-phase hoof lift as a fraction of leg length (leg shortens from the hip).
const GAIT_WALK_LIFT := 0.22
const GAIT_TROT_LIFT := 0.32
const LEG_HIP_Y := 0.34
const LEG_LEN := 0.34
## Planted legs may stretch to this × nominal to reach the ground on steep downhill sides.
const LEG_STRETCH_MAX := 2.2

var _tilt_base: Dictionary = {}
var _tilt_q: Quaternion = Quaternion.IDENTITY
var _gait_phase: float = 0.0
var _gait_speed: float = 0.0
var _gait_env: float = 0.0
var _gait_trot: float = 0.0
var _gait_cadence: float = 0.0
var _gait_prev_pos: Vector3 = Vector3.ZERO
var _gait_has_prev: bool = false
var _leg_angle: Dictionary = {}
var _leg_lift: Dictionary = {}

var bogged: bool = false
## Chore cow only: while bogged and not being worked by the player, stay stuck fast
## (herd cows keep their existing bog behaviour).
var bog_hold_still: bool = false
## Set by the opening set sequence: goads bounce off (no impulse / drive / stir) until unlocked.
var goad_locked: bool = false
var start_position: Vector3 = Vector3.ZERO
var _start_basis: Basis = Basis.IDENTITY
var _pen_slot: Vector3 = Vector3.ZERO
var _has_slot: bool = false


func _ready() -> void:
	super._ready()
	start_position = global_position
	_start_basis = global_transform.basis
	for nm in _TILT_NODES:
		var n := get_node_or_null(nm) as Node3D
		if n:
			_tilt_base[nm] = n.transform


## 0..1 — how much the last goad / proximity push still carries the cow along the lane.
func drive_freshness() -> float:
	if not driven:
		return 0.0
	# Full while the timer is in its first FRESH_FULL_SECS, then linear fade to 0.
	var fade_window := maxf(0.01, DRIVEN_HOLD - FRESH_FULL_SECS)
	return clampf(_driven_timer / fade_window, 0.0, 1.0)


func is_stalled() -> bool:
	return driven and not delivered and drive_freshness() <= 0.02


func set_bogged(on: bool) -> void:
	bogged = on and not delivered


## Re-anchor idle wander (and reset_opening) on a spot set after the cow was placed —
## _ready runs inside add_child, before a spawner moves the cow to its authored spot.
func set_home_spot(p: Vector3) -> void:
	start_position = p
	_home = p
	_wander_timer = 0.0
	_pick_wander()


## Bogged with nothing player-driven acting on her (no goad impulse, no fresh drive):
## stuck fast — no wander, no drift, no slide.
func _bog_held() -> bool:
	return bog_hold_still and bogged and not delivered and _goad_vel.length_squared() < 0.0001 and drive_freshness() <= 0.02


func _wander_velocity() -> Vector3:
	if bogged and bog_hold_still:
		return Vector3.ZERO
	return super._wander_velocity()


func set_pen_slot(slot: Vector3) -> void:
	_pen_slot = slot
	_has_slot = true


func apply_goad(from_pos: Vector3, forward: Vector3, strength: float = 1.0, kind: StringName = &"light") -> void:
	if goad_locked and not delivered:
		goad_blocked.emit(self, kind)
		return
	var was_delivered := delivered
	super.apply_goad(from_pos, forward, strength, kind)
	if not was_delivered:
		goaded.emit(self, kind)


func reset_opening() -> void:
	reset_to_pen(start_position)
	global_transform.basis = _start_basis
	bogged = false
	_has_slot = false


func _path_bias_velocity() -> Vector3:
	var v: Vector3 = super._path_bias_velocity()
	var k := drive_freshness()
	if bogged:
		k *= BOG_BIAS_SCALE
	return v * k


func _soft_follow_velocity() -> Vector3:
	return super._soft_follow_velocity() * drive_freshness()


func _physics_process(delta: float) -> void:
	_keep_on_terrain()
	if delivered and _has_slot:
		_walk_to_slot(delta)
	else:
		var held := _bog_held()
		var hold_xz := global_position
		super._physics_process(delta)
		if held:
			velocity.x = 0.0
			velocity.z = 0.0
			global_position = Vector3(hold_xz.x, global_position.y, hold_xz.z)
		if bogged and driven and not delivered:
			_driven_timer = maxf(0.0, _driven_timer - delta * BOG_DRAIN)
		_tick_label()
	_tick_slope_tilt(delta)
	_tick_gait(delta)
	_apply_pose()


func _keep_on_terrain() -> void:
	var p := global_position
	var gy := Terrain.surface_y(p.x, p.z)
	if p.y < gy - SINK_GUARD:
		global_position = Vector3(p.x, gy + 0.05, p.z)
		velocity.y = 0.0


func _tick_slope_tilt(delta: float) -> void:
	## Lean the visible body with the shared terrain normal (local frame, yaw-independent).
	if _tilt_base.is_empty():
		return
	var p := global_position
	var n_world := Terrain.normal_at(p.x, p.z)
	var n_local := (global_transform.basis.orthonormalized().inverse() * n_world).normalized()
	var ang := Vector3.UP.angle_to(n_local)
	var max_a := deg_to_rad(SLOPE_TILT_MAX_DEG)
	var target := Quaternion.IDENTITY
	if ang > 0.001:
		var axis := Vector3.UP.cross(n_local).normalized()
		target = Quaternion(axis, minf(ang, max_a))
	_tilt_q = _tilt_q.slerp(target, clampf(SLOPE_TILT_RATE * delta, 0.0, 1.0))


# ---------------------------------------------------------------- gait (visual only)

func _tick_gait(delta: float) -> void:
	## Real ground speed from the horizontal position delta this tick (not AI state).
	var p := global_position
	var raw := 0.0
	if _gait_has_prev and delta > 0.0:
		var d := Vector2(p.x - _gait_prev_pos.x, p.z - _gait_prev_pos.z).length()
		if d < 1.0:  # bigger jumps are teleports / resets, not walking
			raw = d / delta
	_gait_prev_pos = p
	_gait_has_prev = true
	_gait_speed = lerpf(_gait_speed, raw, clampf(GAIT_SPEED_SMOOTH * delta, 0.0, 1.0))
	var spd := _gait_speed
	# Bogged legs stay still — except the chore cow while she's actually being goaded /
	# pushed out (not held), whose legs walk off her real ground speed like any other cow.
	if bogged and not (bog_hold_still and not _bog_held()):
		spd = 0.0
	if spd < 0.01:
		spd = 0.0
	# Envelope: 0 when still (legs ease to plumb), 1 once properly walking.
	var env_target := 0.0
	if spd > GAIT_STILL_SPEED:
		env_target = smoothstep(GAIT_STILL_SPEED, GAIT_MOVE_FULL, spd)
	_gait_env = move_toward(_gait_env, env_target, GAIT_ENV_RATE * delta)
	_gait_trot = smoothstep(GAIT_TROT_START, GAIT_TROT_FULL, spd)
	var stride := lerpf(GAIT_WALK_STRIDE, GAIT_TROT_STRIDE, _gait_trot)
	_gait_cadence = spd / stride  # cycles per second, proportional to ground speed
	_gait_phase = fposmod(_gait_phase + _gait_cadence * delta, 1.0)
	var amp := deg_to_rad(lerpf(GAIT_WALK_AMP_DEG, GAIT_TROT_AMP_DEG, _gait_trot)) * _gait_env
	var duty := lerpf(GAIT_WALK_DUTY, GAIT_TROT_DUTY, _gait_trot)
	var lift_k := lerpf(GAIT_WALK_LIFT, GAIT_TROT_LIFT, _gait_trot) * _gait_env
	for i in _LEG_NODES.size():
		var off := lerpf(GAIT_WALK_OFFSETS[i], GAIT_TROT_OFFSETS[i], _gait_trot)
		# Leg i plants when the cycle phase reaches its offset → footfalls LH, LF, RH, RF.
		var ph := fposmod(_gait_phase - off, 1.0)
		var a: float
		var lift := 0.0
		if ph < duty:
			# Stance: hoof planted, leg sweeps forward → back as the body passes over it.
			a = lerpf(amp, -amp, ph / duty)
		else:
			# Swing: hoof lifts and reaches forward again.
			var u := (ph - duty) / (1.0 - duty)
			a = lerpf(-amp, amp, u * u * (3.0 - 2.0 * u))
			lift = sin(u * PI) * lift_k
		_leg_angle[_LEG_NODES[i]] = a
		_leg_lift[_LEG_NODES[i]] = lift


func _apply_pose() -> void:
	## Body / head lean with the slope; legs swing about their hips inside that leaned frame.
	## Each leg's length is then fitted along its own (swung) axis to the real terrain under the
	## hoof (OpeningTerrain.surface_y = the collider surface), so planted hooves touch the ground
	## even on curved banks and where the upright capsule rides a little above a steep slope.
	if _tilt_base.is_empty():
		return
	var tb := Basis(_tilt_q)
	var gt := global_transform
	for nm in _tilt_base:
		var n := get_node_or_null(nm) as Node3D
		if n == null:
			continue
		var base: Transform3D = _tilt_base[nm]
		if not _leg_angle.has(nm) and not _LEG_NODES.has(nm):
			n.transform = Transform3D(tb * base.basis, tb * base.origin)
			continue
		var a: float = _leg_angle.get(nm, 0.0)
		var lift: float = _leg_lift.get(nm, 0.0)
		# Positive angle about +X swings the hoof toward -Z (the cow's head end = forward).
		var rot := tb * Basis(Vector3.RIGHT, a)
		var hip_l := tb * Vector3(base.origin.x, LEG_HIP_Y, base.origin.z)
		var axis_l := rot * Vector3.DOWN
		var reach := _leg_reach(gt * hip_l, (gt.basis * axis_l).normalized())
		# Swinging legs shorten from the hip so the hoof clears the grass.
		var length := clampf(reach - lift * LEG_LEN, LEG_LEN * 0.5, LEG_LEN * LEG_STRETCH_MAX)
		var sy := length / LEG_LEN
		n.transform = Transform3D(rot * base.basis * Basis.from_scale(Vector3(1.0, sy, 1.0)),
			hip_l + axis_l * (length * 0.5))


func _leg_reach(hip_w: Vector3, axis_w: Vector3) -> float:
	## Distance from the hip along the leg axis to the terrain surface (bisection on the shared
	## surface, robust on steep / curved banks). Nominal leg if the axis is too flat.
	if axis_w.y > -0.3:
		return LEG_LEN
	var lo := LEG_LEN * 0.5
	var hi := LEG_LEN * LEG_STRETCH_MAX
	var p_hi := hip_w + axis_w * hi
	if p_hi.y > Terrain.surface_y(p_hi.x, p_hi.z):
		return hi  # ground further than the leg can stretch
	for i in 10:
		var mid := (lo + hi) * 0.5
		var p := hip_w + axis_w * mid
		if p.y > Terrain.surface_y(p.x, p.z):
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Probe / capture helpers (read-only).
func gait_debug() -> Dictionary:
	return {
		"speed": _gait_speed, "phase": _gait_phase, "cadence": _gait_cadence,
		"env": _gait_env, "trot": _gait_trot, "angles": _leg_angle.duplicate(), "lifts": _leg_lift.duplicate(),
	}


func _walk_to_slot(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var to_slot := _pen_slot - global_position
	to_slot.y = 0.0
	if to_slot.length() > 0.3:
		var v := to_slot.normalized() * SLOT_WALK_SPEED
		velocity.x = v.x
		velocity.z = v.z
		look_at(global_position + v, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_has_slot = false
	move_and_slide()


func _tick_label() -> void:
	if label == null or _react_timer > 0.0 or delivered:
		return
	if bogged:
		label.text = "bogged!"
		label.modulate = Color(0.95, 0.55, 0.35)
	elif is_stalled():
		label.text = "grazing — goad on"
		label.modulate = Color(0.85, 0.8, 0.6)
	elif driven:
		label.text = "drove"
		label.modulate = Color(0.95, 0.85, 0.45)
	elif herded:
		label.text = "herd"
		label.modulate = Color(0.9, 0.8, 0.55)
	else:
		# Free, idle cow (e.g. the chore cow after force_free) — never leave "bogged!" stale.
		label.text = "cattle"
		label.modulate = Color(0.85, 0.78, 0.6)
