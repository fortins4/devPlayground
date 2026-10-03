extends SceneTree
## Full-body knife stills: idle, side cut, chest-height thrust.
## xvfb + x11/opengl3. Do not run bare --headless (SubViewport stays blank).

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/knife-reach-thrust"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "KnifeReachCapture"
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

	var stake := MeshInstance3D.new()
	var stake_mesh := BoxMesh.new()
	stake_mesh.size = Vector3(0.08, 1.55, 0.08)
	stake.mesh = stake_mesh
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.55, 0.18, 0.12)
	stake.material_override = smat
	stake.position = Vector3(0.05, 1.05, -1.25)
	world.add_child(stake)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	player.rotation_degrees.y = 12.0
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 36.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(3.35, 1.28, 1.9), Vector3(0.02, 1.08, -0.25), Vector3.UP)
	cam.current = true

	var hud := CanvasLayer.new()
	vp.add_child(hud)
	var hud_label := Label.new()
	hud_label.position = Vector2(28, 18)
	hud_label.add_theme_font_size_override("font_size", 40)
	hud_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72))
	hud_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06))
	hud_label.add_theme_constant_override("outline_size", 10)
	hud.add_child(hud_label)
	var hud_sub := Label.new()
	hud_sub.position = Vector2(28, 68)
	hud_sub.add_theme_font_size_override("font_size", 24)
	hud_sub.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	hud_sub.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06))
	hud_sub.add_theme_constant_override("outline_size", 8)
	hud_sub.text = "L/R = CUT (blade across)    neutral / look-up = THRUST (point)"
	hud.add_child(hud_sub)

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

	var side := Vector3(3.35, 1.28, 1.9)
	var side_aim := Vector3(0.02, 1.08, -0.25)
	# Profile so the thrust point reads as a jab, not an end-on nub.
	var profile := Vector3(3.7, 1.22, 0.15)
	var profile_aim := Vector3(0.05, 1.12, -0.35)
	var shots: Array = [
		{"file": "knife-idle", "phase": "idle", "label": "KNIFE idle", "cam": side, "aim": side_aim},
		{"file": "knife-cut", "dir": CombatSystem.StrikeDirection.RIGHT, "phase": "contact", "label": "KNIFE CUT  look right", "cam": side, "aim": side_aim},
		{"file": "knife-thrust", "dir": CombatSystem.StrikeDirection.TOP, "phase": "contact", "label": "KNIFE THRUST  top / look-up", "cam": profile, "aim": profile_aim},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		player.rotation_degrees.y = 12.0
		if loco:
			loco.clear_combat_additives()
			loco.reset_to_rest()
		combat.reset_weapon_pose()
		combat.set_weapon(CombatSystem.Weapon.KNIFE)
		var phase := String(shot.get("phase", "contact"))
		var direction := int(shot.get("dir", CombatSystem.StrikeDirection.TOP))
		if phase == "idle":
			player._apply_tool_pose(ToolStrikePoses.tool_idle_pose(combat.current_weapon))
			player._tool_pose_active = false
		else:
			player._apply_tool_pose(ToolStrikePoses.tool_strike_pose(combat.current_weapon, direction, &"contact", false))
		if loco:
			loco.tick(0.016, 0.0, false, false, phase != "idle", Vector3.ZERO)
			if phase != "idle":
				player._apply_tool_pose(ToolStrikePoses.tool_strike_pose(combat.current_weapon, direction, &"contact", false))
			else:
				player._apply_tool_pose(ToolStrikePoses.tool_idle_pose(combat.current_weapon))
				player._tool_pose_active = false
		player._sync_weapon_to_hand()
		hud_label.text = String(shot["label"])
		var cam_from: Vector3 = shot["cam"]
		var aim: Vector3 = shot["aim"]
		cam.look_at_from_position(cam_from, aim, Vector3.UP)
		for _i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["file"])]
		var err := img.save_png(path)
		var tip := _blade_tip_local(player)
		print("WROTE ", path, " err=", err, " ", img.get_width(), "x", img.get_height(), " tip_local=", tip)

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)


func _blade_tip_local(player: Node3D) -> Vector3:
	var visual := player.get_node("WeaponVisual") as Node3D
	var tip_world: Vector3 = visual.to_global(Vector3(0.0, 0.48, 0.0))
	return player.to_local(tip_world)
