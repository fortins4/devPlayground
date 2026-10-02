extends SceneTree
## Capture seated mounted rider pose proof shots (C2).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/seated-rider"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "SeatedRiderCaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.54, 0.6)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.9, 0.84)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-48.0, 40.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20.0, -130.0, 0.0)
	world.add_child(fill)

	var ground := StaticBody3D.new()
	world.add_child(ground)
	var gmesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(48, 0.2, 48)
	gmesh.mesh = box
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.34, 0.42, 0.27)
	gmat.roughness = 0.95
	gmesh.set_surface_override_material(0, gmat)
	gmesh.position.y = -0.1
	ground.add_child(gmesh)
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(48, 0.2, 48)
	gcol.shape = gshape
	gcol.position.y = -0.1
	ground.add_child(gcol)

	var horse_ps := load("res://scenes/characters/horse/horse.tscn") as PackedScene
	var player_ps := load("res://scenes/characters/player/player.tscn") as PackedScene
	var horse := horse_ps.instantiate() as CharacterBody3D
	var player := player_ps.instantiate() as CharacterBody3D
	world.add_child(horse)
	world.add_child(player)

	horse.global_position = Vector3(0.0, 0.1, 0.0)
	horse.rotation_degrees.y = 20.0
	player.global_position = Vector3(2.3, 0.1, 1.7)
	player.rotation_degrees.y = -35.0

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.current = true

	var banner := Label3D.new()
	banner.text = "Seated rider (C2)\nE mount · WASD · Shift gallop"
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.font_size = 30
	banner.modulate = Color(0.9, 0.82, 0.55)
	banner.position = Vector3(-2.2, 2.55, 0.6)
	world.add_child(banner)

	await process_frame
	await process_frame
	await process_frame
	for _t in 24:
		await physics_frame

	var prompt := horse.get_node_or_null("PromptLabel") as Label3D
	if prompt:
		prompt.text = "E  Mount horse"
		prompt.visible = true

	# 01 — mount nearby
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(4.8, 3.2, 5.2), Vector3(0.2, 1.1, 0.2), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_mount_nearby")

	# 02 — seated idle (side 3/4 to show astride legs)
	if horse.has_method("mount"):
		horse.call("mount", player)
	await process_frame
	await process_frame
	for _t in 14:
		await physics_frame
	# Force one seated tick in case physics hasn't run horse yet
	if player.has_method("tick_mounted_rider_pose"):
		player.call("tick_mounted_rider_pose", 0.016, 0.0, false)
	await process_frame
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(4.2, 2.4, 3.6), Vector3(0.0, 1.35, 0.05), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "02_seated_idle")

	# 03 — seated idle rear/side (legs wrapping barrel)
	cam.look_at_from_position(Vector3(-3.8, 2.2, 3.4), Vector3(0.05, 1.3, 0.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_seated_idle_side")

	# 04 — trot
	Input.action_press("move_forward")
	for _t in 36:
		await physics_frame
	Input.action_release("move_forward")
	await process_frame
	var focus := horse.global_position + Vector3(0.0, 1.35, 0.0)
	cam.fov = 44.0
	cam.look_at_from_position(focus + Vector3(4.6, 2.0, 3.2), focus, Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_trot")

	# 05 — gallop bob
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for _t in 40:
		await physics_frame
	# Mid-stride still holding gallop for bob frame
	await process_frame
	focus = horse.global_position + Vector3(0.0, 1.4, 0.0)
	cam.look_at_from_position(focus + Vector3(5.0, 2.3, 3.8), focus, Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_gallop_bob")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for _t in 10:
		await physics_frame

	# 06 — dismount restores foot loco
	if horse.has_method("dismount"):
		horse.call("dismount")
	await process_frame
	await process_frame
	for _t in 14:
		await physics_frame
	focus = horse.global_position + Vector3(0.0, 1.1, 0.0)
	cam.fov = 48.0
	cam.look_at_from_position(focus + Vector3(4.6, 2.8, 4.0), focus, Vector3.UP)
	if prompt:
		prompt.visible = true
		prompt.text = "E  Mount horse"
	await process_frame
	await _shot(vp, out_dir, "06_dismount")

	print("SEATED_RIDER_SCREENSHOTS_OK dir=", out_dir)
	quit(0)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	if err != OK:
		push_error("Failed to save %s (%s)" % [path, str(err)])
	else:
		print("Wrote ", path)
