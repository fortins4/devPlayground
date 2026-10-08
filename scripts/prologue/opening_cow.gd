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

signal goaded(cow: Node3D, kind: StringName)

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

var _tilt_base: Dictionary = {}
var _tilt_q: Quaternion = Quaternion.IDENTITY

var bogged: bool = false
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


func set_pen_slot(slot: Vector3) -> void:
	_pen_slot = slot
	_has_slot = true


func apply_goad(from_pos: Vector3, forward: Vector3, strength: float = 1.0, kind: StringName = &"light") -> void:
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
	_tick_slope_tilt(delta)
	if delivered and _has_slot:
		_walk_to_slot(delta)
		return
	super._physics_process(delta)
	if bogged and driven and not delivered:
		_driven_timer = maxf(0.0, _driven_timer - delta * BOG_DRAIN)
	_tick_label()


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
	var tb := Basis(_tilt_q)
	for nm in _tilt_base:
		var n := get_node_or_null(nm) as Node3D
		if n:
			var base: Transform3D = _tilt_base[nm]
			n.transform = Transform3D(tb * base.basis, tb * base.origin)


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
