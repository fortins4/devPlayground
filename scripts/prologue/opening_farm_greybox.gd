@tool
extends Node3D
## Greybox geometry for the first-morning cattle drive (house · byre · home pen · twisting
## lane · secluded pasture behind gradual rolling hills (lane winds through saddles) · bog edge · west ditch · neighbours' ringfort).
##
## Builds plain boxes/prisms/cylinders at _ready into an un-owned child, so the layout shows in
## the editor (tool script) but nothing generated is serialized into the .tscn.
## Landscape is physical: OpeningTerrain is the one height function; the terrain mesh and its
## HeightMapShape3D collider are built from the same baked samples, and everything that sits on
## the ground (lane, bog, ditch, rails, hedges, trees, labels, ringfort) is draped onto it. Gameplay nodes
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
const C_SPRING_WATER := Color(0.35, 0.48, 0.52)  # clear farm spring (cooler than bog)
const C_REED := Color(0.5, 0.52, 0.28)
## Natural bog (back paddock): moss / peat ground paint, standing water, tussocks + rushes.
const C_BOG_MOSS := Color(0.31, 0.37, 0.16)
const C_BOG_PEAT := Color(0.23, 0.2, 0.13)
const C_BOG_POOL := Color(0.05, 0.06, 0.05)
const C_TUSSOCK := [Color(0.42, 0.45, 0.21), Color(0.33, 0.4, 0.17), Color(0.55, 0.5, 0.3)]
const C_RUSH := [Color(0.34, 0.44, 0.19), Color(0.48, 0.5, 0.26)]
const C_DITCH := Color(0.17, 0.2, 0.14)
const C_BANK := Color(0.3, 0.38, 0.22)
const C_HEDGE := Color(0.2, 0.33, 0.17)
const C_TRUNK := Color(0.32, 0.25, 0.18)
const C_CANOPY := Color(0.24, 0.38, 0.2)
const C_RATH_BANK := Color(0.33, 0.42, 0.25)
const C_HUT := Color(0.68, 0.62, 0.5)
const C_DAUB := Color(0.74, 0.66, 0.52)   ## clay/lime daub over wattle (family roundhouse)
## Family roundhouse radius (m): 7 m across, door on the old spot by Máire.
const HOUSE_R := 3.5

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
## Terrain mesh tile size (cells). Smaller tiles cull better; same samples as the collider.
const TERRAIN_TILE := 48
## Draped overlays / walls are cut into pieces no longer than this (m) so they hug curvature.
const DRAPE_STEP := 2.4
## Back paddock (behind the pasture's south ridge, holds the bog): gap half-width in the pasture's
## south rail + hedge, and the paddock's hedged extent.
const BACK_GAP_HALF := 3.0
const PADDOCK_X0 := -54.0
const PADDOCK_X1 := 10.0
const PADDOCK_Z1 := 256.0

var _mats: Dictionary = {}
var _gen: Node3D = null
var _terrain_mat: StandardMaterial3D = null


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
	var path := _path_points()
	# One height function for hills / berms / banks / swells (mouth berms follow PastureMouth).
	Terrain.configure(path[-1].x if path.size() > 0 else -28.0)
	Terrain.bake()
	_build_ground()  # terrain mesh + HeightMapShape3D from the same samples
	_build_farmstead()
	_build_rath()
	_build_home_pen()
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
	## Physical landscape: every hill, pasture berm / bank and far swell lives in OpeningTerrain.
	## The visible terrain mesh and the HeightMapShape3D are built from the SAME baked samples
	## with the SAME cell triangulation, so feet rest on exactly the surface that is drawn.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	_gen.add_child(ground)
	var w := Terrain.grid_width()
	var d := Terrain.grid_depth()
	var hs := Terrain.bake()
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = d
	hm.map_data = hs
	var terrain_cs := CollisionShape3D.new()
	terrain_cs.name = "TerrainHeightMap"
	terrain_cs.shape = hm
	# HeightMapShape3D is centred on its node, 1 m per sample (STEP == 1).
	terrain_cs.position = Vector3(
		Terrain.MIN_X + float(w - 1) * 0.5 * Terrain.STEP, 0.0, Terrain.MIN_Z + float(d - 1) * 0.5 * Terrain.STEP)
	terrain_cs.scale = Vector3(Terrain.STEP, 1.0, Terrain.STEP)
	ground.add_child(terrain_cs)
	# Flat far-field backstop + grass sheet OUTSIDE the heightfield window (2 cm under grade): a
	# frame of four slabs around the window (overlapping it by 0.5 m), so neither floors nor
	# paints over the bog dip inside it.
	# Plus a deep safety net under everything (top 1.5 m down, below the dip floor).
	var far := Rect2(-220.0, -150.0, 420.0, 460.0)  # old single backstop's XZ extent
	var win := Rect2(Terrain.MIN_X + 0.5, Terrain.MIN_Z + 0.5,
		float(w - 1) * Terrain.STEP - 1.0, float(d - 1) * Terrain.STEP - 1.0)
	var slabs := [
		Rect2(far.position.x, far.position.y, far.size.x, win.position.y - far.position.y),  # north
		Rect2(far.position.x, win.end.y, far.size.x, far.end.y - win.end.y),  # south
		Rect2(far.position.x, win.position.y, win.position.x - far.position.x, win.size.y),  # west
		Rect2(win.end.x, win.position.y, far.end.x - win.end.x, win.size.y),  # east
	]
	for r: Rect2 in slabs:
		var slab := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(r.size.x, 1.0, r.size.y)
		slab.shape = sb
		slab.position = Vector3(r.get_center().x, -0.52, r.get_center().y)
		ground.add_child(slab)
		# Matching far-field grass sheet (same frame — never drawn over the bog dip).
		_mesh_box(ground, Vector3(r.get_center().x, -0.07, r.get_center().y), Vector3(r.size.x, 0.1, r.size.y), C_GRASS)
	var net := CollisionShape3D.new()
	var nb := BoxShape3D.new()
	nb.size = Vector3(far.size.x, 1.0, far.size.y)
	net.shape = nb
	net.position = Vector3(far.get_center().x, -2.0, far.get_center().y)
	ground.add_child(net)
	_build_terrain_mesh(hs, w, d)


func _bog_ground(x: float, z: float, h: float) -> Color:
	var n := Terrain._bnoise().get_noise_2d(x * 0.9 + 100.0, z * 0.9 - 60.0)
	var c := C_BOG_MOSS.lerp(C_BOG_PEAT, clampf(0.5 + n * 1.4, 0.0, 1.0))
	# Wet floor reads darker from dip depth (works for the main bog and the decorative patches).
	var depth := Terrain.bog_depth(x, z) + Terrain.deco_bog_depth(x, z)
	var wet := clampf((depth - 0.12) / 0.35, 0.0, 1.0)
	return c.darkened(0.35 * wet)


