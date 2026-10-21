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
##
## Chunk 2 (spec steps 4–6), the night and first light of day 1:
##   night (end of 3) on `night_reached`: the screen goes down to black; under it the day turns
##              (WorldClock.advance_day → day 1), Cian is asleep on a rush pallet across the doorway
##              under the eave (the greybox house is a closed drum: doorway framing, conflict 6.15),
##              the light is set to first light (OpeningTimeOfDay stage 4, grey with ground mist),
##              and the screen comes up again.
##   4 wake    (C) off-screen, in order: the dog barking at the gate; a yelp, then nothing; the cattle
##              shifting in the pen and one lowing; far down the lane a horse blowing, harness, men's
##              low voices not in Irish; then Máire from inside (locked line). Captions carry the
##              sounds. He gets up (any move key / E / Space) once the barking has started.
##   5 look    (P) crouched up the inside of the bank by the gate and look down the lane: the party
##              (PrologueRaiders) coming up through the mist. Seen by the guide or the rider (ALERT)
##              before he is back down in the yard → Game.prologue_outcome.seen = true,
##              HeatTracker.note_pre_raid_alert, they hurry to a nearer hold and the archers nock;
##              unseen → seen = false and they come on at a walk to the far hold.
##   6 knife   (P) Máire is up at the door with Cian's sister holding her léine; her locked shout. The
##              knife off its peg on the door jamb (PrologueKnifePeg: the first knife in the game —
##              combat.knife_in_kit, alias knife_carried, turns true only there) and his sister by the
##              hand (PrologueHandHold). Both done → step `out`. Nobody in the party is watching for
##              him while he is at the door (the spec has no seen in step 6: raiders.set_watch(false)).
##
## Chunk 3 (spec steps 7–8), first light of day 1:
##   7 out     (P) lead Máire and the girl out by the gate (the only way out) and west along the outer
##              ditch past the spring scoop into the wood edge (~35 m) before the party reaches the
##              causeway. The herd-hand won't come: he goes to the pen gate to talk to them (locked
##              line). Máire and the girl follow on foot and crouch when he crouches. Optional: the
##              sack of meal and seed-corn by the quern (PrologueSackChore: 1.45 m/s, no sprint, goad
##              stowed). After a pause at the hold the party comes on up the lane to the gate.
##              Fail (the party at the causeway with any of them still short of clear, or Cian seen —
##              ALERT — on the run): the girl freezes in the ditch, Máire goes back for her and a
##              serjeant cuts her forearm; Cian coming up makes him break off to cover the yard →
##              maire_hurt, household_clean = false, a heat bump; no death. All in the wood unseen →
##              household_clean; sack_saved if he still has the sack.
##   attack    (anywhere from first light, Decision 6) Cian swings at one of them / lands a blow →
##              HeatTracker.raise_raid_alarm, they all turn on him (spears in, archers loose from
##              range); armour (6.16) means the goad and the knife do next to nothing; he is downed in
##              seconds → CharacterHealth.set_downed (not dead), cian_wound = deep, seen,
##              household_clean = false, the screen goes down (step 12, not built). Not a game over.
##   8 burn    (C) household in the wood and the party at the ráth: PrologueRaidBurning — the pen
##              opened and the six driven off down the lane south, the house thatch and then the byre
##              fired from a brand off the family's hearth, the herd-hand struck down at a distance
##              (herd_hand_dead), the rider on the causeway, the guide back from the fire. Stay
##              hidden; seen (breaking cover) → the attack branch, the herd outcome unchanged.
##              Both roofs going, the herd away and the herd-hand down → done (chunk 3 ends; step 9
##              is not built).
## Name tags: the old world labels (Meal, Tie post, Trough, the stray's, the place names, Máire's
## and the herd-hand's names) are hidden for the whole prologue; spoken barks still show.

signal step_changed(step_id: StringName, briefed: bool)
signal line_spoken(key: String, text: String)
signal night_reached
signal dawn_reached
signal household_ready

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const VillagerScript := preload("res://scripts/prologue/prologue_villager.gd")
const SupperScript := preload("res://scripts/prologue/prologue_supper_chore.gd")
const WoodScript := preload("res://scripts/prologue/prologue_wood_chore.gd")
const HazeScript := preload("res://scripts/prologue/prologue_haze.gd")
const RaidersScript := preload("res://scripts/prologue/prologue_raiders.gd")
const PegScript := preload("res://scripts/prologue/prologue_knife_peg.gd")
const HandHoldScript := preload("res://scripts/prologue/prologue_hand_hold.gd")
const DawnSfx := preload("res://scripts/prologue/prologue_dawn_sfx.gd")
const HeatTrackerScript := preload("res://systems/stealth/heat_tracker.gd")
const SackScript := preload("res://scripts/prologue/prologue_sack_chore.gd")
const BurningScript := preload("res://scripts/prologue/prologue_raid_burning.gd")

const STEP_IDS: Array[StringName] = [&"news", &"supper", &"penning", &"night", &"wake", &"look", &"knife", &"out", &"burn"]

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
## On the tail of the bank at the gateway, just inside its west gatepost (~(1.96, 17.78)) and
## clear of it: the one place on the bank with an open view SSW down the lane (the crest further
## west carries the palisade, taller than a man).
const HH_BANK := Vector3(2.4, 0.0, 17.45)
const HH_BANK_YAW := PI - 0.26  ## kerne rig faces −Z: PI − 0.26 turns him SSW, out over the lane
const HH_DOWN: Array[Vector3] = [Vector3(1.6, 0.0, 15.2), Vector3(0.9, 0.0, 11.4), Vector3(0.9, 0.0, 0.4), Vector3(1.9, 0.0, -3.4)]
const NIGHT_RADIUS := 3.0

