@tool
extends Node3D
## Greybox geometry for the first-morning cattle drive (house · byre · home pen · twisting
## lane · secluded pasture behind gradual rolling hills (lane winds through saddles) · bog edge · west ditch · neighbours' ringfort).
##
## Builds plain boxes/prisms/cylinders at _ready into an un-owned child, so the layout shows in
## the editor (tool script) but nothing generated is serialized into the .tscn. Gameplay nodes
## (path markers, zones, cows, player) stay authored in opening_cattle_drive.tscn and this
## builder reads them, so moving a marker / zone in the editor moves its greybox too.

@export var path_markers_path: NodePath = ^"../PathMarkers"
@export var home_zone_path: NodePath = ^"../HomeZone"
@export var bog_zone_path: NodePath = ^"../BogZone"
@export var pasture_zone_path: NodePath = ^"../PastureZone"
@export var rebuild: bool = false:
	set(v):
		rebuild = false
		if is_inside_tree():
			build()

const GEN_NAME := "_Generated"
const RAIL_HEIGHT := 1.05
const LANE_WIDTH := 3.2

const C_GRASS := Color(0.36, 0.47, 0.27)
const C_PASTURE := Color(0.42, 0.55, 0.3)
const C_YARD := Color(0.42, 0.36, 0.26)
const C_LANE := Color(0.52, 0.45, 0.32)
const C_WALL := Color(0.78, 0.74, 0.64)
const C_THATCH := Color(0.62, 0.5, 0.3)
const C_DOOR := Color(0.2, 0.16, 0.12)
const C_BYRE := Color(0.55, 0.47, 0.36)
const C_RAIL := Color(0.45, 0.35, 0.22)
const C_STAKE_TOP := Color(0.92, 0.9, 0.8)
const C_BOG := Color(0.2, 0.25, 0.15)
const C_BOG_WATER := Color(0.16, 0.2, 0.2)
const C_REED := Color(0.5, 0.52, 0.28)
const C_DITCH := Color(0.17, 0.2, 0.14)
const C_BANK := Color(0.3, 0.38, 0.22)
const C_HEDGE := Color(0.2, 0.33, 0.17)
const C_TRUNK := Color(0.32, 0.25, 0.18)
const C_CANOPY := Color(0.24, 0.38, 0.2)
const C_RATH_BANK := Color(0.33, 0.42, 0.25)
const C_HUT := Color(0.68, 0.62, 0.5)

var _mats: Dictionary = {}
var _gen: Node3D = null
var _hill_defs: Array = []  # {c,r,scl} for clip/LOS helpers


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
	_hill_defs.clear()
	var path := _path_points()
	_build_ground()
	_build_farmstead()
	_build_home_pen()
	_build_secluding_hills()  # before bog/trees/lane so clip filters see knolls
	_build_lane(path)
	_build_pasture()
	_build_bog()
	_build_edges()
	_build_ringfort(Vector3(-78.0, 0.0, 42.0), 16.0)
	_build_trees(path)
	_build_labels(path)


# ---------------------------------------------------------------- layout readers

func _path_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var markers := get_node_or_null(path_markers_path)
	if markers:
		for c in markers.get_children():
			if c is Node3D:
				pts.append(to_local((c as Node3D).global_position))
	return pts


func _zone_box(path: NodePath, fallback_center: Vector3, fallback_size: Vector3) -> AABB:
	var zone := get_node_or_null(path) as Node3D
	if zone:
		for c in zone.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
				var center := to_local((c as Node3D).global_position)
				return AABB(center - size * 0.5, size)
	return AABB(fallback_center - fallback_size * 0.5, fallback_size)


# ---------------------------------------------------------------- sections

func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	_gen.add_child(ground)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(420.0, 1.0, 460.0)
	shape.shape = bs
	shape.position = Vector3(-10.0, -0.5, 80.0)
	ground.add_child(shape)
	_mesh_box(ground, Vector3(-10.0, -0.05, 80.0), Vector3(420.0, 0.1, 460.0), C_GRASS)
	# Low, rolling south-Leinster farmland: broad flattened swells far off (no mountain).
	for swell in [Vector3(80, 0, 10), Vector3(-60, 0, 130), Vector3(90, 0, 150), Vector3(-120, 0, -30), Vector3(70, 0, 210)]:
		var s := _mesh_sphere(_gen, swell + Vector3(0, -6.0, 0), 34.0, C_GRASS.darkened(0.04))
		s.scale = Vector3(1.6, 0.28, 1.2)