func _build_terrain_mesh(hs: PackedFloat32Array, w: int, d: int) -> void:
	## Tiled ArrayMesh over the baked grid. Vertex colour = grass blended toward the dominant
	## hill / berm colour (as the old per-hill sphere meshes read), smooth grid normals.
	if _terrain_mat == null:
		_terrain_mat = StandardMaterial3D.new()
		_terrain_mat.vertex_color_use_as_albedo = true
		_terrain_mat.roughness = 0.95
	var step := Terrain.STEP
	var caps: Array = Terrain.caps()
	# Pasture field tint is painted into the terrain (not a flat overlay box) so it meets the
	# side banks cleanly; the banks keep their own colour where they rise.
	var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	# Per-sample colour + normal.
	var cols := PackedColorArray()
	cols.resize(w * d)
	var nrms := PackedVector3Array()
	nrms.resize(w * d)
	for iz in d:
		var z := Terrain.MIN_Z + float(iz) * step
		for ix in w:
			var i := iz * w + ix
			var x := Terrain.MIN_X + float(ix) * step
			var h := hs[i]
			var base := C_PASTURE if _in_xz(pas, Vector3(x, 0.0, z)) else C_GRASS
			var c := base
			if h > 0.0005:
				var dom := Terrain.dominant_cap(x, z)
				if dom >= 0:
					var f := Terrain.cap_value(caps[dom], x, z)
					var k := smoothstep(-Terrain.FILLET * 0.6, Terrain.FILLET * 0.6, f)
					c = base.lerp(caps[dom]["color"], k)
			# Family ráth: trodden yard inside the bank, bank turf, dark wet ditch outside it.
			var rr := Terrain.rath_radius(x, z)
			if rr < Terrain.RATH_EXTENT:
				c = c.lerp(C_YARD, smoothstep(Terrain.RATH_R - 1.2, Terrain.RATH_R - 2.8, rr))
				var rel := Terrain.rath_relief(x, z)
				if rel > 0.0:
					c = c.lerp(C_RATH_BANK, clampf(rel / 0.45, 0.0, 1.0))
				elif rel < 0.0:
					c = c.lerp(C_DITCH, clampf(-rel / 0.35, 0.0, 1.0))
			# Natural bog: blended into the grass by the terrain's own soft bog mask (no overlay
			# slab, no rim) — mottled moss / peat, darker toward the wet floor.
			if absf(x - Terrain.BOG_CX) < Terrain.BOG_EXTENT and absf(z - Terrain.BOG_CZ) < Terrain.BOG_EXTENT:
				var bm := Terrain.bog_mask(x, z)
				if bm > 0.0:
					c = c.lerp(_bog_ground(x, z, h), bm)
			# Decorative west-of-lane bog patches (same moss/peat fade, no square overlays).
			var dm := Terrain.deco_bog_mask(x, z)
			if dm > 0.0:
				c = c.lerp(_bog_ground(x, z, h), dm)
			cols[i] = c
			var hl := hs[iz * w + maxi(ix - 1, 0)]
			var hr := hs[iz * w + mini(ix + 1, w - 1)]
			var hd := hs[maxi(iz - 1, 0) * w + ix]
			var hu := hs[mini(iz + 1, d - 1) * w + ix]
			nrms[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var root := Node3D.new()
	root.name = "TerrainMesh"
	_gen.add_child(root)
	var tz := 0
	while tz < d - 1:
		var tz1 := mini(tz + TERRAIN_TILE, d - 1)
		var tx := 0
		while tx < w - 1:
			var tx1 := mini(tx + TERRAIN_TILE, w - 1)
			_terrain_tile(root, hs, cols, nrms, w, tx, tz, tx1, tz1)
			tx = tx1
		tz = tz1


func _terrain_tile(root: Node3D, hs: PackedFloat32Array, cols: PackedColorArray, nrms: PackedVector3Array,
		w: int, tx0: int, tz0: int, tx1: int, tz1: int) -> void:
	var step := Terrain.STEP
	var tw := tx1 - tx0 + 1
	var verts := PackedVector3Array()
	var vn := PackedVector3Array()
	var vc := PackedColorArray()
	var flat := true
	for iz in range(tz0, tz1 + 1):
		for ix in range(tx0, tx1 + 1):
			var i := iz * w + ix
			verts.append(Vector3(Terrain.MIN_X + float(ix) * step, hs[i], Terrain.MIN_Z + float(iz) * step))
			vn.append(nrms[i])
			vc.append(cols[i])
			if absf(hs[i]) > 0.0005 or cols[i] != C_GRASS:
				flat = false
	var idx := PackedInt32Array()
	if flat:
		# Open field tile: two triangles are enough (all samples are 0).
		verts = PackedVector3Array([verts[0], verts[tw - 1], verts[verts.size() - tw], verts[verts.size() - 1]])
		vn = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		vc = PackedColorArray([C_GRASS, C_GRASS, C_GRASS, C_GRASS])
		idx = PackedInt32Array([0, 1, 2, 1, 3, 2])
	else:
		for z in tz1 - tz0:
			for x in tw - 1:
				var p00 := z * tw + x
				var p10 := p00 + 1
				var p01 := p00 + tw
				var p11 := p01 + 1
				# Same split as HeightMapShape3D: (x+1,z)–(x,z+1) diagonal. Clockwise = front (up).
				idx.append_array([p00, p10, p01, p10, p11, p01])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = vn
	arrays[Mesh.ARRAY_COLOR] = vc
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _terrain_mat
	root.add_child(mi)


func _build_farmstead() -> void:
	# Muddy yard: painted into the terrain inside the ráth bank (see _build_terrain_mesh).
	_build_roundhouse()
	# Byre / calf shed — small and low inside the ráth, door opening onto the night pen.
	var byre := Vector3(7.0, 0.0, -2.2)
	_solid_box(_gen, byre + Vector3(0, 1.0, 0), Vector3(7.5, 2.0, 4.0), C_BYRE)
	_roof(_gen, byre + Vector3(0, 2.0, 0), Vector3(8.1, 1.5, 4.6), C_THATCH.darkened(0.08))
	_mesh_box(_gen, byre + Vector3(0, 0.85, 2.02), Vector3(2.2, 1.7, 0.08), C_DOOR)
	# Hay rick + woodpile + quern stone dressing (rick and woodpile tucked inside the bank).
	_mesh_cyl(_gen, Vector3(-9.5, 1.0, 8.5), 1.4, 1.4, 2.0, C_THATCH)
	_mesh_cyl(_gen, Vector3(-9.5, 2.6, 8.5), 0.05, 1.5, 1.2, C_THATCH.darkened(0.05))
	_solid_box(_gen, Vector3(-3.8, 0.45, -6.1), Vector3(2.6, 0.9, 1.0), C_TRUNK)
	_mesh_cyl(_gen, Vector3(-5.0, 0.2, 3.6), 0.45, 0.45, 0.4, C_WALL.darkened(0.35))
	_build_spring_scoop()


func _build_roundhouse() -> void:
	## Family house: round wattle-and-daub wall under a thatch cone, door facing the yard on the
	## same spot as before (OpeningFamilyCaller.DOOR_POS), central hearth under a smoke hole.
	var door := Vector3(-7.2, 0.0, 1.77)
	var c := door - Vector3(0.0, 0.0, HOUSE_R)
	var wall_h := 1.9
	# Solid round wall (one cylinder collider; the hearth inside is dressing only).
	var body := StaticBody3D.new()
	body.name = "Roundhouse"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = c + Vector3(0, wall_h * 0.5, 0)
	_gen.add_child(body)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = HOUSE_R
	cyl.height = wall_h
	cs.shape = cyl
	body.add_child(cs)
	# Daub skin over the wattle, a darker splash-band at the foot, and wattle weave hints.
	var wall_mi := _mesh_cyl(body, Vector3.ZERO, HOUSE_R, HOUSE_R, wall_h, C_DAUB)
	(wall_mi.mesh as CylinderMesh).radial_segments = 36
	var foot_mi := _mesh_cyl(body, Vector3(0, -wall_h * 0.5 + 0.18, 0), HOUSE_R + 0.03, HOUSE_R + 0.03, 0.36, C_DAUB.darkened(0.3))
	(foot_mi.mesh as CylinderMesh).radial_segments = 36
	for i in 28:
		var ang := TAU * float(i) / 28.0
		if absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.32:
			continue  # door
		var post := _mesh_box(body, Vector3(cos(ang) * (HOUSE_R + 0.02), 0.1, sin(ang) * (HOUSE_R + 0.02)), Vector3(0.09, wall_h - 0.5, 0.06), C_DAUB.darkened(0.14))
		post.rotation.y = -ang + PI * 0.5
	# Doorway: dark opening with timber jambs and lintel.
	_mesh_box(_gen, door + Vector3(0, 0.82, 0.02), Vector3(1.0, 1.64, 0.12), C_DOOR)
	for sx in [-0.6, 0.6]:
		_mesh_box(_gen, door + Vector3(sx, 0.85, 0.06), Vector3(0.14, 1.75, 0.16), C_TRUNK)
	_mesh_box(_gen, door + Vector3(0, 1.74, 0.06), Vector3(1.36, 0.14, 0.18), C_TRUNK)
	# Thatch cone: eaves well out past the wall, truncated at the top for the smoke hole.
	var cone_h := 3.3
	var cone := _mesh_cyl(_gen, c + Vector3(0, wall_h + cone_h * 0.5 - 0.15, 0), 0.32, HOUSE_R + 0.7, cone_h, C_THATCH)
	(cone.mesh as CylinderMesh).radial_segments = 36
	_mesh_cyl(_gen, c + Vector3(0, wall_h - 0.12, 0), HOUSE_R + 0.7, HOUSE_R + 0.72, 0.1, C_THATCH.darkened(0.12))  # eave lip
	_mesh_cyl(_gen, c + Vector3(0, wall_h + cone_h - 0.12, 0), 0.26, 0.26, 0.06, Color(0.08, 0.07, 0.06))  # smoke hole
	# Hearth smoke drifting from the hole (a few soft puffs).
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color(0.72, 0.72, 0.7, 0.32)
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 4:
		var puff := _mesh_sphere(_gen, c + Vector3(0.15 * k, wall_h + cone_h + 0.25 + 0.55 * k, -0.1 * k), 0.28 + 0.14 * k, C_THATCH)
		puff.material_override = smoke
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Central hearth (stone kerb + embers), seen through the door.
	for i in 8:
		var ang := TAU * float(i) / 8.0
		_mesh_box(_gen, c + Vector3(cos(ang) * 0.55, 0.08, sin(ang) * 0.55), Vector3(0.28, 0.16, 0.22), C_WALL.darkened(0.4))
	_mesh_cyl(_gen, c + Vector3(0, 0.05, 0), 0.42, 0.42, 0.06, Color(0.45, 0.16, 0.06))


func _build_spring_scoop() -> void:
	## Dug-out spring scoop by the farmstead — clean water source (not a village well).
	## Yard→grass SW edge — nudged farther into wild/damp ground (not by house/rick).
	var spring := Vector3(-23.5, 0.0, 19.0)
	# Shallow dug hollow (elongated oval ~3.2 × 1.9 m) — sunken ditch earth, not a shaft.
	_mesh_box(_gen, spring + Vector3(0.0, -0.08, 0.0), Vector3(3.2, 0.22, 1.9), C_DITCH)
	# Soft bank lips around the scoop rim.
	_mesh_box(_gen, spring + Vector3(0.0, 0.06, -1.15), Vector3(3.4, 0.18, 0.45), C_BANK)
	_mesh_box(_gen, spring + Vector3(0.0, 0.06, 1.15), Vector3(3.4, 0.18, 0.45), C_BANK)
	_mesh_box(_gen, spring + Vector3(-1.75, 0.06, 0.0), Vector3(0.4, 0.18, 2.0), C_BANK)
	_mesh_box(_gen, spring + Vector3(1.75, 0.06, 0.0), Vector3(0.4, 0.18, 2.0), C_BANK)
	# Rustic stone curb lining (low farm stones, not a masonry well curb).
	var stone := C_WALL.darkened(0.28)
	for ox in [-1.2, -0.4, 0.4, 1.2]:
		_mesh_box(_gen, spring + Vector3(ox, 0.12, -0.85), Vector3(0.55, 0.22, 0.28), stone)
		_mesh_box(_gen, spring + Vector3(ox, 0.12, 0.85), Vector3(0.55, 0.22, 0.28), stone)
	_mesh_box(_gen, spring + Vector3(-1.45, 0.11, 0.0), Vector3(0.28, 0.2, 1.2), stone)
	_mesh_box(_gen, spring + Vector3(1.45, 0.11, 0.0), Vector3(0.28, 0.2, 1.2), stone)
	# Timber plank on the north rim — rustic wood lining.
	_mesh_box(_gen, spring + Vector3(0.2, 0.14, -1.0), Vector3(1.8, 0.08, 0.18), C_TRUNK)
	# Clear spring pool (visibly cooler/clearer than C_BOG_WATER).
	_mesh_box(_gen, spring + Vector3(0.0, 0.02, 0.0), Vector3(2.6, 0.06, 1.35), C_SPRING_WATER)
	# Tiny spring-eye at the west head of the scoop.
	_mesh_box(_gen, spring + Vector3(-1.0, 0.025, -0.15), Vector3(0.55, 0.05, 0.45), C_SPRING_WATER.darkened(0.22))
	# Short outflow ditch trickle SE toward lower yard / damp edge (clear → slightly murkier).
	_mesh_box(_gen, spring + Vector3(1.8, -0.02, 0.9), Vector3(1.4, 0.1, 0.55), C_DITCH)
	_mesh_box(_gen, spring + Vector3(2.4, 0.01, 1.35), Vector3(1.1, 0.04, 0.4), C_SPRING_WATER.darkened(0.12))
	_mesh_box(_gen, spring + Vector3(3.2, 0.005, 1.9), Vector3(0.9, 0.03, 0.35), Color(0.22, 0.28, 0.28))


func _build_rath() -> void:
	## Family ráth: the bank + ditch are terrain relief (OpeningTerrain.rath_relief); here the
	## palisade on the crest (stakes + solid collider runs) and the entrance gateposts.
	var c := Vector3(Terrain.RATH_CX, 0.0, Terrain.RATH_CZ)
	var r := Terrain.RATH_R - 0.15
	var segs := 64
	var stakes: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var ends: Array[Vector3] = []
	var was_on := true
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := c + Vector3(cos(a0), 0.0, sin(a0)) * r
		var p1 := c + Vector3(cos(a1), 0.0, sin(a1)) * r
		var on := Terrain.rath_gap_mask(p0.x, p0.z) > 0.85 and Terrain.rath_gap_mask(p1.x, p1.z) > 0.85
		if on != was_on:
			ends.append(p0)
		was_on = on
		if not on:
			continue
		var y0 := _ground_y(p0)
		var y1 := _ground_y(p1)
		var mid := (p0 + p1) * 0.5
		var seg := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		var body := StaticBody3D.new()
		body.name = "Palisade"
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(mid.x, (y0 + y1) * 0.5, mid.z)
		body.rotation = Vector3(0.0, atan2(p1.x - p0.x, p1.z - p0.z), 0.0)
		_gen.add_child(body)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.3, 2.1, seg + 0.08)
		cs.shape = bs
		cs.position = Vector3(0.0, 0.75, 0.0)
		body.add_child(cs)
		# Close-set split stakes, slightly uneven tops.
		var n := int(ceil(seg / 0.21))
		for k in n:
			var t := (float(k) + 0.5) / float(n)
			var sp := p0.lerp(p1, t)
			var h := rng.randf_range(1.55, 1.95)
			var basis := Basis(Vector3.UP, atan2(p1.x - p0.x, p1.z - p0.z)).rotated(Vector3.UP, 0.0)
			basis = basis.scaled(Vector3(1.0, h, 1.0))
			stakes.append(Transform3D(basis, Vector3(sp.x, _ground_y(sp) + h * 0.5 - 0.25, sp.z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 1.0, 0.2)
	mm.mesh = bm
	mm.instance_count = stakes.size()
	for i in stakes.size():
		mm.set_instance_transform(i, stakes[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PalisadeStakes"
	mmi.multimesh = mm
	mmi.material_override = _mat(C_RAIL.darkened(0.12))
	_gen.add_child(mmi)
	# Entrance: a pair of stout gateposts at the palisade ends.
	for e in ends:
		_mesh_box(_gen, _on_ground(e + Vector3(0, 1.05, 0), -0.2), Vector3(0.36, 2.5, 0.36), C_RAIL.darkened(0.25))


## Inside the entrance: rails from the bank's inner toe (behind each palisade end) toward the
## night-pen gate. East side closes to the pen's east gate post (just outside it, so the open
## east leaf swings back against it); west side stops short so Cian can step in from the yard.
func _build_rath_funnel() -> void:
	var box := _zone_box(home_zone_path, Vector3(6.5, 1.2, 5.5), Vector3(9.0, 2.4, 8.0))
	var z1 := box.end.z + 0.4
	var cx := box.get_center().x
	_rail(Vector3(cx + 2.3 + 0.35, 0.0, z1), _rath_toe_point(-1.0))
	var west_toe := _rath_toe_point(1.0)
	_rail(west_toe, west_toe.lerp(Vector3(cx - 2.3, 0.0, z1), 0.45))


## Inner bank toe radially behind the palisade end on one side of the entrance
## (side -1 = east / clockwise, +1 = west / anticlockwise).
func _rath_toe_point(side: float) -> Vector3:
	var c := Vector2(Terrain.RATH_CX, Terrain.RATH_CZ)
	var mid := Terrain.RATH_GAP_A + Terrain.RATH_GAP_DIR * 3.0
	var a := (mid - c).angle()
	for k in 180:
		var ang := a + side * deg_to_rad(float(k) * 0.5)
		var q := c + Vector2(cos(ang), sin(ang)) * Terrain.RATH_R
		if Terrain.rath_gap_mask(q.x, q.y) > 0.85:
			var t := c + Vector2(cos(ang), sin(ang)) * (Terrain.RATH_R - Terrain.RATH_BANK_HALF - 0.3)
			return Vector3(t.x, 0.0, t.y)
	return Vector3(mid.x, 0.0, mid.y)


func _build_home_pen() -> void:
	var box := _zone_box(home_zone_path, Vector3(6.5, 1.2, 5.5), Vector3(9.0, 2.4, 8.0))
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
	# Gate posts. The hinged double gate + latch hang on them from OpeningPenGateChore.
	for gx in [cx - gate_half, cx + gate_half]:
		_mesh_box(_gen, Vector3(gx, 0.75, z1), Vector3(0.3, 1.5, 0.3), C_RAIL.darkened(0.2))
	# Trampled pen floor.
	_mesh_box(_gen, Vector3(box.get_center().x, 0.03, box.get_center().z), Vector3(box.size.x, 0.04, box.size.z), C_YARD.darkened(0.12))


func _build_lane(path: Array[Vector3]) -> void:
	if path.size() < 2:
		return
	# Lane strips + soft joints, draped on the terrain (the boreen climbs the skirts it crosses).
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b) + 1.2
		_drape_rect(mid, LANE_WIDTH, length, atan2(b.x - a.x, b.z - a.z), 0.035, C_LANE)
		_drape_disc(a, LANE_WIDTH * 0.5, LANE_WIDTH * 0.5, 0.036, C_LANE)
	_drape_disc(path[-1], LANE_WIDTH * 0.5, LANE_WIDTH * 0.5, 0.036, C_LANE)
	# Bias stakes (white-topped) at every marker — the drove's waypoints.
	for p in path:
		var sp := Vector3(p.x + LANE_WIDTH * 0.62, 0.0, p.z)
		_mesh_box(_gen, _on_ground(sp + Vector3(0, 0.5, 0)), Vector3(0.18, 1.1, 0.18), C_RAIL)
		_mesh_box(_gen, _on_ground(sp + Vector3(0, 1.1, 0)), Vector3(0.24, 0.16, 0.24), C_STAKE_TOP)
	# The boreen enters the ráth over the causeway; inside, short rails funnel the herd from
	# the entrance to the night-pen gate (bank + ditch do the funnelling outside).
	_build_rath_funnel()
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
		if Terrain.rath_radius(c.x, c.z) < Terrain.RATH_EXTENT + 8.0:
			continue  # clear of the ráth bank / ditch
		_rail(c - along * 7.0, c + along * 7.0)


func _build_pasture() -> void:
	var box := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	var c := box.get_center()
	# Field tint is painted into the terrain mesh (see _build_terrain_mesh).
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
	# South rail with a gap into the back paddock (over the south ridge to the bog), lined up
	# with the bog so a freed cow walks straight back to the herd.
	var gx := _back_gap_x()
	_rail(Vector3(x0, 0, z1), Vector3(gx - BACK_GAP_HALF, 0, z1))
	_rail(Vector3(gx + BACK_GAP_HALF, 0, z1), Vector3(x1, 0, z1))
	# Water trough + rubbing stone.
	# Both sit on the pasture side banks — rest them on the surface (sunk a touch, no float).
	_solid_box(_gen, _on_ground(Vector3(x1 - 4.0, 0.3, c.z + 4.0)), Vector3(2.6, 0.7, 0.9), C_TRUNK)
	_solid_box(_gen, _on_ground(Vector3(x0 + 6.0, 0.5, z1 - 5.0)), Vector3(0.9, 1.2, 0.9), C_WALL.darkened(0.4))


func _build_bog() -> void:
	## Natural bog in the back paddock behind the pasture's south ridge. The ground itself is the
	## bog: OpeningTerrain sinks an organic, noise-wobbled dip (shared collider + mesh) and the
	## terrain mesh paints it by the same soft mask. On top: standing water where the dip floor
	## drops below the water line, then tussocks, rush clumps and bog cotton scattered by the mask.
	_build_bog_water()
	_build_bog_plants()
	# Decorative west-of-lane bog patches: same organic treatment (shallower dip, no stuck logic).
	for p in Terrain.deco_bogs():
		_build_deco_bog_patch(p)


func _build_bog_water() -> void:
	## One flat sheet at BOG_WATER_Y over every grid cell that dips below it; the terrain hides it
	## wherever the ground stands higher, so the pool shorelines follow the hummocks.
	var wy := Terrain.BOG_WATER_Y
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var e := int(Terrain.BOG_EXTENT)
	for iz in range(-e, e):
		for ix in range(-e, e):
			var x0 := Terrain.BOG_CX + float(ix)
			var z0 := Terrain.BOG_CZ + float(iz)
			var lo := minf(minf(_ground_y(Vector3(x0, 0, z0)), _ground_y(Vector3(x0 + 1.0, 0, z0))),
				minf(_ground_y(Vector3(x0, 0, z0 + 1.0)), _ground_y(Vector3(x0 + 1.0, 0, z0 + 1.0))))
			if lo >= wy:
				continue
			var b := verts.size()
			verts.append_array([Vector3(x0, wy, z0), Vector3(x0 + 1.0, wy, z0), Vector3(x0, wy, z0 + 1.0), Vector3(x0 + 1.0, wy, z0 + 1.0)])
			for k in 4:
				norms.append(Vector3.UP)
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "BogWater"
	mi.mesh = am
	var m := StandardMaterial3D.new()
	# Dark peaty water: low specular so a bright sky doesn't turn it pale slate (esp. edge-on).
	m.albedo_color = C_BOG_POOL
	m.roughness = 0.35
	m.metallic_specular = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_gen.add_child(mi)


func _build_bog_plants() -> void:
	## Tussocks + rush clumps + bog cotton, merged into one mesh per colour (few draw calls).
	## Denser inside, thinning across the soft edge (a few stray tussocks just outside it), never
	## standing in open water.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var tools := {}
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	var blade := BoxMesh.new()
	blade.size = Vector3.ONE
	var ext := Terrain.BOG_EXTENT
	var placed_t := 0
	var placed_r := 0
	var tries := 0
	while (placed_t < 70 or placed_r < 38) and tries < 4000:
		tries += 1
		var p := Vector3(Terrain.BOG_CX + rng.randf_range(-ext, ext), 0.0, Terrain.BOG_CZ + rng.randf_range(-ext, ext))
		var m := Terrain.bog_mask(p.x, p.z)
		if m < 0.04:
			continue
		var gy := _ground_y(p)
		if gy < Terrain.BOG_WATER_Y + 0.04:
			continue  # open water
		var keep := 0.15 + 0.85 * m
		if rng.randf() > keep:
			continue
		if placed_t < 70 and (placed_r >= 38 or rng.randf() < 0.62):
			var r := rng.randf_range(0.28, 0.6) * (0.6 + 0.4 * m)
			var col: Color = C_TUSSOCK[rng.randi() % C_TUSSOCK.size()]
			var xf := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(r, r * rng.randf_range(0.45, 0.7), r * rng.randf_range(0.8, 1.2))), Vector3(p.x, gy - r * 0.12, p.z))
			_st_append(tools, col, sphere, xf)
			placed_t += 1
		elif placed_r < 38 and m > 0.3:
			var blades := rng.randi_range(6, 11)
			for b in blades:
				var h := rng.randf_range(0.5, 1.25)
				var off := Vector3(rng.randf_range(-0.28, 0.28), 0.0, rng.randf_range(-0.28, 0.28))
				var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
				var base := Vector3(p.x, gy - 0.05, p.z) + off
				var xf := Transform3D(tilt.scaled(Vector3(0.035, h, 0.035)), base + tilt * Vector3(0, h * 0.5, 0))
				_st_append(tools, C_RUSH[rng.randi() % C_RUSH.size()], blade, xf)
			placed_r += 1
	# Bog cotton: small white heads on the drier hummocks.
	for i in 26:
		var p := Vector3(Terrain.BOG_CX + rng.randf_range(-ext, ext), 0.0, Terrain.BOG_CZ + rng.randf_range(-ext, ext))
		if Terrain.bog_mask(p.x, p.z) < 0.5 or _ground_y(p) < Terrain.BOG_WATER_Y + 0.06:
			continue
		var xf := Transform3D(Basis().scaled(Vector3.ONE * 0.075), Vector3(p.x, _ground_y(p) + rng.randf_range(0.25, 0.45), p.z))
		_st_append(tools, C_STAKE_TOP, sphere, xf)
	for key in tools:
		var st: SurfaceTool = tools[key][0]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "BogPlants"
		mi.mesh = st.commit()
		mi.material_override = _mat(tools[key][1])
		_gen.add_child(mi)
	print("OPENING_BOG_NATURAL tussocks=%d rush_clumps=%d" % [placed_t, placed_r])


func _st_append(tools: Dictionary, col: Color, mesh: Mesh, xf: Transform3D) -> void:
	var key := col.to_html()
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = [st, col]
	(tools[key][0] as SurfaceTool).append_from(mesh, 0, xf)


func _build_deco_bog_patch(p: Dictionary) -> void:
	## One decorative organic bog: pools where the shallow dip is deep enough, plus a few
	## tussocks / rush clumps / bog cotton. No flat square, slab or rim — paint is in the terrain.
	_build_deco_bog_water(p)
	_build_deco_bog_plants(p)


func _build_deco_bog_water(p: Dictionary) -> void:
	## These patches sit on hill skirts, so one level sheet would float over the downhill side.
	## Instead the water surface follows the UNDIPPED ground, water_rel below it, on the same grid
	## and diagonal as the terrain. It only rises above the (dipped) ground where the dip is deeper
	## than water_rel, so the terrain clips it into pools in the hollows between the hummocks.
	var cx := float(p["cx"])
	var cz := float(p["cz"])
	var water_rel := float(p["water_rel"])
	var e := int(ceil(float(p["extent"])))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for iz in range(-e, e):
		for ix in range(-e, e):
			var x0 := cx + float(ix)
			var z0 := cz + float(iz)
			var cs := [Vector2(x0, z0), Vector2(x0 + 1.0, z0), Vector2(x0, z0 + 1.0), Vector2(x0 + 1.0, z0 + 1.0)]
			var wet := false
			var ws: Array[float] = []
			for c: Vector2 in cs:
				var dep := Terrain.deco_bog_depth_one(p, c.x, c.y)
				ws.append(_ground_y(Vector3(c.x, 0, c.y)) + dep - water_rel)
				if dep > water_rel + 0.005:
					wet = true
			if not wet:
				continue
			var b := verts.size()
			for k in 4:
				verts.append(Vector3(cs[k].x, ws[k], cs[k].y))
				norms.append(Vector3.UP)
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "DecoBogWater"
	mi.mesh = am
	var m := StandardMaterial3D.new()
	m.albedo_color = C_BOG_POOL
	# Pools follow the skirt slope: keep specular low so grazing views never go sky-pale.
	m.roughness = 0.6
	m.metallic_specular = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_gen.add_child(mi)


func _build_deco_bog_plants(p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var tools := {}
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var blade := BoxMesh.new()
	blade.size = Vector3.ONE
	var ext := float(p["extent"])
	var cx := float(p["cx"])
	var cz := float(p["cz"])
	var water_rel := float(p["water_rel"])
	var want_t := 18
	var want_r := 10
	var placed_t := 0
	var placed_r := 0
	var tries := 0
	while (placed_t < want_t or placed_r < want_r) and tries < 1200:
		tries += 1
		var pos := Vector3(cx + rng.randf_range(-ext, ext), 0.0, cz + rng.randf_range(-ext, ext))
		var msk := Terrain.deco_bog_mask_one(p, pos.x, pos.z)
		if msk < 0.08:
			continue
		var gy := _ground_y(pos)
		var depth := Terrain.deco_bog_depth_one(p, pos.x, pos.z)
		if depth > water_rel - 0.02:
			continue  # open water / pool
		var keep := 0.2 + 0.8 * msk
		if rng.randf() > keep:
			continue
		if placed_t < want_t and (placed_r >= want_r or rng.randf() < 0.6):
			var r := rng.randf_range(0.22, 0.48) * (0.6 + 0.4 * msk)
			var col: Color = C_TUSSOCK[rng.randi() % C_TUSSOCK.size()]
			var xf := Transform3D(
				Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(
					Vector3(r, r * rng.randf_range(0.45, 0.7), r * rng.randf_range(0.8, 1.2))),
				Vector3(pos.x, gy - r * 0.12, pos.z))
			_st_append(tools, col, sphere, xf)
			placed_t += 1
		elif placed_r < want_r and msk > 0.25:
			var blades := rng.randi_range(5, 9)
			for b in blades:
				var hh := rng.randf_range(0.4, 1.0)
				var off := Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))
				var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
				var base := Vector3(pos.x, gy - 0.05, pos.z) + off
				var xf := Transform3D(tilt.scaled(Vector3(0.03, hh, 0.03)), base + tilt * Vector3(0, hh * 0.5, 0))
				_st_append(tools, C_RUSH[rng.randi() % C_RUSH.size()], blade, xf)
			placed_r += 1
	# Bog cotton on the drier hummocks.
	for i in 8:
		var pos := Vector3(cx + rng.randf_range(-ext, ext), 0.0, cz + rng.randf_range(-ext, ext))
		if Terrain.deco_bog_mask_one(p, pos.x, pos.z) < 0.45:
			continue
		if Terrain.deco_bog_depth_one(p, pos.x, pos.z) > water_rel - 0.04:
			continue
		var xf := Transform3D(Basis().scaled(Vector3.ONE * 0.07),
			Vector3(pos.x, _ground_y(pos) + rng.randf_range(0.2, 0.4), pos.z))
		_st_append(tools, C_STAKE_TOP, sphere, xf)
	for key in tools:
		var st: SurfaceTool = tools[key][0]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "DecoBogPlants"
		mi.mesh = st.commit()
		mi.material_override = _mat(tools[key][1])
		_gen.add_child(mi)
	print("OPENING_DECO_BOG cx=%.1f cz=%.1f tussocks=%d rush_clumps=%d" % [cx, cz, placed_t, placed_r])


