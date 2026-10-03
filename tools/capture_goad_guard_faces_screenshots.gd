extends SceneTree
## Full-body goad guard faces. Same camera for every still.
## Scheme labeled on the HUD text: hold F, look picks the face.
##   neutral → CHEST   look left → LEFT   look right → RIGHT
##   look up → HIGH    look down → LOW
## xvfb + x11/opengl3. Do not run bare --headless (SubViewport stays blank).

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-guard-faces"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "GoadGuardFaces"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.55, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.93, 0.93, 0.96)
	environment.ambient_light_energy = 1.1
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	light.rotation_degrees = Vector3(-48.0, 36.0, 0.0)
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-16.0, -100.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.36, 0.24)
	ground.material_override = gmat
	world.add_child(ground)

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 0.4, 24)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, -0.2, 0)
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 32.0
	world.add_child(cam)
	# 3/4 front. Far enough for feet, a crouched low guard, and a shaft overhead.
	# Same frame every still. The HUD label is screen-space so it cannot clip.
	var eye := Vector3(1.85, 1.42, 5.15)
	var look := Vector3(0.0, 1.05, 0.0)
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.current = true

	var hud := CanvasLayer.new()
	vp.add_child(hud)
	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.09, 0.1, 0.78)
	panel.position = Vector2(24, 16)
	panel.size = Vector2(980, 64)
	hud.add_child(panel)
	var dir_label := Label.new()
	dir_label.position = Vector2(36, 26)
	dir_label.add_theme_font_size_override("font_size", 28)
	dir_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72))
	dir_label.text = "GUARD"
	hud.add_child(dir_label)

	for _i in 6:
		await process_frame

	var _reg := _Loco
	var combat := player.get_node("CombatSystem") as CombatSystem
	var loco := player.get_node("KerneLocomotion") as KerneLocomotion
	combat.set_physics_process(false)
	combat.set_process(false)
	combat.process_mode = Node.PROCESS_MODE_DISABLED
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	combat.enable_hit_feedback = false
	if loco and loco.joints.is_empty():
		loco.rebuild()

	# Yaw faces the camera enough that the chest shaft is not hidden by the cloak.
	var shots: Array = [
		{"file": "guard-chest", "face": &"chest", "label": "GUARD CHEST   hold F   neutral look"},
		{"file": "guard-left", "face": &"left", "label": "GUARD LEFT   hold F   look left"},
		{"file": "guard-right", "face": &"right", "label": "GUARD RIGHT   hold F   look right"},
		{"file": "guard-high", "face": &"high", "label": "GUARD HIGH   hold F   look up"},
		{"file": "guard-low", "face": &"low", "label": "GUARD LOW   hold F   look down"},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		player.rotation_degrees.y = 208.0
		if loco:
			loco.clear_combat_additives()
			loco.reset_to_rest()
		combat.reset_weapon_pose()
		combat.set_weapon(CombatSystem.Weapon.GOAD)
		var face: StringName = shot["face"]
		player._apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
		if loco:
			loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
			player._apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
		player._sync_weapon_to_hand()
		cam.look_at_from_position(eye, look, Vector3.UP)
		dir_label.text = String(shot["label"])
		for _i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["file"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err, " ", img.get_width(), "x", img.get_height())

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)
