class_name PlayerBogSubmerge
extends Node
## Deep-bog layer on top of the player's existing crouch (not a parallel stance).
##
## In a BogZone with deep_water: standing wades (legs under), crouch drops him to
## the shoulders, and keeping crouch held takes him under with only the top of
## the head and the eyes out. Release crouch to rise. While sunk: slow creep, no
## sprint, no attacks except the ambush rise, weapon keys ignored, and the goad
## (if out) is pinned to the existing look-guard faces that sit below the
## shoulder line: chest at the shoulders, low (flat, two hands) once under.
## A look can't lift it through the surface.
##
## Breath exists only while fully under (no meter anywhere else, no effect on
## attacks or sprint). Running out forces him up with a loud gasp, heard
## through DetectionSensor hearing via get_noise_radius().
##
## Afterwards he is wet and muddy: darker, glossy clothes fading over
## WET_FADE_SEC. DetectionSensor bumps suspicion once if it sees him wet up close.
##
## Ambush: a guard within AMBUSH_REACH of a sunk Cian + attack press = rise and
## lunge into the existing goad point jab (both hands), armed as a surprise
## strike on CombatSystem (bonus damage + stagger through the normal hit path).

# --- Depths (metres) ---
const BANK_WIDTH := 1.1 ## water shelves from the outline to full wading depth over this
const WADE_DROP := 0.78 ## standing in deep water: water at the upper thigh
const SHOULDER_ABOVE_WATER := 0.02 ## shoulder depth: shoulder tops just break the surface (shaft stays ~8 cm under)
const UNDER_HEAD_ABOVE := 0.03 ## fully under: head centre this far above the water
const UNDER_THRESHOLD := 1.85 ## sink >= this counts as fully under (breath, HUD)
# --- Timing ---
const SINK_RATE := 2.2 ## sink units/s surface -> shoulders (~0.45 s)
const UNDER_HOLD_SEC := 1.0 ## crouch held AT the shoulders this long before going under
const UNDER_RATE := 1.1 ## sink units/s shoulders -> under (~0.9 s)
const RISE_RATE := 2.4
const GASP_RISE_RATE := 3.5
const AMBUSH_RISE_RATE := 10.0 ## under -> up in ~0.2 s
const VISUAL_SPEED_DOWN := 1.5 ## m/s, body descent is eased, never snapped
const VISUAL_SPEED_UP := 2.4
const VISUAL_SPEED_AMBUSH := 8.0
# --- Movement ---
const WADE_SPEED := 2.6
const CREEP_SPEED_SHOULDER := 1.1
const CREEP_SPEED_UNDER := 0.75
# --- Sight ---
const VIS_WADE := 0.85
const VIS_SHOULDER := 0.15
const VIS_UNDER := 0.04
const VIS_MOVE_PER_MPS := 0.04 ## creeping stirs the surface a little
# --- Breath ---
const BREATH_SEC := 13.0
const BREATH_RESET_BELOW := 1.5 ## head clear of the water: breath refills
const GASP_NOISE := 1.0
const GASP_RADIUS := 18.0
const GASP_SEC := 1.6
const GASP_RESINK_LOCK := 2.5
# --- Wet / mud ---
const WET_FADE_SEC := 75.0
const WET_MUD := Color(0.20, 0.15, 0.08)
# --- Ambush ---
const AMBUSH_REACH := 2.5
const AMBUSH_MULT := 2.5
const AMBUSH_STAGGER := &"stagger_heavy"
const AMBUSH_STRIKE_DIST := 1.05 ## lunge stops this far from the guard (jab reach)
const AMBUSH_LUNGE_SEC := 0.22
var ambush_jab_delay := 0.06 ## jab lands as the rise completes, not while still under
const AMBUSH_SURPRISE_WINDOW := 0.9

var player: CharacterBody3D
var zone: Node3D = null
var wade: float = 0.0
var sink: float = 0.0
var breath_left: float = BREATH_SEC
var wet: float = 0.0
var stats := {
	"slip_ins": 0, "surfaces": 0, "gasps": 0, "ambushes": 0,
	"ambush_refused": 0, "ripples": 0, "sounds": 0,
}
var last_sound: StringName = &""

