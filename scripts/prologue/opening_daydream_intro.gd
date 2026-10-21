extends Node
class_name OpeningDaydreamIntro
## Opening shot before control (opening cattle drive scene, first load). Cian stands in the
## ráth gateway with the goad slung on his back, looking out over the open fields to the trees
## and daydreaming: a slow, calm over-the-shoulder push while he looks along the tree line, takes
## a slow breath with a small weight shift and tilts his head up to the crowns. Máire calls him from
## the house door (bark over her + the HUD line, as her other lines); he startles out of it, looks
## round and turns to her, the camera eases back to the normal follow cam and control starts on
## the existing step 1 (talk to Máire). No new props, lights, sounds or NPCs.
##
## While it plays: player movement / look / combat / kit keys / interaction are off
## (player.begin_cinematic + every key / mouse event is eaten here, F4 and Esc excepted), and the
## HUD hides the objective + controls lines (OpeningDriveHUD asks is_playing()).
##
## When it plays: mode AUTO plays it only when the opening is the running game scene
## (SceneTree.current_scene: F4 from main, or the scene run on its own). Smokes / captures that
## add the scene under root themselves get the old start untouched (no intro). PLAY forces it,
## SKIP never plays it; RIOCHT_SKIP_INTRO=1 or the user arg --skip-intro also skip it.
## T (restart) never replays it: it keeps the director's reset to the authored start.

signal intro_call(line: String)
signal intro_finished

enum Mode { AUTO, PLAY, SKIP }

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

@export var mode: Mode = Mode.AUTO
@export var family_caller_path: NodePath = ^"../FamilyCaller"

## Daydream spot: on the causeway in the ráth gateway (between the palisade ends, ~18 m from
## the house door), facing ~14° east of south out over the lane, the fields and the tree clumps.
## The facing keeps the carved post by the lane (-0.6, 24) and both gateposts out of the shot for
## the whole push. Máire stands in plain view across the yard when he turns.
const SPOT := Vector3(6.2, 0.0, 17.2)
const SPOT_YAW_DEG := 194.0
const CALL_LINE := "Cian! There you are, with your head in the trees again. The herd's to be home and penned before dark."

## Timeline (s from the first frame of the shot).
const T_CALL := 8.6               ## Máire's call
const REACT := 0.22               ## startle reaction delay after the call starts
const T_TURN := T_CALL + 0.6      ## body starts turning to her
const TURN_SECS := 1.6
const T_CAM := T_CALL + 0.7       ## camera starts easing to the follow cam
const CAM_SECS := 2.1
const T_CONTROL := T_CAM + CAM_SECS  ## 11.4 s: control starts
const MAIRE_TURN_SECS := 0.6      ## she turns to face him as she calls

const SHOT_FOV := 50.0
## Daydream gaze keys: [t, head yaw deg (+ = his left), head pitch deg (+ = up)].
const GAZE := [
	[0.0, -4.0, 3.0],
	[1.3, -4.0, 3.5],
	[3.3, 24.0, 5.0],    # slow look left along the tree line
	[4.5, 24.0, 5.5],
	[6.2, 14.0, 18.0],   # head tilts up toward the crowns / sky
	[7.9, 12.0, 20.0],
	[8.6, 12.0, 18.5],
]

var _playing: bool = false
var _done: bool = false
var _called: bool = false
var _t: float = 0.0
var _player: CharacterBody3D = null
var _follow_cam: Camera3D = null
var _cam: Camera3D = null
var _maire: Node3D = null
var _spot: Vector3 = Vector3.ZERO
var _yaw0: float = 0.0
var _yaw_turn: float = 0.0
var _maire_yaw0: float = 0.0
var _maire_yaw1: float = 0.0
var _head := Vector2.ZERO        ## current head (yaw, pitch) deg relative to the body
var _shift_w: float = 0.0        ## weight-shift weight (0..1)
var _call_yaw_rel: float = 0.0


func _ready() -> void:
	add_to_group("opening_intro")
	call_deferred("_begin")


func is_playing() -> bool:
	return _playing


func is_done() -> bool:
	return _done


func elapsed() -> float:
	return _t


func call_line() -> String:
	return CALL_LINE


func has_called() -> bool:
	return _called


func intro_camera() -> Camera3D:
	return _cam


