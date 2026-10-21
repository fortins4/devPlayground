extends Node
class_name RaidSequence
## Prologue after the opening ("The foragers from the strand", raid-option1-spec rev 12): picks up
## when Máire's closer is said (OpeningSequence.sequence_complete) and runs as a set sequence with
## the same hub contract as OpeningSequence (is_step_active / complete_step / awaiting_maire /
## take_pending_line / note_line), so OpeningFamilyCaller hands its hub over to it.
##
## Chunk 1 (spec steps 1–3), dusk into twilight on day 0:
##   1 news    (C) the neighbours' boy comes in at the gate on an errand (a borrowed sieve back), sets
##              it down by the quern and says his piece (locked line) while Cian sits on at the meal
##              stool and Máire milks the red cow at the post. She pauses at the milking, then goes
##              on. When the boy goes home she calls the next job from the post.
##   2 supper  (P) the herd-hand's supper (piggin + bread) from by the stool up to him on the bank by
##              the gate; a thin haze to the SSW against the afterglow; his locked line. Back to
##              Máire (hub).
##   3 penning (P) her line: untie the milk cow, lead her back into the pen, latch it; an armful of
##              wood to the door; the herd-hand puts the hatchet away in the byre (ambient).
##   then the day's work is done; going back in to Máire at the door ends chunk 1 (`night_reached`).
## Nothing here gives Cian a knife or a hatchet (combat.knife_in_kit stays false; the hatchet is
## set dressing only), and there is no cow counter.

signal step_changed(step_id: StringName, briefed: bool)
signal line_spoken(key: String, text: String)
signal night_reached

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const VillagerScript := preload("res://scripts/prologue/prologue_villager.gd")
const SupperScript := preload("res://scripts/prologue/prologue_supper_chore.gd")
const WoodScript := preload("res://scripts/prologue/prologue_wood_chore.gd")
const HazeScript := preload("res://scripts/prologue/prologue_haze.gd")

const STEP_IDS: Array[StringName] = [&"news", &"supper", &"penning", &"night"]

## Delay after the closer before the boy is in at the gate ("a short beat later").
const START_DELAY := 2.5
const BOY_LINE := "My mother's people from by the strand came up last evening with their cows. They wouldn't say why."
const SUPPER_LINE := "Take the herd-hand his supper, he's up on the bank by the gate."
const CLAMP_LINE := "Someone's charcoal clamp, that."
const PENNING_LINE := "Put her back in with the others, and latch it well tonight. And bring in an armful for the fire."
const HANDOFF_LINES := {&"penning": PENNING_LINE}

## Meal stool seat (OpeningStowMealChore.SEAT_POS / SEAT_YAW).
const SEAT_POS := Vector3(-3.8, 0.0, 2.8)
const SEAT_YAW := PI * 0.5
const SIT_RADIUS := 6.0
const SIT_STAY_RADIUS := 1.2  ## still at the stool after the meal
## The boy: in by the causeway, round the pen's south fence, to the quern by the door.
const BOY_IN: Array[Vector3] = [Vector3(5.6, 0.0, 24.0), Vector3(6.0, 0.0, 16.5), Vector3(4.6, 0.0, 12.4), Vector3(0.4, 0.0, 11.2), Vector3(-3.0, 0.0, 6.2), Vector3(-3.3, 0.0, 5.6)]
const BOY_TALK := Vector3(-4.0, 0.0, 4.0)
const BOY_OUT: Array[Vector3] = [Vector3(-3.0, 0.0, 6.4), Vector3(0.4, 0.0, 11.2), Vector3(4.6, 0.0, 12.4), Vector3(6.0, 0.0, 16.5), Vector3(4.6, 0.0, 24.0), Vector3(-6.0, 0.0, 33.0), Vector3(-30.0, 0.0, 38.0), Vector3(-60.0, 0.0, 41.0)]
const SIEVE_POS := Vector3(-3.55, 0.0, 5.05)
## Máire at the milking: on a low stool at the tied cow's right flank, facing her.
## (Tied cow: centre = post (−1.2, 5.6) + (0.45, 0, 0.89)·1.95, head to the post.)
const MILK_SPOT := Vector3(0.52, 0.0, 7.12)
const MILK_YAW := -1.1   ## her +Z (front) toward the cow's flank (WNW)
const MAIRE_DOOR := Vector3(-5.2, 0.0, 3.2)
## Her way between the door and the cow's right flank: past the quern's west side, round the tail.
const MAIRE_ROUTE: Array[Vector3] = [Vector3(-5.6, 0.0, 4.4), Vector3(-5.0, 0.0, 6.2), Vector3(-2.4, 0.0, 8.3), Vector3(0.7, 0.0, 8.9)]
const MAIRE_DOOR_YAW := 0.36
## The herd-hand: on the bank beside the palisade's west end at the gate, looking out south.
const HH_BANK := Vector3(1.75, 0.0, 17.55)
const HH_BANK_YAW := PI - 0.26  ## kerne rig faces −Z: PI − 0.26 turns him SSW, out over the lane
const HH_DOWN: Array[Vector3] = [Vector3(1.6, 0.0, 15.2), Vector3(0.9, 0.0, 11.4), Vector3(0.9, 0.0, 0.4), Vector3(1.9, 0.0, -3.4)]
const NIGHT_RADIUS := 3.0

