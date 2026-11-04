extends Node3D
## A patch of wild food Cian can pick and eat on the spot (open world, F5). Near-E only: the
## "PromptLabel" shows within REACH and nothing else is drawn (Minimal UI 2026-10-28).
## Picked patches look stripped and come back after a night's sleep (WorldClock.day_advanced).
## May in south Leinster: wood sorrel (trefoil leaves, small white flowers, sour) under the trees,
## and young bramble shoots (peeled tips of this year's canes) in the scrub.

enum Kind { WOOD_SORREL, BRAMBLE_SHOOTS }

@export var kind: Kind = Kind.WOOD_SORREL
@export var reach: float = 1.7

var picked := false
var _player: Node3D
var _near := false
var _prompt: Label3D
var _full: Node3D
var _bare: Node3D
var _mats := {}

signal eaten(kind: int, amount: float)


func _ready() -> void:
	add_to_group("forageable")
	_full = Node3D.new()
	_full.name = "Full"
	add_child(_full)
	_bare = Node3D.new()
	_bare.name = "Picked"
	add_child(_bare)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1169 + int(kind) * 7
	if kind == Kind.WOOD_SORREL:
		_build_sorrel(rng)
	else:
		_build_bramble(rng)
	_prompt = Label3D.new()
	_prompt.name = "PromptLabel"
	_prompt.text = "E — Pick and eat %s" % display_name()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 30
	_prompt.outline_size = 8
	_prompt.position = Vector3(0, 1.1, 0)
	_prompt.visible = false
	add_child(_prompt)
	_refresh()
	var clock := get_node_or_null("/root/WorldClock")
	if clock:
		clock.day_advanced.connect(func(_d: int) -> void: regrow())


func display_name() -> String:
	return "wood sorrel" if kind == Kind.WOOD_SORREL else "bramble shoots"


func food_value() -> float:
	return 0.18 if kind == Kind.WOOD_SORREL else 0.3


func regrow() -> void:
	picked = false
	_refresh()


func _refresh() -> void:
	_full.visible = not picked
	_bare.visible = picked
	_prompt.visible = _near and not picked


func is_player_near() -> bool:
	return _near


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var d := Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z).length()
	var n: bool = d <= reach and not ("is_mounted" in _player and _player.is_mounted)
	if n != _near:
		_near = n
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near or picked:
		return
	pick_and_eat()
	get_viewport().set_input_as_handled()


func pick_and_eat() -> bool:
	if picked:
		return false
	picked = true
	_refresh()
	var h := get_tree().get_first_node_in_group("exile_hunger")
	if h:
		h.eat(food_value())
	var tips := get_tree().get_first_node_in_group("exile_tips")
	if tips:
		tips.tip_once(&"forage", "Picked over. It will come back after a night.")
	eaten.emit(int(kind), food_value())
	return true


# ------------------------------------------------------------------ greybox

func _mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[k] = m
	return _mats[k]


func _mesh(parent: Node, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_sorrel(rng: RandomNumberGenerator) -> void:
	## A low carpet of bright trefoil clumps in leaf litter, a few white flowers.
	var litter := CylinderMesh.new()
	litter.top_radius = 0.75
	litter.bottom_radius = 0.75
	litter.height = 0.015
	_mesh(self, litter, Vector3(0, 0.008, 0), Color(0.3, 0.23, 0.15))
	for i in 22:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.62
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		for l in 3:  # three heart-shaped leaflets
			var lf := SphereMesh.new()
			lf.radius = 0.035
			lf.height = 0.018
			var off := Vector3(0.035, 0, 0).rotated(Vector3.UP, l * TAU / 3.0 + a)
			_mesh(_full, lf, base + off + Vector3(0, 0.06, 0), Color(0.42, 0.62, 0.26))
		var st := CylinderMesh.new()
		st.top_radius = 0.004
		st.bottom_radius = 0.004
		st.height = 0.06
		_mesh(_full, st, base + Vector3(0, 0.03, 0), Color(0.5, 0.35, 0.3))
		if i % 5 == 0:
			var fl := SphereMesh.new()
			fl.radius = 0.018
			fl.height = 0.02
			_mesh(_full, fl, base + Vector3(0.02, 0.09, 0.01), Color(0.95, 0.94, 0.9))
		if i % 3 == 0:  # what a picked patch leaves: a few bare stalks
			_mesh(_bare, st, base + Vector3(0, 0.03, 0), Color(0.4, 0.32, 0.25))


func _build_bramble(rng: RandomNumberGenerator) -> void:
	## Last year's dark arching canes with this year's soft red-green shoots at the tips.
	for i in 7:
		var yaw := rng.randf() * TAU
		var length := rng.randf_range(0.9, 1.5)
		var cane := CylinderMesh.new()
		cane.top_radius = 0.012
		cane.bottom_radius = 0.02
		cane.height = length
		var dir := Vector3(0, 0, 1).rotated(Vector3.UP, yaw)
		var tilt := rng.randf_range(0.7, 1.1)
		var mid := dir * (sin(tilt) * length * 0.5) + Vector3(0, cos(tilt) * length * 0.5, 0)
		var mi := _mesh(self, cane, mid, Color(0.3, 0.2, 0.17))
		mi.rotation = Vector3(tilt, yaw, 0)
		var tip := dir * (sin(tilt) * length) + Vector3(0, cos(tilt) * length, 0)
		var shoot := CylinderMesh.new()
		shoot.top_radius = 0.008
		shoot.bottom_radius = 0.014
		shoot.height = 0.22
		var smi := _mesh(_full, shoot, tip + Vector3(0, 0.1, 0), Color(0.55, 0.5, 0.28))
		smi.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		for l in 2:
			var lf := SphereMesh.new()
			lf.radius = 0.05
			lf.height = 0.02
			_mesh(_full, lf, tip + Vector3(0.04 * (l * 2 - 1), 0.14, 0.02), Color(0.4, 0.5, 0.24))
		var stub := CylinderMesh.new()
		stub.top_radius = 0.01
		stub.bottom_radius = 0.012
		stub.height = 0.05
		_mesh(_bare, stub, tip + Vector3(0, 0.02, 0), Color(0.62, 0.66, 0.45))  # pale snapped ends
	var leaf := SphereMesh.new()
	leaf.radius = 0.55
	leaf.height = 0.5
	_mesh(self, leaf, Vector3(0.2, 0.22, -0.15), Color(0.2, 0.3, 0.16))