var _hold: float = 0.0
var _sink_target: float = 0.0
var _gasp_left: float = 0.0
var _resink_lock: float = 0.0
var _suppress_crouch: bool = false
var _visual_y: float = NAN
var _visual_active: bool = false
var _head_world_y: float = 0.0
var _ripple_t: float = 0.0
var _burst_noise: float = 0.0
var _burst_left: float = 0.0
var _speed: float = 0.0
var _was_sunk: bool = false
var _was_in_water: bool = false
var _ambush_t: float = -1.0
var _ambush_target: Node3D = null
var _ambush_fired: bool = false
var _wet_meshes: Array = [] ## [MeshInstance3D, original Material]
var _wet_copies: Dictionary = {} ## original Material -> wet StandardMaterial3D
var _wet_applied: float = -1.0
var _hud: CanvasLayer
var _hud_root: Control
var _hud_bar: ProgressBar
var _hud_label: Label
var _hud_fill: StyleBoxFlat


func setup(owner_player: CharacterBody3D) -> void:
	player = owner_player
	_build_hud()


# --- Queries used by the controller / DetectionSensor ----------------------

func is_in_water() -> bool:
	return zone != null and wade > 0.001


func is_sunk() -> bool:
	return sink > 0.25


func is_fully_under() -> bool:
	return sink >= UNDER_THRESHOLD


func is_ambushing() -> bool:
	return _ambush_t >= 0.0


func is_gasping() -> bool:
	return _gasp_left > 0.0


## Crouch filter: after a gasp or an ambush he stays up until crouch is released.
func filter_crouch(want: bool, held: bool) -> bool:
	if not held:
		_suppress_crouch = false
	if _suppress_crouch or is_ambushing():
		return false
	return want


func blocks_sprint() -> bool:
	return is_sunk() or wade > 0.35 or is_ambushing()


## Attacks and weapon keys are swallowed while sunk (the ambush is the only strike).
func blocks_combat_input() -> bool:
	return is_sunk() or is_ambushing()


## Goad look-guard while in the water crouched: chest at the shoulders (the
## shaft sits ~0.13 m under the shoulder tops), low once he goes under (flat,
## lower still). Looking up / sideways can't lift it out. "" = normal look-guard.
func forced_guard_face() -> StringName:
	if is_ambushing():
		# Until the jab owns the shaft, hold the low guard (hands stay on it).
		return &"" if _ambush_fired else &"low"
	if _sink_target >= 2.0 or sink > 1.02:
		return &"low"
	if _sink_target > 0.0 or sink > 0.05:
		return &"chest"
	return &""


func limit_speed(target: float) -> float:
	if is_ambushing():
		return target
	if sink > 1.0:
		return minf(target, lerpf(CREEP_SPEED_SHOULDER, CREEP_SPEED_UNDER, clampf(sink - 1.0, 0.0, 1.0)))
	if sink > 0.05:
		return minf(target, lerpf(WADE_SPEED, CREEP_SPEED_SHOULDER, clampf(sink, 0.0, 1.0)))
	if wade > 0.35:
		return minf(target, WADE_SPEED)
	return target


func visibility_factor() -> float:
	var f := lerpf(1.0, VIS_WADE, wade)
	if sink <= 1.0:
		f = lerpf(f, VIS_SHOULDER, clampf(sink, 0.0, 1.0))
	else:
		f = lerpf(VIS_SHOULDER, VIS_UNDER, clampf(sink - 1.0, 0.0, 1.0))
	if sink > 0.25:
		f += VIS_MOVE_PER_MPS * _speed
	return clampf(f, 0.0, 1.0)


## LOS aim point: the head once he is down in the water.
func visibility_point(base: Vector3) -> Vector3:
	if sink <= 0.01 or zone == null:
		return base
	var water := zone.call("water_surface_y") as float
	var head := Vector3(base.x, maxf(_head_world_y + 0.04, water + 0.05), base.z)
	return base.lerp(head, clampf(sink, 0.0, 1.0))


