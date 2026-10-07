extends Node3D
class_name OpeningStrayDogChore
## Greybox stray dog on the opening lane — scare it off with the goad (E or prod).
## Additive soft cue; does not gate cattle soft success.

enum DogState { LURKING, MENACING, FLEEING, DONE }

const NOTICE_RANGE := 10.0
const SCARE_RANGE := 4.0
const PROD_SCARE_RANGE := 5.0
## West of lane between Bend4 (−12,70) and Bend5 (10,92) — clear of bog/pasture.
const DOG_SPAWN := Vector3(-6.0, 0.0, 88.0)
const FLEE_TARGET := Vector3(-48.0, 0.0, 70.0)

const C_HIDE := Color(0.42, 0.36, 0.30)
const C_HIDE_DARK := Color(0.28, 0.24, 0.20)
const C_MUZZLE := Color(0.55, 0.48, 0.40)
const C_EYE := Color(0.12, 0.10, 0.08)

@export var director_path: NodePath = ^"../OpeningDriveDirector"

var _state: DogState = DogState.LURKING
var _player: Node3D = null
var _director: Node = null
var _dog: Node3D = null
var _bark: Label3D = null
var _mats: Dictionary = {}
var _menace_flashed: bool = false
var _flee_t: float = 0.0
var _flee_from: Vector3 = Vector3.ZERO
var _bark_bob_t: float = 0.0


func _ready() -> void:
	add_to_group("opening_stray_dog")
	_build_dog()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	print("OPENING_STRAY_DOG_READY spawn=%s flee=%s" % [DOG_SPAWN, FLEE_TARGET])


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	match _state:
		DogState.LURKING:
			_tick_lurk()
		DogState.MENACING:
			_tick_menace(delta)
		DogState.FLEEING:
			_tick_flee(delta)
		DogState.DONE:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_scare_from_e():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries

func chore_done() -> bool:
	return _state == DogState.DONE


func dog_state() -> String:
	match _state:
		DogState.LURKING:
			return "lurking"
		DogState.MENACING:
			return "menacing"
		DogState.FLEEING:
			return "fleeing"
		DogState.DONE:
			return "done"
	return "unknown"


func dog_pos() -> Vector3:
	if _dog and is_instance_valid(_dog):
		return _dog.global_position
	return DOG_SPAWN


func spawn_pos() -> Vector3:
	return DOG_SPAWN


func interact_prompt() -> String:
	if _state == DogState.DONE or _state == DogState.FLEEING:
		return ""
	if _player == null or not is_instance_valid(_player):
		return ""
	if not _near(_player.global_position, dog_pos(), SCARE_RANGE + 1.5):
		if _state == DogState.MENACING and _near(_player.global_position, dog_pos(), NOTICE_RANGE):
			return "Stray dog after the herd — scare it off!"
		return ""
	if _goad_equipped():
		return "E — shout / brandish goad"
	return "Draw the goad (3) to scare the dog"


func is_active() -> bool:
	return _state != DogState.DONE


func force_scare() -> void:
	if _state == DogState.DONE:
		return
	if _state == DogState.LURKING:
		_enter_menacing(false)
	_begin_flee(true)


func force_state(state_name: String) -> void:
	match state_name:
		"lurking":
			_set_lurking()
		"menacing":
			_set_lurking()
			_enter_menacing(false)
		"fleeing":
			_set_lurking()
			_enter_menacing(false)
			_begin_flee(false)
		"done":
			force_scare()
			_finish_gone(false)
		_:
			push_warning("OpeningStrayDogChore.force_state unknown: " + state_name)


func debug_set_state(state_name: String) -> void:
	force_state(state_name)


func try_interact() -> bool:
	return _try_scare_from_e()


## Smoke / capture: simulate a goad prod scare near the dog.
func try_prod_scare() -> bool:
	if _state == DogState.DONE or _state == DogState.FLEEING:
		return false
	if _state == DogState.LURKING:
		_enter_menacing(false)
	if not _goad_equipped():
		_flash("Draw the goad (3) to scare the dog.", 3.0)
		return true
	_begin_flee(true)
	return true


# ---------------------------------------------------------------- behaviour

func _tick_lurk() -> void:
	if _player == null:
		return
	if _near(_player.global_position, dog_pos(), NOTICE_RANGE):
		_enter_menacing(true)


func _tick_menace(delta: float) -> void:
	_bark_bob_t += delta
	if _bark:
		_bark.visible = true
		_bark.position.y = 1.35 + sin(_bark_bob_t * 6.0) * 0.04
	# Slow creep toward player (menacing).
	if _dog and _player:
		var to_p := _player.global_position - _dog.global_position
		to_p.y = 0.0
		if to_p.length() > 0.4:
			var step := to_p.normalized() * 1.1 * delta
			_dog.global_position += step
			_dog.look_at(_dog.global_position + to_p.normalized(), Vector3.UP)
	# Goad prod near the dog also scares it off.
	if _player and _goad_equipped() and _near(_player.global_position, dog_pos(), PROD_SCARE_RANGE):
		var combat := _player.get_node_or_null("CombatSystem")
		if combat and bool(combat.get("is_attacking")):
			_begin_flee(true)


func _tick_flee(delta: float) -> void:
	_flee_t += delta
	var dur := 1.6
	var k := clampf(_flee_t / dur, 0.0, 1.0)
	var ease := k * k * (3.0 - 2.0 * k)
	if _dog:
		_dog.global_position = _flee_from.lerp(FLEE_TARGET, ease)
		var dir := (FLEE_TARGET - _flee_from)
		dir.y = 0.0
		if dir.length() > 0.1:
			_dog.look_at(_dog.global_position + dir.normalized(), Vector3.UP)
	if _bark:
		_bark.visible = k < 0.7
	if k >= 1.0:
		_finish_gone(true)


