extends Node3D
class_name OpeningDriveDirector
## First-morning tutorial: walk the lane from the house to the pasture, stir the grazing herd
## with the goad, and drive enough head back into the home pen beside the byre.
##
## Reuses raid_cow.gd AI via opening_cow.gd (idle → goad → drove + path bias). Standalone scene:
## no CattleRaidDirector / CattleEconomy / HeatTracker, so the F5 cattle_raid_lane is untouched.
## Soft success: >= need_home head inside HomeZone → signal + print + HUD banner. No fail state.
##
## Set-sequence flow (OpeningSequence present — the drive is step 4, no Máire trips inside it):
## - The herd is SIX: the five Herd cows at the pasture + the bogged chore cow (appended last).
## - Beats (drive_beat(), shown by OpeningSequence.objective_text()): walk_out → missing /
##   free_her (she's stuck in the bog; lowing + HUD lead there) → rejoin (drive her back to the
##   herd) → stir → driving, with the stray-dog ambush on the lane (ambush → regather).
## - Before she rejoins, the five stay goad_locked (goads bounce, "Not yet" flash: no stir, no
##   drive) and pen arrivals don't count. Success needs ALL SIX in the pen (need_count()).
## - The ambush springs when a herd cow comes within AMBUSH_RADIUS of the dog's hedge spot
##   (between Bend4 and Bend5) on the way home; the dog dashes in, the herd balks and the
##   nearest head scatter (opening_cow.scatter_from) and must be regathered.
## - Failsafes: unstick watchdog (a pushed cow pinned for STUCK_SECS, or a cow outside the farm
##   bounds, is set back on the lane), periodic pen re-check, R = herd reset that keeps the pen,
##   never re-bogs her and never touches the sequence.

enum Stage { WALK_OUT, AT_HERD, DRIVING, SUCCESS }

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
## Player below the shared terrain surface by more than this (m) → lift onto it (teleport guard;
## normal walking is plain CharacterBody3D physics on the heightfield).
const PLAYER_SINK_GUARD := 0.3

signal stage_changed(stage: int, stage_name: String)
signal cow_home(count: int, total: int)
signal soft_success(home_count: int, total: int)

@export var need_home: int = 4
@export var herd_path: NodePath = ^"../Herd"
@export var home_zone_path: NodePath = ^"../HomeZone"
@export var bog_zone_path: NodePath = ^"../BogZone"
@export var pasture_zone_path: NodePath = ^"../PastureZone"
@export var path_markers_path: NodePath = ^"../PathMarkers"
@export var family_caller_path: NodePath = ^"../FamilyCaller"
@export var bog_chore_path: NodePath = ^"../OpeningBoggedCowChore"
@export var dog_chore_path: NodePath = ^"../OpeningStrayDogChore"
## Herd "lifts its heads" (all start milling / respond to goad pressure) after the first prod.
@export var stir_radius: float = 30.0
@export var at_herd_radius: float = 22.0

## Dog ambush: a herd cow within this of the dog's hedge spot (or past AMBUSH_FALLBACK_Z) springs it.
## 10 m: the first head to pass the hedge spot is on the Bend5 → Bend4 straight (lane ~8.5 m
## from the spot), past Bend5's outer wattle rail, so the scatter has open field to the SE.
const AMBUSH_RADIUS := 10.0
const AMBUSH_FALLBACK_Z := 66.0
## Scatter: herd cows within SCATTER_RADIUS of the dog bolt (nearest first, at least 1, at most
## SCATTER_MAX); others within BALK_RADIUS balk (go stale on the spot).
const SCATTER_RADIUS := 12.0
const SCATTER_MAX := 3
const BALK_RADIUS := 24.0
## Near her in the bog (player) → "free_her" beat instead of "missing".
const FREE_HER_RADIUS := 16.0
## Unstick watchdog: a cow being pushed (fresh drive) that moves less than STUCK_MOVE in STUCK_SECS.
const STUCK_SECS := 6.0
const STUCK_MOVE := 0.6
const PEN_RECHECK_SECS := 0.5

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
var _family: Node = null
var _sequence: Node = null
var _bog_chore: Node = null
var _bog_cow: Node3D = null
var _dog: Node = null
var _ambush_fired: bool = false
var _pen_recheck_t: float = 0.0
var _stuck_ref: Dictionary = {}  # cow → [anchor_pos, secs]
var _beat: String = ""


