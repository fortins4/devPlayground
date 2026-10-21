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
## Step 7: after a pause at the hold the party comes on up the rest of the lane (Bend2 → Bend1 →
## the causeway → the gate mouth) — `advance()`; `reached_causeway()` is the step 7 deadline.
## Sight stays on (ALERT → `spotted`) except while `watch` is off (step 6: nobody in the column is
## looking for him while he is indoors at the peg; the spec has no seen in step 6).
## Attack branch (Decision 6, 6.16): `start_combat(cian)` — the serjeants come at him with levelled
## spears and the archers loose from range; every blow or arrow that lands is `struck` (the raid
## sequence applies it and downs him; nobody here kills). Each man has a Hurtbox and a CombatSystem
## (team 1) wearing what he wears: mail (the rider, one serjeant), padded (the other serjeants, the
## jacked archers) or none (the guide, two archers) — the goad and the knife do next to nothing
## through padding and nothing through mail.
## Step 8: `release(man)` takes a man out of the column for the burning (PrologueRaidBurning walks
## him); `stop_column()` ends the column walk altogether.

signal spotted(by: Node3D)
signal struck(target: Node3D, amount: float, kind: StringName, from: Node3D)
signal arrived

const VillagerScript := preload("res://scripts/prologue/prologue_villager.gd")
const SensorScript := preload("res://systems/stealth/detection_sensor.gd")
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const HORSE_SCENE := "res://scenes/characters/horse/horse.tscn"

## The lane from the south (PathMarkers Bend6 → Bend5 → Bend4 → Bend3 → Bend2), walked upward.
## Then on (step 7) to Bend1 (4, 25), the causeway foot over the ditch and the gate mouth.
const LANE: Array[Vector3] = [Vector3(-2.0, 0, 118.0), Vector3(10.0, 0, 92.0), Vector3(-12.0, 0, 70.0), Vector3(-18.0, 0, 54.0), Vector3(-15.0, 0, 37.0),
	Vector3(4.0, 0, 25.0), Vector3(5.8, 0, 20.5), Vector3(6.4, 0, 15.5)]
const CAUSEWAY_I := 6       ## LANE index of the causeway foot
const ARRIVE_BACK := 2.5    ## the head stops this far short of the gate mouth
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
const LOW_MIST_TOP := 1.4   ## the ground mist's top (OpeningTimeOfDay MIST_TOP): low figures in it…
const LOW_MIST_HIDE := 22.0 ## …are lost beyond this (crouched in the ditch / grass)
const ArrowScript := preload("res://scripts/prologue/prologue_arrow.gd")
const DawnSfx := preload("res://scripts/prologue/prologue_dawn_sfx.gd")
## Attack branch tuning.
const CLOSE_SPEED := 3.2    ## serjeants running in with spears levelled
const SPEAR_REACH := 2.1
const THRUST_EVERY := 1.3
const THRUST_DMG := 24.0
const THRUST_HIT := 0.65
const ARROW_DMG := 18.0
const LOOSE_EVERY := 2.6
const BOW_RANGE := 60.0
const BOW_MIN := 4.0

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
var watch: bool = true
var _column: bool = true
var _free: Dictionary = {}
var _combat_target: Node3D = null
var _cd: Dictionary = {}
var _arrived: bool = false
var _arrows: Array[Node3D] = []
var arrows_loosed: int = 0
## Step 8: men still at a job for the burning (driving the herd, the brand) keep at it in a fight.
var busy_check: Callable = Callable()
var thrusts: int = 0


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
	if horse and rider:
		horse.global_position = Terrain.surface_point(rider.global_position, 0.0)
		horse.rotation.y = rider.rotation.y


func start() -> void:
	_running = true
	print("RAIDERS_START head_s=%.1f" % _s)


func is_seen() -> bool:
	return _seen


## Step 6 / 7: sight on or off (off: meters cleared and the sensors idle).
func set_watch(on: bool) -> void:
	watch = on
	for sn in _sensors:
		sn.set_physics_process(on)
		sn.call("force_awareness", 0)


## Step 7: on from the hold up the rest of the lane to the gate mouth.
func advance(speed: float = -1.0) -> void:
	_hold = _lane_len[_lane_len.size() - 1] - ARRIVE_BACK
	_speed = speed if speed > 0.0 else (HURRY if _seen else WALK)
	_running = true
	print("RAIDERS_ADVANCE head_s=%.1f speed=%.2f" % [_s, _speed])


