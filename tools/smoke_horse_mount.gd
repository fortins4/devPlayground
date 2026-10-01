extends SceneTree
## Headless-ish smoke: load main, mount, ride, dismount.


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	assert(packed != null)
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for _i in 15:
		await physics_frame

	var player := root.get_tree().get_first_node_in_group("player") as CharacterBody3D
	var horse := root.get_tree().get_first_node_in_group("horse") as CharacterBody3D
	assert(player != null and horse != null, "missing player/horse")
	print("SMOKE positions player=", player.global_position, " horse=", horse.global_position)

	# Walk player into mount zone
	player.global_position = horse.global_position + Vector3(1.2, 0.1, 0.8)
	for _i in 10:
		await physics_frame

	assert(horse.has_method("mount"))
	horse.call("mount", player)
	await process_frame
	await process_frame
	assert(bool(player.call("is_mounted_on_horse")), "expected mounted")
	assert(bool(horse.call("is_mounted")), "horse should report mounted")
	print("SMOKE mounted ok")

	# Simulate ride forward
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var start := horse.global_position
	for _i in 40:
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var dist := start.distance_to(horse.global_position)
	print("SMOKE rode distance=", dist)
	assert(dist > 2.0, "expected horse to move while galloping")

	horse.call("dismount")
	await process_frame
	await process_frame
	assert(not bool(player.call("is_mounted_on_horse")), "expected dismounted")
	assert(not bool(horse.call("is_mounted")), "horse should be free")
	print("SMOKE dismount ok player=", player.global_position)
	print("HORSE_SMOKE_OK")
	quit(0)
