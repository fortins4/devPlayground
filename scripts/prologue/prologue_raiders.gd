extends Node3D
class_name PrologueRaiders
## Raid day, steps 4–6 (raid-option1-spec rev 12): the forage party from the Bannow landing coming
## up the farm lane at first light, as Cian sees it from the bank (step 5). Normans: one mounted
## leader in a knee-length mail hauberk, coif and conical nasal helm with a kite shield and a lance
## on a small horse (~14 hands); three serjeants on foot in padded aketons (one in a short mail
## shirt) with nasal helms or caps, ~2.5 m spears and kite shields slung on the march; five Welsh
## and Flemish archers with stout unpolished wild-elm self-bows and arrows in a bag at the belt
## (hood or cap, no armour beyond a padded jack); and in front an Irish guide in léine and brat with
## two light spears. Nobody is named and nothing says who they are.
## They walk up the lane from beyond Bend6 at a careful walk and stop at a hold point below the
## ráth (for step 7, not built here). The dog is already dead in the grass (never shown).
## Sight: DetectionSensors on the guide (in front, looking ahead) and the rider (eye ~2.4 m), with
## the dawn light-and-mist factor. ALERT on Cian → `spotted` (the raid sequence sets `seen`): the
## party hurries on to a nearer hold point and the archers put arrows on their strings (no
## shooting at people yet).

signal spotted(by: Node3D)

const VillagerScript := preload("res://scripts/prologue/prologue_villager.gd")
const SensorScript := preload("res://systems/stealth/detection_sensor.gd")
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const HORSE_SCENE := "res://scenes/characters/horse/horse.tscn"

## The lane from the south (PathMarkers Bend6 → Bend5 → Bend4 → Bend3 → Bend2), walked upward.
const LANE: Array[Vector3] = [Vector3(-2.0, 0, 118.0), Vector3(10.0, 0, 92.0), Vector3(-12.0, 0, 70.0), Vector3(-18.0, 0, 54.0), Vector3(-15.0, 0, 37.0)]
## How far along the lane (m from LANE[0]) the head of the column stops: unseen / seen.
const HOLD_UNSEEN := 74.0   ## just short of Bend3 (−18, 54), ~42 m below the gate
const HOLD_SEEN := 92.0     ## past Bend3 toward Bend2, ~30 m below the gate
const START_S := 6.0
const WALK := 1.25          ## a careful walk in the half-light behind a guide
const HURRY := 2.1          ## a fast walk once they know they're seen
## Column order from the front: [role, gap behind the one in front (m)].
const ORDER := [
	["guide", 0.0], ["serjeant", 4.0], ["serjeant", 1.8], ["rider", 2.6], ["serjeant", 2.6],
	["archer", 2.0], ["archer", 1.4], ["archer", 1.6], ["archer", 1.4], ["archer", 1.5],
]
const LIGHT_FACTOR := 0.5   ## grey first light and ground mist: half the daylight sight range

var men: Array[Node3D] = []
var guide: Node3D = null
var rider: Node3D = null
var horse: Node3D = null
var _sensors: Array[Node] = []
var _offsets: Array[float] = []
var _s: float = START_S
var _speed: float = WALK
var _hold: float = HOLD_UNSEEN
var _running: bool = false
var _seen: bool = false
var _horse_legs: Array[Node3D] = []
var _horse_t: float = 0.0
var _lane_len: Array[float] = []


func _ready() -> void:
	add_to_group("prologue_raiders")
	top_level = true
	global_transform = Transform3D.IDENTITY
	var acc := 0.0
	_lane_len.append(0.0)
	for i in range(1, LANE.size()):
		acc += Vector2(LANE[i].x - LANE[i - 1].x, LANE[i].z - LANE[i - 1].z).length()
		_lane_len.append(acc)
	_spawn()
	_place_all(0.0)


func start() -> void:
	_running = true
	print("RAIDERS_START head_s=%.1f" % _s)


func is_seen() -> bool:
	return _seen


func head_s() -> float:
	return _s


func hold_s() -> float:
	return _hold


func is_holding() -> bool:
	return _s >= _hold - 0.01


func sensors() -> Array[Node]:
	return _sensors


func max_awareness() -> int:
	var m := 0
	for sn in _sensors:
		m = maxi(m, int(sn.get("awareness")))
	return m


func max_meter() -> float:
	var m := 0.0
	for sn in _sensors:
		m = maxf(m, float(sn.get("meter")))
	return m


## Smoke / capture: move the column head to `s` metres along the lane.
func debug_set_head(s: float) -> void:
	_s = clampf(s, 0.0, _hold)
	_place_all(0.0)


func archers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for m in men:
		if StringName(m.get_meta("role", &"")) == &"archer":
			out.append(m)
	return out


