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
	if _world_bucket:
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
	if _carried:
		_carried.visible = false
	if _trough_water:
		_trough_water.visible = true
	_flash("Trough filled.", 4.0)
	print("OPENING_BUCKET_TROUGH_SOFT_SUCCESS")
	_report_done()


func _set_none() -> void:
	_state = BucketState.NONE
	if _world_bucket:
		_world_bucket.visible = true
	if _carried:
		_carried.visible = false
	if _trough_water:
		_trough_water.visible = false


# ---------------------------------------------------------------- geometry

func _build_props() -> void:
	_world_bucket = _make_bucket_mesh("WorldBucket", false)
	_world_bucket.position = BUCKET_SPAWN + Vector3(0.0, 0.28, 0.0)
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
	_mesh_cyl(root, Vector3(0.0, 0.0, 0.0), 0.22, 0.26, 0.42, body_col)
	_mesh_cyl(root, Vector3(0.0, 0.18, 0.0), 0.24, 0.24, 0.04, C_BAND)
	_mesh_cyl(root, Vector3(0.0, -0.12, 0.0), 0.24, 0.24, 0.04, C_BAND)
	# Bail handle.
	_mesh_box(root, Vector3(0.0, 0.32, 0.0), Vector3(0.38, 0.04, 0.04), C_BAND)
	_mesh_box(root, Vector3(-0.18, 0.22, 0.0), Vector3(0.04, 0.22, 0.04), C_BAND)
	_mesh_box(root, Vector3(0.18, 0.22, 0.0), Vector3(0.04, 0.22, 0.04), C_BAND)
	var water := _mesh_cyl(root, Vector3(0.0, 0.08, 0.0), 0.18, 0.18, 0.08, C_WATER_FULL)
	water.name = "Water"
	water.visible = full
	return root


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
	# Float in front / right of player — greybox carry pose.
	var basis := _player.global_transform.basis
	var offset := basis * Vector3(0.42, 1.05, -0.35)
	_carried.global_position = _player.global_position + offset
	_carried.global_rotation.y = _player.global_rotation.y


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
