extends SceneTree
## Capture FULL bog body-drag proof shots (staged poses).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/bog-full"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "BogFullCapture"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.38, 0.48, 0.52)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.92, 0.88)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20.0, -120.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.33, 0.41, 0.28)
	ground.material_override = gmat
	world.add_child(ground)

	# Bog patch
	var bog_mesh := MeshInstance3D.new()
	var bog_box := BoxMesh.new()
	bog_box.size = Vector3(9.0, 0.14, 6.5)
	bog_mesh.mesh = bog_box
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.14, 0.22, 0.13)
	bog_mesh.material_override = bmat
	world.add_child(bog_mesh)
	bog_mesh.global_position = Vector3(6.0, 0.07, 1.5)

	var bog_zone := Area3D.new()
	bog_zone.set_script(load("res://systems/stealth/bog_zone.gd"))
	bog_zone.set("label_text", "Bog — release E to hide")
	bog_zone.set("hide_sink_depth", 1.35)
	bog_zone.set("hide_duration", 1.4)
	world.add_child(bog_zone)
	bog_zone.global_position = Vector3(6.0, 0.07, 1.5)
	var bog_col := CollisionShape3D.new()
	var bog_shape := BoxShape3D.new()
	bog_shape.size = Vector3(9.0, 1.2, 6.5)
	bog_col.shape = bog_shape
	bog_col.position.y = 0.4
	bog_zone.add_child(bog_col)

	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	var sentry := (load("res://scenes/characters/npcs/sentry.tscn") as PackedScene).instantiate() as CharacterBody3D
	var dummy := (load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene).instantiate() as CharacterBody3D
	var corpse := (load("res://scenes/characters/npcs/draggable_corpse.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(sentry)
	world.add_child(dummy)
	world.add_child(corpse)

	var heat := Node.new()
	heat.set_script(load("res://systems/stealth/heat_tracker.gd"))
	heat.set("scan_interval", 9999.0)
	heat.set("honor_coupling_enabled", false)
	world.add_child(heat)

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 46.0
	world.add_child(cam)
	cam.current = true

	await process_frame
	await process_frame
	await process_frame

	var sensor := sentry.get_node("DetectionSensor")

	# ========== 01 kill → corpse ==========
	dummy.global_position = Vector3(-1.5, 0.0, -2.0)
	dummy.rotation_degrees = Vector3(0.0, 30.0, 78.0)
	dummy.visible = false  # replaced by corpse spawn read
	player.global_position = Vector3(-3.2, 0.0, -0.8)
	player.rotation_degrees.y = 40.0
	corpse.global_position = Vector3(-1.2, 0.12, -1.8)
	corpse.rotation = Vector3(deg_to_rad(82.0), deg_to_rad(25.0), 0.0)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	corpse.set_meta("spawn_source", "combat_kill")
	# Floating caption
	var cap := Label3D.new()
	cap.text = "Combat kill → draggable corpse"
	cap.font_size = 42
	cap.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cap.modulate = Color(0.95, 0.85, 0.55)
	world.add_child(cap)
	cap.global_position = Vector3(-1.0, 2.4, -1.5)
	sentry.global_position = Vector3(8.0, 0.0, -6.0)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"boot")
	cam.look_at_from_position(Vector3(2.5, 2.5, 2.8), Vector3(-1.5, 0.7, -1.5), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "01_kill_to_corpse")
	cap.queue_free()

	# ========== 02 long drag ==========
	dummy.visible = false
	sentry.global_position = Vector3(-8.0, 0.0, -6.0)
	player.global_position = Vector3(1.5, 0.0, 4.0)
	player.rotation_degrees.y = -40.0
	corpse.set("state", 0)
	corpse.set("_discovered", false)
	corpse.global_position = Vector3(1.5, 0.2, 5.2)
	if corpse.has_method("start_drag"):
		corpse.call("start_drag", player)
	# Staged shot: keep DRAGGED without requiring held Interact.
	corpse.set("_hold_grabbed", false)
	# Simulate long drag trail toward bog
	for i in 22:
		player.global_position = player.global_position.lerp(Vector3(4.2, 0.0, 2.6), 0.1)
		await physics_frame
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	var drag_cap := Label3D.new()
	drag_cap.text = "Hold E drag · body follows"
	drag_cap.font_size = 36
	drag_cap.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	drag_cap.modulate = Color(0.95, 0.9, 0.5)
	world.add_child(drag_cap)
	drag_cap.global_position = player.global_position + Vector3(0.0, 2.6, 0.0)
	var focus := (player.global_position + corpse.global_position) * 0.5
	cam.look_at_from_position(focus + Vector3(4.5, 2.8, 5.5), focus + Vector3(0.0, 0.6, 0.0), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "02_long_drag")
	drag_cap.queue_free()

	# ========== 03 hide / concealed ==========
	if player.has_method("end_drag"):
		player.call("end_drag")
	# Trigger splash + deep hide pose
	if bog_zone.has_method("_play_splash"):
		bog_zone.call("_play_splash", Vector3(6.0, 0.1, 1.5))
	corpse.set("state", 3)  # HIDDEN
	corpse.set("_discovered", false)
	corpse.global_position = Vector3(6.0, -1.05, 1.5)
	corpse.rotation = Vector3(deg_to_rad(88.0), 0.0, 0.0)
	var vis := corpse.get_node_or_null("Visual") as Node3D
	if vis:
		vis.scale = Vector3(1.05, 0.22, 1.05)
		for child in vis.get_children():
			if child is MeshInstance3D:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.14, 0.18, 0.12, 0.18)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				(child as MeshInstance3D).material_override = m
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	player.global_position = Vector3(4.0, 0.0, 3.6)
	player.rotation_degrees.y = 35.0
	sentry.global_position = Vector3(-4.0, 0.0, -3.0)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.03)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"bog_hide")
	if heat.has_method("_flash_banner"):
		heat.call("_flash_banner", "Body CONCEALED — heat eased", Color(0.45, 0.8, 0.5))
	cam.look_at_from_position(Vector3(10.0, 2.8, 6.8), Vector3(5.5, 0.2, 1.6), Vector3.UP)
	await _settle()
	await process_frame
	await _shot(vp, out_dir, "03_hide_concealed")

	# ========== 04 discovered (vs concealed) ==========
	corpse.set("state", 0)
	corpse.set("_discovered", true)
	corpse.set("discovery_count", 2)
	corpse.global_position = Vector3(1.0, 0.12, 0.5)
	corpse.rotation = Vector3(deg_to_rad(82.0), 15.0, 0.0)
	if vis:
		vis.scale = Vector3.ONE
		vis.rotation = Vector3.ZERO
		for child in vis.get_children():
			if child is MeshInstance3D:
				var m2 := StandardMaterial3D.new()
				m2.albedo_color = Color(0.38, 0.28, 0.24)
				(child as MeshInstance3D).material_override = m2
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	sentry.global_position = Vector3(1.2, 0.0, -3.4)
	_face_toward(sentry, corpse.global_position)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 2, 1.0)
	player.global_position = Vector3(-2.8, 0.0, 2.6)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 40.0, &"body_seen")
	if heat.has_method("_flash_banner"):
		heat.call("_flash_banner", "BODY DISCOVERED — heat +28", Color(0.98, 0.3, 0.2))
	cam.look_at_from_position(Vector3(5.5, 2.6, 4.8), Vector3(1.0, 1.0, -0.5), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "04_discovered")

	# ========== 05 concealed calm contrast ==========
	corpse.set("state", 3)
	corpse.set("_discovered", false)
	corpse.set("discovery_count", 0)
	corpse.global_position = Vector3(6.0, -1.1, 1.5)
	if vis:
		vis.scale = Vector3(1.05, 0.2, 1.05)
		for child in vis.get_children():
			if child is MeshInstance3D:
				var m3 := StandardMaterial3D.new()
				m3.albedo_color = Color(0.12, 0.16, 0.1, 0.15)
				m3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				(child as MeshInstance3D).material_override = m3
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	sentry.global_position = Vector3(-2.5, 0.0, -3.5)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.02)
	player.global_position = Vector3(3.8, 0.0, 3.8)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"concealed")
	if heat.has_method("_flash_banner"):
		heat.call("_flash_banner", "CONCEALED — discovery skipped", Color(0.4, 0.75, 0.45))
	cam.look_at_from_position(Vector3(10.2, 2.9, 7.0), Vector3(5.6, 0.25, 1.7), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "05_concealed_calm")

	print("CAPTURE_BOG_FULL_DONE")
	quit(0)


func _face_toward(node: Node3D, target: Vector3) -> void:
	var to := target - node.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	node.rotation.y = atan2(-to.x, -to.z)
	node.rotation.x = 0.0
	node.rotation.z = 0.0


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("WROTE ", path, " err=", err)