func _ready() -> void:
	add_to_group("opening_drive")
	_home_zone = get_node_or_null(home_zone_path) as Area3D
	_bog_zone = get_node_or_null(bog_zone_path) as Area3D
	_pasture_zone = get_node_or_null(pasture_zone_path) as Area3D
	_bog_chore = get_node_or_null(bog_chore_path)
	_dog = get_node_or_null(dog_chore_path)
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
		if cow.has_signal("goad_blocked"):
			cow.connect("goad_blocked", _on_cow_goad_blocked)
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
	_family = get_node_or_null(family_caller_path)
	if _family and _family.has_signal("callout_spoken"):
		if not _family.is_connected("callout_spoken", _on_family_callout):
			_family.connect("callout_spoken", _on_family_callout)
	_set_stage(Stage.WALK_OUT)
	print("OPENING_DRIVE_READY cows=%d need=%d path_markers=%d bogged_in_herd=%s" % [
		_cows.size(), need_count(), _path_home_first.size(), _bog_cow != null])


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
	_sync_herd_lock()
	if stage == Stage.WALK_OUT and _player and is_instance_valid(_player):
		if _player.global_position.distance_to(herd_centroid()) <= at_herd_radius:
			_set_stage(Stage.AT_HERD)
	if _seq() == null:
		return
	_pen_recheck_t -= delta
	if _pen_recheck_t <= 0.0:
		_pen_recheck_t = PEN_RECHECK_SECS
		_recheck_pen()
	_check_success()
	_tick_ambush()
	_tick_unstick(delta)
	var b := drive_beat()
	if b != _beat:
		_beat = b
		if bool(_seq().call("is_step_active", &"drive")):
			print("OPENING_DRIVE_BEAT %s" % b)


func _physics_process(_delta: float) -> void:
	if _player and is_instance_valid(_player):
		var p := _player.global_position
		var gy := Terrain.surface_y(p.x, p.z)
		if p.y < gy - PLAYER_SINK_GUARD:
			_player.global_position = Vector3(p.x, gy + 0.05, p.z)
			_player.set("velocity", Vector3.ZERO)


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
		if not is_herd_member(cow):
			continue
		if cow.has_method("is_stalled") and bool(cow.call("is_stalled")):
			n += 1
	return n


func bogged_count() -> int:
	var n := 0
	for cow in _cows:
		if bool(cow.get("bogged")):
			n += 1
	return n


func scattered_count() -> int:
	var n := 0
	for cow in _cows:
		if is_herd_member(cow) and not bool(cow.get("delivered")) and bool(cow.get("scattered")):
			n += 1
	return n


## Pen success threshold: all six in the set-sequence flow, need_home standalone.
func need_count() -> int:
	return _cows.size() if _seq() != null else need_home


func get_bogged_cow() -> Node3D:
	return _bog_cow


## The bogged cow only counts as part of the moving herd once she has rejoined it.
func is_herd_member(cow: Node3D) -> bool:
	return cow != _bog_cow or bogged_cow_rejoined()


func bogged_cow_rejoined() -> bool:
	return _bog_chore == null or not _bog_chore.has_method("rejoined") or bool(_bog_chore.call("rejoined"))


func bogged_cow_state() -> String:
	return String(_bog_chore.call("herd_state")) if _bog_chore and _bog_chore.has_method("herd_state") else "rejoined"


func bogged_cow_pos() -> Vector3:
	return _bog_cow.global_position if _bog_cow else Vector3(27.5, 0, 116)


func bogged_cow_to_herd() -> float:
	return float(_bog_chore.call("distance_to_herd")) if _bog_chore and _bog_chore.has_method("distance_to_herd") else 0.0


func ambush_fired() -> bool:
	return _ambush_fired


## Set-sequence in-drive beat (drives the HUD objective line; "" outside the drive).
func drive_beat() -> String:
	if succeeded:
		return "success"
	match bogged_cow_state():
		"bogged":
			if _player and _bog_cow and _hdist(_player.global_position, _bog_cow.global_position) <= FREE_HER_RADIUS:
				return "free_her"
			return "walk_out" if stage == Stage.WALK_OUT else "missing"
		"freed":
			return "rejoin"
	if _dog and _dog.has_method("is_threat") and bool(_dog.call("is_threat")):
		return "ambush"
	if not first_goad_done:
		return "walk_out" if stage == Stage.WALK_OUT else "stir"
	if scattered_count() > 0:
		return "regather"
	return "driving"