func _build_farmstead() -> void:
	# Muddy yard.
	_mesh_box(_gen, Vector3(0.0, 0.01, 3.0), Vector3(34.0, 0.04, 24.0), C_YARD)
	# House (family) — whitewashed walls, thatch, door to the south yard.
	var house := Vector3(-8.0, 0.0, -1.0)
	_solid_box(_gen, house + Vector3(0, 1.2, 0), Vector3(7.5, 2.4, 5.5), C_WALL)
	_roof(_gen, house + Vector3(0, 2.4, 0), Vector3(8.2, 2.1, 6.2), C_THATCH)
	_mesh_box(_gen, house + Vector3(0.8, 0.95, 2.77), Vector3(1.1, 1.9, 0.08), C_DOOR)
	_mesh_box(_gen, house + Vector3(-2.2, 1.5, 2.77), Vector3(0.7, 0.6, 0.08), C_DOOR)
	_mesh_box(_gen, house + Vector3(2.6, 3.6, 0.0), Vector3(0.6, 1.1, 0.6), C_WALL.darkened(0.25))  # smoke-hole chimney stub
	# Byre — long, low, door opening onto the home pen.
	var byre := Vector3(7.0, 0.0, -2.6)
	_solid_box(_gen, byre + Vector3(0, 1.1, 0), Vector3(12.0, 2.2, 5.0), C_BYRE)
	_roof(_gen, byre + Vector3(0, 2.2, 0), Vector3(12.6, 1.6, 5.6), C_THATCH.darkened(0.08))
	_mesh_box(_gen, byre + Vector3(0, 0.9, 2.52), Vector3(2.4, 1.8, 0.08), C_DOOR)
	# Hay rick + woodpile + quern stone dressing.
	_mesh_cyl(_gen, Vector3(-14.0, 1.0, 5.0), 1.4, 1.4, 2.0, C_THATCH)
	_mesh_cyl(_gen, Vector3(-14.0, 2.6, 5.0), 0.05, 1.5, 1.2, C_THATCH.darkened(0.05))
	_solid_box(_gen, Vector3(-12.5, 0.45, -4.6), Vector3(2.6, 0.9, 1.0), C_TRUNK)
	_mesh_cyl(_gen, Vector3(-5.0, 0.2, 3.6), 0.45, 0.45, 0.4, C_WALL.darkened(0.35))


