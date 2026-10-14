extends Node3D
class_name OpeningBucketTroughChore
## Self-contained opening-farm chore: pick up greybox bucket → fill at clear spring scoop →
## pour into byre trough. Additive soft progress cue; does not gate cattle soft success.
##
## Interact: E when in range (~2.5 m). States: none → empty → full → done.

enum BucketState { NONE, EMPTY, FULL, DONE }

const INTERACT_RANGE := 2.5
const SPRING_CLEAR := Vector3(-23.5, 0.0, 19.0)
## Murky outflow SE of the clear pool — fill rejected if closer to this than to clear water.
const SPRING_OUTFLOW := Vector3(-20.7, 0.0, 20.5)
const FILL_CLEAR_MAX := 1.85
const BUCKET_SPAWN := Vector3(5.2, 0.0, 2.5)
const TROUGH_POS := Vector3(8.2, 0.0, 0.4)
## Where the emptied bucket is left after the pour: on the yard side of the trough rail, at the
## trough's west end (reachable ground, clear of the hitch post and the pour spot).
const BUCKET_SETDOWN := Vector3(7.0, 0.0, 1.8)
## Period stave bucket: 0.32 m across the base (0.30 rim), 0.36 m tall, ~15 L carried (~17 kg full).
## Carried: bail bar (0.31 up, 0.03 thick) sits in the palms → bucket origin this far below the grip.
const HANDLE_TO_ORIGIN := 0.325
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

const C_WOOD := Color(0.42, 0.30, 0.18)
const C_WOOD_DARK := Color(0.32, 0.22, 0.12)
const C_WATER := Color(0.35, 0.48, 0.52)
const C_WATER_FULL := Color(0.32, 0.55, 0.58)
const C_EMPTY_TINT := Color(0.48, 0.38, 0.26)
const C_BAND := Color(0.28, 0.24, 0.18)

const SEQ_STEP := &"bucket"

@export var director_path: NodePath = ^"../OpeningDriveDirector"

var _state: BucketState = BucketState.NONE
var _player: Node3D = null
var _director: Node = null
var _sequence: Node = null
var _world_bucket: Node3D = null
var _carried: Node3D = null
var _trough: Node3D = null
var _trough_water: MeshInstance3D = null
var _prompt_timer: float = 0.0
var _mats: Dictionary = {}
## Where the bucket stood when picked up (it is lifted from here as the hands take it).
var _lift_from: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("opening_bucket_trough")
	_build_props()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	print(
		"OPENING_BUCKET_TROUGH_READY bucket=%s trough=%s spring=%s"
		% [BUCKET_SPAWN, TROUGH_POS, SPRING_CLEAR]
	)


func _process(delta: float) -> void:
	if _prompt_timer > 0.0:
		_prompt_timer -= delta
	_sync_carried()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries (smoke / stills)

func chore_done() -> bool:
	return _state == BucketState.DONE


func bucket_state() -> String:
	match _state:
		BucketState.NONE:
			return "none"
		BucketState.EMPTY:
			return "empty"
		BucketState.FULL:
			return "full"
		BucketState.DONE:
			return "done"
	return "unknown"


func bucket_spawn_pos() -> Vector3:
	return BUCKET_SPAWN


func trough_pos() -> Vector3:
	return TROUGH_POS


func spring_clear_pos() -> Vector3:
	return SPRING_CLEAR


func interact_prompt() -> String:
	if _state == BucketState.DONE or _player == null or not is_instance_valid(_player):
		return ""
	var p := _player.global_position
	if not _gate_open():
		return _not_yet() if _near_any_spot(p) else ""
	match _state:
		BucketState.NONE:
			if _near(p, BUCKET_SPAWN):
				return "E — pick up bucket"
		BucketState.EMPTY:
			if _at_clear_pool(p):
				return "E — fill bucket at spring"
			if _near_outflow_only(p):
				return "Fill at the clear pool (not the murky outflow)"
		BucketState.FULL:
			if _near(p, TROUGH_POS):
				return "E — pour into trough"
	return ""


func is_active() -> bool:
	return _state != BucketState.DONE


## Smoke / capture: force state without walking.
func debug_set_state(state_name: String) -> void:
	match state_name:
		"none":
			_set_none()
		"empty":
			_pickup()
		"full":
			if _state == BucketState.NONE:
				_pickup()
			_fill()
		"done":
			if _state == BucketState.NONE:
				_pickup()
			if _state == BucketState.EMPTY:
				_fill()
			_pour()
		_:
			push_warning("OpeningBucketTroughChore.debug_set_state unknown: " + state_name)


# ---------------------------------------------------------------- interact

func try_interact() -> bool:
	return _try_interact()


