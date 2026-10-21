extends Node3D
class_name OpeningStrayDogChore
## Greybox stray dog on the opening lane — scare it off with the goad (E or prod).
## Does not gate cattle success.
##
## Set-sequence flow: the dog is part of the drive step (step 4). It stays hidden and inert in
## the hedge (quiet walk out) until the director springs the AMBUSH on the way home
## (trigger_ambush): it breaks from the hedge by the old spot between Bend4 and Bend5, dashes at
## the herd (CHARGING), the herd balks and the nearest head scatter (director.ambush_scatter),
## then it MENACES until Cian scares it off (E / goad prod up close) → FLEEING → DONE.
## Without a sequence (standalone) it lurks visibly at its spot like before.

enum DogState { LURKING, CHARGING, MENACING, FLEEING, DONE }

const NOTICE_RANGE := 10.0
const SCARE_RANGE := 4.0
const PROD_SCARE_RANGE := 5.0
## West of lane between Bend4 (−12,70) and Bend5 (10,92) — clear of bog/pasture.
const DOG_SPAWN := Vector3(-6.0, 0.0, 88.0)
const FLEE_TARGET := Vector3(-48.0, 0.0, 70.0)
## Ambush dash from the hedge to just short of the herd.
const CHARGE_SECS := 1.3 ## (unused by the gallop; kept for tools)
const CHARGE_STOP_SHORT := 3.0
## Real dog speeds: a ~58 cm herding/cur dog trots ~3–4 m/s and gallops ~9–11 m/s, reaching it
## in about a second. Menace is a stiff stalking walk.
const MENACE_SPEED := 1.1
const TROT_SPEED := 3.5
const RUN_SPEED := 10.0
const RUN_ACCEL := 14.0 ## m/s² from a standing start
const FLEE_DONE_SECS := 1.6 ## off as a threat (chore done) this long into the bolt; it keeps running out of sight
## Leg rig: hip / shoulder pivots, two segments, sole on the ground; stance soles held world-still.
const HIP_Y := 0.36
const UPPER_LEN := 0.20
const LOWER_LEN := 0.20
const LEG_X := 0.12
const LEG_Z := 0.24
## Gaits: stride frequency (Hz), duty factor, per-leg phase offsets [LF, RF, LH, RH].
const GAIT_WALK := {"hz": 1.6, "duty": 0.62, "off": [0.25, 0.75, 0.0, 0.5], "lift": 0.06}
const GAIT_TROT := {"hz": 2.9, "duty": 0.38, "off": [0.0, 0.5, 0.5, 0.0], "lift": 0.09}
const GAIT_GALLOP := {"hz": 3.3, "duty": 0.12, "off": [0.55, 0.45, 0.0, 0.1], "lift": 0.14}
const MAX_SWEEP := 0.44
## The dog is not a physics body: every move rests it on the shared OpeningTerrain surface
## (its flee line runs up onto the near west roll).
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

const C_HIDE := Color(0.42, 0.36, 0.30)
const C_HIDE_DARK := Color(0.28, 0.24, 0.20)
const C_MUZZLE := Color(0.55, 0.48, 0.40)
const C_EYE := Color(0.12, 0.10, 0.08)

const SEQ_STEP := &"drive"

@export var director_path: NodePath = ^"../OpeningDriveDirector"

var _state: DogState = DogState.LURKING
var _player: Node3D = null
var _director: Node = null
var _sequence: Node = null
var _dog: Node3D = null
var _bark: Label3D = null
var _mats: Dictionary = {}
var _menace_flashed: bool = false
var _flee_t: float = 0.0
var _flee_from: Vector3 = Vector3.ZERO
var _bark_bob_t: float = 0.0
## Set-sequence flow: true once the ambush is sprung (or a debug force_state shows the dog).
var _armed: bool = false
var _ambush: bool = false
var _charge_t: float = 0.0
var _charge_from: Vector3 = Vector3.ZERO
var _charge_to: Vector3 = Vector3.ZERO
var _speed: float = 0.0 ## current ground speed (m/s), drives the gait
var _gait_phase: float = 0.0
var _gait_name: String = "stand"
var _legs: Array = [] ## [{hip, knee, side_x, front}]
var _flee_trot: bool = false
var _runoff: bool = false ## DONE but still running out of sight
var _last_pos: Vector3 = Vector3.ZERO
var _stance: Array = [false, false, false, false]
var _body: Node3D = null
## Coat (the prologue's farm dog reuses this mesh and gait with its own colours).
var coat: Color = C_HIDE
var coat_dark: Color = C_HIDE_DARK
var coat_muzzle: Color = C_MUZZLE


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
	if _state == DogState.LURKING:
		# Hidden and inert in the hedge until the drive ambush springs it (quiet walk out).
		var open := _gate_open()
		if _dog and _dog.visible != open:
			_dog.visible = open
		if not open:
			return
	if _runoff:
		_tick_runoff(delta)
	_tick_gait(delta)
	match _state:
		DogState.LURKING:
			_tick_lurk()
		DogState.CHARGING:
			_tick_charge(delta)
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
		DogState.CHARGING:
			return "charging"
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


