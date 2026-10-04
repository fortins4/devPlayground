extends SceneTree
## Goad clearance, settle, and high-left release.
## xvfb + x11/opengl3. Do not run bare --headless (SubViewport stays blank).

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-clear-swing"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "GoadClearSwing"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.55, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.93, 0.93, 0.96)
	environment.ambient_light_energy = 1.15
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.35
	light.rotation_degrees = Vector3(-48.0, 36.0, 0.0)
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
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
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	var eye := Vector3(3.15, 1.55, 4.15)
	var look := Vector3(0.05, 1.05, 0.0)
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.current = true

	var hud := CanvasLayer.new()
	vp.add_child(hud)
	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.09, 0.1, 0.78)
	panel.position = Vector2(24, 16)
	panel.size = Vector2(1180, 64)
	hud.add_child(panel)
	var dir_label := Label.new()
	dir_label.position = Vector2(36, 26)
	dir_label.add_theme_font_size_override("font_size", 26)
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
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	combat.enable_hit_feedback = false
	if loco and loco.joints.is_empty():
		loco.rebuild()

	var idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	var follow: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, 1.0, 0.0, &"follow")
	var mid_settle := _slerp_pose(follow, idle, 0.5)
	var hl_hold: Dictionary = ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, -0.72, -0.58, 1.0)
	var hl_hit: Dictionary = ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, -0.72, -0.58, &"contact")

	var shots: Array = [
		{"file": "a-charge-right-full", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 1.0, 0.0, 1.0), "label": "A  RIGHT CHARGE full   shaft outside head and shoulder"},
		{"file": "a-charge-right-mid", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 1.0, 0.0, 0.55), "label": "A  RIGHT CHARGE mid   same aim, still outside the head"},
		{"file": "a-charge-left-full", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, -1.0, 0.0, 1.0), "label": "A  LEFT CHARGE full   shaft outside the body"},
		{"file": "a-charge-high-full", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 0.0, -1.0, 1.0), "label": "A  HIGH CHARGE full   overhead, clear of the skull"},
		{"file": "a-charge-stab-low", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 0.0, 1.0, 1.0), "label": "A  STAB / LOW CHARGE   point forward, shaft clear"},
		{"file": "b-settle-follow", "pose": follow, "label": "B  FOLLOW-THROUGH   end of the right swing"},
		{"file": "b-settle-mid", "pose": mid_settle, "label": "B  MID BLEND   easing back to idle ~0.11s of 0.22s"},
		{"file": "b-settle-idle", "pose": idle, "label": "B  IDLE   ready pose after the blend"},
		{"file": "c-hold-high-left", "pose": hl_hold, "label": "C  HIGH-LEFT HOLD   chambered high and to the player's left"},
		{"file": "c-release-high-left", "pose": hl_hit, "label": "C  HIGH-LEFT RELEASE   same aim through contact, not a thrust"},
		{"file": "a-charge-right-side", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 1.0, 0.0, 1.0), "label": "A  RIGHT CHARGE side view   gap beside the head", "yaw": 90.0, "eye": Vector3(3.4, 1.45, 0.15)},
		{"file": "a-charge-right-mid-side", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 1.0, 0.0, 0.55), "label": "A  RIGHT MID side view   shaft beside the skull", "yaw": 90.0, "eye": Vector3(3.4, 1.45, 0.15)},
		{"file": "a-charge-high-side", "pose": ToolStrikePoses.tool_aim_pose(CombatSystem.Weapon.GOAD, 0.0, -1.0, 1.0), "label": "A  HIGH CHARGE side view   shaft off the face", "yaw": 80.0, "eye": Vector3(3.2, 1.35, 1.1)},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		player.rotation_degrees.y = float(shot.get("yaw", 208.0))
		if loco:
			loco.clear_combat_additives()
			loco.reset_to_rest()
		combat.reset_weapon_pose()
		combat.set_weapon(CombatSystem.Weapon.GOAD)
		var pose: Dictionary = shot["pose"]
		player._apply_tool_pose(pose)
		if loco:
			loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
			player._apply_tool_pose(pose)
		player._sync_weapon_to_hand()
		var shot_eye: Vector3 = shot.get("eye", eye)
		cam.look_at_from_position(shot_eye, look, Vector3.UP)
		dir_label.text = String(shot["label"])
		for _i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["file"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err, " bytes=", FileAccess.get_file_as_bytes(path).size())

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)


func _lerp_pose(from_pose: Dictionary, to_pose: Dictionary, t: float) -> Dictionary:
	var blended := {}
	for k in to_pose.keys():
		var a: Vector3 = from_pose.get(k, Vector3.ZERO)
		var b: Vector3 = to_pose[k]
		blended[k] = a.lerp(b, t)
	return blended

func _slerp_pose(from_pose: Dictionary, to_pose: Dictionary, amount: float) -> Dictionary:
	var blended := {}
	for k in to_pose.keys():
		var a: Vector3 = from_pose.get(k, Vector3.ZERO)
		var b: Vector3 = to_pose[k]
		blended[k] = Quaternion.from_euler(a).slerp(Quaternion.from_euler(b), amount).get_euler()
	return blended
