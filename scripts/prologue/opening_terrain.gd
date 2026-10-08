@tool
extends RefCounted
class_name OpeningTerrain
## One shared height function for the opening cattle-drive landscape.
##
## Every rolling hill, pasture berm / bank and far swell is an ellipsoid cap (sphere sunk below
## grade, then squashed — the same shape the old visual-only sphere meshes had), unioned with a
## soft fillet so toes blend into the field instead of creasing. The greybox samples this ONE
## function onto a regular grid and builds both the visible terrain mesh and the
## HeightMapShape3D collider from the very same samples (same triangulation), so the surface the
## player / cattle stand on is the surface you see. NPCs that are not physics bodies (stray dog,
## props, labels) call surface_y() to rest on the same ground.

## Fillet width (m) of the smooth union between caps and the flat field. Keeps the steepest
## toe (pasture side banks) under ~42° so CharacterBody3D floors stay walkable.
const FILLET := 0.8
## Heightfield sample spacing (m). Collider + visual share it.
const STEP := 1.0
## Heightfield window (world XZ). Covers every cap; outside it the field is flat (y = 0).
const MIN_X := -180.0
const MIN_Z := -80.0
const SIZE_X := 330  # cells
const SIZE_Z := 340  # cells

const C_GRASS := Color(0.36, 0.47, 0.27)
const C_BANK := Color(0.3, 0.38, 0.22)
const C_HEDGE := Color(0.2, 0.33, 0.17)

## --- Back-paddock bog: an organic patch with a shallow dip, applied AFTER the cap union (so it
## sinks whatever ground it sits on). Outline = mean radius with a few fixed harmonics plus a
## low-frequency noise wobble; everything (dip, hummocks, colour blend, stuck test) keys off the
## one signed edge distance bog_edge(), so the collider, mesh, paint and gameplay agree.
const BOG_CX := -25.0
const BOG_CZ := 242.0
const BOG_R := 8.6           # mean outline radius (m)
const BOG_EXTENT := 14.0     # nothing bog-related beyond this radius (outline max ≈ 12.2)
const BOG_BLEND := 2.2       # soft colour/mask band inside the outline (m)
const BOG_FEATHER := 0.6     # ... and how far it feathers out past it (m)
const BOG_DIP := 0.45        # depth of the dip at its floor (m)
const BOG_HUMMOCK := 0.2     # hummock relief inside the dip (± m)
## Standing water level (absolute y): pools show wherever the dip floor drops below it.
const BOG_WATER_Y := -0.53

static var _bog_noise: FastNoiseLite = null
static var _deco_noises: Dictionary = {}  # seed → FastNoiseLite
static var _caps: Array = []  # [{cx, cz, rx, rz, ry, sink, color, kind, name}]
static var _mouth_x: float = -28.0
static var _heights: PackedFloat32Array = PackedFloat32Array()
static var _baked_for: float = NAN

## Decorative west-of-lane bog patches (organic outline + shallow dip + paint). Visual only —
## no stuck/slow logic. Sizes match the old flat squares; shallower dip than the main bog.
## Keys: cx, cz, r, extent, blend, feather, dip, hummock, ease, seed, phase, water_rel (pool
## surface this far below the undipped ground — only hollows deeper than it flood).
const DECO_BOGS: Array = [
	{  # nearer patch, west of Bend5 (was 14×10 square at (-10, 100))
		"cx": -14.0, "cz": 102.0, "r": 5.6, "extent": 9.0,
		"blend": 1.6, "feather": 0.5, "dip": 0.30, "hummock": 0.14, "ease": 2.5,
		"seed": 5521, "phase": 1.3, "water_rel": 0.33,
	},
	{  # farther patch, west of Bend8 (was 18×14 square at (-55, 160))
		"cx": -55.0, "cz": 160.0, "r": 7.2, "extent": 11.5,
		"blend": 1.8, "feather": 0.55, "dip": 0.32, "hummock": 0.14, "ease": 2.7,
		"seed": 7733, "phase": 4.1, "water_rel": 0.38,
	},
]


## Rebuild cap list (PastureMouth x moves the mouth berms). Invalidates the baked grid.
static func configure(mouth_x: float) -> void:
	if not is_nan(_baked_for) and is_equal_approx(_baked_for, mouth_x) and not _caps.is_empty():
		return
	_mouth_x = mouth_x
	_caps.clear()
	_heights = PackedFloat32Array()
	_baked_for = NAN
	_define_caps()


