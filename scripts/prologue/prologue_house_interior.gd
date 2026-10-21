extends Node3D
class_name PrologueHouseInterior
## Raid day, dawn on (steps 4–6): the family roundhouse can be entered. The evening's greybox house
## is a solid drum (one cylinder collider, the doorway a dark slab); for the wake Cian sleeps
## inside, on the rush pallet just inside the door, and at step 6 the knife hangs on the inside
## face of the wattle, left of the doorway as you go out. This swaps the drum for a ring of wall
## panels with a real door gap (daub outside, sooty wattle inside, one box collider each), puts a
## dark shell under the thatch (open at the smoke hole), and lights it only by the hearth embers
## where Máire stirs and the grey glow of the doorway. No furnishing beyond that (spec: a simple
## dark interior). Camera: while Cian is in or near the house the third-person camera is pulled in
## along the pivot→camera ray so it never goes through the wall, and kept under the thatch.

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const DOOR := Vector3(-7.2, 0.0, 1.77)
const R := 3.5
const WALL_H := 1.9
const CONE_H := 3.3
const PANELS := 36
const CAM_LAYER := 1 << 19 ## the wall panels only (camera ray)
const C_DAUB := Color(0.74, 0.66, 0.52)
const C_SOOT := Color(0.14, 0.11, 0.085)
const C_THATCH_IN := Color(0.1, 0.08, 0.06)
const C_FLOOR := Color(0.2, 0.16, 0.12)

var _player: Node3D = null
var _cam_pulled: bool = false
var _hearth_light: OmniLight3D = null
var _t: float = 0.0
var _built: bool = false
var _cam_dist_now: float = -1.0


static func centre() -> Vector3:
	return DOOR - Vector3(0.0, 0.0, R)


## Ground-level point at angle `ang` (rad; +PI/2 = the door, facing +Z) and radius `r`.
static func ring_point(ang: float, r: float) -> Vector3:
	var c := centre()
	return Vector3(c.x + cos(ang) * r, 0.0, c.z + sin(ang) * r)


static func is_inside(p: Vector3, margin: float = 0.15) -> bool:
	var c := centre()
	return Vector2(p.x - c.x, p.z - c.z).length() < R - margin


func _ready() -> void:
	add_to_group("prologue_house_interior")
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 1000  # after the player has placed his camera pivot


