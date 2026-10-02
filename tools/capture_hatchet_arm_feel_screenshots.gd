extends SceneTree
## Capture charge-aim left/right/top + mid-swing for hatchet arm-feel review.
## Mirrors directional-hatchet capture style (fill light, freeze physics, Label3D).

const _Combat := preload("res://systems/combat/combat_system.gd")
const _Loco := preload("res://scripts/characters/shared/kerne_locomotion.gd")


func _initialize() -> void:
	_run_capture()


func _run_capture() -> void:
	var out_dir := "/workspace/riocht-builds/screenshots/hatchet-arm-feel"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var world := Node3D.new()
	world.name = "HatchetArmFeelCapture"
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
	player.set_physics_process(false)
	player.set_process(false)
	player.velocity = Vector3.ZERO
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false

	var cam := Camera3D.new()
	cam.fov = 46.0
	world.add_child(cam)
	# Slightly closer / higher so arm cock reads clearly.
	cam.look_at_from_position(Vector3(2.35, 1.75, 1.85), Vector3(0.2, 1.2, -0.1), Vector3.UP)
	cam.current = true

	var dir_label := Label3D.new()
	dir_label.name = "DirLabel"
	dir_label.font_size = 64
	dir_label.pixel_size = 0.004
	dir_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dir_label.modulate = Color(1.0, 0.95, 0.7)
	dir_label.outline_size = 10
	dir_label.position = Vector3(0.0, 2.2, 0.0)
	player.add_child(dir_label)

	await process_frame
	await process_frame
	await process_frame

	var _reg = _Combat
	var _reg2 = _Loco
	var combat := player.get_node("CombatSystem") as CombatSystem
	var weapon_visual := player.get_node("WeaponVisual") as Node3D
	var loco := player.get_node("KerneLocomotion") as KerneLocomotion
	combat.set_weapon(CombatSystem.Weapon.HATCHET)
	combat.hit_stop_light = 0.0
	combat.hit_stop_heavy = 0.0
	combat.enable_hit_feedback = false

	if loco and loco.joints.is_empty():
		loco.rebuild()

	var shots: Array = [
		{"name": "01_charge_left", "mode": "charge", "ratio": 1.0, "dir": CombatSystem.StrikeDirection.LEFT, "label": "CHARGE AIM · LEFT"},
		{"name": "02_charge_right", "mode": "charge", "ratio": 1.0, "dir": CombatSystem.StrikeDirection.RIGHT, "label": "CHARGE AIM · RIGHT"},
		{"name": "03_charge_top", "mode": "charge", "ratio": 1.0, "dir": CombatSystem.StrikeDirection.TOP, "label": "CHARGE AIM · TOP"},
		{"name": "04_mid_swing_top", "mode": "strike", "kind": &"heavy", "dir": CombatSystem.StrikeDirection.TOP, "pose": "contact", "label": "MID-SWING · TOP"},
		{"name": "05_idle_hold", "mode": "idle", "label": "IDLE HOLD · hatchet ready"},
		{"name": "06_mid_swing_left", "mode": "strike", "kind": &"heavy", "dir": CombatSystem.StrikeDirection.LEFT, "pose": "contact", "label": "MID-SWING · LEFT"},
	]

	for shot in shots:
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		if loco:
			loco.clear_combat_additives()
			loco.reset_to_rest()
		combat.reset_weapon_pose()
		dir_label.text = String(shot.get("label", shot["name"]))
		match String(shot["mode"]):
			"idle":
				_pose_idle_hold(loco, weapon_visual, combat)
				cam.look_at_from_position(Vector3(2.35, 1.75, 1.85), Vector3(0.2, 1.2, -0.1), Vector3.UP)
			"charge":
				_pose_charge_arm(loco, weapon_visual, combat, float(shot["ratio"]), int(shot["dir"]))
				# Side-biased cams so left/right cock separates; top from slightly lower front.
				match int(shot["dir"]):
					CombatSystem.StrikeDirection.LEFT:
						cam.look_at_from_position(Vector3(2.8, 1.65, 0.35), Vector3(0.15, 1.25, -0.1), Vector3.UP)
					CombatSystem.StrikeDirection.RIGHT:
						cam.look_at_from_position(Vector3(0.2, 1.7, 2.7), Vector3(0.25, 1.25, -0.05), Vector3.UP)
					_:
						cam.look_at_from_position(Vector3(2.1, 1.95, 1.7), Vector3(0.15, 1.45, -0.05), Vector3.UP)
			"strike":
				_pose_strike(loco, weapon_visual, combat, shot["kind"], int(shot["dir"]), String(shot["pose"]))
				cam.look_at_from_position(Vector3(2.4, 1.55, 1.9), Vector3(0.2, 1.05, -0.15), Vector3.UP)
		# Nudge loco once so additives stick on frozen player.
		if loco:
			loco.tick(0.016, 0.0, false, false, true, Vector3.ZERO)
		await process_frame
		await process_frame
		await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, String(shot["name"])]
		var err := img.save_png(path)
		print("WROTE ", path, " err=", err)

	print("CAPTURE_DONE dir=", out_dir)
	quit(0)


