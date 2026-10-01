extends SceneTree
## Smoke: calm deliver; mid-drove spot raises heat/alarm; hot heat → ATTACK (no auto-fail).


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

	# --- Path A: undetected success ---
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"smoke_reset")
	if bridge.has_method("reset_for_new_raid"):
		bridge.call("reset_for_new_raid")
	bridge.set("fail_on_hot_heat", false)
	bridge.set("attack_on_hot_heat", true)

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

	# --- Path B: spot mid-drove ---
	if director.has_method("_reset_raid"):
		director.call("_reset_raid")
	await process_frame
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"smoke_reset2")
	if bridge.has_method("reset_for_new_raid"):
		bridge.call("reset_for_new_raid")

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

	# --- Path C: hot heat → ATTACK, raid NOT failed ---
	if director.has_method("_reset_raid"):
		director.call("_reset_raid")
	await process_frame
	if heat.has_method("force_heat"):
		heat.call("force_heat", 0.0, &"smoke_reset3")
	if bridge.has_method("reset_for_new_raid"):
		bridge.call("reset_for_new_raid")
	bridge.set("fail_on_hot_heat", false)
	bridge.set("attack_on_hot_heat", true)
	bridge.set("attack_heat_threshold", 40.0)
	director.call("debug_begin_raid")
	await process_frame
	await process_frame
	if bridge.has_method("debug_force_hot_attack"):
		bridge.call("debug_force_hot_attack")
	else:
		if heat.has_method("force_heat"):
			heat.call("force_heat", 90.0, &"smoke_hot")
		for _i in 30:
			await process_frame
			await physics_frame
	for _i in 10:
		await process_frame
		await physics_frame
	var phase_hot := String(director.call("get_phase_name"))
	print("SMOKE phase_after_hot=", phase_hot)
	if phase_hot == "failed":
		push_error("SMOKE_FAIL hot heat must NOT auto-fail raid (Q1)")
		quit(1)
		return
	var attacking := bool(bridge.call("are_watchmen_attacking")) if bridge.has_method("are_watchmen_attacking") else false
	print("SMOKE attacking=", attacking)
	if not attacking:
		push_error("SMOKE_FAIL expected watchmen ATTACK after hot heat")
		quit(1)
		return
	# Still completable while attacking
	var hot_deliver: Dictionary = director.call("debug_force_deliver")
	await process_frame
	print("SMOKE hot_deliver=", hot_deliver)
	if not bool(hot_deliver.get("success", false)):
		push_error("SMOKE_FAIL deliver should still succeed while watchmen attack")
		quit(1)
		return

	print("WATCHMEN_RAID_HEAT_SMOKE_OK heat_after_spot=", heat_after, " attack_ok=1")
	quit(0)
