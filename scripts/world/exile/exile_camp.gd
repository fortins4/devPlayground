extends Node3D
## Cian's camp at the wood edge (open world, F5): a stone fire ring with banked embers, a bed of
## cut bracken and rushes under a hazel lean-to, and some gathered deadwood. Near-E on the bed
## sleeps the night: fade to black, WorldClock.advance_day(1), the sun comes back low in the east,
## Cian wakes beside the bed, and the light eases back to day. (May 1169, south Leinster.)

const SLEEP_REACH := 1.8
const FADE_OUT := 1.1
const HOLD_DARK := 0.8
const FADE_IN := 1.6
const DAWN_TO_DAY := 45.0

@export var light_path: NodePath = ^"../DirectionalLight3D"
@export var hunger_path: NodePath = ^"../ExileHunger"

var sleeping := false
var sleeps := 0
var _player: Node3D
var _near := false
var _prompt: Label3D
var _bed_pos := Vector3(1.6, 0, 0.9)  ## local
var _day_light := {}
var _day_tween: Tween
var _mats := {}

signal slept(day: int)
signal woke


func _ready() -> void:
	add_to_group("exile_camp")
	_build()
	_prompt = Label3D.new()
	_prompt.name = "PromptLabel"
	_prompt.text = "E — Sleep by the fire"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 30
	_prompt.outline_size = 8
	_prompt.position = _bed_pos + Vector3(0, 1.2, 0)
	_prompt.visible = false
	add_child(_prompt)
	var l := _light()
	if l:
		_day_light = {"xf": l.global_transform, "energy": l.light_energy, "color": l.light_color}


func _light() -> DirectionalLight3D:
	return get_node_or_null(light_path) as DirectionalLight3D


func bed_global() -> Vector3:
	return to_global(_bed_pos)


func is_player_near() -> bool:
	return _near


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var b := bed_global()
	var d := Vector2(_player.global_position.x - b.x, _player.global_position.z - b.z).length()
	_near = bool(d <= SLEEP_REACH and not sleeping and not ("is_mounted" in _player and _player.is_mounted))
	_prompt.visible = _near


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near or sleeping:
		return
	get_viewport().set_input_as_handled()
	sleep()


func sleep() -> void:
	if sleeping:
		return
	sleeping = true
	_prompt.visible = false
	var tips := get_tree().get_first_node_in_group("exile_tips")
	if _player:
		_player.set_physics_process(false)
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
	if tips:
		await tips.fade_to(1.0, FADE_OUT).finished
	await get_tree().create_timer(HOLD_DARK).timeout
	# The night passes.
	var clock := get_node_or_null("/root/WorldClock")
	if clock:
		clock.advance_day(1)
	var h := get_node_or_null(hunger_path)
	if h and h.has_method("on_slept"):
		h.on_slept()
	sleeps += 1
	_set_dawn()
	_wake_pose()
	slept.emit(clock.day if clock else sleeps)
	if tips:
		await tips.fade_to(0.0, FADE_IN).finished
		tips.tip_once(&"sleep", "A night has passed. Sleeping leaves you hungrier.")
	if _player:
		_player.set_physics_process(true)
	sleeping = false
	woke.emit()


func _wake_pose() -> void:
	## He gets up off the bed and stands on its fire side, between bed and hearth, facing the fire.
	if _player == null:
		return
	var stand := to_global(Vector3(0.6, 0.1, 1.7))
	var to_fire := global_position - stand
	_player.global_position = stand
	_player.rotation.y = atan2(-to_fire.x, -to_fire.z)


func _set_dawn() -> void:
	var l := _light()
	if l == null or _day_light.is_empty():
		return
	if _day_tween and _day_tween.is_valid():
		_day_tween.kill()
	# Early May dawn, ~5:30: sun just up in the east-north-east, low, warm and weak.
	var p := l.global_position
	l.look_at_from_position(p, p + Vector3(-0.92, -0.2, 0.33).normalized(), Vector3.UP)
	l.light_energy = 0.45
	l.light_color = Color(1.0, 0.72, 0.5)
	_day_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_day_tween.tween_property(l, "global_transform", _day_light["xf"], DAWN_TO_DAY)
	_day_tween.tween_property(l, "light_energy", _day_light["energy"], DAWN_TO_DAY)
	_day_tween.tween_property(l, "light_color", _day_light["color"], DAWN_TO_DAY)


## Capture / smoke: stop the dawn ease where it is.
func hold_dawn() -> void:
	if _day_tween and _day_tween.is_valid():
		_day_tween.pause()


