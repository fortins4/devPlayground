extends SceneTree
## Capture kerne model + locomotion/combat poses for fluid-anims proof.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/anims-model"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "AnimsCaptureRoot"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.40, 0.50, 0.58)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.92, 0.95)
	environment.ambient_light_energy = 1.1
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-18.0, -95.0, 0.0)
	world.add_child(fill)

	# Visual ground + collision so bodies do not fall during multi-frame posing
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.36, 0.24)
	ground.material_override = gmat
	world.add_child(ground)

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40, 0.2, 40)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.1
	floor_body.add_child(floor_col)
	world.add_child(floor_body)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var dummy_packed := load("res://scenes/characters/npcs/dummy_fighter.tscn") as PackedScene
	var player := player_packed.instantiate() as CharacterBody3D
	var dummy := dummy_packed.instantiate() as CharacterBody3D
	world.add_child(player)
	world.add_child(dummy)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.rotation_degrees.y = 25.0
	dummy.global_position = Vector3(0.35, 0.05, -1.55)
	dummy.rotation_degrees.y = 185.0

	# Freeze physics simulation — we drive loco manually
	player.set_physics_process(false)
	dummy.set_physics_process(false)
	player.velocity = Vector3.ZERO
	dummy.velocity = Vector3.ZERO

	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.current = true

	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var loco := player.get_node("KerneLocomotion") as KerneLocomotion
	var dloco := dummy.get_node("KerneLocomotion") as KerneLocomotion
	var pcombat := player.get_node("CombatSystem") as CombatSystem
	var dcombat := dummy.get_node("CombatSystem") as CombatSystem
	pcombat.hit_stop_light = 0.0
	pcombat.hit_stop_heavy = 0.0
	dcombat.hit_stop_light = 0.0
	dcombat.hit_stop_heavy = 0.0
	pcombat.set_weapon(CombatSystem.Weapon.HATCHET)
	if player.has_method("_bind_locomotion_joints"):
		player.call("_bind_locomotion_joints")
	if player.has_method("_on_weapon_changed"):
		player.call("_on_weapon_changed", &"hatchet")

	for i in 10:
		loco.tick(0.05, 0.0, false, false, false, Vector3.ZERO)
		dloco.tick(0.05, 0.0, false, false, false, Vector3.ZERO)
		if player.has_method("_sync_weapon_to_hand"):
			player.call("_sync_weapon_to_hand")
		await process_frame

	# 01 close-up idle
	cam.fov = 36.0
	cam.look_at_from_position(Vector3(1.55, 1.45, 2.0), Vector3(0.05, 1.15, 0.05), Vector3.UP)
	await _shot(vp, out_dir, "01_idle_model_closeup")

	# 02 walk — pin mid-stride phase for readable screenshot
	loco.set("_phase", 1.2)
	for i in 4:
		loco.tick(0.02, 4.8, false, false, false, Vector3(0.0, 0.0, -1.0))
		if player.has_method("_sync_weapon_to_hand"):
			player.call("_sync_weapon_to_hand")
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(2.1, 1.5, 2.2), Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await _shot(vp, out_dir, "02_walk_stride")

	# 03 sprint
	loco.set("_phase", 2.0)
	for i in 4:
		loco.tick(0.02, 7.8, true, false, false, Vector3(0.0, 0.0, -1.0))
		if player.has_method("_sync_weapon_to_hand"):
			player.call("_sync_weapon_to_hand")
	await _shot(vp, out_dir, "03_sprint")

	# 04 crouch walk
	player.get_node("Visual").position.y = -0.4
	loco.set("_phase", 1.4)
	for i in 4:
		loco.tick(0.02, 2.1, false, true, false, Vector3(0.0, 0.0, -1.0))
		if player.has_method("_sync_weapon_to_hand"):
			player.call("_sync_weapon_to_hand")
	cam.look_at_from_position(Vector3(2.0, 1.2, 2.1), Vector3(0.0, 0.7, 0.0), Vector3.UP)
	await _shot(vp, out_dir, "04_crouch_walk")
	player.get_node("Visual").position.y = 0.0

	# Reset toward idle
	loco.clear_combat_additives()
	for i in 6:
		loco.tick(0.05, 0.0, false, false, false, Vector3.ZERO)
		if player.has_method("_sync_weapon_to_hand"):
			player.call("_sync_weapon_to_hand")

	cam.fov = 40.0
	cam.look_at_from_position(Vector3(1.85, 1.5, 2.15), Vector3(0.15, 1.15, 0.0), Vector3.UP)

	_pose_swing(player, pcombat, loco, &"light", "contact")
	loco.lock_attack(1.0)
	loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	await _shot(vp, out_dir, "05_hatchet_light_swing")

	_pose_swing(player, pcombat, loco, &"heavy", "windup")
	loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	await _shot(vp, out_dir, "06_hatchet_heavy_windup")

	_pose_swing(player, pcombat, loco, &"heavy", "contact")
	loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	dcombat.call("_play_hurt_feedback", 28.0, player)
	await process_frame
	await _shot(vp, out_dir, "07_hatchet_heavy_contact")

	# knife
	pcombat.reset_weapon_pose()
	loco.clear_combat_additives()
	pcombat.set_weapon(CombatSystem.Weapon.KNIFE)
	if player.has_method("_on_weapon_changed"):
		player.call("_on_weapon_changed", &"knife")
	_pose_swing(player, pcombat, loco, &"light", "contact")
	loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	await _shot(vp, out_dir, "08_knife_light")

	# goad vs dummy
	pcombat.reset_weapon_pose()
	loco.clear_combat_additives()
	pcombat.set_weapon(CombatSystem.Weapon.GOAD)
	if player.has_method("_on_weapon_changed"):
		player.call("_on_weapon_changed", &"goad")
	_pose_swing(player, pcombat, loco, &"light", "contact")
	loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
	for i in 8:
		dloco.tick(0.05, 1.4, false, false, false, Vector3.ZERO)
	cam.look_at_from_position(Vector3(2.5, 1.65, 1.9), Vector3(0.15, 1.1, -0.55), Vector3.UP)
	await _shot(vp, out_dir, "09_goad_vs_dummy_lane")

	print("CAPTURE_ANIMS_MODEL_DONE")
	quit(0)


