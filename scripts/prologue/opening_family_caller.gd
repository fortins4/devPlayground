extends Node3D
class_name OpeningFamilyCaller
## Greybox family member at the house door — the hub of the opening set sequence
## (scripts/prologue/opening_sequence.gd).
## - Whenever she has a line waiting (her door talk = the first job, each next job after a step
##   completes, and the closing line) she WAVES: raised right arm swinging overhead with a linen
##   kerchief, readable across the yard.
## - When Cian comes within TALK_RADIUS she speaks it automatically (no E): bark Label3D over her
##   plus the HUD flash. Saying it unlocks the next step and the wave stops. Each line plays once.
## - Nothing waiting: she stands idle, arm down; at most one short idle line per idle stretch.
## The old auto door callout is folded into the first wave + door talk (no separate callout line).
## Standalone prologue prop — no combat / CattleEconomy hooks.

signal callout_spoken(line: String)

enum TalkState { IDLE, TALKING, DONE }

const INTERACT_RANGE := 2.5
## Auto-talk radius (horizontal m): waiting line plays when Cian comes this close.
const TALK_RADIUS := 3.0
## Cian must step back out past this before the idle line can play.
const TALK_LEAVE_RADIUS := 4.0
const WAVE_HZ := 1.6
const WAVE_CENTER_DEG := -28.0
const WAVE_SWING_DEG := 30.0
const ARM_DOWN_DEG := -165.0
const ARM_TALK_DEG := -70.0
const BARK_Y := 2.32
## House door south face (authored FamilyCaller sits just outside).
const DOOR_POS := Vector3(-7.2, 0.0, 1.77)

@export var speaker_name: String = "Máire"
@export var callout_line: String = "Cian! Bring them home before the sun's high — and mind the bog!"
@export var bark_hold_secs: float = 6.5
@export var auto_trigger_delay: float = 1.1
@export var retrigger_on_reset: bool = true
@export var director_path: NodePath = ^"../OpeningDriveDirector"
@export var talk_line_hold_secs: float = 2.4

