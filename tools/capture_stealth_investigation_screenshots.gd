extends SceneTree
## Capture stealth investigation polish proof shots (staged poses).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/stealth-investigation"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "StealthInvestigationCapture"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.36, 0.46, 0.5)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.92, 0.88)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.38
	fill.rotation_degrees = Vector3(-18.0, -130.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(36, 36)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.4, 0.27)
	ground.material_override = gmat
	world.add_child(ground)
	# Collision floor so CharacterBody3Ds do not freefall out of frame.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	world.add_child(floor_body)
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40, 0.4, 40)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(floor_col)

	# Cover crate (kept clear of sentry framing)
	var cover := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(1.4, 1.1, 1.0)
	cover.mesh = cbox
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.45, 0.38, 0.28)
	cover.material_override = cmat
	world.add_child(cover)
	cover.global_position = Vector3(-2.5, 0.55, -1.5)

	var bog_mesh := MeshInstance3D.new()
	var bog_box := BoxMesh.new()
	bog_box.size = Vector3(7.5, 0.12, 5.5)
	bog_mesh.mesh = bog_box
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.13, 0.2, 0.12)
	bog_mesh.material_override = bmat
	world.add_child(bog_mesh)
	bog_mesh.global_position = Vector3(7.0, 0.06, 2.0)

	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	var sentry := (load("res://scenes/characters/npcs/sentry.tscn") as PackedScene).instantiate() as CharacterBody3D
	var corpse := (load("res://scenes/characters/npcs/draggable_corpse.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(sentry)
	world.add_child(corpse)
	# Keep staged poses — disable physics slide for screenshot framing.
	player.set_physics_process(false)
	sentry.set_physics_process(false)
	corpse.set_physics_process(false)
	# Always-visible proxy (packed sentry mesh can fail to shade in SubViewport captures).
	var proxy := MeshInstance3D.new()
	proxy.name = "SentryProxy"
	var sentry_cap := CapsuleMesh.new()
	sentry_cap.radius = 0.36
	sentry_cap.height = 1.7
	proxy.mesh = sentry_cap
	proxy.position = Vector3(0.0, 0.85, 0.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.78, 0.55, 0.16)
	proxy.material_override = sm
	sentry.add_child(proxy)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.17
	head.mesh = sph
	head.position = Vector3(0.0, 1.7, 0.0)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.55, 0.52, 0.45)
	head.material_override = hm
	sentry.add_child(head)
	var vis := sentry.get_node_or_null("Visual") as Node3D
	if vis:
		vis.visible = false
	print("SENTRY_SPAWNED pos=", sentry.global_position)

	var heat := Node.new()
	heat.set_script(load("res://systems/stealth/heat_tracker.gd"))
	heat.set("scan_interval", 9999.0)
	heat.set("investigation_delay", 2.0)
	heat.set("honor_coupling_enabled", false)
	world.add_child(heat)

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.current = true

	await process_frame
	await process_frame
	await process_frame

	var sensor := sentry.get_node("DetectionSensor")
	var cap := Label3D.new()
	cap.font_size = 40
	cap.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cap.modulate = Color(0.95, 0.92, 0.75)
	cap.outline_size = 6
	world.add_child(cap)

	# ========== 01 calm post — body in open, sentry unaware ==========
	player.global_position = Vector3(-2.8, 0.0, 1.5)
	player.rotation_degrees.y = -20.0
	sentry.global_position = Vector3(3.2, 0.0, -1.2)
	sentry.rotation_degrees.y = 180.0
	if sentry.has_method("_ready"):
		pass
	# Reset rest pose fields if present
	if "_rest_position" in sentry:
		sentry.set("_rest_position", sentry.global_position)
	if "_rest_yaw" in sentry:
		sentry.set("_rest_yaw", sentry.rotation.y)
	corpse.global_position = Vector3(4.0, 0.12, 2.4)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.0)
	heat.call("force_heat", 0.0, &"calm")
	cap.text = "01 Calm post — body in open"
	cap.global_position = Vector3(2.0, 3.4, 0.5)
	cam.global_position = Vector3(0.2, 3.6, 7.2)
	cam.look_at(Vector3(3.2, 1.0, 0.6), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "01_calm_body_open.png")

	# ========== 02 investigate start — telegraph + walk ==========
	sentry.global_position = Vector3(3.5, 0.0, 0.2)
	sentry.rotation_degrees.y = 20.0
	corpse.global_position = Vector3(4.6, 0.12, 2.6)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 1, 0.55)
	if sentry.has_method("begin_body_investigate"):
		sentry.call("begin_body_investigate", corpse, 1.8)
	if corpse.has_method("set_investigation"):
		corpse.call("set_investigation", true, 1.8)
	# Seed heat HUD investigating state via internal dicts if possible
	heat.set("_investigating", {corpse.get_instance_id(): 1.8})
	heat.set("_investigate_sentry", {corpse.get_instance_id(): sentry})
	heat.set("_investigate_total", {corpse.get_instance_id(): 2.0})
	heat.call("_refresh_hud", "investigating")
	heat.call("_refresh_progress_ui")
	heat.call("_flash_banner", "Sentry investigating body… 2.0s", Color(0.95, 0.8, 0.35))
	cap.text = "02 Investigate telegraph — walk-to-body"
	cap.global_position = Vector3(3.5, 3.5, 1.0)
	# Place sentry mid-approach so walk-to-body reads in frame
	sentry.global_position = Vector3(3.9, 0.0, 1.0)
	var face := corpse.global_position - sentry.global_position
	face.y = 0.0
	if face.length_squared() > 0.01:
		sentry.rotation.y = atan2(-face.x, -face.z)
	if sentry.has_method("update_body_investigate"):
		sentry.call("update_body_investigate", 1.6)
	cam.global_position = Vector3(-0.2, 4.0, 7.5)
	cam.look_at(Vector3(3.8, 1.0, 1.2), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "02_investigate_telegraph.png")

	# ========== 03 stand-off look — mid countdown ==========
	sentry.global_position = Vector3(4.0, 0.0, 1.1)
	var to_c := corpse.global_position - sentry.global_position
	to_c.y = 0.0
	if to_c.length_squared() > 0.01:
		sentry.rotation.y = atan2(-to_c.x, -to_c.z)
	if sentry.has_method("update_body_investigate"):
		sentry.call("update_body_investigate", 0.9)
	if corpse.has_method("set_investigation"):
		corpse.call("set_investigation", true, 0.9)
	heat.set("_investigating", {corpse.get_instance_id(): 0.9})
	heat.call("_refresh_hud", "investigating")
	heat.call("_refresh_progress_ui")
	cap.text = "03 Stand-off look — UNDER SCRUTINY"
	cap.global_position = Vector3(3.8, 3.5, 1.2)
	cam.global_position = Vector3(7.2, 3.6, 6.2)
	cam.look_at(Vector3(4.2, 1.05, 1.7), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "03_standoff_scrutiny.png")

	# ========== 04 discovered ==========
	if sentry.has_method("confirm_body_discovered"):
		sentry.call("confirm_body_discovered")
	if corpse.has_method("set_investigation"):
		corpse.call("set_investigation", false, 0.0)
	if corpse.has_method("mark_discovered"):
		corpse.call("mark_discovered")
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 2, 1.0)
	heat.set("_investigating", {})
	heat.set("_investigate_sentry", {})
	heat.set("_investigate_total", {})
	heat.call("force_heat", 28.0, &"body_seen")
	heat.call("_flash_banner", "BODY DISCOVERED — heat +28", Color(0.98, 0.3, 0.2))
	heat.call("_hide_progress_ui")
	if sentry.has_method("_on_awareness_changed"):
		sentry.call("_on_awareness_changed", 1, 2)
	cap.text = "04 BODY DISCOVERED — heat bump"
	cap.global_position = Vector3(3.8, 3.5, 1.2)
	cam.global_position = Vector3(1.4, 3.5, 6.5)
	cam.look_at(Vector3(4.0, 1.1, 1.6), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "04_body_discovered.png")

	# ========== 05 concealed calm ==========
	if corpse.has_method("mark_hidden"):
		# Use begin_hide path visually: move into bog and force hidden state
		corpse.global_position = Vector3(7.0, -0.4, 2.0)
		if corpse.get("state") != null:
			corpse.set("state", 3)  # HIDDEN
		if "_discovered" in corpse:
			corpse.set("_discovered", false)
		if "_under_investigation" in corpse:
			corpse.set("_under_investigation", false)
		if corpse.has_method("_refresh_labels"):
			corpse.call("_refresh_labels")
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.05)
	if "_investigate_label" in sentry and sentry.get("_investigate_label"):
		sentry.get("_investigate_label").visible = false
	sentry.global_position = Vector3(3.2, 0.0, -1.2)
	sentry.rotation_degrees.y = 180.0
	if sentry.has_method("_on_awareness_changed"):
		sentry.call("_on_awareness_changed", 2, 0)
	heat.call("force_heat", 18.0, &"bog_hide")
	heat.call("_flash_banner", "Body CONCEALED — heat eased", Color(0.45, 0.8, 0.5))
	cap.text = "05 Concealed in bog — heat eased"
	cap.global_position = Vector3(5.5, 3.3, 1.5)
	player.global_position = Vector3(5.2, 0.0, 3.5)
	cam.global_position = Vector3(3.0, 3.8, 8.0)
	cam.look_at(Vector3(6.0, 0.8, 1.5), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "05_concealed_calm.png")

	# ========== 06 HUD progress close-up (mid investigate) ==========
	corpse.global_position = Vector3(4.6, 0.12, 2.6)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if corpse.get("state") != null:
		corpse.set("state", 0)  # GROUND
	if "_visual" in corpse and corpse.get("_visual"):
		corpse.get("_visual").scale = Vector3.ONE
	sentry.global_position = Vector3(3.8, 0.0, 0.9)
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 1, 0.6)
	if sentry.has_method("begin_body_investigate"):
		sentry.call("begin_body_investigate", corpse, 1.2)
	if corpse.has_method("set_investigation"):
		corpse.call("set_investigation", true, 1.2)
	heat.set("_investigating", {corpse.get_instance_id(): 1.2})
	heat.set("_investigate_sentry", {corpse.get_instance_id(): sentry})
	heat.set("_investigate_total", {corpse.get_instance_id(): 2.0})
	heat.call("force_heat", 5.0, &"stirred")
	heat.call("_refresh_hud", "investigating")
	heat.call("_refresh_progress_ui")
	heat.call("_flash_banner", "Sentry investigating body… 1.2s", Color(0.95, 0.8, 0.35))
	cap.text = "06 HUD — investigate progress bar"
	cap.global_position = Vector3(3.5, 3.6, 1.0)
	cam.global_position = Vector3(-0.5, 4.2, 6.0)
	cam.look_at(Vector3(3.5, 1.4, 1.2), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "06_hud_progress.png")

	print("Stealth investigation screenshots written to ", out_dir)
	quit(0)


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
	await create_timer(0.08).timeout


func _shot(vp: SubViewport, out_dir: String, filename: String) -> void:
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	var path := out_dir.path_join(filename)
	var err := img.save_png(path)
	if err != OK:
		push_error("Failed to save %s (%s)" % [path, str(err)])
	else:
		print("Wrote ", path)