static func _ensure() -> void:
	if _caps.is_empty():
		_define_caps()


static func _define_caps() -> void:
	# --- Rolling hills (same centres / radii / squash as the 1ac8fa5 gradual-hills layout).
	# Near west/east rolls — wide low skirts; saddle ~x 0–12 at z≈70–95 (Bend4→Bend5).
	_hill("west_roll_near", Vector3(-50.0, 0.0, 72.0), 32.0, Vector3(1.4, 0.30, 1.6), C_BANK.lightened(0.08))
	_hill("east_roll_near", Vector3(46.0, 0.0, 100.0), 30.0, Vector3(1.4, 0.28, 1.45), C_GRASS.darkened(0.06))
	# West-of-lane continuous roll (two overlapping soft rises) — LOS screen house↔pasture.
	_hill("west_roll_a", Vector3(-38.0, 0.0, 112.0), 30.0, Vector3(1.4, 0.38, 1.55), C_HEDGE)
	_hill("west_roll_b", Vector3(-50.0, 0.0, 118.0), 28.0, Vector3(1.3, 0.32, 1.5), C_BANK)
	# Mid west/east rolls — saddle ~x 4–12 at z≈118–145 (Bend6→Bend7).
	_hill("west_roll_mid", Vector3(-48.0, 0.0, 144.0), 30.0, Vector3(1.4, 0.32, 1.55), C_GRASS.darkened(0.05))
	_hill("east_roll_mid", Vector3(46.0, 0.0, 134.0), 30.0, Vector3(1.35, 0.28, 1.4), C_BANK.lightened(0.05))
	_hill("west_roll_mid_b", Vector3(-38.0, 0.0, 136.0), 28.0, Vector3(1.4, 0.38, 1.5), C_HEDGE.lightened(0.04))
	# Far west roll (west of Bend8).
	_hill("west_roll_far", Vector3(-48.0, 0.0, 156.0), 24.0, Vector3(1.4, 0.34, 1.4), C_HEDGE)
	_hill("west_roll_far_b", Vector3(-58.0, 0.0, 148.0), 22.0, Vector3(1.25, 0.30, 1.3), C_BANK)
	# Pasture flanks — broad soft rises tucking the hollow.
	_hill("pasture_flank_e", Vector3(28.0, 0.0, 186.0), 28.0, Vector3(1.35, 0.30, 1.4), C_BANK)
	_hill("pasture_flank_w", Vector3(-62.0, 0.0, 192.0), 28.0, Vector3(1.3, 0.28, 1.35), C_GRASS.darkened(0.04))
	# Pasture mouth berms — wide low lips with a walkable gap at PastureMouth.
	var gap := 6.5
	var west_end := _mouth_x - gap
	var east_start := _mouth_x + gap
	_hill("mouth_berm_w_far", Vector3(-50.0, 0.0, 176.5), 14.0, Vector3(1.45, 0.38, 0.9), C_BANK)
	_hill("mouth_berm_w", Vector3(west_end - 9.0, 0.0, 177.0), 12.0, Vector3(1.3, 0.36, 0.85), C_BANK.lightened(0.05))
	_hill("mouth_berm_e", Vector3(east_start + 10.0, 0.0, 176.5), 13.0, Vector3(1.35, 0.38, 0.9), C_BANK)
	_hill("mouth_berm_e_far", Vector3(-4.0, 0.0, 177.5), 13.0, Vector3(1.3, 0.34, 0.85), C_HEDGE.lightened(0.08))
	# Pasture side banks — long low N–S hedge-bank berms.
	_hill("pasture_bank_e", Vector3(-8.0, 0.0, 191.0), 16.0, Vector3(0.5, 0.40, 2.0), C_HEDGE)
	_hill("pasture_bank_w", Vector3(-42.0, 0.0, 191.0), 16.0, Vector3(0.5, 0.40, 2.0), C_HEDGE)
	# South ridge behind the pasture — screens the back paddock (and its bog) from the lane and
	# the pasture mouth. Raised-cosine profile: crest 4.5 m, flanks ≤ ~33° (walkable for cattle,
	# floor_max_angle 47°); the back-paddock gap in the pasture's south rail sits at its north toe.
	_ridge("pasture_south_ridge", Vector3(-25.0, 0.0, 219.0), 16.0, 14.0, 13.0, 4.5, C_BANK.lightened(0.04))
	# --- Far farmland swells (old _build_ground sphere swells: r 34, centre 6 m below, squash).
	for s in [Vector3(80, 0, 10), Vector3(-60, 0, 130), Vector3(90, 0, 150), Vector3(-120, 0, -30), Vector3(70, 0, 210)]:
		_caps.append({
			"name": "swell_%d_%d" % [int(s.x), int(s.z)], "kind": "swell",
			"cx": s.x, "cz": s.z, "rx": 34.0 * 1.6, "rz": 34.0 * 1.2, "ry": 34.0 * 0.28,
			"sink": 6.0, "color": C_GRASS.darkened(0.04),
		})


