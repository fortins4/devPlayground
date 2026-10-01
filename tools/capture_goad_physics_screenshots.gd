extends SceneTree
## Capture goad-physics drove proof shots → riocht-builds/screenshots/goad-physics/


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-physics"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "GoadPhysicsCaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.46, 0.55, 0.6)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.9, 0.84)
	environment.ambient_light_energy = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.7, 0.72, 0.65)
	environment.fog_density = 0.0012
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.38
	fill.rotation_degrees = Vector3(-22.0, -125.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var gmesh := BoxMesh.new()
	gmesh.size = Vector3(80, 0.15, 80)
	ground.mesh = gmesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.33, 0.41, 0.26)
	gmat.roughness = 0.95
	ground.set_surface_override_material(0, gmat)
	ground.position.y = -0.08
	world.add_child(ground)

	var lane_ps := load("res://scenes/world/raid/cattle_raid_lane.tscn") as PackedScene
	var ring_ps := load("res://scenes/world/ringfort/ringfort.tscn") as PackedScene
	var player_ps := load("res://scenes/characters/player/player.tscn") as PackedScene
	var hud_ps := load("res://scenes/ui/cattle_raid_hud.tscn") as PackedScene

	var lane := lane_ps.instantiate() as Node3D
	lane.position = Vector3(-8, 0, 26)
	world.add_child(lane)

	var ringfort := ring_ps.instantiate() as Node3D
	ringfort.position = Vector3(-24, 0, 0)
	world.add_child(ringfort)

	var player := player_ps.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3(-8, 0.1, 28)
	player.rotation_degrees.y = 0.0

	var combat := player.get_node_or_null("CombatSystem")
	if combat and combat.has_method("set_weapon"):
		combat.call("set_weapon", 2)  # GOAD

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var hud := hud_ps.instantiate()
	root.add_child(hud)

	var cam := Camera3D.new()
	cam.fov = 52.0
	world.add_child(cam)
	cam.current = true

	# Tip banner (SubViewport may not composite CanvasLayer HUD reliably).
	var tip := Label3D.new()
	tip.text = "GOAD READY  ·  3 / Q cycle  ·  LMB prod"
	tip.font_size = 36
	tip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tip.modulate = Color(0.95, 0.88, 0.45)
	tip.position = Vector3(-8, 4.2, 30)
	world.add_child(tip)

	await process_frame
	await process_frame
	await process_frame

	if ringfort.has_method("_find_player_deferred"):
		ringfort.call("_find_player_deferred")
	if lane.has_method("_deferred_bind"):
		lane.call("_deferred_bind")

	for _t in 20:
		await physics_frame

	var cattle: CattleEconomy = ringfort.get_node("CattleEconomy") as CattleEconomy
	var herd := lane.get_node_or_null("Herd") as Node3D

	# 01 — goad ready at pens
	player.global_position = Vector3(-8, 0.1, 28)
	player.rotation_degrees.y = 180.0
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-2.0, 5.5, 34.0), Vector3(-8.0, 1.2, 29.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_goad_ready")

	# Begin raid (herd, not auto-drove)
	if lane.has_method("debug_begin_raid"):
		lane.call("debug_begin_raid")
	await process_frame
	await process_frame
	for _t in 10:
		await physics_frame

	# 02 — prodding herd (apply goad + spark)
	tip.text = "PRODDING  ·  goad impulse + peel"
	tip.position = Vector3(-8, 4.2, 32)
	player.global_position = Vector3(-8, 0.1, 31.2)
	player.rotation_degrees.y = 180.0
	if herd:
		var n := 0
		for cow in herd.get_children():
			if cow is Node3D and cow.has_method("apply_goad"):
				(cow as Node3D).global_position = Vector3(-9.5 + float(n) * 1.15, 0.1, 29.2)
				cow.call("apply_goad", player.global_position, Vector3(0.15, 0, -1).normalized(), 1.25, &"light" if n < 2 else &"heavy")
				n += 1
	for _t in 10:
		await physics_frame
	# Re-seat slightly so impulse peel is readable in-frame.
	if herd:
		var n2 := 0
		for cow in herd.get_children():
			if cow is Node3D and bool(cow.get("driven")):
				(cow as Node3D).global_position = Vector3(-9.8 + float(n2) * 1.25, 0.1, 27.8 - float(n2 % 2) * 0.6)
				if cow is CharacterBody3D:
					(cow as CharacterBody3D).velocity = Vector3.ZERO
			n2 += 1
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(-15.5, 6.2, 36.5), Vector3(-8.0, 1.0, 28.5), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "02_prodding_herd")

	# 03 — cows peeling / steering
	tip.text = "PEEL / STEER  ·  lateral goad fan"
	tip.position = Vector3(-12, 4.0, 22)
	player.global_position = Vector3(-9.5, 0.1, 25.5)
	player.rotation_degrees.y = 40.0
	if herd:
		var i := 0
		for cow in herd.get_children():
			if cow is Node3D and cow.has_method("apply_goad"):
				var side := 1.0 if (i % 2) == 0 else -1.0
				(cow as Node3D).global_position = Vector3(-11.5 + float(i) * 1.4, 0.1, 23.5 - float(i) * 0.55)
				cow.call("apply_goad", player.global_position, Vector3(-0.55 * side, 0, -0.85).normalized(), 1.5, &"heavy")
			i += 1
	for _t in 8:
		await physics_frame
	if herd:
		var i2 := 0
		for cow in herd.get_children():
			if cow is Node3D:
				var side2 := 1.0 if (i2 % 2) == 0 else -1.0
				(cow as Node3D).global_position = Vector3(-12.0 + float(i2) * 1.5 + side2 * 0.7, 0.1, 22.8 - float(i2) * 0.65)
				if cow is CharacterBody3D:
					(cow as CharacterBody3D).velocity = Vector3.ZERO
				if cow.has_method("start_driven"):
					cow.call("start_driven")
			i2 += 1
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-4.5, 6.5, 28.0), Vector3(-11.5, 1.0, 21.5), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_cows_peeling")

	# 04 — drove in motion along escape path
	tip.text = "DROVE IN MOTION  ·  path bias + goad"
	tip.position = Vector3(-16, 4.2, 16)
	player.global_position = Vector3(-15.5, 0.1, 15.5)
	player.rotation_degrees.y = 40.0
	if herd:
		var j := 0
		for cow in herd.get_children():
			if cow is Node3D:
				(cow as Node3D).global_position = Vector3(-17.2 + float(j % 3) * 1.15, 0.1, 17.0 - float(j / 3) * 1.2 - float(j) * 0.15)
				if cow.has_method("start_driven"):
					cow.call("start_driven")
				if cow is CharacterBody3D:
					(cow as CharacterBody3D).velocity = Vector3(-1.2, 0, -1.0)
			j += 1
	for _t in 6:
		await physics_frame
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(-9.0, 7.0, 22.0), Vector3(-17.0, 1.0, 14.5), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_drove_in_motion")

	# 05 — home delivery
	tip.text = "HOME DELIVERY  ·  ≥3 head"
	player.global_position = Vector3(-28, 0.1, 8)
	if herd:
		var k := 0
		for cow in herd.get_children():
			if cow is Node3D:
				(cow as Node3D).global_position = Vector3(-30.0 + float(k) * 0.9, 0.1, 8.5)
				if cow.has_method("start_driven"):
					cow.call("start_driven")
			k += 1
	for _t in 16:
		await physics_frame
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-18.0, 6.0, 14.0), Vector3(-30.0, 1.2, 8.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_home_delivery")

	# 06 — outcome success
	var outcome: Dictionary = {}
	if lane.has_method("debug_force_deliver"):
		outcome = lane.call("debug_force_deliver")
	await process_frame
	await process_frame
	var gained := int(outcome.get("cattle_gained", 0))
	var herd_size := cattle.get_herd_size() if cattle else -1
	tip.text = "RAID SUCCESS  ·  +%d head · pens %d" % [gained, herd_size]
	tip.modulate = Color(0.75, 0.95, 0.55)
	tip.position = Vector3(-30, 4.5, 8)
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(-22.0, 5.5, 16.0), Vector3(-30.0, 2.5, 8.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "06_outcome_success")

	print("GOAD_PHYSICS_SCREENSHOTS_OK dir=", out_dir, " outcome=", outcome)
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
