extends SceneTree
## Capture switching guard faces.


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/switch-block-face"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.52, 0.60)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.2
	light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.26, 0.34, 0.22)
	ground.material_override = gmat
	world.add_child(ground)
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false
	var dummy := (load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(dummy)
	dummy.set_physics_process(false)
	dummy.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.current = true
	await process_frame
	await process_frame
	var dcombat := dummy.get_node("CombatSystem") as CombatSystem
	dcombat.enable_block = true
	player.global_position = Vector3(0.15, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.55)
	dummy.rotation_degrees.y = 180.0
	cam.look_at_from_position(Vector3(2.4, 1.55, 1.2), Vector3(0.1, 1.1, -0.8), Vector3.UP)
	for pair in [
		[CombatSystem.StrikeDirection.TOP, "01_guard_top"],
		[CombatSystem.StrikeDirection.LEFT, "02_guard_left"],
		[CombatSystem.StrikeDirection.RIGHT, "03_guard_right"],
	]:
		dcombat.set_blocking(true)
		if dummy.has_method("_set_guard_face"):
			dummy.call("_set_guard_face", pair[0])
		else:
			dcombat.set_guard_direction(pair[0])
		await _shot(vp, out_dir, pair[1])
	# Wrong face open
	dcombat.set_guard_direction(CombatSystem.StrikeDirection.TOP)
	dcombat.set_blocking(true)
	dcombat.apply_damage(18.0, player, true, CombatSystem.StrikeDirection.LEFT)
	await _shot(vp, out_dir, "04_wrong_face_hits")
	dcombat.health = dcombat.max_health
	dcombat.apply_damage(18.0, player, true, CombatSystem.StrikeDirection.TOP)
	await _shot(vp, out_dir, "05_matching_face_blocked")
	print("SWITCH_BLOCK_FACE_CAPTURE_OK ", out_dir)
	quit(0)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	print("WROTE ", "%s/%s.png" % [out_dir, name], " err=", img.save_png("%s/%s.png" % [out_dir, name]))