static func _hill(nm: String, c: Vector3, r: float, scl: Vector3, color: Color) -> void:
	# Old visual: sphere radius r sunk by r*scl.y*0.55, scaled by scl → crest ≈ r*scl.y*0.45.
	_caps.append({
		"name": nm, "kind": "hill", "cx": c.x, "cz": c.z,
		"rx": r * scl.x, "rz": r * scl.z, "ry": r * scl.y, "sink": r * scl.y * 0.55, "color": color,
	})


## Long bank with a flat-topped crest: |x - cx| <= half_len is full height, then a raised-cosine
## fall over `fall` m; across (z) a raised-cosine profile of half-width rz. Offset by -FILLET so the
## soft union meets the flat field with no step at the cap's edge.
static func _ridge(nm: String, c: Vector3, half_len: float, fall: float, rz: float, crest: float, color: Color) -> void:
	_caps.append({
		"name": nm, "kind": "ridge", "cx": c.x, "cz": c.z,
		"rx": half_len + fall, "rz": rz, "ry": crest, "sink": 0.0, "color": color,
		"half_len": half_len, "fall": fall,
	})


static func caps() -> Array:
	_ensure()
	return _caps


## Signed cap height (negative = below grade) at xz for one cap.
static func cap_value(cap: Dictionary, x: float, z: float) -> float:
	if String(cap["kind"]) == "ridge":
		var uz := absf(z - float(cap["cz"])) / float(cap["rz"])
		var ux := maxf(0.0, absf(x - float(cap["cx"])) - float(cap["half_len"])) / float(cap["fall"])
		if uz >= 1.0 or ux >= 1.0:
			return -FILLET - 1.0
		var k := (1.0 + cos(PI * uz)) * 0.5 * (1.0 + cos(PI * ux)) * 0.5
		return (float(cap["ry"]) + FILLET) * k - FILLET
	var dx: float = (x - float(cap["cx"])) / float(cap["rx"])
	var dz: float = (z - float(cap["cz"])) / float(cap["rz"])
	var rem := 1.0 - dx * dx - dz * dz
	return -float(cap["sink"]) + float(cap["ry"]) * sqrt(maxf(rem, 0.0))


static func _smax(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0)
	return maxf(a, b) + h * h / (4.0 * k)


## Analytic surface height (m above the flat field) at world xz.
static func height_at(x: float, z: float) -> float:
	_ensure()
	var acc := 0.0
	for cap in _caps:
		var f := cap_value(cap, x, z)
		if f > acc - FILLET:
			acc = _smax(acc, f, FILLET)
	return acc - bog_depth(x, z) - deco_bog_depth(x, z)


# ---------------------------------------------------------------- bog patch

static func _bnoise() -> FastNoiseLite:
	if _bog_noise == null:
		_bog_noise = FastNoiseLite.new()
		_bog_noise.seed = 7137
		_bog_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_bog_noise.frequency = 0.16
		_bog_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_bog_noise.fractal_octaves = 2
	return _bog_noise


## Signed distance-ish (m) from xz to the bog outline: + inside, − outside.
static func bog_edge(x: float, z: float) -> float:
	var dx := x - BOG_CX
	var dz := z - BOG_CZ
	var d := sqrt(dx * dx + dz * dz)
	if d > BOG_EXTENT:
		return -(d - BOG_EXTENT) - 2.0
	var a := atan2(dz, dx)
	var r := BOG_R * (1.0 + 0.17 * sin(3.0 * a + 0.6) + 0.10 * sin(5.0 * a + 2.4) + 0.05 * sin(9.0 * a + 1.1))
	r += 1.1 * _bnoise().get_noise_2d(x, z)
	return r - d


## 0 on firm grass → 1 inside the bog, soft across the edge (colour blend + stuck test).
static func bog_mask(x: float, z: float) -> float:
	return smoothstep(-BOG_FEATHER, BOG_BLEND, bog_edge(x, z))