func filter_noise(noise: float, speed: float) -> float:
	var n := noise
	if is_sunk():
		# Slow wading under the surface: below DetectionSensor's 0.12 hearing floor.
		n = 0.0 if speed < 0.15 else 0.07 + 0.04 * clampf(speed / CREEP_SPEED_SHOULDER, 0.0, 1.0)
	elif wade > 0.35 and speed > 0.15:
		n = maxf(n, 0.5 + 0.25 * clampf(speed / WADE_SPEED, 0.0, 1.0))
	if _burst_left > 0.0:
		n = maxf(n, _burst_noise)
	if _gasp_left > 0.0:
		n = maxf(n, GASP_NOISE)
	return n


func noise_radius() -> float:
	return GASP_RADIUS if _gasp_left > 0.0 else 0.0


## 0..1 wet tint (1 = just out of the bog, 0 = dry).
func wet_level() -> float:
	return wet


## Wet as seen by a guard: only once he is up out of the water.
func wet_suspicion() -> float:
	return wet if sink < 0.25 else 0.0


func breath_fraction() -> float:
	return clampf(breath_left / BREATH_SEC, 0.0, 1.0)


func is_breath_hud_visible() -> bool:
	return _hud_root != null and _hud_root.visible


# --- Per-frame -----------------------------------------------------------

## Called right after the controller's _apply_crouch_visual.
func tick(delta: float, crouching: bool, speed: float) -> void:
	if player == null:
		return
	_speed = speed
	_resolve_zone()
	var pos := player.global_position
	var can_sink: bool = (
		zone != null
		and bool(zone.call("is_deep_at", pos))
		and not bool(player.call("is_dragging"))
	)
	var in_water := is_in_water()
	if _resink_lock > 0.0:
		_resink_lock = maxf(0.0, _resink_lock - delta)
	if _gasp_left > 0.0:
		_gasp_left = maxf(0.0, _gasp_left - delta)
	if _burst_left > 0.0:
		_burst_left = maxf(0.0, _burst_left - delta)

	# Sink target from the existing crouch.
	var want_sink: bool = crouching and can_sink and _resink_lock <= 0.0 and not is_ambushing()
	if want_sink:
		if sink >= 0.98:
			_hold += delta
		_sink_target = 2.0 if _hold >= UNDER_HOLD_SEC else 1.0
	else:
		_hold = 0.0
		_sink_target = 0.0
	var rate := RISE_RATE
	if _sink_target > sink:
		rate = SINK_RATE if sink < 1.0 else UNDER_RATE
	elif is_ambushing():
		rate = AMBUSH_RISE_RATE
	elif _gasp_left > 0.0:
		rate = GASP_RISE_RATE
	sink = move_toward(sink, _sink_target, rate * delta)

	_tick_breath(delta)
	_tick_events(delta, in_water)
	_tick_wet(delta, in_water)
	_apply_visual(delta)
	_tick_ambush(delta)
	_refresh_hud()


func _resolve_zone() -> void:
	zone = null
	wade = 0.0
	var pos := player.global_position
	for z in player.get_tree().get_nodes_in_group("bog_deep"):
		if not (z is Node3D) or not z.has_method("is_in_water"):
			continue
		if not bool(z.call("is_in_water", pos)):
			continue
		var local := (z as Node3D).to_local(pos)
		var r := Vector2(local.x, local.z)
		var edge := float(z.call("outline_radius", atan2(r.y, r.x)))
		zone = z as Node3D
		wade = clampf((edge - r.length()) / BANK_WIDTH, 0.0, 1.0)
		return


func _tick_breath(delta: float) -> void:
	if is_fully_under():
		breath_left = maxf(0.0, breath_left - delta)
		if breath_left <= 0.0:
			_force_gasp()
	elif sink < BREATH_RESET_BELOW:
		breath_left = BREATH_SEC


func _force_gasp() -> void:
	stats["gasps"] = int(stats["gasps"]) + 1
	_gasp_left = GASP_SEC
	_resink_lock = GASP_RESINK_LOCK
	_suppress_crouch = true
	_sink_target = 0.0
	_hold = 0.0
	breath_left = BREATH_SEC
	_ripple(1.3)
	_sound(&"splash", 0.9)
	_sound(&"gasp", 1.2)