func _back_gap_x() -> float:
	return _zone_box(bog_zone_path, Vector3(-25.0, 1.0, 242.0), Vector3(28.0, 2.0, 28.0)).get_center().x


func _build_edges() -> void:
	## Field boundaries are solid and follow the ground: each run is cut into short pieces that
	## sit on (and slightly into) the terrain, so they climb over the rolls they cross.
	# West ditch + bank: the farm edge beyond the early lane (cattle cannot climb the bank).
	_drape_rect(Vector3(-27.0, 0.0, 70.0), 2.6, 140.0, 0.0, 0.02, C_DITCH)
	_drape_wall(Vector3(-25.2, 0, 0.0), Vector3(-25.2, 0, 140.0), 0.9, 0.7, C_BANK)
	_drape_wall(Vector3(-28.8, 0, 0.0), Vector3(-28.8, 0, 140.0), 1.0, 0.9, C_HEDGE)
	# East hedge bank (field boundary) and south hedge behind the secluded pasture.
	_drape_wall(Vector3(42.0, 0, -20.0), Vector3(42.0, 0, 200.0), 1.6, 1.8, C_HEDGE)
	var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	var sz := pas.end.z + 3.0
	# South hedge behind the pasture, with the back-paddock gap; the paddock beyond is hedged on
	# its other three sides (holds the bog, screened from the lane by the south ridge).
	var gx := _back_gap_x()
	_drape_wall(Vector3(PADDOCK_X0, 0, sz), Vector3(gx - BACK_GAP_HALF, 0, sz), 1.6, 1.8, C_HEDGE)
	_drape_wall(Vector3(gx + BACK_GAP_HALF, 0, sz), Vector3(PADDOCK_X1, 0, sz), 1.6, 1.8, C_HEDGE)
	_drape_wall(Vector3(PADDOCK_X0, 0, sz), Vector3(PADDOCK_X0, 0, PADDOCK_Z1), 1.6, 1.8, C_HEDGE)
	_drape_wall(Vector3(PADDOCK_X1, 0, sz), Vector3(PADDOCK_X1, 0, PADDOCK_Z1), 1.6, 1.8, C_HEDGE)
	_drape_wall(Vector3(PADDOCK_X0, 0, PADDOCK_Z1), Vector3(PADDOCK_X1, 0, PADDOCK_Z1), 1.6, 1.8, C_HEDGE)
	# North hedge behind the farmstead.
	_drape_wall(Vector3(-35.0, 0, -22.0), Vector3(35.0, 0, -22.0), 1.4, 1.8, C_HEDGE)


