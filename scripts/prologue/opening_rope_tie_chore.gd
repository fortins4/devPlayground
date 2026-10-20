extends Node3D
class_name OpeningRopeTieChore
## Opening-farm chore (set-sequence step "milk", after the herd is penned and before the meal):
## Cian takes the red milk cow out of the night pen and ties her to the post by the house, so she
## is to hand for the morning milking. No knife anywhere in the opening (canon): hands and rope.
##
## How she gets from the pen to the post (the realistic way a herdsman does it):
##   1. E at the latched pen gate: he lifts the latch and swings the west leaf back by hand.
##      The milk cow — the herd's quiet one, used to being handled — comes to the gateway, he
##      slips the rope loop over her head and brings her out, then shuts and latches the gate
##      behind her (the other five stay penned).
##   2. He leads her on the rope (goad on his back, rope in the right hand, a cow's pace, no
##      sprint). She walks his own track behind him, so she goes round the pen corner, not
##      through it.
##   3. E at the post: she's brought up head-to-post and he ties the rope to the post with both
##      hands (knot worked, then drawn tight). Once tied a rope runs from her neck to the post.
## States: penned → lead_out → leading → tying → tied.

enum TieState { PENNED, LEAD_OUT, LEADING, TYING, TIED }

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

const INTERACT_RANGE := 2.5
## Tie post: in the yard by the house, clear of Máire's door, the meal stool and the drove's way.
const POST_POS := Vector3(-1.2, 0.0, 5.6)
const POST_RADIUS := 0.1
## Knot height on the post: a little under his elbows, in easy reach.
const KNOT_Y := 1.05
## Tied cow: head to the post, body running SSE from it.
const TIE_DIR := Vector3(0.45, 0.0, 0.89)
const TIE_DIST := 1.95
## Cian stands to the post's west side, square to her line, facing the post.
const STAND_DIR := Vector3(-0.89, 0.0, 0.45)
const STAND_DIST := 0.42
## Hands this far out from the post's surface (forearm ends clear the timber).
const HAND_OUT := 0.085
const HAND_HALF := 0.055
const TIE_SECS := 2.6
## Gate work: where he stands (outside, east of the west leaf's swing) and the beats.
const GATE_STAND := Vector3(6.75, 0.0, 10.3)
const UNLATCH_SECS := 0.5
const OPEN_SECS := 1.0
const SHUT_SECS := 1.0
const RELATCH_SECS := 0.35
## Her way out: inside the gateway (west half), out through it, then a step on to stand by him.
const OUT_PATH: Array[Vector3] = [Vector3(5.3, 0.0, 8.6), Vector3(5.3, 0.0, 11.0), Vector3(6.2, 0.0, 12.6)]
## Leading: she follows his track this far behind him.
const FOLLOW_GAP := 2.0
const TRAIL_STEP := 0.25
const TIE_REACH := 4.5

const C_POST := Color(0.38, 0.28, 0.16)
const C_POST_DARK := Color(0.28, 0.20, 0.12)
const C_ROPE := Color(0.55, 0.48, 0.32)

const SEQ_STEP := &"milk"

@export var director_path: NodePath = ^"../OpeningDriveDirector"
@export var gate_path: NodePath = ^"../OpeningPenGateChore"
## The milk cow: Cow1 is a red, short-horned cow of the six.
@export var milk_cow_path: NodePath = ^"../Herd/Cow1"

var _state: TieState = TieState.PENNED
var _player: Node3D = null
var _director: Node = null
var _gate: Node = null
var _cow: CharacterBody3D = null
var _sequence: Node = null
var _post_root: Node3D = null
var _rope: Node3D = null
var _loop: MeshInstance3D = null
var _prompt_timer: float = 0.0
var _mats: Dictionary = {}
var _work_t: float = 0.0
var _phase: int = 0          # lead-out beat: 0 unlatch, 1 open, 2 she comes out, 3 shut, 4 relatch
var _phase_t: float = 0.0
var _path_i: int = 0
var _trail: Array[Vector3] = []
var _roped: bool = false
var _rope_key: String = ""