func causeway_s() -> float:
	return _lane_len[CAUSEWAY_I]


func reached_causeway() -> bool:
	return _s >= causeway_s() - 0.5


func has_arrived() -> bool:
	return _arrived


func release(m: Node3D) -> void:
	_free[m] = true


func is_released(m: Node3D) -> bool:
	return _free.has(m)


func stop_column() -> void:
	_column = false


func men_with_role(role: StringName) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for m in men:
		if StringName(m.get_meta("role", &"")) == role:
			out.append(m)
	return out


func in_combat() -> bool:
	return _combat_target != null


## Smoke: count of arrows in flight or stuck in the turf.
func arrow_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for a in _arrows:
		if is_instance_valid(a):
			out.append(a)
	return out


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
	if horse and rider:
		horse.global_position = Terrain.surface_point(rider.global_position, 0.0)
		horse.rotation.y = rider.rotation.y


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
	if _combat_target:
		_tick_combat(delta)
	if horse and rider:
		horse.global_position = Terrain.surface_point(rider.global_position, 0.0)
		horse.rotation.y = rider.rotation.y
	if not _running:
		return
	var moving := _column and _s < _hold - 0.01
	if moving:
		_s = minf(_hold, _s + _speed * delta)
	if _column:
		_place_all(delta)
	if not _arrived and _s >= _lane_len[_lane_len.size() - 1] - ARRIVE_BACK - 0.01:
		_arrived = true
		print("RAIDERS_ARRIVED")
		arrived.emit()
	var rv := float(rider.get("_speed_now")) if rider and not _column else (_speed if moving else 0.0)
	_tick_horse(delta, rv)
	if not watch:
		return
	if not _seen:
		for sn in _sensors:
			if int(sn.get("awareness")) == 2:
				_on_seen(sn.get_parent() as Node3D)
				break


func _on_seen(by: Node3D) -> void:
	_seen = true
	_hold = maxf(_hold, HOLD_SEEN)  # already coming on past it (step 7): keep on to the gate
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
		if _free.has(m) or (_combat_target and StringName(m.get_meta("role", &"")) != &"rider"):
			continue
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


# ---------------------------------------------------------------- attack branch

## Decision 6: Cian has gone for one of them. Everyone but the rider (he sits his horse on the
## lane) turns on him: spears levelled and run in, bows drawn and loosed from where they stand.
func start_combat(target: Node3D) -> void:
	if _combat_target:
		return
	_combat_target = target
	_seen = true
	var k := 0
	for m in men:
		# Spearmen need a moment to close and level; the bowmen to nock and draw.
		var archer := StringName(m.get_meta("role", &"")) == &"archer"
		_cd[m] = (1.2 + 0.3 * k) if archer else (1.0 + 0.6 * k)
		k += 1
		m.call("set_crouch", false)
		if StringName(m.get_meta("role", &"")) == &"archer":
			m.call("set_nocked", true)
	print("RAIDERS_COMBAT")


func stop_combat() -> void:
	_combat_target = null
	for m in men:
		m.call("level_spear", Vector3.ZERO, 0.0)
		m.call("set_drawing", false)


func _tick_combat(delta: float) -> void:
	var t := _combat_target
	if t == null or not is_instance_valid(t):
		_combat_target = null
		return
	var tp := t.global_position
	for m in men:
		var role := StringName(m.get_meta("role", &""))
		if role == &"rider" or bool(m.call("is_down")):
			continue
		if busy_check.is_valid() and bool(busy_check.call(m)):
			continue
		var to := Vector3(tp.x - m.global_position.x, 0.0, tp.z - m.global_position.z)
		var d := to.length()
		_cd[m] = float(_cd.get(m, 0.0)) - delta
		match role:
			&"serjeant", &"guide":
				m.call("level_spear", tp + Vector3.UP * 1.0, 1.0 if d < 6.0 else 0.0)
				if d > SPEAR_REACH * 0.85:
					m.call("walk_path", [tp - to.normalized() * (SPEAR_REACH * 0.7)], CLOSE_SPEED)
				else:
					m.call("face_point", tp)
					if float(_cd[m]) <= 0.0:
						_cd[m] = THRUST_EVERY
						thrusts += 1
						# He twists away from some of them; most go home.
						if randf() < THRUST_HIT:
							struck.emit(t, THRUST_DMG, &"cut", m)
			&"archer":
				m.call("face_point", tp)
				if d < BOW_MIN:
					m.call("walk_path", [m.global_position - to.normalized() * 3.0], 2.6)
				elif d > BOW_RANGE:
					m.call("walk_path", [tp - to.normalized() * (BOW_RANGE * 0.8)], 2.6)
				else:
					m.call("set_drawing", true)
					if float(_cd[m]) <= 0.0 and bool(m.call("is_drawn")):
						_cd[m] = LOOSE_EVERY
						_loose_at(m, t, d)


