extends Node3D
class_name OpeningDriveDirector
## First-morning tutorial: walk the lane from the house to the pasture, stir the grazing herd
## with the goad, and drive enough head back into the home pen beside the byre.
##
## Reuses raid_cow.gd AI via opening_cow.gd (idle → goad → drove + path bias). Standalone scene:
## no CattleRaidDirector / CattleEconomy / HeatTracker, so the F5 cattle_raid_lane is untouched.
## Soft success: >= need_home head inside HomeZone → signal + print + HUD banner. No fail state.

enum Stage { WALK_OUT, AT_HERD, DRIVING, SUCCESS }

signal stage_changed(stage: int, stage_name: String)
signal cow_home(count: int, total: int)
signal soft_success(home_count: int, total: int)

@export var need_home: int = 4
@export var herd_path: NodePath = ^"../Herd"
@export var home_zone_path: NodePath = ^"../HomeZone"
@export var bog_zone_path: NodePath = ^"../BogZone"
@export var pasture_zone_path: NodePath = ^"../PastureZone"
@export var path_markers_path: NodePath = ^"../PathMarkers"
## Herd "lifts its heads" (all start milling / respond to goad pressure) after the first prod.
@export var stir_radius: float = 30.0
@export var at_herd_radius: float = 22.0

var stage: Stage = Stage.WALK_OUT
var succeeded: bool = false
var first_goad_done: bool = false

var _player: Node3D = null
var _cows: Array[Node3D] = []
var _home_zone: Area3D = null
var _bog_zone: Area3D = null
var _pasture_zone: Area3D = null
var _path_home_first: Array[Vector3] = []
var _player_start: Transform3D = Transform3D.IDENTITY
var _slot_index: int = 0
var _flash_text: String = ""
var _flash_timer: float = 0.0


func _ready() -> void:
	add_to_group("opening_drive")
	_home_zone = get_node_or_null(home_zone_path) as Area3D
	_bog_zone = get_node_or_null(bog_zone_path) as Area3D
	_pasture_zone = get_node_or_null(pasture_zone_path) as Area3D
	_collect_cows()
	_collect_path()
	if _home_zone:
		_home_zone.body_entered.connect(_on_home_entered)
	if _bog_zone:
		_bog_zone.body_entered.connect(_on_bog_entered)
		_bog_zone.body_exited.connect(_on_bog_exited)
	if _pasture_zone:
		_pasture_zone.body_entered.connect(_on_pasture_entered)
	for cow in _cows:
		if cow.has_signal("goaded"):
			cow.connect("goaded", _on_cow_goaded)
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		_player_start = _player.global_transform
		var combat := _player.get_node_or_null("CombatSystem")
		if combat and combat.has_method("set_weapon"):
			combat.call("set_weapon", 2)  # CombatSystem.Weapon.GOAD — opening kit: goad + knife.
	var home := _home_center()
	for cow in _cows:
		cow.call("set_player", _player)
		cow.call("set_path_bias", _path_home_first, home)
	_set_stage(Stage.WALK_OUT)
	print("OPENING_DRIVE_READY cows=%d need=%d path_markers=%d" % [_cows.size(), need_home, _path_home_first.size()])


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
	if stage == Stage.WALK_OUT and _player and is_instance_valid(_player):
		if _player.global_position.distance_to(herd_centroid()) <= at_herd_radius:
			_set_stage(Stage.AT_HERD)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_R:
			reset_herd()
			get_viewport().set_input_as_handled()
		elif key == KEY_T:
			reset_herd()
			if _player:
				_player.global_transform = _player_start
				_player.set("velocity", Vector3.ZERO)
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries (HUD / smoke)

func get_stage_name() -> String:
	match stage:
		Stage.WALK_OUT:
			return "walk_out"
		Stage.AT_HERD:
			return "at_herd"
		Stage.DRIVING:
			return "driving"
		Stage.SUCCESS:
			return "success"
	return "unknown"


func get_cows() -> Array[Node3D]:
	return _cows


func home_count() -> int:
	var n := 0
	for cow in _cows:
		if bool(cow.get("delivered")):
			n += 1
	return n


func driven_count() -> int:
	var n := 0
	for cow in _cows:
		if bool(cow.get("driven")) and not bool(cow.get("delivered")):
			n += 1
	return n


func stalled_count() -> int:
	var n := 0
	for cow in _cows:
		if cow.has_method("is_stalled") and bool(cow.call("is_stalled")):
			n += 1
	return n


func bogged_count() -> int:
	var n := 0
	for cow in _cows:
		if bool(cow.get("bogged")):
			n += 1
	return n


func herd_centroid(include_home: bool = false) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for cow in _cows:
		if not include_home and bool(cow.get("delivered")):
			continue
		sum += cow.global_position
		n += 1
	return sum / float(n) if n > 0 else _home_center()


func path_home_first() -> Array[Vector3]:
	return _path_home_first


func home_center() -> Vector3:
	return _home_center()


func distance_to_herd() -> float:
	if _player == null:
		return 0.0
	return _player.global_position.distance_to(herd_centroid())


func distance_to_home() -> float:
	if _player == null:
		return 0.0
	return _player.global_position.distance_to(_home_center())