func _ready() -> void:
	add_to_group("opening_rope_tie")
	_build_props()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	_gate = get_node_or_null(gate_path)
	_cow = get_node_or_null(milk_cow_path) as CharacterBody3D
	print("OPENING_MILK_TIE_READY post=%s cow=%s" % [POST_POS, _cow.name if _cow else "none"])


func _process(delta: float) -> void:
	if _prompt_timer > 0.0:
		_prompt_timer -= delta
	match _state:
		TieState.LEAD_OUT:
			_tick_lead_out(delta)
		TieState.LEADING:
			_tick_leading()
		TieState.TYING:
			_hold_cow_at(_tie_pos(), _tie_yaw(), delta)
			if _work_t > 0.0 or (_cow_at(_tie_pos()) and _cow_turned() and _player_ready()):
				if _work_t == 0.0:
					print("OPENING_MILK_TIE_KNOT")
				_work_t += delta
				if _work_t >= TIE_SECS:
					_finish_tie(true)
		TieState.TIED:
			_hold_cow_at(_tie_pos(), _tie_yaw(), delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries (HUD / smoke / stills)

func chore_done() -> bool:
	return _state == TieState.TIED


func tie_state() -> String:
	return ["penned", "lead_out", "leading", "tying", "tied"][int(_state)]


func is_tied() -> bool:
	return _state == TieState.TIED


func post_pos() -> Vector3:
	return POST_POS


func gate_stand_point() -> Vector3:
	return GATE_STAND


func milk_cow() -> Node3D:
	return _cow


func animal_pos() -> Vector3:
	return _cow.global_position if _cow else _tie_pos()


## World ends of the visible rope: [post knot or Cian's hand, her neck].
func rope_ends() -> Array:
	if _state == TieState.TIED or (_state == TieState.TYING and _work_t > 0.0):
		return [_knot_far(), _neck_point()]
	return [_hand_point(), _neck_point()]


func rope_visible() -> bool:
	return _rope != null and _rope.visible


func interact_prompt() -> String:
	if _player == null or not is_instance_valid(_player) or not _gate_open():
		return ""
	var p := _player.global_position
	match _state:
		TieState.PENNED:
			if _near(p, GATE_STAND, 2.6) and p.z > 10.15:
				return "E — open the gate and rope the milk cow"
		TieState.LEADING:
			if _near(p, POST_POS):
				if not _near(animal_pos(), POST_POS, TIE_REACH):
					return "Bring her up to the post"
				return "E — tie the milk cow to the post"
	return ""


func is_active() -> bool:
	return _gate_open() and _state != TieState.TIED


## Objective line for the sequence HUD while the step is live.
func objective_text() -> String:
	match _state:
		TieState.PENNED:
			return "Bring the milk cow out of the pen: E at the pen gate to rope her and lead her out."
		TieState.LEAD_OUT:
			return "Bring the milk cow out through the gate, then shut it behind her."
		TieState.LEADING:
			return "Lead the milk cow to the post by the house — E at the post to tie her."
		TieState.TYING:
			return "Tie the milk cow to the post."
	return ""


## Smoke / capture: force a state without walking. "penned" / "leading" (out at the gate, rope in
## hand) / "tied" (at the post).
func force_state(state_name: String) -> void:
	_release_player()
	if _gate and _gate.has_method("set_lead_pose"):
		_gate.call("set_lead_pose", 0.0, 0.0)
	if _cow and not bool(_cow.get("delivered")) and state_name != "penned":
		_cow.call("mark_delivered")
	match state_name:
		"penned":
			_state = TieState.PENNED
			_set_roped(false)
		"leading":
			_place_cow(OUT_PATH[-1], 0.0)
			_set_roped(true)
			_trail.clear()
			_trail.append(OUT_PATH[-1])
			_state = TieState.LEADING
			if _player and _player.has_method("begin_lead"):
				_player.call("begin_lead", self)
		"tied":
			_place_cow(_tie_pos(), _tie_yaw())
			_set_roped(true)
			_state = TieState.TIED
		_:
			push_warning("OpeningRopeTieChore.force_state unknown: " + state_name)
			return
	_rope.visible = _roped


func debug_set_state(state_name: String) -> void:
	force_state(state_name)


# ---------------------------------------------------------------- interact

func try_interact() -> bool:
	return _try_interact()


func _try_interact() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or _cow == null or not _gate_open():
		return false
	var p := _player.global_position
	match _state:
		TieState.PENNED:
			if not (_near(p, GATE_STAND, 2.6) and p.z > 10.15):
				return false
			if _gate == null or not bool(_gate.call("pen_latched")) or not bool(_cow.get("delivered")):
				return false
			_state = TieState.LEAD_OUT
			_phase = 0
			_phase_t = 0.0
			_path_i = 0
			_player.call("begin_hand_work", self, GATE_STAND, _yaw_to(GATE_STAND, _gate.call("latch_point")))
			print("OPENING_MILK_LEAD_OUT_BEGIN")
			return true
		TieState.LEADING:
			if not _near(p, POST_POS):
				return false
			if not _near(animal_pos(), POST_POS, TIE_REACH):
				_flash("Bring her up to the post first.", 2.0)
				return true
			_state = TieState.TYING
			_work_t = 0.0
			_player.call("end_lead", self)
			var stand := POST_POS + _stand_dir() * STAND_DIST
			_player.call("begin_hand_work", self, stand, _yaw_to(stand, POST_POS))
			print("OPENING_MILK_TIE_BEGIN")
			return true
	return false


# ---------------------------------------------------------------- lead-out at the gate

func _tick_lead_out(delta: float) -> void:
	if not _player_ready() and _phase == 0 and _phase_t == 0.0:
		return  # still stepping to the gate / stowing the goad
	_phase_t += delta
	match _phase:
		0:  # lift the latch
			_gate.call("set_lead_pose", clampf(_phase_t / UNLATCH_SECS, 0.0, 1.0), 0.0)
			if _phase_t >= UNLATCH_SECS:
				_next_phase()
		1:  # swing the west leaf back
			_gate.call("set_lead_pose", 1.0, clampf(_phase_t / OPEN_SECS, 0.0, 1.0))
			if _phase_t >= OPEN_SECS:
				_next_phase()
		2:  # she comes to the gateway, he ropes her, she steps out beside him
			var tgt := OUT_PATH[_path_i]
			if _path_i >= 1 and not _roped:
				_set_roped(true)
				print("OPENING_MILK_ROPED")
			if _cow_at(tgt, 0.4):
				_path_i += 1
				if _path_i >= OUT_PATH.size():
					_hold_cow_at(OUT_PATH[-1], _cow.rotation.y, delta)
					_next_phase()
					return
			_walk_cow_to(OUT_PATH[_path_i])
		3:  # shut the leaf behind her
			_hold_cow_at(OUT_PATH[-1], _cow.rotation.y, delta)
			_gate.call("set_lead_pose", 1.0, 1.0 - clampf(_phase_t / SHUT_SECS, 0.0, 1.0))
			if _phase_t >= SHUT_SECS:
				_next_phase()
		4:  # drop the latch
			_hold_cow_at(OUT_PATH[-1], _cow.rotation.y, delta)
			_gate.call("set_lead_pose", 1.0 - clampf(_phase_t / RELATCH_SECS, 0.0, 1.0), 0.0)
			if _phase_t >= RELATCH_SECS:
				_gate.call("set_lead_pose", 0.0, 0.0)
				_trail.clear()
				_trail.append(OUT_PATH[-1])
				_state = TieState.LEADING
				_player.call("end_hand_work", self)
				_player.call("begin_lead", self)
				print("OPENING_MILK_LEADING")


func _next_phase() -> void:
	_phase += 1
	_phase_t = 0.0


# ---------------------------------------------------------------- leading

func _tick_leading() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pp := _player.global_position
	pp.y = 0.0
	if _trail.is_empty() or _flat(_trail[-1]).distance_to(pp) >= TRAIL_STEP:
		_trail.append(pp)
	# Drop track points she has reached.
	while _trail.size() > 1 and _flat(_cow.global_position).distance_to(_flat(_trail[0])) < 0.45:
		_trail.remove_at(0)
	# Walk on only while she's more than FOLLOW_GAP of track behind him.
	var behind := _flat(_cow.global_position).distance_to(_flat(_trail[0]))
	for i in range(1, _trail.size()):
		behind += _flat(_trail[i - 1]).distance_to(_flat(_trail[i]))
	behind += _flat(_trail[-1]).distance_to(pp)
	if behind > FOLLOW_GAP and _trail.size() > 0:
		_walk_cow_to(_trail[0])
	else:
		_cow.call("set_pen_slot", _cow.global_position)


# ---------------------------------------------------------------- tie

func _finish_tie(announce: bool) -> void:
	_state = TieState.TIED
	_rope.visible = true
	_release_player()
	if announce:
		_flash("She's tied fast at the post, handy for the morning milking.", 3.0)
		print("OPENING_MILK_TIE_SOFT_SUCCESS")
	_report_done()


func _release_player() -> void:
	if _player and is_instance_valid(_player):
		if _player.has_method("end_hand_work"):
			_player.call("end_hand_work", self)
		if _player.has_method("end_lead"):
			_player.call("end_lead", self)


func _player_ready() -> bool:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("hand_work_ready"):
		return true
	return bool(_player.call("hand_work_ready"))


## Player rig callback: world targets for [left hand, right hand] this frame.
func hand_work_grips() -> Array:
	if _state == TieState.LEAD_OUT:
		return _gate_grips()
	var c := _knot_near()
	var out := _stand_dir()
	var side := Vector3.UP.cross(-out).normalized()  # Cian's left as he faces the post
	var l := c + side * HAND_HALF
	var r := c - side * HAND_HALF
	var t := _work_t
	if t <= 0.0:
		# Bringing her up: rope in both hands just in front of the post.
		return [l + out * 0.08 - Vector3.UP * 0.1, r + out * 0.08 - Vector3.UP * 0.1]
	# Knot work: the left hand holds the standing part at the post while the right passes the end
	# round it in small loops; hands swap halfway; the last beat draws the knot tight.
	var u := clampf(t / TIE_SECS, 0.0, 1.0)
	var loop_amt := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.78, 0.86, u))
	var ph := t * TAU * 1.6
	var loop_r := (side * cos(ph) * 0.035 + Vector3.UP * sin(ph) * 0.04 + out * (0.02 + 0.015 * sin(ph))) * loop_amt
	var loop_l := (side * -cos(ph) * 0.035 + Vector3.UP * sin(ph) * 0.04 + out * (0.02 + 0.015 * sin(ph))) * loop_amt
	if u < 0.45:
		r += loop_r
		l += out * 0.01 * sin(ph * 0.5)
	else:
		l += loop_l
	var pull := smoothstep(0.84, 1.0, u)
	l += (side * 0.07 + out * 0.05 - Vector3.UP * 0.02) * pull
	r += (-side * 0.07 + out * 0.05 - Vector3.UP * 0.02) * pull
	return [l, r]


