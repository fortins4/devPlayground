extends SceneTree
## Look-guard and the uncharged jab. xvfb + x11/opengl3.
## Do not run bare --headless (SubViewport stays blank).

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-mouse-guard"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "GoadMouseGuard"
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
	cam.fov = 38.0
	world.add_child(cam)
	var eye := Vector3(2.15, 0.95, 3.55)
	var look := Vector3(0.0, 0.7, 0.15)
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

	var shots: Array = [
		{"file": "look-down-no-click", "kind": "guard", "aim": Vector2(0.0, 48.0), "label": "LOOK DOWN  no click   LOW GUARD  not a jab"},
		{"file": "look-down-lmb-jab-contact", "kind": "lmb", "aim": Vector2(0.0, 48.0), "label": "LOOK DOWN + LEFT CLICK   point jab at contact"},
		{"file": "rmb-jab-contact", "kind": "rmb", "aim": Vector2(-40.0, 0.0), "label": "RIGHT MOUSE   same point jab at contact  not a shaft swing"},
		{"file": "guard-left", "kind": "guard", "aim": Vector2(-48.0, 0.0), "label": "LOOK LEFT   left guard  no attack"},
		{"file": "guard-right", "kind": "guard", "aim": Vector2(48.0, 0.0), "label": "LOOK RIGHT   right guard  no attack"},
		{"file": "guard-high", "kind": "guard", "aim": Vector2(0.0, -48.0), "label": "LOOK UP   high guard  no attack"},
		{"file": "shaft-swing-guard-dropped", "kind": "swing", "aim": Vector2(-48.0, -20.0), "label": "SHAFT SWING   left contact  guard dropped  both feet"},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		player.rotation_degrees.y = float(shot.get("yaw", 170.0))
		player._sprinting = false
		player.pivot.rotation.x = 0.0
		player._tool_aim_delta = Vector2.ZERO
		player._charge_aim_delta = Vector2.ZERO
		player._hatchet_charge_armed = false
		if player._arm_tween and player._arm_tween.is_valid():
			player._arm_tween.kill()
		if loco:
			loco.clear_combat_additives()
			loco.reset_to_rest()
		combat.is_attacking = false
		combat.attack_recovery_left = 0.0
		combat.is_charging = false
		combat.set_shaft_block(false)
		combat.reset_weapon_pose()
		combat.set_weapon(CombatSystem.Weapon.GOAD)
		player._tool_pose_active = false
		player._tool_aim_delta = shot["aim"]
		var kind := String(shot["kind"])
		if kind == "guard":
			player._tick_shaft_block()
			if combat.is_attacking or combat.is_charging:
				push_error("CAPTURE look alone attacked")
		elif kind == "lmb":
			player._begin_hatchet_or_light()
		elif kind == "rmb":
			player._heavy_or_ignore_hatchet()
		elif kind == "swing":
			player._charge_aim_delta = shot["aim"]
			player._begin_hatchet_or_light()
			combat.charge_time = 0.5
			combat.charge_ratio = 0.5
			player._release_hatchet_or_ignore()
		if kind != "guard":
			if player._arm_tween and player._arm_tween.is_valid():
				player._arm_tween.kill()
			var aim: Vector2 = Vector2(0.0, 1.0) if combat.last_strike_direction() == CombatSystem.StrikeDirection.BOTTOM else player._shaft_aim_axes()
			player._apply_tool_pose(ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim.x, aim.y, &"contact"))
		if loco:
			var locking := combat.is_attacking or combat.is_charging or combat.is_shaft_blocking
			loco.tick(0.016, 0.0, false, false, locking, Vector3.ZERO)
			if kind == "guard":
				player._tick_shaft_block()
			else:
				var aim2: Vector2 = Vector2(0.0, 1.0) if combat.last_strike_direction() == CombatSystem.StrikeDirection.BOTTOM else player._shaft_aim_axes()
				player._apply_tool_pose(ToolStrikePoses.tool_aim_phase_pose(CombatSystem.Weapon.GOAD, aim2.x, aim2.y, &"contact"))
		player._sync_weapon_to_hand()
		print("STATE ", shot["file"], " atk=", combat.is_attacking, " chg=", combat.is_charging, " guard=", combat.is_shaft_blocking, " face=", combat.shaft_guard_face, " dir=", combat.direction_name(combat.last_strike_direction()), " power=", combat.last_attack_power)
		var shot_eye: Vector3 = shot.get("eye", eye)
		var shot_look: Vector3 = shot.get("look", look)
		cam.fov = float(shot.get("fov", 38.0))
		cam.look_at_from_position(shot_eye, shot_look, Vector3.UP)
		dir_label.text = String(shot["label"])
		for _i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["file"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err, " bytes=", FileAccess.get_file_as_bytes(path).size())

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)