func _build_ringfort(center: Vector3, radius: float) -> void:
	# Neighbours' ráth — solid earthen ring bank with a gap facing east, a few round houses,
	# all resting on the ground they stand on.
	var segs := 30
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		if dir.x > 0.93:
			continue  # east entrance
		var p := center + dir * radius
		_solid_box(_gen, _on_ground(p + Vector3(0, 1.0, 0)), Vector3(3.6, 2.2, 1.6), C_RATH_BANK, atan2(dir.x, dir.z))
		var palisade := _mesh_box(_gen, _on_ground(center + dir * (radius - 0.5) + Vector3(0, 2.7, 0)), Vector3(3.4, 1.4, 0.2), C_RAIL.darkened(0.15))
		palisade.rotation.y = atan2(dir.x, dir.z)
	for hut in [Vector3(-4, 0, -3), Vector3(5, 0, 2), Vector3(-3, 0, 6)]:
		var h: Vector3 = center + hut
		var hg := _on_ground(h)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = hg + Vector3(0, 1.1, 0)
		_gen.add_child(body)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 3.0
		cyl.height = 2.4
		cs.shape = cyl
		body.add_child(cs)
		_mesh_cyl(body, Vector3.ZERO, 3.0, 3.0, 2.4, C_HUT)
		_mesh_cyl(_gen, hg + Vector3(0, 3.3, 0), 0.1, 3.5, 2.2, C_THATCH)
	_label(_on_ground(center + Vector3(0, 7.0, 0)), "Neighbours' ráth (ringfort)", 46, Color(0.82, 0.86, 0.72))


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
		if Terrain.rath_radius(p.x, p.z) < Terrain.RATH_EXTENT + 3.0:
			continue  # farmstead ráth
		var bog := _zone_box(bog_zone_path, Vector3(-25.0, 1.0, 242.0), Vector3(28.0, 2.0, 28.0)).grow(1.0)
		var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0)).grow(1.0)
		if _in_xz(bog, p) or _in_xz(pas, p):
			continue
		if p.distance_to(Vector3(-78, 0, 42)) < 22.0:
			continue
		if _on_hill(p, 0.35):
			continue  # sit trees beside knolls, not through them
		var h := rng.randf_range(3.5, 6.0)
		var g := _on_ground(p)
		_mesh_cyl(_gen, g + Vector3(0, h * 0.4 - 0.1, 0), 0.22, 0.3, h * 0.8, C_TRUNK)
		var crown := _mesh_sphere(_gen, g + Vector3(0, h * 0.85 - 0.1, 0), rng.randf_range(1.6, 2.6), C_CANOPY.darkened(rng.randf_range(0.0, 0.15)))
		crown.scale = Vector3(1.0, 0.85, 1.0)
		placed += 1


