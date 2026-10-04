extends SceneTree
## One landed hit on the sparring foe, then his ready pose.
## xvfb + x11/opengl3. Do not run bare --headless (SubViewport stays blank).

const ToolStrikePoses := preload("res://systems/combat/tool_strike_poses.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/goad-foe-flinch"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "FoeFlinch"
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

	var foe_packed := load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene
	var foe := foe_packed.instantiate() as CharacterBody3D
	world.add_child(foe)
	foe.global_position = Vector3.ZERO
	foe.velocity = Vector3.ZERO
	foe.set_physics_process(false)
	foe.set_process(false)
	foe.process_mode = Node.PROCESS_MODE_DISABLED

	var cam := Camera3D.new()
	cam.fov = 36.0
	world.add_child(cam)
	var eye := Vector3(1.15, 1.28, -3.35)
	var look := Vector3(0.05, 1.15, 0.0)
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
	var combat := foe.get_node("CombatSystem") as CombatSystem
	var loco := foe.get_node("KerneLocomotion") as KerneLocomotion
	combat.set_physics_process(false)
	combat.set_process(false)
	combat.process_mode = Node.PROCESS_MODE_DISABLED
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	combat.enable_hit_feedback = false
	if loco and loco.joints.is_empty():
		loco.rebuild()

	foe.global_position = Vector3.ZERO
	foe.velocity = Vector3.ZERO
	foe.rotation_degrees = Vector3.ZERO
	if loco:
		loco.clear_combat_additives()
		loco.reset_to_rest()
	combat.is_attacking = false
	combat.attack_recovery_left = 0.0
	combat.is_charging = false
	combat.stamina = combat.max_stamina
	combat.health = combat.max_health
	combat.set_weapon(CombatSystem.Weapon.GOAD)
	combat.set_face_guard(&"open")
	foe._apply_goad_pose(ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD))

	var goad := foe.weapon_visual.get_node_or_null("Goad") as Node3D
	if goad == null or not goad.visible:
		push_error("CAPTURE foe is not holding a visible goad")
		quit(1)
		return

	var dealt := combat.apply_damage(14.0, null, true, CombatSystem.StrikeDirection.LEFT)
	if dealt <= 0.0 or not foe.is_hurt_flinching():
		push_error("CAPTURE hit did not play the foe flinch dealt=%s hurt=%s" % [dealt, foe.is_hurt_flinching()])
		quit(1)
		return
	if foe._flinch_tween and foe._flinch_tween.is_valid():
		foe._flinch_tween.kill()
	foe._hurt_reacting = true
	var flinch: Dictionary = ToolStrikePoses.tool_hurt_flinch_pose(CombatSystem.Weapon.GOAD)
	foe._apply_goad_pose(flinch)
	if loco:
		loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
		foe._apply_goad_pose(flinch)
	foe._sync_goad_to_hand()
	var dur := float(foe.HURT_FLINCH_IN_SEC) + float(foe.HURT_FLINCH_HOLD_SEC) + float(foe.HURT_FLINCH_OUT_SEC)
	print("STATE flinch dealt=", dealt, " hurt=", foe.is_hurt_flinching(), " sec=", dur, " dead=", combat.is_dead)
	dir_label.text = "FOE FLINCH  shaft clear of the face  goad in hand"
	cam.look_at_from_position(eye, look, Vector3.UP)
	for _i in 5:
		await process_frame
	_save(vp, out_dir, "foe-flinch")

	foe._hurt_reacting = false
	foe._finish_hurt_flinch()
	var idle: Dictionary = ToolStrikePoses.tool_idle_pose(CombatSystem.Weapon.GOAD)
	if loco:
		loco.tick(0.016, 0.0, false, false, false, Vector3.ZERO)
		foe._apply_goad_pose(idle)
	foe._sync_goad_to_hand()
	print("STATE ready hurt=", foe.is_hurt_flinching(), " dead=", combat.is_dead, " goad=", goad.visible)
	dir_label.text = "FOE BACK IN THE READY POSE"
	cam.look_at_from_position(Vector3(2.15, 1.35, -2.4), look, Vector3.UP)
	for _i in 5:
		await process_frame
	_save(vp, out_dir, "foe-ready")

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)


func _save(vp: SubViewport, out_dir: String, file_name: String) -> void:
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, file_name]
	var err := img.save_png(path)
	if err != OK:
		push_error("CAPTURE save failed %s %s" % [path, err])