func _skip_reason() -> String:
	if mode == Mode.SKIP:
		return "mode"
	if OS.get_environment("RIOCHT_SKIP_INTRO") == "1" or OS.get_cmdline_user_args().has("--skip-intro"):
		return "flag"
	if mode == Mode.AUTO:
		var root := owner if owner else get_parent()
		if get_tree().current_scene != root:
			return "not_game_scene"
	return ""


func _begin() -> void:
	var why := _skip_reason()
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if why != "" or _player == null or not _player.has_method("begin_cinematic"):
		_done = true
		print("OPENING_INTRO_SKIPPED reason=%s" % (why if why != "" else "no_player"))
		return
	_maire = get_node_or_null(family_caller_path) as Node3D
	_follow_cam = _player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	_spot = Terrain.surface_point(SPOT, 0.05)
	_yaw0 = deg_to_rad(SPOT_YAW_DEG)
	_player.global_position = _spot
	_player.rotation = Vector3(0.0, _yaw0, 0.0)
	_player.velocity = Vector3.ZERO
	var pivot := _player.get_node_or_null("CameraPivot") as Node3D
	if pivot:
		pivot.rotation.x = 0.0
	_player.call("snap_goad_stowed")  # the goad rides on his back; hands hang free
	_player.call("begin_cinematic")
	if _maire:
		_maire.set("intro_hold", true)
		_maire_yaw0 = _maire.rotation.y
		var to_cian := _spot - _maire.global_position
		_maire_yaw1 = atan2(to_cian.x, to_cian.z)  # her figure faces +Z
	var to_maire := (_maire.global_position if _maire else Vector3(-5.2, 0.0, 3.2)) - _spot
	_yaw_turn = atan2(-to_maire.x, -to_maire.z)  # Cian's rig faces −Z
	_cam = Camera3D.new()
	_cam.name = "IntroCamera"
	_cam.fov = SHOT_FOV
	add_child(_cam)
	_cam.global_transform = _shot_xf(0.0)
	_cam.current = true
	_head = Vector2(GAZE[0][1], GAZE[0][2])
	_playing = true
	_t = 0.0
	print("OPENING_INTRO_START spot=%s yaw=%.1f call_at=%.2f control_at=%.2f line=%s" % [
		_spot.snapped(Vector3.ONE * 0.01), SPOT_YAW_DEG, T_CALL, T_CONTROL, CALL_LINE])


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventKey:
		var k := (event as InputEventKey).keycode
		if k == KEY_F4 or k == KEY_ESCAPE:
			return  # scene toggle / mouse release stay live
	if (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventMouseMotion
		or event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	):
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _playing:
		return
	if _player == null or not is_instance_valid(_player):
		_finish()
		return
	_t += delta
	if not _called and _t >= T_CALL:
		_called = true
		if _maire and _maire.has_method("call_out"):
			_maire.call("call_out", CALL_LINE)
		intro_call.emit(CALL_LINE)
	_tick_maire()
	_tick_body(delta)
	_tick_camera()
	if _t >= T_CONTROL:
		_finish()


func _tick_maire() -> void:
	if _maire == null:
		return
	# She half-turns from the doorway toward him as she calls (just before the words).
	var u := _smooth((_t - (T_CALL - 0.35)) / MAIRE_TURN_SECS)
	_maire.rotation.y = lerp_angle(_maire_yaw0, _maire_yaw1, u)