func _build_home_pen() -> void:
	var box := _zone_box(home_zone_path, Vector3(7.0, 1.2, 6.5), Vector3(12.6, 2.4, 10.6))
	var x0 := box.position.x - 0.4
	var x1 := box.end.x + 0.4
	var z0 := box.position.z - 0.4
	var z1 := box.end.z + 0.4
	var cx := box.get_center().x
	var gate_half := 2.3
	_rail(Vector3(x0, 0, z0), Vector3(x1, 0, z0))
	_rail(Vector3(x0, 0, z0), Vector3(x0, 0, z1))
	_rail(Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	_rail(Vector3(x0, 0, z1), Vector3(cx - gate_half, 0, z1))
	_rail(Vector3(cx + gate_half, 0, z1), Vector3(x1, 0, z1))
	# Gate posts (open gate swung back).
	for gx in [cx - gate_half, cx + gate_half]:
		_mesh_box(_gen, Vector3(gx, 0.75, z1), Vector3(0.3, 1.5, 0.3), C_RAIL.darkened(0.2))
	_mesh_box(_gen, Vector3(cx + gate_half + 0.2, 0.55, z1 + 1.6), Vector3(0.12, 0.9, 3.2), C_RAIL)
	# Trampled pen floor.
	_mesh_box(_gen, Vector3(box.get_center().x, 0.03, box.get_center().z), Vector3(box.size.x, 0.04, box.size.z), C_YARD.darkened(0.12))


func _build_lane(path: Array[Vector3]) -> void:
	if path.size() < 2:
		return
	# Lane strips + soft joints.
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b) + 1.2
		var strip := _mesh_box(_gen, Vector3(mid.x, 0.035, mid.z), Vector3(LANE_WIDTH, 0.05, length), C_LANE)
		strip.rotation.y = atan2(b.x - a.x, b.z - a.z)
		_mesh_cyl(_gen, Vector3(a.x, 0.036, a.z), LANE_WIDTH * 0.5, LANE_WIDTH * 0.5, 0.05, C_LANE)
	_mesh_cyl(_gen, Vector3(path[-1].x, 0.036, path[-1].z), LANE_WIDTH * 0.5, LANE_WIDTH * 0.5, 0.05, C_LANE)
	# Bias stakes (white-topped) at every marker — the drove's waypoints.
	for p in path:
		_mesh_box(_gen, Vector3(p.x + LANE_WIDTH * 0.62, 0.55, p.z), Vector3(0.18, 1.1, 0.18), C_RAIL)
		_mesh_box(_gen, Vector3(p.x + LANE_WIDTH * 0.62, 1.15, p.z), Vector3(0.24, 0.16, 0.24), C_STAKE_TOP)
	# Boreen out of the pen: fenced first leg so the herd funnels into the gate.
	var g := path[0]
	var b1 := path[1]
	# West side starts a little south of the gate so the player can step in from the yard.
	_rail(Vector3(g.x - 3.4, 0, g.z + 1.0), Vector3(b1.x - 3.4, 0, b1.z - 3.0))
	_rail(Vector3(g.x + 3.4, 0, g.z - 2.4), Vector3(b1.x + 3.4, 0, b1.z - 3.0))
	# Outer-bend wattle rails: on each interior bend, fence the side the herd overshoots
	# when walking home (home-ward = toward lower marker index).
	for i in range(1, path.size() - 1):
		var p := path[i]
		var d_in := (p - path[i + 1])
		d_in.y = 0.0
		d_in = d_in.normalized()
		var d_out := (path[i - 1] - p)
		d_out.y = 0.0
		d_out = d_out.normalized()
		var outer := d_in - d_out
		if outer.length() < 0.15:
			continue
		outer = outer.normalized()
		var along := Vector3(-outer.z, 0.0, outer.x)
		var c := p + outer * (LANE_WIDTH * 0.5 + 1.8)
		if _on_hill(c, 0.5) or _on_hill(c - along * 5.0, 0.5) or _on_hill(c + along * 5.0, 0.5):
			continue  # keep wattle off knoll volumes
		_rail(c - along * 7.0, c + along * 7.0)


