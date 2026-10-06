extends Node3D
class_name OpeningFamilyCaller
## Greybox family member at the house door who calls out to Cian as the morning
## cattle drive leaves the yard. Readable bark (Label3D + HUD flash) + raised-arm pose.
## Standalone prologue prop — no combat / CattleEconomy hooks.

signal callout_spoken(line: String)

@export var speaker_name: String = "Máire"
@export var callout_line: String = "Cian! Bring them home before the sun's high — and mind the bog!"
@export var bark_hold_secs: float = 6.5
@export var auto_trigger_delay: float = 1.1
@export var retrigger_on_reset: bool = true

var _spoken: bool = false
var _bark: Label3D = null
var _name_label: Label3D = null
var _bark_timer: float = 0.0
var _delay_left: float = -1.0
var _arm: Node3D = null


func _ready() -> void:
	_build_figure()
	_delay_left = auto_trigger_delay


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


func speak() -> void:
	_spoken = true
	_bark_timer = bark_hold_secs
	if _bark:
		_bark.text = callout_line
		_bark.visible = true
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