# ---- chunk 2: night and first light
const MAIRE_WAKE_LINE := "Cian? What's at the dog?"
const MAIRE_KNIFE_LINE := "The knife, Cian, off the peg! Take your sister and go, the wood, go to the wood!"
const FADE_OUT_SECS := 2.0
const NIGHT_HOLD_SECS := 2.4
const FADE_IN_SECS := 2.6
## Asleep on a rush pallet across the doorway, under the eave, his back to the yard (camera side),
## head to the west. Rig faces −Z: yaw 0 = facing north, into the doorway.
const SLEEP_POS := Vector3(-7.2, 0.0, 2.55)
const SLEEP_YAW := 0.0
const RISE_SECS := 1.6
## Off-screen sound cues (seconds after the screen is up): bark, yelp → silence, the cattle, the
## lane, then Máire. About 8 s in all.
const CUE_BARK := 0.8
const CUE_YELP := 3.4
const CUE_CATTLE := 4.6
const CUE_LANE := 6.1
const CUE_MAIRE := 8.2
const RISE_ALLOWED_AT := 0.8
const DOG_POS := Vector3(6.6, 0.0, 22.0)
const PEN_POS := Vector3(7.0, 0.0, 6.5)
## Step 5: the look-out place on the bank's tail inside the west gatepost (the herd-hand's spot).
const LOOK_SPOT := HH_BANK
const LOOK_RADIUS := 2.3
const LOOK_SECS := 1.5
const RATH_CENTRE := Vector3(0.5, 0.0, 3.0)
const YARD_RADIUS := 13.2   ## down off the bank, inside the ráth
const YARD_CLEAR_OF_SPOT := 4.0
## Step 6: Máire at the door with the girl; the herd-hand out by the byre's yard door.
const GIRL_AT_DOOR := Vector3(-4.75, 0.0, 3.55)
const HH_BYRE := Vector3(2.7, 0.0, -1.6)
# ---- chunk 3
const HH_LINE := "It's some mistake. They'll be wanting the lord's ráth."
const HH_TO_PEN: Array[Vector3] = [Vector3(1.2, 0.0, 2.0), Vector3(1.4, 0.0, 9.0), Vector3(5.2, 0.0, 11.3)]
const ADVANCE_DELAY_UNSEEN := 11.0  ## they wait at the hold before coming on (unseen: a careful walk)
const ADVANCE_DELAY_SEEN := 4.0     ## seen on the bank: hurrying, and soon
const CLEAR_R := 16.2               ## past the inner lip of the outer ditch = out of the gate
const CLEAR_X := -6.0               ## …and on west along the ditch, past the stretch the causeway overlooks
const WOOD_X := -32.5               ## the west wood's inner edge is x = −32.5 all the way along
## Down in the trees just inside the wood, by the gap at the north end of the west field bank (the
## bank at x −25.2 runs z 0 → 140 with no way over; the way to the wood is round its north end).
const COVER_MAIRE := Vector3(-35.6, 0.0, -8.4)
const COVER_GIRL := Vector3(-35.9, 0.0, -9.3)
const MAIRE_GAP := 1.7
const MAIRE_RUN := 2.8
const ATTACK_NEAR := 2.6            ## a swing at a raider within this → the attack branch
const DOWN_AT_HP := 20.0            ## Cian goes down rather than dying (step 12 picks him up)
const CUT_HEAT := 10.0
const BREAK_OFF_NEAR := 5.0
const BREAK_OFF_FALLBACK := 30.0
const SERJEANT_RUN := 3.0
const YARD_COVER: Array[Vector3] = [Vector3(6.4, 0.0, 15.5), Vector3(4.0, 0.0, 11.0)]
const DOWN_FADE_SECS := 2.4

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
# chunk 2
var _dawn: bool = false
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _fade_label: Label = null
var _raiders: Node3D = null
var _girl: Node3D = null
var _peg: Node3D = null
var _hand: Node3D = null
var _heat: Node = null
var _pallet: Node3D = null
var _cues_done: int = 0
var _bark_player: Node = null
var _lying: bool = false
var _rising: bool = false
var _rise_t: float = 0.0
var _looked: bool = false
var _look_t: float = 0.0
var _seen: bool = false
var _knife_taken: bool = false
var _girl_in_hand: bool = false
var _knife_shouted: bool = false
# ---- chunk 3
var _sack: Node3D = null
var _burning: Node3D = null
var _advance_left: float = -1.0
var _failed: bool = false
var _fail_reason: String = ""
var _fail_beat: String = ""
var _fail_t: float = 0.0
var _fail_serjeant: Node3D = null
var _attacked: bool = false
var _downed: bool = false
var _down_t: float = 0.0
var _in_wood: bool = false
var _sack_saved: bool = false
var _burn_started: bool = false
var _chunk3_done: bool = false
var _combat_hooked: bool = false


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
	return false  # chunk 3 ends at step 8 (step 9 not built); the hub stays with the raid sequence


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
	if _dawn:
		return 4.0  # first light (stage 4) from the night cut on
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
	_hide_name_tags()
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
		"night", "fade_out", "night_black", "fade_in", "wake", "look", "knife", "out", "burn_wait", "burn", "chunk3_done":
			_tick_chunk2(delta)


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
		&"wake":
			if _rising or _beat_t < RISE_ALLOWED_AT:
				return ""
			return "Get up."
		&"look":
			if _seen and not _looked:
				return "They've seen you. Get down off the bank, back into the yard."
			if not _looked:
				return "See what's at the dog: crouch (Ctrl) up the inside of the bank by the gate and look down the lane."
			return "Get back down into the yard before they see you." if not _seen else "They've seen you. Get down off the bank, back into the yard."
		&"knife":
			var bits: Array[String] = []
			if not _knife_taken:
				bits.append(String(_peg.call("objective_text")) if _peg else "")
			if not _girl_in_hand:
				bits.append(String(_hand.call("objective_text")) if _hand else "")
			return "  ".join(bits)
		&"out":
			if _downed:
				return ""
			if _attacked:
				return "Get away from them."
			if _fail_beat in ["freeze", "maire_back", "cut", "standover"]:
				return "Your sister has frozen in the ditch. Get back to them."
			return "Get Máire and your sister out by the gate and west along the outer ditch into the wood, before they reach the causeway."
		&"burn":
			if _downed:
				return ""
			if _attacked:
				return "Get away from them."
			return "Stay hidden at the wood edge."
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