func _pose_swing(player: Node, combat: CombatSystem, loco: KerneLocomotion, kind: StringName, pose: String) -> void:
	combat.reset_weapon_pose()
	var weapon_visual := player.get_node("WeaponVisual") as Node3D
	var poses: Dictionary = combat.call("_swing_poses", kind)
	weapon_visual.rotation_degrees = poses["%s_rot" % pose]
	weapon_visual.position = poses["%s_pos" % pose]
	var heavy := kind == &"heavy"
	var arm := Vector3.ZERO
	var torso := Vector3.ZERO
	match pose:
		"windup":
			arm = Vector3(deg_to_rad(-55.0 if heavy else -32.0), deg_to_rad(-15.0 if heavy else -8.0), deg_to_rad(-25.0 if heavy else -14.0))
			torso = Vector3(deg_to_rad(-8.0 if heavy else -4.0), deg_to_rad(-12.0 if heavy else -6.0), 0.0)
		"contact":
			arm = Vector3(deg_to_rad(25.0 if heavy else 12.0), deg_to_rad(10.0), deg_to_rad(35.0 if heavy else 22.0))
			torso = Vector3(deg_to_rad(10.0 if heavy else 5.0), deg_to_rad(8.0 if heavy else 4.0), 0.0)
		"follow":
			arm = Vector3(deg_to_rad(55.0 if heavy else 35.0), deg_to_rad(18.0), deg_to_rad(50.0 if heavy else 32.0))
			torso = Vector3(deg_to_rad(14.0 if heavy else 8.0), deg_to_rad(12.0 if heavy else 6.0), 0.0)
	loco.set_combat_additive("right_arm", arm)
	loco.set_combat_additive("right_forearm", Vector3(arm.x * 0.4, 0.0, 0.0))
	loco.set_combat_additive("torso", torso)


func _shot(vp: SubViewport, out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("WROTE ", path, " err=", err, " size=", img.get_width(), "x", img.get_height())