func _tick_body(delta: float) -> void:
	# Body yaw: the daydream facing, then the turn to her.
	var turn_u := _smooth((_t - T_TURN) / TURN_SECS)
	_player.rotation.y = lerp_angle(_yaw0, _yaw_turn, turn_u)
	var react := _t - (T_CALL + REACT)
	var head_target: Vector2
	if react < 0.0:
		head_target = _gaze(_t)
		_head = head_target
	else:
		# Startled: the head comes down off the canopy and snaps round toward her voice, then
		# leads the body round and unwinds as the body catches up.
		var rel := rad_to_deg(wrapf(_yaw_turn - _player.rotation.y, -PI, PI))
		head_target = Vector2(clampf(rel, -72.0, 72.0), -2.0)
		var rate := 11.0 if react < 0.5 else 6.0
		_head = _head.lerp(head_target, 1.0 - exp(-rate * delta))
	# Slow breath (in ~1.6 s, out ~2 s) while he looks along the trees.
	var breath := _smooth((_t - 3.4) / 1.6) - _smooth((_t - 5.0) / 2.0)
	# Weight eases onto the left leg, then squares up again when she calls.
	var shift_target := _smooth((_t - 3.8) / 1.8)
	if react >= 0.0:
		shift_target = 0.0
	_shift_w = move_toward(_shift_w, shift_target, delta * (1.0 / 0.45 if react >= 0.0 else 1.0))
	# Startle: a quick lift of the chest and head (in 0.12 s, gone in ~0.5 s).
	var startle := 0.0
	if react >= 0.0:
		startle = clampf(react / 0.12, 0.0, 1.0) * exp(-maxf(react - 0.12, 0.0) / 0.22)
	var torso := Vector3(
		deg_to_rad(1.8 * breath + 3.0 * startle),
		deg_to_rad(_head.x * 0.22),
		deg_to_rad(1.6 * _shift_w))
	var head := Vector3(
		deg_to_rad(_head.y - 1.8 * breath * 0.5 - 4.0 * startle),
		deg_to_rad(_head.x * 0.78),
		0.0)
	var hips := Vector3(0.0, 0.0, deg_to_rad(-2.4 * _shift_w))
	var thigh := Vector3(0.0, 0.0, deg_to_rad(2.4 * _shift_w))
	_player.call("set_cinematic_pose", {
		"root_pos": Vector3(-0.022 * _shift_w, 0.008 * breath + 0.01 * startle, 0.0),
		"hips": hips,
		"left_thigh": thigh,
		"right_thigh": thigh,
		"torso": torso,
		"head": head,
	})


func _gaze(t: float) -> Vector2:
	for i in GAZE.size() - 1:
		var a: Array = GAZE[i]
		var b: Array = GAZE[i + 1]
		if t <= float(b[0]):
			var u := _smooth((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
			return Vector2(lerpf(a[1], b[1], u), lerpf(a[2], b[2], u))
	var last: Array = GAZE[GAZE.size() - 1]
	return Vector2(last[1], last[2])


## The set shot: behind his right shoulder, a slow push in toward the tree line.
func _shot_xf(t: float) -> Transform3D:
	var fwd := Vector3(-sin(_yaw0), 0.0, -cos(_yaw0))
	var right := Vector3(cos(_yaw0), 0.0, -sin(_yaw0))
	var u := _smooth(t / (T_CONTROL + 1.0))
	var pos := _spot + right * lerpf(1.5, 1.15, u) - fwd * lerpf(3.6, 2.7, u) + Vector3.UP * lerpf(1.95, 1.85, u)
	var look := _spot + fwd * 14.0 - right * 1.2 + Vector3.UP * lerpf(2.5, 2.9, u)
	return Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)


func _tick_camera() -> void:
	if _cam == null:
		return
	var shot := _shot_xf(_t)
	var w := _smooth((_t - T_CAM) / CAM_SECS)
	if w <= 0.0 or _follow_cam == null:
		_cam.global_transform = shot
		_cam.fov = SHOT_FOV
		return
	# Ease round to the follow cam, orbiting about him (never through him or the goad).
	var center := _player.global_position + Vector3.UP * 1.4
	_cam.global_transform = _orbit_blend(shot, _follow_cam.global_transform, w, center)
	_cam.fov = lerpf(SHOT_FOV, _follow_cam.fov, w)


func _orbit_blend(a: Transform3D, b: Transform3D, w: float, center: Vector3) -> Transform3D:
	var ra := a.origin - center
	var rb := b.origin - center
	var ang := lerp_angle(atan2(ra.x, ra.z), atan2(rb.x, rb.z), w)
	var rad := lerpf(Vector2(ra.x, ra.z).length(), Vector2(rb.x, rb.z).length(), w)
	var pos := center + Vector3(sin(ang) * rad, lerpf(ra.y, rb.y, w), cos(ang) * rad)
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), w)
	return Transform3D(Basis(q), pos)


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	_done = true
	if _player and is_instance_valid(_player):
		_player.rotation.y = _yaw_turn
		_player.call("set_cinematic_pose", {})
		_player.call("end_cinematic")
	if _follow_cam:
		_follow_cam.current = true
	if _cam:
		_cam.queue_free()
		_cam = null
	if _maire:
		_maire.set("intro_hold", false)
	print("OPENING_INTRO_DONE t=%.2f control=true" % _t)
	intro_finished.emit()


static func _smooth(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