func _loose_at(m: Node3D, t: Node3D, d: float) -> void:
	m.call("loose")
	m.call("set_nocked", true)
	arrows_loosed += 1
	var from := m.global_position + Vector3(0, 1.4, 0) + (-m.global_transform.basis.z) * 0.6
	# Half-light, a moving man: the nearer, the likelier.
	var crouch := float(t.call("get_visibility_factor")) if t.has_method("get_visibility_factor") else 1.0
	var p_hit := clampf(0.9 - d / 70.0, 0.2, 0.85) * lerpf(0.6, 1.0, (crouch - 0.55) / 0.45)
	var hit := randf() < p_hit
	var aim := t.global_position + Vector3(0, 1.1, 0)
	if not hit:
		var off := Vector3(randf_range(-2.2, 2.2), 0, randf_range(-2.2, 2.2))
		aim = Terrain.surface_point(t.global_position + off, 0.0)
	DawnSfx.play(self, &"loose", from, -4.0, 6.0)
	var host := self
	var a := ArrowScript.shoot(self, from, aim, not hit, func() -> void:
		if hit and is_instance_valid(t) and host._combat_target == t:
			host.struck.emit(t, ARROW_DMG, &"arrow", m))
	_arrows.append(a)


## Step 8 (and anywhere): an archer looses one arrow at `aim` (a hit if `hit`); `done` on arrival.
func loose_one(m: Node3D, aim: Vector3, hit: bool, done: Callable = Callable()) -> void:
	m.call("loose")
	var from := m.global_position + Vector3(0, 1.4, 0) + (-m.global_transform.basis.z) * 0.6
	DawnSfx.play(self, &"loose", from, -2.0, 8.0)
	arrows_loosed += 1
	_arrows.append(ArrowScript.shoot(self, from, aim, not hit, done))


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
		_add_hurtbox(v, role, i)
		if role == "guide":
			guide = v
			_add_sensor(v, 1.55)
		elif role == "rider":
			rider = v
			_add_sensor(v, 1.75)  # + the 0.62 m seat: eye ~2.4 m above the lane
	_spawn_horse()


## Hurtbox (layer 4: the player's hitbox finds it) and a CombatSystem wearing his armour.
func _add_hurtbox(v: Node3D, role: String, i: int) -> void:
	var hb := Area3D.new()
	hb.name = "Hurtbox"
	hb.collision_layer = 4
	hb.collision_mask = 0
	hb.monitorable = true
	hb.monitoring = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.9 + (0.62 if role == "rider" else 0.0), 0)
	hb.add_child(cs)
	v.add_child(hb)
	var cb := CombatSystem.new()
	cb.name = "CombatSystem"
	cb.team = 1
	cb.starting_weapon = CombatSystem.Weapon.UNARMED
	cb.show_damage_numbers = false
	var arm := &"none"
	match role:
		"rider":
			arm = &"mail"
		"serjeant":
			arm = &"mail" if i == 2 else &"padded"
		"archer":
			arm = &"padded" if i % 2 == 1 else &"none"
	cb.armour = arm
	v.set_meta("armour", arm)
	v.add_child(cb)


func _add_sensor(host: Node3D, eye: float) -> void:
	var sn: Node3D = SensorScript.new()
	sn.name = "DetectionSensor"
	sn.set("show_debug_cone", false)
	sn.set("view_distance", 110.0)
	sn.set("view_half_angle_deg", 55.0)
	sn.set("eye_height", eye)
	sn.set("hearing_range", 7.0)
	sn.set("light_factor", LIGHT_FACTOR)
	sn.set("low_mist_top", LOW_MIST_TOP)
	sn.set("low_mist_hide_beyond", LOW_MIST_HIDE)
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
