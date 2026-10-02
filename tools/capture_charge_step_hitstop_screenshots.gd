extends SceneTree
## Capture #5 charge footwork step + #6 charged hit-stop juice (mirror directional-hatchet capture).


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/charge-step-hitstop"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var world := Node3D.new()
	world.name = "ChargeStepHitstopCapture"
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.44, 0.54, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.92, 0.96)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-50.0, 38.0, 0.0)
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.38
	fill.rotation_degrees = Vector3(-18.0, -85.0, 0.0)
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 22)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.27, 0.35, 0.23)
	ground.material_override = gmat
	world.add_child(ground)

	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	player.rotation_degrees.y = 20.0
	player.set_physics_process(false)
	player.set_process(false)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var dummy := (load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(dummy)
	dummy.global_position = Vector3(0.2, 0.0, -1.55)
	dummy.rotation_degrees.y = 180.0
	dummy.set_physics_process(false)
	dummy.set_process(false)
	if dummy is CharacterBody3D:
		(dummy as CharacterBody3D).velocity = Vector3.ZERO

	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(2.4, 1.65, 2.2), Vector3(0.15, 1.15, -0.4), Vector3.UP)
	cam.current = true

	var label := Label3D.new()
	label.font_size = 56
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.95, 0.7)
	label.outline_size = 10
	label.position = Vector3(0.0, 2.2, 0.0)
	player.add_child(label)

	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var pcombat := player.get_node("CombatSystem") as CombatSystem
	var dcombat := dummy.get_node("CombatSystem") as CombatSystem
	pcombat.set_weapon(CombatSystem.Weapon.HATCHET)
	pcombat.hit_stop_light = 0.0
	pcombat.hit_stop_heavy = 0.0
	pcombat.hit_stop_charged = 0.0
	if "enable_hit_feedback" in pcombat:
		pcombat.enable_hit_feedback = false
	dcombat.enable_block = false

	# 01 charge ready
	pcombat.begin_charge()
	pcombat.charge_direction = CombatSystem.StrikeDirection.TOP
	pcombat.charge_time = pcombat.charge_full_secs
	pcombat.charge_ratio = 1.0
	pcombat.call("_update_charge_pose", 1.0, CombatSystem.StrikeDirection.TOP)
	label.text = "CHARGE READY — tap WASD step"
	await _shot(vp, out_dir, "01_charge_ready_for_step")

	# 02 stepped while charging
	player.global_position = Vector3(0.55, 0.0, 0.15)
	label.text = "CHARGE STEP (no cancel)"
	await _shot(vp, out_dir, "02_charge_footwork_step")

	# 03 charged impact
	player.global_position = Vector3(0.05, 0.0, 0.05)
	pcombat.is_charging = false
	pcombat.charge_ratio = 0.0
	pcombat.try_attack(&"heavy", CombatSystem.StrikeDirection.TOP, 1.0)
	await process_frame
	await process_frame
	dcombat.apply_damage(32.0, player, true, CombatSystem.StrikeDirection.TOP)
	var wv := player.get_node_or_null("WeaponVisual") as Node3D
	if wv:
		wv.position += Vector3(0.0, 0.06, -0.1)
	label.text = "CHARGED HIT-STOP + JUICE"
	await _shot(vp, out_dir, "03_charged_hit_impact")

	print("CHARGE_STEP_HITSTOP_CAPTURE_OK ", out_dir)
	quit(0)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	print("WROTE ", path, " bytes~ ", img.get_width(), "x", img.get_height(), " err=", img.save_png(path))
