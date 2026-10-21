extends Node3D
class_name PrologueHandHold
## Raid day, step 6: Cian takes his sister by the hand (E beside her). She comes off Máire's léine,
## puts her hand in his right hand and keeps at his right side, half a step behind, at his pace.
## A child in hand is a lead, not a load (PlayerController.begin_lead): the goad goes on his back
## (both hands can't be on the shaft with one holding hers), no strikes or kit changes, and no
## sprint (he can't run flat out towing a ten-year-old); he walks or jogs (lead_walk_speed: the
## jog, or the walk with Alt), and crouches as ever. E again beside her lets go; she then stays at
## his heel. (Following on her own, crouching with him and Máire coming too belong to step 7.)

const SEQ_STEP := &"knife"
const INTERACT_RANGE := 1.6
## Her place at his side: his right (+X), a little behind (+Z), in his frame.
const SIDE := Vector3(0.48, 0.0, 0.3)
const HEEL := Vector3(0.35, 0.0, 0.95)
const JOG := 2.6    ## a child's jog, hand in hand
const WALK := 1.5

enum State { WAITING, IN_HAND, AT_HEEL }

var _state: State = State.WAITING
var _player: Node3D = null
var _raid: Node = null
var _girl: Node3D = null


func _ready() -> void:
	add_to_group("prologue_chore")
	add_to_group("prologue_hand_hold")
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")


func set_girl(g: Node3D) -> void:
	_girl = g


func hold_state() -> String:
	return ["waiting", "in_hand", "at_heel"][int(_state)]


func is_in_hand() -> bool:
	return _state == State.IN_HAND


func _open() -> bool:
	return _raid != null and bool(_raid.call("is_step_active", SEQ_STEP)) and _girl != null


func is_active() -> bool:
	return _open() and _state == State.WAITING


func interact_prompt() -> String:
	if _player == null or _girl == null:
		return ""
	if not _near(_player.global_position, _girl.global_position, INTERACT_RANGE):
		return ""
	match _state:
		State.WAITING:
			return "E — take your sister by the hand" if _open() else ""
		State.IN_HAND:
			return "E — let go of her hand"
		State.AT_HEEL:
			return "E — take her hand again"
	return ""


func objective_text() -> String:
	if _state == State.WAITING:
		return "Take your sister by the hand."
	return ""


func lead_walk_speed() -> float:
	return WALK if Input.is_action_pressed("walk") else JOG


## _input, not _unhandled_input: Máire stands beside the door and her talk node takes any E near her
## (she has nothing more to say by now), which would swallow this one.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_E:
		if try_interact():
			get_viewport().set_input_as_handled()


func try_interact() -> bool:
	if _player == null or _girl == null:
		return false
	if not _near(_player.global_position, _girl.global_position, INTERACT_RANGE):
		return false
	match _state:
		State.WAITING, State.AT_HEEL:
			if _state == State.WAITING and not _open():
				return false
			if bool(_player.call("is_leading")) or bool(_player.call("is_carrying")) or bool(_player.call("is_hand_working")):
				return false
			_take_hand()
			return true
		State.IN_HAND:
			_let_go()
			return true
	return false


func _take_hand() -> void:
	var first := _state == State.WAITING
	_state = State.IN_HAND
	_player.call("begin_lead", self)
	_girl.call("reach_right", Vector3.ZERO, 0.0)
	_girl.call("follow", _player, SIDE, 3.2)
	print("PROLOGUE_GIRL_HAND_TAKEN")
	if first and _raid and _raid.has_method("report_girl_in_hand"):
		_raid.call("report_girl_in_hand")


func _let_go() -> void:
	_state = State.AT_HEEL
	_player.call("end_lead", self)
	_girl.call("follow", _player, HEEL, 3.2)
	_girl.call("reach_left", Vector3.ZERO, 0.0)
	print("PROLOGUE_GIRL_HAND_RELEASED")


## Smoke / capture.
func force_in_hand() -> void:
	if _state != State.IN_HAND:
		_take_hand()


func _physics_process(_delta: float) -> void:
	if _state == State.IN_HAND and _girl and _player and is_instance_valid(_player):
		# Her left hand up into his right (he holds it low by his hip: lead_hand_point).
		var hp: Vector3 = _player.call("lead_hand_point")
		var d := Vector2(hp.x - _girl.global_position.x, hp.z - _girl.global_position.z).length()
		_girl.call("reach_left", hp, clampf(1.6 - d, 0.0, 1.0))


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= r