func herd_centroid(include_home: bool = false) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for cow in _cows:
		if not is_herd_member(cow):
			continue
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
	# Set sequence owns the top line (names the current step + where to go).
	var seq := _seq()
	if seq:
		return String(seq.call("objective_text"))
	var total := _cows.size()
	match stage:
		Stage.WALK_OUT:
			if family_bark_visible():
				return "%s calls from the door — walk the lane south and bring the cattle home.  (pasture ~%d m)" % [family_speaker(), int(distance_to_herd())]
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
	var s := "Home pen  %d / %d   (need %d)\nDrove %d  ·  grazing %d  ·  bogged %d" % [
		home_count(), _cows.size(), need_count(), driven_count(), stalled_count(), bogged_count()
	]
	if scattered_count() > 0:
		s += "\nScattered %d — regather" % scattered_count()
	return s


func flash_text() -> String:
	return _flash_text if _flash_timer > 0.0 else ""


# ---------------------------------------------------------------- actions

func reset_herd() -> void:
	if _seq() != null:
		_reset_herd_flow()
		return
	for cow in _cows:
		if cow.has_method("reset_opening"):
			cow.call("reset_opening")
	_slot_index = 0
	succeeded = false
	first_goad_done = false
	_set_stage(Stage.WALK_OUT)
	if _family and _family.has_method("reset_callout"):
		_family.call("reset_callout")
	_flash("Herd back at the pasture.", 3.0)


## Set-sequence R: a failsafe, not a restart. Penned cows stay penned; every other head goes back
## to its pasture spot, idle. She is never re-bogged: still bogged → left in the bog (goad her
## out as normal); freed / rejoined → back at the pasture with the herd, counted as rejoined.
## The sequence, Máire, and the dog beat are not touched (a sprung ambush doesn't re-fire).
func _reset_herd_flow() -> void:
	if succeeded:
		_flash("The herd's already home.", 2.5)
		return
	for cow in _cows:
		if bool(cow.get("delivered")):
			continue
		if cow == _bog_cow:
			if _bog_chore and _bog_chore.has_method("reset_with_herd"):
				_bog_chore.call("reset_with_herd")
			continue
		if cow.has_method("reset_opening"):
			cow.call("reset_opening")
	_stuck_ref.clear()
	first_goad_done = false
	_set_stage(Stage.WALK_OUT)
	_flash("Herd back at the pasture — penned head stay penned.", 3.0)
	print("OPENING_DRIVE_RESET_FLOW home=%d/%d bogged_state=%s" % [home_count(), _cows.size(), bogged_cow_state()])


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
		if bool(cow.get("delivered")) or not is_herd_member(cow):
			continue
		cow.global_position = home + Vector3(-4.0 + float(placed) * 2.2, 0.15, 1.5)
		cow.call("start_driven")
		placed += 1


func family_has_spoken() -> bool:
	return bool(_family.call("has_spoken")) if _family and _family.has_method("has_spoken") else false


func family_bark_visible() -> bool:
	return bool(_family.call("is_bark_visible")) if _family and _family.has_method("is_bark_visible") else false


func family_speaker() -> String:
	return String(_family.call("get_speaker_name")) if _family and _family.has_method("get_speaker_name") else ""


func _on_family_callout(line: String) -> void:
	var who := family_speaker()
	var prefix := ("%s: " % who) if who != "" else ""
	_flash(prefix + line, 6.0)


# ---------------------------------------------------------------- internals

func _collect_cows() -> void:
	_cows.clear()
	var herd := get_node_or_null(herd_path)
	if herd == null:
		return
	for c in herd.get_children():
		if c is Node3D and c.has_method("apply_goad"):
			_cows.append(c as Node3D)
	# Set-sequence flow: the bogged chore cow is the herd's sixth head (appended last).
	if _bog_chore and _bog_chore.has_method("get_chore_cow"):
		var bc := _bog_chore.call("get_chore_cow") as Node3D
		if bc and not _cows.has(bc):
			_bog_cow = bc
			_cows.append(bc)


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
		if bool(cow.get("delivered")) or not is_herd_member(cow):
			continue
		if cow.global_position.distance_to(origin) <= stir_radius or not first_goad_done:
			if not bool(cow.get("herded")):
				cow.call("begin_herd")
	first_goad_done = true
	if stage == Stage.WALK_OUT or stage == Stage.AT_HERD:
		_set_stage(Stage.DRIVING)


# ---------------------------------------------------------------- set sequence gate

func _seq() -> Node:
	if _sequence == null or not is_instance_valid(_sequence):
		_sequence = get_tree().get_first_node_in_group("opening_sequence") if is_inside_tree() else null
	return _sequence