# ================================================================ chunk 2: night and first light

func raiders() -> Node3D:
	return _raiders


func girl() -> Node3D:
	return _girl


func knife_peg() -> Node3D:
	return _peg


func hand_hold() -> Node3D:
	return _hand


func heat_tracker() -> Node:
	return _heat


func is_dawn() -> bool:
	return _dawn


func is_lying() -> bool:
	return _lying


func has_looked() -> bool:
	return _looked


func was_seen() -> bool:
	return _seen


func fade_alpha() -> float:
	return _fade_rect.color.a if _fade_rect else 0.0


## Smoke / capture: chunk 1 done the quick way. Running, the cast out, the day's work counted done
## (cow penned, wood in, hatchet in the byre), Máire at the door: the next time Cian is by her,
## `night_reached` fires as in play.
func debug_jump_to_night_pending() -> void:
	if not _running:
		start_now()
	if _boy and is_instance_valid(_boy):
		_boy.queue_free()
		_boy = null
	if _player and bool(_player.call("is_seated")):
		_player.call("end_seat")
	_index = STEP_IDS.find(&"night")
	_briefed = true
	_cow_penned = true
	_wood_in = true
	_hatchet_stowed = true
	if _supper:
		_supper.call("hide_prop")
	if _herd_hand:
		_herd_hand.call("place", HH_BYRE, PI * 0.5)
	if _maire:
		_maire.call("set_milking", false)
		_maire.call("place_at", MAIRE_DOOR, _maire_door_yaw)
	_maire_to_door = false
	_next_beat("night_pending")
	step_changed.emit(current_step_id(), true)


func report_knife_taken() -> void:
	_knife_taken = true
	_check_household()


func report_girl_in_hand() -> void:
	_girl_in_hand = true
	_check_household()


func _check_household() -> void:
	if _knife_taken and _girl_in_hand and is_step_active(&"knife"):
		complete_step(&"knife")
		_next_beat("out")
		print("RAID_CHUNK2_HOUSEHOLD_READY seen=%s" % _seen)
		household_ready.emit()
		_setup_out_step()


func _tick_chunk2(delta: float) -> void:
	match _beat:
		"night":
			# Straight on from `night_reached`: the screen goes down.
			_ensure_fade()
			if _player:
				_player.call("begin_cinematic")
			_next_beat("fade_out")
		"fade_out":
			_fade_rect.color.a = clampf(_beat_t / FADE_OUT_SECS, 0.0, 1.0)
			if _beat_t >= FADE_OUT_SECS:
				_night_cut()
				_next_beat("night_black")
		"night_black":
			_fade_rect.color.a = 1.0
			_fade_label.modulate.a = clampf(minf(_beat_t / 0.6, (NIGHT_HOLD_SECS - _beat_t) / 0.6), 0.0, 1.0)
			_hold_sleep_pose()
			if _beat_t >= NIGHT_HOLD_SECS:
				_fade_label.modulate.a = 0.0
				complete_step(&"night")
				_raiders.call("start")
				print("RAID_DAWN_REACHED day=%d" % _world_day())
				dawn_reached.emit()
				_next_beat("fade_in")
		"fade_in":
			_fade_rect.color.a = 1.0 - clampf(_beat_t / FADE_IN_SECS, 0.0, 1.0)
			_hold_sleep_pose()
			if _beat_t >= FADE_IN_SECS:
				_fade_rect.color.a = 0.0
				_fade_layer.visible = false
				_next_beat("wake")
		"wake":
			_tick_wake_cues(delta)
			_tick_rise(delta)
		"look":
			_tick_wake_cues(delta)
			_tick_look(delta)
			_tick_seen()
		"knife":
			_tick_seen()
			if not _knife_shouted and _maire and _beat_t > 0.4:
				_knife_shouted = true
				_maire.call("say_line", "maire_knife", MAIRE_KNIFE_LINE, 7.0)
		"out":
			_tick_out(delta)
		"burn_wait", "burn", "chunk3_done":
			_tick_burn(delta)
	_tick_downed(delta)


func _world_day() -> int:
	var wc := get_node_or_null("/root/WorldClock")
	return int(wc.get("day")) if wc else -1


# ---------------------------------------------------------------- the night cut

func _ensure_fade() -> void:
	if _fade_layer:
		_fade_layer.visible = true
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "NightFadeLayer"
	_fade_layer.layer = 60
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	_fade_label = Label.new()
	_fade_label.text = "The short night."
	_fade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.add_theme_font_size_override("font_size", 30)
	_fade_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.7))
	_fade_label.modulate.a = 0.0
	_fade_layer.add_child(_fade_label)


## Under the black: the day turns, the light is first light, Cian is asleep across the doorway and
## the party is on the lane. Máire is inside asleep (not shown); the herd-hand is in the byre.
func _night_cut() -> void:
	_dawn = true
	var wc := get_node_or_null("/root/WorldClock")
	if wc and wc.has_method("advance_day"):
		wc.call("advance_day", 1)
	var tod := get_tree().get_first_node_in_group("opening_time_of_day")
	if tod and tod.has_method("debug_set_progress"):
		tod.call("debug_set_progress", 4.0)
	if _maire:
		_maire.call("place_at", MAIRE_DOOR + Vector3(0.0, 0.0, -0.6), _maire_door_yaw)
		_maire.visible = false
	if _herd_hand:
		_herd_hand.call("place", HH_BYRE, PI * 0.5)
		_herd_hand.visible = false
	if _supper:
		_supper.call("hide_prop")
	# The evening's haze to the SSW was the day before; by first light it is gone in the mist.
	if _haze:
		_haze.visible = false
	_spawn_dawn_cast()
	_lay_down()
	print("RAID_NIGHT_CUT day=%d stage=first_light" % _world_day())


func _spawn_dawn_cast() -> void:
	var root := get_parent()
	_heat = HeatTrackerScript.new()
	_heat.name = "HeatTracker"
	add_child(_heat)
	# The heat readout is a debug/raid HUD; nothing of it shows in the prologue.
	var hud := _heat.get_node_or_null("HeatHUDLayer") as CanvasLayer
	if hud:
		hud.visible = false
	var wl := get_node_or_null("HeatWorldLabel") as Node3D
	if wl:
		wl.visible = false
	_raiders = RaidersScript.new()
	_raiders.name = "PrologueRaiders"
	root.add_child(_raiders)
	_raiders.connect("spotted", _on_raiders_spotted)
	_girl = VillagerScript.new()
	_girl.name = "Sister"
	_girl.set("display_name", "")   # unnamed in the spec: no name tag over her
	_girl.set("stature_m", 1.34)   # ~9–10 years old
	_girl.set("walk_speed", 1.1)
	_girl.set("beardless", true)
	_girl.set("palette", {
		"skin": Color(0.87, 0.72, 0.62), "hair": Color(0.5, 0.3, 0.14),
		"tunic": Color(0.72, 0.66, 0.52), "skirt": Color(0.7, 0.64, 0.5),   # undyed léine, ankle-long
		"pants": Color(0.7, 0.64, 0.5), "shoes": Color(0.8, 0.64, 0.54),    # bare feet
		"belt": Color(0.4, 0.3, 0.2), "cloak": Color(0.36, 0.32, 0.4),      # a small brat
		"wood": Color(0.42, 0.28, 0.14), "iron": Color(0.45, 0.48, 0.5), "wrap": Color(0.7, 0.64, 0.5),
	})
	root.add_child(_girl)
	_girl.call("place", GIRL_AT_DOOR + Vector3(0.0, 0.0, -0.7), MAIRE_DOOR_YAW)
	_girl.visible = false
	_peg = PegScript.new()
	_peg.name = "PrologueKnifePeg"
	add_child(_peg)
	_hand = HandHoldScript.new()
	_hand.name = "PrologueHandHold"
	add_child(_hand)
	_hand.call("set_girl", _girl)
	# A rush pallet on the ground across the doorway.
	_pallet = MeshInstance3D.new()
	_pallet.name = "RushPallet"
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 0.06, 0.8)
	(_pallet as MeshInstance3D).mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.3)
	m.roughness = 1.0
	(_pallet as MeshInstance3D).material_override = m
	root.add_child(_pallet)
	_pallet.global_position = Terrain.surface_point(SLEEP_POS, 0.03)
	_sack = SackScript.new()
	_sack.name = "PrologueSackChore"
	add_child(_sack)
	_raiders.connect("struck", _on_raiders_struck)
	_hook_combat()
	_hide_name_tags()


func _sleep_pose(w: float) -> Dictionary:
	# Lying on his left side, knees drawn up: the whole rig rolled 90° about its forward axis so
	# the head goes west (rig −X), lifted and shifted so he lies along the pallet.
	return {
		"root": Vector3(0.0, 0.0, PI * 0.5 * w),
		"root_pos": Vector3(0.92 * w, 0.17 * w, 0.0),
		"left_thigh": Vector3(0.75 * w, 0.0, 0.0), "right_thigh": Vector3(0.6 * w, 0.0, 0.0),
		"left_shin": Vector3(-1.0 * w, 0.0, 0.0), "right_shin": Vector3(-0.9 * w, 0.0, 0.0),
		"left_arm": Vector3(0.9 * w, 0.0, 0.0), "right_arm": Vector3(0.5 * w, 0.0, 0.0),
		"left_forearm": Vector3(0.6 * w, 0.0, 0.0), "right_forearm": Vector3(0.7 * w, 0.0, 0.0),
		"head": Vector3(0.15 * w, 0.0, 0.0),
	}


