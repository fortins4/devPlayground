class_name KerneMeshBuilder
extends RefCounted
## Builds a readable early-medieval Irish kerne silhouette from primitive meshes.
## Original greybox art for Ríocht (no third-party mesh import). Kit: hatchet + knife + goad.

const PALETTE_PLAYER := {
	"skin": Color(0.86, 0.70, 0.58),
	"hair": Color(0.16, 0.10, 0.06),
	"tunic": Color(0.34, 0.44, 0.38), # soft léine green-grey
	"skirt": Color(0.30, 0.38, 0.34),
	"pants": Color(0.26, 0.24, 0.20),
	"shoes": Color(0.22, 0.16, 0.10),
	"belt": Color(0.18, 0.12, 0.08),
	"cloak": Color(0.28, 0.24, 0.36), # muted brat
	"wood": Color(0.42, 0.28, 0.14),
	"iron": Color(0.45, 0.48, 0.50),
	"wrap": Color(0.55, 0.48, 0.38),
}

const PALETTE_HOSTILE := {
	"skin": Color(0.78, 0.58, 0.48),
	"hair": Color(0.12, 0.08, 0.06),
	"tunic": Color(0.48, 0.22, 0.18),
	"skirt": Color(0.40, 0.18, 0.15),
	"pants": Color(0.22, 0.18, 0.16),
	"shoes": Color(0.18, 0.12, 0.08),
	"belt": Color(0.14, 0.10, 0.08),
	"cloak": Color(0.32, 0.16, 0.14),
	"wood": Color(0.40, 0.26, 0.12),
	"iron": Color(0.50, 0.52, 0.55),
	"wrap": Color(0.45, 0.35, 0.28),
}


