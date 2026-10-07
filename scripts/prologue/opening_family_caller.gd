extends Node3D
class_name OpeningFamilyCaller
## Greybox family member at the house door who calls out to Cian as the morning
## cattle drive leaves the yard — plus interactive E-talk when the player walks up.
## Readable bark (Label3D + HUD flash) + raised-arm pose.
## Standalone prologue prop — no combat / CattleEconomy hooks.
## Additive soft cue only; does not gate cattle soft success.

signal callout_spoken(line: String)

enum TalkState { IDLE, TALKING, DONE }

const INTERACT_RANGE := 2.5
## House door south face (authored FamilyCaller sits just outside).
const DOOR_POS := Vector3(-7.2, 0.0, 1.77)

@export var speaker_name: String = "Máire"
@export var callout_line: String = "Cian! Bring them home before the sun's high — and mind the bog!"
@export var bark_hold_secs: float = 6.5
@export var auto_trigger_delay: float = 1.1
@export var retrigger_on_reset: bool = true
@export var director_path: NodePath = ^"../OpeningDriveDirector"
@export var talk_line_hold_secs: float = 2.4

## Morning-chore E-talk lines (greybox; short).
var talk_lines: PackedStringArray = PackedStringArray([
	"There you are, Cian — goad ready?",
	"Herd's down the lane. Bring them home, and mind the bog.",
	"Water the trough if you pass the spring — and free that hitch by the byre.",
])

var _spoken: bool = false
var _bark: Label3D = null
var _name_label: Label3D = null
var _bark_timer: float = 0.0
var _delay_left: float = -1.0
var _arm: Node3D = null

var _talk_state: TalkState = TalkState.IDLE
var _talk_idx: int = -1
var _talk_hold: float = 0.0
var _director: Node = null
var _player: Node3D = null
var _off_you_go_said: bool = false


func _ready() -> void:
	add_to_group("opening_maire_door_talk")
	_build_figure()
	_delay_left = auto_trigger_delay
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	print(
		"OPENING_MAIRE_DOOR_TALK_READY maire=%s door=%s"
		% [global_position, DOOR_POS]
	)


