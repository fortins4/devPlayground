extends Node
## Opening morning as a SET SEQUENCE with Máire as the hub.
##
##   1 maire  — talk to Máire at the door (her talk ends by giving the bucket job)
##   2 bucket — pick up the bucket, fill it at the spring scoop, pour it at the trough
##   3 knife  — cut the knife hitch
##   4 drive  — bring the herd home. ONE step, no Máire trips inside it; in-drive beats run off
##              the objective HUD line + chore flashes (OpeningDriveDirector.drive_beat()):
##                walk_out → missing (one of the six is stuck in the bog; her lowing leads there)
##                → free_her → rejoin (drive her back to the herd at the pasture) → stir
##                → driving, with the stray-dog ambush on the lane (ambush / regather)
##                → all 6 in the pen
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

const STEP_IDS: Array[StringName] = [&"maire", &"bucket", &"knife", &"drive", &"meal"]
const CLOSER_INDEX := 5

## Máire's handoff line for each step that she hands out on Cian's return (step 2's job is given
## at the end of her door talk — see OpeningFamilyCaller.talk_lines).
const HANDOFF_LINES := {
	&"knife": "Good lad. Now the heifer's still tied at the post by the byre — cut her loose with your knife.",
	&"drive": "Now bring the herd home from the south pasture. All six, mind — count them into the pen.",
	&"meal": "All six home, thank God. Put that goad away and come eat — your meal's by the door.",
}
const CLOSER_LINE := "That's the morning's work done, and done well. Sit and rest a while, a stór."
const IDLE_LINE := "Go on now — the work won't do itself."

const STEP_SHORT := {
	&"maire": "talk to Máire",
	&"bucket": "water the trough",
	&"knife": "cut the heifer's tether",
	&"drive": "bring the herd home",
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
		return "Go back to Máire at the house door — %s.%s" % [what, _dist_suffix(_maire_pos())]
	match current_step_id():
		&"maire":
			return "Talk to Máire — she's waving at the house door.%s" % _dist_suffix(_maire_pos())
		&"bucket":
			var bucket := _group("opening_bucket_trough")
			var st := String(bucket.call("bucket_state")) if bucket else "none"
			match st:
				"empty":
					return "Fill the bucket at the spring scoop — west of the house.%s" % _dist_suffix(Vector3(-23.5, 0, 19.0))
				"full":
					return "Pour the water into the trough at the byre.%s" % _dist_suffix(Vector3(8.2, 0, 0.4))
			return "Water the trough: pick up the bucket by the byre.%s" % _dist_suffix(Vector3(5.2, 0, 2.5))
		&"knife":
			return "Cut the heifer's tether — the hitch post east of the byre trough. Draw the knife (2)."
		&"drive":
			return _drive_text()
		&"meal":
			return "Stow the goad (1) and eat your meal by the house door.%s" % _dist_suffix(Vector3(-4.5, 0, 2.8))
	return ""


func _drive_text() -> String:
	## In-drive beats (no Máire trips inside the drive step) — see OpeningDriveDirector.drive_beat().
	var d := _group("opening_drive")
	if d == null:
		return "Bring the herd home from the south pasture."
	var need := int(d.call("need_count"))
	var home := int(d.call("home_count"))
	match String(d.call("drive_beat")):
		"walk_out":
			return "Bring the herd home: walk the lane south to the pasture.  (pasture ~%d m)" % int(d.call("distance_to_herd"))
		"missing":
			return "Only five at the pasture — one's missing. Hark: lowing from beyond the pasture, past the grazing herd — over the south ridge.%s" % _dist_suffix(Vector3(d.call("bogged_cow_pos")))
		"free_her":
			return "There she is, stuck fast. Goad her out of the bog — goad drawn (3), prod her (LMB / RMB)."
		"rejoin":
			return "Drive her back to the herd at the pasture — walk behind her, goad drawn.  (herd ~%d m)" % int(d.call("bogged_cow_to_herd"))
		"stir":
			return "She's back with the herd. Draw the goad (3) and prod a cow (LMB / RMB) to start all six home."
		"latch":
			return "All six in. Swing the pen gate shut and latch it — E at the gateway.%s" % _dist_suffix(Vector3(7.0, 0.0, 13.8))
		"ambush":
			return "A stray dog's at the herd! Scare it off — E or a goad prod, up close."
		"regather":
			return "Regather the strays — %d scattered off the lane. Goad them back to the herd.  (home %d/%d)" % [
				int(d.call("scattered_count")), home, need]
	var s := "Bring the herd home: walk behind them, goad drawn, up the lane to the pen by the byre.  (home %d/%d)" % [home, need]
	if int(d.call("hud_bogged_count")) > 0:
		s += "  %d in the bog — goad them out!" % int(d.call("hud_bogged_count"))
	elif int(d.call("stalled_count")) > 0:
		s += "  %d grazing — keep pushing." % int(d.call("stalled_count"))
	if home > 0 and home < need:
		s += "  All %d must be in the pen." % need
	return s


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
