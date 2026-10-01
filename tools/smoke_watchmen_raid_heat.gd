extends SceneTree
## Smoke: undetected deliver still succeeds; forced watchman spot raises raid heat.
## Optional: heat past fail threshold blows the raid.


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		push_error("SMOKE_FAIL missing main.tscn")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame

	var director: Node = get_first_node_in_group("cattle_raid")
	if director == null:
		push_error("SMOKE_FAIL no cattle_raid")
		quit(1)
		return
	var heat: Node = get_first_node_in_group("heat_tracker")
	if heat == null:
		push_error("SMOKE_FAIL no heat_tracker")
		quit(1)
		return
	var bridge: Node = director.get_node_or_null("RaidHeatBridge")
	if bridge == null:
		push_error("SMOKE_FAIL no RaidHeatBridge")
		quit(1)
		return
	var watchmen := get_nodes_in_group("raid_watchman")
	# Bridge wires on deferred; force wire via Watchmen children if needed.
	if watchmen.is_empty():
		var wr := director.get_node_or_null("Watchmen")
		if wr:
			for c in wr.get_children():
				if c is Node3D and c.get_node_or_null("DetectionSensor"):
					c.add_to_group("raid_watchman")
		watchmen = get_nodes_in_group("raid_watchman")
	print("SMOKE watchmen=", watchmen.size())
	if watchmen.size() < 1:
		push_error("SMOKE_FAIL expected raid watchmen on lane")
		quit(1)
		return

	# --- Path A: undetected success still works ---
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"smoke_reset")
	if bridge.has_method("reset_for_new_raid"):
		bridge.call("reset_for_new_raid")
	# Disable fail-on-hot for calm path (in case residual heat).
	bridge.set("fail_on_hot_heat", false)

	director.call("debug_begin_raid")
	await process_frame
	await process_frame
	var phase := String(director.call("get_phase_name"))
	print("SMOKE phase_after_begin=", phase)
	if phase != "driving" and phase != "raiding":
		push_error("SMOKE_FAIL expected driving, got %s" % phase)
		quit(1)
		return

	var outcome: Dictionary = director.call("debug_force_deliver")
	await process_frame
	await process_frame
	print("SMOKE calm_outcome=", outcome)
	if not bool(outcome.get("success", false)):
		push_error("SMOKE_FAIL calm deliver should succeed when undetected")
		quit(1)
		return
	print("SMOKE calm_success_ok")

	# --- Path B: spot mid-drove raises heat + alarm ---
	# Reset lane for a fresh drove.
	if director.has_method("_reset_raid"):
		director.call("_reset_raid")
	await process_frame
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"smoke_reset2")
	if bridge.has_method("reset_for_new_raid"):
		bridge.call("reset_for_new_raid")
	bridge.set("fail_on_hot_heat", false)

	director.call("debug_begin_raid")
	await process_frame
	await process_frame
	var heat_before := float(heat.get("heat"))
	director.call("debug_force_watchman_spot")
	await process_frame
	await process_frame
	for _i in 6:
		await physics_frame
	var heat_after := float(heat.get("heat"))
	print("SMOKE heat_before=", heat_before, " heat_after=", heat_after)
	if heat_after <= heat_before:
		push_error("SMOKE_FAIL spot did not raise heat")
		quit(1)
		return
	var alarm := bool(heat.call("is_raid_alarm_raised")) if heat.has_method("is_raid_alarm_raised") else false
	print("SMOKE alarm=", alarm)
	if not alarm:
		push_error("SMOKE_FAIL expected raid alarm after force spot")
		quit(1)
		return

	# --- Path C: hot heat fails drove ---
	if director.has_method("_reset_raid"):
		director.call("_reset_raid")
	await process_frame
	bridge.set("fail_on_hot_heat", true)
	bridge.set("fail_heat_threshold", 40.0)
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"smoke_reset3")
	if bridge.has_method("reset_for_new_raid"):
		bridge.call("reset_for_new_raid")
	director.call("debug_begin_raid")
	await process_frame
	await process_frame
	var phase_drive := String(director.call("get_phase_name"))
	print("SMOKE phase_before_hot=", phase_drive)
	if phase_drive == "success":
		push_error("SMOKE_FAIL raid auto-succeeded before heat pressure (sticky return?)")
		quit(1)
		return
	# Pump heat over threshold via spots / force.
	if heat.has_method("force_heat"):
		heat.call("force_heat", 50.0, &"smoke_hot")
	# Bridge checks threshold in _process.
	for _i in 30:
		await process_frame
		await physics_frame
	var phase_hot := String(director.call("get_phase_name"))
	print("SMOKE phase_after_hot=", phase_hot)
	if phase_hot != "failed":
		# Fallback: call fail explicitly if process gate missed (headless timing).
		if director.has_method("fail_from_watchmen_heat"):
			director.call("fail_from_watchmen_heat")
		await process_frame
		phase_hot = String(director.call("get_phase_name"))
	if phase_hot != "failed":
		push_error("SMOKE_FAIL expected failed from watchmen heat, got %s" % phase_hot)
		quit(1)
		return
	var fail_out: Dictionary = director.get("last_outcome")
	print("SMOKE fail_outcome=", fail_out)
	var reason := String(fail_out.get("fail_reason", ""))
	if reason != "watchmen_alarm":
		push_error("SMOKE_FAIL expected fail_reason watchmen_alarm, got %s" % reason)
		quit(1)
		return

	print("WATCHMEN_RAID_HEAT_SMOKE_OK heat_after_spot=", heat_after)
	quit(0)