## Ambush sprung and the dog still at the herd (charging or menacing).
func is_threat() -> bool:
	return _state == DogState.CHARGING or _state == DogState.MENACING


func ambush_fired() -> bool:
	return _ambush


## Drive ambush: break from the hedge and dash at the herd near target.
func trigger_ambush(target: Vector3) -> bool:
	if _state != DogState.LURKING or _ambush:
		return false
	_armed = true
	_ambush = true
	_state = DogState.CHARGING
	_menace_flashed = true
	_charge_t = 0.0
	_charge_from = _grounded(DOG_SPAWN)
	var to_dog := _charge_from - target
	to_dog.y = 0.0
	var stop := CHARGE_STOP_SHORT if to_dog.length() > CHARGE_STOP_SHORT else 0.0
	_charge_to = _grounded(target + (to_dog.normalized() * stop if to_dog.length() > 0.01 else Vector3.ZERO))
	if _dog:
		_dog.visible = true
		_dog.global_position = _charge_from
	if _bark:
		_bark.text = "WOOF! WOOF!"
		_bark.visible = true
	_flash("A stray dog breaks from the hedge — the herd balks!", 4.0)
	print("OPENING_STRAY_DOG_AMBUSH from=%s to=%s" % [_charge_from.snapped(Vector3.ONE * 0.1), _charge_to.snapped(Vector3.ONE * 0.1)])
	return true


## The herd made it home with the dog still about: it slinks off on its own.
func give_up() -> void:
	if _state == DogState.MENACING or _state == DogState.CHARGING:
		_begin_flee(false, true)
		print("OPENING_STRAY_DOG_GAVE_UP")


func interact_prompt() -> String:
	if _state == DogState.DONE or _state == DogState.FLEEING or _state == DogState.CHARGING:
		return ""
	if _state == DogState.LURKING and not _gate_open():
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
	if _state == DogState.DONE or _state == DogState.FLEEING or _state == DogState.CHARGING:
		return false
	if _state == DogState.LURKING and not _gate_open():
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


func _tick_charge(delta: float) -> void:
	_charge_t += delta
	_bark_bob_t += delta
	var k := 1.0
	if _dog:
		# Gallop from a standing start, flat out, to the herd.
		_speed = minf(RUN_SPEED, _speed + RUN_ACCEL * delta)
		var arrived := _move_toward(_charge_to, _speed * delta)
		k = 1.0 if arrived else 0.0
	if _bark:
		_bark.visible = true
		_bark.position.y = 1.35 + sin(_bark_bob_t * 9.0) * 0.06
	if k >= 1.0:
		_state = DogState.MENACING
		if _bark:
			_bark.text = "woof!"
		if _director and _director.has_method("ambush_scatter"):
			_director.call("ambush_scatter", dog_pos())
		print("OPENING_STRAY_DOG_MENACING")


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
			_speed = move_toward(_speed, MENACE_SPEED, RUN_ACCEL * delta)
			_move_toward(_player.global_position, _speed * delta)
		else:
			_speed = 0.0
	# Goad prod near the dog also scares it off.
	if _player and _goad_equipped() and _near(_player.global_position, dog_pos(), PROD_SCARE_RANGE):
		var combat := _player.get_node_or_null("CombatSystem")
		if combat and bool(combat.get("is_attacking")):
			_begin_flee(true)


func _tick_flee(delta: float) -> void:
	_flee_t += delta
	var k := clampf(_flee_t / FLEE_DONE_SECS, 0.0, 1.0)
	_run_off_step(delta)
	if _bark:
		_bark.visible = k < 0.7
	if k >= 1.0:
		_finish_gone(true)


## Bolting (scared: flat-out gallop) or slinking off (gave up: a trot) toward the far hedge.
func _run_off_step(delta: float) -> void:
	if _dog == null:
		return
	var top := TROT_SPEED if _flee_trot else RUN_SPEED
	_speed = minf(top, _speed + RUN_ACCEL * delta)
	if _move_toward(FLEE_TARGET, _speed * delta):
		_runoff = false
		_speed = 0.0
		_dog.visible = false


func _tick_runoff(delta: float) -> void:
	_run_off_step(delta)


## Step the dog along the ground toward `target`, facing the way it goes. True on arrival.
func _move_toward(target: Vector3, step: float) -> bool:
	var to := target - _dog.global_position
	to.y = 0.0
	var d := to.length()
	if d <= maxf(step, 0.01):
		_dog.global_position = _grounded(target)
		return true
	var dir := to / d
	_dog.global_position = _grounded(_dog.global_position + dir * step)
	_dog.look_at(_dog.global_position + dir, Vector3.UP, true)  # model front is +Z (head)
	return false


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
	if _state == DogState.DONE or _state == DogState.FLEEING or _state == DogState.CHARGING:
		return false
	if _state == DogState.LURKING and not _gate_open():
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


