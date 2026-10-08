extends Node3D
class_name OpeningBoggedCowChore
## Drive beat: one of the SIX herd cows starts bogged at the lane-facing bog edge (the director
## counts her as the herd's 6th head; the Herd node holds the other five at the pasture).
## Player goads her onto firm ground (freed only after at least one goad while bogged, then
## leaving the bog). In the set-sequence flow she must then be driven back to the herd at the
## pasture: she REJOINS once she's within REJOIN_RADIUS of the other five's centre. Until then
## her home (idle wander + path bias) is the herd, not the free spot. Without a sequence (old
## standalone behaviour) she re-homes where she came free and counts as rejoined at once.
## While bogged and the drive is live she lows (Label3D "Mooo!" pulse) so the bog is findable.

enum BogChoreState { BOGGED, FREED, REJOINED }

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
## She rejoins within this horizontal distance of the other five's centre (pasture herd spreads
## ~8.5 m from its centre while grazing).
const REJOIN_RADIUS := 12.0
## Her pasture spot (the herd's sixth grazing spot) — used by the R reset / force_rejoin.
const PASTURE_SPOT := Vector3(-23.0, 0.1, 200.0)
const LOW_PERIOD := 4.0
const LOW_ON := 1.7
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

@export var bog_zone_path: NodePath = ^"../BogZone"
## Her beat lives inside the drive step (step 4); goads bounce off her until it's live.
const SEQ_STEP := &"drive"

@export var director_path: NodePath = ^"../OpeningDriveDirector"
@export var path_markers_path: NodePath = ^"../PathMarkers"

var _state: BogChoreState = BogChoreState.BOGGED
var _cow: Node3D = null
var _director: Node = null
var _sequence: Node = null
var _bog_zone: Area3D = null
var _player: Node3D = null
var _goaded_while_bogged: bool = false
var _intro_flashed: bool = false
var _prompt_near: bool = false
var _low_label: Label3D = null
var _low_t: float = 0.0
var _low_announced: bool = false


func _ready() -> void:
	add_to_group("opening_bogged_cow")
	_spawn_cow()
	_build_low_label()
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
	if _seq() != null:
		# Set sequence: Máire hands this job out (step 5); no remote intro flash at start.
		_intro_flashed = true
		return
	_intro_flashed = true
	_flash("A cow's stuck in the bog — goad it onto the lane.", 4.5)


func _process(delta: float) -> void:
	_tick_lowing(delta)
	if _state != BogChoreState.BOGGED:
		if _cow and is_instance_valid(_cow) and bool(_cow.get("goad_locked")):
			_cow.set("goad_locked", false)
		if _state == BogChoreState.FREED:
			_check_rejoin()
		return
	if _cow == null or not is_instance_valid(_cow):
		return
	# Goads bounce off her (she stays stuck fast) until her step is live.
	var locked := not _gate_open()
	if bool(_cow.get("goad_locked")) != locked:
		_cow.set("goad_locked", locked)
	# Fallback if Area3D exit is missed (teleport / force).
	if _goaded_while_bogged and not _inside_bog(_cow.global_position):
		if bool(_cow.get("bogged")):
			_cow.call("set_bogged", false)
		_try_complete()


func _spawn_cow() -> void:
	_cow = COW_SCENE.instantiate() as Node3D
	_cow.name = "BoggedChoreCow"
	if "cow_id" in _cow:
		# Herd sixth head. id 6: same lateral goad peel as the old id 99 (id % 3 == 0, so her
		# goad-out is unchanged) and a sane soft-follow trail slot (99 put it ~47 m back).
		_cow.set("cow_id", 6)
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
	if _cow.has_signal("goad_blocked"):
		_cow.connect("goad_blocked", _on_cow_goad_blocked)


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

## Freed from the bog (rejoined or not).
func chore_done() -> bool:
	return _state != BogChoreState.BOGGED


func bog_state() -> String:
	return "bogged" if _state == BogChoreState.BOGGED else "done"