func _tick_events(delta: float, in_water: bool) -> void:
	var sunk := is_sunk()
	var fast := clampf(_speed / 3.0, 0.0, 1.0)
	if sunk and not _was_sunk:
		stats["slip_ins"] = int(stats["slip_ins"]) + 1
		_ripple(0.9 + 0.5 * fast)
		_sound(&"splash", 0.55 + 0.45 * fast)
		_burst(0.28 + 0.2 * fast, 0.35)
	elif _was_sunk and not sunk:
		stats["surfaces"] = int(stats["surfaces"]) + 1
		if not is_gasping():
			_ripple(0.8 + 0.5 * fast)
			_sound(&"splash", 0.5 + 0.4 * fast)
			_burst(0.26, 0.3)
	if in_water and not _was_in_water and _speed > 3.0:
		_ripple(1.3)
		_sound(&"splash", 1.0)
	_was_sunk = sunk
	_was_in_water = in_water
	# Moving through the water: rings + squelch/splash, bigger and louder when fast.
	if in_water and _speed > 0.25:
		_ripple_t -= delta
		if _ripple_t <= 0.0:
			var strength := 0.35
			var kind := &"squelch"
			var level := 0.3
			if not sunk:
				strength = 0.75 if _speed < 3.5 else 1.3
				kind = &"splash"
				level = 0.45 if _speed < 3.5 else 1.0
			_ripple(strength)
			_sound(kind, level)
			_ripple_t = lerpf(0.75, 0.32, clampf(_speed / 5.0, 0.0, 1.0))
	else:
		_ripple_t = minf(_ripple_t, 0.15)


func _tick_wet(delta: float, in_water: bool) -> void:
	if sink > 0.5:
		wet = 1.0
	elif not in_water and wet > 0.0:
		wet = maxf(0.0, wet - delta / WET_FADE_SEC)
	_apply_wet_tint()


func _apply_visual(delta: float) -> void:
	var visual := player.get("visual") as Node3D
	if visual == null:
		return
	var base_y := visual.position.y # what the crouch just set this frame
	if not _visual_active and zone == null:
		_visual_y = base_y
		return
	if is_nan(_visual_y):
		_visual_y = base_y
	var loco = player.get("locomotion")
	var head: Node3D = loco.get_joint("head") if loco else null
	var shoulder := visual.find_child("ShoulderR", true, false) as Node3D
	var root_y := player.global_position.y + base_y
	var target := base_y
	if zone != null and head and shoulder:
		var water := float(zone.call("water_surface_y")) - player.global_position.y
		var head_local := head.global_position.y - root_y
		var shoulder_local := shoulder.global_position.y + 0.05 - root_y
		var y_wade := base_y - wade * WADE_DROP
		var y_sh := water + SHOULDER_ABOVE_WATER - shoulder_local
		var y_under := water + UNDER_HEAD_ABOVE - head_local
		if sink <= 1.0:
			target = lerpf(y_wade, y_sh, clampf(sink, 0.0, 1.0))
		else:
			target = lerpf(y_sh, y_under, clampf(sink - 1.0, 0.0, 1.0))
	var speed := VISUAL_SPEED_DOWN if target < _visual_y else VISUAL_SPEED_UP
	if is_ambushing():
		speed = VISUAL_SPEED_AMBUSH
	_visual_y = move_toward(_visual_y, target, speed * delta)
	_visual_active = zone != null or absf(_visual_y - base_y) > 0.002
	visual.position.y = _visual_y
	if head:
		_head_world_y = head.global_position.y


# --- Ambush ----------------------------------------------------------------