func _pose_idle_hold(loco: KerneLocomotion, weapon_visual: Node3D, combat: CombatSystem) -> void:
	var pose: Dictionary = CombatSystem.hatchet_idle_arm_pose()
	if loco:
		loco.set_combat_additive("right_arm", pose["right_arm"] as Vector3)
		loco.set_combat_additive("right_forearm", pose["right_forearm"] as Vector3)
		loco.set_combat_additive("torso", pose["torso"] as Vector3)
	_glue_weapon_to_forearm(loco, weapon_visual, Vector3(deg_to_rad(-12.0), deg_to_rad(6.0), deg_to_rad(-14.0)))
	if combat:
		combat.set_weapon_rest_transform(weapon_visual.transform)


func _pose_charge_arm(
	loco: KerneLocomotion,
	weapon_visual: Node3D,
	combat: CombatSystem,
	ratio: float,
	direction: int
) -> void:
	combat.is_charging = true
	combat.charge_ratio = ratio
	combat.charge_direction = direction
	var pose: Dictionary = CombatSystem.hatchet_charge_arm_pose(direction, ratio)
	if loco:
		loco.set_combat_additive("right_arm", pose["right_arm"] as Vector3)
		loco.set_combat_additive("right_forearm", pose["right_forearm"] as Vector3)
		loco.set_combat_additive("torso", pose["torso"] as Vector3)
	var t := clampf(ratio, 0.0, 1.0)
	t = t * t
	var rot := Vector3(deg_to_rad(-12.0), deg_to_rad(6.0), deg_to_rad(-14.0))
	match direction:
		CombatSystem.StrikeDirection.LEFT:
			rot = Vector3(
				deg_to_rad(lerpf(-12.0, -48.0, t)),
				deg_to_rad(lerpf(6.0, 78.0, t)),
				deg_to_rad(lerpf(-14.0, 36.0, t))
			)
		CombatSystem.StrikeDirection.RIGHT:
			rot = Vector3(
				deg_to_rad(lerpf(-12.0, -52.0, t)),
				deg_to_rad(lerpf(6.0, -68.0, t)),
				deg_to_rad(lerpf(-14.0, -48.0, t))
			)
		_:
			rot = Vector3(
				deg_to_rad(lerpf(-12.0, -118.0, t)),
				deg_to_rad(lerpf(6.0, 18.0, t)),
				deg_to_rad(lerpf(-14.0, 70.0, t))
			)
	_glue_weapon_to_forearm(loco, weapon_visual, rot)


func _pose_strike(
	loco: KerneLocomotion,
	weapon_visual: Node3D,
	combat: CombatSystem,
	kind: StringName,
	direction: int,
	pose_name: String
) -> void:
	combat.is_charging = false
	combat._last_strike_direction = direction
	var poses: Dictionary = combat.call("_swing_poses", kind, direction)
	weapon_visual.rotation_degrees = poses["%s_rot" % pose_name]
	weapon_visual.position = poses["%s_pos" % pose_name]
	# Arm at contact / mid-swing additive matching player swing table.
	var heavy := kind == &"heavy"
	var arm := Vector3.ZERO
	var torso := Vector3.ZERO
	match direction:
		CombatSystem.StrikeDirection.LEFT:
			arm = Vector3(deg_to_rad(20.0 if heavy else 12.0), deg_to_rad(-28.0), deg_to_rad(34.0 if heavy else 22.0))
			torso = Vector3(deg_to_rad(8.0), deg_to_rad(-14.0 if heavy else -8.0), 0.0)
		CombatSystem.StrikeDirection.RIGHT:
			arm = Vector3(deg_to_rad(20.0 if heavy else 12.0), deg_to_rad(34.0), deg_to_rad(-22.0 if heavy else -12.0))
			torso = Vector3(deg_to_rad(8.0), deg_to_rad(16.0 if heavy else 10.0), 0.0)
		_:
			arm = Vector3(deg_to_rad(48.0 if heavy else 28.0), deg_to_rad(6.0), deg_to_rad(32.0 if heavy else 20.0))
			torso = Vector3(deg_to_rad(20.0 if heavy else 12.0), deg_to_rad(5.0), 0.0)
	if loco:
		loco.set_combat_additive("right_arm", arm)
		loco.set_combat_additive("right_forearm", Vector3(arm.x * 0.45, 0.0, 0.0))
		loco.set_combat_additive("torso", torso)


func _glue_weapon_to_forearm(loco: KerneLocomotion, weapon_visual: Node3D, rot: Vector3) -> void:
	if weapon_visual == null:
		return
	var forearm: Node3D = null
	if loco:
		forearm = loco.get_joint("right_forearm")
	if forearm:
		weapon_visual.global_position = forearm.to_global(Vector3(0.0, -0.28, 0.05))
	else:
		weapon_visual.position = Vector3(0.38, 1.15, -0.12)
	weapon_visual.rotation = rot
