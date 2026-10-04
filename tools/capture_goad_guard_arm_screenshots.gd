extends SceneTree
## Bent-elbow goad guards. xvfb + x11/opengl3. Not bare --headless.

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-guard-arm"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
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

	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 32.0
	world.add_child(cam)
	cam.current = true

	var hud := CanvasLayer.new()
	vp.add_child(hud)
	var dir_label := Label.new()
	dir_label.position = Vector2(28, 22)
	dir_label.add_theme_font_size_override("font_size", 28)
	dir_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72))
	hud.add_child(dir_label)

	for _i in 6:
		await process_frame

	var _reg := _Loco
	var combat := player.get_node("CombatSystem") as CombatSystem
	var loco := player.get_node("KerneLocomotion") as KerneLocomotion
	combat.set_physics_process(false)
	combat.set_process(false)
	combat.process_mode = Node.PROCESS_MODE_DISABLED
	combat.enable_hit_feedback = false
	if loco.joints.is_empty():
		loco.rebuild()

	var shots: Array = [
		{"file": "guard-left", "face": &"left", "label": "LEFT GUARD  elbow bent  shaft beside head", "eye": Vector3(2.55, 1.32, 0.05)},
		{"file": "guard-right", "face": &"right", "label": "RIGHT GUARD  elbow bent  shaft beside head", "eye": Vector3(2.45, 1.38, -1.25)},
		{"file": "guard-low", "face": &"low", "label": "LOW GUARD  look down  elbow bent", "eye": Vector3(2.35, 1.05, -1.85)},
	]
	for shot in shots:
		player.global_position = Vector3.ZERO
		player.rotation_degrees.y = 0.0
		loco.clear_combat_additives()
		loco.reset_to_rest()
		combat.reset_weapon_pose()
		combat.set_weapon(CombatSystem.Weapon.GOAD)
		var face: StringName = shot["face"]
		player._apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
		loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
		player._apply_tool_pose(ToolStrikePoses.tool_shaft_guard_pose(face))
		player._sync_weapon_to_hand()
		var eye: Vector3 = shot["eye"]
		var look := Vector3(0.0, 1.15, 0.0)
		if String(shot["file"]) == "guard-right":
			var arm: Node3D = loco.get_joint("right_arm")
			var forearm: Node3D = loco.get_joint("right_forearm")
			var elbow: Vector3 = forearm.global_position
			var u := (elbow - arm.global_position).normalized()
			var tip: Vector3 = forearm.to_global(Vector3(0.0, -0.28, 0.05))
			var f := (tip - elbow).normalized()
			var n := u.cross(f).normalized()
			if n.dot(-player.global_transform.basis.z) < 0.0:
				n = -n
			eye = elbow + n * 3.1 + Vector3(0.0, 0.45, 0.0)
			look = Vector3(0.15, 1.25, 0.0)
		cam.look_at_from_position(eye, look, Vector3.UP)
		dir_label.text = String(shot["label"])
		for _i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["file"])]
		img.save_png(path)
		print("WROTE ", path, " bytes ", FileAccess.get_file_as_bytes(path).size())
	quit(0)
