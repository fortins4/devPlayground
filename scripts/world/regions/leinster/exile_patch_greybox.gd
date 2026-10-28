@tool
extends Node3D
## Greybox for the exile start (open-world chunk 1): the family's burned ráth, the wood edge west
## of it, the tóchar fen beyond the wood, and the lane south-west to the strand at Bannow.
## May 1169, the morning after the raid: the earthen bank and ditch survive the fire; the thatch
## and wattle of the roundhouse and byre are gone — charred post stumps, burnt wall stubs, roof
## timbers fallen in, ash with a few embers still alive. The cattle are gone and the pen broken.
##
## Same pattern as OpeningFarmGreybox: plain boxes / cylinders built at _ready into an un-owned
## child (shows in the editor, never saved into the .tscn). The anchors (BurnedRath, WoodEdge,
## TocharFen, ExileStart) are authored nodes in leinster_region.tscn; move one in the editor and
## its greybox follows (BannowLane only marks where the lane leaves the ráth). Layout mirrors the prologue farm (opening_terrain.gd /
## opening_farm_greybox.gd): 30 m bank crest, gap to the south, roundhouse west, byre east, pen SE,
## wood to the west.

@export var rath_path: NodePath = ^"BurnedRath"
@export var wood_path: NodePath = ^"WoodEdge"
@export var fen_path: NodePath = ^"TocharFen"
@export var start_path: NodePath = ^"ExileStart"
@export var rebuild: bool = false:
	set(v):
		rebuild = false
		if is_inside_tree():
			build()

const GEN_NAME := "_Generated"

## Ráth (as the prologue farm: opening_terrain.gd RATH_*).
const RATH_R := 15.0
const BANK_H := 1.3
const BANK_HALF := 2.2
const DITCH_OFF := 3.9
const DITCH_HALF := 1.7
const GAP_DIR := Vector2(-0.2631174, 0.9647638)   ## entrance faces SSW, as at home
const GAP_HALF_DEG := 14.0
const BANK_SEGS := 40
## Offsets from the ráth centre (prologue: house (-7.2, -1.73), byre door (3.2, -2.2), pen (7, 6.5)
## with the ráth centre at (0.5, 3)).
const HOUSE_OFF := Vector3(-7.7, 0.0, -4.7)
const HOUSE_R := 3.5
const BYRE_OFF := Vector3(3.0, 0.0, -6.0)
const BYRE_SIZE := Vector2(6.4, 4.2)
const PEN_OFF := Vector3(6.5, 0.0, 3.5)
const PEN_SIZE := Vector2(8.0, 6.0)

## Lane from the gap to the east end of the Bannow strand (region coords, after the gap).
const LANE_PTS: Array[Vector3] = [Vector3(86.5, 0, 26.0), Vector3(80.0, 0, 32.5), Vector3(68.0, 0, 37.0), Vector3(52.0, 0, 39.5), Vector3(36.0, 0, 40.5), Vector3(19.0, 0, 41.0)]

const C_TURF := Color(0.33, 0.42, 0.25)
const C_TURF_SCORCH := Color(0.27, 0.29, 0.19)
const C_DITCH := Color(0.17, 0.2, 0.14)
const C_YARD := Color(0.36, 0.31, 0.23)
const C_POACHED := Color(0.24, 0.19, 0.13)
const C_CHAR := Color(0.09, 0.08, 0.07)
const C_CHAR_WOOD := Color(0.15, 0.12, 0.1)
const C_DAUB_FIRED := Color(0.56, 0.36, 0.26)   ## daub baked red by the fire
const C_ASH := Color(0.36, 0.35, 0.33)
const C_ASH_DARK := Color(0.19, 0.18, 0.17)
const C_EMBER := Color(1.0, 0.36, 0.08)
const C_STONE := Color(0.5, 0.48, 0.43)
const C_WATTLE := Color(0.5, 0.4, 0.25)
const C_TRUNK := Color(0.32, 0.25, 0.18)
const C_TRUNK_ASH := Color(0.45, 0.43, 0.38)
const C_CANOPY := [Color(0.24, 0.38, 0.2), Color(0.28, 0.42, 0.22), Color(0.21, 0.34, 0.18)]
const C_HAZEL := Color(0.3, 0.44, 0.22)
const C_SEDGE := Color(0.34, 0.41, 0.18)
const C_PEAT := Color(0.27, 0.25, 0.15)
const C_POOL := Color(0.07, 0.085, 0.06)
const C_REED := [Color(0.5, 0.52, 0.28), Color(0.44, 0.47, 0.24)]
const C_ALDER := Color(0.22, 0.33, 0.19)
const C_OAK_PLANK := Color(0.29, 0.21, 0.13)
const C_LANE := Color(0.29, 0.22, 0.14)
const C_VERGE := Color(0.36, 0.39, 0.21)
const C_SAND := Color(0.62, 0.55, 0.38)
const C_MUDFLAT := Color(0.33, 0.33, 0.27)
const C_WATER := Color(0.22, 0.36, 0.44)
const C_HULL := Color(0.3, 0.25, 0.19)
const C_LABEL := Color(0.92, 0.84, 0.62)