func _try_interact() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	var p := _player.global_position
	if _state != BucketState.DONE and not _gate_open():
		# Out of order: say so, change nothing.
		if _near_any_spot(p):
			_flash(_not_yet(), 2.5)
			return true
		return false
	match _state:
		BucketState.NONE:
			if _near(p, BUCKET_SPAWN):
				_pickup()
				return true
		BucketState.EMPTY:
			if _at_clear_pool(p):
				_fill()
				return true
			if _near_outflow_only(p):
				_flash("Fill at the clear spring pool — not the murky outflow.", 3.0)
				return true
			if _near(p, SPRING_CLEAR, INTERACT_RANGE + 0.8):
				_flash("Step closer to the clear water in the scoop.", 2.5)
				return true
		BucketState.FULL:
			if _near(p, TROUGH_POS):
				_pour()
				return true
		BucketState.DONE:
			pass
	return false


func _pickup() -> void:
	_state = BucketState.EMPTY
	_set_carrying(true)
	if _world_bucket:
		_lift_from = _world_bucket.global_position
		_world_bucket.visible = false
	_ensure_carried(false)
	_flash("Bucket in hand — fill it at the spring scoop.", 3.5)
	print("OPENING_BUCKET_PICKUP")


func _fill() -> void:
	_state = BucketState.FULL
	_ensure_carried(true)
	_flash("Bucket full — pour it into the byre trough.", 3.5)
	print("OPENING_BUCKET_FILLED")


func _pour() -> void:
	_state = BucketState.DONE
	_set_carrying(false)
	if _carried:
		_carried.visible = false
	# The emptied bucket is set down on the ground at the trough's west end.
	if _world_bucket:
		_world_bucket.position = Vector3(BUCKET_SETDOWN.x, Terrain.surface_y(BUCKET_SETDOWN.x, BUCKET_SETDOWN.z) + 0.18, BUCKET_SETDOWN.z)
		_world_bucket.visible = true
	if _trough_water:
		_trough_water.visible = true
	_flash("Trough filled.", 4.0)
	print("OPENING_BUCKET_TROUGH_SOFT_SUCCESS")
	_report_done()


func _set_none() -> void:
	_state = BucketState.NONE
	_set_carrying(false)
	if _world_bucket:
		_world_bucket.position = BUCKET_SPAWN + Vector3(0.0, 0.25, 0.0)
		_world_bucket.visible = true
	if _carried:
		_carried.visible = false
	if _trough_water:
		_trough_water.visible = false


# ---------------------------------------------------------------- geometry

func _build_props() -> void:
	_world_bucket = _make_bucket_mesh("WorldBucket", false)
	_world_bucket.position = BUCKET_SPAWN + Vector3(0.0, 0.25, 0.0)
	add_child(_world_bucket)

	_trough = Node3D.new()
	_trough.name = "ByreTrough"
	_trough.position = TROUGH_POS
	add_child(_trough)
	# Low wood trough — outer shell + hollow.
	_mesh_box(_trough, Vector3(0.0, 0.28, 0.0), Vector3(2.2, 0.55, 0.85), C_WOOD)
	_mesh_box(_trough, Vector3(0.0, 0.42, 0.0), Vector3(1.85, 0.12, 0.55), C_WOOD_DARK)
	_mesh_box(_trough, Vector3(-1.0, 0.35, 0.0), Vector3(0.12, 0.5, 0.78), C_WOOD_DARK)
	_mesh_box(_trough, Vector3(1.0, 0.35, 0.0), Vector3(0.12, 0.5, 0.78), C_WOOD_DARK)
	_mesh_box(_trough, Vector3(0.0, 0.35, -0.36), Vector3(2.05, 0.45, 0.1), C_WOOD_DARK)
	_mesh_box(_trough, Vector3(0.0, 0.35, 0.36), Vector3(2.05, 0.45, 0.1), C_WOOD_DARK)
	_trough_water = _mesh_box(_trough, Vector3(0.0, 0.38, 0.0), Vector3(1.7, 0.08, 0.5), C_WATER)
	_trough_water.visible = false
	_trough_water.name = "TroughWater"

	var label := Label3D.new()
	label.text = "Trough"
	label.font_size = 28
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.85, 0.65)
	label.outline_size = 8
	label.position = Vector3(0.0, 1.35, 0.0)
	_trough.add_child(label)