func _process(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left -= delta
		if _delay_left <= 0.0 and not _spoken:
			speak()
	if _bark_timer > 0.0:
		_bark_timer -= delta
		if _bark != null:
			_bark.visible = _bark_timer > 0.0
			# Soft bob so the bark reads as live speech.
			_bark.position.y = 2.55 + sin(Time.get_ticks_msec() * 0.006) * 0.04
		if _arm:
			_arm.rotation_degrees.z = -55.0 + sin(Time.get_ticks_msec() * 0.008) * 8.0
	if _talk_state == TalkState.TALKING:
		_talk_hold -= delta
		if _talk_hold <= 0.0:
			_advance_talk(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- auto callout

func speak() -> void:
	_spoken = true
	_show_bark(callout_line, bark_hold_secs)
	callout_spoken.emit(callout_line)
	print("OPENING_FAMILY_CALLOUT speaker=%s line=%s" % [speaker_name, callout_line])


func reset_callout() -> void:
	_spoken = false
	_bark_timer = 0.0
	if _bark:
		_bark.visible = false
	if retrigger_on_reset:
		_delay_left = auto_trigger_delay * 0.6


func has_spoken() -> bool:
	return _spoken


func is_bark_visible() -> bool:
	return _bark != null and _bark.visible and _bark_timer > 0.0


func get_callout_line() -> String:
	return callout_line


func get_speaker_name() -> String:
	return speaker_name


# ---------------------------------------------------------------- E-talk queries (smoke / stills)

func chore_done() -> bool:
	return _talk_state == TalkState.DONE


func talk_state() -> String:
	match _talk_state:
		TalkState.IDLE:
			return "idle"
		TalkState.TALKING:
			return "talking"
		TalkState.DONE:
			return "done"
	return "unknown"


func maire_pos() -> Vector3:
	return global_position


func door_pos() -> Vector3:
	return DOOR_POS


func interact_prompt() -> String:
	if _player == null or not is_instance_valid(_player):
		return ""
	if not _near(_player.global_position, global_position):
		return ""
	match _talk_state:
		TalkState.IDLE:
			return "E — talk to Máire"
		TalkState.TALKING:
			return "E — continue"
		TalkState.DONE:
			return ""
	return ""


func is_active() -> bool:
	return _talk_state != TalkState.DONE


## Smoke / capture helpers.
func force_done() -> void:
	_talk_state = TalkState.DONE
	_talk_idx = talk_lines.size() - 1
	_talk_hold = 0.0
	_off_you_go_said = false
	if _bark:
		_bark.visible = false
		_bark_timer = 0.0


func force_state(state_name: String) -> void:
	match state_name:
		"idle":
			_talk_state = TalkState.IDLE
			_talk_idx = -1
			_talk_hold = 0.0
			_off_you_go_said = false
			if _bark and _bark_timer <= 0.0:
				_bark.visible = false
		"talking":
			_talk_state = TalkState.TALKING
			_talk_idx = 0
			_deliver_line(0, false)
		"done":
			force_done()
		_:
			push_warning("OpeningFamilyCaller.force_state unknown: " + state_name)


func debug_set_state(state_name: String) -> void:
	force_state(state_name)


## Capture helper: hide bark and cancel pending auto-callout (does not unspeak).
func debug_clear_bark() -> void:
	_delay_left = -1.0
	_bark_timer = 0.0
	if _bark:
		_bark.visible = false


func try_interact() -> bool:
	return _try_interact()


# ---------------------------------------------------------------- interact / talk

func _try_interact() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	if not _near(_player.global_position, global_position):
		return false
	match _talk_state:
		TalkState.IDLE:
			_start_talk()
			return true
		TalkState.TALKING:
			_advance_talk(true)
			return true
		TalkState.DONE:
			if not _off_you_go_said:
				_off_you_go_said = true
				_flash("Off you go, lad — the herd won't walk itself home.", 3.0)
				_show_bark("Off you go.", 2.5)
			return true
	return false


func _start_talk() -> void:
	_talk_state = TalkState.TALKING
	_talk_idx = 0
	print("OPENING_MAIRE_DOOR_TALK_START")
	_deliver_line(0, true)


func _advance_talk(_from_input: bool) -> void:
	if _talk_state != TalkState.TALKING:
		return
	var next := _talk_idx + 1
	if next >= talk_lines.size():
		_finish_talk()
		return
	_talk_idx = next
	_deliver_line(next, true)


func _deliver_line(idx: int, _announce: bool) -> void:
	if idx < 0 or idx >= talk_lines.size():
		return
	var line := String(talk_lines[idx])
	_show_bark(line, maxf(talk_line_hold_secs + 0.8, 3.0))
	_flash("%s: %s" % [speaker_name, line], talk_line_hold_secs + 0.6)
	_talk_hold = talk_line_hold_secs
	print("OPENING_MAIRE_DOOR_TALK_LINE idx=%d line=%s" % [idx, line])


func _finish_talk() -> void:
	_talk_state = TalkState.DONE
	_talk_hold = 0.0
	_flash("Máire nods — cattle home before the sun's high.", 3.5)
	print("OPENING_MAIRE_DOOR_TALK_SOFT_SUCCESS")


func _show_bark(line: String, secs: float) -> void:
	_bark_timer = secs
	if _bark:
		_bark.text = line
		_bark.visible = true


func _flash(text: String, secs: float = 3.0) -> void:
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)
	elif _director and _director.has_method("_flash"):
		_director.call("_flash", text, secs)


func _near(p: Vector3, target: Vector3, range_m: float = INTERACT_RANGE) -> bool:
	var a := Vector3(p.x, 0.0, p.z)
	var b := Vector3(target.x, 0.0, target.z)
	return a.distance_to(b) <= range_m


# ---------------------------------------------------------------- figure

func _build_figure() -> void:
	# Clear any authored placeholders.
	for c in get_children():
		remove_child(c)
		c.free()

	var skin := _mat(Color(0.86, 0.70, 0.58))
	var hair := _mat(Color(0.28, 0.16, 0.08))
	var léine := _mat(Color(0.72, 0.68, 0.55))  # undyed linen
	var brat := _mat(Color(0.42, 0.28, 0.38))    # muted purple brat
	var shoes := _mat(Color(0.22, 0.16, 0.10))

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.28
	body_mesh.height = 1.35
	body.mesh = body_mesh
	body.material_override = léine
	body.position = Vector3(0.0, 0.85, 0.0)
	add_child(body)

	var skirt := MeshInstance3D.new()
	var skirt_mesh := CylinderMesh.new()
	skirt_mesh.top_radius = 0.30
	skirt_mesh.bottom_radius = 0.42
	skirt_mesh.height = 0.55
	skirt.mesh = skirt_mesh
	skirt.material_override = léine.duplicate()
	(skirt.material_override as StandardMaterial3D).albedo_color = Color(0.62, 0.58, 0.48)
	skirt.position = Vector3(0.0, 0.42, 0.0)
	add_child(skirt)

	var cloak := MeshInstance3D.new()
	var cloak_mesh := BoxMesh.new()
	cloak_mesh.size = Vector3(0.72, 0.85, 0.18)
	cloak.mesh = cloak_mesh
	cloak.material_override = brat
	cloak.position = Vector3(0.0, 1.15, -0.12)
	add_child(cloak)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.165
	head_mesh.height = 0.33
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0.0, 1.72, 0.0)
	add_child(head)

	var hair_mi := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.18
	hair_mesh.height = 0.28
	hair_mi.mesh = hair_mesh
	hair_mi.material_override = hair
	hair_mi.position = Vector3(0.0, 1.82, -0.02)
	hair_mi.scale = Vector3(1.05, 0.75, 1.1)
	add_child(hair_mi)

	# Resting left arm.
	var left_arm := MeshInstance3D.new()
	var la_mesh := CapsuleMesh.new()
	la_mesh.radius = 0.055
	la_mesh.height = 0.55
	left_arm.mesh = la_mesh
	left_arm.material_override = skin
	left_arm.position = Vector3(-0.38, 1.15, 0.05)
	left_arm.rotation_degrees = Vector3(12.0, 0.0, 18.0)
	add_child(left_arm)

	# Raised right arm (calling / waving) — joint so we can animate a little.
	_arm = Node3D.new()
	_arm.name = "CallArm"
	_arm.position = Vector3(0.32, 1.35, 0.05)
	_arm.rotation_degrees = Vector3(10.0, 0.0, -55.0)
	add_child(_arm)
	var right_arm := MeshInstance3D.new()
	var ra_mesh := CapsuleMesh.new()
	ra_mesh.radius = 0.055
	ra_mesh.height = 0.58
	right_arm.mesh = ra_mesh
	right_arm.material_override = skin
	right_arm.position = Vector3(0.0, 0.28, 0.0)
	_arm.add_child(right_arm)
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.07
	hand_mesh.height = 0.12
	hand.mesh = hand_mesh
	hand.material_override = skin
	hand.position = Vector3(0.0, 0.58, 0.0)
	_arm.add_child(hand)

	var shoe_l := MeshInstance3D.new()
	var shoe_mesh := BoxMesh.new()
	shoe_mesh.size = Vector3(0.16, 0.1, 0.28)
	shoe_l.mesh = shoe_mesh
	shoe_l.material_override = shoes
	shoe_l.position = Vector3(-0.12, 0.06, 0.04)
	add_child(shoe_l)
	var shoe_r := shoe_l.duplicate() as MeshInstance3D
	shoe_r.position = Vector3(0.12, 0.06, 0.04)
	add_child(shoe_r)

	_name_label = Label3D.new()
	_name_label.text = speaker_name
	_name_label.font_size = 42
	_name_label.pixel_size = 0.01
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.modulate = Color(0.95, 0.88, 0.7)
	_name_label.outline_size = 10
	_name_label.outline_modulate = Color(0.05, 0.05, 0.04, 0.85)
	_name_label.position = Vector3(0.0, 2.15, 0.0)
	add_child(_name_label)

	_bark = Label3D.new()
	_bark.name = "Bark"
	_bark.text = ""
	_bark.font_size = 36
	_bark.pixel_size = 0.012
	_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark.modulate = Color(1.0, 0.96, 0.82)
	_bark.outline_size = 12
	_bark.outline_modulate = Color(0.08, 0.06, 0.04, 0.92)
	_bark.position = Vector3(0.0, 2.55, 0.0)
	_bark.visible = false
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark.width = 420.0
	add_child(_bark)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	return m