## "bogged" → "freed" (on her way back to the herd) → "rejoined".
func herd_state() -> String:
	match _state:
		BogChoreState.BOGGED:
			return "bogged"
		BogChoreState.FREED:
			return "freed"
		BogChoreState.REJOINED:
			return "rejoined"
	return "unknown"


func rejoined() -> bool:
	return _state == BogChoreState.REJOINED


func is_lowing() -> bool:
	return _low_label != null and _low_label.visible


## Horizontal distance from her to the centre of the other five (0 when unknown).
func distance_to_herd() -> float:
	if _cow == null or not is_instance_valid(_cow):
		return 0.0
	var c := _herd_point()
	return Vector2(_cow.global_position.x - c.x, _cow.global_position.z - c.z).length()


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
	if _state != BogChoreState.BOGGED:
		return ""
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or _cow == null:
		return ""
	if not _near(_player.global_position, _cow.global_position, INTERACT_RANGE):
		return ""
	if not _gate_open():
		return _not_yet()
	return "Goad the bogged cow onto the lane (3 · LMB)"


func is_active() -> bool:
	return _state == BogChoreState.BOGGED


func force_free() -> void:
	if _cow == null or not is_instance_valid(_cow):
		return
	if _state != BogChoreState.BOGGED:
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
				if "bog_hold_still" in _cow:
					_cow.set("bog_hold_still", true)
				if _cow.has_method("set_home_spot"):
					_cow.call("set_home_spot", _cow.global_position)
				_setup_cow_ai()
				if _cow.has_method("set_bogged"):
					_cow.call("set_bogged", true)
		"done", "freed":
			force_free()
		"rejoined":
			force_rejoin()
		_:
			push_warning("OpeningBoggedCowChore.force_state unknown: " + state_name)


func debug_set_state(state_name: String) -> void:
	force_state(state_name)


## Debug / smoke: free her (if still bogged), set her down beside the herd idle, and rejoin.
func force_rejoin() -> void:
	if _cow == null or not is_instance_valid(_cow):
		return
	if _state == BogChoreState.BOGGED:
		force_free()
	if _state == BogChoreState.REJOINED:
		return
	_place_with_herd()
	_rejoin()


## Herd reset (R) in the set-sequence flow: once she's out of the bog she goes back to the
## pasture with the rest and counts as rejoined (never re-bogged). Still bogged: left as is.
func reset_with_herd() -> void:
	if _state == BogChoreState.BOGGED or _cow == null or not is_instance_valid(_cow):
		return
	if _cow.has_method("reset_opening"):
		_cow.call("reset_opening")
	_place_with_herd()
	if _state == BogChoreState.FREED:
		_rejoin()


func _place_with_herd() -> void:
	var p := _ground(PASTURE_SPOT)
	_cow.global_position = p
	_cow.velocity = Vector3.ZERO
	if _cow.has_method("stop_driven"):
		_cow.call("stop_driven")
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", false)
	if _cow.has_method("set_home_spot"):
		_cow.call("set_home_spot", p)


# ---------------------------------------------------------------- bog / goad

func _on_cow_goad_blocked(_cow_ref: Node3D, _kind: StringName) -> void:
	if _state == BogChoreState.BOGGED:
		_flash(_not_yet(), 2.5)


func _on_cow_goaded(_cow_ref: Node3D, _kind: StringName) -> void:
	if _state != BogChoreState.BOGGED:
		return
	_goaded_while_bogged = true
	_flash("Keep goading — walk it onto firm ground.", 3.0)
	print("OPENING_BOGGED_COW_GOADED")


func _on_bog_entered(body: Node3D) -> void:
	if body != _cow or _state != BogChoreState.BOGGED:
		return
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", true)


func _on_bog_exited(body: Node3D) -> void:
	if body != _cow or _state != BogChoreState.BOGGED:
		return
	if _cow.has_method("set_bogged"):
		_cow.call("set_bogged", false)
	_try_complete()