## Gate beats: both hands lift the latch; the right starts the leaf's swing; hands hold the rope
## low in front while she comes out; the right hand meets the leaf as it closes and drops the latch.
func _gate_grips() -> Array:
	var p := _player.global_position
	var f := -_player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var left := Vector3.UP.cross(f).normalized()
	var rest_l := p + f * 0.26 + left * 0.08 + Vector3.UP * 0.95
	var rest_r := p + f * 0.26 - left * 0.08 + Vector3.UP * 0.95
	var latch: Vector3 = _gate.call("latch_point")
	var tip: Vector3 = _gate.call("west_tip_point")
	var reach := p + Vector3.UP * 1.0
	var tip_ok := tip.distance_to(reach) < 0.55
	match _phase:
		0:
			return [latch + left * 0.05, latch - left * 0.05 + Vector3.UP * 0.02]
		1:
			var k := clampf(_phase_t / 0.3, 0.0, 1.0)
			var r1 := tip + Vector3.UP * 0.05 if tip_ok else rest_r
			return [latch.lerp(rest_l, k), r1 if k < 1.0 else rest_r]
		3:
			var r3 := tip + Vector3.UP * 0.05 if tip_ok else rest_r
			return [rest_l, r3]
		4:
			return [rest_l, latch - left * 0.05]
	return [rest_l, rest_r]


