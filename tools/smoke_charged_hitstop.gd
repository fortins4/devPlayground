extends SceneTree
func _initialize() -> void:
	var s := load("res://systems/combat/combat_system.gd") as Script
	var n: CombatSystem = s.new()
	root.add_child(n)
	await process_frame
	if n.hit_stop_charged <= n.hit_stop_heavy:
		push_error("SMOKE_FAIL charged hitstop should exceed heavy")
		quit(1)
		return
	if n.charged_impact_scale >= 0.1:
		push_error("SMOKE_FAIL charged impact scale should be deep freeze")
		quit(1)
		return
	print("CHARGED_HITSTOP_SMOKE_OK charged=", n.hit_stop_charged, " scale=", n.charged_impact_scale)
	quit(0)