## The bog's slow/stuck zone follows the same outline (mask ≥ 0.5 ≈ 0.8 m inside the edge).
static func in_bog(p: Vector3) -> bool:
	return bog_mask(p.x, p.z) >= 0.5


## How far the ground drops at xz (0 outside): a shallow bowl easing in from the feathered edge
## to BOG_DIP ~3.5 m in, with hummocks (tussock mounds / pool hollows) on the floor.
static func bog_depth(x: float, z: float) -> float:
	var dx := x - BOG_CX
	var dz := z - BOG_CZ
	if dx * dx + dz * dz > BOG_EXTENT * BOG_EXTENT:
		return 0.0
	var e := bog_edge(x, z)
	if e <= -BOG_FEATHER:
		return 0.0
	var prof := smoothstep(-BOG_FEATHER, 3.5, e)
	var hum := BOG_HUMMOCK * _bnoise().get_noise_2d(x * 1.25 + 40.0, z * 1.25 - 17.0) * 1.8
	return prof * (BOG_DIP - hum)


# ---------------------------------------------------------------- decorative west bog patches

static func deco_bogs() -> Array:
	return DECO_BOGS


static func _deco_noise(seed_val: int) -> FastNoiseLite:
	if not _deco_noises.has(seed_val):
		var n := FastNoiseLite.new()
		n.seed = seed_val
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.18
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		_deco_noises[seed_val] = n
	return _deco_noises[seed_val]


## Signed edge distance for decorative patch `p`: + inside, − outside.
static func deco_bog_edge(p: Dictionary, x: float, z: float) -> float:
	var dx := x - float(p["cx"])
	var dz := z - float(p["cz"])
	var d := sqrt(dx * dx + dz * dz)
	var extent := float(p["extent"])
	if d > extent:
		return -(d - extent) - 2.0
	var a := atan2(dz, dx)
	var phase := float(p["phase"])
	var r := float(p["r"]) * (1.0 + 0.17 * sin(3.0 * a + 0.6 + phase)
		+ 0.10 * sin(5.0 * a + 2.4 + phase * 0.7)
		+ 0.05 * sin(9.0 * a + 1.1 + phase * 1.3))
	r += 1.0 * _deco_noise(int(p["seed"])).get_noise_2d(x, z)
	return r - d


static func deco_bog_mask_one(p: Dictionary, x: float, z: float) -> float:
	return smoothstep(-float(p["feather"]), float(p["blend"]), deco_bog_edge(p, x, z))


## Soft mask across every decorative patch (for vertex-colour blend). Max of individuals.
static func deco_bog_mask(x: float, z: float) -> float:
	var best := 0.0
	for p in DECO_BOGS:
		var dx := x - float(p["cx"])
		var dz := z - float(p["cz"])
		if dx * dx + dz * dz > float(p["extent"]) * float(p["extent"]):
			continue
		best = maxf(best, deco_bog_mask_one(p, x, z))
	return best


static func deco_bog_depth_one(p: Dictionary, x: float, z: float) -> float:
	var dx := x - float(p["cx"])
	var dz := z - float(p["cz"])
	var extent := float(p["extent"])
	if dx * dx + dz * dz > extent * extent:
		return 0.0
	var e := deco_bog_edge(p, x, z)
	if e <= -float(p["feather"]):
		return 0.0
	var prof := smoothstep(-float(p["feather"]), float(p["ease"]), e)
	var hum := float(p["hummock"]) * _deco_noise(int(p["seed"])).get_noise_2d(
		x * 1.25 + 40.0, z * 1.25 - 17.0) * 1.8
	return prof * (float(p["dip"]) - hum)


## Sum of decorative dips at xz (0 outside every patch).
static func deco_bog_depth(x: float, z: float) -> float:
	var acc := 0.0
	for p in DECO_BOGS:
		acc += deco_bog_depth_one(p, x, z)
	return acc


## Index of the cap that dominates xz (highest signed value), or -1 on open field.
static func dominant_cap(x: float, z: float) -> int:
	_ensure()
	var best := -INF
	var idx := -1
	for i in _caps.size():
		var f := cap_value(_caps[i], x, z)
		if f > best:
			best = f
			idx = i
	return idx if best > -FILLET else -1


# ---------------------------------------------------------------- baked grid (collider == mesh)

