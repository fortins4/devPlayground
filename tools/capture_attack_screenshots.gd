extends SceneTree
## Capture hatchet light/heavy attack poses for playtest proof.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "CaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.55, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	environment.ambient_light_energy = 1.0
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.2
	light.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20.0, -80.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.36, 0.24)
	ground.material_override = gmat
	world.add_child(ground)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_packed.instantiate() as Node3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	# Turn slightly so right-hand hatchet reads clearly from camera
	player.rotation_degrees.y = 25.0
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	# Side-rear framing focused on weapon hand
	cam.look_at_from_position(Vector3(2.1, 1.55, 2.0), Vector3(0.35, 1.15, -0.1), Vector3.UP)
	cam.current = true

	await process_frame
	await process_frame

	var combat := player.get_node("CombatSystem") as CombatSystem
	var weapon_visual := player.get_node("WeaponVisual") as Node3D
	var right_arm := player.get_node("Visual/RightArm") as MeshInstance3D
	combat.set_weapon(CombatSystem.Weapon.HATCHET)
	var arm_base := right_arm.transform

	var shots: Array = [
		{"name": "hatchet_idle", "kind": &"light", "pose": "idle"},
		{"name": "hatchet_light_windup", "kind": &"light", "pose": "windup"},
		{"name": "hatchet_light_contact", "kind": &"light", "pose": "contact"},
		{"name": "hatchet_heavy_windup", "kind": &"heavy", "pose": "windup"},
		{"name": "hatchet_heavy_contact", "kind": &"heavy", "pose": "contact"},
		{"name": "hatchet_heavy_follow", "kind": &"heavy", "pose": "follow"},
	]

	for shot in shots:
		right_arm.transform = arm_base
		_apply_pose(combat, weapon_visual, right_arm, arm_base, shot["kind"], String(shot["pose"]))
		await process_frame
		await process_frame
		await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["name"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err, " weapon_rot=", weapon_visual.rotation_degrees)

	print("CAPTURE_DONE")
	quit(0)


func _apply_pose(
	combat: CombatSystem,
	weapon_visual: Node3D,
	right_arm: Node3D,
	arm_base: Transform3D,
	kind: StringName,
	pose: String
) -> void:
	combat.reset_weapon_pose()
	if pose == "idle":
		return
	var poses: Dictionary = combat.call("_swing_poses", kind)
	weapon_visual.rotation_degrees = poses["%s_rot" % pose]
	weapon_visual.position = poses["%s_pos" % pose]
	var heavy := kind == &"heavy"
	var base := arm_base.basis.get_euler()
	match pose:
		"windup":
			right_arm.rotation = base + Vector3(
				deg_to_rad(-25.0 if heavy else -12.0), 0.0, deg_to_rad(-0.55 if heavy else -0.35)
			)
		"contact":
			right_arm.rotation = base + Vector3(
				deg_to_rad(20.0 if heavy else 10.0), 0.0, deg_to_rad(0.55 if heavy else 0.35)
			)
		"follow":
			right_arm.rotation = base + Vector3(
				deg_to_rad(45.0 if heavy else 28.0), 0.0, deg_to_rad(0.95 if heavy else 0.65)
			)
