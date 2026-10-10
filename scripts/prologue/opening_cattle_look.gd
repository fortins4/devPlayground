extends RefCounted
## Shared look for the opening's small native cattle (Kerry / Dexter-like): used by the herd
## cows (opening_cow.gd, on the raid-cow body/head nodes) and the knife-hitch heifer prop.
## Visual only. Everything is placed in the animal's local frame (head toward −Z, ground y 0,
## legs at x ±0.25, z ±0.47, hips 0.34 m up); parts parented under the non-uniformly scaled
## body / head meshes are counter-transformed so they keep their own shape.
##
## Silhouette: the barrel (1.45 m long, 0.84 m wide, back ≈ 0.87 m), a raised withers with a
## slight dip behind it and a squarer rump, a deep brisket hanging between the forelegs, a
## thick neck, and a long tapered face (broad poll → narrow muzzle, with a jaw line) carried
## nose-down. Ears stand out sideways just below the horn roots; short pale horns run out and
## then turn up with dark tips (polled beasts get none); the tail hangs from the tailhead to a
## dark switch.

const C_HORN := Color(0.86, 0.8, 0.64)
const C_HORN_TIP := Color(0.16, 0.13, 0.1)
const C_MUZZLE := Color(0.22, 0.19, 0.17)

## Face axis: from the poll down and forward to the muzzle (≈ 40° nose-down).
const FACE_DIR := Vector3(0.0, -0.64, -0.77)
const POLL := Vector3(0.0, 0.84, -0.98)
const FACE_LEN := 0.46


## Dress `body` (a CapsuleMesh r 0.42 h 1.35 instance) and `head` (any MeshInstance3D; its mesh
## is replaced) in the cattle look. `mat` maps a Color to a Material. Returns the parts that
## should share the body's (state-tinted) material.
static func dress(body: MeshInstance3D, head: MeshInstance3D, coat: Color, horned: bool, mat: Callable) -> Array:
	var coat_parts: Array = []
	var sph := _sphere()
	if body:
		body.transform = Transform3D(Basis(Vector3(1.0, 0, 0), Vector3(0, 0, 1.07), Vector3(0, -0.76, 0)), Vector3(0, 0.55, 0.02))
		body.set_surface_override_material(0, mat.call(coat))
		# Withers: raised over the shoulders; a squarer rump behind leaves a slight dip between.
		coat_parts.append(_attach(body, Vector3(0, 0.8, -0.4), Basis.from_scale(Vector3(0.3, 0.16, 0.3)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 0.79, 0.43), Basis.from_scale(Vector3(0.38, 0.13, 0.3)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 0.79, 0.6), Basis.from_scale(Vector3(0.27, 0.08, 0.13)), sph, coat, mat))  # pins / tailhead
		# Deep brisket and chest hanging between the forelegs.
		coat_parts.append(_attach(body, Vector3(0, 0.42, -0.5), Basis.from_scale(Vector3(0.27, 0.27, 0.28)), sph, coat, mat))
		coat_parts.append(_attach(body, Vector3(0, 0.33, -0.66), Basis.from_scale(Vector3(0.14, 0.16, 0.12)), sph, coat, mat))  # dewlap fold
		# Tail: from the tailhead down the rump to a dark switch near the hocks.
		var top := Vector3(0, 0.8, 0.7)
		var bot := Vector3(0, 0.34, 0.8)
		var ax := (bot - top)
		var tb := _axis_basis(ax.normalized())
		coat_parts.append(_attach(body, (top + bot) * 0.5, tb * Basis.from_scale(Vector3(0.028, ax.length(), 0.028)), _cyl(1.0, 1.0), coat, mat))
		_attach(body, bot + Vector3(0, -0.05, 0.005), Basis.from_scale(Vector3(0.055, 0.11, 0.055)), sph, coat.darkened(0.45), mat)
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
		head.set_surface_override_material(0, mat.call(coat))
		var tip := POLL + FACE_DIR * FACE_LEN
		# Thick neck from the withers down into the poll.
		coat_parts.append(_attach(head, Vector3(0, 0.7, -0.76), Basis(Vector3.RIGHT, 0.55) * Basis.from_scale(Vector3(0.2, 0.25, 0.25)), sph, coat, mat))
		# Broad forehead / poll and cheeks.
		coat_parts.append(_attach(head, POLL + Vector3(0, -0.02, -0.02), Basis.from_scale(Vector3(0.15, 0.12, 0.12)), sph, coat, mat))
		coat_parts.append(_attach(head, POLL + FACE_DIR * 0.2 + Vector3(0, -0.03, 0.04), Basis.from_scale(Vector3(0.13, 0.11, 0.12)), sph, coat, mat))
		# Jaw line under the face, and the muzzle (greyer) with two nostrils at the tip.
		coat_parts.append(_attach(head, POLL + FACE_DIR * 0.3 + Vector3(0, -0.08, 0.06), Basis(Vector3.RIGHT, -0.65) * Basis.from_scale(Vector3(0.075, 0.06, 0.17)), sph, coat, mat))
		_attach(head, tip + Vector3(0, 0.01, 0.0), Basis.from_scale(Vector3(0.09, 0.075, 0.07)), sph, C_MUZZLE, mat)
		for sx in [-1.0, 1.0]:
			_attach(head, tip + Vector3(sx * 0.035, 0.02, -0.055), Basis.from_scale(Vector3(0.018, 0.014, 0.01)), sph, Color(0.05, 0.04, 0.04), mat)
		for sx in [-1.0, 1.0]:
			# Ear: a leaf standing out sideways (a touch down and back) just below the horn root.
			var ear_root := POLL + Vector3(sx * 0.13, -0.04, 0.05)
			var eb := Basis(Vector3.FORWARD, sx * 0.2) * Basis(Vector3.UP, sx * -0.25)
			_attach(head, ear_root + eb * Vector3(sx * 0.1, 0, 0), eb * Basis.from_scale(Vector3(0.11, 0.055, 0.022)), sph, coat.lightened(0.04), mat)
			_attach(head, ear_root + eb * Vector3(sx * 0.11, 0, -0.012), eb * Basis.from_scale(Vector3(0.08, 0.035, 0.01)), sph, coat.lightened(0.18), mat)  # inner ear
			if horned:
				# Short horn: out sideways from the poll, then up and a little forward, pale with
				# a dark tip — thick enough to read at walk-up distance.
				var root := POLL + Vector3(sx * 0.11, 0.05, -0.01)
				var out := Vector3(sx * 0.9, 0.3, -0.25).normalized()
				var up := Vector3(sx * 0.25, 0.95, -0.2).normalized()
				var mid := root + out * 0.12
				var end := mid + up * 0.1
				_attach(head, (root + mid) * 0.5, _axis_basis(out) * Basis.from_scale(Vector3(0.036, 0.13, 0.036)), _cyl(0.8, 1.0), C_HORN, mat)
				_attach(head, mid, Basis.from_scale(Vector3(0.03, 0.03, 0.03)), sph, C_HORN, mat)
				_attach(head, (mid + end) * 0.5, _axis_basis(up) * Basis.from_scale(Vector3(0.029, 0.1, 0.029)), _cyl(0.35, 1.0), C_HORN, mat)
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

