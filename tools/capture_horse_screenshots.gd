extends SceneTree
## Capture horse mount / ride / dismount proof shots.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/horse"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "HorseCaptureRoot"
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

	# Floor
	var ground := StaticBody3D.new()
	world.add_child(ground)
	var gmesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 0.2, 40)
	gmesh.mesh = box
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.34, 0.42, 0.27)
	gmat.roughness = 0.95
	gmesh.set_surface_override_material(0, gmat)
	gmesh.position.y = -0.1
	ground.add_child(gmesh)
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(40, 0.2, 40)
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
	horse.rotation_degrees.y = 25.0
	player.global_position = Vector3(2.2, 0.1, 1.6)
	player.rotation_degrees.y = -40.0

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true

	# Lane sign for HUD/control hint shot
	var sign := Label3D.new()
	sign.text = "Horse lane\nE mount/dismount · WASD · Shift gallop\n(Combat blocked while mounted)"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 32
	sign.modulate = Color(0.9, 0.82, 0.55)
	sign.position = Vector3(-2.0, 2.5, 0.5)
	world.add_child(sign)

	await process_frame
	await process_frame
	await process_frame

	# Settle physics
	for _t in 20:
		await physics_frame

	# Force prompt visible for nearby shot
	var prompt := horse.get_node_or_null("PromptLabel") as Label3D
	if prompt:
		prompt.text = "E  Mount horse"
		prompt.visible = true

	# 01 — horse nearby + prompt
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(4.8, 3.2, 5.2), Vector3(0.2, 1.1, 0.2), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_horse_nearby")

	# 02 — mounted
	if horse.has_method("mount"):
		horse.call("mount", player)
	await process_frame
	await process_frame
	for _t in 10:
		await physics_frame
	cam.look_at_from_position(Vector3(5.2, 3.6, 5.8), Vector3(0.0, 1.4, 0.0), Vector3.UP)
	await process_frame
	await _shot(vp, out_dir, "02_mounted")

	# 03 — riding (gallop forward a bit)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for _t in 45:
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await process_frame
	var focus := horse.global_position + Vector3(0.0, 1.3, 0.0)
	cam.look_at_from_position(focus + Vector3(5.5, 2.8, 4.5), focus, Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_riding")

	# 04 — dismount
	if horse.has_method("dismount"):
		horse.call("dismount")
	await process_frame
	await process_frame
	for _t in 12:
		await physics_frame
	focus = horse.global_position + Vector3(0.0, 1.1, 0.0)
	cam.look_at_from_position(focus + Vector3(4.8, 3.0, 4.2), focus, Vector3.UP)
	if prompt:
		prompt.visible = true
		prompt.text = "E  Mount horse"
	await process_frame
	await _shot(vp, out_dir, "04_dismount")

	# 05 — control hint / lane label framing
	player.global_position = horse.global_position + Vector3(2.4, 0.1, 1.8)
	sign.global_position = horse.global_position + Vector3(-1.8, 2.6, 0.8)
	cam.fov = 52.0
	cam.look_at_from_position(
		horse.global_position + Vector3(3.5, 3.8, 6.0),
		horse.global_position + Vector3(-0.5, 1.8, 0.5),
		Vector3.UP
	)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_control_hint")

	print("HORSE_SCREENSHOTS_OK dir=", out_dir)
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