func _make_bucket_mesh(node_name: String, full: bool) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var body_col := C_WOOD if not full else C_EMPTY_TINT.lerp(C_WATER_FULL, 0.15)
	# Staves taper slightly to the rim (0.30 top, 0.32 base), two hoops.
	_mesh_cyl(root, Vector3(0.0, 0.0, 0.0), 0.15, 0.16, 0.36, body_col)
	_mesh_cyl(root, Vector3(0.0, 0.11, 0.0), 0.158, 0.158, 0.028, C_BAND)
	_mesh_cyl(root, Vector3(0.0, -0.11, 0.0), 0.163, 0.163, 0.028, C_BAND)
	# Bail handle: lugs on two long staves, a bar 0.13 m over the rim.
	_mesh_box(root, Vector3(0.0, 0.31, 0.0), Vector3(0.32, 0.03, 0.03), C_BAND)
	_mesh_box(root, Vector3(-0.145, 0.225, 0.0), Vector3(0.03, 0.17, 0.03), C_BAND)
	_mesh_box(root, Vector3(0.145, 0.225, 0.0), Vector3(0.03, 0.17, 0.03), C_BAND)
	# ~80 % full (inner r ≈ 0.135, 0.33 inner depth ≈ 19 L; water 0.26 deep ≈ 15 L).
	var water := _mesh_cyl(root, Vector3(0.0, 0.08, 0.0), 0.14, 0.14, 0.06, C_WATER_FULL)
	water.name = "Water"
	water.visible = full
	return root


## The bucket in hand is a carried object for the player's movement (slow walk, no sprint).
func _set_carrying(on: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if on and _player.has_method("begin_carry"):
		_player.call("begin_carry", self)
	elif not on and _player.has_method("end_carry"):
		_player.call("end_carry", self)


func _ensure_carried(full: bool) -> void:
	if _carried == null:
		_carried = _make_bucket_mesh("CarriedBucket", full)
		_carried.visible = false
		add_child(_carried)
	var water := _carried.get_node_or_null("Water") as MeshInstance3D
	if water:
		water.visible = full
	# Retint body slightly when full.
	for c in _carried.get_children():
		if c is MeshInstance3D and c.name != "Water":
			var mi := c as MeshInstance3D
			if mi.material_override:
				var m := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
				if full and mi.mesh is CylinderMesh:
					var cm := mi.mesh as CylinderMesh
					if cm.height > 0.2:
						m.albedo_color = C_WOOD.lerp(C_WATER_FULL, 0.12)
						mi.material_override = m
	_carried.visible = true
	_sync_carried()


func _sync_carried() -> void:
	if _carried == null or not _carried.visible:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	_carried.global_rotation = Vector3(0.0, _player.global_rotation.y, 0.0)
	if not _player.has_method("carry_grip_point"):
		_carried.global_position = _player.global_position + _player.global_transform.basis * Vector3(0.42, 1.05, -0.35)
		return
	# Hangs from its bail in both hands (the bar sits in the palms); until the hands have it
	# (goad still going onto his back) it stays where it stood and is lifted as they take it.
	var hang := Vector3(_player.call("carry_grip_point")) - Vector3(0.0, HANDLE_TO_ORIGIN, 0.0)
	var w := float(_player.call("carry_hold_weight"))
	_carried.global_position = _lift_from.lerp(hang, w)


# ---------------------------------------------------------------- helpers

func _near(p: Vector3, target: Vector3, range_m: float = INTERACT_RANGE) -> bool:
	var a := Vector3(p.x, 0.0, p.z)
	var b := Vector3(target.x, 0.0, target.z)
	return a.distance_to(b) <= range_m


func _at_clear_pool(p: Vector3) -> bool:
	## Require clear-pool proximity and reject murky-outflow-only fills.
	if not _near(p, SPRING_CLEAR, FILL_CLEAR_MAX):
		return false
	var d_clear := _xz_dist(p, SPRING_CLEAR)
	var d_out := _xz_dist(p, SPRING_OUTFLOW)
	return d_clear + 0.35 < d_out


func _near_any_spot(p: Vector3) -> bool:
	return _near(p, BUCKET_SPAWN) or _near(p, TROUGH_POS) or _near(p, SPRING_CLEAR) or _near(p, SPRING_OUTFLOW, 1.6)


func _near_outflow_only(p: Vector3) -> bool:
	return _near(p, SPRING_OUTFLOW, 1.6) and not _at_clear_pool(p)


func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


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


# ---------------------------------------------------------------- set sequence gate

func _seq() -> Node:
	if _sequence == null or not is_instance_valid(_sequence):
		_sequence = get_tree().get_first_node_in_group("opening_sequence") if is_inside_tree() else null
	return _sequence


## Open when there is no sequence (other scenes) or this chore's step is the live one.
func _gate_open() -> bool:
	var seq := _seq()
	return seq == null or bool(seq.call("is_step_active", SEQ_STEP))


func _not_yet() -> String:
	var seq := _seq()
	return String(seq.call("not_yet_text")) if seq else ""


func _report_done() -> void:
	var seq := _seq()
	if seq:
		seq.call("complete_step", SEQ_STEP)