func _begin_flee(announce: bool, slink: bool = false) -> void:
	if _state == DogState.FLEEING or _state == DogState.DONE:
		return
	_state = DogState.FLEEING
	_flee_trot = slink
	_flee_t = 0.0
	_flee_from = dog_pos()
	if _bark:
		_bark.text = "yelp!"
		_bark.visible = true
	if announce:
		_flash("Dog bolts — now regather the herd." if _ambush else "Dog bolts — herd's clear of the stray.", 3.5)
		print("OPENING_STRAY_DOG_FLEEING")


func _finish_gone(announce: bool) -> void:
	if _state == DogState.DONE:
		return
	var was_fleeing := _state == DogState.FLEEING
	_state = DogState.DONE
	if _dog:
		if was_fleeing and _dog.visible and announce:
			# No longer a threat; it keeps running till it is out of sight at the far hedge.
			_runoff = true
		else:
			_runoff = false
			_speed = 0.0
			_dog.visible = false
			_dog.global_position = _grounded(FLEE_TARGET)
	if _bark:
		_bark.visible = false
	if announce:
		print("OPENING_STRAY_DOG_SOFT_SUCCESS")


func _set_lurking() -> void:
	# Debug / smoke path: shows the dog at its hedge spot with the old notice → menace behaviour.
	_armed = true
	_state = DogState.LURKING
	_menace_flashed = false
	_flee_t = 0.0
	_runoff = false
	_speed = 0.0
	if _dog:
		_dog.visible = true
		_dog.global_position = _grounded(DOG_SPAWN)
		_dog.rotation = Vector3(0.0, 0.4, 0.0)
	if _bark:
		_bark.visible = false
		_bark.text = ""


# ---------------------------------------------------------------- geometry

func _build_dog() -> void:
	_dog = Node3D.new()
	_dog.name = "StrayDog"
	_dog.position = _grounded(DOG_SPAWN)
	_dog.rotation.y = 0.4
	add_child(_dog)

	# Hound silhouette — body, chest, head, snout, legs, tail, ears.
	_mesh_box(_dog, Vector3(0.0, 0.42, 0.0), Vector3(0.38, 0.32, 0.72), coat)
	_mesh_box(_dog, Vector3(0.0, 0.48, 0.28), Vector3(0.34, 0.28, 0.28), coat_dark)
	_mesh_box(_dog, Vector3(0.0, 0.58, 0.52), Vector3(0.26, 0.24, 0.26), coat)
	_mesh_box(_dog, Vector3(0.0, 0.52, 0.72), Vector3(0.16, 0.12, 0.22), coat_muzzle)
	_mesh_box(_dog, Vector3(-0.08, 0.70, 0.48), Vector3(0.06, 0.14, 0.08), coat_dark)
	_mesh_box(_dog, Vector3(0.08, 0.70, 0.48), Vector3(0.06, 0.14, 0.08), coat_dark)
	_mesh_box(_dog, Vector3(-0.06, 0.60, 0.58), Vector3(0.04, 0.04, 0.04), C_EYE)
	_mesh_box(_dog, Vector3(0.06, 0.60, 0.58), Vector3(0.04, 0.04, 0.04), C_EYE)
	# Legs: shoulder / hip pivot, upper and lower segment, paw. Order LF, RF, LH, RH.
	_legs.clear()
	for spec in [[-LEG_X, LEG_Z, true], [LEG_X, LEG_Z, true], [-LEG_X, -LEG_Z, false], [LEG_X, -LEG_Z, false]]:
		var hip := Node3D.new()
		hip.position = Vector3(spec[0], HIP_Y, spec[1])
		_dog.add_child(hip)
		_mesh_box(hip, Vector3(0.0, -UPPER_LEN * 0.5, 0.0), Vector3(0.085, UPPER_LEN + 0.03, 0.09), coat_dark)
		var knee := Node3D.new()
		knee.position = Vector3(0.0, -UPPER_LEN, 0.0)
		hip.add_child(knee)
		_mesh_box(knee, Vector3(0.0, -LOWER_LEN * 0.5, 0.0), Vector3(0.065, LOWER_LEN, 0.065), coat_dark)
		_mesh_box(knee, Vector3(0.0, -LOWER_LEN + 0.02, 0.025), Vector3(0.075, 0.04, 0.10), coat_dark)
		_legs.append({"hip": hip, "knee": knee, "front": spec[2]})
	# Tail.
	_mesh_box(_dog, Vector3(0.0, 0.55, -0.42), Vector3(0.06, 0.06, 0.28), coat)
	_mesh_box(_dog, Vector3(0.0, 0.62, -0.55), Vector3(0.05, 0.05, 0.12), coat_dark)

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