## Point (and lane tangent) `s` metres along the lane from LANE[0].
func lane_point(s: float) -> Array:
	var ss := clampf(s, 0.0, _lane_len[_lane_len.size() - 1])
	for i in range(1, LANE.size()):
		if ss <= _lane_len[i] or i == LANE.size() - 1:
			var seg := _lane_len[i] - _lane_len[i - 1]
			var u := (ss - _lane_len[i - 1]) / maxf(seg, 0.001)
			var p := LANE[i - 1].lerp(LANE[i], clampf(u, 0.0, 1.0))
			var dir := (LANE[i] - LANE[i - 1]).normalized()
			return [p, dir]
	return [LANE[0], Vector3.FORWARD]


func _physics_process(delta: float) -> void:
	if not _running:
		return
	var moving := _s < _hold - 0.01
	if moving:
		_s = minf(_hold, _s + _speed * delta)
	_place_all(delta)
	_tick_horse(delta, _speed if moving else 0.0)
	if not _seen:
		for sn in _sensors:
			if int(sn.get("awareness")) == 2:
				_on_seen(sn.get_parent() as Node3D)
				break


func _on_seen(by: Node3D) -> void:
	_seen = true
	_hold = HOLD_SEEN
	_speed = HURRY
	for a in archers():
		a.call("set_nocked", true)
	if guide:
		# Points up at the bank with his free (left) hand; the light spears stay in his right.
		guide.call("reach_left", Terrain.surface_point(Vector3(2.4, 0, 17.45), 1.2), 1.0)
	print("RAIDERS_SPOTTED by=%s head_s=%.1f" % [by.name if by else "?", _s])
	spotted.emit(by)


func _place_all(_delta: float) -> void:
	var back := 0.0
	for i in men.size():
		back += float(ORDER[i][1])
		var m := men[i]
		var pd: Array = lane_point(_s - back)
		var p: Vector3 = pd[0]
		var d: Vector3 = pd[1]
		# Two-abreast where the lane is wide enough: alternate a little either side of its line.
		var side := Vector3(-d.z, 0.0, d.x) * (0.55 if i % 2 == 0 else -0.55) * (0.0 if i == 0 else 1.0)
		var target := p + side
		var yaw := atan2(-d.x, -d.z)
		var cur := m.global_position
		if cur.distance_to(Vector3(target.x, cur.y, target.z)) > 3.0 or _delta <= 0.0:
			m.call("place", target, yaw)
		else:
			m.call("walk_path", [target], maxf(_speed * 1.4, 0.4) if _s < _hold - 0.01 else 0.6)
			if _s >= _hold - 0.01:
				m.call("face_yaw", yaw)
	if horse and rider:
		horse.global_position = Terrain.surface_point(rider.global_position, 0.0)
		horse.rotation.y = rider.rotation.y


func _tick_horse(delta: float, v: float) -> void:
	if _horse_legs.is_empty():
		return
	if v > 0.05:
		_horse_t += delta * v * 1.6
	var a := 0.32 * clampf(v / 1.5, 0.0, 1.0)
	# Four-beat walk: LH, LF, RH, RF a quarter-cycle apart.
	var phase := [0.25, 0.75, 0.0, 0.5]  # FL, FR, BL, BR
	for i in _horse_legs.size():
		_horse_legs[i].rotation.x = sin(TAU * (_horse_t + phase[i])) * a


# ---------------------------------------------------------------- the party

func _palette(role: String, i: int) -> Dictionary:
	var skin: Color = [Color(0.84, 0.68, 0.56), Color(0.78, 0.62, 0.5), Color(0.86, 0.72, 0.6)][i % 3]
	var base := {
		"skin": skin, "hair": [Color(0.3, 0.2, 0.12), Color(0.5, 0.36, 0.2), Color(0.2, 0.15, 0.1)][i % 3],
		"belt": Color(0.24, 0.17, 0.1), "wood": Color(0.45, 0.33, 0.2), "iron": Color(0.42, 0.43, 0.45),
		"shoes": Color(0.25, 0.18, 0.12), "pants": Color(0.36, 0.32, 0.27),
	}
	match role:
		"guide":
			# Léine (saffron-ish linen) and a dark wool brat; bare-legged.
			base.merge({"tunic": Color(0.72, 0.6, 0.34), "skirt": Color(0.7, 0.58, 0.33), "cloak": Color(0.26, 0.24, 0.2),
				"wrap": Color(0.7, 0.58, 0.33), "pants": skin.darkened(0.08), "shoes": skin.darkened(0.2)}, true)
		"rider":
			# Knee-length mail hauberk with long sleeves, mail coif under the helm, hose and boots.
			base.merge({"tunic": Color(0.44, 0.45, 0.47), "skirt": Color(0.42, 0.43, 0.45), "cloak": Color(0.36, 0.14, 0.12),
				"wrap": Color(0.44, 0.45, 0.47), "hair": Color(0.44, 0.45, 0.47), "pants": Color(0.3, 0.26, 0.22)}, true)
		"serjeant":
			var mail := i == 2
			var c := Color(0.43, 0.44, 0.46) if mail else Color(0.74, 0.7, 0.6)  # mail shirt / padded aketon
			base.merge({"tunic": c, "skirt": c.darkened(0.05), "cloak": Color(0.38, 0.34, 0.28), "wrap": c}, true)
		_:
			# Archers: undyed wool tunic, a padded jack on some, hood.
			var t: Color = [Color(0.55, 0.5, 0.4), Color(0.48, 0.42, 0.32), Color(0.62, 0.58, 0.48)][i % 3]
			base.merge({"tunic": t, "skirt": t.darkened(0.06), "cloak": Color(0.34, 0.32, 0.26), "wrap": t.darkened(0.04)}, true)
	return base