## Door talk = step 1 (folds in the old door callout). Its last line hands out step 2.
var talk_lines: PackedStringArray = PackedStringArray([
	"Cian! There you are. The herd's to be home before the sun is high.",
	"But water first — take the bucket from by the byre and fill it at the spring scoop, west of the house.",
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
var _sequence: Node = null
var _kerchief: Node3D = null
var _wave_t: float = 0.0
var _arm_deg: float = ARM_DOWN_DEG
## Player inside TALK_RADIUS last frame (idle line needs a fresh approach).
var _player_near: bool = false
var _idle_said: bool = false


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
			_bark.position.y = BARK_Y + sin(Time.get_ticks_msec() * 0.006) * 0.04
	if _talk_state == TalkState.TALKING:
		_talk_hold -= delta
		if _talk_hold <= 0.0:
			_advance_talk(false)
	_tick_hub()
	_tick_arm(delta)


## Auto-talk: a waiting line plays once when Cian walks within TALK_RADIUS.
func _tick_hub() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	var near := _near(_player.global_position, global_position, TALK_RADIUS)
	if not near and _player_near and not _near(_player.global_position, global_position, TALK_LEAVE_RADIUS):
		_player_near = false
	elif near and not _player_near:
		_player_near = true
		_on_player_arrived()
	elif near and has_pending_line():
		_on_player_arrived()


func _on_player_arrived() -> void:
	if _talk_state == TalkState.IDLE and _door_talk_pending():
		_start_talk()
		return
	var seq := _seq()
	if seq and bool(seq.call("awaiting_maire")):
		if _talk_state == TalkState.TALKING:
			_finish_talk()  # door talk still on its last hold — the new job takes over
		var line := String(seq.call("take_pending_line"))
		if line != "":
			_say(line)
			_idle_said = false
		return
	if _talk_state == TalkState.TALKING:
		return
	if not _idle_said and _bark_timer <= 0.0:
		_idle_said = true
		_show_bark(String(seq.call("idle_line")) if seq else "Go on now — the work won't do itself.", 2.5)
		if seq:
			seq.call("note_line", "idle", _bark.text)


func _say(line: String) -> void:
	_show_bark(line, 5.5)
	_flash("%s: %s" % [speaker_name, line], 5.0)
	_talk_hold = 0.0


func _door_talk_pending() -> bool:
	var seq := _seq()
	return seq == null or StringName(seq.call("current_step_id")) == &"maire"


## Waiting line (door talk not started yet, or a sequence handoff / closer not yet said).
func has_pending_line() -> bool:
	if _talk_state == TalkState.IDLE and _door_talk_pending():
		return true
	var seq := _seq()
	return seq != null and bool(seq.call("awaiting_maire"))


func is_waving() -> bool:
	return has_pending_line()


func _tick_arm(delta: float) -> void:
	if _arm == null:
		return
	var waving := is_waving()
	var target := ARM_DOWN_DEG
	if waving:
		_wave_t += delta
		target = WAVE_CENTER_DEG + sin(_wave_t * TAU * WAVE_HZ) * WAVE_SWING_DEG
	elif _bark_timer > 0.0:
		target = ARM_TALK_DEG + sin(Time.get_ticks_msec() * 0.008) * 8.0
	var k := 1.0 if waving and absf(_arm_deg - target) < 40.0 else clampf(delta * 9.0, 0.0, 1.0)
	_arm_deg = lerpf(_arm_deg, target, k)
	_arm.rotation_degrees = Vector3(10.0, 0.0, _arm_deg)
	if _kerchief:
		_kerchief.visible = waving


func _seq() -> Node:
	if _sequence == null or not is_instance_valid(_sequence):
		_sequence = get_tree().get_first_node_in_group("opening_sequence") if is_inside_tree() else null
	return _sequence


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- auto callout

## Old auto door callout, folded into the first wave + door talk: she starts calling Cian over
## by waving (no separate line / HUD flash). has_spoken() stays true for HUD / smokes.
func speak() -> void:
	_spoken = true
	print("OPENING_FAMILY_CALLOUT speaker=%s wave=%s (folded into door talk)" % [speaker_name, is_waving()])


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
	return String(talk_lines[0])


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
			return "Máire is talking  (E — next line)"
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
			# E is never needed; a waiting handoff plays as on approach, else the one idle line.
			_on_player_arrived()
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
	var last := idx == talk_lines.size() - 1
	var hold := talk_line_hold_secs + (1.6 if last else 0.0)
	_show_bark(line, maxf(hold + 0.8, 3.0))
	_flash("%s: %s" % [speaker_name, line], hold + 0.6)
	_talk_hold = hold
	print("OPENING_MAIRE_DOOR_TALK_LINE idx=%d line=%s" % [idx, line])
	if not _announce:
		return
	var seq := _seq()
	if seq:
		seq.call("note_line", "maire_talk_%d" % idx, line)
		# The last door-talk line hands out the bucket job: step 1 done, step 2 unlocked.
		if last:
			seq.call("complete_step", &"maire")


func _finish_talk() -> void:
	_talk_state = TalkState.DONE
	_talk_hold = 0.0
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
	_arm.rotation_degrees = Vector3(10.0, 0.0, ARM_DOWN_DEG)
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
	# Linen kerchief in the waving hand — makes the wave read across the yard.
	_kerchief = MeshInstance3D.new()
	_kerchief.name = "Kerchief"
	var k_mesh := BoxMesh.new()
	k_mesh.size = Vector3(0.3, 0.34, 0.02)
	(_kerchief as MeshInstance3D).mesh = k_mesh
	var k_mat := _mat(Color(0.95, 0.92, 0.82))
	(_kerchief as MeshInstance3D).material_override = k_mat
	_kerchief.position = Vector3(0.1, 0.76, 0.0)
	_kerchief.visible = false
	_arm.add_child(_kerchief)

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
	_bark.font_size = 30
	_bark.pixel_size = 0.0085
	_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark.modulate = Color(1.0, 0.96, 0.82)
	_bark.outline_size = 12
	_bark.outline_modulate = Color(0.08, 0.06, 0.04, 0.92)
	_bark.position = Vector3(0.0, BARK_Y, 0.0)
	_bark.visible = false
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark.width = 560.0
	# Grow upward from just above her name, so longer job lines never cover her face.
	_bark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_bark)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	return m