func _build_pasture() -> void:
	var box := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	var c := box.get_center()
	_mesh_box(_gen, Vector3(c.x, 0.02, c.z), Vector3(box.size.x, 0.03, box.size.z), C_PASTURE)
	var x0 := box.position.x
	var x1 := box.end.x
	var z0 := box.position.z
	var z1 := box.end.z
	# North rail with a mouth where the lane enters; west rail. East/south are hedge banks.
	var path := _path_points()
	var mouth_x := path[-1].x if path.size() > 0 else c.x
	_rail(Vector3(x0, 0, z0), Vector3(mouth_x - 4.0, 0, z0))
	_rail(Vector3(mouth_x + 4.0, 0, z0), Vector3(x1, 0, z0))
	_rail(Vector3(x0, 0, z0), Vector3(x0, 0, z1))
	_rail(Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	_rail(Vector3(x0, 0, z1), Vector3(x1, 0, z1))
	# Water trough + rubbing stone.
	_solid_box(_gen, Vector3(x1 - 4.0, 0.35, c.z + 4.0), Vector3(2.6, 0.7, 0.9), C_TRUNK)
	_solid_box(_gen, Vector3(x0 + 6.0, 0.6, z1 - 5.0), Vector3(0.9, 1.2, 0.9), C_WALL.darkened(0.4))


func _build_bog() -> void:
	var box := _zone_box(bog_zone_path, Vector3(34.0, 1.0, 118.0), Vector3(20.0, 2.0, 20.0))
	var c := box.get_center()
	_mesh_box(_gen, Vector3(c.x, 0.03, c.z), Vector3(box.size.x, 0.05, box.size.z), C_BOG)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for i in 7:
		var px := rng.randf_range(box.position.x + 2.0, box.end.x - 2.0)
		var pz := rng.randf_range(box.position.z + 2.0, box.end.z - 2.0)
		if _on_hill(Vector3(px, 0.0, pz), 0.35):
			continue
		var pool := _mesh_cyl(_gen, Vector3(px, 0.06, pz), 1.0, 1.0, 0.03, C_BOG_WATER)
		pool.scale = Vector3(rng.randf_range(1.0, 2.4), 1.0, rng.randf_range(0.8, 1.8))
	for i in 46:
		var px := rng.randf_range(box.position.x, box.end.x)
		var pz := rng.randf_range(box.position.z, box.end.z)
		if _on_hill(Vector3(px, 0.0, pz), 0.35):
			continue
		var h := rng.randf_range(0.6, 1.3)
		_mesh_box(_gen, Vector3(px, h * 0.5, pz), Vector3(0.08, h, 0.08), C_REED)
	# Bog-cotton tufts.
	for i in 18:
		var px := rng.randf_range(box.position.x, box.end.x)
		var pz := rng.randf_range(box.position.z, box.end.z)
		if _on_hill(Vector3(px, 0.0, pz), 0.35):
			continue
		_mesh_sphere(_gen, Vector3(px, 0.35, pz), 0.12, C_STAKE_TOP)
	# Extra visual bog patches on clear ground west of the lane (avoid knoll volumes).
	_build_bog_patch(Vector3(-10.0, 0.0, 100.0), Vector3(14.0, 2.0, 10.0), 5521)
	_build_bog_patch(Vector3(-55.0, 0.0, 160.0), Vector3(18.0, 2.0, 14.0), 7733)


func _build_bog_patch(center: Vector3, size: Vector3, seed_val: int) -> void:
	var half := size * 0.5
	var box := AABB(center - half, size)
	_mesh_box(_gen, Vector3(center.x, 0.03, center.z), Vector3(size.x, 0.05, size.z), C_BOG)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in 5:
		var px := rng.randf_range(box.position.x + 2.0, box.end.x - 2.0)
		var pz := rng.randf_range(box.position.z + 2.0, box.end.z - 2.0)
		if _on_hill(Vector3(px, 0.0, pz), 0.35):
			continue
		var pool := _mesh_cyl(_gen, Vector3(px, 0.06, pz), 1.0, 1.0, 0.03, C_BOG_WATER)
		pool.scale = Vector3(rng.randf_range(1.0, 2.2), 1.0, rng.randf_range(0.8, 1.7))
	for i in 28:
		var px := rng.randf_range(box.position.x, box.end.x)
		var pz := rng.randf_range(box.position.z, box.end.z)
		if _on_hill(Vector3(px, 0.0, pz), 0.35):
			continue
		var h := rng.randf_range(0.55, 1.2)
		_mesh_box(_gen, Vector3(px, h * 0.5, pz), Vector3(0.08, h, 0.08), C_REED)
	for i in 10:
		var px := rng.randf_range(box.position.x, box.end.x)
		var pz := rng.randf_range(box.position.z, box.end.z)
		if _on_hill(Vector3(px, 0.0, pz), 0.35):
			continue
		_mesh_sphere(_gen, Vector3(px, 0.35, pz), 0.12, C_STAKE_TOP)


func _build_secluding_hills() -> void:
	## Broad rolling ground — very gradual rises with long skirts (not distinct hill blobs).
	## Overlapping soft volumes keep Bend4–8 + PastureMouth clear and kill house↔pasture LOS.
	## Crest ≈ r * scl.y * 0.45. Walk collision on each.
	# Near west/east rolls — wide low skirts; saddle ~x 0–12 at z≈70–95 (Bend4→Bend5).
	_hill(Vector3(-50.0, 0.0, 72.0), 32.0, Vector3(1.4, 0.30, 1.6), C_BANK.lightened(0.08))
	_hill(Vector3(46.0, 0.0, 100.0), 30.0, Vector3(1.4, 0.28, 1.45), C_GRASS.darkened(0.06))
	# West-of-lane continuous roll (merged near+mid screens into two overlapping soft rises).
	# Low crest, long skirt; still clears elevated yard cams. Eastern toes west of Bend6 (−2,118).
	_hill(Vector3(-38.0, 0.0, 112.0), 30.0, Vector3(1.4, 0.38, 1.55), C_HEDGE)
	_hill(Vector3(-50.0, 0.0, 118.0), 28.0, Vector3(1.3, 0.32, 1.5), C_BANK)
	# Mid west/east rolls — saddle ~x 4–12 at z≈118–145 (Bend6→Bend7).
	_hill(Vector3(-48.0, 0.0, 144.0), 30.0, Vector3(1.4, 0.32, 1.55), C_GRASS.darkened(0.05))
	_hill(Vector3(46.0, 0.0, 134.0), 30.0, Vector3(1.35, 0.28, 1.4), C_BANK.lightened(0.05))
	# Mid west continuation — blends with near roll into one long N–S swell.
	_hill(Vector3(-38.0, 0.0, 136.0), 28.0, Vector3(1.4, 0.38, 1.5), C_HEDGE.lightened(0.04))
	# Far west roll (west of Bend8) — soft approach into the hollow.
	_hill(Vector3(-48.0, 0.0, 156.0), 24.0, Vector3(1.4, 0.34, 1.4), C_HEDGE)
	_hill(Vector3(-58.0, 0.0, 148.0), 22.0, Vector3(1.25, 0.30, 1.3), C_BANK)
	# Pasture flanks — broad soft rises tucking the hollow.
	_hill(Vector3(28.0, 0.0, 186.0), 28.0, Vector3(1.35, 0.30, 1.4), C_BANK)
	_hill(Vector3(-62.0, 0.0, 192.0), 28.0, Vector3(1.3, 0.28, 1.35), C_GRASS.darkened(0.04))
	# Pasture mouth lips — wide low berms with a walkable gap at PastureMouth.
	var mouth_x := -28.0
	var path_pts := _path_points()
	if path_pts.size() > 0:
		mouth_x = path_pts[-1].x
	var gap := 6.5
	var west_end := mouth_x - gap
	var east_start := mouth_x + gap
	_hill(Vector3(-50.0, 0.0, 176.5), 14.0, Vector3(1.45, 0.38, 0.9), C_BANK)
	_hill(Vector3(west_end - 9.0, 0.0, 177.0), 12.0, Vector3(1.3, 0.36, 0.85), C_BANK.lightened(0.05))
	_hill(Vector3(east_start + 10.0, 0.0, 176.5), 13.0, Vector3(1.35, 0.38, 0.9), C_BANK)
	_hill(Vector3(-4.0, 0.0, 177.5), 13.0, Vector3(1.3, 0.34, 0.85), C_HEDGE.lightened(0.08))
	# Pasture side screens — long low N–S banks (soft hedge feel).
	_hill(Vector3(-8.0, 0.0, 191.0), 16.0, Vector3(0.5, 0.40, 2.0), C_HEDGE)
	_hill(Vector3(-42.0, 0.0, 191.0), 16.0, Vector3(0.5, 0.40, 2.0), C_HEDGE)


func _hill(center: Vector3, radius: float, scl: Vector3, color: Color) -> void:
	# Sphere sunk below grade then scaled flat — crest height ≈ radius * scl.y * 0.45.
	_hill_defs.append({"c": center, "r": radius, "scl": scl})
	var sink := radius * scl.y * 0.55
	var mesh_pos := center + Vector3(0.0, -sink, 0.0)
	var s := _mesh_sphere(_gen, mesh_pos, radius, color)
	s.scale = scl
	# Walk collision on the mound bulk (cylinder) so players/cattle cannot phase through.
	# Undersized vs the visual skirt so the lane can graze soft toes without snagging.
	var body := StaticBody3D.new()
	body.name = "HillCollide_%d_%d" % [int(center.x), int(center.z)]
	body.collision_layer = 1
	body.collision_mask = 0
	var coll_h := maxf(2.2, radius * scl.y * 0.75)
	var coll_r := radius * minf(scl.x, scl.z) * 0.52
	body.position = center + Vector3(0.0, coll_h * 0.5, 0.0)
	_gen.add_child(body)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = coll_r
	cyl.height = coll_h
	cs.shape = cyl
	body.add_child(cs)


func _build_edges() -> void:
	# West ditch + bank: the farm edge beyond the early lane (cattle cannot climb the bank).
	_mesh_box(_gen, Vector3(-27.0, 0.02, 70.0), Vector3(2.6, 0.05, 140.0), C_DITCH)
	_solid_box(_gen, Vector3(-25.2, 0.35, 70.0), Vector3(0.9, 0.7, 140.0), C_BANK)
	_solid_box(_gen, Vector3(-28.8, 0.45, 70.0), Vector3(1.0, 0.9, 140.0), C_HEDGE)
	# East hedge bank (field boundary) and south hedge behind the secluded pasture.
	_solid_box(_gen, Vector3(42.0, 0.9, 90.0), Vector3(1.6, 1.8, 220.0), C_HEDGE)
	var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	_solid_box(_gen, Vector3(pas.get_center().x, 0.9, pas.end.z + 3.0), Vector3(pas.size.x + 18.0, 1.8, 1.6), C_HEDGE)
	# North hedge behind the farmstead.
	_solid_box(_gen, Vector3(0.0, 0.9, -14.0), Vector3(70.0, 1.8, 1.4), C_HEDGE)
	# Short ditch along the bog's lane side (visual cue: "wet ground starts here").
	var box := _zone_box(bog_zone_path, Vector3(34.0, 1.0, 118.0), Vector3(20.0, 2.0, 20.0))
	_mesh_box(_gen, Vector3(box.position.x - 0.6, 0.025, box.get_center().z), Vector3(1.0, 0.05, box.size.z + 2.0), C_DITCH)


func _build_ringfort(center: Vector3, radius: float) -> void:
	# Neighbours' ráth — earthen ring bank with a gap facing east, a few round houses.
	var segs := 30
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		if dir.x > 0.93:
			continue  # east entrance
		var p := center + dir * radius
		var seg := _mesh_box(_gen, p + Vector3(0, 1.1, 0), Vector3(3.6, 2.2, 1.6), C_RATH_BANK)
		seg.rotation.y = atan2(dir.x, dir.z)
		var palisade := _mesh_box(_gen, center + dir * (radius - 0.5) + Vector3(0, 2.8, 0), Vector3(3.4, 1.4, 0.2), C_RAIL.darkened(0.15))
		palisade.rotation.y = atan2(dir.x, dir.z)
	for hut in [Vector3(-4, 0, -3), Vector3(5, 0, 2), Vector3(-3, 0, 6)]:
		var h: Vector3 = center + hut
		_mesh_cyl(_gen, h + Vector3(0, 1.2, 0), 3.0, 3.0, 2.4, C_HUT)
		_mesh_cyl(_gen, h + Vector3(0, 3.4, 0), 0.1, 3.5, 2.2, C_THATCH)
	_label(center + Vector3(0, 7.0, 0), "Neighbours' ráth (ringfort)", 46, Color(0.82, 0.86, 0.72))


func _build_trees(path: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1169
	var placed := 0
	var tries := 0
	while placed < 58 and tries < 800:
		tries += 1
		var p := Vector3(rng.randf_range(-70.0, 70.0), 0.0, rng.randf_range(-40.0, 220.0))
		if _near_lane(p, path, 7.0):
			continue
		if p.x > -18.0 and p.x < 20.0 and p.z > -10.0 and p.z < 18.0:
			continue  # farmstead
		var bog := _zone_box(bog_zone_path, Vector3(34.0, 1.0, 118.0), Vector3(20.0, 2.0, 20.0)).grow(1.0)
		var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0)).grow(1.0)
		if _in_xz(bog, p) or _in_xz(pas, p):
			continue
		if p.distance_to(Vector3(-78, 0, 42)) < 22.0:
			continue
		if _on_hill(p, 0.35):
			continue  # sit trees beside knolls, not through them
		var h := rng.randf_range(3.5, 6.0)
		_mesh_cyl(_gen, p + Vector3(0, h * 0.4, 0), 0.22, 0.3, h * 0.8, C_TRUNK)
		var crown := _mesh_sphere(_gen, p + Vector3(0, h * 0.85, 0), rng.randf_range(1.6, 2.6), C_CANOPY.darkened(rng.randf_range(0.0, 0.15)))
		crown.scale = Vector3(1.0, 0.85, 1.0)
		placed += 1


