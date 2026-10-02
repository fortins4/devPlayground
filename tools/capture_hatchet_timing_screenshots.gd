extends SceneTree
## Capture windup / contact / recover phases for light + charged hatchet (all dirs).


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/hatchet-timing"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "HatchetTimingCapture"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.52, 0.60)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.92, 0.96)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-50.0, 38.0, 0.0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.38
	fill.rotation_degrees = Vector3(-18.0, -85.0, 0.0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 22)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.27, 0.35, 0.23)
	ground.material_override = gmat
	world.add_child(ground)

	var player_packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_packed.instantiate() as Node3D
	world.add_child(player)
	player.global_position = Vector3.ZERO
	player.rotation_degrees.y = 20.0
	player.set_physics_process(false)
	player.set_process(false)
	player.velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(2.55, 1.55, 1.55), Vector3(0.25, 1.1, -0.2), Vector3.UP)
	cam.current = true

	var dir_label := Label3D.new()
	dir_label.font_size = 56
	dir_label.pixel_size = 0.004
	dir_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dir_label.modulate = Color(1.0, 0.95, 0.7)
	dir_label.outline_size = 10
	dir_label.position = Vector3(0.0, 2.2, 0.0)
	player.add_child(dir_label)

	var timing_label := Label3D.new()
	timing_label.font_size = 42
	timing_label.pixel_size = 0.0035
	timing_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	timing_label.modulate = Color(0.75, 0.95, 1.0)
	timing_label.outline_size = 8
	timing_label.position = Vector3(0.0, 1.95, 0.0)
	player.add_child(timing_label)

	await process_frame
	await process_frame
	await process_frame

	var combat := player.get_node("CombatSystem") as CombatSystem
	var weapon_visual := player.get_node("WeaponVisual") as Node3D
	combat.set_weapon(CombatSystem.Weapon.HATCHET)
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	combat.enable_hit_feedback = false

	var right_arm: Node3D = player.get_node_or_null("Visual/RightArm") as Node3D
	if right_arm == null:
		var loco := player.get_node_or_null("KerneLocomotion")
		if loco and loco.has_method("get_right_arm"):
			right_arm = loco.call("get_right_arm") as Node3D
	var arm_base := Transform3D()
	if right_arm:
		arm_base = right_arm.transform

	weapon_visual.position = Vector3(0.38, 1.05, -0.15)
	weapon_visual.rotation_degrees = Vector3(-15.0, 10.0, -25.0)
	combat._weapon_rest_transform = weapon_visual.transform

	var dirs := [
		{"key": "top", "dir": CombatSystem.StrikeDirection.TOP},
		{"key": "left", "dir": CombatSystem.StrikeDirection.LEFT},
		{"key": "right", "dir": CombatSystem.StrikeDirection.RIGHT},
	]
	var kinds := [
		{"key": "light", "kind": &"light"},
		{"key": "charged", "kind": &"heavy"},
	]
	var poses := ["windup", "contact", "follow"]

	var shot_idx := 0
	for kind_info in kinds:
		for dir_info in dirs:
			var timings: Dictionary = combat.resolved_hatchet_timings(kind_info["kind"], dir_info["dir"])
			var ms := "w %.0f · a %.0f · r %.0f ms" % [
				float(timings["windup"]) * 1000.0,
				float(timings["active"]) * 1000.0,
				float(timings["recovery"]) * 1000.0,
			]
			for pose in poses:
				shot_idx += 1
				var name := "%02d_%s_%s_%s" % [shot_idx, kind_info["key"], dir_info["key"], pose]
				# follow reads as recover mid-return; also shoot a true recover (rest-lerp)
				dir_label.text = "%s %s · %s" % [String(kind_info["key"]).to_upper(), String(dir_info["key"]).to_upper(), pose.to_upper()]
				timing_label.text = ms
				_reset_pose(player, combat, weapon_visual, right_arm, arm_base)
				if pose == "follow":
					# Mid-recovery blend toward rest for recover readability.
					_apply_pose(combat, weapon_visual, right_arm, arm_base, kind_info["kind"], dir_info["dir"], "follow")
					# Soften toward rest so it reads as recover, not just follow-through.
					weapon_visual.rotation_degrees = weapon_visual.rotation_degrees.lerp(
						Vector3(-15.0, 10.0, -25.0), 0.35
					)
					weapon_visual.position = weapon_visual.position.lerp(Vector3(0.38, 1.05, -0.15), 0.35)
					dir_label.text = "%s %s · RECOVER" % [String(kind_info["key"]).to_upper(), String(dir_info["key"]).to_upper()]
					name = "%02d_%s_%s_recover" % [shot_idx, kind_info["key"], dir_info["key"]]
				else:
					_apply_pose(combat, weapon_visual, right_arm, arm_base, kind_info["kind"], dir_info["dir"], pose)
				await process_frame
				await process_frame
				await process_frame
				var img: Image = vp.get_texture().get_image()
				var path := "%s/%s.png" % [out_dir, name]
				var err := img.save_png(path)
				print("WROTE ", path, " err=", err)

	# Idle reference
	shot_idx += 1
	_reset_pose(player, combat, weapon_visual, right_arm, arm_base)
	dir_label.text = "IDLE · ready"
	timing_label.text = "controls unchanged · hold LMB charge"
	await process_frame
	await process_frame
	var idle_path := "%s/%02d_idle_ready.png" % [out_dir, shot_idx]
	var idle_img: Image = vp.get_texture().get_image()
	print("WROTE ", idle_path, " err=", idle_img.save_png(idle_path))

	print("CAPTURE_DONE dir=", out_dir, " shots=", shot_idx)
	quit(0)