func _lay_down() -> void:
	if _player == null:
		return
	if bool(_player.call("is_seated")):
		_player.call("end_seat")
	var combat := _player.get_node_or_null("CombatSystem")
	if combat and combat.has_method("set_weapon"):
		combat.call("set_weapon", 3)  # the goad laid by (on his back on the rig)
	var body := _player as CharacterBody3D
	_player.global_position = Terrain.surface_point(SLEEP_POS, 0.05)
	_player.rotation.y = SLEEP_YAW
	if body:
		body.velocity = Vector3.ZERO
	var pivot := _player.get_node_or_null("CameraPivot") as Node3D
	if pivot:
		pivot.rotation.x = deg_to_rad(-14.0)
	_lying = true
	_rising = false
	_player.call("set_cinematic_pose", _sleep_pose(1.0))


func _hold_sleep_pose() -> void:
	if _lying and not _rising and _player:
		_player.call("set_cinematic_pose", _sleep_pose(1.0))


# ---------------------------------------------------------------- step 4: wake

func _tick_wake_cues(delta: float) -> void:
	_wake_clock += delta
	var cues := [CUE_BARK, CUE_YELP, CUE_CATTLE, CUE_LANE, CUE_MAIRE]
	while _cues_done < cues.size() and _wake_clock >= float(cues[_cues_done]):
		_play_cue(_cues_done)
		_cues_done += 1


var _wake_clock: float = 0.0


func _play_cue(i: int) -> void:
	match i:
		0:
			_bark_player = DawnSfx.play(self, &"bark", DOG_POS, 2.0, 10.0)
			_caption("[Out by the gate, the dog is barking hard.]", 2.6)
			print("RAID_WAKE_CUE bark")
		1:
			if _bark_player and is_instance_valid(_bark_player):
				_bark_player.call("stop")
			DawnSfx.play(self, &"yelp", DOG_POS, 2.0, 10.0)
			_caption("[A yelp, and the barking stops. Nothing.]", 1.4)
			print("RAID_WAKE_CUE yelp")
		2:
			DawnSfx.play(self, &"low", PEN_POS, -2.0, 8.0)
			_caption("[In the pen the cattle shift and blow. One lows.]", 1.5)
			print("RAID_WAKE_CUE cattle")
		3:
			var lane: Vector3 = (_raiders.call("lane_point", float(_raiders.call("head_s"))) as Array)[0] if _raiders else Vector3(0, 0, 90)
			DawnSfx.play(self, &"blow", lane, 6.0, 30.0)
			DawnSfx.play(self, &"jingle", lane, 4.0, 30.0)
			DawnSfx.play(self, &"voices", lane, 4.0, 30.0)
			_caption("[Far down the lane: a horse blowing, harness, men's low voices. Not Irish.]", 2.0)
			print("RAID_WAKE_CUE lane")
		4:
			var line := "Máire (from inside): %s" % MAIRE_WAKE_LINE
			_caption(line, 4.5)
			note_line("maire_wake", MAIRE_WAKE_LINE)


func _caption(text: String, secs: float) -> void:
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)


func _input(event: InputEvent) -> void:
	if not _lying:
		return
	# Asleep / waking: the view stays put (no spinning the sleeper with the mouse) and any move
	# key, E or Space gets him up once the dog has started.
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return
	if _rising:
		return
	var wants := false
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump"]:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			wants = true
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_E:
		wants = true
	if wants:
		get_viewport().set_input_as_handled()
		request_rise()


## Get up (input above, or smoke). Only once the screen is up and the barking has started.
func request_rise() -> bool:
	if not _lying or _rising or _beat != "wake" or _beat_t < RISE_ALLOWED_AT:
		return false
	_rising = true
	_rise_t = 0.0
	print("RAID_WAKE_RISE_START")
	return true


func _tick_rise(delta: float) -> void:
	if not _lying:
		return
	if not _rising:
		_hold_sleep_pose()
		return
	_rise_t += delta
	var u := clampf(_rise_t / RISE_SECS, 0.0, 1.0)
	# Up on an elbow, then to a knee, then standing: ease the lying offsets out.
	var w := 1.0 - u * u * (3.0 - 2.0 * u)
	var pose := _sleep_pose(w)
	if u < 0.85:
		var k := sin(u / 0.85 * PI)
		pose["right_thigh"] = Vector3(0.6 * w + 0.9 * k, 0.0, 0.0)
		pose["right_shin"] = Vector3(-0.9 * w - 1.1 * k, 0.0, 0.0)
	_player.call("set_cinematic_pose", pose)
	if u >= 1.0:
		_lying = false
		_rising = false
		_player.call("end_cinematic")
		print("RAID_WAKE_RISEN")
		complete_step(&"wake")
		_next_beat("look")


# ---------------------------------------------------------------- step 5: the look from the bank

func _tick_look(delta: float) -> void:
	if _player == null:
		return
	var p := _player.global_position
	var d_spot := Vector2(p.x - LOOK_SPOT.x, p.z - LOOK_SPOT.z).length()
	if not _looked:
		# At the look-out place on the bank's tail by the west gatepost (the one open view SSW down
		# the lane; further west the palisade stands on the crest).
		if d_spot <= LOOK_RADIUS:
			_look_t += delta
			if _look_t >= LOOK_SECS:
				_looked = true
				print("RAID_LOOK_DONE crouched=%s seen=%s head_s=%.1f" % [_player.get("is_crouching"), _seen, float(_raiders.call("head_s"))])
				_caption("Down the lane through the mist: men on foot, ten or so, and one on a horse. Spears, bows. In front, a man in a léine and brat, picking the way.", 6.0)
		else:
			_look_t = maxf(0.0, _look_t - delta * 0.5)
		return
	# Back down into the yard, clear of the bank.
	var d_c := Vector2(p.x - RATH_CENTRE.x, p.z - RATH_CENTRE.z).length()
	if d_c <= YARD_RADIUS and d_spot >= YARD_CLEAR_OF_SPOT:
		_finish_look()


