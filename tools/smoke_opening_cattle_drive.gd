extends SceneTree
## Smoke: opening cattle drive loads, spawn near house, herd far + idle, first goad stirs the herd,
## un-pushed drove stalls, scripted goad drive gets >= need head home → soft success,
## then (6/6 only) Cian swings the pen gate shut and latches it → drive step completes.
## The scene always runs the set sequence, so this is the sequence flow: need = all 6 (the
## bogged cow is the sixth head — debug-rejoined here), the dog ambush springs on the lane and
## the bot sees it off and regathers; R after success keeps the pen and the sequence.
## Run with --fixed-fps 60 so the drive sim is not real-time bound:
##   godot --headless --path . --fixed-fps 60 --script res://tools/smoke_opening_cattle_drive.gd

const SCENE := "res://scenes/prologue/opening_cattle_drive.tscn"
const DRIVE_LIMIT_SECS := 480.0

var _fail := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail = true
		push_error("SMOKE_FAIL " + msg)
		print("SMOKE_FAIL " + msg)


func _wait_physics(secs: float) -> void:
	var frames := int(secs * Engine.physics_ticks_per_second)
	for i in frames:
		await physics_frame


func _run() -> void:
	var ps := load(SCENE) as PackedScene
	_check(ps != null, "missing " + SCENE)
	if ps == null:
		quit(1)
		return
	root.add_child(ps.instantiate())
	await _wait_physics(0.3)
	# Opening is a set sequence now: jump straight to this chore's step (sequence-only debug path).
	var _seq_dbg: Node = get_first_node_in_group("opening_sequence")
	if _seq_dbg:
		_seq_dbg.call("force_advance_to", &"drive")
		get_first_node_in_group("opening_bogged_cow").call("force_rejoin")  # her beat: debug path

	var director: Node = get_first_node_in_group("opening_drive")
	var player := get_first_node_in_group("player") as Node3D
	_check(director != null, "no OpeningDriveDirector")
	_check(player != null, "no player")
	if _fail:
		quit(1)
		return
	var cows: Array = director.call("get_cows")
	var home: Vector3 = director.call("home_center")
	var path: Array = director.call("path_home_first")
	_check(cows.size() >= 5, "expected >=5 cows, got %d" % cows.size())
	_check(path.size() >= 5, "expected >=5 lane markers, got %d" % path.size())
	_check(String(director.call("get_stage_name")) == "walk_out", "stage should start walk_out")
	var spawn_to_home := player.global_position.distance_to(home)
	var herd_to_home := Vector3(director.call("herd_centroid")).distance_to(home)
	print("SMOKE spawn_to_home=%.1f herd_to_home=%.1f" % [spawn_to_home, herd_to_home])
	_check(spawn_to_home < 16.0, "player should spawn near the house/pen")
	_check(herd_to_home > 80.0, "pasture herd should graze a good distance from home")
	var combat := player.get_node_or_null("CombatSystem")
	_check(combat != null and String(combat.call("weapon_name")) == "goad", "opening kit should start on goad")

	# Pen gate: stands open, and is inert before 6/6 (no prompt, E does nothing).
	var gate: Node = get_first_node_in_group("opening_pen_gate")
	_check(gate != null, "no OpeningPenGateChore")
	if gate:
		_check(String(gate.call("gate_state")) == "open", "pen gate should start open")
		_check(not bool(gate.call("blocker_enabled")), "open gate must not block the gateway")
		var spawn_xf := player.global_transform
		player.global_position = Vector3(gate.call("stand_point")) + Vector3(0, 0.1, 0)
		await _wait_physics(0.1)
		_check(String(gate.call("interact_prompt")) == "", "no gate prompt before 6/6")
		_check(not bool(gate.call("try_interact")), "gate must not latch before 6/6")
		_check(String(gate.call("gate_state")) == "open", "gate must stay open before 6/6")
		player.global_transform = spawn_xf
		await _wait_physics(0.1)

	# Family callout at the house as the drive leaves (opening beat).
	await _wait_physics(1.6)
	_check(bool(director.call("family_has_spoken")), "family callout should fire in the opening beat")
	print("SMOKE family_speaker=%s bark_visible=%s" % [director.call("family_speaker"), director.call("family_bark_visible")])

	# Idle until goaded.
	await _wait_physics(2.0)
	var any_driven := false
	for c in cows:
		if bool(c.get("driven")) or bool(c.get("herded")):
			any_driven = true
	_check(not any_driven, "cattle should idle-graze until goaded")

	# Walk out (teleport) → at_herd.
	var centroid: Vector3 = director.call("herd_centroid")
	player.global_position = centroid + Vector3(0, 0.2, -12.0)
	await _wait_physics(0.3)
	_check(String(director.call("get_stage_name")) == "at_herd", "stage should be at_herd near cattle (got %s)" % director.call("get_stage_name"))

	# First prod stirs the herd. Player then walks off → drove should stall (no auto-walk home).
	var cow0: Node3D = cows[0]
	var start0 := cow0.global_position
	var fwd: Vector3 = (home - cow0.global_position)
	fwd.y = 0.0
	cow0.call("apply_goad", cow0.global_position - fwd.normalized() * 2.0, fwd.normalized(), 1.0, &"light")
	await _wait_physics(0.1)
	_check(String(director.call("get_stage_name")) == "driving", "stage should be driving after first goad")
	var herded := 0
	for c in cows:
		if bool(c.get("herded")) or bool(c.get("driven")):
			herded += 1
	print("SMOKE stirred_herd=%d/%d" % [herded, cows.size()])
	_check(herded == cows.size(), "first goad should stir the whole herd")
	player.global_position = centroid + Vector3(-45.0, 0.2, 10.0)
	await _wait_physics(14.0)
	var moved := cow0.global_position.distance_to(start0)
	var fresh := float(cow0.call("drive_freshness"))
	print("SMOKE unpushed_cow moved=%.1f freshness=%.2f stalled=%s" % [moved, fresh, cow0.call("is_stalled")])
	_check(fresh <= 0.02 and bool(cow0.call("is_stalled")), "un-pushed drove should go stale")
	_check(moved < 40.0, "un-pushed cow should not walk itself home (moved %.1f)" % moved)
	_check(int(director.call("home_count")) == 0, "no cow should be home without driving")

	# Scripted goad drive.
	var Bot = load("res://tools/opening_drive_bot.gd")
	var bot = Bot.new(director, player)
	var t := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var bog_seen := 0
	var next_log := 30.0
	while t < DRIVE_LIMIT_SECS and String(director.call("get_stage_name")) != "success":
		bot.tick(dt)
		await physics_frame
		t += dt
		bog_seen = maxi(bog_seen, int(director.call("bogged_count")))
		if t >= next_log:
			next_log += 30.0
			print("SMOKE t=%.0fs home=%d driven=%d stalled=%d bogged=%d centroid=%s" % [
				t, director.call("home_count"), director.call("driven_count"),
				director.call("stalled_count"), director.call("bogged_count"),
				str(Vector3(director.call("herd_centroid")).snapped(Vector3.ONE))])
	var home_n := int(director.call("home_count"))
	print("SMOKE drive_secs=%.1f prods=%d home=%d/%d max_bogged=%d" % [t, bot.prods, home_n, cows.size(), bog_seen])
	_check(String(director.call("get_stage_name")) == "success", "soft success not reached in %.0fs" % DRIVE_LIMIT_SECS)
	_check(home_n >= int(director.call("need_count")), "home count below need")
	_check(int(director.call("need_count")) == cows.size() and cows.size() == 6, "sequence flow needs all 6 (need=%d cows=%d)" % [director.call("need_count"), cows.size()])
	_check(bool(director.get("succeeded")), "director.succeeded false")
	_check(bool(director.call("ambush_fired")), "dog ambush should spring on the lane")
	print("SMOKE ambush=%s dog_scares=%d dog_state=%s" % [director.call("ambush_fired"), bot.dog_scares, get_first_node_in_group("opening_stray_dog").call("dog_state")])

	# 6/6 home: the drive step waits on the gate latch.
	_check(gate != null and String(gate.call("gate_state")) == "open", "gate should still be open at 6/6")
	_check(StringName(_seq_dbg.call("current_step_id")) == &"drive", "drive step must wait for the latch")
	_check(String(director.call("drive_beat")) == "latch", "drive beat after 6/6 should be latch")
	await _wait_physics(4.2)   # let the 6/6 flash run out so the prompt surfaces
	player.global_position = Vector3(gate.call("stand_point")) + Vector3(0, 0.1, 0)
	await _wait_physics(0.1)
	var prompt := String(gate.call("interact_prompt"))
	print("SMOKE gate_prompt=%s" % prompt)
	_check(prompt.begins_with("E —"), "gate prompt after 6/6 at the gateway, got '%s'" % prompt)
	_check(bool(gate.call("try_interact")), "E at the gateway after 6/6 should start the gate")
	await _wait_physics(0.45)
	var mid_swing := float(gate.call("swing_fraction"))
	_check(mid_swing > 0.2 and mid_swing < 0.95 and not bool(gate.call("pen_latched")), "gate should be mid-swing (%.2f)" % mid_swing)
	await _wait_physics(1.2)
	_check(bool(gate.call("gate_closed")), "gate should be shut")
	_check(bool(gate.call("pen_latched")) and float(gate.call("latch_fraction")) >= 1.0, "latch should be engaged")
	_check(bool(gate.call("blocker_enabled")), "shut gate should block the gateway")
	var tips: Array = gate.call("leaf_tip_positions")
	var gc: Vector3 = gate.call("gate_center")
	_check(Vector3(tips[0]).distance_to(Vector3(tips[1])) < 0.4 and absf(Vector3(tips[0]).z - gc.z) < 0.15, "leaves should meet across the gateway (%s)" % str(tips))
	var ray := PhysicsRayQueryParameters3D.create(Vector3(gc.x + 0.6, gc.y + 0.9 + OpeningTerrain.surface_y(gc.x, gc.z), gc.z + 1.0), Vector3(gc.x + 0.6, gc.y + 0.9 + OpeningTerrain.surface_y(gc.x, gc.z), gc.z - 1.0))
	ray.collision_mask = 1
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty() and String((hit.collider as Node).name) == "GateBlocker", "ray through the shut gateway should hit the gate (%s)" % str(hit.get("collider")))
	_check(bool(director.get("pen_latched")), "director should know the pen is latched")
	_check(StringName(_seq_dbg.call("current_step_id")) != &"drive", "latch should complete the drive step")
	_check(String(director.call("flash_text")) == "", "latch must not flash (quiet walk out), got '%s'" % director.call("flash_text"))
	print("SMOKE gate=%s swing_mid=%.2f step=%s" % [gate.call("gate_state"), mid_swing, _seq_dbg.call("current_step_id")])
	# Walk out quietly: no new flash for a few seconds after the latch.
	var noisy := ""
	for i in 180:
		await physics_frame
		var ft := String(director.call("flash_text"))
		if ft != "":
			noisy = ft
	_check(noisy == "", "walk out after the latch should stay quiet, got '%s'" % noisy)

	# R after success (sequence flow): a failsafe, not a restart — the pen and the sequence stay.
	director.call("reset_herd")
	await _wait_physics(0.2)
	_check(int(director.call("home_count")) == home_n, "R after success must keep the pen")
	_check(bool(director.get("succeeded")), "R after success must keep success")
	_check(StringName(_seq_dbg.call("current_step_id")) != &"drive", "R must not undo the sequence")

	if _fail:
		print("OPENING_CATTLE_DRIVE_SMOKE_FAIL")
		quit(1)
	else:
		print("OPENING_CATTLE_DRIVE_SMOKE_OK home=%d/%d drive_secs=%.0f prods=%d" % [home_n, cows.size(), t, bot.prods])
		quit(0)