func _reset_pose(
	player: Node3D,
	combat: CombatSystem,
	weapon_visual: Node3D,
	right_arm: Node3D,
	arm_base: Transform3D
) -> void:
	player.global_position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	weapon_visual.position = Vector3(0.38, 1.05, -0.15)
	weapon_visual.rotation_degrees = Vector3(-15.0, 10.0, -25.0)
	combat._weapon_rest_transform = weapon_visual.transform
	combat.reset_weapon_pose()
	if right_arm:
		right_arm.transform = arm_base


func _apply_pose(
	combat: CombatSystem,
	weapon_visual: Node3D,
	right_arm: Node3D,
	arm_base: Transform3D,
	kind: StringName,
	direction: int,
	pose: String
) -> void:
	combat.reset_weapon_pose()
	combat._last_strike_direction = direction
	var poses: Dictionary = combat.call("_swing_poses", kind, direction)
	weapon_visual.rotation_degrees = poses["%s_rot" % pose]
	weapon_visual.position = poses["%s_pos" % pose]
	if right_arm == null:
		return
	var heavy := kind == &"heavy"
	var base := arm_base.basis.get_euler()
	match direction:
		CombatSystem.StrikeDirection.LEFT:
			match pose:
				"windup":
					right_arm.rotation = base + Vector3(deg_to_rad(-20.0 if heavy else -12.0), deg_to_rad(0.4), deg_to_rad(-0.5))
				"contact":
					right_arm.rotation = base + Vector3(deg_to_rad(12.0 if heavy else 6.0), deg_to_rad(-0.25), deg_to_rad(0.35))
				"follow":
					right_arm.rotation = base + Vector3(deg_to_rad(28.0 if heavy else 16.0), deg_to_rad(-0.5), deg_to_rad(0.55))
		CombatSystem.StrikeDirection.RIGHT:
			match pose:
				"windup":
					right_arm.rotation = base + Vector3(deg_to_rad(-20.0 if heavy else -12.0), deg_to_rad(-0.45), deg_to_rad(0.25))
				"contact":
					right_arm.rotation = base + Vector3(deg_to_rad(12.0 if heavy else 6.0), deg_to_rad(0.3), deg_to_rad(-0.2))
				"follow":
					right_arm.rotation = base + Vector3(deg_to_rad(28.0 if heavy else 16.0), deg_to_rad(0.55), deg_to_rad(-0.35))
		_:
			match pose:
				"windup":
					right_arm.rotation = base + Vector3(deg_to_rad(-40.0 if heavy else -22.0), 0.0, deg_to_rad(-0.35))
				"contact":
					right_arm.rotation = base + Vector3(deg_to_rad(28.0 if heavy else 14.0), 0.0, deg_to_rad(0.45))
				"follow":
					right_arm.rotation = base + Vector3(deg_to_rad(55.0 if heavy else 32.0), 0.0, deg_to_rad(0.7))
