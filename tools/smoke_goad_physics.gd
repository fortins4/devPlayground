extends SceneTree
## Smoke: goad impulse marks drove, path bias context set, force deliver still resolves.


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
		push_error("SMOKE_FAIL no CattleRaidLane")
		quit(1)
		return

	var ringfort := get_first_node_in_group("ringfort")
	if ringfort == null:
		push_error("SMOKE_FAIL no ringfort")
		quit(1)
		return
	var cattle = ringfort.get_node("CattleEconomy")
	if cattle == null:
		push_error("SMOKE_FAIL no CattleEconomy")
		quit(1)
		return
	var herd_before: int = int(cattle.call("get_herd_size"))

	var player := get_first_node_in_group("player") as Node3D
	if player == null:
		push_error("SMOKE_FAIL no player")
		quit(1)
		return
	var combat := player.get_node_or_null("CombatSystem")
	if combat and combat.has_method("set_weapon"):
		combat.call("set_weapon", 2)  # CombatSystem.Weapon.GOAD

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

	# After begin_herd, cows should NOT all be auto-driven.
	var driven_after_begin := int(director.call("get_driven_count"))
	print("SMOKE driven_after_begin=", driven_after_begin)
	if driven_after_begin > 0:
		push_error("SMOKE_FAIL expected 0 driven after begin_herd (got %d) — pure follow leaked" % driven_after_begin)
		quit(1)
		return

	var herd := director.get_node_or_null("Herd") as Node3D
	if herd == null:
		push_error("SMOKE_FAIL no Herd")
		quit(1)
		return

	var goaded := 0
	var fwd := -player.global_transform.basis.z
	for cow in herd.get_children():
		if cow == null or not cow.has_method("apply_goad"):
			continue
		if goaded >= 3:
			break
		cow.call("apply_goad", player.global_position, fwd, 1.2, &"light")
		goaded += 1
	await process_frame
	await process_frame
	for _i in 12:
		await physics_frame

	var driven_after_goad := int(director.call("get_driven_count"))
	print("SMOKE goaded=", goaded, " driven_after_goad=", driven_after_goad)
	if driven_after_goad < 3:
		push_error("SMOKE_FAIL expected ≥3 driven after goad, got %d" % driven_after_goad)
		quit(1)
		return

	# At least one driven cow should show drove/prodded feedback label.
	var labeled := 0
	for cow in herd.get_children():
		if cow == null:
			continue
		var lab := cow.get_node_or_null("Label3D") as Label3D
		if lab and (lab.text == "drove" or lab.text == "prodded!" or lab.text == "drove!"):
			labeled += 1
	print("SMOKE drove_labels=", labeled)
	if labeled < 1:
		push_error("SMOKE_FAIL expected drove/prodded labels after goad")
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
	var herd_after: int = int(cattle.call("get_herd_size"))
	if gained <= 0 or herd_after <= herd_before:
		push_error("SMOKE_FAIL herd did not grow")
		quit(1)
		return
	if String(director.call("get_phase_name")) != "success":
		push_error("SMOKE_FAIL phase not success")
		quit(1)
		return

	# Existing cattle-raid smoke path still green via force deliver.
	print("GOAD_PHYSICS_SMOKE_OK gained=", gained, " herd=", herd_after, " driven=", driven_after_goad)
	quit(0)
