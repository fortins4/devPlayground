extends SceneTree
## Smoke: mount → seated joints → trot/gallop pose states → dismount rest.


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

	var loco = player.get_node_or_null("KerneLocomotion")
	assert(loco != null, "missing KerneLocomotion")

	player.global_position = horse.global_position + Vector3(1.2, 0.1, 0.8)
	for _i in 10:
		await physics_frame

	horse.call("mount", player)
	await process_frame
	await process_frame
	for _i in 8:
		await physics_frame

	assert(bool(player.call("is_mounted_on_horse")), "expected mounted")
	assert(bool(horse.call("is_mounted")), "horse should report mounted")

	var state: StringName = loco.call("current_state")
	print("SMOKE mounted state=", state)
	assert(str(state).begins_with("mounted"), "expected mounted_* state, got %s" % str(state))

	# Legs should be astride (thigh pitch well above rest)
	var lt: Node3D = loco.call("get_joint", "left_thigh")
	var rt: Node3D = loco.call("get_joint", "right_thigh")
	assert(lt != null and rt != null)
	print("SMOKE thigh pitch L=", lt.rotation.x, " R=", rt.rotation.x, " open Lz=", lt.rotation.z, " Rz=", rt.rotation.z)
	assert(lt.rotation.x > deg_to_rad(40.0), "left thigh should be pitched for seated")
	assert(rt.rotation.x > deg_to_rad(40.0), "right thigh should be pitched for seated")
	assert(lt.rotation.z < -deg_to_rad(10.0), "left thigh should open outward")
	assert(rt.rotation.z > deg_to_rad(10.0), "right thigh should open outward")

	# Trot
	Input.action_press("move_forward")
	for _i in 25:
		await physics_frame
	state = loco.call("current_state")
	print("SMOKE trot state=", state)
	assert(state == &"mounted_trot" or state == &"mounted_gallop", "expected trot/gallop while moving")

	# Gallop
	Input.action_press("sprint")
	for _i in 30:
		await physics_frame
	var start := horse.global_position
	for _i in 20:
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	state = loco.call("current_state")
	print("SMOKE gallop state=", state, " dist=", start.distance_to(horse.global_position))
	assert(state == &"mounted_gallop" or start.distance_to(horse.global_position) > 1.5)

	# Let settle toward idle mounted
	for _i in 40:
		await physics_frame
	state = loco.call("current_state")
	print("SMOKE after stop state=", state)

	horse.call("dismount")
	await process_frame
	await process_frame
	for _i in 10:
		await physics_frame

	assert(not bool(player.call("is_mounted_on_horse")), "expected dismounted")
	state = loco.call("current_state")
	print("SMOKE dismount state=", state)
	assert(state == &"idle" or state == &"walk" or state == &"turn", "expected foot loco state after dismount")

	# Thighs should no longer be locked astride
	assert(absf(lt.rotation.x) < deg_to_rad(25.0), "left thigh should leave seated pitch")
	print("SEATED_RIDER_SMOKE_OK")
	quit(0)