func _try_complete() -> void:
	if _state != BogChoreState.BOGGED:
		return
	if not _gate_open():
		return
	if not _goaded_while_bogged:
		return
	if _cow and is_instance_valid(_cow) and bool(_cow.get("bogged")):
		return
	_complete()


func _complete() -> void:
	if _state != BogChoreState.BOGGED:
		return
	_state = BogChoreState.FREED
	if _flow():
		# Set-sequence flow: she's one of the six — her home is the herd at the pasture now
		# (idle wander + goad path bias lead back there), not the free spot. Drive mode as is.
		var herd := _herd_point()
		if _cow and is_instance_valid(_cow):
			if "bog_hold_still" in _cow:
				_cow.set("bog_hold_still", false)  # a later bog visit = ordinary herd-cow bog
			if _cow.has_method("set_home_spot"):
				_cow.call("set_home_spot", Vector3(herd.x, _cow.global_position.y, herd.z))
			if _cow.has_method("set_path_bias"):
				_cow.call("set_path_bias", _collect_path_points(), herd)
		_flash("She's free of the bog — drive her back to the herd at the pasture.", 4.5)
		print("OPENING_BOGGED_COW_SOFT_SUCCESS")
		print("OPENING_BOGGED_COW_FREED herd=%s" % herd.snapped(Vector3.ONE))
	else:
		# Standalone: graze where she came free (goad exit or force_free), not at the bog edge.
		if _cow and is_instance_valid(_cow) and _cow.has_method("set_home_spot"):
			_cow.call("set_home_spot", _cow.global_position)
		_flash("Cow free of the bog.", 4.0)
		print("OPENING_BOGGED_COW_SOFT_SUCCESS")
		_state = BogChoreState.REJOINED


func _check_rejoin() -> void:
	if _cow == null or not is_instance_valid(_cow):
		return
	if distance_to_herd() <= REJOIN_RADIUS:
		_rejoin()


func _rejoin() -> void:
	if _state == BogChoreState.REJOINED:
		return
	_state = BogChoreState.REJOINED
	# Back in the herd: graze with them, and the lane path bias leads home to the pen again.
	if _cow and is_instance_valid(_cow):
		if _cow.has_method("set_home_spot"):
			_cow.call("set_home_spot", _cow.global_position)
		_setup_cow_ai()
	_flash("She's back with the herd.", 4.0)
	print("OPENING_BOGGED_COW_REJOINED dist=%.1f" % distance_to_herd())


func _herd_point() -> Vector3:
	if _director and _director.has_method("herd_centroid"):
		return _director.call("herd_centroid")
	return _ground(PASTURE_SPOT)


## Set-sequence flow (rejoin required) vs the old standalone bog chore.
func _flow() -> bool:
	return _seq() != null


# ---------------------------------------------------------------- lowing cue

func _build_low_label() -> void:
	_low_label = Label3D.new()
	_low_label.name = "Lowing"
	_low_label.text = "Mmmooo!"
	# Heard, not seen: constant on-screen size and drawn through the rolls, so it reads as a sound
	# cue from the pasture (~90 m) as well as at the bog edge.
	_low_label.font_size = 40
	_low_label.fixed_size = true
	_low_label.pixel_size = 0.0016
	_low_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_low_label.no_depth_test = true
	_low_label.modulate = Color(1.0, 0.86, 0.6)
	_low_label.outline_size = 12
	_low_label.visible = false
	add_child(_low_label)


func _tick_lowing(delta: float) -> void:
	if _low_label == null:
		return
	var on := false
	if _state == BogChoreState.BOGGED and _cow and is_instance_valid(_cow) and _flow() and _gate_open():
		_low_t = fposmod(_low_t + delta, LOW_PERIOD)
		on = _low_t < LOW_ON
		_low_label.global_position = _cow.global_position + Vector3(0.0, 2.3 + 0.25 * sin(_low_t * 5.0), 0.0)
		if on and not _low_announced:
			_low_announced = true
			print("OPENING_BOGGED_COW_LOWING")
	else:
		_low_t = 0.0
	_low_label.visible = on


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

