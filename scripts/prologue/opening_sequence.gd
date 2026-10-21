extends Node
## Opening morning as a SET SEQUENCE with Máire as the hub.
##
##   1 maire  — talk to Máire at the door (her talk ends by giving the bucket job)
##   2 bucket — pick up the bucket, fill it at the spring scoop, pour it at the trough
##   3 drive  — bring the herd home. ONE step, no Máire trips inside it; in-drive beats run off
##              the objective HUD line + chore flashes (OpeningDriveDirector.drive_beat()):
##                walk_out → missing (one of the six is stuck in the bog; her lowing leads there)
##                → free_her → rejoin (drive her back to the herd at the pasture) → stir
##                → driving, with the stray-dog ambush on the lane (ambush / regather)
##                → all 6 in the pen, gate latched
##   4 milk   — take the milk cow out of the pen on a rope and tie her to the post by the house by
##              hand (for the morning milking). No knife anywhere in the opening.
##   5 meal   — stow the goad and eat the meal, then Máire's closing line
##
## After each step (2..5) completes, the next step stays LOCKED until Cian walks back to Máire:
## she waves while she has a line waiting and speaks it automatically when he comes within
## OpeningFamilyCaller.TALK_RADIUS (no E). Saying the line unlocks the step. After the meal she
## has one closing line. Chores query is_step_active(id) and report complete_step(id); their own
## mechanics are unchanged. Later chores reject interaction with not_yet_text().
##
## Debug / smoke: force_advance_to(id) jumps the sequence (sequence state only — chore states
## are untouched); force_finish() marks everything done.

signal step_changed(step_id: StringName, briefed: bool)
signal line_spoken(key: String, text: String)
signal sequence_complete

const STEP_IDS: Array[StringName] = [&"maire", &"bucket", &"drive", &"milk", &"meal"]
const CLOSER_INDEX := 5

## Máire's handoff line for each step that she hands out on Cian's return (step 2's job is given
## at the end of her door talk — see OpeningFamilyCaller.talk_lines).
const HANDOFF_LINES := {
	&"drive": "Good lad. Now bring the herd home from the south pasture. All six, mind — count them into the pen.",
	&"milk": "All six home, thank God. Now bring the red milk cow out of the pen on the rope and tie her to the post by the house. I'll want her handy for the milking in the morning.",
	&"meal": "That's her tied, good lad. Put that goad away and come eat — your meal's by the door.",
}
const CLOSER_LINE := "That's the day's work done, and done well. Sit and rest a while, a stór."
const IDLE_LINE := "Go on now — the work won't do itself."

const STEP_SHORT := {
	&"maire": "talk to Máire",
	&"bucket": "water the trough",
	&"drive": "bring the herd home",
	&"milk": "tie the milk cow at the post",
	&"meal": "eat your meal",
}

var _index: int = 0
## True once Máire has given the current step's job (step 1 is "talk to her", so it starts briefed).
var _briefed: bool = true
var _finished: bool = false
var _player: Node3D = null


func _ready() -> void:
	add_to_group("opening_sequence")
	call_deferred("_announce")


func _announce() -> void:
	print("OPENING_SEQUENCE_READY step=%s" % current_step_id())


# ---------------------------------------------------------------- queries

func current_index() -> int:
	return _index


func current_step_id() -> StringName:
	if _index >= 0 and _index < STEP_IDS.size():
		return STEP_IDS[_index]
	return &"closer" if not _finished else &"finished"


## Step id is the live one: unlocked (Máire has given it) and not yet completed.
func is_step_active(id: StringName) -> bool:
	return not _finished and _index < STEP_IDS.size() and STEP_IDS[_index] == id and _briefed


func is_step_done(id: StringName) -> bool:
	var i := STEP_IDS.find(id)
	return i >= 0 and (i < _index or _finished)


## Active or already behind us (e.g. herd may still be goaded after the drive).
func is_step_open(id: StringName) -> bool:
	return is_step_active(id) or is_step_done(id)


func awaiting_maire() -> bool:
	return not _finished and not _briefed


func is_finished() -> bool:
	return _finished


## Line Máire would say next on Cian's return ("" when nothing is waiting).
func pending_line() -> String:
	if not awaiting_maire():
		return ""
	if _index >= CLOSER_INDEX:
		return CLOSER_LINE
	return String(HANDOFF_LINES.get(STEP_IDS[_index], ""))


func pending_key() -> String:
	if not awaiting_maire():
		return ""
	return "closer" if _index >= CLOSER_INDEX else String(STEP_IDS[_index])


func idle_line() -> String:
	return IDLE_LINE


func not_yet_text() -> String:
	if _finished:
		return ""
	if awaiting_maire() or _index >= CLOSER_INDEX:
		return "Not yet — go back to Máire first."
	return "Not yet — %s first." % String(STEP_SHORT.get(STEP_IDS[_index], "the job in hand"))


# ---------------------------------------------------------------- reports

## Chores report completion. Ignored (returns false) unless id is the active step.
func complete_step(id: StringName) -> bool:
	if not is_step_active(id):
		return false
	_index += 1
	# Her door talk already handed out the bucket job; every later step needs a trip back to her.
	_briefed = id == &"maire"
	print("OPENING_SEQUENCE_STEP_DONE id=%s next=%s awaiting_maire=%s" % [id, current_step_id(), awaiting_maire()])
	step_changed.emit(current_step_id(), _briefed)
	return true