## Attack press while sunk. Returns true if the rise strike started.
func request_ambush() -> bool:
	if is_ambushing() or not is_sunk():
		return false
	var target := _nearest_guard()
	if target == null:
		stats["ambush_refused"] = int(stats["ambush_refused"]) + 1
		return false
	if target.has_method("ensure_hittable"):
		target.call("ensure_hittable")
	var combat = player.get("combat")
	if combat == null:
		return false
	stats["ambushes"] = int(stats["ambushes"]) + 1
	_ambush_target = target
	_ambush_t = 0.0
	_ambush_fired = false
	_suppress_crouch = true
	_sink_target = 0.0
	_hold = 0.0
	# Face him now (still under the surface).
	var to := target.global_position - player.global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		player.rotation.y = atan2(-to.x, -to.z)
	# Goad into both hands. If it was on the back it swaps under the water.
	player.call("bog_ready_goad")
	combat.call("arm_surprise_strike", AMBUSH_MULT, AMBUSH_STAGGER, AMBUSH_SURPRISE_WINDOW)
	_ripple(1.4)
	_sound(&"splash", 1.1)
	_burst(0.6, 0.4)
	return true


func _nearest_guard() -> Node3D:
	var best: Node3D = null
	var best_d := AMBUSH_REACH
	for n in player.get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or n == player:
			continue
		var g := n as Node3D
		var cs := g.get_node_or_null("CombatSystem")
		if cs and bool(cs.get("is_dead")):
			continue
		var d := g.global_position - player.global_position
		if absf(d.y) > 1.2:
			continue
		d.y = 0.0
		var dist := d.length()
		if dist <= best_d:
			best_d = dist
			best = g
	return best


func is_lunging() -> bool:
	return is_ambushing() and _ambush_t < AMBUSH_LUNGE_SEC + 0.08


func lunge_velocity() -> Vector3:
	if not is_lunging() or _ambush_target == null or not is_instance_valid(_ambush_target):
		return Vector3.ZERO
	var to := _ambush_target.global_position - player.global_position
	to.y = 0.0
	var rem := to.length() - AMBUSH_STRIKE_DIST
	if rem <= 0.02:
		return Vector3.ZERO
	var left := maxf(0.05, AMBUSH_LUNGE_SEC - _ambush_t)
	return to.normalized() * clampf(rem / left, 0.0, 7.5)


func _tick_ambush(delta: float) -> void:
	if not is_ambushing():
		return
	_ambush_t += delta
	if _ambush_target and is_instance_valid(_ambush_target):
		var to := _ambush_target.global_position - player.global_position
		to.y = 0.0
		if to.length_squared() > 0.001:
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(1.0, 18.0 * delta))
	if not _ambush_fired and _ambush_t >= ambush_jab_delay:
		# The existing uncharged goad point jab (two hands) on the rise.
		_ambush_fired = true
		player.call("bog_fire_ambush_strike")
	var combat = player.get("combat")
	var busy := combat != null and (bool(combat.get("is_attacking")) or float(combat.get("attack_recovery_left")) > 0.05)
	if _ambush_fired and _ambush_t > 0.3 and not busy:
		_ambush_t = -1.0
		_ambush_target = null
		if combat and combat.has_method("clear_surprise_strike"):
			combat.call("clear_surprise_strike")


# --- Effects -----------------------------------------------------------------

func _ripple(strength: float) -> void:
	if zone == null:
		return
	stats["ripples"] = int(stats["ripples"]) + 1
	zone.call("play_ripple", player.global_position, strength)


func _sound(kind: StringName, level: float) -> void:
	stats["sounds"] = int(stats["sounds"]) + 1
	last_sound = kind
	var at := player.global_position + Vector3(0.0, 0.3, 0.0)
	if zone:
		zone.call("play_bog_sound", kind, at, level)
	else:
		BogSfx.play(player.get_parent(), kind, at, level)


func _burst(noise: float, secs: float) -> void:
	_burst_noise = maxf(_burst_noise if _burst_left > 0.0 else 0.0, noise)
	_burst_left = maxf(_burst_left, secs)


func _collect_wet_meshes() -> void:
	_wet_meshes.clear()
	_wet_copies.clear()
	var visual := player.get("visual") as Node3D
	if visual == null:
		return
	var skin: Color = KerneMeshBuilder.PALETTE_PLAYER["skin"]
	var hair: Color = KerneMeshBuilder.PALETTE_PLAYER["hair"]
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m == null or m.metallic > 0.3:
			continue
		var c := m.albedo_color
		if _same_color(c, skin) or _same_color(c, hair):
			continue
		if not _wet_copies.has(m):
			var wm := m.duplicate() as StandardMaterial3D
			wm.clearcoat_enabled = true
			_wet_copies[m] = wm
		_wet_meshes.append([mi, m])
		(mi as MeshInstance3D).material_override = _wet_copies[m]