var _running: bool = false
var _finished_chunk: bool = false
var _start_left: float = -1.0
var _index: int = 0
var _briefed: bool = true
var _beat: String = ""
var _beat_t: float = 0.0
var _opening: Node = null
var _maire: Node3D = null
var _player: Node3D = null
var _director: Node = null
var _tie: Node = null
var _boy: Node3D = null
var _herd_hand: Node3D = null
var _supper: Node3D = null
var _wood: Node3D = null
var _haze: Node3D = null
var _sieve: Node3D = null
var _cow_penned: bool = false
var _wood_in: bool = false
var _hatchet_stowed: bool = false
var _sat_for_news: bool = false
var _night: bool = false
var _hh_down_started: bool = false


func _ready() -> void:
	add_to_group("raid_sequence")
	# The props of the twilight chores belong to the farm from the start (the block and hatchet by
	# the woodpile, the byre's yard door); the chores stay shut until their step.
	_wood = WoodScript.new()
	_wood.name = "PrologueWoodChore"
	add_child(_wood)
	call_deferred("_bind")


func _bind() -> void:
	_opening = get_tree().get_first_node_in_group("opening_sequence")
	_maire = get_tree().get_first_node_in_group("opening_maire_door_talk") as Node3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_tree().get_first_node_in_group("opening_drive")
	_tie = get_tree().get_first_node_in_group("opening_rope_tie")
	if _opening and _opening.has_signal("sequence_complete"):
		_opening.connect("sequence_complete", _on_opening_complete)
	print("RAID_SEQUENCE_READY")


func _on_opening_complete() -> void:
	if _running or _start_left > 0.0:
		return
	_start_left = START_DELAY
	print("RAID_SEQUENCE_ARMED delay=%.1f" % START_DELAY)


# ---------------------------------------------------------------- hub contract

func is_running() -> bool:
	return _running


func current_step_id() -> StringName:
	if _index >= 0 and _index < STEP_IDS.size():
		return STEP_IDS[_index]
	return &"done"


func current_beat() -> String:
	return _beat


func is_step_active(id: StringName) -> bool:
	return _running and _index < STEP_IDS.size() and STEP_IDS[_index] == id and _briefed


func is_step_done(id: StringName) -> bool:
	var i := STEP_IDS.find(id)
	return i >= 0 and i < _index


func awaiting_maire() -> bool:
	return _running and not _briefed and HANDOFF_LINES.has(current_step_id())


func is_finished() -> bool:
	return false  # chunk 1 hands on to the night (chunk 2)


func is_night_reached() -> bool:
	return _night


func pending_line() -> String:
	if not awaiting_maire():
		return ""
	return String(HANDOFF_LINES.get(current_step_id(), ""))


func take_pending_line() -> String:
	var line := pending_line()
	if line == "":
		return ""
	var key := String(current_step_id())
	_briefed = true
	note_line(key, line)
	print("RAID_STEP_UNLOCKED id=%s" % key)
	_on_step_unlocked(current_step_id())
	step_changed.emit(current_step_id(), true)
	return line


## Máire says nothing idle in the twilight (her hands are full); the hub only plays real lines.
func idle_line() -> String:
	return ""


func note_line(key: String, text: String) -> void:
	print("RAID_LINE key=%s line=%s" % [key, text])
	line_spoken.emit(key, text)


func complete_step(id: StringName) -> bool:
	if not is_step_active(id):
		return false
	_index += 1
	_briefed = not HANDOFF_LINES.has(current_step_id())
	print("RAID_STEP_DONE id=%s next=%s awaiting_maire=%s" % [id, current_step_id(), awaiting_maire()])
	step_changed.emit(current_step_id(), _briefed)
	return true