## Máire delivers the waiting line (called by OpeningFamilyCaller when Cian comes close).
## Returns the text; unlocks the step (or finishes the sequence after the closer).
func take_pending_line() -> String:
	var line := pending_line()
	if line == "":
		return ""
	var key := pending_key()
	_briefed = true
	note_line(key, line)
	if _index >= CLOSER_INDEX:
		_finished = true
		print("OPENING_SEQUENCE_COMPLETE")
		sequence_complete.emit()
	else:
		print("OPENING_SEQUENCE_STEP_UNLOCKED id=%s" % current_step_id())
	step_changed.emit(current_step_id(), _briefed)
	return line


## Every line Máire speaks goes through here (smoke counts them; one print per line).
func note_line(key: String, text: String) -> void:
	print("OPENING_MAIRE_LINE key=%s line=%s" % [key, text])
	line_spoken.emit(key, text)


# ---------------------------------------------------------------- debug / smoke

## Jump to step id (sequence state only). briefed=false leaves it waiting on Máire's line.
func force_advance_to(id: StringName, briefed: bool = true) -> void:
	var i := STEP_IDS.find(id)
	if id == &"closer":
		i = CLOSER_INDEX
		briefed = false
	if i < 0:
		push_warning("OpeningSequence.force_advance_to unknown: " + String(id))
		return
	_index = i
	_briefed = briefed or i == 0
	_finished = false
	print("OPENING_SEQUENCE_FORCE step=%s briefed=%s" % [current_step_id(), _briefed])
	step_changed.emit(current_step_id(), _briefed)


func force_finish() -> void:
	_index = CLOSER_INDEX
	_briefed = true
	_finished = true
	step_changed.emit(current_step_id(), true)


# ---------------------------------------------------------------- HUD objective

func objective_text() -> String:
	if _finished:
		return "The morning's work is done. Explore the farm, or rest a while."
	if awaiting_maire():
		var what := "she has a word for you" if _index >= CLOSER_INDEX else "she has the next job"
		return "Go back to Máire at the house door — %s." % what
	match current_step_id():
		&"maire":
			return "Talk to Máire — she's waving at the house door."
		&"bucket":
			var bucket := _group("opening_bucket_trough")
			var st := String(bucket.call("bucket_state")) if bucket else "none"
			var poured := int(bucket.call("pours_done")) if bucket and bucket.has_method("pours_done") else 0
			var need := int(bucket.call("pours_needed")) if bucket and bucket.has_method("pours_needed") else 1
			match st:
				"empty":
					if poured > 0:
						return "%s — back down to the spring for another." % _trough_words(poured, need)
					return "Fill the bucket at the spring, down the slope west of the house."
				"full":
					if poured > 0:
						return "%s — carry this one up to the trough at the byre." % _trough_words(poured, need)
					return "Carry the water up to the trough at the byre."
			return "Water the cattle: take up the bucket beside the byre."
		&"drive":
			return _drive_text()
		&"milk":
			var tie := _group("opening_rope_tie")
			return String(tie.call("objective_text")) if tie else "Tie the milk cow to the post by the house."
		&"meal":
			return "Stow the goad (1) and eat your meal by the house door."
	return ""


func _drive_text() -> String:
	## In-drive beats (no Máire trips inside the drive step) — see OpeningDriveDirector.drive_beat().
	var d := _group("opening_drive")
	if d == null:
		return "Bring the herd home from the south pasture."
	# No cow counts on the HUD in the opening (no pen counter, no "n of six"): the internal
	# count (need_count / home_count, 6/6 gate rule) lives in the director only.
	match String(d.call("drive_beat")):
		"walk_out":
			return "Bring the herd home: walk the lane south to the pasture."
		"missing":
			return "A cow's missing from the herd. Hark: lowing from beyond the pasture, past the grazing herd — over the south ridge."
		"free_her":
			return "There she is, stuck fast. Goad her out of the bog — goad drawn (3), prod her (LMB / RMB)."
		"rejoin":
			return "Drive her back to the herd at the pasture — walk behind her, goad drawn."
		"stir":
			return "She's back with the herd. Draw the goad (3) and prod a cow (LMB / RMB) to start the herd home."
		"latch":
			return "The herd's in. Swing the pen gate shut and latch it — E at the gateway."
		"ambush":
			return "A stray dog's at the herd! Scare it off — E or a goad prod, up close."
		"regather":
			return "Regather the strays scattered off the lane. Goad them back to the herd."
	var s := "Bring the herd home: walk behind them, goad drawn, up the lane to the pen by the byre."
	if int(d.call("hud_bogged_count")) > 0:
		s += "  There's a cow in the bog — goad her out!"
	elif int(d.call("stalled_count")) > 0:
		s += "  Some have stopped to graze — keep pushing."
	return s


const _NUM_WORDS := ["none", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]


func _num_word(n: int) -> String:
	return _NUM_WORDS[n] if n >= 0 and n < _NUM_WORDS.size() else str(n)


## "One bucket in the trough of three" style count for the watering trips.
func _trough_words(poured: int, need: int) -> String:
	return "%s %s in the trough, of %s" % [_num_word(poured).capitalize(), "bucket" if poured == 1 else "buckets", _num_word(need)]


## (Unused by the HUD now: hints name places, not metres.)
func _dist_suffix(target: Vector3) -> String:
	var p := _player_node()
	if p == null:
		return ""
	var d := Vector2(p.global_position.x - target.x, p.global_position.z - target.z).length()
	if d < 6.0:
		return ""
	return "  (~%d m)" % int(d)


func _maire_pos() -> Vector3:
	var m := _group("opening_maire_door_talk") as Node3D
	return m.global_position if m else Vector3(-5.2, 0, 3.2)


func _player_node() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _group(g: String) -> Node:
	return get_tree().get_first_node_in_group(g)
