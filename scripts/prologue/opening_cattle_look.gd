extends RefCounted
## Shared look for the opening's small native cattle (Kerry / Dexter-like): used by the herd
## cows (opening_cow.gd, on the raid-cow body/head nodes) and the knife-hitch heifer prop.
## Visual only. Everything is placed in the animal's local frame (head toward −Z, ground y 0,
## legs at x ±LEG_X, z ±LEG_Z, hips LEG_LEN up); parts parented under the non-uniformly scaled
## body / head meshes are counter-transformed so they keep their own shape.
##
## Proportions (H5 fix 3, Dexter / Kerry): withers ≈ 1.07 m on 0.6 m legs (≈ 0.55 m of clear
## leg under the belly); a long, flat-backed trunk (1.75 m × 0.62 m wide × 0.5 m deep, back
## 1.05 m, belly 0.55 m); nose to rump ≈ 2.3 m. Over that: a low withers with a slight dip
## behind it and a level, square rump, shoulders and thighs, a brisket hanging between the
## forelegs, a
## thick neck, and a long tapered face (broad poll → narrow muzzle, with a jaw line) carried
## nose-down. Ears stand out sideways just below the horn roots; short pale horns run out and
## then turn up with dark tips (polled beasts get none); the tail hangs from the tailhead to a
## dark switch.

const C_HORN := Color(0.86, 0.8, 0.64)
const C_HORN_TIP := Color(0.16, 0.13, 0.1)
const C_MUZZLE := Color(0.22, 0.19, 0.17)
## Black coats (H5 fix 2): a mealy, lighter muzzle and a subtly browner face so the head's
## wedge reads against the dark body at walk-up / herd distance.
const C_MUZZLE_MEALY := Color(0.42, 0.35, 0.27)
const C_NOSE_PAD := Color(0.1, 0.085, 0.08)
const DARK_FACE_TINT := Color(0.34, 0.25, 0.17)
const DARK_FACE_LIFT := 0.32
const DARK_LUMA := 0.12

## Face axis: from the poll down and forward to the muzzle (≈ 40° nose-down).
const FACE_DIR := Vector3(0.0, -0.57, -0.82)
const POLL := Vector3(0.0, 0.98, -1.06)
const FACE_LEN := 0.49


## Trunk: a capsule laid along Z (own mesh), centre height and half-length.
const BODY_Y := 0.8
const BODY_HALF_LEN := 0.875
## Legs: hip spacing and length (hip at LEG_LEN, inside the belly; hoof on the ground). The leg
## mesh is LEG_MESH_H tall (the gait rig's hoof sits at −LEG_MESH_H/2 in mesh space) and is
## stretched to LEG_LEN by its rest basis.
const LEG_X := 0.19
const LEG_Z := 0.6
const LEG_LEN := 0.6
const LEG_MESH_H := 0.34


## True for the black coats (and their state tints).
static func is_dark(coat: Color) -> bool:
	return coat.get_luminance() < DARK_LUMA


## Face (head mesh) tone for a coat: unchanged on red coats, lifted toward brown on black ones.
static func face_tone(coat: Color) -> Color:
	return coat.lerp(DARK_FACE_TINT, DARK_FACE_LIFT) if is_dark(coat) else coat


## Rest transform for a leg at hip (sx, sz) signs: plumb, mesh stretched to LEG_LEN.
static func leg_rest(sx: float, sz: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(1.0, LEG_LEN / LEG_MESH_H, 1.0)), Vector3(sx * LEG_X, LEG_LEN * 0.5, sz * LEG_Z))


## Slim, slightly tapered cannon-and-forearm leg (mesh space: LEG_MESH_H tall).
static func leg_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.068
	m.bottom_radius = 0.047
	m.height = LEG_MESH_H
	m.radial_segments = 8
	m.rings = 1
	return m


