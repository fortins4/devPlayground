extends SceneTree
## Headless smoke: investigation delay, walk hooks, progress UI, cancel/confirm.


func _initialize() -> void:
	var ok := true
	var world := Node3D.new()
	root.add_child(world)

	var sentry := (load("res://scenes/characters/npcs/sentry.tscn") as PackedScene).instantiate()
	var corpse := (load("res://scenes/characters/npcs/draggable_corpse.tscn") as PackedScene).instantiate()
	world.add_child(sentry)
	world.add_child(corpse)
	sentry.global_position = Vector3(0, 0, 0)
	corpse.global_position = Vector3(0, 0, 4)

	var heat := Node.new()
	heat.set_script(load("res://systems/stealth/heat_tracker.gd"))
	heat.set("scan_interval", 0.2)
	heat.set("investigation_delay", 2.0)
	heat.set("honor_coupling_enabled", false)
	world.add_child(heat)

	await process_frame
	await process_frame

	# API presence
	for m in ["begin_body_investigate", "update_body_investigate", "cancel_body_investigate", "confirm_body_discovered", "is_investigating_body"]:
		if not sentry.has_method(m):
			push_error("sentry missing " + m)
			ok = false
	for m in ["set_investigation", "is_under_investigation"]:
		if not corpse.has_method(m):
			push_error("corpse missing " + m)
			ok = false
	for m in ["get_primary_investigation_remaining", "get_active_investigation_count"]:
		if not heat.has_method(m):
			push_error("heat missing " + m)
			ok = false

	# Delay default
	var delay := float(heat.get("investigation_delay"))
	if not is_equal_approx(delay, 2.0):
		push_error("expected investigation_delay 2.0 got %s" % delay)
		ok = false

	# Manual investigate path
	sentry.call("begin_body_investigate", corpse, 2.0)
	if not bool(sentry.call("is_investigating_body")):
		push_error("sentry should be investigating")
		ok = false
	corpse.call("set_investigation", true, 1.5)
	if not bool(corpse.call("is_under_investigation")):
		push_error("corpse should be under scrutiny")
		ok = false

	# Investigate tick should aim velocity toward body (move_and_slide needs floor in play).
	sentry.call("_investigate_tick", 0.05)
	var vel: Vector3 = sentry.velocity
	var to_body: Vector3 = corpse.global_position - sentry.global_position
	to_body.y = 0.0
	print("investigate vel=", vel, " to_body=", to_body)
	if vel.length() < 0.5:
		push_error("sentry investigate should set walk velocity, vel=%s" % vel)
		ok = false
	elif to_body.normalized().dot(Vector3(vel.x, 0.0, vel.z).normalized()) < 0.7:
		push_error("sentry velocity not aimed at body")
		ok = false
	# Soft-close distance manually (greybox stand-in for move_and_slide on flat floor).
	for i in 30:
		sentry.call("_investigate_tick", 0.05)
		var step: Vector3 = Vector3(sentry.velocity.x, 0.0, sentry.velocity.z) * 0.05
		sentry.global_position += step
	var dist: float = sentry.global_position.distance_to(corpse.global_position)
	print("after simulated walk dist=", dist)
	if dist > 3.0:
		push_error("sentry should have closed distance toward body, dist=%s" % dist)
		ok = false

	sentry.call("confirm_body_discovered")
	if bool(sentry.call("is_investigating_body")):
		push_error("sentry should clear investigate target on confirm")
		ok = false

	sentry.call("begin_body_investigate", corpse, 1.0)
	sentry.call("cancel_body_investigate")
	if bool(sentry.call("is_investigating_body")):
		push_error("cancel should clear target")
		ok = false

	# Heat discovery confirm path via internal start
	heat.set("_investigating", {corpse.get_instance_id(): 0.01})
	heat.set("_investigate_sentry", {corpse.get_instance_id(): sentry})
	heat.set("_investigate_total", {corpse.get_instance_id(): 2.0})
	await process_frame
	# tick a bit
	for i in 5:
		heat.call("_tick_investigations", 0.05)
		await process_frame
	var h := float(heat.call("get_heat"))
	print("heat after confirm tick=", h)
	if h < 20.0:
		push_error("expected discover bump heat, got %s" % h)
		ok = false

	if ok:
		print("SMOKE OK stealth-investigation-polish")
		quit(0)
	else:
		print("SMOKE FAIL")
		quit(1)
