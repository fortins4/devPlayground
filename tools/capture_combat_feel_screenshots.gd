extends SceneTree
## Capture hit-feedback + dummy counter poses for combat-feel polish proof.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/feel"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "FeelCaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.52, 0.6)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.92, 0.95)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	fill.rotation_degrees = Vector3(-18.0, -95.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.36, 0.24)
	ground.material_override = gmat
	world.add_child(ground)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var dummy_packed := load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene
	var player := player_packed.instantiate() as Node3D
	var dummy := dummy_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(dummy)
	player.global_position = Vector3(0.0, 0.0, 0.6)
	player.rotation_degrees.y = 10.0
	dummy.global_position = Vector3(0.15, 0.0, -1.15)
	dummy.rotation_degrees.y = 180.0

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(2.35, 1.65, 2.1), Vector3(0.1, 1.2, -0.35), Vector3.UP)
	cam.current = true

	# Let nodes enter tree fully before posing.
	await process_frame
	await process_frame
	await process_frame

	var pcombat := player.get_node("CombatSystem") as CombatSystem
	var dcombat := dummy.get_node("CombatSystem") as CombatSystem
	pcombat.set_weapon(CombatSystem.Weapon.HATCHET)
	dcombat.set_weapon(CombatSystem.Weapon.HATCHET)
	pcombat.hit_stop_light = 0.0
	pcombat.hit_stop_heavy = 0.0
	dcombat.hit_stop_light = 0.0
	dcombat.hit_stop_heavy = 0.0

	var pweapon := player.get_node("WeaponVisual") as Node3D
	var dweapon := dummy.get_node("WeaponVisual") as Node3D
	var right_arm := player.get_node("Visual/RightArm") as MeshInstance3D
	var arm_base := right_arm.transform

	await _shot(vp, out_dir, "01_faceoff_idle")

	_pose_attacker(pcombat, pweapon, right_arm, arm_base, &"light", "contact")
	dcombat.call("_play_hurt_feedback", 14.0, player)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "02_player_hit_flash_dmgnum")

	_cleanup_fx(world, pcombat, dcombat)
	_reset_dummy(dummy)
	pcombat.reset_weapon_pose()
	right_arm.transform = arm_base
	dummy.global_position = Vector3(0.15, 0.0, -1.15)
	if dummy.has_method("_begin_telegraph"):
		dummy.call("_begin_telegraph", &"light", true)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "03_dummy_counter_telegraph")

	_cleanup_fx(world, pcombat, dcombat)
	if dummy.has_method("_show_telegraph_visual"):
		dummy.call("_show_telegraph_visual", false, false)
	_pose_attacker(dcombat, dweapon, null, Transform3D(), &"light", "contact")
	pcombat.call("_play_hurt_feedback", 14.0, dummy)
	# Nudge camera slightly side-on so both read
	cam.look_at_from_position(Vector3(2.6, 1.7, 1.4), Vector3(0.05, 1.15, -0.2), Vector3.UP)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "04_dummy_counter_contact_player_flash")

	_cleanup_fx(world, pcombat, dcombat)
	dcombat.reset_weapon_pose()
	cam.look_at_from_position(Vector3(2.35, 1.65, 2.1), Vector3(0.1, 1.2, -0.35), Vector3.UP)
	_pose_attacker(pcombat, pweapon, right_arm, arm_base, &"heavy", "contact")
	dcombat.call("_play_hurt_feedback", 28.0, player)
	dummy.global_position += Vector3(0.05, 0.0, -0.4)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "05_heavy_hit_knockback_read")

	_cleanup_fx(world, pcombat, dcombat)
	_reset_dummy(dummy)
	pcombat.reset_weapon_pose()
	right_arm.transform = arm_base
	player.global_position = Vector3(0.0, 0.0, 0.6)
	dummy.global_position = Vector3(0.15, 0.0, -1.15)
	cam.look_at_from_position(Vector3(2.35, 1.65, 2.1), Vector3(0.1, 1.2, -0.35), Vector3.UP)
	if dummy.has_method("_begin_telegraph"):
		dummy.call("_begin_telegraph", &"light", false)
	await process_frame
	await process_frame
	await _shot(vp, out_dir, "06_dummy_opportunistic_telegraph")

	print("CAPTURE_FEEL_DONE")
	quit(0)


func _cleanup_fx(world: Node, pcombat: CombatSystem, dcombat: CombatSystem) -> void:
	pcombat.call("_clear_hurt_flash")
	dcombat.call("_clear_hurt_flash")
	for child in world.get_children():
		if child is Label3D:
			child.queue_free()


func _reset_dummy(dummy: Node) -> void:
	if dummy.has_method("_show_telegraph_visual"):
		dummy.call("_show_telegraph_visual", false, false)
	if dummy.has_method("_set_state"):
		# State.CHASE == 1
		dummy.call("_set_state", 1)
	var dweapon := dummy.get_node_or_null("WeaponVisual") as Node3D
	var dcombat := dummy.get_node_or_null("CombatSystem") as CombatSystem
	if dcombat:
		dcombat.reset_weapon_pose()
	dummy.set("_is_counter", false)


func _pose_attacker(
	combat: CombatSystem,
	weapon_visual: Node3D,
	right_arm: MeshInstance3D,
	arm_base: Transform3D,
	kind: StringName,
	pose: String
) -> void:
	combat.reset_weapon_pose()
	var poses: Dictionary = combat.call("_swing_poses", kind)
	weapon_visual.rotation_degrees = poses["%s_rot" % pose]
	weapon_visual.position = poses["%s_pos" % pose]
	if right_arm == null:
		return
	var heavy := kind == &"heavy"
	var base := arm_base.basis.get_euler()
	match pose:
		"windup":
			right_arm.rotation = base + Vector3(
				deg_to_rad(-25.0 if heavy else -12.0), 0.0, deg_to_rad(-0.55 if heavy else -0.35)
			)
		"contact":
			right_arm.rotation = base + Vector3(
				deg_to_rad(20.0 if heavy else 10.0), 0.0, deg_to_rad(0.55 if heavy else 0.35)
			)
		"follow":
			right_arm.rotation = base + Vector3(
				deg_to_rad(45.0 if heavy else 28.0), 0.0, deg_to_rad(0.95 if heavy else 0.65)
			)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("WROTE ", path, " err=", err)