static func _mat(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _mesh_inst(mesh: Mesh, mat: Material, name: String = "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


## Clears children of `visual` and builds a jointed kerne. Returns joint Node3D map.
static func build(visual: Node3D, palette: Dictionary = PALETTE_PLAYER, include_kit_props: bool = true) -> Dictionary:
	while visual.get_child_count() > 0:
		var child := visual.get_child(0)
		visual.remove_child(child)
		child.free()

	var skin := _mat(palette.get("skin", PALETTE_PLAYER["skin"]), 0.85)
	var hair := _mat(palette.get("hair", PALETTE_PLAYER["hair"]), 0.8)
	var tunic := _mat(palette.get("tunic", PALETTE_PLAYER["tunic"]), 0.92)
	var skirt := _mat(palette.get("skirt", PALETTE_PLAYER["skirt"]), 0.94)
	var pants := _mat(palette.get("pants", PALETTE_PLAYER["pants"]), 0.95)
	var shoes := _mat(palette.get("shoes", PALETTE_PLAYER["shoes"]), 0.96)
	var belt := _mat(palette.get("belt", PALETTE_PLAYER["belt"]), 0.9)
	var cloak := _mat(palette.get("cloak", PALETTE_PLAYER["cloak"]), 0.93)
	var wood := _mat(palette.get("wood", PALETTE_PLAYER["wood"]), 0.9)
	var iron := _mat(palette.get("iron", PALETTE_PLAYER["iron"]), 0.45, 0.55)
	var wrap := _mat(palette.get("wrap", PALETTE_PLAYER["wrap"]), 0.88)

	var root := Node3D.new()
	root.name = "Root"
	visual.add_child(root)

	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0.0, 0.92, 0.0)
	root.add_child(hips)

	var hips_mesh := BoxMesh.new()
	hips_mesh.size = Vector3(0.40, 0.16, 0.24)
	hips.add_child(_mesh_inst(hips_mesh, pants, "HipsMesh"))

	var left_thigh := Node3D.new()
	left_thigh.name = "LeftThigh"
	left_thigh.position = Vector3(-0.11, -0.08, 0.0)
	hips.add_child(left_thigh)
	var lt_mesh := CapsuleMesh.new()
	lt_mesh.radius = 0.07
	lt_mesh.height = 0.42
	var lt_mi := _mesh_inst(lt_mesh, pants, "Mesh")
	lt_mi.position = Vector3(0.0, -0.22, 0.0)
	left_thigh.add_child(lt_mi)

	var left_shin := Node3D.new()
	left_shin.name = "LeftShin"
	left_shin.position = Vector3(0.0, -0.44, 0.0)
	left_thigh.add_child(left_shin)
	var ls_mesh := CapsuleMesh.new()
	ls_mesh.radius = 0.055
	ls_mesh.height = 0.40
	var ls_mi := _mesh_inst(ls_mesh, pants, "Mesh")
	ls_mi.position = Vector3(0.0, -0.18, 0.0)
	left_shin.add_child(ls_mi)
	var lf_mesh := BoxMesh.new()
	lf_mesh.size = Vector3(0.11, 0.055, 0.22)
	var lf_mi := _mesh_inst(lf_mesh, shoes, "Foot")
	lf_mi.position = Vector3(0.0, -0.38, 0.05)
	left_shin.add_child(lf_mi)

	var right_thigh := Node3D.new()
	right_thigh.name = "RightThigh"
	right_thigh.position = Vector3(0.11, -0.08, 0.0)
	hips.add_child(right_thigh)
	var rt_mesh := CapsuleMesh.new()
	rt_mesh.radius = 0.07
	rt_mesh.height = 0.42
	var rt_mi := _mesh_inst(rt_mesh, pants, "Mesh")
	rt_mi.position = Vector3(0.0, -0.22, 0.0)
	right_thigh.add_child(rt_mi)

	var right_shin := Node3D.new()
	right_shin.name = "RightShin"
	right_shin.position = Vector3(0.0, -0.44, 0.0)
	right_thigh.add_child(right_shin)
	var rs_mesh := CapsuleMesh.new()
	rs_mesh.radius = 0.055
	rs_mesh.height = 0.40
	var rs_mi := _mesh_inst(rs_mesh, pants, "Mesh")
	rs_mi.position = Vector3(0.0, -0.18, 0.0)
	right_shin.add_child(rs_mi)
	var rf_mesh := BoxMesh.new()
	rf_mesh.size = Vector3(0.11, 0.055, 0.22)
	var rf_mi := _mesh_inst(rf_mesh, shoes, "Foot")
	rf_mi.position = Vector3(0.0, -0.38, 0.05)
	right_shin.add_child(rf_mi)

	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0.0, 0.08, 0.0)
	hips.add_child(torso)

	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.44, 0.48, 0.26)
	var torso_mi := _mesh_inst(torso_mesh, tunic, "TorsoMesh")
	torso_mi.position = Vector3(0.0, 0.28, 0.0)
	torso.add_child(torso_mi)

	# Léine flare / skirt hem — reads as tunic at gameplay distance
	var skirt_mesh := BoxMesh.new()
	skirt_mesh.size = Vector3(0.50, 0.28, 0.30)
	var skirt_mi := _mesh_inst(skirt_mesh, skirt, "TunicSkirt")
	skirt_mi.position = Vector3(0.0, 0.02, 0.0)
	torso.add_child(skirt_mi)

	var sh_l := BoxMesh.new()
	sh_l.size = Vector3(0.14, 0.1, 0.18)
	var sh_l_mi := _mesh_inst(sh_l, wrap, "ShoulderL")
	sh_l_mi.position = Vector3(-0.26, 0.48, 0.0)
	torso.add_child(sh_l_mi)
	var sh_r := BoxMesh.new()
	sh_r.size = Vector3(0.14, 0.1, 0.18)
	var sh_r_mi := _mesh_inst(sh_r, wrap, "ShoulderR")
	sh_r_mi.position = Vector3(0.26, 0.48, 0.0)
	torso.add_child(sh_r_mi)

	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.46, 0.06, 0.28)
	var belt_mi := _mesh_inst(belt_mesh, belt, "Belt")
	belt_mi.position = Vector3(0.0, 0.08, 0.0)
	torso.add_child(belt_mi)

	# Soft brat / cloak fold on shoulders (back)
	var cloak_mesh := BoxMesh.new()
	cloak_mesh.size = Vector3(0.48, 0.42, 0.06)
	var cloak_mi := _mesh_inst(cloak_mesh, cloak, "Cloak")
	cloak_mi.position = Vector3(0.0, 0.34, 0.18)
	torso.add_child(cloak_mi)

	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, 0.54, 0.0)
	torso.add_child(neck)
	var neck_mesh := CapsuleMesh.new()
	neck_mesh.radius = 0.06
	neck_mesh.height = 0.12
	neck.add_child(_mesh_inst(neck_mesh, skin, "NeckMesh"))

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.14, 0.0)
	neck.add_child(head)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.145
	head_mesh.height = 0.29
	head.add_child(_mesh_inst(head_mesh, skin, "HeadMesh"))
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.15
	hair_mesh.height = 0.20
	var hair_mi := _mesh_inst(hair_mesh, hair, "Hair")
	hair_mi.position = Vector3(0.0, 0.06, -0.02)
	head.add_child(hair_mi)
	# Short beard hint
	var beard_mesh := SphereMesh.new()
	beard_mesh.radius = 0.08
	beard_mesh.height = 0.12
	var beard_mi := _mesh_inst(beard_mesh, hair, "Beard")
	beard_mi.position = Vector3(0.0, -0.08, 0.06)
	beard_mi.scale = Vector3(1.1, 0.7, 0.9)
	head.add_child(beard_mi)

	var left_arm := Node3D.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-0.28, 0.42, 0.0)
	left_arm.rotation_degrees = Vector3(0.0, 0.0, 12.0)
	torso.add_child(left_arm)
	var la_upper := CapsuleMesh.new()
	la_upper.radius = 0.05
	la_upper.height = 0.32
	var la_u := _mesh_inst(la_upper, wrap, "Upper")
	la_u.position = Vector3(0.0, -0.14, 0.0)
	left_arm.add_child(la_u)
	var left_fore := Node3D.new()
	left_fore.name = "LeftForearm"
	left_fore.position = Vector3(0.0, -0.30, 0.0)
	left_arm.add_child(left_fore)
	var la_fore := CapsuleMesh.new()
	la_fore.radius = 0.045
	la_fore.height = 0.30
	var la_f := _mesh_inst(la_fore, skin, "Fore")
	la_f.position = Vector3(0.0, -0.12, 0.0)
	left_fore.add_child(la_f)

	var right_arm := Node3D.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(0.28, 0.42, 0.0)
	right_arm.rotation_degrees = Vector3(0.0, 0.0, -12.0)
	torso.add_child(right_arm)
	var ra_upper := CapsuleMesh.new()
	ra_upper.radius = 0.05
	ra_upper.height = 0.32
	var ra_u := _mesh_inst(ra_upper, wrap, "Upper")
	ra_u.position = Vector3(0.0, -0.14, 0.0)
	right_arm.add_child(ra_u)
	var right_fore := Node3D.new()
	right_fore.name = "RightForearm"
	right_fore.position = Vector3(0.0, -0.30, 0.0)
	right_arm.add_child(right_fore)
	var ra_fore := CapsuleMesh.new()
	ra_fore.radius = 0.045
	ra_fore.height = 0.30
	var ra_f := _mesh_inst(ra_fore, skin, "Fore")
	ra_f.position = Vector3(0.0, -0.12, 0.0)
	right_fore.add_child(ra_f)

	if include_kit_props:
		# Sheathed knife on left hip — always visible kit silhouette
		var belt_knife := Node3D.new()
		belt_knife.name = "BeltKnife"
		# Left hip, just outside the tunic. Hangs on him when the knife is not drawn.
		belt_knife.position = Vector3(-0.34, 0.14, 0.04)
		belt_knife.rotation_degrees = Vector3(18.0, -40.0, 16.0)
		torso.add_child(belt_knife)
		var bk_handle := BoxMesh.new()
		bk_handle.size = Vector3(0.045, 0.11, 0.04)
		belt_knife.add_child(_mesh_inst(bk_handle, wood, "Handle"))
		var bk_blade := BoxMesh.new()
		bk_blade.size = Vector3(0.04, 0.20, 0.018)
		var bk_b := _mesh_inst(bk_blade, iron, "Blade")
		bk_b.position = Vector3(0.0, -0.12, 0.0)
		belt_knife.add_child(bk_b)

		# Same goad as the hands: full shaft, gray head. Face is +Z, so -Z is the back.
		# Long axis is local Y, up the spine, inside the torso's width.
		var back_goad := Node3D.new()
		back_goad.name = "BackGoad"
		back_goad.position = Vector3(0.0, -0.55, -0.158)
		back_goad.rotation_degrees = Vector3.ZERO
		torso.add_child(back_goad)
		var goad_mesh := BoxMesh.new()
		goad_mesh.size = Vector3(0.045, 1.75, 0.045)
		var goad_mi := _mesh_inst(goad_mesh, wood, "Staff")
		goad_mi.position = Vector3(0.0, 0.62, 0.0)
		back_goad.add_child(goad_mi)
		var tip_mesh := BoxMesh.new()
		tip_mesh.size = Vector3(0.08, 0.12, 0.08)
		var tip_mi := _mesh_inst(tip_mesh, iron, "Tip")
		tip_mi.position = Vector3(0.0, 1.52, 0.0)
		back_goad.add_child(tip_mi)

	return {
		"root": root,
		"hips": hips,
		"torso": torso,
		"neck": neck,
		"head": head,
		"left_thigh": left_thigh,
		"left_shin": left_shin,
		"right_thigh": right_thigh,
		"right_shin": right_shin,
		"left_arm": left_arm,
		"left_forearm": left_fore,
		"right_arm": right_arm,
		"right_forearm": right_fore,
	}
