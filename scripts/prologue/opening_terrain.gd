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

static var _caps: Array = []  # [{cx, cz, rx, rz, ry, sink, color, kind, name}]
static var _mouth_x: float = -28.0
static var _heights: PackedFloat32Array = PackedFloat32Array()
static var _baked_for: float = NAN


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


static func caps() -> Array:
	_ensure()
	return _caps


## Signed cap height (negative = below grade) at xz for one cap.
static func cap_value(cap: Dictionary, x: float, z: float) -> float:
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