func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.02


func _apply_wet_tint() -> void:
	if wet <= 0.0:
		if not _wet_meshes.is_empty():
			for pair in _wet_meshes:
				if is_instance_valid(pair[0]):
					(pair[0] as MeshInstance3D).material_override = pair[1]
			_wet_meshes.clear()
			_wet_copies.clear()
		_wet_applied = -1.0
		return
	if _wet_meshes.is_empty():
		_collect_wet_meshes()
		_wet_applied = -1.0
	if absf(wet - _wet_applied) < 0.004:
		return
	_wet_applied = wet
	var w := wet
	for orig in _wet_copies.keys():
		var o := orig as StandardMaterial3D
		var wm := _wet_copies[orig] as StandardMaterial3D
		var c := o.albedo_color.lerp(WET_MUD, 0.45 * w)
		wm.albedo_color = Color(c.r * (1.0 - 0.3 * w), c.g * (1.0 - 0.3 * w), c.b * (1.0 - 0.3 * w), 1.0)
		wm.roughness = lerpf(o.roughness, 0.38, w)
		wm.metallic_specular = lerpf(0.5, 0.7, w)
		wm.clearcoat = 0.55 * w
		wm.clearcoat_roughness = 0.3


## Mesh tint strength the wet layer currently shows (probe).
func wet_tint_applied() -> float:
	return maxf(0.0, _wet_applied)


# --- Breath HUD ----------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "BreathHUD"
	_hud.layer = 12
	add_child(_hud)
	_hud_root = Control.new()
	_hud_root.name = "Breath"
	_hud_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud_root.offset_left = -170.0
	_hud_root.offset_right = 170.0
	_hud_root.offset_top = 70.0
	_hud_root.offset_bottom = 124.0
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.visible = false
	_hud.add_child(_hud_root)
	_hud_label = Label.new()
	_hud_label.text = "BREATH"
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_label.offset_bottom = 26.0
	_hud_label.add_theme_font_size_override("font_size", 20)
	_hud_label.add_theme_color_override("font_color", Color(0.86, 0.93, 0.95))
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_label.add_theme_constant_override("outline_size", 2)
	_hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_hud_label.add_theme_constant_override("shadow_offset_x", 2)
	_hud_label.add_theme_constant_override("shadow_offset_y", 2)
	_hud_root.add_child(_hud_label)
	_hud_bar = ProgressBar.new()
	_hud_bar.min_value = 0.0
	_hud_bar.max_value = 1.0
	_hud_bar.step = 0.001
	_hud_bar.show_percentage = false
	_hud_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud_bar.offset_top = -22.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.08, 0.75)
	bg.border_color = Color(0.75, 0.85, 0.9, 0.8)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	_hud_fill = StyleBoxFlat.new()
	_hud_fill.bg_color = Color(0.45, 0.78, 0.92)
	_hud_fill.set_corner_radius_all(3)
	_hud_bar.add_theme_stylebox_override("background", bg)
	_hud_bar.add_theme_stylebox_override("fill", _hud_fill)
	_hud_root.add_child(_hud_bar)


func _refresh_hud() -> void:
	if _hud_root == null:
		return
	var show := is_fully_under() and not is_gasping()
	_hud_root.visible = show
	if not show:
		return
	var f := breath_fraction()
	_hud_bar.value = f
	_hud_label.text = "BREATH  %.1fs" % breath_left
	if breath_left < 4.0:
		var pulse := 0.6 + 0.4 * absf(sin(breath_left * 6.0))
		_hud_fill.bg_color = Color(0.92, 0.32, 0.22).lerp(Color(1.0, 0.6, 0.4), pulse * 0.4)
	else:
		_hud_fill.bg_color = Color(0.45, 0.78, 0.92)