func _spawn() -> void:
	for i in ORDER.size():
		var role: String = ORDER[i][0]
		var v: Node3D = VillagerScript.new()
		v.name = "Raider_%d_%s" % [i, role]
		v.set_meta("role", StringName(role))
		v.set("display_name", "")
		v.set("palette", _palette(role, i))
		match role:
			"guide":
				v.set("stature_m", 1.7)
				v.set("kit", [&"light_spears"])
			"rider":
				v.set("stature_m", 1.72)
				v.set("kit", [&"nasal_helm", &"kite_shield", &"lance", &"sword"])
				v.set("riding", true)
				v.set("y_offset", 0.62)
			"serjeant":
				v.set("stature_m", [1.68, 1.73, 1.7][i % 3])
				v.set("kit", [&"nasal_helm" if i != 4 else &"cap", &"kite_shield", &"spear"])
			_:
				v.set("stature_m", [1.66, 1.7, 1.64, 1.68, 1.72][i % 5])
				v.set("kit", [&"bow", &"arrow_bag", &"cap" if i % 2 == 0 else &"hood_up"])
		add_child(v)
		men.append(v)
		if role == "guide":
			guide = v
			_add_sensor(v, 1.55)
		elif role == "rider":
			rider = v
			_add_sensor(v, 1.75)  # + the 0.62 m seat: eye ~2.4 m above the lane
	_spawn_horse()


func _add_sensor(host: Node3D, eye: float) -> void:
	var sn: Node3D = SensorScript.new()
	sn.name = "DetectionSensor"
	sn.set("show_debug_cone", false)
	sn.set("view_distance", 110.0)
	sn.set("view_half_angle_deg", 55.0)
	sn.set("eye_height", eye)
	sn.set("hearing_range", 7.0)
	sn.set("light_factor", LIGHT_FACTOR)
	host.add_child(sn)
	var lbl := sn.get_node_or_null("AwarenessLabel") as Node3D
	if lbl:
		lbl.visible = false  # no debug readout over their heads in the prologue
	_sensors.append(sn)


func _spawn_horse() -> void:
	var ps := load(HORSE_SCENE) as PackedScene
	if ps == null or rider == null:
		return
	var inst := ps.instantiate()
	var vis := inst.get_node_or_null("Visual") as Node3D
	if vis == null:
		inst.free()
		return
	inst.remove_child(vis)
	inst.free()
	horse = Node3D.new()
	horse.name = "RiderHorse"
	add_child(horse)
	horse.add_child(vis)
	# Legs swing from the shoulder / hip, not their middles.
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var leg := vis.get_node_or_null(leg_name) as Node3D
		if leg == null:
			continue
		var pivot := Node3D.new()
		pivot.name = leg_name + "Pivot"
		pivot.position = leg.position + Vector3(0.0, 0.36, 0.0)
		vis.add_child(pivot)
		vis.remove_child(leg)
		pivot.add_child(leg)
		leg.position = Vector3(0.0, -0.36, 0.0)
		_horse_legs.append(pivot)
	# A saddle with a high cantle and stirrups (the "feet in irons" of the boy's candidate line).
	var saddle := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.5, 0.12, 0.55)
	saddle.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.2, 0.12)
	saddle.material_override = m
	saddle.position = Vector3(0.0, 1.42, 0.05)
	vis.add_child(saddle)
	var cantle := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.42, 0.2, 0.06)
	cantle.mesh = cmesh
	cantle.material_override = m
	cantle.position = Vector3(0.0, 1.55, 0.3)
	vis.add_child(cantle)