# ---------------------------------------------------------------- gait

## Ground speed from the actual displacement, then a four-legged gait: walk (lateral sequence),
## trot (diagonal pairs) or rotary gallop (with suspension). Stance paws sweep back at exactly
## the body speed, so they stay put on the ground; swing paws lift and reach forward.
func _tick_gait(delta: float) -> void:
	if _dog == null or not _dog.visible or _legs.is_empty():
		if _dog:
			_last_pos = _dog.global_position
		return
	var moved := _dog.global_position - _last_pos
	moved.y = 0.0
	_last_pos = _dog.global_position
	var v := moved.length() / maxf(delta, 1e-4)
	if v > 25.0:
		v = 0.0  # a teleport (spawn / force_state), not a gait
	var g: Dictionary
	if v < 0.05:
		_gait_name = "stand"
		for i in 4:
			_stance[i] = true
			_pose_leg(i, 0.0, 0.0)
		return
	elif v < 1.8:
		g = GAIT_WALK
		_gait_name = "walk"
	elif v < 6.0:
		g = GAIT_TROT
		_gait_name = "trot"
	else:
		g = GAIT_GALLOP
		_gait_name = "gallop"
	var hz: float = g["hz"]
	var duty: float = g["duty"]
	_gait_phase = fposmod(_gait_phase + hz * delta, 1.0)
	var sweep := minf(v * duty / hz, MAX_SWEEP)
	var off: Array = g["off"]
	for i in 4:
		var u := fposmod(_gait_phase + float(off[i]), 1.0)
		var fz: float
		var lift := 0.0
		if u < duty:
			fz = sweep * 0.5 - sweep * (u / duty)
			_stance[i] = true
		else:
			var w := (u - duty) / (1.0 - duty)
			var e := w * w * (3.0 - 2.0 * w)
			fz = -sweep * 0.5 + sweep * e
			lift = sin(w * PI) * float(g["lift"])
			_stance[i] = false
		_pose_leg(i, fz, lift)
	if _body:
		var susp := 0.0
		if _gait_name == "gallop":
			susp = 0.025 * sin(_gait_phase * TAU * 2.0)
		_body.position.y = susp


## Two-bone leg to a paw target (fz fore of the pivot, lift above the ground). Fore legs fold
## with the joint pointing back (elbow / carpus read), hind legs with it forward (stifle).
func _pose_leg(i: int, fz: float, lift: float) -> void:
	var L: Dictionary = _legs[i]
	var h := HIP_Y - lift
	var d := clampf(sqrt(fz * fz + h * h), 0.05, UPPER_LEN + LOWER_LEN - 0.002)
	var phi_t := atan2(fz, h)
	var cos_a := clampf((UPPER_LEN * UPPER_LEN + d * d - LOWER_LEN * LOWER_LEN) / (2.0 * UPPER_LEN * d), -1.0, 1.0)
	var a := acos(cos_a)
	var phi_u := phi_t + (a if not bool(L["front"]) else -a)
	var kz := UPPER_LEN * sin(phi_u)
	var ky := -UPPER_LEN * cos(phi_u)
	var phi_l := atan2(fz - kz, -(-h - ky))
	# Rotation about +X by r swings a down-pointing bone's tip toward -Z, hence the minus.
	(L["hip"] as Node3D).rotation.x = -phi_u
	(L["knee"] as Node3D).rotation.x = -(phi_l - phi_u)


func current_speed() -> float:
	return _speed


func gait_name() -> String:
	return _gait_name


func paw_in_stance(i: int) -> bool:
	return bool(_stance[i])


func paw_world(i: int) -> Vector3:
	var knee := (_legs[i] as Dictionary)["knee"] as Node3D
	return knee.global_transform * Vector3(0.0, -LOWER_LEN, 0.0)


func is_running_off() -> bool:
	return _runoff


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


func _grounded(p: Vector3) -> Vector3:
	return Vector3(p.x, Terrain.surface_y(p.x, p.z), p.z)


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


# ---------------------------------------------------------------- set sequence gate

func _seq() -> Node:
	if _sequence == null or not is_instance_valid(_sequence):
		_sequence = get_tree().get_first_node_in_group("opening_sequence") if is_inside_tree() else null
	return _sequence


## Open when there is no sequence (other scenes), or the drive step is live and the ambush has
## sprung (or a debug force_state armed it).
func _gate_open() -> bool:
	var seq := _seq()
	return seq == null or (_armed and bool(seq.call("is_step_active", SEQ_STEP)))


func _not_yet() -> String:
	var seq := _seq()
	return String(seq.call("not_yet_text")) if seq else ""

