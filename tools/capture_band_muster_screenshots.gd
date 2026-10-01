extends SceneTree
## Capture ringfort band muster proof shots (empty / recruited / follow-hold).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/band"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "BandMusterCapture"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.52, 0.58)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.9, 0.92)
	environment.ambient_light_energy = 1.0
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.2
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.3
	fill.rotation_degrees = Vector3(-25.0, -120.0, 0.0)
	world.add_child(fill)

	var ringfort_ps := load("res://scenes/world/ringfort/ringfort.tscn") as PackedScene
	var player_ps := load("res://scenes/characters/player/player.tscn") as PackedScene
	var ringfort := ringfort_ps.instantiate() as Node3D
	var player := player_ps.instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(ringfort)

	player.global_position = Vector3(2.0, 0.1, 3.5)
	player.rotation_degrees.y = -20.0
	ringfort.global_position = Vector3.ZERO

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true

	await process_frame
	await process_frame
	await process_frame

	# Ensure ringfort found the player + runtime is set up.
	if ringfort.has_method("_find_player_deferred"):
		ringfort.call("_find_player_deferred")
	await process_frame
	await process_frame

	var cattle: CattleEconomy = ringfort.get_node("CattleEconomy") as CattleEconomy
	var runtime: Node = ringfort.get_node("BandRuntime")
	var muster: Node3D = ringfort.get_node("MusterPoint") as Node3D

	# --- 01 empty muster ---
	if cattle:
		cattle.set_band(0, 50.0, 45.0)
	if runtime and runtime.has_method("set_follow_enabled"):
		runtime.call("set_follow_enabled", true)
	player.global_position = Vector3(3.5, 0.1, 4.0)
	cam.look_at_from_position(Vector3(8.5, 5.5, 9.0), Vector3(0.0, 1.2, 1.5), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_empty_muster")

	# --- 02 recruited followers at muster (hold) ---
	player.global_position = muster.global_position + Vector3(1.2, 0.1, 1.0)
	if cattle:
		# Direct recruit without interact — three kernes.
		for _i in 3:
			cattle.try_recruit_option(&"local_kerne", 50.0)
	await process_frame
	await process_frame
	if runtime and runtime.has_method("set_follow_enabled"):
		runtime.call("set_follow_enabled", false)
	await process_frame
	await process_frame
	# Nudge followers into hold slots by simulating a few physics ticks.
	for _t in 45:
		await physics_frame
	cam.look_at_from_position(Vector3(7.5, 4.8, 8.5), Vector3(0.2, 1.0, 2.2), Vector3.UP)
	await process_frame
	await _shot(vp, out_dir, "02_recruited_hold_at_muster")

	# --- 03 follow near player ---
	if runtime and runtime.has_method("set_follow_enabled"):
		runtime.call("set_follow_enabled", true)
	player.global_position = Vector3(1.5, 0.1, -1.0)
	player.rotation_degrees.y = 40.0
	for _t in 55:
		await physics_frame
	cam.look_at_from_position(Vector3(6.5, 3.8, 5.5), Vector3(0.5, 1.1, 0.2), Vector3.UP)
	await process_frame
	await _shot(vp, out_dir, "03_followers_follow_player")

	print("BAND_MUSTER_SCREENSHOTS_OK dir=", out_dir)
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
