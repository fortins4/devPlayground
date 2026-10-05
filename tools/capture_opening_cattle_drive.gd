extends SceneTree
## Capture stills of the opening cattle-drive greybox. Needs a real GL context
## (xvfb DISPLAY=:1 + omit --headless). Bare --headless leaves SubViewports blank.

const SCENE := "res://scenes/prologue/opening_cattle_drive.tscn"
const OUT := "/workspace/riocht-builds/opening-cattle-drive"
const BotScript := preload("res://tools/opening_drive_bot.gd")


func _initialize() -> void:
	_run()


func _wait_physics(secs: float) -> void:
	var frames := maxi(1, int(secs * Engine.physics_ticks_per_second))
	for i in frames:
		await physics_frame


func _snap(vp: SubViewport, name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("CAPTURE_FAIL blank texture for " + name)
		return
	# Reject near-blank frames (mean luma too low / too uniform).
	var sample := img.duplicate()
	sample.resize(64, 36, Image.INTERPOLATE_NEAREST)
	var sum := 0.0
	var n := 0
	for y in sample.get_height():
		for x in sample.get_width():
			sum += sample.get_pixel(x, y).get_luminance()
			n += 1
	var mean := sum / float(maxi(1, n))
	var path := "%s/%s.png" % [OUT, name]
	var err := img.save_png(path)
	print("CAPTURE %s mean_luma=%.3f err=%s path=%s" % [name, mean, err, path])
	if mean < 0.04:
		push_error("CAPTURE_FAIL blankish " + name)


func _aim(cam: Camera3D, from: Vector3, look: Vector3) -> void:
	cam.global_position = from
	cam.look_at(look, Vector3.UP)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.own_world_3d = true
	root.add_child(vp)

	var scene := (load(SCENE) as PackedScene).instantiate() as Node3D
	vp.add_child(scene)
	await _wait_physics(0.5)

	var director: Node = null
	for n in get_nodes_in_group("opening_drive"):
		# Prefer the one inside our SubViewport world.
		if vp.is_ancestor_of(n):
			director = n
			break
	if director == null:
		director = get_first_node_in_group("opening_drive")
	var player := get_first_node_in_group("player") as Node3D
	# Prefer player under our scene.
	for n in get_nodes_in_group("player"):
		if vp.is_ancestor_of(n):
			player = n as Node3D
			break
	if director == null or player == null:
		push_error("CAPTURE_FAIL missing director/player")
		quit(1)
		return

	# Mute the player camera; use a dedicated capture cam.
	var pcam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if pcam:
		pcam.current = false
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	scene.add_child(cam)

	var home: Vector3 = director.call("home_center")
	var cows: Array = director.call("get_cows")
	var path: Array = director.call("path_home_first")
	var pasture_c: Vector3 = director.call("herd_centroid")

	# 1) House / byre / home pen — player near spawn looking south.
	_aim(cam, Vector3(-6.0, 5.5, 22.0), Vector3(0.0, 1.5, 0.0))
	await _snap(vp, "01_house")

	# 2) Path bend (west swing around the bog) — elevated, facing the turn + bog edge.
	var bend: Vector3 = path[2] if path.size() > 2 else Vector3(-12, 0, 44)  # Bend2
	_aim(cam, bend + Vector3(18.0, 11.0, -6.0), bend + Vector3(-6.0, 0.5, 10.0))
	await _snap(vp, "02_path_bend")

	# 3) Pasture cattle idle.
	_aim(cam, pasture_c + Vector3(-10.0, 6.5, -16.0), pasture_c + Vector3(2.0, 0.5, 4.0))
	await _snap(vp, "03_pasture_cattle")

	# 4) Drive moment — scripted bot pushes a few seconds, then freeze-frame.
	player.global_position = pasture_c + Vector3(0.0, 0.2, -8.0)
	await _wait_physics(0.2)
	# First goad to stir.
	var cow0: Node3D = cows[0]
	var fwd := (home - cow0.global_position)
	fwd.y = 0.0
	cow0.call("apply_goad", cow0.global_position - fwd.normalized() * 2.0, fwd.normalized(), 1.0, &"light")
	await _wait_physics(0.1)
	var bot = BotScript.new(director, player)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for i in int(12.0 * Engine.physics_ticks_per_second):
		bot.tick(dt)
		await physics_frame
	var mid: Vector3 = director.call("herd_centroid")
	_aim(cam, mid + Vector3(12.0, 7.0, 10.0), mid + Vector3(-2.0, 0.5, -4.0))
	await _snap(vp, "04_drive_moment")

	print("CAPTURE_OPENING_CATTLE_DRIVE_OK")
	quit(0)