# ---------------------------------------------------------------- cow control (her own walk)

func _walk_cow_to(tgt: Vector3) -> void:
	_cow.call("set_pen_slot", Vector3(tgt.x, _cow.global_position.y, tgt.z))


func _cow_at(tgt: Vector3, r: float = 0.35) -> bool:
	return _flat(_cow.global_position).distance_to(_flat(tgt)) <= r


## Holds her on `spot` (walks back if nudged) and eases her round to `yaw` (−Z is her head).
func _hold_cow_at(spot: Vector3, yaw: float, delta: float) -> void:
	if _cow == null:
		return
	if _cow_at(spot, 0.3):
		_cow.call("set_pen_slot", _cow.global_position)
		_cow.rotation.y = rotate_toward(_cow.rotation.y, yaw, 1.3 * delta)
	else:
		_walk_cow_to(spot)


func _cow_turned() -> bool:
	return absf(angle_difference(_cow.rotation.y, _tie_yaw())) < 0.06


func _place_cow(pos: Vector3, yaw: float) -> void:
	_cow.global_position = Terrain.surface_point(pos, 0.1)
	_cow.rotation.y = yaw
	_cow.set("velocity", Vector3.ZERO)
	_cow.call("set_pen_slot", _cow.global_position)


func _set_roped(on: bool) -> void:
	_roped = on
	if _loop == null and _cow and on:
		_loop = MeshInstance3D.new()
		_loop.name = "NeckRope"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.18
		tm.outer_radius = 0.21
		tm.rings = 18
		tm.ring_segments = 6
		_loop.mesh = tm
		_loop.material_override = _mat(C_ROPE)
		# Round her neck in front of the withers, tilted with the neck (cow −Z is her head end).
		_loop.transform = Transform3D(Basis(Vector3.RIGHT, -0.55) * Basis.from_scale(Vector3(0.95, 1.0, 1.15)), Vector3(0.0, 0.93, -0.86))
		_cow.add_child(_loop)
	if _loop:
		_loop.visible = on
	if _rope:
		_rope.visible = on


