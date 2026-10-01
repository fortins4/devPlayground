extends SceneTree
## Capture Leinster greybox landmark proof shots (overview, Bannow, path/home/monastic).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/leinster"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "LeinsterCaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.48, 0.56, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.9, 0.84)
	environment.ambient_light_energy = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.7, 0.72, 0.65)
	environment.fog_density = 0.0012
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	fill.rotation_degrees = Vector3(-25.0, -120.0, 0.0)
	world.add_child(fill)

	var region_packed := load("res://scenes/world/regions/leinster/leinster_region.tscn") as PackedScene
	var region := region_packed.instantiate() as Node3D
	world.add_child(region)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3(0.0, 0.1, 0.0)
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.current = true

	await process_frame
	await process_frame
	await process_frame

	# 01 overview — elevated look covering home (W), road, Bannow (S), monastic (NE)
	player.global_position = Vector3(0.0, 0.1, 2.0)
	cam.fov = 62.0
	cam.look_at_from_position(Vector3(-22.0, 32.0, 22.0), Vector3(2.0, 1.0, 8.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_overview")

	# 02 Bannow Bay approach
	player.global_position = Vector3(0.0, 0.1, 34.0)
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(-12.0, 9.0, 28.0), Vector3(2.0, 1.5, 46.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "02_bannow_bay")

	# 03 road / path read (N–S road + west fork signage)
	player.global_position = Vector3(0.0, 0.1, 8.0)
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(8.0, 6.5, 16.0), Vector3(-6.0, 1.0, 0.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_road_path")

	# 04 home túath / ringfort link
	player.global_position = Vector3(-30.0, 0.1, -2.0)
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(-24.0, 7.0, 10.0), Vector3(-38.0, 2.0, -2.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_home_tuath")

	# 05 monastic stub landmark
	player.global_position = Vector3(20.0, 0.1, -22.0)
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(14.0, 8.0, -14.0), Vector3(24.0, 4.0, -26.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_monastic_stub")

	print("CAPTURE_LEINSTER_DONE")
	quit(0)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("WROTE ", path, " err=", err)