func _build_labels(path: Array[Vector3]) -> void:
	_label(Vector3(-7.2, 6.4, 1.77 - HOUSE_R), "Home — the house", 40, Color(0.95, 0.9, 0.75))
	_label(Vector3(7.0, 4.6, -2.6), "Byre", 40, Color(0.95, 0.9, 0.75))
	var home := _zone_box(home_zone_path, Vector3(6.5, 1.2, 5.5), Vector3(9.0, 2.4, 8.0))
	_label(home.get_center() + Vector3(0, 2.0, 0), "Home pen\n(drive the herd in)", 34, Color(0.7, 0.92, 0.55))
	var pas := _zone_box(pasture_zone_path, Vector3(-25.0, 1.0, 192.0), Vector3(40.0, 2.0, 28.0))
	_label(_on_ground(Vector3(pas.get_center().x, 4.5, pas.get_center().z - 6.0)), "Secluded pasture", 46, Color(0.85, 0.95, 0.7))
	# No "Bog edge" sign: the natural patch (dip, peat, pools, rushes) reads on its own.
	_label(_on_ground(Vector3(-27.0, 2.4, 40.0)), "Ditch (farm edge)", 30, Color(0.7, 0.8, 0.6))
	if path.size() >= 2:
		_label(path[0] + Vector3(-3.8, 2.3, 0), "Lane to the pasture ↓", 32, Color(0.95, 0.88, 0.6))


