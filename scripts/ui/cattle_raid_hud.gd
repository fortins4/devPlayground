extends CanvasLayer
## Cattle-raid phase / outcome banner for the greybox loop.


func _ready() -> void:
	layer = 12
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_refresh)
	add_child(timer)
	timer.start()
	_refresh()
	call_deferred("_bind_director")


func _bind_director() -> void:
	var director := _find_director()
	if director == null:
		return
	if director.has_signal("hud_refresh") and not director.hud_refresh.is_connected(_on_hud):
		director.hud_refresh.connect(_on_hud)
	if director.has_signal("raid_outcome") and not director.raid_outcome.is_connected(_on_outcome):
		director.raid_outcome.connect(_on_outcome)


func _on_hud(text: String) -> void:
	var label := $Root/RaidLabel as Label
	if label:
		label.text = text


func _on_outcome(outcome: Dictionary) -> void:
	var banner := $Root/OutcomeBanner as Label
	if banner == null:
		return
	var ok := bool(outcome.get("success", false))
	if ok:
		banner.text = "CATTLE RAID SUCCESS  ·  +%d head  ·  pens %s" % [
			int(outcome.get("cattle_gained", 0)),
			str(outcome.get("upkeep", {}).get("herd_size", "?")),
		]
		banner.modulate = Color(0.75, 0.95, 0.55)
	else:
		banner.text = "CATTLE RAID FAILED  ·  %s" % String(outcome.get("fail_reason", outcome.get("reason", "failed")))
		banner.modulate = Color(0.95, 0.55, 0.45)
	banner.visible = true
	var t := get_tree().create_timer(6.0)
	t.timeout.connect(func() -> void:
		if is_instance_valid(banner):
			banner.visible = false
	)


func _refresh() -> void:
	var label := $Root/RaidLabel as Label
	if label == null:
		return
	var director := _find_director()
	if director == null:
		label.text = "Cattle raid — (lane south of spawn)"
		return
	if director.has_method("get_hud_text"):
		label.text = String(director.call("get_hud_text"))


func _find_director() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("cattle_raid")
