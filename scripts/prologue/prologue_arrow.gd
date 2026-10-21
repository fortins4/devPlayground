extends Node3D
class_name PrologueArrow
## Raid day, steps 7–8: an arrow in flight from an elm self-bow (ash shaft, grey goose fletching,
## a plain iron head). It flies a shallow arc from the string to `to` in `flight` seconds, turned
## along its path. A miss goes into the turf and stays there, two-thirds of the shaft showing; a hit
## just ends (the target's hurt flash shows it; no blood, no arrow left in anyone).

const LEN := 0.78

var _from: Vector3
var _to: Vector3
var _flight: float = 0.6
var _t: float = 0.0
var _arc: float = 0.6
var _stick: bool = true
var _done: Callable
var _flying: bool = false
var _life: float = 40.0


static func shoot(host: Node, from: Vector3, to: Vector3, stick: bool, done: Callable = Callable()) -> Node3D:
	var a: Node3D = (load("res://scripts/prologue/prologue_arrow.gd") as GDScript).new()
	host.add_child(a)
	a.call("_launch", from, to, stick, done)
	return a


func _launch(from: Vector3, to: Vector3, stick: bool, done: Callable) -> void:
	top_level = true
	_build()
	_from = from
	_to = to
	_stick = stick
	_done = done
	var d := from.distance_to(to)
	_flight = clampf(d / 48.0, 0.12, 2.0)
	_arc = d * 0.035
	_flying = true
	_place(0.0)


func is_flying() -> bool:
	return _flying


func _pos_at(u: float) -> Vector3:
	return _from.lerp(_to, u) + Vector3.UP * (_arc * 4.0 * u * (1.0 - u))


func _place(u: float) -> void:
	var p := _pos_at(u)
	var q := _pos_at(minf(u + 0.02, 1.0)) if u < 0.98 else p + (_to - _from).normalized() + Vector3.DOWN * 0.15
	var dir := q - p
	if dir.length() < 0.001:
		dir = (_to - _from)
	global_position = p
	if dir.length() > 0.001:
		look_at(p + dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	if not _flying:
		_life -= delta
		if _life <= 0.0:
			queue_free()
		return
	_t += delta
	var u := clampf(_t / _flight, 0.0, 1.0)
	_place(u)
	if u >= 1.0:
		_flying = false
		if _stick:
			# Into the turf: the head and a third of the shaft buried, at the angle it came down.
			var flat := Vector3(_to.x - _from.x, 0.0, _to.z - _from.z)
			if flat.length() < 0.01:
				flat = Vector3.FORWARD
			var dn := (flat.normalized() + Vector3.DOWN * 0.7).normalized()
			global_position = _to + dn * (LEN * 0.3)
			look_at(global_position + dn, Vector3.UP)
		else:
			visible = false
			_life = 0.1
		if _done.is_valid():
			_done.call()


func _build() -> void:
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045
	cm.bottom_radius = 0.0045
	cm.height = LEN
	cm.radial_segments = 4
	cm.rings = 1
	shaft.mesh = cm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.62, 0.52, 0.36)
	shaft.material_override = wm
	shaft.rotation.x = PI * 0.5   # along −Z (look_at forward)
	shaft.position = Vector3(0, 0, LEN * 0.5)
	add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.011
	hm.height = 0.06
	hm.radial_segments = 4
	hm.rings = 1
	head.mesh = hm
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.3, 0.3, 0.32)
	head.material_override = im
	head.rotation.x = -PI * 0.5
	head.position = Vector3(0, 0, -0.03)
	add_child(head)
	var fl := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.035, 0.035, 0.12)
	fl.mesh = fm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.7, 0.7, 0.68)
	fl.material_override = gm
	fl.position = Vector3(0, 0, LEN - 0.08)
	fl.rotation.z = PI * 0.25
	add_child(fl)