# ---------------------------------------------------------------- reports from the chores

func report_supper_given() -> void:
	_herd_hand.call("face_yaw", HH_BANK_YAW)
	_beat = "clamp_line"
	_beat_t = 0.0


func report_cow_penned() -> void:
	_cow_penned = true
	_check_penning()


func report_wood_in() -> void:
	_wood_in = true
	_check_penning()


func report_hatchet_stowed() -> void:
	_hatchet_stowed = true


func cow_penned() -> bool:
	return _cow_penned


func wood_in() -> bool:
	return _wood_in


func hatchet_stowed() -> bool:
	return _hatchet_stowed


func _check_penning() -> void:
	if _cow_penned and _wood_in and is_step_active(&"penning"):
		complete_step(&"penning")
		_beat = "night_pending"


# ---------------------------------------------------------------- nodes (smoke / capture)

func boy() -> Node3D:
	return _boy


func herd_hand() -> Node3D:
	return _herd_hand


func supper_chore() -> Node3D:
	return _supper


func wood_chore() -> Node3D:
	return _wood


func haze() -> Node3D:
	return _haze


## Light for OpeningTimeOfDay: 2 = dusk (the meal) … 3 = twilight (the last chores).
func time_progress() -> float:
	if not _running:
		return 2.0
	match current_step_id():
		&"news":
			return 2.2
		&"supper":
			return 2.55
		&"penning":
			return 2.55 if not _briefed else 2.85
	return 3.0


# ---------------------------------------------------------------- start

func start_now() -> void:
	if _running:
		return
	_start_left = -1.0
	_running = true
	_index = 0
	_briefed = true
	_beat = "boy_in"
	_beat_t = 0.0
	# Counted present at the Bannow landing before day 0 resolves (invisible to the player).
	var wc := get_node_or_null("/root/WorldClock")
	if wc and wc.has_method("set_player_present"):
		wc.call("set_player_present", &"bannow_bay_landing", true)
	_spawn_cast()
	if _maire:
		_maire_door_yaw = _maire.rotation.y
	# Máire goes to the milk cow at the post and settles to milk her.
	if _maire:
		var route: Array = MAIRE_ROUTE.duplicate()
		route.append(MILK_SPOT)
		_maire.call("walk_route", route, MILK_YAW)
	# He sits on at the meal stool, as she bade him.
	_try_sit()
	print("RAID_SEQUENCE_START step=news")
	step_changed.emit(current_step_id(), true)


func _spawn_cast() -> void:
	var root := get_parent()
	_boy = VillagerScript.new()
	_boy.name = "NeighboursBoy"
	_boy.set("display_name", "Neighbours' boy")
	_boy.set("stature_m", 1.36)   # ~10 years old
	_boy.set("walk_speed", 1.15)
	_boy.set("palette", {
		"skin": Color(0.86, 0.71, 0.6), "hair": Color(0.42, 0.26, 0.12),
		"tunic": Color(0.66, 0.6, 0.47), "skirt": Color(0.6, 0.55, 0.43),   # undyed léine
		"pants": Color(0.82, 0.67, 0.56), "shoes": Color(0.62, 0.48, 0.38),  # bare legs and feet
		"belt": Color(0.3, 0.22, 0.14), "cloak": Color(0.36, 0.3, 0.22),
		"wood": Color(0.42, 0.28, 0.14), "iron": Color(0.45, 0.48, 0.5), "wrap": Color(0.62, 0.56, 0.44),
	})
	root.add_child(_boy)
	_boy.call("place", BOY_IN[0], PI)
	_boy.call("walk_path", BOY_IN)
	_boy.call("hold_right", true)
	_sieve = _build_sieve()
	_herd_hand = VillagerScript.new()
	_herd_hand.name = "HerdHand"
	_herd_hand.set("display_name", "Herd-hand")
	_herd_hand.set("stature_m", 1.64)
	_herd_hand.set("walk_speed", 1.05)  # an old man's pace
	_herd_hand.set("palette", {
		"skin": Color(0.8, 0.64, 0.54), "hair": Color(0.62, 0.6, 0.56),
		"tunic": Color(0.5, 0.46, 0.38), "skirt": Color(0.44, 0.4, 0.33),
		"pants": Color(0.32, 0.28, 0.22), "shoes": Color(0.22, 0.16, 0.1),
		"belt": Color(0.2, 0.14, 0.09), "cloak": Color(0.3, 0.27, 0.22),
		"wood": Color(0.42, 0.28, 0.14), "iron": Color(0.45, 0.48, 0.5), "wrap": Color(0.48, 0.44, 0.36),
	})
	root.add_child(_herd_hand)
	_herd_hand.call("place", HH_BANK, HH_BANK_YAW)
	_herd_hand.call("face_yaw", HH_BANK_YAW)
	_supper = SupperScript.new()
	_supper.name = "PrologueSupperChore"
	add_child(_supper)
	_supper.call("set_herd_hand", _herd_hand)
	_wood.call("set_herd_hand", _herd_hand)
	_haze = HazeScript.new()
	_haze.name = "PrologueHaze"
	add_child(_haze)