# ---------------------------------------------------------------- geometry helpers

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


func _tie_pos() -> Vector3:
	return POST_POS + TIE_DIR.normalized() * TIE_DIST


## Her yaw with her head (−Z) to the post.
func _tie_yaw() -> float:
	var to_post := -TIE_DIR.normalized()
	return atan2(-to_post.x, -to_post.z)


func _stand_dir() -> Vector3:
	return STAND_DIR.normalized()


func _post_base() -> Vector3:
	return Vector3(POST_POS.x, Terrain.surface_y(POST_POS.x, POST_POS.z), POST_POS.z)


func _knot_near() -> Vector3:
	return _post_base() + Vector3(0.0, KNOT_Y, 0.0) + _stand_dir() * (POST_RADIUS + HAND_OUT)


func _knot_far() -> Vector3:
	return _post_base() + Vector3(0.0, KNOT_Y, 0.0) + TIE_DIR.normalized() * (POST_RADIUS + 0.02)


## Where the lead leaves her neck loop (under the throat, cow-local).
func _neck_point() -> Vector3:
	if _cow == null:
		return _tie_pos() + Vector3(0, 0.8, 0)
	return _cow.global_transform * Vector3(0.0, 0.78, -0.97)


func _hand_point() -> Vector3:
	if _player and is_instance_valid(_player) and _player.has_method("lead_hand_point"):
		return _player.call("lead_hand_point")
	return _neck_point()


# ---------------------------------------------------------------- props

