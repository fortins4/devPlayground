extends SceneTree
## Capture sparring foe face-block vs flank (SubViewport).


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/sparring-foe"
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

	var label := Label3D.new()
	label.font_size = 48
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 2.55, 0.0)
	dummy.add_child(label)

	await process_frame
	await process_frame

	var pcombat := player.get_node("CombatSystem") as CombatSystem
	var dcombat := dummy.get_node("CombatSystem") as CombatSystem
	dcombat.enable_block = true
	pcombat.enable_hit_feedback = false
	dcombat.enable_hit_feedback = false

	# Face-on
	player.global_position = Vector3(0.15, 0.0, 0.0)
	player.rotation_degrees.y = 0.0
	dummy.global_position = Vector3(0.0, 0.0, -1.55)
	dummy.rotation_degrees.y = 180.0
	dcombat.set_blocking(true)
	dcombat.health = dcombat.max_health
	label.text = "FACE BLOCK READY"
	cam.look_at_from_position(Vector3(2.4, 1.55, 1.2), Vector3(0.1, 1.1, -0.8), Vector3.UP)
	await _shot(vp, out_dir, "01_face_block_ready")

	dcombat.apply_damage(18.0, player, true)
	label.text = "FACE BLOCKED (mitigated)"
	await _shot(vp, out_dir, "02_face_hit_mitigated")

	# Flank from right
	dcombat.health = dcombat.max_health
	dcombat.set_blocking(true)
	player.global_position = Vector3(1.55, 0.0, -1.55)
	player.rotation_degrees.y = -90.0
	label.text = "FLANK SETUP"
	cam.look_at_from_position(Vector3(2.8, 1.6, -0.2), Vector3(0.6, 1.1, -1.4), Vector3.UP)
	await _shot(vp, out_dir, "03_flank_setup")

	dcombat.apply_damage(18.0, player, false)
	label.text = "FLANK HIT (full)"
	await _shot(vp, out_dir, "04_flank_hit")

	# Left charge vs blocker face
	player.global_position = Vector3(0.2, 0.0, 0.05)
	player.rotation_degrees.y = 10.0
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	dummy.rotation_degrees.y = 180.0
	dcombat.health = dcombat.max_health
	dcombat.set_blocking(true)
	pcombat.begin_charge()
	pcombat.set_charge_direction(CombatSystem.StrikeDirection.LEFT)
	for _i in 40:
		await physics_frame
	label.text = "LEFT CHARGE vs FACE"
	cam.look_at_from_position(Vector3(2.5, 1.55, 1.35), Vector3(0.2, 1.1, -0.7), Vector3.UP)
	await _shot(vp, out_dir, "05_left_charge_vs_face")

	pcombat.release_charged_attack()
	await process_frame
	await process_frame
	await process_frame
	label.text = "LEFT RELEASE"
	await _shot(vp, out_dir, "06_left_release")

	print("SPARRING_FOE_CAPTURE_OK ", out_dir)
	quit(0)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	print("WROTE ", path, " err=", img.save_png(path))