## Dress `body` (any MeshInstance3D; its mesh is replaced by the trunk capsule) and `head` (its
## mesh is replaced by the face) in the cattle look. `mat` maps a Color to a Material. Returns
## the parts that should share the body's (state-tinted) material.
static func dress(body: MeshInstance3D, head: MeshInstance3D, coat: Color, horned: bool, mat: Callable) -> Array:
	var coat_parts: Array = []
	var sph := _sphere()
	var dark := is_dark(coat)
	var face := face_tone(coat)
	if body:
		var cap := CapsuleMesh.new()
		cap.radius = 0.25
		cap.height = BODY_HALF_LEN * 2.0
		cap.radial_segments = 16
		cap.rings = 6
		body.mesh = cap
		# Capsule axis (local Y) along Z; 1.24 wide on X → 0.62 m wide, 0.5 m deep.
		body.transform = Transform3D(Basis(Vector3(1.24, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, BODY_Y, 0.0))
		body.set_surface_override_material(0, mat.call(coat))
		# Low withers, a slight dip behind, a level square rump with pins / tailhead.
		coat_parts.append(_attach(body, Vector3(0, 1.0, -0.52), Basis.from_scale(Vector3(0.22, 0.075, 0.26)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 1.0, 0.5), Basis.from_scale(Vector3(0.29, 0.07, 0.3)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 1.01, 0.78), Basis.from_scale(Vector3(0.22, 0.055, 0.12)), sph, coat, mat))
		# Shoulders and thighs over the leg tops.
		for sx in [-1.0, 1.0]:
			coat_parts.append(_attach(body, Vector3(sx * 0.15, 0.8, -0.56), Basis.from_scale(Vector3(0.15, 0.23, 0.2)), sph, coat, mat))
			coat_parts.append(_attach(body, Vector3(sx * 0.15, 0.76, 0.6), Basis.from_scale(Vector3(0.15, 0.24, 0.22)), sph, coat, mat))
		# Brisket and dewlap hanging between the forelegs; a little belly depth mid-trunk.
		coat_parts.append(_attach(body, Vector3(0, 0.62, -0.7), Basis.from_scale(Vector3(0.21, 0.2, 0.2)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 0.52, -0.84), Basis.from_scale(Vector3(0.1, 0.14, 0.1)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 0.6, -0.05), Basis.from_scale(Vector3(0.27, 0.09, 0.45)), sph, coat, mat))
		# Tail: from the tailhead down the buttocks to a dark switch at the hocks.
		var top := Vector3(0, 1.0, 0.86)
		var bot := Vector3(0, 0.42, 0.95)
		var ax := (bot - top)
		var tb := _axis_basis(ax.normalized())
		coat_parts.append(_attach(body, (top + bot) * 0.5, tb * Basis.from_scale(Vector3(0.028, ax.length(), 0.028)), _cyl(1.0, 1.0), coat, mat))
		_attach(body, bot + Vector3(0, -0.06, 0.005), Basis.from_scale(Vector3(0.055, 0.12, 0.055)), sph, coat.darkened(0.45), mat)
	if head:
		# Tapered face: a cone frustum along FACE_DIR, broad at the poll, narrow at the muzzle.
		var fm := CylinderMesh.new()
		fm.top_radius = 0.075
		fm.bottom_radius = 0.135
		fm.height = 1.0
		fm.radial_segments = 10
		fm.rings = 1
		head.mesh = fm
		var fb := _axis_basis(FACE_DIR) * Basis.from_scale(Vector3(1.0, FACE_LEN, 0.82))
		head.transform = Transform3D(fb, POLL + FACE_DIR * (FACE_LEN * 0.5))
		head.set_surface_override_material(0, mat.call(face))
		var tip := POLL + FACE_DIR * FACE_LEN
		# Thick neck from the withers down into the poll.
		coat_parts.append(_attach(head, Vector3(0, 0.93, -0.86), Basis(Vector3.RIGHT, 0.45) * Basis.from_scale(Vector3(0.17, 0.21, 0.27)), sph, coat, mat))
		# Broad forehead / poll and cheeks.
		coat_parts.append(_attach(head, POLL + Vector3(0, -0.02, -0.02), Basis.from_scale(Vector3(0.16, 0.11, 0.13)), sph, coat, mat))
		_attach(head, POLL + FACE_DIR * 0.2 + Vector3(0, -0.03, 0.04), Basis.from_scale(Vector3(0.13, 0.11, 0.12)), sph, face, mat)
		# Jaw line under the face, and the muzzle (greyer) with two nostrils at the tip.
		coat_parts.append(_attach(head, POLL + FACE_DIR * 0.3 + Vector3(0, -0.08, 0.06), Basis(Vector3.RIGHT, -0.65) * Basis.from_scale(Vector3(0.075, 0.06, 0.17)), sph, coat, mat))
		if dark:
			# Mealy band along the lower face and jaw (not a disc at the tip), capped by a dark
			# moist nose pad, so the face reads as a long bovine wedge rather than a snout.
			_attach(head, tip - FACE_DIR * 0.1 + Vector3(0, -0.005, 0), _axis_basis(FACE_DIR) * Basis.from_scale(Vector3(0.088, 0.15, 0.074)), sph, C_MUZZLE_MEALY, mat)
			_attach(head, tip + FACE_DIR * 0.03 + Vector3(0, 0.005, 0), Basis.from_scale(Vector3(0.07, 0.05, 0.035)), sph, C_NOSE_PAD, mat)
		else:
			_attach(head, tip + Vector3(0, 0.01, 0.0), Basis.from_scale(Vector3(0.09, 0.075, 0.07)), sph, C_MUZZLE, mat)
		for sx in [-1.0, 1.0]:
			_attach(head, tip + Vector3(sx * 0.035, 0.02, -0.055), Basis.from_scale(Vector3(0.018, 0.014, 0.01)), sph, Color(0.05, 0.04, 0.04), mat)
		for sx in [-1.0, 1.0]:
			# Ear: a leaf standing out sideways (a touch down and back) just below the horn root.
			var ear_root := POLL + Vector3(sx * 0.13, -0.04, 0.05)
			var eb := Basis(Vector3.FORWARD, sx * 0.12) * Basis(Vector3.UP, sx * -0.2)
			_attach(head, ear_root + eb * Vector3(sx * 0.115, 0, 0), eb * Basis.from_scale(Vector3(0.125, 0.06, 0.024)), sph, coat.lightened(0.04), mat)
			_attach(head, ear_root + eb * Vector3(sx * 0.125, 0, -0.013), eb * Basis.from_scale(Vector3(0.09, 0.038, 0.01)), sph, coat.lightened(0.24 if dark else 0.18), mat)  # inner ear
			if horned:
				# Short horn: out sideways from the poll, then up and a little forward, pale with
				# a dark tip — thick enough to read at walk-up distance.
				var root := POLL + Vector3(sx * 0.11, 0.05, -0.01)
				var out := Vector3(sx * 0.9, 0.3, -0.25).normalized()
				var up := Vector3(sx * 0.25, 0.95, -0.2).normalized()
				var mid := root + out * 0.12
				var end := mid + up * 0.11
				_attach(head, (root + mid) * 0.5, _axis_basis(out) * Basis.from_scale(Vector3(0.047, 0.13, 0.047)), _cyl(0.78, 1.0), C_HORN, mat)
				_attach(head, root, Basis.from_scale(Vector3(0.05, 0.045, 0.05)), sph, C_HORN, mat)  # boss at the root
				_attach(head, mid, Basis.from_scale(Vector3(0.037, 0.037, 0.037)), sph, C_HORN, mat)
				_attach(head, (mid + end) * 0.5, _axis_basis(up) * Basis.from_scale(Vector3(0.036, 0.11, 0.036)), _cyl(0.4, 1.0), C_HORN, mat)
				_attach(head, end + up * 0.025, _axis_basis(up) * Basis.from_scale(Vector3(0.011, 0.05, 0.011)), _cyl(0.1, 1.0), C_HORN_TIP, mat)
	return coat_parts


## Basis whose +Y points along `dir` (unit).
static func _axis_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := ref.cross(y).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


static func _attach(parent: MeshInstance3D, pos: Vector3, basis: Basis, mesh: Mesh, col: Color, mat: Callable) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat.call(col)
	mi.transform = parent.transform.affine_inverse() * Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


static func _sphere() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 10
	m.rings = 6
	return m


static func _cyl(top: float, bottom: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = 1.0
	m.radial_segments = 7
	return m

