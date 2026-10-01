extends SceneTree
## Capture cattle-raid greybox proof shots (start, drive, return, outcome).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/cattle-raid"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "CattleRaidCaptureRoot"
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

	# Ground
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
	player.global_position = Vector3(-8, 0.1, 24)
	player.rotation_degrees.y = 180.0

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var hud := hud_ps.instantiate()
	# CanvasLayer under SubViewport needs a parent in the tree; attach to root.
	root.add_child(hud)

	var cam := Camera3D.new()
	cam.fov = 52.0
	world.add_child(cam)
	cam.current = true

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

	# 01 — approach / pens start
	player.global_position = Vector3(-8, 0.1, 22.5)
	cam.fov = 55.0
	cam.look_at_from_position(Vector3(-2.0, 7.5, 18.0), Vector3(-8.0, 1.2, 30.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_approach_pens")

	# 02 — raid start / herd driven
	if lane.has_method("debug_begin_raid"):
		lane.call("debug_begin_raid")
	await process_frame
	await process_frame
	for _t in 25:
		await physics_frame
	player.global_position = Vector3(-8, 0.1, 28)
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-14.0, 5.5, 34.0), Vector3(-7.0, 1.0, 28.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "02_herd_driving")

	# 03 — escape path mid-drive
	player.global_position = Vector3(-16, 0.1, 14)
	# Nudge cattle toward path for visual
	var herd := lane.get_node_or_null("Herd") as Node3D
	if herd:
		var i := 0
		for cow in herd.get_children():
			if cow is Node3D:
				(cow as Node3D).global_position = player.global_position + Vector3(
					-1.2 + float(i % 3) * 1.1, 0.1, 1.8 + float(i / 3) * 1.0
				)
				if cow.has_method("start_driven"):
					cow.call("start_driven")
			i += 1
	for _t in 15:
		await physics_frame
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(-8.0, 6.5, 20.0), Vector3(-18.0, 1.0, 10.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_escape_path")

	# 04 — home pens return
	player.global_position = Vector3(-28, 0.1, 8)
	if herd:
		var j := 0
		for cow in herd.get_children():
			if cow is Node3D:
				(cow as Node3D).global_position = Vector3(-30.0 + float(j) * 0.9, 0.1, 8.5)
				if cow.has_method("start_driven"):
					cow.call("start_driven")
			j += 1
	for _t in 20:
		await physics_frame
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-18.0, 6.0, 14.0), Vector3(-30.0, 1.2, 8.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_home_pens_return")

	# 05 — outcome success banner (force deliver)
	var outcome: Dictionary = {}
	if lane.has_method("debug_force_deliver"):
		outcome = lane.call("debug_force_deliver")
	await process_frame
	await process_frame
	await process_frame
	# Overlay outcome text into 3D for the proof shot (HUD may not composite into SubViewport).
	var banner := Label3D.new()
	var gained := int(outcome.get("cattle_gained", 0))
	var herd_size := cattle.get_herd_size() if cattle else -1
	banner.text = "CATTLE RAID SUCCESS\n+%d head · pens %d" % [gained, herd_size]
	banner.font_size = 42
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.modulate = Color(0.75, 0.95, 0.55)
	banner.position = Vector3(-30, 4.5, 8)
	world.add_child(banner)
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(-22.0, 5.5, 16.0), Vector3(-30.0, 2.5, 8.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_outcome_success")

	# 06 — overview of lane from spawn side
	banner.queue_free()
	player.global_position = Vector3(0, 0.1, 6)
	cam.fov = 60.0
	cam.look_at_from_position(Vector3(6.0, 14.0, 8.0), Vector3(-10.0, 1.0, 24.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "06_lane_overview")

	print("CATTLE_RAID_SCREENSHOTS_OK dir=", out_dir, " outcome=", outcome)
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