## The drive step (4) is live (or behind us).
func drive_open() -> bool:
	var seq := _seq()
	return seq == null or bool(seq.call("is_step_open", &"drive"))


## Herd stir / drive / pen arrivals open once the drive is live AND she has rejoined the herd.
func herd_open() -> bool:
	return drive_open() and bogged_cow_rejoined()


func _sync_herd_lock() -> void:
	var locked := not herd_open()
	for cow in _cows:
		if cow == _bog_cow:
			continue  # her lock belongs to the bog chore (her beat opens with the drive step)
		if "goad_locked" in cow and bool(cow.get("goad_locked")) != locked:
			cow.set("goad_locked", locked)


func _on_cow_goad_blocked(_cow: Node3D, _kind: StringName) -> void:
	var seq := _seq()
	if seq == null or _cow == _bog_cow:
		return
	if drive_open() and not bogged_cow_rejoined():
		_flash("Not yet — fetch the missing cow back to the herd first.", 2.5)
	else:
		_flash(String(seq.call("not_yet_text")), 2.5)


func _on_cow_goaded(_cow: Node3D, _kind: StringName) -> void:
	if not herd_open() or not is_herd_member(_cow):
		return  # her goad-out / drive back to the herd doesn't start the drive home
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
	if not herd_open() or not is_herd_member(body):
		return  # set sequence: pen arrivals don't count before the drive / before she rejoins
	_deliver(body)


func _deliver(body: Node3D) -> void:
	body.call("mark_delivered")
	if body.has_method("set_pen_slot"):
		body.call("set_pen_slot", _next_pen_slot())
	var n := home_count()
	cow_home.emit(n, _cows.size())
	print("OPENING_DRIVE_COW_HOME %d/%d" % [n, _cows.size()])
	if not _check_success() and not succeeded:
		if n < need_count() and _seq() != null:
			_flash("%d / %d home — all %d must be in the pen." % [n, need_count(), need_count()], 2.5)
		else:
			_flash("%d / %d home." % [n, need_count()], 2.5)


## Success: need_count() head in the pen (all six in the set-sequence flow; the drive must be
## open and she must have rejoined). Returns true when it fires.
func _check_success() -> bool:
	if succeeded or not herd_open():
		return false
	var n := home_count()
	if n < need_count():
		return false
	succeeded = true
	_set_stage(Stage.SUCCESS)
	if _seq() != null:
		_flash("All six home! The herd's in the pen beside the byre.", 8.0)
	else:
		_flash("Herd home! %d of %d head in the pen beside the byre." % [n, _cows.size()], 8.0)
	print("OPENING_DRIVE_SOFT_SUCCESS home=%d/%d need=%d" % [n, _cows.size(), need_count()])
	soft_success.emit(n, _cows.size())
	if _dog and _dog.has_method("give_up"):
		_dog.call("give_up")
	var seq := _seq()
	if seq:
		seq.call("complete_step", &"drive")
	return true


## A cow already standing in the pen when the herd opens (body_entered fired while it was shut).
func _recheck_pen() -> void:
	if _home_zone == null or not herd_open() or succeeded:
		return
	for b in _home_zone.get_overlapping_bodies():
		if _cows.has(b) and not bool(b.get("delivered")) and is_herd_member(b):
			_deliver(b)


# ---------------------------------------------------------------- dog ambush

func _tick_ambush() -> void:
	if _ambush_fired or _dog == null or not _dog.has_method("trigger_ambush"):
		return
	if not herd_open() or not first_goad_done or succeeded:
		return
	if not bool(_seq().call("is_step_active", &"drive")):
		return
	var spot: Vector3 = _dog.call("spawn_pos")
	var best: Node3D = null
	var best_d := INF
	for cow in _cows:
		if bool(cow.get("delivered")) or not is_herd_member(cow):
			continue
		var d := _hdist(cow.global_position, spot)
		var past := cow.global_position.z < AMBUSH_FALLBACK_Z and cow.global_position.z > 20.0
		if (d <= AMBUSH_RADIUS or past) and d < best_d:
			best_d = d
			best = cow
	if best == null:
		return
	if bool(_dog.call("trigger_ambush", best.global_position)):
		_ambush_fired = true
		print("OPENING_DRIVE_AMBUSH cow=%s at=%s dist_to_spot=%.1f" % [best.name, best.global_position.snapped(Vector3.ONE * 0.1), best_d])