## Bake the grid once (idempotent). Sample (ix, iz) is at world (MIN_X + ix*STEP, MIN_Z + iz*STEP).
static func bake() -> PackedFloat32Array:
	_ensure()
	if _heights.size() == (SIZE_X + 1) * (SIZE_Z + 1) and is_equal_approx(_baked_for, _mouth_x):
		return _heights
	var w := SIZE_X + 1
	var d := SIZE_Z + 1
	var hs := PackedFloat32Array()
	hs.resize(w * d)
	hs.fill(0.0)
	# Each cap only touches its own ellipse bbox (outside it the cap is ≤ -sink < -FILLET).
	for cap in _caps:
		var x0 := maxi(0, int(floor((float(cap["cx"]) - float(cap["rx"]) - MIN_X) / STEP)))
		var x1 := mini(w - 1, int(ceil((float(cap["cx"]) + float(cap["rx"]) - MIN_X) / STEP)))
		var z0 := maxi(0, int(floor((float(cap["cz"]) - float(cap["rz"]) - MIN_Z) / STEP)))
		var z1 := mini(d - 1, int(ceil((float(cap["cz"]) + float(cap["rz"]) - MIN_Z) / STEP)))
		for iz in range(z0, z1 + 1):
			var z := MIN_Z + float(iz) * STEP
			var row := iz * w
			for ix in range(x0, x1 + 1):
				var f := cap_value(cap, MIN_X + float(ix) * STEP, z)
				var a := hs[row + ix]
				if f > a - FILLET:
					hs[row + ix] = _smax(a, f, FILLET)
	# Bog dip, after the union (same order as height_at).
	var bx0 := maxi(0, int(floor((BOG_CX - BOG_EXTENT - MIN_X) / STEP)))
	var bx1 := mini(w - 1, int(ceil((BOG_CX + BOG_EXTENT - MIN_X) / STEP)))
	var bz0 := maxi(0, int(floor((BOG_CZ - BOG_EXTENT - MIN_Z) / STEP)))
	var bz1 := mini(d - 1, int(ceil((BOG_CZ + BOG_EXTENT - MIN_Z) / STEP)))
	for iz in range(bz0, bz1 + 1):
		var z := MIN_Z + float(iz) * STEP
		for ix in range(bx0, bx1 + 1):
			hs[iz * w + ix] -= bog_depth(MIN_X + float(ix) * STEP, z)
	# Decorative west-of-lane bog dips (same order as height_at).
	for p in DECO_BOGS:
		var ex := float(p["extent"])
		var dx0 := maxi(0, int(floor((float(p["cx"]) - ex - MIN_X) / STEP)))
		var dx1 := mini(w - 1, int(ceil((float(p["cx"]) + ex - MIN_X) / STEP)))
		var dz0 := maxi(0, int(floor((float(p["cz"]) - ex - MIN_Z) / STEP)))
		var dz1 := mini(d - 1, int(ceil((float(p["cz"]) + ex - MIN_Z) / STEP)))
		for iz in range(dz0, dz1 + 1):
			var z := MIN_Z + float(iz) * STEP
			for ix in range(dx0, dx1 + 1):
				hs[iz * w + ix] -= deco_bog_depth_one(p, MIN_X + float(ix) * STEP, z)
	_heights = hs
	_baked_for = _mouth_x
	return _heights


static func grid_width() -> int:
	return SIZE_X + 1


static func grid_depth() -> int:
	return SIZE_Z + 1


static func sample(ix: int, iz: int) -> float:
	var w := SIZE_X + 1
	ix = clampi(ix, 0, SIZE_X)
	iz = clampi(iz, 0, SIZE_Z)
	return bake()[iz * w + ix]


## Surface height exactly as the HeightMapShape3D / terrain mesh triangulate it:
## each cell splits on the (x+1,z)–(x,z+1) diagonal.
static func surface_y(x: float, z: float) -> float:
	var gx := (x - MIN_X) / STEP
	var gz := (z - MIN_Z) / STEP
	if gx < 0.0 or gz < 0.0 or gx > float(SIZE_X) or gz > float(SIZE_Z):
		return 0.0
	var ix := mini(int(floor(gx)), SIZE_X - 1)
	var iz := mini(int(floor(gz)), SIZE_Z - 1)
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var h00 := sample(ix, iz)
	var h10 := sample(ix + 1, iz)
	var h01 := sample(ix, iz + 1)
	var h11 := sample(ix + 1, iz + 1)
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


static func surface_point(p: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, surface_y(p.x, p.z) + lift, p.z)


## Smooth surface normal (central differences on the analytic function).
static func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Slope (degrees) of the smooth surface at xz.
static func slope_deg(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).dot(Vector3.UP), -1.0, 1.0)))
