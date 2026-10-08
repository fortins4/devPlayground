extends Node3D
class_name OpeningBoggedCowChore
## Tutorial beat: one extra cow starts bogged at the lane-facing bog edge.
## Player goads it onto firm ground. Additive soft cue — not part of the 6-head herd.
## Soft success only after at least one goad while bogged, then leaving the bog.

enum BogChoreState { BOGGED, DONE }

const COW_SCENE := preload("res://scenes/prologue/opening_cow.tscn")
const INTERACT_RANGE := 8.0
## BogZone center/size from opening_cattle_drive (transform 34,1,118 · box 20×20).
const BOG_CENTER := Vector3(34.0, 0.0, 118.0)
const BOG_HALF_XZ := Vector3(10.0, 0.0, 10.0)
## West (lane-facing) bog edge — readable from Bend6 (~-2,118).
## Y is height above the local ground: the bog edge sits on the east roll's skirt, so the cow
## is placed on the OpeningTerrain surface (see _ground()).
const COW_SPAWN := Vector3(27.5, 0.1, 116.0)
const FIRM_GROUND := Vector3(18.0, 0.1, 116.0)
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

@export var bog_zone_path: NodePath = ^"../BogZone"
@export var director_path: NodePath = ^"../OpeningDriveDirector"
@export var path_markers_path: NodePath = ^"../PathMarkers"

var _state: BogChoreState = BogChoreState.BOGGED
var _cow: Node3D = null
var _director: Node = null
var _bog_zone: Area3D = null
var _player: Node3D = null
var _goaded_while_bogged: bool = false
var _intro_flashed: bool = false
var _prompt_near: bool = false


func _ready() -> void:
	add_to_group("opening_bogged_cow")
	_spawn_cow()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	_bog_zone = get_node_or_null(bog_zone_path) as Area3D
	if _bog_zone:
		if not _bog_zone.body_entered.is_connected(_on_bog_entered):
			_bog_zone.body_entered.connect(_on_bog_entered)
		if not _bog_zone.body_exited.is_connected(_on_bog_exited):
			_bog_zone.body_exited.connect(_on_bog_exited)
	_setup_cow_ai()
	if _cow and _cow.has_method("set_bogged"):
		_cow.call("set_bogged", true)
	print(
		"OPENING_BOGGED_COW_READY spawn=%s bog_center=%s firm=%s"
		% [COW_SPAWN, BOG_CENTER, FIRM_GROUND]
	)
	# One intro flash so the beat is findable on the drive.
	call_deferred("_flash_intro")


func _flash_intro() -> void:
	if _intro_flashed:
		return
	_intro_flashed = true
	_flash("A cow's stuck in the bog — goad it onto the lane.", 4.5)


func _process(_delta: float) -> void:
	if _state == BogChoreState.DONE:
		return
	if _cow == null or not is_instance_valid(_cow):
		return
	# Fallback if Area3D exit is missed (teleport / force).
	if _goaded_while_bogged and not _inside_bog(_cow.global_position):
		if bool(_cow.get("bogged")):
			_cow.call("set_bogged", false)
		_try_complete()


func _spawn_cow() -> void:
	_cow = COW_SCENE.instantiate() as Node3D
	_cow.name = "BoggedChoreCow"
	if "cow_id" in _cow:
		_cow.set("cow_id", 99)
	add_child(_cow)
	_cow.global_position = _ground(COW_SPAWN)
	# Wander home = her placed bog spot (her _ready captured (0,0,0) before placement).
	if _cow.has_method("set_home_spot"):
		_cow.call("set_home_spot", _cow.global_position)
	if "bog_hold_still" in _cow:
		_cow.set("bog_hold_still", true)
	# Stuck from the first physics frame (_bind re-asserts it once deferred setup runs).
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", true)
	# Face toward the lane (west).
	_cow.rotation.y = PI * 0.5
	if _cow.has_signal("goaded"):
		_cow.connect("goaded", _on_cow_goaded)


func _setup_cow_ai() -> void:
	if _cow == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _cow.has_method("set_player"):
		_cow.call("set_player", _player)
	# Bias toward home so a goad walks it west out of the bog onto the lane.
	var path: Array = _collect_path_points()
	var home := Vector3(7.0, 0.0, 6.5)
	if _director and _director.has_method("home_center"):
		home = _director.call("home_center")
	if _cow.has_method("set_path_bias"):
		_cow.call("set_path_bias", path, home)