func _enter_menacing(announce: bool) -> void:
	if _state != DogState.LURKING:
		return
	_state = DogState.MENACING
	if _bark:
		_bark.text = "woof!"
		_bark.visible = true
	if announce and not _menace_flashed:
		_menace_flashed = true
		_flash("Stray dog after the herd — scare it off!", 4.0)
		print("OPENING_STRAY_DOG_MENACING")


func _try_scare_from_e() -> bool:
	if _state == DogState.DONE or _state == DogState.FLEEING:
		return false
	if _player == null:
		return false
	if not _near(_player.global_position, dog_pos(), SCARE_RANGE):
		return false
	if _state == DogState.LURKING:
		_enter_menacing(true)
	if not _goad_equipped():
		_flash("Draw the goad (3) to scare the dog.", 3.0)
		return true
	_begin_flee(true)
	return true


func _begin_flee(announce: bool) -> void:
	if _state == DogState.FLEEING or _state == DogState.DONE:
		return
	_state = DogState.FLEEING
	_flee_t = 0.0
	_flee_from = dog_pos()
	if _bark:
		_bark.text = "yelp!"
		_bark.visible = true
	if announce:
		_flash("Dog bolts — herd's clear of the stray.", 3.5)
		print("OPENING_STRAY_DOG_FLEEING")


func _finish_gone(announce: bool) -> void:
	if _state == DogState.DONE:
		return
	_state = DogState.DONE
	if _dog:
		_dog.visible = false
		_dog.global_position = FLEE_TARGET
	if _bark:
		_bark.visible = false
	if announce:
		print("OPENING_STRAY_DOG_SOFT_SUCCESS")


func _set_lurking() -> void:
	_state = DogState.LURKING
	_menace_flashed = false
	_flee_t = 0.0
	if _dog:
		_dog.visible = true
		_dog.global_position = DOG_SPAWN
		_dog.rotation = Vector3(0.0, 0.4, 0.0)
	if _bark:
		_bark.visible = false
		_bark.text = ""


# ---------------------------------------------------------------- geometry

func _build_dog() -> void:
	_dog = Node3D.new()
	_dog.name = "StrayDog"
	_dog.position = DOG_SPAWN
	_dog.rotation.y = 0.4
	add_child(_dog)

	# Hound silhouette — body, chest, head, snout, legs, tail, ears.
	_mesh_box(_dog, Vector3(0.0, 0.42, 0.0), Vector3(0.38, 0.32, 0.72), C_HIDE)
	_mesh_box(_dog, Vector3(0.0, 0.48, 0.28), Vector3(0.34, 0.28, 0.28), C_HIDE_DARK)
	_mesh_box(_dog, Vector3(0.0, 0.58, 0.52), Vector3(0.26, 0.24, 0.26), C_HIDE)
	_mesh_box(_dog, Vector3(0.0, 0.52, 0.72), Vector3(0.16, 0.12, 0.22), C_MUZZLE)
	_mesh_box(_dog, Vector3(-0.08, 0.70, 0.48), Vector3(0.06, 0.14, 0.08), C_HIDE_DARK)
	_mesh_box(_dog, Vector3(0.08, 0.70, 0.48), Vector3(0.06, 0.14, 0.08), C_HIDE_DARK)
	_mesh_box(_dog, Vector3(-0.06, 0.60, 0.58), Vector3(0.04, 0.04, 0.04), C_EYE)
	_mesh_box(_dog, Vector3(0.06, 0.60, 0.58), Vector3(0.04, 0.04, 0.04), C_EYE)
	# Legs.
	for ox in [-0.12, 0.12]:
		for oz in [-0.22, 0.22]:
			_mesh_box(_dog, Vector3(ox, 0.16, oz), Vector3(0.08, 0.32, 0.08), C_HIDE_DARK)
	# Tail.
	_mesh_box(_dog, Vector3(0.0, 0.55, -0.42), Vector3(0.06, 0.06, 0.28), C_HIDE)
	_mesh_box(_dog, Vector3(0.0, 0.62, -0.55), Vector3(0.05, 0.05, 0.12), C_HIDE_DARK)

	var name_l := Label3D.new()
	name_l.text = "Stray"
	name_l.font_size = 28
	name_l.pixel_size = 0.01
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.modulate = Color(0.9, 0.82, 0.65)
	name_l.outline_size = 8
	name_l.position = Vector3(0.0, 1.05, 0.0)
	_dog.add_child(name_l)

	_bark = Label3D.new()
	_bark.name = "Bark"
	_bark.text = ""
	_bark.font_size = 32
	_bark.pixel_size = 0.012
	_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark.modulate = Color(1.0, 0.92, 0.7)
	_bark.outline_size = 10
	_bark.position = Vector3(0.0, 1.35, 0.0)
	_bark.visible = false
	_dog.add_child(_bark)


# ---------------------------------------------------------------- helpers

func _goad_equipped() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var combat := _player.get_node_or_null("CombatSystem")
	if combat == null:
		return false
	# CombatSystem.Weapon.GOAD = 2
	if "current_weapon" in combat:
		return int(combat.get("current_weapon")) == 2
	if combat.has_method("weapon_name"):
		return String(combat.call("weapon_name")) == "goad"
	return false


func _near(a: Vector3, b: Vector3, range_m: float) -> bool:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) <= range_m


func _flash(text: String, secs: float = 3.0) -> void:
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)
	elif _director and _director.has_method("_flash"):
		_director.call("_flash", text, secs)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	_mats[key] = m
	return m


func _mesh_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi
