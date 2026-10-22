extends Node3D
class_name PrologueRaidBurning
## Raid day, step 8 (raid-option1-spec rev 12): what Cian sees from the wood edge once the party
## is up at the ráth. Only the farm's own things happen here; nobody hunts for him.
##   1. A serjeant lifts the pen latch and swings the gate back; two of the archers go in behind the
##      six and goad them out through the gateway, over the causeway and away down the lane south.
##   2. Another serjeant goes in at the house door, comes out with a brand from the family's hearth
##      and puts it to the house thatch at the eave, then to the byre's (the hatchet is in there).
##      The roofs burn — thatch and wattle; the turf bank doesn't.
##   3. The herd-hand stands at the pen gate, then goes out after the herd pleading. Out on the
##      causeway an archer shoots him from a dozen paces; he goes down by the ditch, seen from far off
##      in the half-light (Decision 1: no close-up, no blood), and the ditch lip hides him.
##   4. The rider sits his horse on the causeway; the guide keeps back from the fire on the lane.
## Done (`is_done`) when both roofs are well alight, the herd is away past Bend1 and the herd-hand is
## down. Each man still doing a job here is `busy` (an attack on Cian doesn't stop the drive:
## "the herd outcome is unchanged").

signal herd_hand_struck
signal finished

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const FireScript := preload("res://scripts/prologue/prologue_thatch_fire.gd")
const DawnSfx := preload("res://scripts/prologue/prologue_dawn_sfx.gd")

const GATE_MOUTH := Vector3(6.4, 0.0, 15.5)
const CAUSEWAY := Vector3(5.8, 0.0, 20.5)
const RIDER_AT := Vector3(6.2, 0.0, 22.4)
const GUIDE_AT := Vector3(0.8, 0.0, 26.0)
const GUARD_AT := Vector3(8.0, 0.0, 17.6)
const SPARE_AT: Array[Vector3] = [Vector3(11.0, 0.0, 23.0), Vector3(9.5, 0.0, 28.5)]
const SHOOTER_AT := Vector3(12.5, 0.0, 29.0)
const PEN_GATE := Vector3(6.5, 0.0, 9.9)
const OPENER_STAND := Vector3(6.1, 0.0, 10.9)
const OPENER_ASIDE := Vector3(8.9, 0.0, 12.2)
const DROVER_IN: Array[Vector3] = [Vector3(4.2, 0.0, 3.6), Vector3(9.0, 0.0, 3.6)]
const HOUSE_C := Vector3(-7.2, 0.0, -1.73)
const HOUSE_DOOR_OUT := Vector3(-7.2, 0.0, 2.7)
const HOUSE_IN := Vector3(-7.2, 0.0, -0.4)
const HOUSE_EAVE_STAND := Vector3(-10.3, 0.0, 2.3)
const BYRE_STAND := Vector3(2.3, 0.0, 0.9)
const BYRE_EAVE := Vector3(3.0, 2.05, 0.1)
## Cattle way out: through the pen gate, the gateway, over the causeway and down the lane south.
const HERD_WAY: Array[Vector3] = [Vector3(6.5, 0.0, 8.2), Vector3(6.5, 0.0, 11.8), Vector3(6.4, 0.0, 15.5), Vector3(5.8, 0.0, 20.5),
	Vector3(4.0, 0.0, 25.0), Vector3(-5.5, 0.0, 31.0), Vector3(-15.0, 0.0, 37.0), Vector3(-17.0, 0.0, 46.0), Vector3(-18.0, 0.0, 54.0), Vector3(-15.0, 0.0, 62.0)]
const HH_AT_GATE := Vector3(5.2, 0.0, 11.3)
const HH_OUT: Array[Vector3] = [Vector3(5.6, 0.0, 13.2), Vector3(6.0, 0.0, 16.2), Vector3(5.2, 0.0, 19.6), Vector3(4.3, 0.0, 21.6)]
const HH_FALL_YAW := -1.2   ## facing the shooter (ESE): he goes over backwards, west, to the ditch
const HERD_GAP := 1.9

var _raiders: Node = null
var _cows: Array[Node3D] = []
var _gate: Node = null
var _hh: Node3D = null
var _opener: Node3D = null
var _firer: Node3D = null
var _shooter: Node3D = null
var _drovers: Array[Node3D] = []
var _house_fire: Node3D = null
var _byre_fire: Node3D = null
var _brand: Node3D = null
var _running: bool = false
var _t: float = 0.0
var _phase: Dictionary = {}     ## per-actor state name
var _pt: Dictionary = {}        ## per-actor phase time
var _cow_i: Array[int] = []
var _cow_stuck: Array[float] = []
var _cow_start: Array[float] = []
var _gate_open: bool = false
var _gate_open_at: float = -1.0
var _hh_down: bool = false
var _done: bool = false
var _busy: Dictionary = {}


func setup(raiders: Node, cows: Array, gate: Node, herd_hand: Node3D) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_raiders = raiders
	for c in cows:
		if c is Node3D:
			_cows.append(c)
	_gate = gate
	_hh = herd_hand
	_build_fires()


func house_fire() -> Node3D:
	return _house_fire


func byre_fire() -> Node3D:
	return _byre_fire


func is_running() -> bool:
	return _running


func is_done() -> bool:
	return _done


func herd_hand_down() -> bool:
	return _hh_down


func gate_open() -> bool:
	return _gate_open


func is_busy(m: Node) -> bool:
	return _busy.has(m)


func cows_out_count() -> int:
	var n := 0
	for i in _cow_i.size():
		if _cow_i[i] >= 5:
			n += 1
	return n


func brand_visible() -> bool:
	return _brand != null and _brand.visible


func phase_of(m: Node) -> String:
	return String(_phase.get(m, ""))


func start() -> void:
	if _running:
		return
	_running = true
	_t = 0.0
	var men: Array = _raiders.get("men")
	var serj: Array[Node3D] = _raiders.call("men_with_role", &"serjeant")
	var arch: Array[Node3D] = _raiders.call("men_with_role", &"archer")
	_raiders.call("stop_column")
	for m in men:
		_raiders.call("release", m)
	_opener = serj[0]
	_firer = serj[1]
	var guard: Node3D = serj[2]
	_drovers = [arch[0], arch[1]]
	_shooter = arch[2]
	for m in [_opener, _firer, _shooter, arch[0], arch[1]]:
		_busy[m] = true
	_go(_opener, [GATE_MOUTH, OPENER_STAND], 1.5, "to_gate")
	_go(_firer, [GATE_MOUTH, Vector3(1.5, 0, 10.0), HOUSE_DOOR_OUT], 1.5, "to_door")
	_go(guard, [GUARD_AT], 1.3, "guard")
	_go(_drovers[0], [GATE_MOUTH, Vector3(6.4, 0, 11.4), DROVER_IN[0]], 1.5, "to_pen")
	_go(_drovers[1], [GATE_MOUTH, Vector3(6.6, 0, 11.4), DROVER_IN[1]], 1.5, "to_pen")
	_go(_shooter, [SHOOTER_AT], 1.3, "station")
	_go(arch[3], [SPARE_AT[0]], 1.3, "station")
	_go(arch[4], [SPARE_AT[1]], 1.3, "station")
	var guide: Node3D = _raiders.get("guide")
	var rider: Node3D = _raiders.get("rider")
	if guide:
		_go(guide, [GUIDE_AT], 1.1, "back")
	if rider:
		_go(rider, [RIDER_AT], 0.9, "causeway")
	for i in _cows.size():
		_cow_i.append(-1)
		_cow_stuck.append(0.0)
		_cow_start.append(0.0)
	if _hh:
		_hh.call("walk_path", [HH_AT_GATE], 1.0)
		_phase[_hh] = "at_gate"
	print("RAID_BURNING_START")


func _go(m: Node3D, pts: Array, speed: float, ph: String) -> void:
	if m == null:
		return
	m.call("walk_path", pts, speed)
	_phase[m] = ph
	_pt[m] = 0.0


func _arrived(m: Node3D) -> bool:
	return not bool(m.call("is_walking"))


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	for k in _pt.keys():
		_pt[k] = float(_pt[k]) + delta
	_tick_opener()
	_tick_drovers()
	_tick_cows(delta)
	_tick_firer()
	_tick_herd_hand()
	_tick_stations()
	if not _done and _house_fire.call("is_going") and _byre_fire.call("is_going") and _hh_down and _herd_away():
		_done = true
		print("RAID_BURNING_DONE t=%.1f" % _t)
		finished.emit()


func _herd_away() -> bool:
	if _cow_i.is_empty():
		return false
	for i in _cows.size():
		if _cow_i[i] < 5:
			return false
	return true


func _phase_to(m: Node3D, ph: String) -> void:
	_phase[m] = ph
	_pt[m] = 0.0


# ---------------------------------------------------------------- the pen gate

func _tick_opener() -> void:
	var m := _opener
	match String(_phase.get(m, "")):
		"to_gate":
			if _arrived(m):
				m.call("face_point", PEN_GATE)
				_phase_to(m, "latch")
		"latch":
			var u := clampf(float(_pt[m]) / 0.8, 0.0, 1.0)
			var lp: Vector3 = _gate.call("latch_point") if _gate and _gate.has_method("latch_point") else PEN_GATE + Vector3(0, 1, 0)
			m.call("reach_right", lp, u)
			if _gate:
				_gate.call("set_lead_pose", u, 0.0)
			if u >= 1.0:
				_phase_to(m, "swing")
		"swing":
			var u2 := clampf(float(_pt[m]) / 1.6, 0.0, 1.0)
			if _gate:
				_gate.call("set_lead_pose", 1.0, u2)
				var tip: Vector3 = _gate.call("west_tip_point")
				m.call("reach_right", tip, 1.0 - u2 * 0.6)
			if u2 >= 1.0:
				m.call("reach_right", Vector3.ZERO, 0.0)
				_gate_open = true
				_gate_open_at = _t
				print("RAID_PEN_OPENED t=%.1f" % _t)
				m.call("walk_path", [OPENER_ASIDE], 1.2)
				_phase_to(m, "aside")
		"aside":
			if _arrived(m):
				m.call("face_point", GATE_MOUTH)
				_busy.erase(m)
				_phase_to(m, "stand")


# ---------------------------------------------------------------- the drive

func _tick_drovers() -> void:
	for k in _drovers.size():
		var m := _drovers[k]
		match String(_phase.get(m, "")):
			"to_pen":
				if _arrived(m):
					m.call("face_point", PEN_GATE)
					_phase_to(m, "wait")
			"wait":
				if _gate_open and _cow_i.size() > 0:
					_phase_to(m, "drive")
			"drive":
				# Walk on behind the last cow, a few paces back and to one side, the bow staves out
				# low to poke at her hocks.
				var last := _last_cow()
				if last:
					var lp := last.global_position
					var nxt := _cow_target(_cows.find(last))
					var dir := (nxt - lp)
					dir.y = 0.0
					dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
					var side := Vector3(-dir.z, 0, dir.x) * (1.0 if k == 0 else -1.0)
					var want := lp - dir * 2.6 + side * 1.1
					if m.global_position.distance_to(Vector3(want.x, m.global_position.y, want.z)) > 0.6:
						m.call("walk_path", [want], 1.7)
					m.call("reach_left", lp + Vector3(0, 0.6, 0), 0.5 + 0.3 * sin(_t * 3.0 + k))
					if int(_cow_i[_cows.find(last)]) >= 7:
						m.call("reach_left", Vector3.ZERO, 0.0)
						_busy.erase(m)
						_phase_to(m, "done")


func _last_cow() -> Node3D:
	var best: Node3D = null
	var bi := 99
	for i in _cows.size():
		if _cow_i[i] < bi:
			bi = _cow_i[i]
			best = _cows[i]
	return best


func _cow_target(i: int) -> Vector3:
	if i < 0:
		return HERD_WAY[0]
	return HERD_WAY[clampi(_cow_i[i], 0, HERD_WAY.size() - 1)]


func _tick_cows(delta: float) -> void:
	if not _gate_open:
		return
	for i in _cows.size():
		var c := _cows[i]
		if not is_instance_valid(c):
			continue
		if _cow_i[i] < 0:
			# Out one at a time, nearest the gate first.
			if _t - _gate_open_at >= 0.6 + HERD_GAP * float(_order_of(i)):
				_cow_i[i] = 0
				c.set("delivered", true)
				c.call("set_pen_slot", HERD_WAY[0])
				if i % 2 == 0:
					DawnSfx.play(self, &"low", c.global_position, -4.0, 8.0)
			continue
		var has_slot := bool(c.get("_has_slot"))
		var tgt := HERD_WAY[_cow_i[i]]
		var d := Vector2(c.global_position.x - tgt.x, c.global_position.z - tgt.z).length()
		_cow_stuck[i] += delta
		if (not has_slot or d < 0.9 or _cow_stuck[i] > 6.0) and _cow_i[i] < HERD_WAY.size() - 1:
			_cow_i[i] += 1
			_cow_stuck[i] = 0.0
			var p := HERD_WAY[_cow_i[i]] + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) * (1.0 if _cow_i[i] > 3 else 0.0)
			c.call("set_pen_slot", p)
			if _cow_i[i] == HERD_WAY.size() - 1:
				c.call("set_home_spot", p)


var _order: Array[int] = []


func _order_of(i: int) -> int:
	if _order.is_empty():
		var idx: Array = range(_cows.size())
		idx.sort_custom(func(a, b) -> bool:
			return _cows[a].global_position.distance_to(PEN_GATE) < _cows[b].global_position.distance_to(PEN_GATE))
		for k in idx:
			_order.append(int(k))
	return _order.find(i)


# ---------------------------------------------------------------- the brand

func _tick_firer() -> void:
	var m := _firer
	match String(_phase.get(m, "")):
		"to_door":
			if _arrived(m):
				m.call("walk_path", [HOUSE_IN], 1.0)
				_phase_to(m, "going_in")
		"going_in":
			if _arrived(m):
				m.visible = false   # inside, at the hearth
				_phase_to(m, "inside")
		"inside":
			if float(_pt[m]) > 2.4:
				m.visible = true
				_show_brand(m, true)
				m.call("walk_path", [HOUSE_DOOR_OUT, HOUSE_EAVE_STAND], 1.2)
				print("RAID_BRAND_TAKEN")
				_phase_to(m, "to_eave")
		"to_eave":
			if _arrived(m):
				_phase_to(m, "fire_house")
		"fire_house":
			var eave := _house_eave_point()
			m.call("face_point", eave)
			m.call("reach_right", eave, clampf(float(_pt[m]) / 0.6, 0.0, 1.0))
			if float(_pt[m]) > 1.6:
				_house_fire.call("ignite", eave)
				m.call("reach_right", Vector3.ZERO, 0.0)
				m.call("walk_path", [Vector3(-4.0, 0, 7.5), Vector3(0.8, 0, 6.0), BYRE_STAND], 1.3)
				_phase_to(m, "to_byre")
		"to_byre":
			if _arrived(m):
				_phase_to(m, "fire_byre")
		"fire_byre":
			m.call("face_point", BYRE_EAVE)
			m.call("reach_right", BYRE_EAVE, clampf(float(_pt[m]) / 0.6, 0.0, 1.0))
			if float(_pt[m]) > 1.6:
				_byre_fire.call("ignite", BYRE_EAVE)
				m.call("reach_right", Vector3.ZERO, 0.0)
				# The brand goes up onto the byre thatch after it.
				_show_brand(m, false)
				m.call("walk_path", [Vector3(1.5, 0, 9.0), GATE_MOUTH + Vector3(-0.8, 0, 1.4)], 1.3)
				_phase_to(m, "out")
		"out":
			if _arrived(m):
				m.call("face_point", HOUSE_C)
				_busy.erase(m)
				_phase_to(m, "stand")
	if _brand and _brand.visible:
		var hand: Vector3 = m.call("right_hand_point") if m.has_method("right_hand_point") else m.global_position + Vector3(0, 1.0, 0)
		_brand.global_position = hand
		_brand.global_rotation = Vector3(0.0, m.rotation.y, 0.0)


func _house_eave_point() -> Vector3:
	var d := (HOUSE_EAVE_STAND - HOUSE_C)
	d.y = 0.0
	d = d.normalized()
	var p := HOUSE_C + d * 4.05
	return Vector3(p.x, Terrain.surface_y(p.x, p.z) + 1.78, p.z)


func _show_brand(m: Node3D, on: bool) -> void:
	if _brand == null:
		_brand = Node3D.new()
		_brand.name = "Brand"
		add_child(_brand)
		_brand.top_level = true
		var stick := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.03
		cm.height = 0.7
		stick.mesh = cm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.22, 0.16, 0.1)
		stick.material_override = wm
		stick.position = Vector3(0, 0.25, 0)
		_brand.add_child(stick)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		head.mesh = sm
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.albedo_color = Color(1.0, 0.55, 0.15)
		head.material_override = hm
		head.position = Vector3(0, 0.6, 0)
		_brand.add_child(head)
		var fl := CPUParticles3D.new()
		fl.amount = 24
		fl.lifetime = 0.5
		fl.local_coords = false
		fl.direction = Vector3.UP
		fl.spread = 20.0
		fl.initial_velocity_min = 0.4
		fl.initial_velocity_max = 0.9
		fl.gravity = Vector3(0, 1.2, 0)
		fl.scale_amount_min = 0.12
		fl.scale_amount_max = 0.22
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
		g.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
		fl.color_ramp = g
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.vertex_color_use_as_albedo = true
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fm.albedo_texture = FireScript._soft_tex(true)
		q.material = fm
		fl.mesh = q
		fl.position = Vector3(0, 0.62, 0)
		_brand.add_child(fl)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.25)
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position = Vector3(0, 0.65, 0)
		_brand.add_child(l)
	_brand.visible = on


# ---------------------------------------------------------------- the herd-hand

func _tick_herd_hand() -> void:
	if _hh == null:
		return
	var ph := String(_phase.get(_hh, ""))
	match ph:
		"at_gate":
			if _arrived(_hh):
				_hh.call("face_point", PEN_GATE + Vector3(0, 0, -2))
			# He goes out after them once the fourth is through the gateway.
			if _count_past(2) >= 4:
				_hh.call("walk_path", HH_OUT, 1.15)
				_phase_to(_hh, "after_herd")
		"after_herd":
			_hh.call("reach_right", _hh.global_position + Vector3(0.4, 1.3, 2.0), 0.6)
			if _arrived(_hh):
				_hh.call("face_yaw", HH_FALL_YAW)
				_hh.call("reach_left", _hh.global_position + Vector3(1.6, 1.4, 0.5), 0.8)
				_phase_to(_hh, "pleading")
		"pleading":
			if float(_pt[_hh]) > 1.2 and _shooter and String(_phase.get(_shooter, "")) == "station" and _arrived(_shooter):
				_shooter.call("face_point", _hh.global_position)
				_shooter.call("set_drawing", true)
				_phase_to(_hh, "drawn_on")
		"drawn_on":
			_shooter.call("face_point", _hh.global_position)
			if bool(_shooter.call("is_drawn")) and float(_pt[_hh]) > 1.2:
				var aim := _hh.global_position + Vector3(0, 1.15, 0)
				_raiders.call("loose_one", _shooter, aim, true, _on_hh_hit)
				_phase_to(_hh, "shot")
				print("RAID_HERD_HAND_SHOT dist=%.1f" % _shooter.global_position.distance_to(_hh.global_position))
		"down":
			if float(_pt[_hh]) > 2.5 and _shooter:
				_shooter.call("set_nocked", false)
				_busy.erase(_shooter)