func objective_text() -> String:
	var total := _cows.size()
	match stage:
		Stage.WALK_OUT:
			return "First morning. Walk the lane south to the pasture and bring the cattle home.  (pasture ~%d m)" % int(distance_to_herd())
		Stage.AT_HERD:
			return "The herd is grazing. Draw the goad (3) and prod a cow (LMB / RMB) to stir them."
		Stage.DRIVING:
			var bits := "Walk BEHIND the herd, goad drawn, facing them — push them up the lane to the home pen."
			if bogged_count() > 0:
				bits += "  %d in the bog — goad them out!" % bogged_count()
			elif stalled_count() > 0:
				bits += "  %d grazing — keep pushing." % stalled_count()
			return bits
		Stage.SUCCESS:
			return "The herd is home (%d/%d in the pen). Soft success — finish the rest, or explore." % [home_count(), total]
	return ""


func status_text() -> String:
	return "Home pen  %d / %d   (need %d)\nDrove %d  ·  grazing %d  ·  bogged %d" % [
		home_count(), _cows.size(), need_home, driven_count(), stalled_count(), bogged_count()
	]


func flash_text() -> String:
	return _flash_text if _flash_timer > 0.0 else ""


# ---------------------------------------------------------------- actions

func reset_herd() -> void:
	for cow in _cows:
		if cow.has_method("reset_opening"):
			cow.call("reset_opening")
	_slot_index = 0
	succeeded = false
	first_goad_done = false
	_set_stage(Stage.WALK_OUT)
	_flash("Herd back at the pasture.", 3.0)


## Smoke / capture helper: stir the whole herd as if the first prod landed.
func debug_stir() -> void:
	_stir_herd()


## Smoke helper: drop n undelivered cows inside the home pen (physics delivers them).
func debug_place_in_home(n: int) -> void:
	var home := _home_center()
	var placed := 0
	for cow in _cows:
		if placed >= n:
			break
		if bool(cow.get("delivered")):
			continue
		cow.global_position = home + Vector3(-4.0 + float(placed) * 2.2, 0.15, 1.5)
		cow.call("start_driven")
		placed += 1


# ---------------------------------------------------------------- internals

func _collect_cows() -> void:
	_cows.clear()
	var herd := get_node_or_null(herd_path)
	if herd == null:
		return
	for c in herd.get_children():
		if c is Node3D and c.has_method("apply_goad"):
			_cows.append(c as Node3D)


func _collect_path() -> void:
	## PathMarkers children are authored house → pasture; cows want them pasture → house.
	_path_home_first.clear()
	var markers := get_node_or_null(path_markers_path)
	if markers == null:
		return
	var pts: Array[Vector3] = []
	for c in markers.get_children():
		if c is Node3D:
			pts.append((c as Node3D).global_position)
	pts.reverse()
	_path_home_first = pts


func _home_center() -> Vector3:
	if _home_zone:
		return _home_zone.global_position
	return global_position


func _stir_herd() -> void:
	var origin := _player.global_position if _player else herd_centroid()
	for cow in _cows:
		if bool(cow.get("delivered")):
			continue
		if cow.global_position.distance_to(origin) <= stir_radius or not first_goad_done:
			if not bool(cow.get("herded")):
				cow.call("begin_herd")
	first_goad_done = true
	if stage == Stage.WALK_OUT or stage == Stage.AT_HERD:
		_set_stage(Stage.DRIVING)


func _on_cow_goaded(_cow: Node3D, _kind: StringName) -> void:
	if not first_goad_done:
		_stir_herd()
		_flash("The herd lifts its heads — drive them home up the lane!", 4.0)
		print("OPENING_DRIVE_STIRRED")


func _on_pasture_entered(body: Node3D) -> void:
	if body and body.is_in_group("player") and stage == Stage.WALK_OUT:
		_set_stage(Stage.AT_HERD)


func _on_home_entered(body: Node3D) -> void:
	if body == null or not _cows.has(body):
		return
	if bool(body.get("delivered")):
		return
	body.call("mark_delivered")
	if body.has_method("set_pen_slot"):
		body.call("set_pen_slot", _next_pen_slot())
	var n := home_count()
	cow_home.emit(n, _cows.size())
	print("OPENING_DRIVE_COW_HOME %d/%d" % [n, _cows.size()])
	if not succeeded and n >= need_home:
		succeeded = true
		_set_stage(Stage.SUCCESS)
		_flash("Herd home! %d of %d head in the pen beside the byre." % [n, _cows.size()], 8.0)
		print("OPENING_DRIVE_SOFT_SUCCESS home=%d/%d need=%d" % [n, _cows.size(), need_home])
		soft_success.emit(n, _cows.size())
	elif not succeeded:
		_flash("%d / %d home." % [n, need_home], 2.5)


func _next_pen_slot() -> Vector3:
	var home := _home_center()
	var col := _slot_index % 4
	var row := _slot_index / 4
	_slot_index += 1
	return Vector3(home.x - 4.2 + float(col) * 2.8, home.y, home.z - 3.0 + float(row) * 2.4)


func _on_bog_entered(body: Node3D) -> void:
	if body and _cows.has(body) and body.has_method("set_bogged"):
		body.call("set_bogged", true)
		if stage == Stage.DRIVING:
			_flash("A cow has wandered into the bog — goad it back onto the lane.", 3.0)


func _on_bog_exited(body: Node3D) -> void:
	if body and _cows.has(body) and body.has_method("set_bogged"):
		body.call("set_bogged", false)


func _set_stage(next: Stage) -> void:
	stage = next
	stage_changed.emit(int(stage), get_stage_name())


func _flash(text: String, secs: float) -> void:
	_flash_text = text
	_flash_timer = secs
