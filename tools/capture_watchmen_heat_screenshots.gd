extends SceneTree
## Capture watchmen / raid-heat proof shots on the cattle lane.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/watchmen-heat"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "WatchmenHeatCaptureRoot"
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
	gmesh.size = Vector3(90, 0.15, 90)
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
	var heat_script := load("res://systems/stealth/heat_tracker.gd") as Script

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

	var heat := Node.new()
	heat.name = "HeatTracker"
	heat.set_script(heat_script)
	world.add_child(heat)

	var hud := hud_ps.instantiate()
	root.add_child(hud)

	var cam := Camera3D.new()
	cam.fov = 52.0
	world.add_child(cam)
	cam.current = true

	# Overlay labels for SubViewport (2D HUD may not composite).
	var overlay := Label3D.new()
	overlay.name = "ShotOverlay"
	overlay.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	overlay.font_size = 40
	overlay.modulate = Color(0.95, 0.9, 0.65)
	world.add_child(overlay)

	await process_frame
	await process_frame
	await process_frame

	if lane.has_method("_deferred_bind"):
		lane.call("_deferred_bind")
	# Ensure watchmen groups for bridge.
	var wr := lane.get_node_or_null("Watchmen")
	if wr:
		for c in wr.get_children():
			if c is Node3D and c.get_node_or_null("DetectionSensor"):
				c.add_to_group("raid_watchman")
				c.add_to_group("sentry")

	for _t in 25:
		await physics_frame

	# 01 — approach pens / lane with watchmen visible
	player.global_position = Vector3(-8, 0.1, 22.5)
	overlay.text = "Approach cattle pens\nWatchmen on the drove path"
	overlay.global_position = Vector3(-6, 4.2, 28)
	cam.fov = 55.0
	cam.look_at_from_position(Vector3(-1.0, 8.0, 18.0), Vector3(-10.0, 1.2, 30.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_approach_pens")

	# 02 — watchman idle (mid-path sentry + cone)
	player.global_position = Vector3(-16, 0.1, 18)
	overlay.text = "Watchman idle\n[UNAWARE] · vision cone"
	overlay.global_position = Vector3(-11, 4.0, 20)
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(-6.0, 5.5, 24.0), Vector3(-19.5, 1.4, 21.5), Vector3.UP)
	await process_frame
	for _t in 15:
		await physics_frame
	await _shot(vp, out_dir, "02_watchman_idle")

	# 03 — spotted mid-drove
	if lane.has_method("debug_begin_raid"):
		lane.call("debug_begin_raid")
	await process_frame
	await process_frame
	# Place player + herd near mid watchman and force spot.
	player.global_position = Vector3(-18, 0.1, 20)
	var herd := lane.get_node_or_null("Herd") as Node3D
	if herd:
		var i := 0
		for cow in herd.get_children():
			if cow is Node3D:
				(cow as Node3D).global_position = player.global_position + Vector3(
					-1.0 + float(i % 3) * 1.0, 0.1, 1.5 + float(i / 3) * 0.9
				)
				if cow.has_method("start_driven"):
					cow.call("start_driven")
			i += 1
	if lane.has_method("debug_force_watchman_spot"):
		lane.call("debug_force_watchman_spot")
	# Force mid watchman visual ALERT.
	var mid := lane.get_node_or_null("Watchmen/WatchmanMid")
	if mid:
		var sensor := mid.get_node_or_null("DetectionSensor")
		if sensor and sensor.has_method("force_awareness"):
			sensor.call("force_awareness", 2, 1.0)
	for _t in 20:
		await physics_frame
	var hval := float(heat.get("heat"))
	overlay.text = "SPOTTED mid-drove\nRAID ALARM · heat %d" % int(hval)
	overlay.modulate = Color(0.98, 0.35, 0.25)
	overlay.global_position = Vector3(-16, 4.5, 22)
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-10.0, 6.0, 28.0), Vector3(-19.0, 1.5, 21.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_spotted_mid_drove")

	# 04 — heat / alert UI (world labels stand in for HUD)
	overlay.text = "Heat %d / 100  [HOT]\n· RAID ALARM" % int(maxf(hval, 22.0))
	overlay.modulate = Color(0.95, 0.4, 0.28)
	overlay.global_position = Vector3(-14, 5.2, 24)
	var banner := Label3D.new()
	banner.text = "RAID ALARM — spotted mid-drove!"
	banner.font_size = 36
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.modulate = Color(0.98, 0.3, 0.22)
	banner.global_position = Vector3(-18, 3.2, 22)
	world.add_child(banner)
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(-8.0, 7.0, 30.0), Vector3(-16.0, 2.5, 22.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_heat_alert_ui")

	# 05 — calm success path (reset heat, deliver undetected)
	banner.queue_free()
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"calm")
	if heat.has_method("reset_raid_spot_state"):
		heat.call("reset_raid_spot_state")
	var bridge := lane.get_node_or_null("RaidHeatBridge")
	if bridge:
		bridge.set("fail_on_hot_heat", false)
		if bridge.has_method("reset_for_new_raid"):
			bridge.call("reset_for_new_raid")
	# Clear watchman awareness for calm look.
	if wr:
		for c in wr.get_children():
			var sensor2 = c.get_node_or_null("DetectionSensor") if c is Node else null
			if sensor2 and sensor2.has_method("force_awareness"):
				sensor2.call("force_awareness", 0, 0.0)
	if lane.has_method("_reset_raid"):
		lane.call("_reset_raid")
	await process_frame
	if lane.has_method("debug_begin_raid"):
		lane.call("debug_begin_raid")
	await process_frame
	var outcome: Dictionary = {}
	if lane.has_method("debug_force_deliver"):
		outcome = lane.call("debug_force_deliver")
	await process_frame
	await process_frame
	var gained := int(outcome.get("cattle_gained", 0))
	overlay.text = "Calm success path\nUNDETECTED · +%d cattle" % gained
	overlay.modulate = Color(0.7, 0.95, 0.55)
	overlay.global_position = Vector3(-28, 4.8, 8)
	cam.fov = 48.0
	cam.look_at_from_position(Vector3(-20.0, 6.0, 16.0), Vector3(-30.0, 1.5, 8.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_calm_success")

	# 06 — overview with watchmen along path
	overlay.text = "Cattle lane + watchmen\nPens → mid → home"
	overlay.modulate = Color(0.92, 0.85, 0.55)
	overlay.global_position = Vector3(-12, 6.0, 18)
	player.global_position = Vector3(0, 0.1, 8)
	cam.fov = 58.0
	cam.look_at_from_position(Vector3(8.0, 16.0, 10.0), Vector3(-16.0, 1.0, 20.0), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "06_lane_overview")

	print("WATCHMEN_HEAT_SCREENSHOTS_OK dir=", out_dir, " heat=", hval, " outcome=", outcome)
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
