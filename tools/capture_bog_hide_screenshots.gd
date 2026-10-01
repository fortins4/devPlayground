extends SceneTree
## Capture bog body-hide prototype proof shots (staged poses).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/bog"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "BogHideCapture"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.4, 0.5, 0.55)
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
	plane.size = Vector2(36, 36)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.33, 0.41, 0.28)
	ground.material_override = gmat
	world.add_child(ground)

	# Bog patch (visual)
	var bog_mesh := MeshInstance3D.new()
	var bog_box := BoxMesh.new()
	bog_box.size = Vector3(8.0, 0.12, 6.0)
	bog_mesh.mesh = bog_box
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.15, 0.24, 0.14)
	bog_mesh.material_override = bmat
	world.add_child(bog_mesh)
	bog_mesh.global_position = Vector3(5.0, 0.06, 1.5)

	var bog_zone := Area3D.new()
	bog_zone.set_script(load("res://systems/stealth/bog_zone.gd"))
	bog_zone.set("label_text", "Bog — E to hide")
	world.add_child(bog_zone)
	bog_zone.global_position = Vector3(5.0, 0.06, 1.5)
	var bog_col := CollisionShape3D.new()
	var bog_shape := BoxShape3D.new()
	bog_shape.size = Vector3(8.0, 1.2, 6.0)
	bog_col.shape = bog_shape
	bog_col.position.y = 0.4
	bog_zone.add_child(bog_col)

	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	var sentry := (load("res://scenes/characters/npcs/sentry.tscn") as PackedScene).instantiate() as CharacterBody3D
	var corpse := (load("res://scenes/characters/npcs/draggable_corpse.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(sentry)
	world.add_child(corpse)

	var heat := Node.new()
	heat.set_script(load("res://systems/stealth/heat_tracker.gd"))
	# Freeze auto-scan during staged shots; we force heat/labels.
	heat.set("scan_interval", 9999.0)
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

	# ========== 01 body visible ==========
	player.global_position = Vector3(-2.0, 0.0, 2.2)
	player.rotation_degrees.y = 50.0
	corpse.global_position = Vector3(0.8, 0.12, 0.6)
	corpse.rotation = Vector3(deg_to_rad(82.0), deg_to_rad(20.0), 0.0)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	sentry.global_position = Vector3(1.5, 0.0, -4.0)
	_face_toward(sentry, corpse.global_position)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.05)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"boot")
	cam.look_at_from_position(Vector3(4.5, 2.4, 5.5), Vector3(0.5, 0.8, 0.3), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "01_body_visible")

	# ========== 02 dragging ==========
	sentry.global_position = Vector3(-6.0, 0.0, -5.0)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.0)
	player.global_position = Vector3(1.0, 0.0, 3.2)
	player.rotation_degrees.y = -30.0
	corpse.set("state", 0)
	corpse.set("_discovered", false)
	if corpse.has_method("start_drag"):
		corpse.call("start_drag", player)
	# Let follow settle
	for _i in 12:
		await physics_frame
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"dragging")
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	cam.look_at_from_position(Vector3(5.0, 2.2, 6.0), Vector3(1.0, 0.7, 2.4), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "02_dragging")

	# ========== 03 hidden in bog ==========
	if player.has_method("end_drag"):
		player.call("end_drag")
	corpse.set("state", 3)  # HIDDEN
	corpse.set("_discovered", false)
	corpse.global_position = Vector3(5.0, -0.55, 1.5)
	corpse.rotation = Vector3(deg_to_rad(88.0), 0.0, 0.0)
	var vis := corpse.get_node_or_null("Visual") as Node3D
	if vis:
		vis.scale = Vector3(1.0, 0.32, 1.0)
		# Darken / fade mats
		for child in vis.get_children():
			if child is MeshInstance3D:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.22, 0.16, 0.35)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				(child as MeshInstance3D).material_override = m
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	player.global_position = Vector3(3.4, 0.0, 3.5)
	player.rotation_degrees.y = 40.0
	sentry.global_position = Vector3(-3.5, 0.0, -3.0)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.04)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"bog_hide")
	cam.look_at_from_position(Vector3(8.5, 2.6, 6.5), Vector3(4.5, 0.35, 1.6), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "03_hidden_in_bog")

	# ========== 04 heat discovered contrast ==========
	# Restore opaque ground body in open, sentry alert, heat stirred
	corpse.set("state", 0)
	corpse.set("_discovered", true)
	corpse.global_position = Vector3(1.2, 0.12, 0.4)
	corpse.rotation = Vector3(deg_to_rad(82.0), 15.0, 0.0)
	if vis:
		vis.scale = Vector3.ONE
		for child in vis.get_children():
			if child is MeshInstance3D:
				var m2 := StandardMaterial3D.new()
				m2.albedo_color = Color(0.38, 0.28, 0.24)
				(child as MeshInstance3D).material_override = m2
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	sentry.global_position = Vector3(1.4, 0.0, -3.6)
	_face_toward(sentry, corpse.global_position)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 2, 1.0)
	player.global_position = Vector3(-2.5, 0.0, 2.8)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 28.0, &"body_seen")
	cam.look_at_from_position(Vector3(5.2, 2.5, 4.5), Vector3(1.0, 1.0, -0.6), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "04_heat_discovered")

	# ========== 05 heat concealed calm contrast ==========
	corpse.set("state", 3)
	corpse.set("_discovered", false)
	corpse.global_position = Vector3(5.0, -0.6, 1.5)
	if vis:
		vis.scale = Vector3(1.0, 0.3, 1.0)
		for child in vis.get_children():
			if child is MeshInstance3D:
				var m3 := StandardMaterial3D.new()
				m3.albedo_color = Color(0.18, 0.2, 0.14, 0.3)
				m3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				(child as MeshInstance3D).material_override = m3
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	sentry.global_position = Vector3(-2.0, 0.0, -3.5)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.02)
	player.global_position = Vector3(3.2, 0.0, 3.6)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"concealed")
	cam.look_at_from_position(Vector3(8.8, 2.7, 6.8), Vector3(4.6, 0.4, 1.7), Vector3.UP)
	await _settle()
	await _shot(vp, out_dir, "05_heat_concealed_calm")

	print("CAPTURE_BOG_HIDE_DONE")
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