func _build_labels(path: Array[Vector3]) -> void:
	_label(Vector3(-8.0, 5.6, -1.0), "Home — the house", 40, Color(0.95, 0.9, 0.75))
	_label(Vector3(7.0, 4.6, -2.6), "Byre", 40, Color(0.95, 0.9, 0.75))
	var home := _zone_box(home_zone_path, Vector3(7.0, 1.2, 6.5), Vector3(12.6, 2.4, 10.6))
	_label(home.get_center() + Vector3(0, 2.0, 0), "Home pen\n(drive the herd in)", 34, Color(0.7, 0.92, 0.55))
	var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	_label(pas.get_center() + Vector3(0, 4.5, -6.0), "Secluded pasture", 46, Color(0.85, 0.95, 0.7))
	var bog := _zone_box(bog_zone_path, Vector3(34.0, 1.0, 118.0), Vector3(20.0, 2.0, 20.0))
	_label(bog.get_center() + Vector3(0, 2.6, 0), "Bog edge — cattle bog down here", 34, Color(0.75, 0.85, 0.6))
	_label(Vector3(-27.0, 2.4, 40.0), "Ditch (farm edge)", 30, Color(0.7, 0.8, 0.6))
	if path.size() >= 2:
		_label(path[0] + Vector3(-3.8, 2.3, 0), "Lane to the pasture ↓", 32, Color(0.95, 0.88, 0.6))