func _try_sit() -> void:
	if _sat_for_news or _player == null:
		return
	# Only if he has stayed by the stool with empty hands since the meal (he "sits on"). A player
	# who has walked off or taken up the goad is left alone: the boy comes to him by the door.
	var p := _player.global_position
	if Vector2(p.x - SEAT_POS.x, p.z - SEAT_POS.z).length() > SIT_STAY_RADIUS:
		return
	if bool(_player.call("is_input_locked")) or bool(_player.call("is_carrying")) or bool(_player.call("is_leading")):
		return
	var combat := _player.get_node_or_null("CombatSystem")
	if combat and int(combat.get("current_weapon")) != 3:
		return
	if (_player as CharacterBody3D) and Vector2((_player as CharacterBody3D).velocity.x, (_player as CharacterBody3D).velocity.z).length() > 0.2:
		return
	if bool(_player.call("begin_seat", SEAT_POS, SEAT_YAW)):
		_sat_for_news = true
		print("RAID_NEWS_CIAN_SITS")


# ---------------------------------------------------------------- tick

func _process(delta: float) -> void:
	if _start_left > 0.0:
		_start_left -= delta
		if _start_left <= 0.0:
			start_now()
		return
	if not _running:
		return
	_beat_t += delta
	match _beat:
		"boy_in":
			_tick_maire_to_milking()
			if not bool(_boy.call("is_walking")):
				_place_sieve()
				_boy.call("hold_right", false)
				_boy.call("walk_path", [BOY_TALK])
				_next_beat("boy_set_down")
		"boy_set_down":
			_tick_maire_to_milking()
			if not bool(_boy.call("is_walking")):
				_boy.call("face_point", _player.global_position if _player else SEAT_POS)
				# He speaks when Cian is by (sat at the stool, or back near the house).
				if _player and Vector2(_player.global_position.x - BOY_TALK.x, _player.global_position.z - BOY_TALK.z).length() <= SIT_RADIUS + 1.0 and _beat_t > 0.6:
					_boy.call("say", BOY_LINE, 6.5)
					note_line("boy", BOY_LINE)
					_next_beat("boy_talk")
		"boy_talk":
			_tick_maire_to_milking()
			if _beat_t > 2.6 and _maire and float(_maire.call("milk_pause_left")) <= 0.0 and not _paused_once:
				# A moment's pause at the milking — then the normal routine.
				_paused_once = true
				_maire.call("pause_milking", 2.2)
				print("RAID_NEWS_MAIRE_PAUSE")
			if _beat_t > 7.0:
				_boy.call("walk_path", BOY_OUT)
				if _player and bool(_player.call("is_seated")):
					_player.call("end_seat")
				_next_beat("boy_out")
		"boy_out":
			_tick_maire_to_milking()
			var bp: Vector3 = _boy.global_position
			if bp.z > 15.5 or _beat_t > 14.0:
				complete_step(&"news")
				if _maire:
					_maire.call("say_line", "supper", SUPPER_LINE, 6.0)
				_next_beat("supper")
		"supper":
			_tick_boy_gone()
		"clamp_line":
			_tick_boy_gone()
			if _beat_t > 0.8:
				_herd_hand.call("say", CLAMP_LINE, 5.0)
				note_line("herd_hand", CLAMP_LINE)
				complete_step(&"supper")
				_next_beat("back_to_maire")
				# She has finished the milking: up off the stool, pail by her.
				if _maire:
					_maire.call("set_milking", false)
		"back_to_maire":
			_tick_boy_gone()
		"penning":
			_tick_boy_gone()
			_tick_maire_to_door()
			if not _hh_down_started and _beat_t > 1.5:
				_hh_down_started = true
				_herd_hand.call("hold_right", false)
				_supper.call("hide_prop")
				if String(_wood.call("hatchet_state")) == "in_block":
					_herd_hand.call("walk_path", HH_DOWN)
		"night_pending":
			_tick_maire_to_door()
			# The night only comes on once the yard is settled: the hatchet away in the byre too.
			if _player and _maire and not _night and _hatchet_stowed:
				var mp := _maire.global_position
				if Vector2(_player.global_position.x - mp.x, _player.global_position.z - mp.z).length() <= NIGHT_RADIUS and not bool(_maire.call("is_walking")):
					_night = true
					_beat = "night"
					print("RAID_CHUNK1_NIGHT_REACHED")
					night_reached.emit()