func _finish_look() -> void:
	var g := get_node_or_null("/root/Game")
	if g:
		var o: Dictionary = g.get("prologue_outcome")
		o["seen"] = _seen
		g.set("prologue_outcome", o)
	print("RAID_LOOK_BACK_IN_YARD seen=%s" % _seen)
	complete_step(&"look")
	_next_beat("knife")
	_setup_knife_step()


## Any ALERT from the party, from the look on: the seen flag (spec: seen on the bank; it stays
## live through step 6, where the gateway still gives them a view straight up the causeway).
func _tick_seen() -> void:
	pass  # driven by the raiders' `spotted` signal


func _on_raiders_spotted(by: Node3D) -> void:
	if _seen:
		_spotted_after_look(by)
		return
	_seen = true
	var g := get_node_or_null("/root/Game")
	if g:
		var o: Dictionary = g.get("prologue_outcome")
		o["seen"] = true
		g.set("prologue_outcome", o)
	if _heat and by:
		_heat.call("note_pre_raid_alert", by)
	print("RAID_SEEN by=%s step=%s" % [by.name if by else "?", current_step_id()])
	if current_step_id() == &"look":
		_caption("The man in front is pointing up at the bank, at you. They're coming on faster now.", 4.5)
	_spotted_after_look(by)


# ---------------------------------------------------------------- step 6: the knife and the girl

func _setup_knife_step() -> void:
	if _maire:
		_maire.visible = true
		_maire.call("place_at", MAIRE_DOOR, _maire_door_yaw)
	if _girl:
		_girl.visible = true
		_girl.call("place", GIRL_AT_DOOR, MAIRE_DOOR_YAW)
		_girl.call("face_yaw", MAIRE_DOOR_YAW)
		# Holding on to her mother's léine.
		if _maire:
			_girl.call("reach_right", (_maire as Node3D).global_position + Vector3(0.0, 0.8, 0.0), 0.8)
	if _herd_hand:
		_herd_hand.visible = true
		_herd_hand.call("place", HH_BYRE, PI * 0.5)
		_herd_hand.call("face_point", Terrain.surface_point(Vector3(7.0, 0, 14.0), 0.0))
	# Step 6 has no seen: nobody below is looking for him while he is at the door.
	if _raiders:
		_raiders.call("set_watch", false)
	print("RAID_KNIFE_STEP_SETUP")


# ================================================================ chunk 3: the flight and the burning

func sack_chore() -> Node3D:
	return _sack


func burning() -> Node3D:
	return _burning


func has_failed() -> bool:
	return _failed


func fail_reason() -> String:
	return _fail_reason


func fail_beat() -> String:
	return _fail_beat


func fail_serjeant() -> Node3D:
	return _fail_serjeant


func was_attacked() -> bool:
	return _attacked


func is_downed() -> bool:
	return _downed


func household_in_wood() -> bool:
	return _in_wood


func is_chunk3_done() -> bool:
	return _chunk3_done


func _outcome_set(vals: Dictionary) -> void:
	var g := get_node_or_null("/root/Game")
	if g == null:
		return
	var o: Dictionary = g.get("prologue_outcome")
	for k in vals.keys():
		o[k] = vals[k]
	g.set("prologue_outcome", o)


## Every Label3D in the scene that names a thing (old greybox / world tags, Máire's and the
## herd-hand's names) goes; speech ("Bark") and the cattle's lowing stay.
func _hide_name_tags() -> void:
	var root := get_tree().current_scene if get_tree().current_scene else get_parent()
	var n := 0
	for l in root.find_children("*", "Label3D", true, false):
		var lb := l as Label3D
		if lb.name == "Bark" or lb.name == "Lowing":
			continue
		if lb.visible:
			n += 1
		lb.visible = false
	print("RAID_NAME_TAGS_HIDDEN n=%d" % n)


func _setup_out_step() -> void:
	if _herd_hand:
		_herd_hand.call("say", HH_LINE, 6.0)
		note_line("herd_hand_out", HH_LINE)
		_herd_hand.call("walk_path", HH_TO_PEN, 1.05)
	if _maire:
		_maire.call("follow", _player, MAIRE_GAP, MAIRE_RUN)
	if _raiders:
		_raiders.call("set_watch", true)
	_advance_left = ADVANCE_DELAY_SEEN if _seen else ADVANCE_DELAY_UNSEEN
	_hide_name_tags()
	print("RAID_OUT_STEP_SETUP seen=%s advance_in=%.1f" % [_seen, _advance_left])


func _crouch_sync() -> void:
	if _player == null:
		return
	var c := bool(_player.get("is_crouching"))
	if _maire and _maire.call("following") != null:
		_maire.call("set_crouch", c)
	if _girl and _hand and not bool(_hand.call("is_frozen")):
		_girl.call("set_crouch", c)