# ---------------------------------------------------------------- helpers


func _hill_surface_y(p: Vector3) -> float:
	## Approximate mound height above grade at xz (0 if off every knoll).
	var best := 0.0
	for h in _hill_defs:
		var c: Vector3 = h["c"]
		var r: float = h["r"]
		var scl: Vector3 = h["scl"]
		var sink := r * scl.y * 0.55
		var rem := 1.0 - pow((p.x - c.x) / (r * scl.x), 2.0) - pow((p.z - c.z) / (r * scl.z), 2.0)
		if rem <= 0.0:
			continue
		var y_surf := -sink + (r * scl.y) * sqrt(rem)
		if y_surf > best:
			best = y_surf
	return best


func _on_hill(p: Vector3, thr: float = 0.4) -> bool:
	return _hill_surface_y(p) > thr


func _near_lane(p: Vector3, path: Array[Vector3], dist: float) -> bool:
	for i in path.size() - 1:
		var a := Vector2(path[i].x, path[i].z)
		var b := Vector2(path[i + 1].x, path[i + 1].z)
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
		if q.distance_to(a + ab * t) < dist:
			return true
	return false


func _in_xz(box: AABB, p: Vector3) -> bool:
	return p.x >= box.position.x and p.x <= box.end.x and p.z >= box.position.z and p.z <= box.end.z


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
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


