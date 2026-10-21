extends OpeningStrayDogChore
class_name PrologueFarmDog
## Raid day, evening (steps 1–3): the household's own dog in the yard — met before the dawn so its
## barking and the yelp at first light (step 4, heard only) mean something. The stray's hound mesh
## and four-legged gait (OpeningStrayDogChore) in its own coat: black, with a white chest, muzzle
## and stockings (the stray is a dun-brown hound). Ambient only: no prompt, no interaction, no
## name tag. It lies by the house door; gets up and trots after Cian when he is about the yard
## (or after the herd-hand when he goes down off the bank); goes once to sniff at the neighbours'
## boy. It is gone from the night fade on (RaidSequence calls `night_gone`): at dawn it is a
## sound at the gate and then nothing (Decision 15), never seen.

const LIE_AT := Vector3(-5.9, 0.0, 2.7)
const LIE_YAW := 2.6
const FOLLOW_GAP := 2.4
const WALK_V := 1.3
const TROT_V := 2.6
const YARD_R := 13.0
const RATH_C := Vector3(0.5, 0.0, 3.0)

enum Mode { LYING, FOLLOWING, SNIFFING, GONE }

var _mode: Mode = Mode.LYING
var _raid: Node = null
var _boy: Node3D = null
var _hh: Node3D = null
var _lead: Node3D = null
var _sniffed: bool = false
var _sniff_t: float = 0.0
var _lie_w: float = 1.0
var _mode_t: float = 0.0
var _ever_followed: bool = false


func _ready() -> void:
	add_to_group("prologue_farm_dog")
	coat = Color(0.11, 0.1, 0.09)
	coat_dark = Color(0.86, 0.84, 0.78)
	coat_muzzle = Color(0.9, 0.88, 0.82)
	_build_dog()
	_dog.name = "FarmDog"
	# No name tag: the stray's label goes (its bark label stays, unused).
	for c in _dog.get_children():
		if c is Label3D and (c as Label3D).name != "Bark":
			c.queue_free()
	_dog.global_position = _grounded(LIE_AT)
	_dog.rotation.y = LIE_YAW
	_last_pos = _dog.global_position
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")


func set_cast(boy: Node3D, herd_hand: Node3D) -> void:
	_boy = boy
	_hh = herd_hand


func mode_name() -> String:
	return ["lying", "following", "sniffing", "gone"][int(_mode)]


func is_present() -> bool:
	return _mode != Mode.GONE and _dog != null and _dog.is_visible_in_tree()


func dog_node() -> Node3D:
	return _dog


## The night fade: the dog is not seen again.
func night_gone() -> void:
	_mode = Mode.GONE
	if _dog:
		_dog.visible = false
	set_process(false)
	print("PROLOGUE_FARM_DOG_GONE")


# No prompt, no E, never a chore.
func interact_prompt() -> String:
	return ""


func is_active() -> bool:
	return false


func try_interact() -> bool:
	return false


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _process(delta: float) -> void:
	if _mode == Mode.GONE or _dog == null:
		return
	_mode_t += delta
	var dp := _dog.global_position
	match _mode:
		Mode.LYING:
			# Back to its place by the door first, then settle there.
			if _flat(dp - LIE_AT) > 0.05:
				if _move_toward(LIE_AT, WALK_V * delta):
					_dog.rotation.y = LIE_YAW
			# Up when Cian (or the herd-hand coming down) is about the yard away from the door.
			var lead := _pick_lead()
			if lead and _mode_t > 2.0:
				_lead = lead
				_ever_followed = true
				_set_mode(Mode.FOLLOWING)
			elif _boy and is_instance_valid(_boy) and not _sniffed and _flat(_boy.global_position - dp) < 6.0 and _mode_t > 1.0:
				_set_mode(Mode.SNIFFING)
		Mode.FOLLOWING:
			if _lead == null or not is_instance_valid(_lead) or _pick_lead() == null:
				# Back to lie by the door.
				if _move_toward(LIE_AT, WALK_V * delta):
					_dog.rotation.y = LIE_YAW
					_set_mode(Mode.LYING)
			else:
				var lp := _lead.global_position
				var d := _flat(lp - dp)
				if d > FOLLOW_GAP:
					_move_toward(lp, (TROT_V if d > 5.0 else WALK_V) * delta)
				if _boy and is_instance_valid(_boy) and not _sniffed and _flat(_boy.global_position - dp) < 3.5:
					_set_mode(Mode.SNIFFING)
		Mode.SNIFFING:
			if _boy == null or not is_instance_valid(_boy):
				_set_mode(Mode.LYING)
			else:
				var bp := _boy.global_position
				if _flat(bp - dp) > 0.75:
					_move_toward(bp, WALK_V * delta)
				else:
					_sniff_t += delta
					if _sniff_t > 2.2:
						_sniffed = true
						print("PROLOGUE_FARM_DOG_SNIFFED_BOY")
						_set_mode(Mode.LYING)
	_tick_gait(delta)
	# Lying: settled down on its belly, legs folded under (a crude fold of the same legs).
	var want := 1.0 if (_mode == Mode.LYING and _flat(_dog.global_position - LIE_AT) < 0.2) else 0.0
	_lie_w = move_toward(_lie_w, want, delta * 2.5)
	if _lie_w > 0.0:
		for i in _legs.size():
			var L: Dictionary = _legs[i]
			(L["hip"] as Node3D).rotation.x = lerpf((L["hip"] as Node3D).rotation.x, -1.35 if bool(L["front"]) else 1.25, _lie_w)
			(L["knee"] as Node3D).rotation.x = lerpf((L["knee"] as Node3D).rotation.x, 0.4 if bool(L["front"]) else -2.3, _lie_w)
	for c in _dog.get_children():
		if c is MeshInstance3D:
			pass
	_dog.position.y = _grounded(_dog.global_position).y - 0.24 * _lie_w


func ever_followed() -> bool:
	return _ever_followed


func has_sniffed_boy() -> bool:
	return _sniffed


func visible_tags() -> int:
	var n := 0
	for c in _dog.get_children():
		if c is Label3D and (c as Label3D).visible:
			n += 1
	return n


func is_lying() -> bool:
	return _mode == Mode.LYING and _lie_w > 0.9


func _set_mode(m: Mode) -> void:
	_mode = m
	_mode_t = 0.0
	_sniff_t = 0.0


## Who it would trot after: Cian when he is in the yard and away from the door, else the herd-hand
## once he is down in the yard; nobody while Cian sits at the meal / is in at the door.
func _pick_lead() -> Node3D:
	if _player and is_instance_valid(_player):
		var pp := _player.global_position
		if _flat(pp - RATH_C) < YARD_R and _flat(pp - LIE_AT) > 4.0:
			return _player
	if _hh and is_instance_valid(_hh) and _hh.visible:
		var hp := _hh.global_position
		if _flat(hp - RATH_C) < YARD_R - 1.5 and _flat(hp - LIE_AT) > 4.0 and bool(_hh.call("is_walking")):
			return _hh
	return null


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