var _paused_once: bool = false
var _maire_door_yaw: float = 0.36
var _maire_at_milk: bool = false
var _maire_to_door: bool = false


func _on_step_unlocked(id: StringName) -> void:
	if id == &"penning":
		_next_beat("penning")
		# Pail in hand, she goes in to the door; the cow is free to be untied.
		if _maire:
			_maire.call("carry_pail", true)
			var back: Array = MAIRE_ROUTE.duplicate()
			back.reverse()
			back.append(MAIRE_DOOR)
			_maire.call("walk_route", back, _maire_door_yaw)
			_maire_to_door = true


func _tick_maire_to_milking() -> void:
	if _maire_at_milk or _maire == null:
		return
	if not bool(_maire.call("is_walking")):
		_maire_at_milk = true
		_maire.call("set_milking", true)


func _tick_maire_to_door() -> void:
	if _maire_to_door and _maire and not bool(_maire.call("is_walking")):
		_maire_to_door = false
		_maire.call("carry_pail", false)


func _tick_boy_gone() -> void:
	if _boy and is_instance_valid(_boy) and not bool(_boy.call("is_walking")):
		_boy.queue_free()
		_boy = null
		print("RAID_NEWS_BOY_GONE_HOME")


func _next_beat(b: String) -> void:
	_beat = b
	_beat_t = 0.0
	print("RAID_BEAT %s" % b)


# ---------------------------------------------------------------- HUD objective

func objective_text() -> String:
	if not _running:
		return ""
	if awaiting_maire():
		return "Go back to Máire — she's at the milking by the post, and she has the next job."
	match current_step_id():
		&"news":
			if _beat == "boy_set_down" and _player and not bool(_player.call("is_seated")):
				return "The neighbours' boy has come in at the gate. He's by the house door."
			return "Sit and rest a while. The neighbours' boy has come in at the gate."
		&"supper":
			return String(_supper.call("objective_text")) if _supper else ""
		&"penning":
			var bits: Array[String] = []
			if not _cow_penned and _tie:
				bits.append(String(_tie.call("objective_text")))
			if not _wood_in:
				bits.append(String(_wood.call("objective_text")))
			return "  ".join(bits)
		&"night":
			if _night:
				return "The day is done. Night comes on."
			return "That's the last of the day's work. Go in to Máire at the house door."
	return ""


# ---------------------------------------------------------------- props

## A sieve: a bent-wood hoop with a woven horsehair floor (borrowed, and brought back).
func _build_sieve() -> Node3D:
	var s := Node3D.new()
	s.name = "Sieve"
	get_parent().add_child(s)
	var hoop := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.2
	tm.bottom_radius = 0.2
	tm.height = 0.08
	tm.radial_segments = 16
	hoop.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.58, 0.45, 0.28)
	m.roughness = 0.9
	hoop.material_override = m
	s.add_child(hoop)
	var floor_mi := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.19
	fm.bottom_radius = 0.19
	fm.height = 0.01
	floor_mi.mesh = fm
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = Color(0.25, 0.2, 0.15)
	floor_mi.material_override = m2
	floor_mi.position = Vector3(0, -0.02, 0)
	s.add_child(floor_mi)
	_sieve_follow = true
	return s


var _sieve_follow: bool = false


func _physics_process(_delta: float) -> void:
	if _sieve_follow and _sieve and _boy and is_instance_valid(_boy):
		var hand: Node3D = _boy.call("right_hand")
		if hand:
			# Carried flat in front of him by the rim.
			_sieve.global_transform = Transform3D(Basis(Vector3.UP, _boy.global_rotation.y), hand.global_position + Vector3(0.0, -0.02, 0.0) + _boy.global_transform.basis * Vector3(0.0, 0.0, -0.16))


func _place_sieve() -> void:
	_sieve_follow = false
	if _sieve:
		_sieve.global_transform = Transform3D(Basis(Vector3.UP, 0.5), Terrain.surface_point(SIEVE_POS, 0.04))
		print("RAID_NEWS_SIEVE_RETURNED")