func build(scene_root: Node) -> void:
	if _built:
		return
	_built = true
	_retire_drum(scene_root)
	var c := centre()
	var gy := 0.0  # the greybox house sits at y 0 (its drum and hearth are placed without terrain)
	var body := StaticBody3D.new()
	body.name = "RoundhouseRing"
	body.collision_layer = 1 | CAM_LAYER
	body.collision_mask = 0
	add_child(body)
	var step := TAU / float(PANELS)
	var chord := 2.0 * R * sin(step * 0.5)
	for k in PANELS:
		if k == 0 or k == PANELS - 1:
			continue  # the doorway (between the jambs, ~1.2 m)
		var ang := PI * 0.5 + (float(k) + 0.5) * step
		var yaw := -ang + PI * 0.5
		var out_p := ring_point(ang, R - 0.04)
		_panel(body, out_p, yaw, Vector3(chord + 0.03, WALL_H, 0.08), C_DAUB, gy)
		var in_p := ring_point(ang, R - 0.12)
		_panel(body, in_p, yaw, Vector3(chord * (R - 0.12) / R + 0.02, WALL_H, 0.06), C_SOOT, gy)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(chord + 0.04, WALL_H, 0.2)
		cs.shape = bs
		cs.position = ring_point(ang, R - 0.08) + Vector3(0.0, gy + WALL_H * 0.5, 0.0)
		cs.rotation.y = yaw
		body.add_child(cs)
	# Dark shell under the thatch (faces inward), open at the smoke hole.
	var cone := MeshInstance3D.new()
	cone.name = "ThatchUnderside"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = R - 0.1
	cm.height = CONE_H - 0.35
	cm.cap_top = false
	cm.cap_bottom = false
	cm.flip_faces = true
	cm.radial_segments = 36
	cone.mesh = cm
	cone.material_override = _mat(C_THATCH_IN)
	cone.position = c + Vector3(0.0, gy + WALL_H - 0.1 + cm.height * 0.5, 0.0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	# Beaten-earth floor, darker than the yard.
	var floor_mi := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = R - 0.1
	fm.bottom_radius = R - 0.1
	fm.height = 0.02
	fm.radial_segments = 36
	floor_mi.mesh = fm
	floor_mi.material_override = _mat(C_FLOOR)
	floor_mi.position = c + Vector3(0.0, gy + 0.012, 0.0)
	add_child(floor_mi)
	# Hearth embers (the greybox kerb stays): a glowing bed, a few coals, the only warm light.
	var bed := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.36
	bm.bottom_radius = 0.4
	bm.height = 0.05
	bed.mesh = bm
	var em := _mat(Color(0.35, 0.1, 0.03))
	em.emission_enabled = true
	em.emission = Color(1.0, 0.36, 0.08)
	em.emission_energy_multiplier = 1.6
	bed.material_override = em
	bed.position = c + Vector3(0.0, gy + 0.08, 0.0)
	add_child(bed)
	for i in 6:
		var coal := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.09, 0.05, 0.07)
		coal.mesh = cb
		coal.material_override = em if i % 2 == 0 else _mat(Color(0.08, 0.06, 0.05))
		var a := TAU * float(i) / 6.0 + 0.4
		coal.position = c + Vector3(cos(a) * 0.18, gy + 0.12, sin(a) * 0.18)
		coal.rotation.y = a
		add_child(coal)
	_hearth_light = OmniLight3D.new()
	_hearth_light.name = "HearthEmbers"
	_hearth_light.light_color = Color(1.0, 0.5, 0.2)
	_hearth_light.light_energy = 1.1
	_hearth_light.omni_range = 4.2
	_hearth_light.omni_attenuation = 1.3
	_hearth_light.position = c + Vector3(0.0, gy + 0.45, 0.0)
	add_child(_hearth_light)
	# The doorway's grey glow spilling a little way in.
	var door_light := OmniLight3D.new()
	door_light.name = "DoorGlow"
	door_light.light_color = Color(0.72, 0.78, 0.86)
	door_light.light_energy = 0.55
	door_light.omni_range = 3.0
	door_light.position = DOOR + Vector3(0.0, gy + 1.1, -0.45)
	add_child(door_light)
	print("PROLOGUE_HOUSE_INTERIOR built panels=%d" % (PANELS - 2))


