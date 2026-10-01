extends SceneTree
## Capture crouch + detection greybox proof shots.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/stealth"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "StealthCaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.4, 0.5, 0.58)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.92, 0.95)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-48.0, 40.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20.0, -110.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 28)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.38, 0.26)
	ground.material_override = gmat
	world.add_child(ground)

	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	var cmesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 1.5, 0.7)
	cmesh.mesh = box
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.42, 0.36, 0.28)
	cmesh.material_override = cmat
	cover.add_child(cmesh)
	var ccol := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = box.size
	ccol.shape = cshape
	cover.add_child(ccol)
	world.add_child(cover)
	cover.global_position = Vector3(0.0, 0.75, -0.4)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var sentry_packed := load("res://scenes/characters/npcs/sentry.tscn") as PackedScene
	var player := player_packed.instantiate() as CharacterBody3D
	var sentry := sentry_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(sentry)

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

	# --- 01 crouch behind cover (side view so height drop reads) ---
	player.global_position = Vector3(-1.8, 0.0, 1.1)
	player.rotation_degrees.y = 35.0
	sentry.global_position = Vector3(1.0, 0.0, -3.6)
	sentry.rotation_degrees.y = 180.0
	_force_crouch(player, true)
	player.set("_noise_level", 0.0)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.04)
	cam.look_at_from_position(Vector3(3.8, 1.55, 3.4), Vector3(-0.6, 0.85, 0.2), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "01_crouch_behind_cover")

	# --- 02 undetected / unaware (peek blocked by cover) ---
	_force_crouch(player, false)
	player.global_position = Vector3(-1.5, 0.0, 0.85)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 0, 0.06)
	cam.look_at_from_position(Vector3(3.5, 1.9, 3.0), Vector3(-0.2, 1.1, -0.8), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "02_undetected_unaware")

	# --- 03 suspicious (player visible in cone, yellow) ---
	_force_crouch(player, true)
	player.global_position = Vector3(0.6, 0.0, -1.2)
	sentry.global_position = Vector3(0.8, 0.0, -4.0)
	_face_toward(sentry, player.global_position)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 1, 0.58)
	cam.look_at_from_position(Vector3(4.2, 2.0, 0.6), Vector3(0.5, 1.1, -2.4), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_suspicious")

	# --- 04 alerted (open LOS, red) ---
	_force_crouch(player, false)
	player.global_position = Vector3(0.5, 0.0, -1.8)
	_face_toward(sentry, player.global_position)
	if sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 2, 1.0)
	cam.look_at_from_position(Vector3(4.0, 2.05, 0.2), Vector3(0.5, 1.15, -2.8), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_alerted")

	print("CAPTURE_STEALTH_DONE")
	quit(0)


func _force_crouch(player: Node, crouch: bool) -> void:
	player.set("is_crouching", crouch)
	player.set("_crouch_blend", 1.0 if crouch else 0.0)
	if player.has_method("_apply_crouch_visual"):
		player.call("_apply_crouch_visual", 1.0)


func _face_toward(node: Node3D, target: Vector3) -> void:
	var to := target - node.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	node.rotation.y = atan2(-to.x, -to.z)
	node.rotation.x = 0.0
	node.rotation.z = 0.0


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("WROTE ", path, " err=", err)