func _build_props() -> void:
	_post_root = Node3D.new()
	_post_root.name = "TiePost"
	_post_root.position = _post_base()
	add_child(_post_root)
	# A plain stout timber post, set in the yard (no cross-rail: nothing for his arms to meet).
	_mesh_cyl(_post_root, Vector3(0.0, 0.7, 0.0), 0.09, POST_RADIUS + 0.01, 1.4, C_POST)
	_mesh_box(_post_root, Vector3(0.0, 0.08, 0.0), Vector3(0.28, 0.12, 0.28), C_POST_DARK)
	var body := StaticBody3D.new()
	body.name = "PostSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = POST_RADIUS + 0.01
	shape.height = 1.4
	cs.shape = shape
	cs.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(cs)
	_post_root.add_child(body)

	var label := Label3D.new()
	label.text = "Tie post"
	label.font_size = 26
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.85, 0.65)
	label.outline_size = 8
	label.position = Vector3(0.0, 1.85, 0.0)
	_post_root.add_child(label)

	_rope = Node3D.new()
	_rope.name = "TieRope"
	_rope.top_level = true
	add_child(_rope)
	_rope.visible = false


func _physics_process(_delta: float) -> void:
	if _rope == null or not _rope.visible:
		_rope_key = ""
		return
	var ends := rope_ends()
	var key := "%s|%s|%d" % [(ends[0] as Vector3).snapped(Vector3.ONE * 0.003), (ends[1] as Vector3).snapped(Vector3.ONE * 0.003), int(_state)]
	if key != _rope_key:
		_rope_key = key
		_rebuild_rope(ends[0], ends[1])


## Two turns round the post and a knot lump with a short tail once tied; then a sagging run
## (4 segments) from the post — or from his hand while leading — to her neck loop.
func _rebuild_rope(a: Vector3, b: Vector3) -> void:
	for c in _rope.get_children():
		_rope.remove_child(c)
		c.free()
	var at_post := _state == TieState.TIED or (_state == TieState.TYING and _work_t > 0.0)
	if at_post:
		var ring := TorusMesh.new()
		ring.inner_radius = POST_RADIUS + 0.005
		ring.outer_radius = POST_RADIUS + 0.04
		ring.rings = 16
		ring.ring_segments = 6
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = ring
			mi.material_override = _mat(C_ROPE)
			mi.position = _post_base() + Vector3(0.0, KNOT_Y + 0.035 * (k - 0.5), 0.0)
			_rope.add_child(mi)
		var knot := _post_base() + Vector3(0.0, KNOT_Y, 0.0) + _stand_dir() * (POST_RADIUS + 0.035)
		_mesh_sphere(_rope, knot, 0.035, C_ROPE.darkened(0.15))
		if _state == TieState.TIED:
			_rope_seg(knot, knot + Vector3(0.0, -0.16, 0.0) + _stand_dir() * 0.03, 0.016)
	var span := a.distance_to(b)
	var sag := clampf(0.5 - span * 0.12, 0.08, 0.35)
	var prev := a
	for i in range(1, 6):
		var f := float(i) / 5.0
		var p := a.lerp(b, f) + Vector3(0.0, -sag * sin(f * PI), 0.0)
		_rope_seg(prev, p, 0.02)
		prev = p


func _rope_seg(a: Vector3, b: Vector3, r: float) -> void:
	var length := a.distance_to(b)
	if length < 0.005:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(C_ROPE)
	var dir := (b - a) / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up) * Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))
	mi.transform = Transform3D(basis, (a + b) * 0.5)
	_rope.add_child(mi)


# ---------------------------------------------------------------- helpers

func _near(p: Vector3, target: Vector3, range_m: float = INTERACT_RANGE) -> bool:
	return _flat(p).distance_to(_flat(target)) <= range_m


func _flash(text: String, secs: float = 3.0) -> void:
	_prompt_timer = secs
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)
	elif _director and _director.has_method("_flash"):
		_director.call("_flash", text, secs)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	_mats[key] = m
	return m


func _mesh_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mesh_cyl(parent: Node, pos: Vector3, top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mesh_sphere(parent: Node, pos: Vector3, r: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- set sequence gate

func _seq() -> Node:
	if _sequence == null or not is_instance_valid(_sequence):
		_sequence = get_tree().get_first_node_in_group("opening_sequence") if is_inside_tree() else null
	return _sequence


## Open when there is no sequence (other scenes) or this chore's step is the live one.
func _gate_open() -> bool:
	var seq := _seq()
	return seq == null or bool(seq.call("is_step_active", SEQ_STEP))


func _report_done() -> void:
	var seq := _seq()
	if seq:
		seq.call("complete_step", SEQ_STEP)