## The greybox drum: collider off, its wall skin and the dark door slab hidden (the posts, the
## thatch, the jambs, the lintel and the hearth kerb stay).
func _retire_drum(scene_root: Node) -> void:
	var drum := scene_root.find_child("Roundhouse", true, false) as Node3D
	if drum == null:
		push_warning("PrologueHouseInterior: no Roundhouse")
		return
	for ch in drum.get_children():
		if ch is CollisionShape3D:
			(ch as CollisionShape3D).disabled = true
		elif ch is MeshInstance3D and (ch as MeshInstance3D).mesh is CylinderMesh:
			(ch as MeshInstance3D).visible = false
	var gen := drum.get_parent()
	for ch in gen.get_children():
		# The eave lip is a flat disc across the whole house at wall-top height: open its caps so
		# it is only the lip band (else it is a lid over the room for a camera above 1.8 m).
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is CylinderMesh:
			var cy := (ch as MeshInstance3D).mesh as CylinderMesh
			var cp := (ch as Node3D).position
			if absf(cy.bottom_radius - (R + 0.72)) < 0.05 and cy.height < 0.2 and Vector2(cp.x - DOOR.x, cp.z - (DOOR.z - R)).length() < 0.3:
				var lip := cy.duplicate() as CylinderMesh
				lip.cap_top = false
				lip.cap_bottom = false
				(ch as MeshInstance3D).mesh = lip
				(ch as MeshInstance3D).material_override = (ch as MeshInstance3D).material_override.duplicate() if (ch as MeshInstance3D).material_override else null
				if (ch as MeshInstance3D).material_override is BaseMaterial3D:
					((ch as MeshInstance3D).material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
				(ch as Node3D).name = "EaveLipBand"
		# The thatch cone's bottom cap is a flat ceiling at the eave: open it (the dark shell is
		# the underside of the thatch from inside).
		if ch is MeshInstance3D and (ch as Node3D).name == "HouseThatch" and (ch as MeshInstance3D).mesh is CylinderMesh:
			var tm := ((ch as MeshInstance3D).mesh as CylinderMesh).duplicate() as CylinderMesh
			tm.cap_bottom = false
			(ch as MeshInstance3D).mesh = tm
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is BoxMesh:
			var bx := (ch as MeshInstance3D).mesh as BoxMesh
			var p := (ch as Node3D).position
			if bx.size.distance_to(Vector3(1.0, 1.64, 0.12)) < 0.01 and Vector2(p.x - DOOR.x, p.z - DOOR.z).length() < 0.3:
				(ch as Node3D).visible = false
				(ch as Node3D).name = "DoorSlabRetired"


func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	if _hearth_light:
		_hearth_light.light_energy = 1.0 + 0.18 * sin(_t * 7.3) + 0.1 * sin(_t * 12.9 + 1.3)
	_camera_rig()


func camera_pulled() -> bool:
	return _cam_pulled


## Pull the camera in along pivot→camera when the wall is in the way; keep it under the thatch.
func _camera_rig() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var cam := _player.get("camera") as Camera3D
	if cam == null:
		return
	var base: Vector3 = _player.get("_camera_base_pos")
	var c := centre()
	var pp := _player.global_position
	var near := Vector2(pp.x - c.x, pp.z - c.z).length() < R + 4.5
	if not near:
		if _cam_pulled:
			cam.position = base
			_cam_pulled = false
		return
	var pivot := cam.get_parent() as Node3D
	var from := pivot.global_position
	var want := pivot.global_transform * base
	var dir := want - from
	var full := dir.length()
	if full < 0.01:
		return
	dir /= full
	var dist := full
	var q := PhysicsRayQueryParameters3D.create(from, want, CAM_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(0.25, from.distance_to(hit["position"]) - 0.28)
	var inside := is_inside(pp, 0.0)
	var p := from + dir * dist
	if inside:
		# Under the thatch: the shell drops from ~2.0 m at the wall to the smoke hole.
		var r := Vector2(p.x - c.x, p.z - c.z).length()
		var gy := 0.0
		var ceil_y := gy + WALL_H - 0.1 + (CONE_H - 0.35) * clampf(1.0 - (r - 0.3) / (R - 0.4), 0.0, 1.0) - 0.3
		if p.y > ceil_y and dir.y > 0.01:
			dist = minf(dist, maxf(0.25, (ceil_y - from.y) / dir.y))
		elif p.y > ceil_y:
			dist = minf(dist, 1.2)
	# Ease out to full length, snap in (no frame through the wall).
	if _cam_dist_now < 0.0 or dist < _cam_dist_now:
		_cam_dist_now = dist
	else:
		_cam_dist_now = move_toward(_cam_dist_now, dist, get_process_delta_time() * 4.0)
	if _cam_dist_now >= full - 0.01:
		if _cam_pulled:
			cam.position = base
			_cam_pulled = false
		return
	cam.global_position = from + dir * _cam_dist_now
	_cam_pulled = true


func _panel(parent: Node3D, p: Vector3, yaw: float, size: Vector3, col: Color, gy: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = p + Vector3(0.0, gy + size.y * 0.5, 0.0)
	mi.rotation.y = yaw
	parent.add_child(mi)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	return m
