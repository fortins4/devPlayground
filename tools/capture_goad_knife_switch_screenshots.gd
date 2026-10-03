extends SceneTree
## Full-body stills: goad idle, four strike directions, knife in hand.
## xvfb + x11/opengl3. Do not run bare --headless (SubViewport stays blank).

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-knife-switch"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "GoadKnifeCapture"
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
	stake_mesh.size = Vector3(0.14, 1.35, 0.14)
	stake.mesh = stake_mesh
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.35, 0.24, 0.12)
	stake.material_override = smat
	stake.position = Vector3(0.05, 0.67, -1.7)
	world.add_child(stake)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	player.rotation_degrees.y = 18.0
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 38.0
	world.add_child(cam)
	# Far enough to read feet, hips, and the full shaft. Same frame for every still.
	cam.look_at_from_position(Vector3(3.15, 1.55, 3.35), Vector3(0.05, 0.92, -0.15), Vector3.UP)
	cam.current = true

	var dir_label := Label3D.new()
	dir_label.font_size = 56
	dir_label.pixel_size = 0.0045
	dir_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dir_label.modulate = Color(1.0, 0.95, 0.72)
	dir_label.outline_size = 12
	dir_label.position = Vector3(-0.15, 2.35, 0.0)
	player.add_child(dir_label)

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
		{"file": "goad-idle", "weapon": CombatSystem.Weapon.GOAD, "phase": "idle", "label": "GOAD idle"},
		{"file": "goad-swing", "weapon": CombatSystem.Weapon.GOAD, "dir": CombatSystem.StrikeDirection.TOP, "phase": "mid", "label": "GOAD top mid-swing"},
		{"file": "goad-top", "weapon": CombatSystem.Weapon.GOAD, "dir": CombatSystem.StrikeDirection.TOP, "phase": "contact", "label": "GOAD top shaft"},
		{"file": "goad-left", "weapon": CombatSystem.Weapon.GOAD, "dir": CombatSystem.StrikeDirection.LEFT, "phase": "contact", "label": "GOAD left shaft"},
		{"file": "goad-right", "weapon": CombatSystem.Weapon.GOAD, "dir": CombatSystem.StrikeDirection.RIGHT, "phase": "contact", "label": "GOAD right shaft"},
		{"file": "goad-stab", "weapon": CombatSystem.Weapon.GOAD, "dir": CombatSystem.StrikeDirection.BOTTOM, "phase": "contact", "label": "GOAD bottom stab"},
		{"file": "knife", "weapon": CombatSystem.Weapon.KNIFE, "phase": "idle", "label": "KNIFE in hand"},
		{"file": "goad-again", "weapon": CombatSystem.Weapon.GOAD, "phase": "idle", "label": "GOAD again"},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		if loco:
			loco.clear_combat_additives()
			loco.reset_to_rest()
		combat.reset_weapon_pose()
		combat.set_weapon(int(shot["weapon"]))
		var phase := String(shot.get("phase", "contact"))
		var direction := int(shot.get("dir", CombatSystem.StrikeDirection.TOP))
		if phase == "idle":
			player._apply_tool_pose(ToolStrikePoses.tool_idle_pose(combat.current_weapon))
			player._tool_pose_active = false
		elif phase == "mid":
			var windup: Dictionary = ToolStrikePoses.tool_strike_pose(combat.current_weapon, direction, &"windup", false)
			var contact: Dictionary = ToolStrikePoses.tool_strike_pose(combat.current_weapon, direction, &"contact", false)
			player._lerp_tool_pose(0.62, windup, contact)
		else:
			player._apply_tool_pose(ToolStrikePoses.tool_strike_pose(combat.current_weapon, direction, &"contact", false))
		if loco:
			loco.tick(0.016, 0.0, false, false, phase != "idle", Vector3.ZERO)
		player._sync_weapon_to_hand()
		dir_label.text = String(shot["label"])
		for _i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["file"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err, " bytes_hint=", img.get_width(), "x", img.get_height())

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)