func _mesh_cyl(parent: Node, pos: Vector3, top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mesh_sphere(parent: Node, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _solid_box(parent: Node, pos: Vector3, size: Vector3, color: Color, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = rot_y
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	_mesh_box(body, Vector3.ZERO, size, color)
	return body


func _roof(parent: Node, base: Vector3, size: Vector3, color: Color) -> void:
	# PrismMesh ridge runs along local Z; rotate so the ridge follows the long (X) axis.
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(size.z, size.y, size.x)
	mi.mesh = pm
	mi.material_override = _mat(color)
	mi.position = base + Vector3(0, size.y * 0.5, 0)
	mi.rotation.y = PI * 0.5
	parent.add_child(mi)


func _rail(a: Vector3, b: Vector3) -> void:
	## Wattle/post-and-rail fence segment with a single box collider (blocks cattle + player).
	var flat_a := Vector3(a.x, 0.0, a.z)
	var flat_b := Vector3(b.x, 0.0, b.z)
	var length := flat_a.distance_to(flat_b)
	if length < 0.2:
		return
	var mid := (flat_a + flat_b) * 0.5
	var yaw := atan2(flat_b.x - flat_a.x, flat_b.z - flat_a.z)
	var body := StaticBody3D.new()
	body.name = "Rail"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = mid + Vector3(0, RAIL_HEIGHT * 0.5, 0)
	body.rotation.y = yaw
	_gen.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, RAIL_HEIGHT, length)
	cs.shape = bs
	body.add_child(cs)
	for h in [0.32, 0.78]:
		_mesh_box(body, Vector3(0, h - RAIL_HEIGHT * 0.5, 0), Vector3(0.1, 0.12, length), C_RAIL)
	var posts := maxi(2, int(length / 2.4) + 1)
	for i in posts:
		var t := float(i) / float(posts - 1) - 0.5
		_mesh_box(body, Vector3(0, 0.0, t * length), Vector3(0.16, RAIL_HEIGHT, 0.16), C_RAIL.darkened(0.15))


func _label(pos: Vector3, text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
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
