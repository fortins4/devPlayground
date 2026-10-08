extends CanvasLayer
## Cattle-raid phase / outcome banner for the greybox loop.
## Also surfaces mid-drove RAID ALARM / heat pressure from HeatTracker.

var _heat: Node = null
var _alert_label: Label = null


func _ready() -> void:
	layer = 12
	_ensure_alert_label()
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_refresh)
	add_child(timer)
	timer.start()
	_refresh()
	call_deferred("_bind_director")
	call_deferred("_bind_heat")


func _bind_director() -> void:
	var director := _find_director()
	if director == null:
		return
	if director.has_signal("hud_refresh") and not director.hud_refresh.is_connected(_on_hud):
		director.hud_refresh.connect(_on_hud)
	if director.has_signal("raid_outcome") and not director.raid_outcome.is_connected(_on_outcome):
		director.raid_outcome.connect(_on_outcome)


func _bind_heat() -> void:
	_heat = get_tree().get_first_node_in_group("heat_tracker")
	if _heat and _heat.has_signal("raid_alarm"):
		if not _heat.raid_alarm.is_connected(_on_raid_alarm):
			_heat.raid_alarm.connect(_on_raid_alarm)
	if _heat and _heat.has_signal("raid_spotted"):
		if not _heat.raid_spotted.is_connected(_on_raid_spotted):
			_heat.raid_spotted.connect(_on_raid_spotted)
	if _heat and _heat.has_signal("heat_changed"):
		if not _heat.heat_changed.is_connected(_on_heat_changed):
			_heat.heat_changed.connect(_on_heat_changed)


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
		var reason := String(outcome.get("fail_reason", outcome.get("reason", "failed")))
		if reason == "watchmen_alarm":
			banner.text = "RAID BLOWN — watchmen heat too high"
		else:
			banner.text = "CATTLE RAID FAILED  ·  %s" % reason
		banner.modulate = Color(0.95, 0.55, 0.45)
	banner.visible = true
	var t := get_tree().create_timer(6.0)
	t.timeout.connect(func() -> void:
		if is_instance_valid(banner):
			banner.visible = false
	)


func _on_raid_alarm(heat_after: float) -> void:
	_flash_alert("RAID ALARM — spotted mid-drove  ·  heat %d" % int(heat_after), Color(0.98, 0.32, 0.22))


func _on_raid_spotted(_sentry: Node3D, heat_after: float) -> void:
	if _heat and _heat.has_method("is_raid_alarm_raised") and bool(_heat.call("is_raid_alarm_raised")):
		_set_alert("RAID ALARM  ·  heat %d / 100" % int(heat_after), Color(0.98, 0.35, 0.25))
	else:
		_set_alert("Watchmen stirring  ·  heat %d" % int(heat_after), Color(0.95, 0.82, 0.3))


func _on_heat_changed(heat: float, reason: StringName) -> void:
	var r := String(reason)
	if r.begins_with("raid_") or r == "raid_suspicious" or r == "raid_alert" or r == "raid_seen_again":
		_refresh_alert_from_heat(heat)


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
	if _heat:
		_refresh_alert_from_heat(float(_heat.get("heat")))


func _refresh_alert_from_heat(heat: float) -> void:
	if _alert_label == null:
		return
	var director := _find_director()
	var driving := false
	if director:
		var pname := String(director.call("get_phase_name")) if director.has_method("get_phase_name") else ""
		driving = pname == "driving" or pname == "raiding"
	if not driving:
		_alert_label.visible = false
		return
	var alarm := false
	if _heat and _heat.has_method("is_raid_alarm_raised"):
		alarm = bool(_heat.call("is_raid_alarm_raised"))
	if alarm:
		_set_alert("RAID ALARM  ·  heat %d / 100  ·  stay low or abort" % int(heat), Color(0.98, 0.32, 0.22))
	elif heat >= 50.0:
		_set_alert("Raid heat pressure  ·  %d / 100" % int(heat), Color(0.95, 0.75, 0.3))
	elif heat > 0.0:
		_set_alert("Raid heat %d / 100" % int(heat), Color(0.9, 0.88, 0.6))
	else:
		_alert_label.visible = false


func _flash_alert(text: String, color: Color) -> void:
	_set_alert(text, color)


func _set_alert(text: String, color: Color) -> void:
	if _alert_label == null:
		_ensure_alert_label()
	if _alert_label == null:
		return
	_alert_label.text = text
	_alert_label.add_theme_color_override("font_color", color)
	_alert_label.visible = true


func _ensure_alert_label() -> void:
	var root := get_node_or_null("Root") as Control
	if root == null:
		return
	_alert_label = root.get_node_or_null("RaidAlertLabel") as Label
	if _alert_label:
		return
	_alert_label = Label.new()
	_alert_label.name = "RaidAlertLabel"
	_alert_label.visible = false
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Same legibility treatment as the raid hint: 24 px, thin 3 px outline + drop shadow so digits
	# keep their open shapes (a thick outline filled "(3)" in until it read as "(5)").
	_alert_label.add_theme_font_size_override("font_size", 24)
	_alert_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04, 0.9))
	_alert_label.add_theme_constant_override("outline_size", 3)
	_alert_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_alert_label.add_theme_constant_override("shadow_offset_x", 2)
	_alert_label.add_theme_constant_override("shadow_offset_y", 2)
	_alert_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_alert_label.offset_left = 16.0
	_alert_label.offset_top = 88.0
	_alert_label.offset_right = -16.0
	_alert_label.offset_bottom = 122.0
	root.add_child(_alert_label)


func _find_director() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("cattle_raid")