func _on_hh_hit() -> void:
	_hh.call("reach_right", Vector3.ZERO, 0.0)
	_hh.call("reach_left", Vector3.ZERO, 0.0)
	_hh.call("set_down", true, true, 0.1)  # the still body pose (villager DOWN_POSE), where he stood
	_hh_down = true
	_phase_to(_hh, "down")
	print("RAID_HERD_HAND_DOWN at=%s" % _hh.global_position)
	herd_hand_struck.emit()


func _count_past(way_i: int) -> int:
	var n := 0
	for i in _cow_i.size():
		if _cow_i[i] > way_i:
			n += 1
	return n


func _tick_stations() -> void:
	for m in _phase.keys():
		if m == _hh or not is_instance_valid(m):
			continue
		var ph := String(_phase[m])
		if (ph == "station" or ph == "guard" or ph == "back" or ph == "causeway") and _arrived(m) and float(_pt[m]) > 0.2:
			if ph == "back" or ph == "causeway":
				m.call("face_point", GATE_MOUTH + Vector3(0, 0, -4))
			elif ph == "guard":
				m.call("face_point", GATE_MOUTH + Vector3(-3, 0, -2))
			elif m != _shooter or String(_phase.get(_hh, "")) in ["at_gate", "after_herd", "down"]:
				m.call("face_point", CAUSEWAY)


# ---------------------------------------------------------------- the fires

func _build_fires() -> void:
	var root := get_tree().root
	var house_mesh := root.find_child("HouseThatch", true, false) as MeshInstance3D
	var byre_mesh := root.find_child("ByreThatch", true, false) as MeshInstance3D
	var gy := Terrain.surface_y(HOUSE_C.x, HOUSE_C.z)
	# House: points on the thatch cone (eave r 4.2 at 1.75 m up to r 0.32 at 5.05 m).
	var hp := PackedVector3Array()
	for ring in 6:
		var u := float(ring) / 5.0
		var r := lerpf(4.15, 0.6, u)
		var y := gy + lerpf(1.78, 4.8, u)
		var n := int(lerpf(18.0, 4.0, u))
		for k in n:
			var a := TAU * (float(k) + 0.5 * float(ring % 2)) / float(n)
			hp.append(Vector3(HOUSE_C.x + cos(a) * r, y, HOUSE_C.z + sin(a) * r))
	_house_fire = FireScript.new()
	_house_fire.name = "HouseFire"
	add_child(_house_fire)
	_house_fire.call("setup", hp, Vector3(HOUSE_C.x, gy + 5.0, HOUSE_C.z), [house_mesh] if house_mesh else [])
	# Byre: points over the two roof slopes (eaves at 2.0 m, ridge at 3.5 m, x 2.95..11.05).
	var by := Vector3(7.0, Terrain.surface_y(7.0, -2.2), -2.2)
	var bp := PackedVector3Array()
	for ix in 9:
		var x := lerpf(3.0, 11.0, float(ix) / 8.0)
		for iz in 5:
			var v := float(iz) / 4.0
			var z := lerpf(-2.3, 2.3, v)
			var h := 1.5 * (1.0 - absf(z) / 2.3)
			bp.append(Vector3(x, by.y + 2.0 + h + 0.05, by.z + z))
	_byre_fire = FireScript.new()
	_byre_fire.name = "ByreFire"
	add_child(_byre_fire)
	_byre_fire.call("setup", bp, by + Vector3(0, 3.6, 0), [byre_mesh] if byre_mesh else [])
