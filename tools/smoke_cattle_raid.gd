extends SceneTree
## Smoke: load main, start cattle raid, force deliver, assert economy loot.


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

	var director: Node = root.get_children().back().get_node_or_null("CattleRaidLane")
	if director == null:
		# Fallback: group search
		director = get_first_node_in_group("cattle_raid")
	if director == null:
		push_error("SMOKE_FAIL no CattleRaidLane")
		quit(1)
		return

	var ringfort := get_first_node_in_group("ringfort")
	if ringfort == null:
		push_error("SMOKE_FAIL no ringfort")
		quit(1)
		return
	var cattle: CattleEconomy = ringfort.get_node("CattleEconomy") as CattleEconomy
	var herd_before := cattle.get_herd_size()
	print("SMOKE herd_before=", herd_before)

	if director.has_method("debug_begin_raid"):
		director.call("debug_begin_raid")
	await process_frame
	await process_frame
	var phase_name := String(director.call("get_phase_name"))
	print("SMOKE phase_after_begin=", phase_name)
	if phase_name != "driving" and phase_name != "raiding":
		push_error("SMOKE_FAIL expected driving/raiding, got %s" % phase_name)
		quit(1)
		return

	var outcome: Dictionary = director.call("debug_force_deliver")
	await process_frame
	await process_frame
	print("SMOKE outcome=", outcome)
	if not bool(outcome.get("ok", false)) or not bool(outcome.get("success", false)):
		push_error("SMOKE_FAIL resolve not successful")
		quit(1)
		return
	var gained := int(outcome.get("cattle_gained", 0))
	var herd_after := cattle.get_herd_size()
	print("SMOKE herd_after=", herd_after, " gained=", gained)
	if gained <= 0 or herd_after <= herd_before:
		push_error("SMOKE_FAIL herd did not grow")
		quit(1)
		return
	if String(director.call("get_phase_name")) != "success":
		push_error("SMOKE_FAIL phase not success")
		quit(1)
		return

	print("CATTLE_RAID_SMOKE_OK gained=", gained, " herd=", herd_after)
	quit(0)