func _collect_path_points() -> Array:
	var out: Array = []
	var markers := get_node_or_null(path_markers_path)
	if markers == null:
		# Lane-facing exit cue toward Bend6 then home.
		out.append(Vector3(-2.0, 0.0, 118.0))
		out.append(Vector3(10.0, 0.0, 92.0))
		out.append(Vector3(7.0, 0.0, 14.0))
		out.append(Vector3(7.0, 0.0, 6.5))
		return out
	# Home-first order matches director: reverse child order (pasture → gate).
	var kids := markers.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var m := kids[i] as Node3D
		if m:
			out.append(m.global_position)
	return out


# ---------------------------------------------------------------- queries

func chore_done() -> bool:
	return _state == BogChoreState.DONE


func bog_state() -> String:
	match _state:
		BogChoreState.BOGGED:
			return "bogged"
		BogChoreState.DONE:
			return "done"
	return "unknown"


func cow_pos() -> Vector3:
	if _cow and is_instance_valid(_cow):
		return _cow.global_position
	return _ground(COW_SPAWN)


func bog_zone_center() -> Vector3:
	return BOG_CENTER


## Authored spawn marker (y = lift above the local ground; the cow itself stands on the surface).
func spawn_pos() -> Vector3:
	return COW_SPAWN


func get_chore_cow() -> Node3D:
	return _cow


func interact_prompt() -> String:
	if _state == BogChoreState.DONE:
		return ""
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or _cow == null:
		return ""
	if not _near(_player.global_position, _cow.global_position, INTERACT_RANGE):
		return ""
	return "Goad the bogged cow onto the lane (3 · LMB)"


func is_active() -> bool:
	return _state != BogChoreState.DONE


func force_free() -> void:
	if _cow == null or not is_instance_valid(_cow):
		return
	_goaded_while_bogged = true
	_cow.global_position = _ground(FIRM_GROUND)
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", false)
	_complete()


func force_state(state_name: String) -> void:
	match state_name:
		"bogged":
			_state = BogChoreState.BOGGED
			_goaded_while_bogged = false
			if _cow:
				_cow.global_position = _ground(COW_SPAWN)
				_cow.velocity = Vector3.ZERO
				if "driven" in _cow:
					_cow.set("driven", false)
				if _cow.has_method("set_bogged"):
					_cow.call("set_bogged", true)
		"done":
			force_free()
		_:
			push_warning("OpeningBoggedCowChore.force_state unknown: " + state_name)


func debug_set_state(state_name: String) -> void:
	force_state(state_name)


# ---------------------------------------------------------------- bog / goad

func _on_cow_goaded(_cow_ref: Node3D, _kind: StringName) -> void:
	if _state == BogChoreState.DONE:
		return
	_goaded_while_bogged = true
	_flash("Keep goading — walk it onto firm ground.", 3.0)
	print("OPENING_BOGGED_COW_GOADED")


func _on_bog_entered(body: Node3D) -> void:
	if body != _cow or _state == BogChoreState.DONE:
		return
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", true)


func _on_bog_exited(body: Node3D) -> void:
	if body != _cow or _state == BogChoreState.DONE:
		return
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", false)
	_try_complete()


func _try_complete() -> void:
	if _state == BogChoreState.DONE:
		return
	if not _goaded_while_bogged:
		return
	if _cow and is_instance_valid(_cow) and bool(_cow.get("bogged")):
		return
	_complete()


func _complete() -> void:
	if _state == BogChoreState.DONE:
		return
	_state = BogChoreState.DONE
	_flash("Cow free of the bog.", 4.0)
	print("OPENING_BOGGED_COW_SOFT_SUCCESS")


# ---------------------------------------------------------------- helpers

func _ground(p: Vector3) -> Vector3:
	## p.y is a lift above the terrain surface at p.xz.
	return Vector3(p.x, Terrain.surface_y(p.x, p.z) + p.y, p.z)


func _inside_bog(p: Vector3) -> bool:
	return (
		absf(p.x - BOG_CENTER.x) <= BOG_HALF_XZ.x
		and absf(p.z - BOG_CENTER.z) <= BOG_HALF_XZ.z
	)


func _near(a: Vector3, b: Vector3, range_m: float) -> bool:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) <= range_m


func _flash(text: String, secs: float = 3.0) -> void:
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)
	elif _director and _director.has_method("_flash"):
		_director.call("_flash", text, secs)