func _clear(p: Vector3) -> bool:
	return Vector2(p.x - RATH_CENTRE.x, p.z - RATH_CENTRE.z).length() > CLEAR_R and p.x < CLEAR_X


func household_clear() -> bool:
	return _player and _maire and _girl and _clear(_player.global_position) and _clear(_maire.global_position) and _clear(_girl.global_position)


func _in_wood_now() -> bool:
	return _player and _maire and _girl and _player.global_position.x < WOOD_X and _maire.global_position.x < WOOD_X and _girl.global_position.x < WOOD_X


func _tick_advance(delta: float) -> void:
	if _advance_left > 0.0:
		_advance_left -= delta
		if _advance_left <= 0.0 and _raiders and not _attacked:
			_raiders.call("advance")


func _tick_out(delta: float) -> void:
	_tick_advance(delta)
	if _downed:
		return
	_crouch_sync()
	if not _failed and not _attacked and _raiders and bool(_raiders.call("reached_causeway")) and not household_clear():
		_start_fail("causeway")
	_tick_fail(delta)
	if not _in_wood and _fail_beat not in ["freeze", "maire_back", "cut", "standover"] and _in_wood_now():
		_reach_wood()


func _reach_wood() -> void:
	_in_wood = true
	_sack_saved = _sack != null and bool(_sack.call("is_carried"))
	var clean := not _failed and not _attacked
	_outcome_set({"household_clean": clean, "sack_saved": _sack_saved, "seen": _seen})
	print("RAID_HOUSEHOLD_IN_WOOD clean=%s sack_saved=%s seen=%s failed=%s" % [clean, _sack_saved, _seen, _failed])
	# Down in the trees at the edge, crouched; he is free to watch or pull back.
	if _maire:
		_maire.call("run_to", COVER_MAIRE, 1.4)
		_maire.call("set_crouch", true)
	if _girl:
		if _hand and bool(_hand.call("is_in_hand")):
			_hand.call("let_go")
		_girl.call("follow", null, Vector3.ZERO, 0.0)
		_girl.call("walk_path", [COVER_GIRL], 1.2)
		_girl.call("set_crouch", true)
	complete_step(&"out")
	_next_beat("burn_wait")


# ---------------------------------------------------------------- step 7 fail

func _spotted_after_look(by: Node3D) -> void:
	match current_step_id():
		&"out":
			if _heat and by:
				_heat.call("note_raid_alert", by)
			if not _failed and not _attacked and not _in_wood:
				_start_fail("seen")
		&"burn":
			if not _attacked:
				_start_attack("broke_cover")


func _start_fail(reason: String) -> void:
	_failed = true
	_fail_reason = reason
	_fail_beat = "freeze"
	_fail_t = 0.0
	if reason == "seen":
		_seen = true
		_outcome_set({"seen": true})
	if _hand:
		_hand.call("freeze")
	# The nearest serjeant comes for her.
	var best: Node3D = null
	var bd := INF
	for m in _raiders.call("men_with_role", &"serjeant"):
		var d := (m as Node3D).global_position.distance_to(_girl.global_position)
		if d < bd:
			bd = d
			best = m
	_fail_serjeant = best
	if best:
		_raiders.call("release", best)
	if _maire:
		_maire.call("run_to", _girl.global_position + Vector3(0.5, 0, 0.3), MAIRE_RUN)
	print("RAID_FAIL reason=%s girl_at=%s" % [reason, _girl.global_position])
	_caption("Your sister has frozen down in the ditch and won't move. Máire is going back for her.", 5.0)


func _tick_fail(delta: float) -> void:
	if not _failed or _fail_beat == "" or _fail_beat == "resumed":
		return
	_fail_t += delta
	var s := _fail_serjeant
	var gp := _girl.global_position
	match _fail_beat:
		"freeze":
			if s:
				s.call("walk_path", [gp + (s.global_position - gp).normalized() * 1.6], SERJEANT_RUN)
				s.call("level_spear", gp + Vector3(0, 0.9, 0), 1.0 if s.global_position.distance_to(gp) < 7.0 else 0.0)
			var md := Vector2(_maire.global_position.x - gp.x, _maire.global_position.z - gp.z).length()
			if md < 1.0:
				_maire.call("set_crouch", true)
				_fail_beat = "maire_back"
				_fail_t = 0.0
		"maire_back":
			if s:
				s.call("walk_path", [gp + (s.global_position - gp).normalized() * 1.6], SERJEANT_RUN)
				s.call("level_spear", _maire.global_position + Vector3(0, 0.9, 0), 1.0)
			if s == null or s.global_position.distance_to(gp) < 2.1:
				_fail_beat = "cut"
				_fail_t = 0.0
		"cut":
			if s:
				s.call("face_point", _maire.global_position)
				s.call("level_spear", _maire.global_position + Vector3(0, 0.9 + 0.2 * sin(_fail_t * 12.0), 0), 1.0)
			if _fail_t > 0.35:
				_maire.call("set_forearm_cut", true)
				_outcome_set({"maire_hurt": true, "household_clean": false})
				if _heat:
					_heat.call("bump", CUT_HEAT, &"maire_cut")
				print("RAID_MAIRE_CUT heat=%.1f" % float(_heat.get("heat")) if _heat else "RAID_MAIRE_CUT")
				_caption("A serjeant's spear opens Máire's forearm as she pulls your sister in to her. He stands over them.", 5.5)
				_fail_beat = "standover"
				_fail_t = 0.0
		"standover":
			if s:
				s.call("face_point", gp)
				s.call("level_spear", gp + Vector3(0, 0.7, 0), 1.0)
			var near := _player and Vector2(_player.global_position.x - gp.x, _player.global_position.z - gp.z).length() <= BREAK_OFF_NEAR
			if near or _fail_t > BREAK_OFF_FALLBACK:
				# He breaks off to cover the yard: the household are nothing to him beside the cattle.
				if s:
					s.call("level_spear", Vector3.ZERO, 0.0)
					s.call("walk_path", YARD_COVER, 2.2)
				_maire.call("set_crouch", false)
				_maire.call("follow", _player, MAIRE_GAP, MAIRE_RUN)
				_hand.call("resume")
				_girl.call("set_crouch", false)
				print("RAID_SERJEANT_BROKE_OFF near=%s" % near)
				if near:
					_caption("He sees you coming and breaks off, back to cover the yard.", 4.0)
				_fail_beat = "resumed"


