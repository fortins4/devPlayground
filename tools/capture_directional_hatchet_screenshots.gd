extends SceneTree
## Capture idle / charging / top·left·right strikes (light + charged) for directional hatchet.


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/directional-hatchet"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "DirectionalHatchetCapture"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.44, 0.54, 0.62)
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
	# Freeze player — PlaneMesh has no collision; gravity would drop them out of frame.
	player.set_physics_process(false)
	player.set_process(false)
	player.velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(2.25, 1.6, 2.15), Vector3(0.3, 1.15, -0.15), Vector3.UP)
	cam.current = true

	# Direction label overlay (3D)
	var dir_label := Label3D.new()
	dir_label.name = "DirLabel"
	dir_label.font_size = 64
	dir_label.pixel_size = 0.004
	dir_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dir_label.modulate = Color(1.0, 0.95, 0.7)
	dir_label.outline_size = 10
	dir_label.position = Vector3(0.0, 2.15, 0.0)
	player.add_child(dir_label)

	await process_frame
	await process_frame
	await process_frame

	var combat := player.get_node("CombatSystem") as CombatSystem
	var weapon_visual := player.get_node("WeaponVisual") as Node3D
	combat.set_weapon(CombatSystem.Weapon.HATCHET)
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	combat.enable_hit_feedback = false

	# Resolve arm for additive pose hints (may be procedural kerne)
	var right_arm: Node3D = player.get_node_or_null("Visual/RightArm") as Node3D
	if right_arm == null:
		var loco := player.get_node_or_null("KerneLocomotion")
		if loco and loco.has_method("get_right_arm"):
			right_arm = loco.call("get_right_arm") as Node3D
	var arm_base := Transform3D()
	if right_arm:
		arm_base = right_arm.transform

	# Place hatchet at a readable right-hand grip (physics sync is frozen).
	weapon_visual.position = Vector3(0.38, 1.05, -0.15)
	weapon_visual.rotation_degrees = Vector3(-15.0, 10.0, -25.0)
	combat._weapon_rest_transform = weapon_visual.transform

	# Slightly side-on camera so left/right arcs separate cleanly.
	cam.look_at_from_position(Vector3(2.55, 1.55, 1.55), Vector3(0.25, 1.1, -0.2), Vector3.UP)

	var shots: Array = [
		{"name": "01_idle_hatchet_ready", "mode": "idle", "kind": &"light", "dir": CombatSystem.StrikeDirection.TOP, "pose": "idle", "label": "IDLE · hatchet ready"},
		{"name": "02_charging_mid", "mode": "charge", "ratio": 0.45, "dir": CombatSystem.StrikeDirection.TOP, "label": "CHARGING 45% · TOP"},
		{"name": "03_charging_full", "mode": "charge", "ratio": 1.0, "dir": CombatSystem.StrikeDirection.TOP, "label": "CHARGING 100% · TOP"},
		{"name": "04_top_strike_light", "mode": "strike", "kind": &"light", "dir": CombatSystem.StrikeDirection.TOP, "pose": "contact", "label": "TOP light"},
		{"name": "05_top_strike_charged", "mode": "strike", "kind": &"heavy", "dir": CombatSystem.StrikeDirection.TOP, "pose": "contact", "label": "TOP charged"},
		{"name": "06_left_strike_light", "mode": "strike", "kind": &"light", "dir": CombatSystem.StrikeDirection.LEFT, "pose": "contact", "label": "LEFT light"},
		{"name": "07_left_strike_charged", "mode": "strike", "kind": &"heavy", "dir": CombatSystem.StrikeDirection.LEFT, "pose": "contact", "label": "LEFT charged"},
		{"name": "08_right_strike_light", "mode": "strike", "kind": &"light", "dir": CombatSystem.StrikeDirection.RIGHT, "pose": "contact", "label": "RIGHT light"},
		{"name": "09_right_strike_charged", "mode": "strike", "kind": &"heavy", "dir": CombatSystem.StrikeDirection.RIGHT, "pose": "contact", "label": "RIGHT charged"},
		{"name": "10_top_charged_windup", "mode": "strike", "kind": &"heavy", "dir": CombatSystem.StrikeDirection.TOP, "pose": "windup", "label": "TOP charged windup"},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		weapon_visual.position = Vector3(0.38, 1.05, -0.15)
		weapon_visual.rotation_degrees = Vector3(-15.0, 10.0, -25.0)
		combat._weapon_rest_transform = weapon_visual.transform
		combat.reset_weapon_pose()
		if right_arm:
			right_arm.transform = arm_base
		dir_label.text = String(shot.get("label", shot["name"]))
		match String(shot["mode"]):
			"idle":
				pass
			"charge":
				_pose_charge(combat, weapon_visual, float(shot["ratio"]), shot["dir"])
			"strike":
				_apply_pose(combat, weapon_visual, right_arm, arm_base, shot["kind"], shot["dir"], String(shot["pose"]))
		await process_frame
		await process_frame
		await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["name"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err)

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)


func _pose_charge(combat: CombatSystem, _weapon_visual: Node3D, ratio: float, direction: int) -> void:
	combat.is_charging = true
	combat.charge_ratio = ratio
	combat.charge_direction = direction
	combat.call("_update_charge_pose", ratio, direction)


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
	if pose == "idle":
		return
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