var _mats: Dictionary = {}
var _gen: Node3D = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	call_deferred("build")


func build() -> void:
	var old := get_node_or_null(GEN_NAME)
	if old:
		remove_child(old)
		old.free()
	_gen = Node3D.new()
	_gen.name = GEN_NAME
	add_child(_gen)  # no owner on purpose → never saved into the scene file
	_rng.seed = 1169
	var c := _anchor(rath_path, Vector3(92, 0, 4))
	_build_rath(c)
	_build_house(c + HOUSE_OFF)
	_build_byre(c + BYRE_OFF)
	_build_pen(c + PEN_OFF)
	_build_lane(c)
	_build_strand()
	_build_wood(_anchor(wood_path, Vector3(61, 0, -2)))
	_build_fen(_anchor(fen_path, Vector3(46, 0, -22)))


func _anchor(p: NodePath, fallback: Vector3) -> Vector3:
	var n := get_node_or_null(p) as Node3D
	return to_local(n.global_position) if n and n.is_inside_tree() else (n.position if n else fallback)


func _start() -> Vector3:
	return _anchor(start_path, Vector3(67.5, 0, -4))


# ---------------------------------------------------------------- the burned ráth

func _gap_angle() -> float:
	return atan2(GAP_DIR.y, GAP_DIR.x)


func _in_gap(a: float, extra_deg: float = 0.0) -> bool:
	return absf(angle_difference(a, _gap_angle())) < deg_to_rad(GAP_HALF_DEG + extra_deg)


func _build_rath(c: Vector3) -> void:
	var root := _group("BurnedRathBank")
	var seg := TAU * RATH_R / BANK_SEGS * 1.06
	for i in BANK_SEGS:
		var a := (i + 0.5) * TAU / BANK_SEGS
		if _in_gap(a):
			continue
		var dir := Vector3(cos(a), 0, sin(a))
		var yaw := atan2(-dir.x, -dir.z)  # local Z along the radius, X along the ring
		var col := C_TURF if _rng.randf() > 0.25 else C_TURF_SCORCH
		# Crest core (collides) and the two lower shoulders that read as the slope.
		_box(root, c + dir * RATH_R + Vector3(0, BANK_H * 0.5, 0), Vector3(seg, BANK_H, 1.6), col, yaw, true)
		_box(root, c + dir * (RATH_R - 1.45) + Vector3(0, BANK_H * 0.28, 0), Vector3(seg * 0.95, BANK_H * 0.56, 1.4), col, yaw, true)
		_box(root, c + dir * (RATH_R + 1.45) + Vector3(0, BANK_H * 0.28, 0), Vector3(seg * 1.08, BANK_H * 0.56, 1.4), col, yaw, true)
		# Outer ditch (wet, dark; no hole in the greybox floor).
		if not _in_gap(a, 2.0):
			_box(root, c + dir * (RATH_R + DITCH_OFF) + Vector3(0, 0.012, 0), Vector3(TAU * (RATH_R + DITCH_OFF) / BANK_SEGS * 1.06, 0.02, DITCH_HALF * 2.0), C_DITCH, yaw)
	# Yard: trodden earth, poached by the driven cattle towards the gap.
	var yard := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RATH_R - 2.2
	cm.bottom_radius = RATH_R - 2.2
	cm.height = 0.02
	cm.radial_segments = 32
	yard.mesh = cm
	yard.material_override = _mat(C_YARD)
	yard.position = c + Vector3(0, 0.008, 0)
	root.add_child(yard)
	var g := Vector3(GAP_DIR.x, 0, GAP_DIR.y)
	for i in 9:
		var p := c + PEN_OFF.lerp(g * (RATH_R + 4.0), float(i) / 8.0) + Vector3(_rng.randf_range(-1.2, 1.2), 0.016, _rng.randf_range(-1.2, 1.2))
		_box(root, p, Vector3(_rng.randf_range(1.0, 2.2), 0.02, _rng.randf_range(0.8, 1.8)), C_POACHED, _rng.randf() * PI)
	# The gate in the gap burned: two charred stumps, the hurdle gate flat and black in the causeway.
	var side := Vector3(-g.z, 0, g.x)
	var gp := c + g * RATH_R
	_post(root, gp + side * 3.0, 0.16, 1.1, C_CHAR, true)
	_post(root, gp - side * 3.0, 0.16, 0.7, C_CHAR, true)
	_box(root, gp + side * 0.6 + g * 1.2 + Vector3(0, 0.05, 0), Vector3(2.6, 0.08, 1.1), C_CHAR_WOOD, atan2(-g.x, -g.z) + 0.3)
	_label(c + Vector3(0, 6.2, 0), "Home ráth — burned in the raid\n(gap to the south)", 40, C_LABEL, "BurnedRathLabel")