## Called by the dog when its dash reaches the herd: nearest head bolt, the rest balk.
func ambush_scatter(src: Vector3) -> int:
	var near: Array = []
	for cow in _cows:
		if bool(cow.get("delivered")) or not is_herd_member(cow):
			continue
		near.append([_hdist(cow.global_position, src), cow])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for pair in near:
		var d: float = pair[0]
		var cow: Node3D = pair[1]
		if n < SCATTER_MAX and (d <= SCATTER_RADIUS or n == 0):
			# Bolt sideways off the lane, on the far side from the dog (mostly perpendicular to
			# the lane so they leave it rather than run along it), via the cow's own scatter.
			cow.call("scatter_from", cow.global_position - _scatter_dir(cow.global_position, src))
			n += 1
		elif d <= BALK_RADIUS and cow.has_method("balk"):
			cow.call("balk")
	if n > 0:
		_flash("The herd balks — %d bolt off the lane! See off the dog, then regather them." % n, 4.5)
	print("OPENING_DRIVE_SCATTER n=%d src=%s" % [n, src.snapped(Vector3.ONE * 0.1)])
	return n


func _scatter_dir(p: Vector3, src: Vector3) -> Vector3:
	var away := p - src
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.RIGHT
	var best_d := INF
	var tangent := Vector3.ZERO
	for i in _path_home_first.size() - 1:
		var a := _path_home_first[i]
		var b := _path_home_first[i + 1]
		var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var t := clampf(Vector3(p.x - a.x, 0.0, p.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := _hdist(p, a + ab * t)
		if d < best_d:
			best_d = d
			tangent = ab.normalized()
	if tangent == Vector3.ZERO:
		return away
	var side := Vector3(-tangent.z, 0.0, tangent.x)
	if side.dot(away) < 0.0:
		side = -side
	return (side * 0.75 + away * 0.25).normalized()


# ---------------------------------------------------------------- unstick watchdog

## Every cow must stay reachable for 6/6: one being pushed (fresh drive) that has moved less
## than STUCK_MOVE in STUCK_SECS (wedged on a rail / bank / terrain), or one outside the farm
## bounds, is set back on the lane at the nearest marker.
func _tick_unstick(delta: float) -> void:
	if not drive_open() or succeeded:
		return
	for cow in _cows:
		if bool(cow.get("delivered")) or (cow == _bog_cow and bogged_cow_state() == "bogged"):
			_stuck_ref.erase(cow)
			continue
		var p := cow.global_position
		if _out_of_bounds(p):
			_rescue(cow, "out_of_bounds")
			continue
		var pushed := bool(cow.get("driven")) and float(cow.call("drive_freshness")) > 0.4 and not bool(cow.call("is_scattering"))
		if not pushed:
			_stuck_ref.erase(cow)
			continue
		var ref: Array = _stuck_ref.get(cow, [p, 0.0])
		if _hdist(p, ref[0]) > STUCK_MOVE:
			ref = [p, 0.0]
		else:
			ref[1] = float(ref[1]) + delta
		_stuck_ref[cow] = ref
		if float(ref[1]) >= STUCK_SECS:
			_rescue(cow, "pinned")


func _out_of_bounds(p: Vector3) -> bool:
	if p.y < Terrain.surface_y(p.x, p.z) - 2.0:
		return true
	if p.x > 41.0 or p.z < -13.0 or p.z > 207.0 or p.x < -60.0:
		return true
	return p.x < -25.0 and p.z < 140.0  # beyond the west ditch bank


func _rescue(cow: Node3D, why: String) -> void:
	cow.set_meta("_rescued_from", cow.global_position.snapped(Vector3.ONE * 0.1))
	var best := _home_center()
	var best_d := INF
	for m in _path_home_first:
		var d := _hdist(m, cow.global_position)
		if d < best_d:
			best_d = d
			best = m
	cow.global_position = Terrain.surface_point(best, 0.1)
	cow.set("velocity", Vector3.ZERO)
	_stuck_ref.erase(cow)
	print("OPENING_DRIVE_UNSTICK cow=%s why=%s from=%s to=%s" % [cow.name, why, (cow.get_meta("_rescued_from", Vector3.ZERO) as Vector3), best.snapped(Vector3.ONE)])


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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


func flash(text: String, secs: float = 3.0) -> void:
	## Public banner flash (chores / callers).
	_flash(text, secs)


func _flash(text: String, secs: float) -> void:
	_flash_text = text
	_flash_timer = secs