# ---------------------------------------------------------------- helpers


func _hill_surface_y(p: Vector3) -> float:
	## Raised-ground height at xz from the shared terrain (0 on open field).
	return Terrain.height_at(p.x, p.z)


func _ground_y(p: Vector3) -> float:
	## Exact walk-surface height (same triangulation as the collider / terrain mesh).
	return Terrain.surface_y(p.x, p.z)


func _on_ground(p: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, _ground_y(p) + p.y + lift, p.z)


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
	## Wattle/post-and-rail fence run (blocks cattle + player). Cut into post-spaced pieces that
	## follow the ground: rails + collider pitch with the slope, posts stay plumb.
	var flat_a := Vector3(a.x, 0.0, a.z)
	var flat_b := Vector3(b.x, 0.0, b.z)
	var length := flat_a.distance_to(flat_b)
	if length < 0.2:
		return
	var n := maxi(1, int(ceil(length / DRAPE_STEP)))
	for k in n:
		_rail_piece(flat_a.lerp(flat_b, float(k) / float(n)), flat_a.lerp(flat_b, float(k + 1) / float(n)), k == n - 1)


func _rail_piece(a: Vector3, b: Vector3, last: bool) -> void:
	var length := a.distance_to(b)
	var ya := _ground_y(a) - 0.04
	var yb := _ground_y(b) - 0.04
	var ym := (ya + yb) * 0.5
	var mid := (a + b) * 0.5
	var yaw := atan2(b.x - a.x, b.z - a.z)
	var pitch := -atan2(yb - ya, length)
	var len3 := sqrt(length * length + (yb - ya) * (yb - ya))
	var body := StaticBody3D.new()
	body.name = "Rail"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(mid.x, ym, mid.z)
	body.rotation.y = yaw
	_gen.add_child(body)
	var tilt := Basis(Vector3.RIGHT, pitch)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, RAIL_HEIGHT, len3 + 0.05)
	cs.shape = bs
	cs.transform = Transform3D(tilt, tilt * Vector3(0, RAIL_HEIGHT * 0.5, 0))
	body.add_child(cs)
	for h in [0.32, 0.78]:
		var bar := _mesh_box(body, Vector3.ZERO, Vector3(0.1, 0.12, len3 + 0.05), C_RAIL)
		bar.transform = Transform3D(tilt, tilt * Vector3(0, h, 0))
	# Plumb posts at the piece start (and end on the last piece) standing on the ground.
	var ends := [0.0] if not last else [0.0, 1.0]
	for t in ends:
		var lz: float = (float(t) - 0.5) * length
		var gy: float = lerpf(ya, yb, float(t)) - ym
		_mesh_box(body, Vector3(0, gy + RAIL_HEIGHT * 0.5, lz), Vector3(0.16, RAIL_HEIGHT + 0.08, 0.16), C_RAIL.darkened(0.15))