# ------------------------------------------------------------------ greybox

func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var k := c.to_html() + ("e" if emit else "")
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.95
		if emit:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 1.4
		_mats[k] = m
	return _mats[k]


func _mi(mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, emit := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, emit)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	return m


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51169
	# Fire ring: a scraped hearth of ash in a ring of fieldstones, embers banked under ash.
	_mi(_cyl(0.75, 0.02), Vector3(0, 0.01, 0), Color(0.2, 0.19, 0.17))
	_mi(_cyl(0.42, 0.03), Vector3(0, 0.02, 0), Color(0.36, 0.35, 0.33))
	for i in 11:
		var a := i * TAU / 11.0 + rng.randf_range(-0.1, 0.1)
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.11, 0.16)
		s.height = s.radius * 1.3
		_mi(s, Vector3(cos(a) * 0.62, 0.07, sin(a) * 0.62), Color(0.5, 0.48, 0.43).darkened(rng.randf_range(0, 0.2)))
	for i in 5:
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(0.08, 0.18), 0.05, rng.randf_range(0.06, 0.14))
		_mi(b, Vector3(rng.randf_range(-0.2, 0.2), 0.045, rng.randf_range(-0.2, 0.2)), Color(1.0, 0.36, 0.08), Vector3(0, rng.randf() * PI, 0), true)
	for i in 4:  # half-burnt sticks laid in to the centre
		var a := i * TAU / 4.0 + 0.4
		var stick := _cyl(0.035, 0.7)
		_mi(stick, Vector3(cos(a) * 0.28, 0.06, sin(a) * 0.28), Color(0.15, 0.12, 0.1), Vector3(PI * 0.5, -a + PI * 0.5, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position = Vector3(0, 0.3, 0)
	add_child(glow)
	# Bed: cut bracken and rushes heaped on the ground, a rolled woollen brat at the head.
	_mi(_box(Vector3(0.9, 0.12, 2.0)), _bed_pos + Vector3(0, 0.06, 0), Color(0.45, 0.36, 0.2), Vector3(0, 0.15, 0))
	_mi(_box(Vector3(0.75, 0.06, 1.8)), _bed_pos + Vector3(0, 0.14, 0), Color(0.38, 0.42, 0.22), Vector3(0, 0.15, 0))
	var brat := _cyl(0.12, 0.65)
	_mi(brat, _bed_pos + Vector3(0, 0.2, -0.8).rotated(Vector3.UP, 0.15) * Vector3(1, 1, 1), Color(0.42, 0.33, 0.27), Vector3(0, 0.15, PI * 0.5))
	# Hazel lean-to over the bed: a ridge pole on two forked uprights, rods slanting to the ground.
	var ridge_y := 1.25
	var bx := _bed_pos.x + 0.55
	for z in [-1.1, 1.1]:
		_mi(_cyl(0.045, ridge_y), Vector3(bx, ridge_y * 0.5, _bed_pos.z + z), Color(0.32, 0.25, 0.18))
	_mi(_cyl(0.04, 2.5), Vector3(bx, ridge_y, _bed_pos.z), Color(0.32, 0.25, 0.18), Vector3(PI * 0.5, 0, 0))
	for k in 9:
		var z := -1.0 + k * 0.25
		var rod := _cyl(0.022, 1.75)
		# rods from the ridge down and back (away from the fire) to the ground
		_mi(rod, Vector3(bx + 0.62, ridge_y * 0.5, _bed_pos.z + z), Color(0.36, 0.3, 0.2), Vector3(0, 0, 0.78))
	_mi(_box(Vector3(0.08, 1.7, 2.4)), Vector3(bx + 0.66, ridge_y * 0.5 + 0.02, _bed_pos.z), Color(0.33, 0.37, 0.2), Vector3(0, 0, 0.78))
	# Gathered deadwood by the fire.
	for k in 6:
		var log := _cyl(rng.randf_range(0.04, 0.07), rng.randf_range(0.8, 1.3))
		_mi(log, Vector3(-1.2 + rng.randf_range(-0.1, 0.1), 0.06 + k * 0.02, -0.6 + k * 0.1), Color(0.3, 0.24, 0.17), Vector3(PI * 0.5, rng.randf_range(-0.2, 0.2), 0))
	# A log to sit on, the far side of the fire.
	_mi(_cyl(0.16, 1.2), Vector3(-0.2, 0.16, -1.25), Color(0.34, 0.26, 0.18), Vector3(0, 0, PI * 0.5))


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