func _build_house(h: Vector3) -> void:
	## Wattle-and-daub roundhouse, 7 m across, door south. Thatch and wattle burned out; the daub
	## survives in low fired stubs; the posts stand as black stumps; roof timbers lie inside.
	var root := _group("RuinedHouse")
	var n := 22
	for i in n:
		var a := (i + 0.5) * TAU / n
		var dir := Vector3(cos(a), 0, sin(a))
		if absf(angle_difference(a, PI * 0.5)) < deg_to_rad(12.0):
			continue  # door (south, +Z)
		var hgt := _rng.randf_range(0.2, 0.85)
		var col := C_DAUB_FIRED if _rng.randf() < 0.45 else C_CHAR
		_box(root, h + dir * HOUSE_R + Vector3(0, hgt * 0.5, 0), Vector3(TAU * HOUSE_R / n * 1.05, hgt, 0.2), col, atan2(-dir.x, -dir.z), hgt > 0.5)
		if i % 3 == 0:  # wall posts stand a little higher than the wattle between them
			_post(root, h + dir * HOUSE_R, 0.09, _rng.randf_range(0.6, 1.4), C_CHAR, true)
	# Door posts (south).
	var door := h + Vector3(0, 0, HOUSE_R)
	_post(root, door + Vector3(-0.65, 0, 0), 0.11, 1.7, C_CHAR, true)
	_post(root, door + Vector3(0.65, 0, 0), 0.11, 1.25, C_CHAR, true)
	# Inner ring of roof posts, burned to stumps.
	for k in 4:
		var a2 := k * TAU / 4.0 + 0.4
		_post(root, h + Vector3(cos(a2), 0, sin(a2)) * 1.9, 0.12, _rng.randf_range(0.5, 1.6), C_CHAR, true)
	# Ash floor, a heap where the roof came down, the hearth stones, embers still alive.
	_disc(root, h + Vector3(0, 0.012, 0), HOUSE_R - 0.15, C_ASH_DARK)
	for k in 5:
		var p := h + Vector3(_rng.randf_range(-2.0, 2.0), 0.04, _rng.randf_range(-2.0, 1.8))
		_box(root, p, Vector3(_rng.randf_range(0.7, 1.4), 0.08, _rng.randf_range(0.6, 1.2)), C_ASH, _rng.randf() * PI)
	for k in 8:
		var a3 := k * TAU / 8.0
		_box(root, h + Vector3(cos(a3) * 0.55, 0.08, sin(a3) * 0.55), Vector3(0.24, 0.16, 0.2), C_STONE, a3)
	# Fallen rafters: from the wall-plate down into the floor, criss-crossed.
	for k in 7:
		var a4 := _rng.randf() * TAU
		var top := h + Vector3(cos(a4), 0, sin(a4)) * (HOUSE_R - 0.2) + Vector3(0, _rng.randf_range(0.25, 0.7), 0)
		var bot := h + Vector3(_rng.randf_range(-1.0, 1.0), 0.06, _rng.randf_range(-1.0, 1.0))
		_beam(root, top, bot, 0.13, C_CHAR_WOOD)
	for k in 6:
		_ember(root, h + Vector3(_rng.randf_range(-1.6, 1.6), 0.06, _rng.randf_range(-1.6, 1.4)))