func _drape_wall(a: Vector3, b: Vector3, width: float, height: float, color: Color) -> void:
	## Solid bank / hedge run along a→b on the ground. Visual: one continuous extruded mesh whose
	## base (sunk 0.15 m) and top follow the terrain every ~1 m (no saw-tooth joints).
	## Collision: short pitched boxes of the same width/height (vertical side faces), so the
	## run blocks exactly where it is drawn.
	var flat_a := Vector3(a.x, 0.0, a.z)
	var flat_b := Vector3(b.x, 0.0, b.z)
	var length := flat_a.distance_to(flat_b)
	if length < 0.2:
		return
	var sink := 0.15
	var n := maxi(1, int(ceil(length / DRAPE_STEP)))
	for k in n:
		var pa := flat_a.lerp(flat_b, float(k) / float(n))
		var pb := flat_a.lerp(flat_b, float(k + 1) / float(n))
		var seg := pa.distance_to(pb)
		var ya := _ground_y(pa)
		var yb := _ground_y(pb)
		var mid := (pa + pb) * 0.5
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(mid.x, (ya + yb) * 0.5, mid.z)
		body.rotation = Vector3(-atan2(yb - ya, seg), atan2(pb.x - pa.x, pb.z - pa.z), 0.0)
		_gen.add_child(body)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(width, height + sink, sqrt(seg * seg + (yb - ya) * (yb - ya)) + 0.05)
		cs.shape = bs
		cs.position = Vector3(0, (height + sink) * 0.5 - sink, 0)
		body.add_child(cs)
	_wall_mesh(flat_a, flat_b, width, height, sink, color)