# ---------------------------------------------------------------- attack branch

func _hook_combat() -> void:
	if _combat_hooked or _player == null:
		return
	var c: Node = _player.get("combat")
	if c == null:
		return
	_combat_hooked = true
	c.connect("attack_performed", _on_player_attack)
	c.connect("hit_landed", _on_player_hit)


func _on_player_attack(_attacker: Node, _kind: StringName, _weapon: StringName) -> void:
	if _attacked or _raiders == null or _player == null:
		return
	for m in _raiders.get("men"):
		if (m as Node3D).global_position.distance_to(_player.global_position) <= ATTACK_NEAR:
			_start_attack("swing")
			return


func _on_player_hit(_attacker: Node, target: Node, _dmg: float, _kind: StringName) -> void:
	if _attacked or _raiders == null:
		return
	if target in _raiders.get("men"):
		_start_attack("hit")


func _start_attack(reason: String) -> void:
	if _attacked or _downed:
		return
	_attacked = true
	_seen = true
	_outcome_set({"seen": true, "household_clean": false})
	if _heat:
		_heat.call("raise_raid_alarm", StringName("cian_" + reason))
	if _raiders:
		if _burning:
			_raiders.set("busy_check", Callable(_burning, "is_busy"))
		_raiders.call("start_combat", _player)
	print("RAID_ATTACK_BRANCH reason=%s step=%s" % [reason, current_step_id()])
	_caption("They're all at you now: spears coming in, and the bowmen drawing.", 4.0)


func _on_raiders_struck(target: Node3D, amount: float, kind: StringName, from: Node3D) -> void:
	if _downed or target != _player:
		return
	var c: Node = _player.get("combat")
	var hp := float(c.get("health")) if c else 0.0
	if hp - amount <= DOWN_AT_HP:
		_go_down()
		return
	if c:
		c.call("apply_damage", amount, from, true)
	var ch := get_node_or_null("/root/CharacterHealth")
	if ch:
		ch.call("apply_wound_tag", &"cut")
	print("RAID_CIAN_STRUCK kind=%s hp=%.0f" % [kind, float(c.get("health")) if c else -1.0])


func _go_down() -> void:
	_downed = true
	_down_t = 0.0
	var ch := get_node_or_null("/root/CharacterHealth")
	if ch:
		ch.call("apply_wound_tag", &"deep")
		ch.call("set_downed", true)
	_outcome_set({"cian_wound": "deep", "seen": true, "household_clean": false})
	if _player:
		_player.call("begin_cinematic")
	if _raiders:
		_raiders.call("stop_combat")
	if _sack:
		_sack.call("release_if_carried")
	print("RAID_CIAN_DOWNED step=%s" % current_step_id())
	_ensure_fade()
	_fade_label.text = "Cian goes down under them."


func _tick_downed(delta: float) -> void:
	if not _downed:
		return
	_down_t += delta
	_fade_rect.color.a = clampf(_down_t / DOWN_FADE_SECS, 0.0, 1.0)
	_fade_label.modulate.a = clampf((_down_t - DOWN_FADE_SECS * 0.5) / 0.8, 0.0, 1.0)


# ---------------------------------------------------------------- step 8

func _tick_burn(delta: float) -> void:
	_tick_advance(delta)
	if _downed:
		return
	if not _burn_started and _raiders and bool(_raiders.call("has_arrived")):
		_burn_started = true
		_burning = BurningScript.new()
		_burning.name = "PrologueRaidBurning"
		add_child(_burning)
		var cows: Array = _director.call("get_cows") if _director and _director.has_method("get_cows") else []
		var gate := get_tree().get_first_node_in_group("opening_pen_gate")
		_burning.call("setup", _raiders, cows, gate, _herd_hand)
		_burning.connect("finished", _on_burning_finished)
		_burning.connect("herd_hand_struck", _on_herd_hand_struck)
		if _attacked:
			_raiders.set("busy_check", Callable(_burning, "is_busy"))
		_burning.call("start")
		_next_beat("burn")
		print("RAID_STEP8_START")


func _on_herd_hand_struck() -> void:
	_outcome_set({"herd_hand_dead": true})
	_caption("Out on the causeway the old man goes down. He doesn't get up.", 5.0)


func _on_burning_finished() -> void:
	_outcome_set({"herd_hand_dead": true})
	_chunk3_done = true
	complete_step(&"burn")
	_next_beat("chunk3_done")
	var g := get_node_or_null("/root/Game")
	print("RAID_CHUNK3_DONE outcome=%s" % [g.get("prologue_outcome") if g else {}])