func _build_byre(b: Vector3) -> void:
	## Post-and-wattle byre, long axis east–west, door south: the posts stand charred, the wattle
	## is gone to stubs, the ridge beam is down across the dung floor.
	var root := _group("RuinedByre")
	var hx := BYRE_SIZE.x * 0.5
	var hz := BYRE_SIZE.y * 0.5
	_box(root, b + Vector3(0, 0.012, 0), Vector3(BYRE_SIZE.x - 0.2, 0.02, BYRE_SIZE.y - 0.2), C_ASH_DARK)
	var posts: Array[Vector3] = [Vector3(-hx, 0, -hz), Vector3(0, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(-hx, 0, 0), Vector3(hx, 0, 0), Vector3(-1.1, 0, hz), Vector3(1.1, 0, hz)]
	for p in posts:
		_post(root, b + p, 0.12, _rng.randf_range(0.8, 2.1), C_CHAR, true)
	# Wall stubs (north, east, west, and the south either side of the door).
	var walls := [[Vector3(0, 0, -hz), BYRE_SIZE.x, 0.0], [Vector3(-hx, 0, 0), BYRE_SIZE.y, PI * 0.5], [Vector3(hx, 0, 0), BYRE_SIZE.y, PI * 0.5], [Vector3(-2.2, 0, hz), 2.2, 0.0], [Vector3(2.2, 0, hz), 2.2, 0.0]]
	for w in walls:
		var hgt := _rng.randf_range(0.2, 0.6)
		_box(root, b + (w[0] as Vector3) + Vector3(0, hgt * 0.5, 0), Vector3(float(w[1]) * 0.95, hgt, 0.16), C_CHAR if _rng.randf() < 0.6 else C_WATTLE.darkened(0.45), float(w[2]), hgt > 0.5)
	_beam(root, b + Vector3(-hx + 0.2, 1.5, 0), b + Vector3(hx - 0.8, 0.07, 0.4), 0.16, C_CHAR_WOOD)
	_beam(root, b + Vector3(-hx, 0.9, -hz), b + Vector3(-0.6, 0.06, 0.6), 0.12, C_CHAR_WOOD)
	for k in 3:
		_ember(root, b + Vector3(_rng.randf_range(-2.4, 2.4), 0.05, _rng.randf_range(-1.4, 1.4)))


func _build_pen(p: Vector3) -> void:
	## Hurdle pen by the byre: empty, the gate side thrown down where they drove the cattle out,
	## two hurdles scorched.
	var root := _group("BrokenPen")
	var hx := PEN_SIZE.x * 0.5
	var hz := PEN_SIZE.y * 0.5
	var spans: Array = []
	for i in 4:
		spans.append([Vector3(-hx + 1.0 + i * 2.0, 0, -hz), 0.0])  # north
	for i in 3:
		spans.append([Vector3(-hx, 0, -hz + 1.0 + i * 2.0), PI * 0.5])  # west
		spans.append([Vector3(hx, 0, -hz + 1.0 + i * 2.0), PI * 0.5])  # east
	for i in 4:
		spans.append([Vector3(-hx + 1.0 + i * 2.0, 0, hz), 0.0])  # south: the gate side
	for s in spans:
		var q: Vector3 = p + (s[0] as Vector3)
		var yaw: float = s[1]
		var down := (s[0] as Vector3).z > 0.0 and _rng.randf() < 0.75
		if down:
			_box(root, q + Vector3(0, 0.05, 0.7), Vector3(1.9, 0.07, 1.0), C_WATTLE.darkened(0.2), yaw + _rng.randf_range(-0.4, 0.4))
		else:
			var col := C_CHAR_WOOD if _rng.randf() < 0.25 else C_WATTLE
			_box(root, q + Vector3(0, 0.5, 0), Vector3(1.9, 1.0, 0.08), col, yaw + _rng.randf_range(-0.06, 0.06), true)
			_post(root, q + Vector3(cos(yaw), 0, -sin(yaw)) * 0.95, 0.05, 1.15, C_TRUNK, false)


# ---------------------------------------------------------------- lane and strand

func _build_lane(c: Vector3) -> void:
	var root := _group("BannowLaneTrack")
	var g := Vector3(GAP_DIR.x, 0, GAP_DIR.y)
	var pts: Array[Vector3] = [c + g * (RATH_R - 1.0), c + g * (RATH_R + 6.5)]
	var extra: Array[Vector3] = LANE_PTS
	for q in extra:
		pts.append(q)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		var yaw := atan2(-d.x, -d.z)
		var mid := (a + b) * 0.5
		_box(root, mid + Vector3(0, 0.02, 0), Vector3(4.2, 0.02, d.length() + 1.6), C_VERGE, yaw)
		_box(root, mid + Vector3(0, 0.03, 0), Vector3(2.8, 0.02, d.length() + 1.2), C_LANE, yaw)
		# Cattle driven down it at dawn: poached mud and dung along the way.
		for k in int(d.length() / 3.0):
			var t := (k + 0.5) / maxf(1.0, d.length() / 3.0)
			var q2 := a.lerp(b, t) + Vector3(_rng.randf_range(-0.8, 0.8), 0.042, _rng.randf_range(-0.8, 0.8))
			_box(root, q2, Vector3(_rng.randf_range(0.4, 0.9), 0.012, _rng.randf_range(0.3, 0.7)), C_POACHED, _rng.randf() * PI)
	# Waymark where the lane leaves the ráth, and one further down where the strand opens out.
	var w0 := pts[2] + Vector3(2.4, 0, -0.8)
	_post(root, w0, 0.12, 1.6, C_TRUNK, true)
	_label(w0 + Vector3(0, 2.5, 0), "Lane to the strand ↙\nBannow — where they landed", 32, C_LABEL, "BannowLaneSign")
	var w1 := pts[pts.size() - 3] + Vector3(0, 0, -2.4)
	_post(root, w1, 0.12, 1.4, C_TRUNK, true)
	_label(w1 + Vector3(0, 2.3, 0), "← Bannow strand", 30, C_LABEL, "BannowLaneSign2")


func _build_strand() -> void:
	## Bannow Bay is a tidal estuary: sand along the top of the shore, then mudflat and shallows.
	## The strand runs east from the old beachhead box to below the ráth, so the lane meets it.
	var root := _group("BannowStrand")
	_box(root, Vector3(64.0, 0.015, 47.0), Vector3(92.0, 0.02, 6.0), C_SAND)
	_box(root, Vector3(32.5, 0.02, 53.0), Vector3(185.0, 0.02, 6.0), C_MUDFLAT)
	_box(root, Vector3(32.5, 0.03, 58.0), Vector3(185.0, 0.02, 4.2), C_WATER)
	# The ships of the landing, drawn up on the strand and riding off it: tall masts read from the lane.
	var ships := [[Vector3(-6.0, 0, 50.5), 0.25, true], [Vector3(4.5, 0, 52.5), -0.1, true], [Vector3(15.0, 0, 57.0), 0.15, false]]
	var i := 0
	for s in ships:
		var p: Vector3 = s[0]
		var yaw: float = s[1]
		var beached: bool = s[2]
		var tilt := 0.12 if beached else 0.0
		var hull := _box(root, p + Vector3(0, 0.55, 0), Vector3(3.4, 1.1, 14.0), C_HULL, yaw, beached)
		hull.rotation.z = tilt
		hull.name = "NormanShip%d" % i
		_box(root, p + Vector3(0, 1.0, -6.6).rotated(Vector3.UP, yaw), Vector3(0.5, 1.8, 1.0), C_HULL, yaw)
		_box(root, p + Vector3(0, 1.0, 6.6).rotated(Vector3.UP, yaw), Vector3(0.5, 1.8, 1.0), C_HULL, yaw)
		_post(root, p + Vector3(0, 0.6, 0), 0.14, 9.5, C_TRUNK, false)
		_box(root, p + Vector3(0, 8.6, 0), Vector3(6.0, 0.18, 0.18), C_TRUNK, yaw + PI * 0.5)
		i += 1


# ---------------------------------------------------------------- wood and fen

func _build_wood(w: Vector3) -> void:
	## Oak and ash with hazel at the edge, a belt west of the ráth between it and the fen. The way
	## out of the fen comes through it (tóchar end → ExileStart) and is kept clear.
	var root := _group("WoodEdgeTrees")
	var start := _start()
	var fen := _anchor(fen_path, Vector3(46, 0, -22))
	var track_end := fen + Vector3(9.5, 0, 9.5)
	var placed := 0
	var tries := 0
	while placed < 52 and tries < 600:
		tries += 1
		var p := w + Vector3(_rng.randf_range(-6.0, 6.0), 0, _rng.randf_range(-24.0, 22.0))
		if _dist_seg(p, track_end, start) < 2.4 or Vector2(p.x - start.x, p.z - start.z).length() < 3.5:
			continue
		if p.x < fen.x + 11.5 and p.z < fen.z + 13.5:
			continue  # that is the fen (its own carr is built with it)
		var ash := _rng.randf() < 0.3
		var r := _rng.randf_range(0.18, 0.42)
		var hgt := _rng.randf_range(4.5, 8.0)
		_post(root, p, r, hgt, C_TRUNK_ASH if ash else C_TRUNK, true)
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = _rng.randf_range(1.8, 3.0)
		sm.height = sm.radius * 1.4
		sm.radial_segments = 10
		sm.rings = 6
		crown.mesh = sm
		crown.material_override = _mat(C_CANOPY[_rng.randi() % C_CANOPY.size()])
		crown.position = p + Vector3(0, hgt + sm.height * 0.25, 0)
		root.add_child(crown)
		placed += 1
	# Hazel scrub along the east face of the wood (the edge you come out of).
	for k in 18:
		var p2 := w + Vector3(_rng.randf_range(4.5, 7.0), 0, _rng.randf_range(-24.0, 22.0))
		if Vector2(p2.x - start.x, p2.z - start.z).length() < 2.6:
			continue
		var bush := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = _rng.randf_range(0.7, 1.2)
		bm.height = bm.radius * 1.5
		bm.radial_segments = 8
		bm.rings = 5
		bush.mesh = bm
		bush.material_override = _mat(C_HAZEL)
		bush.position = p2 + Vector3(0, bm.height * 0.45, 0)
		root.add_child(bush)
	_label(w + Vector3(4.0, 6.5, -14.0), "Wood edge", 30, C_LABEL, "WoodEdgeLabel")


func _build_fen(f: Vector3) -> void:
	## Sedge fen with pools and reed beds, alder and willow carr at its rim, and the tóchar: an oak
	## plank trackway on runners, laid across the soft ground towards the wood.
	var root := _group("TocharFenGround")
	_box(root, f + Vector3(0, 0.01, 0), Vector3(22.0, 0.02, 26.0), C_SEDGE)
	for k in 7:
		var p := f + Vector3(_rng.randf_range(-9.0, 9.0), 0.015, _rng.randf_range(-11.0, 11.0))
		_box(root, p, Vector3(_rng.randf_range(2.0, 4.5), 0.02, _rng.randf_range(1.6, 3.5)), C_PEAT, _rng.randf() * PI)
	var a := f + Vector3(-6.5, 0, -12.5)   # the far (north-west) end, off towards the higher ground
	var b := f + Vector3(9.5, 0, 9.5)      # the wood end
	for k in 9:
		var p := f + Vector3(_rng.randf_range(-9.5, 9.5), 0.02, _rng.randf_range(-11.5, 11.5))
		if _dist_seg(p, a, b) < 2.5:
			continue
		_box(root, p, Vector3(_rng.randf_range(1.5, 3.8), 0.02, _rng.randf_range(1.2, 3.0)), C_POOL, _rng.randf() * PI)
	for k in 46:
		var p := f + Vector3(_rng.randf_range(-10.5, 10.5), 0, _rng.randf_range(-12.5, 12.5))
		if _dist_seg(p, a, b) < 1.4:
			continue
		var col: Color = C_REED[_rng.randi() % C_REED.size()]
		for s in 6:
			var hgt := _rng.randf_range(1.1, 2.0)
			var q := p + Vector3(_rng.randf_range(-0.35, 0.35), hgt * 0.5, _rng.randf_range(-0.35, 0.35))
			var stem := _box(root, q, Vector3(0.05, hgt, 0.05), col, _rng.randf() * PI)
			stem.rotation.x = _rng.randf_range(-0.12, 0.12)
	for k in 10:  # alder / willow carr at the rim
		var ang := _rng.randf() * TAU
		var p := f + Vector3(cos(ang) * 12.0, 0, sin(ang) * 13.5)
		if _dist_seg(p, a, b) < 3.0:
			continue
		_post(root, p, 0.14, 2.6, C_TRUNK, true)
		var bush := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5
		sm.height = 2.2
		sm.radial_segments = 8
		sm.rings = 5
		bush.mesh = sm
		bush.material_override = _mat(C_ALDER)
		bush.position = p + Vector3(0, 2.6, 0)
		root.add_child(bush)
	var track := _group("Tochar")
	var d := b - a
	var yaw := atan2(-d.x, -d.z)
	var side := Vector3(-d.z, 0, d.x).normalized()
	var n := int(d.length() / 0.42)
	for s in [-0.55, 0.55]:
		_box(track, (a + b) * 0.5 + side * s + Vector3(0, 0.05, 0), Vector3(0.12, 0.1, d.length()), C_OAK_PLANK.darkened(0.2), yaw)
	for k in n:
		var t := (k + 0.5) / float(n)
		var p := a.lerp(b, t) + Vector3(0, 0.12 - (0.05 if _rng.randf() < 0.15 else 0.0), 0)
		var plank := _box(track, p, Vector3(1.6, 0.07, 0.3), C_OAK_PLANK, yaw + _rng.randf_range(-0.06, 0.06), false)
		plank.rotation.z = _rng.randf_range(-0.04, 0.04)
	_label(f + Vector3(0, 4.0, 0), "Tóchar — the fen causeway", 34, C_LABEL, "TocharFenLabel")


# ---------------------------------------------------------------- helpers

func _group(nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	_gen.add_child(n)
	return n


func _mat(color: Color, emit: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + ("e" if emit else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if emit:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.6
	_mats[key] = m
	return m


func _box(parent: Node, pos: Vector3, size: Vector3, color: Color, yaw: float = 0.0, collide: bool = false) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	if not collide:
		mi.position = pos
		mi.rotation.y = yaw
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(mi)
	body.add_child(cs)
	parent.add_child(body)
	return body


func _post(parent: Node, base: Vector3, r: float, h: float, color: Color, collide: bool) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.85
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _mat(color)
	var pos := base + Vector3(0, h * 0.5, 0)
	if not collide:
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(mi)
	body.add_child(cs)
	parent.add_child(body)
	return body


func _beam(parent: Node, a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = _mat(color)
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)


func _disc(parent: Node, pos: Vector3, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	cm.radial_segments = 24
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)


func _ember(parent: Node, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_rng.randf_range(0.12, 0.3), 0.06, _rng.randf_range(0.1, 0.24))
	mi.mesh = bm
	mi.material_override = _mat(C_EMBER, true)
	mi.position = pos
	mi.rotation.y = _rng.randf() * PI
	mi.add_to_group("exile_embers")
	parent.add_child(mi)


func _label(pos: Vector3, text: String, size: int, color: Color, nm: String) -> Label3D:
	var l := Label3D.new()
	l.name = nm
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.05, 0.04, 0.85)
	l.position = pos
	_gen.add_child(l)
	return l


func _dist_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()