func _wall_mesh(a: Vector3, b: Vector3, width: float, height: float, sink: float, color: Color) -> void:
	var dir := (b - a).normalized()
	var side := Vector3(dir.z, 0.0, -dir.x) * (width * 0.5)
	var n := maxi(1, int(ceil(a.distance_to(b) / 1.0)))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var pts: Array[Vector3] = []
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		p.y = _ground_y(p)
		pts.append(p)
	# Faces: +side, -side, top. Each face gets its own verts (crisp box edges).
	for face in 3:
		var base := verts.size()
		for i in n + 1:
			var p := pts[i]
			var lo := p + Vector3(0, -sink, 0)
			var hi := p + Vector3(0, height, 0)
			match face:
				0:
					verts.append(lo + side)
					verts.append(hi + side)
					norms.append(side.normalized())
					norms.append(side.normalized())
				1:
					verts.append(lo - side)
					verts.append(hi - side)
					norms.append(-side.normalized())
					norms.append(-side.normalized())
				2:
					verts.append(hi - side)
					verts.append(hi + side)
					var up := Vector3.UP
					if i < n:
						var t := pts[i + 1] - pts[i]
						up = t.cross(side).normalized()
						if up.y < 0.0:
							up = -up
					norms.append(up)
					norms.append(up)
		for i in n:
			var v0 := base + i * 2
			var v1 := v0 + 1
			var v2 := v0 + 2
			var v3 := v0 + 3
			if face == 0:
				idx.append_array([v0, v2, v1, v1, v2, v3])  # +side wall faces outward (clockwise)
			else:
				idx.append_array([v0, v1, v2, v1, v3, v2])
	# End caps.
	for e in 2:
		var p := pts[0] if e == 0 else pts[n]
		var base := verts.size()
		var nn := -dir if e == 0 else dir
		for v in [p + Vector3(0, -sink, 0) - side, p + Vector3(0, -sink, 0) + side, p + Vector3(0, height, 0) + side, p + Vector3(0, height, 0) - side]:
			verts.append(v)
			norms.append(nn)
		if e == 0:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		else:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mat(color)
	_gen.add_child(mi)


func _drape_rect(center: Vector3, size_x: float, size_z: float, yaw: float, lift: float, color: Color) -> MeshInstance3D:
	## Thin ground overlay (lane / bog / ditch) as a subdivided sheet lifted `lift` m above the
	## terrain at every vertex, so it follows the surface instead of hiding under the hills.
	var nx := maxi(1, int(ceil(size_x / 1.0)))
	var nz := maxi(1, int(ceil(size_z / 1.0)))
	var basis := Basis(Vector3.UP, yaw)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for iz in nz + 1:
		for ix in nx + 1:
			var local := Vector3((float(ix) / float(nx) - 0.5) * size_x, 0.0, (float(iz) / float(nz) - 0.5) * size_z)
			var wp := center + basis * local
			wp.y = _ground_y(wp) + lift
			verts.append(wp)
			norms.append(Terrain.normal_at(wp.x, wp.z))
	var idx := PackedInt32Array()
	for iz in nz:
		for ix in nx:
			var p00 := iz * (nx + 1) + ix
			var p10 := p00 + 1
			var p01 := p00 + nx + 1
			var p11 := p01 + 1
			idx.append_array([p00, p10, p01, p10, p11, p01])
	return _sheet(verts, norms, idx, color)


func _drape_disc(center: Vector3, rx: float, rz: float, lift: float, color: Color) -> MeshInstance3D:
	## Elliptical ground overlay (lane joints, bog pools) draped like _drape_rect.
	var segs := 16
	var rings := 2
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var c := Vector3(center.x, _ground_y(center) + lift, center.z)
	verts.append(c)
	norms.append(Terrain.normal_at(c.x, c.z))
	for r in range(1, rings + 1):
		var f := float(r) / float(rings)
		for i in segs:
			var ang := TAU * float(i) / float(segs)
			var wp := Vector3(center.x + cos(ang) * rx * f, 0.0, center.z + sin(ang) * rz * f)
			wp.y = _ground_y(wp) + lift
			verts.append(wp)
			norms.append(Terrain.normal_at(wp.x, wp.z))
	var idx := PackedInt32Array()
	for i in segs:
		var j := (i + 1) % segs
		idx.append_array([0, 1 + i, 1 + j])  # clockwise from above = front
	for r in range(1, rings):
		var o0 := 1 + (r - 1) * segs
		var o1 := 1 + r * segs
		for i in segs:
			var j := (i + 1) % segs
			idx.append_array([o0 + i, o1 + i, o0 + j, o0 + j, o1 + i, o1 + j])
	return _sheet(verts, norms, idx, color)


func _sheet(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, color: Color) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gen.add_child(mi)
	return mi


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
