extends SceneTree
## Foe goad jab incoming, then stopped by the low guard. xvfb + x11/opengl3.

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-spar-jab"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var envn := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.55, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.93, 0.93, 0.96)
	environment.ambient_light_energy = 1.15
	envn.environment = environment
	world.add_child(envn)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.35
	light.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-16.0, 160.0, 0.0)
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
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false
	var foe := (load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(foe)
	foe.set_physics_process(false)
	foe.set_process(false)
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.fov = 36.0
	world.add_child(cam)
	cam.current = true
	var hud := CanvasLayer.new()
	vp.add_child(hud)
	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.09, 0.1, 0.78)
	panel.position = Vector2(24, 16)
	panel.size = Vector2(1180, 56)
	hud.add_child(panel)
	var label := Label.new()
	label.position = Vector2(36, 26)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.72))
	hud.add_child(label)
	for _i in 6:
		await process_frame
	var _reg := _Loco
	var pcombat := player.get_node("CombatSystem") as CombatSystem
	var fcombat := foe.get_node("CombatSystem") as CombatSystem
	var ploco := player.get_node("KerneLocomotion") as KerneLocomotion
	var floco := foe.get_node("KerneLocomotion") as KerneLocomotion
	pcombat.process_mode = Node.PROCESS_MODE_DISABLED
	fcombat.process_mode = Node.PROCESS_MODE_DISABLED
	pcombat.enable_hit_feedback = false
	fcombat.enable_hit_feedback = false
	fcombat.hit_stop_light = 0.0
	fcombat.hit_stop_heavy = 0.0
	if ploco.joints.is_empty():
		ploco.rebuild()
	if floco.joints.is_empty():
		floco.rebuild()
	pcombat.set_weapon(CombatSystem.Weapon.GOAD)
	if fcombat.current_weapon != CombatSystem.Weapon.GOAD:
		fcombat.set_weapon(CombatSystem.Weapon.GOAD)
	foe._hide_stowed_goad()
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	# In front of Cian (he faces -Z). Foe faces him.
	foe.global_position = Vector3(0.05, 0.0, -1.82)
	foe.rotation = Vector3(0.0, PI, 0.0)
	var eye := Vector3(2.35, 1.28, -0.78)
	var look := Vector3(0.0, 1.05, -0.72)
	cam.look_at_from_position(eye, look, Vector3.UP)
	# Incoming: Cian is open. The point is committed toward him and has not met a guard.
	player._sprinting = false
	player._tool_aim_delta = Vector2.ZERO
	player.pivot.rotation.x = 0.0
	pcombat.set_shaft_block(false)
	pcombat.is_attacking = false
	player._apply_tool_pose(ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD))
	ploco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	player._apply_tool_pose(ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD))
	player._sync_weapon_to_hand()
	foe.pose_goad_jab(&"contact")
	floco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	foe.pose_goad_jab(&"contact")
	label.text = "FOE JAB  uncharged point coming in"
	for _i in 4:
		await process_frame
	_save(vp, out_dir, "jab-incoming")
	# Same jab, Cian looking down. Low guard stops a stab. Not a click, not a parry.
	player._tool_aim_delta = Vector2(0.0, 48.0)
	player._tick_shaft_block()
	ploco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	player._tick_shaft_block()
	player._sync_weapon_to_hand()
	foe.pose_goad_jab(&"contact")
	var dealt := pcombat.apply_damage(18.0, foe, true, CombatSystem.StrikeDirection.BOTTOM)
	print("LOW dealt=", dealt, " face=", pcombat.shaft_guard_face, " blocking=", pcombat.is_shaft_blocking, " foe_power=", fcombat.last_attack_power)
	if dealt > 0.01 or pcombat.shaft_guard_face != &"low":
		push_error("CAPTURE low guard did not stop the jab")
		quit(1)
		return
	label.text = "LOW GUARD  look down stops the jab"
	for _i in 4:
		await process_frame
	_save(vp, out_dir, "jab-stopped")
	print("CAPTURE_DONE")
	quit(0)


func _save(vp: SubViewport, out_dir: String, file_name: String) -> void:
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, file_name]
	var err := img.save_png(path)
	print("WROTE ", path, " err=", err, " bytes=", FileAccess.get_file_as_bytes(path).size())
