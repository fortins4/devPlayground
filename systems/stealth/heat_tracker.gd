extends Node
## FULL patrol heat: delayed investigation, rediscovery bumps, optional Honor stub.
## Polish: clearer investigate telegraph, live countdown UI, sentry walk-to-body hooks.
## Hidden corpses skip discovery; unhidden bodies raise heat (once after delay, then repeats).

signal heat_changed(heat: float, reason: StringName)
signal body_discovered(corpse: Node3D, sentry: Node3D)
signal investigation_started(corpse: Node3D, sentry: Node3D)
signal investigation_progress(corpse: Node3D, remaining: float, total: float)
signal honor_stub_applied(delta: float, reason: StringName)
signal raid_spotted(sentry: Node3D, heat_after: float)
signal raid_alarm(heat_after: float)

@export var max_heat: float = 100.0
@export var discover_bump: float = 28.0
@export var rediscovery_bump: float = 12.0
@export var hidden_relief: float = 10.0
@export var scan_interval: float = 0.35
## Tuned 1.6 → 2.0 so walk-to-body + [? INVESTIGATING] telegraph reads before bump.
@export var investigation_delay: float = 2.0
@export var rediscovery_interval: float = 4.0
@export var discovery_view_distance: float = 12.0
@export var discovery_half_angle_deg: float = 48.0
@export var honor_on_discover: float = -4.0
@export var honor_on_hide: float = 1.5
@export var honor_coupling_enabled: bool = true
@export var raid_suspicious_bump: float = 8.0
@export var raid_alert_bump: float = 22.0
@export var raid_rediscovery_bump: float = 10.0
@export var raid_rediscovery_interval: float = 3.5

@export var pre_raid_suspicious_bump: float = 3.0
@export var pre_raid_alert_bump: float = 6.0

var heat: float = 0.0
var _scan_cd: float = 0.0
var _discovered: Dictionary = {}  # instance_id -> true (first formal discovery)
var _investigating: Dictionary = {}  # instance_id -> remaining seconds
var _investigate_sentry: Dictionary = {}  # instance_id -> sentry
var _investigate_total: Dictionary = {}  # instance_id -> starting delay
var _rediscover_cd: Dictionary = {}  # instance_id -> cooldown remaining
var _hud_label: Label
var _banner: Label
var _progress_label: Label
var _progress_bar: ProgressBar
var _world_label: Label3D
var _banner_tween: Tween
var _raid_spot_cd: Dictionary = {}  # sentry instance_id -> cooldown remaining
var _raid_alarm_raised: bool = false
var _hud_tick: float = 0.0


func _ready() -> void:
	add_to_group("heat_tracker")
	_ensure_hud()
	_ensure_world_label()
	_refresh_hud("boot")


func _physics_process(delta: float) -> void:
	_tick_investigations(delta)
	_tick_rediscovery_cds(delta)
	_tick_raid_spot_cds(delta)
	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.12
		if not _investigating.is_empty():
			_refresh_hud("investigating")
			_refresh_progress_ui()
	_scan_cd -= delta
	if _scan_cd > 0.0:
		return
	_scan_cd = scan_interval
	_scan_discoveries()


func get_heat() -> float:
	return heat


func get_active_investigation_count() -> int:
	return _investigating.size()


func get_primary_investigation_remaining() -> float:
	if _investigating.is_empty():
		return 0.0
	var best := 9999.0
	for id in _investigating.keys():
		best = minf(best, float(_investigating[id]))
	return best if best < 9990.0 else 0.0


func bump(amount: float, reason: StringName = &"bump") -> void:
	var prev := heat
	heat = clampf(heat + amount, 0.0, max_heat)
	if not is_equal_approx(prev, heat):
		heat_changed.emit(heat, reason)
		_refresh_hud(String(reason))


func note_body_hidden(corpse: Node3D) -> void:
	bump(-hidden_relief, &"bog_hide")
	if corpse:
		var id := corpse.get_instance_id()
		_cancel_investigation(id, true)
		_rediscover_cd.erase(id)
		if corpse.has_method("set_investigation"):
			corpse.call("set_investigation", false, 0.0)
	_flash_banner("Body CONCEALED — heat eased", Color(0.45, 0.8, 0.5))
	_apply_honor(honor_on_hide, &"bog_hide")
	_hide_progress_ui()


func was_discovered(corpse: Node3D) -> bool:
	if corpse == null:
		return false
	return _discovered.has(corpse.get_instance_id())


func force_heat(value: float, reason: StringName = &"force") -> void:
	heat = clampf(value, 0.0, max_heat)
	heat_changed.emit(heat, reason)
	_refresh_hud(String(reason))


func _tick_investigations(delta: float) -> void:
	var done: Array = []
	for id in _investigating.keys():
		_investigating[id] = float(_investigating[id]) - delta
		var remaining := float(_investigating[id])
		var corpse := instance_from_id(id) as Node3D
		var sentry: Node3D = _investigate_sentry.get(id) as Node3D
		var total := float(_investigate_total.get(id, investigation_delay))
		if corpse and is_instance_valid(corpse) and corpse.has_method("set_investigation"):
			corpse.call("set_investigation", true, maxf(0.0, remaining))
		if sentry and is_instance_valid(sentry) and sentry.has_method("update_body_investigate"):
			sentry.call("update_body_investigate", maxf(0.0, remaining))
		investigation_progress.emit(corpse, maxf(0.0, remaining), total)
		if remaining <= 0.0:
			done.append(id)
	for id in done:
		var corpse := instance_from_id(id) as Node3D
		var sentry: Node3D = _investigate_sentry.get(id) as Node3D
		_investigating.erase(id)
		_investigate_sentry.erase(id)
		_investigate_total.erase(id)
		if corpse == null or not is_instance_valid(corpse):
			continue
		if corpse.has_method("is_hidden") and bool(corpse.call("is_hidden")):
			if corpse.has_method("set_investigation"):
				corpse.call("set_investigation", false, 0.0)
			continue
		_confirm_discovery(corpse, sentry)
	if _investigating.is_empty():
		_hide_progress_ui()


func _tick_rediscovery_cds(delta: float) -> void:
	var keys := _rediscover_cd.keys()
	for id in keys:
		_rediscover_cd[id] = maxf(0.0, float(_rediscover_cd[id]) - delta)


func _scan_discoveries() -> void:
	var corpses := get_tree().get_nodes_in_group("corpse")
	var sentries := get_tree().get_nodes_in_group("sentry")
	for corpse in corpses:
		if corpse == null or not is_instance_valid(corpse):
			continue
		if corpse.has_method("is_hidden") and bool(corpse.call("is_hidden")):
			continue
		var id := corpse.get_instance_id()
		var seeing_sentry: Node3D = null
		for sentry in sentries:
			if sentry == null or not is_instance_valid(sentry):
				continue
			if _sentry_sees_corpse(sentry as Node3D, corpse as Node3D):
				seeing_sentry = sentry as Node3D
				break
		if seeing_sentry == null:
			# Lost LOS during investigation — cancel pending.
			if _investigating.has(id) and not _discovered.has(id):
				_cancel_investigation(id, true)
				if corpse.has_method("set_investigation"):
					corpse.call("set_investigation", false, 0.0)
				_flash_banner("Investigation broken — LOS lost", Color(0.7, 0.75, 0.55))
				_refresh_hud("investigate_cancel")
			continue
		if not _discovered.has(id):
			if not _investigating.has(id):
				_investigating[id] = investigation_delay
				_investigate_sentry[id] = seeing_sentry
				_investigate_total[id] = investigation_delay
				investigation_started.emit(corpse, seeing_sentry)
				_nudge_sentry_suspicious(seeing_sentry)
				if seeing_sentry.has_method("begin_body_investigate"):
					seeing_sentry.call("begin_body_investigate", corpse, investigation_delay)
				if corpse.has_method("set_investigation"):
					corpse.call("set_investigation", true, investigation_delay)
				_flash_banner("Sentry investigating body… %.1fs" % investigation_delay, Color(0.95, 0.8, 0.35))
				_refresh_hud("investigating")
				_refresh_progress_ui()
			continue
		# Already discovered: repeatable bumps while still visible.
		if float(_rediscover_cd.get(id, 0.0)) <= 0.0:
			_rediscover_cd[id] = rediscovery_interval
			bump(rediscovery_bump, &"body_seen_again")
			_nudge_sentry_alert(seeing_sentry)
			if corpse.has_method("mark_discovered"):
				corpse.call("mark_discovered")
			_flash_banner("Body seen again — heat +%d" % int(rediscovery_bump), Color(0.95, 0.4, 0.25))
			_apply_honor(honor_on_discover * 0.5, &"body_seen_again")


func _cancel_investigation(id: int, return_sentry: bool) -> void:
	var sentry: Node3D = _investigate_sentry.get(id) as Node3D
	_investigating.erase(id)
	_investigate_sentry.erase(id)
	_investigate_total.erase(id)
	if return_sentry and sentry and is_instance_valid(sentry) and sentry.has_method("cancel_body_investigate"):
		sentry.call("cancel_body_investigate")
	if _investigating.is_empty():
		_hide_progress_ui()


func _confirm_discovery(corpse: Node3D, sentry: Node3D) -> void:
	var id := corpse.get_instance_id()
	_discovered[id] = true
	_rediscover_cd[id] = rediscovery_interval
	if corpse.has_method("set_investigation"):
		corpse.call("set_investigation", false, 0.0)
	bump(discover_bump, &"body_seen")
	body_discovered.emit(corpse, sentry)
	if sentry:
		_nudge_sentry_alert(sentry)
		if sentry.has_method("confirm_body_discovered"):
			sentry.call("confirm_body_discovered")
	if corpse.has_method("mark_discovered"):
		corpse.call("mark_discovered")
	_flash_banner("BODY DISCOVERED — heat +%d" % int(discover_bump), Color(0.98, 0.3, 0.2))
	_apply_honor(honor_on_discover, &"body_seen")
	_hide_progress_ui()



func note_raid_suspicious(sentry: Node3D) -> void:
	## Watchman stirs during an active drove — small heat bump (cooldown per sentry).
	if sentry == null:
		return
	var id := sentry.get_instance_id()
	if float(_raid_spot_cd.get(id, 0.0)) > 0.0:
		return
	_raid_spot_cd[id] = raid_rediscovery_interval * 0.6
	bump(raid_suspicious_bump, &"raid_suspicious")
	_nudge_sentry_suspicious(sentry)
	_flash_banner("Watchman suspicious — raid heat +%d" % int(raid_suspicious_bump), Color(0.95, 0.82, 0.3))
	raid_spotted.emit(sentry, heat)


func note_raid_alert(sentry: Node3D) -> void:
	## Watchman ALERT mid-drove — alarm bump (or rediscovery while still seen).
	if sentry == null:
		return
	var id := sentry.get_instance_id()
	if float(_raid_spot_cd.get(id, 0.0)) > 0.0:
		return
	var first_alarm := not _raid_alarm_raised
	var amount := raid_alert_bump if first_alarm else raid_rediscovery_bump
	var reason: StringName = &"raid_alert" if first_alarm else &"raid_seen_again"
	_raid_spot_cd[id] = raid_rediscovery_interval
	bump(amount, reason)
	_nudge_sentry_alert(sentry)
	_raid_alarm_raised = true
	if first_alarm:
		_flash_banner("RAID ALARM — spotted mid-drove! heat +%d" % int(amount), Color(0.98, 0.28, 0.2))
		raid_alarm.emit(heat)
	else:
		_flash_banner("Watchmen still on you — heat +%d" % int(amount), Color(0.95, 0.4, 0.25))
	raid_spotted.emit(sentry, heat)


func reset_raid_spot_state() -> void:
	## Clears drove-spot cooldowns / alarm flag. Shared heat value is kept.
	_raid_spot_cd.clear()
	_raid_alarm_raised = false
	if _banner:
		_banner.visible = false
		_banner.modulate.a = 1.0
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_refresh_hud("raid_reset")




func note_pre_raid_suspicious(sentry: Node3D) -> void:
	## Q2=2b: light heat seed near pens before the drove starts.
	if sentry == null:
		return
	var id := sentry.get_instance_id()
	if float(_raid_spot_cd.get(id, 0.0)) > 0.0:
		return
	_raid_spot_cd[id] = raid_rediscovery_interval * 0.8
	bump(pre_raid_suspicious_bump, &"pre_raid_suspicious")
	_nudge_sentry_suspicious(sentry)
	_flash_banner("Watchman stirs at pens — heat +%d" % int(pre_raid_suspicious_bump), Color(0.9, 0.85, 0.45))


func note_pre_raid_alert(sentry: Node3D) -> void:
	## Q2=2b: ALERT near pens seeds a little heat (not full mid-drove alarm).
	if sentry == null:
		return
	var id := sentry.get_instance_id()
	if float(_raid_spot_cd.get(id, 0.0)) > 0.0:
		return
	_raid_spot_cd[id] = raid_rediscovery_interval
	bump(pre_raid_alert_bump, &"pre_raid_alert")
	_nudge_sentry_alert(sentry)
	_flash_banner("Spotted near pens — heat +%d" % int(pre_raid_alert_bump), Color(0.95, 0.55, 0.3))


func raise_raid_alarm(reason: StringName = &"raid_alarm") -> void:
	## Force RAID ALARM banner/flag without requiring a fresh LOS bump (e.g. heat≥85 attack).
	if _raid_alarm_raised:
		return
	_raid_alarm_raised = true
	_flash_banner("RAID ALARM — watchmen ATTACK! (%s)" % String(reason), Color(0.98, 0.25, 0.18))
	raid_alarm.emit(heat)
	_refresh_hud(String(reason))

func is_raid_alarm_raised() -> bool:
	return _raid_alarm_raised


func _tick_raid_spot_cds(delta: float) -> void:
	var keys := _raid_spot_cd.keys()
	for id in keys:
		_raid_spot_cd[id] = maxf(0.0, float(_raid_spot_cd[id]) - delta)


func _apply_honor(delta: float, reason: StringName) -> void:
	if not honor_coupling_enabled or is_zero_approx(delta):
		return
	var honor := get_node_or_null("/root/Honor")
	if honor == null and Engine.has_singleton("Honor"):
		pass
	# Autoload named Honor
	if honor == null:
		honor = get_tree().root.get_node_or_null("Honor")
	if honor and honor.has_method("modify_honor"):
		honor.call("modify_honor", delta)
		honor_stub_applied.emit(delta, reason)
		_refresh_hud("%s honor%+.1f" % [String(reason), delta])


func _sentry_sees_corpse(sentry: Node3D, corpse: Node3D) -> bool:
	var sensor := sentry.get_node_or_null("DetectionSensor") as Node3D
	var eye := sentry.global_position + Vector3(0.0, 1.55, 0.0)
	var aim := corpse.global_position + Vector3(0.0, 0.35, 0.0)
	if corpse.has_method("get_visibility_point"):
		aim = corpse.call("get_visibility_point") as Vector3
	var to_target := aim - eye
	var dist := to_target.length()
	var view_dist := discovery_view_distance
	var half_ang := discovery_half_angle_deg
	if sensor:
		if "view_distance" in sensor:
			view_dist = float(sensor.get("view_distance"))
		if "view_half_angle_deg" in sensor:
			half_ang = float(sensor.get("view_half_angle_deg"))
		if "eye_height" in sensor:
			eye = sentry.global_position + Vector3(0.0, float(sensor.get("eye_height")), 0.0)
	if dist > view_dist or dist < 0.05:
		return false
	var forward := -sentry.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var flat := to_target
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return false
	flat = flat.normalized()
	var ang := rad_to_deg(acos(clampf(forward.dot(flat), -1.0, 1.0)))
	if ang > half_ang:
		return false
	return _has_los(eye, aim, sentry, corpse)


func _has_los(from: Vector3, to: Vector3, sentry: Node3D, corpse: Node3D) -> bool:
	var space := sentry.get_world_3d().direct_space_state if sentry.is_inside_tree() else null
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	if sentry is CollisionObject3D:
		exclude.append((sentry as CollisionObject3D).get_rid())
	if corpse is CollisionObject3D:
		exclude.append((corpse as CollisionObject3D).get_rid())
	var player := get_tree().get_first_node_in_group("player")
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _nudge_sentry_alert(sentry: Node) -> void:
	var sensor := sentry.get_node_or_null("DetectionSensor")
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 2, 1.0)


func _nudge_sentry_suspicious(sentry: Node) -> void:
	var sensor := sentry.get_node_or_null("DetectionSensor")
	if sensor and sensor.has_method("force_awareness"):
		sensor.call("force_awareness", 1, 0.55)


func _ensure_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HeatHUDLayer"
	layer.layer = 20
	add_child(layer)
	_hud_label = Label.new()
	_hud_label.name = "HeatLabel"
	_hud_label.position = Vector2(16, 14)
	_hud_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_hud_label)
	_progress_label = Label.new()
	_progress_label.name = "InvestigateProgressLabel"
	_progress_label.position = Vector2(16, 52)
	_progress_label.add_theme_font_size_override("font_size", 18)
	_progress_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	_progress_label.visible = false
	layer.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.name = "InvestigateProgressBar"
	_progress_bar.position = Vector2(16, 76)
	_progress_bar.custom_minimum_size = Vector2(260, 16)
	_progress_bar.size = Vector2(260, 16)
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.visible = false
	layer.add_child(_progress_bar)
	_banner = Label.new()
	_banner.name = "HeatBanner"
	_banner.position = Vector2(16, 102)
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.visible = false
	layer.add_child(_banner)


func _ensure_world_label() -> void:
	_world_label = get_node_or_null("HeatWorldLabel") as Label3D
	if _world_label:
		return
	var host := get_parent()
	if host == null:
		return
	_world_label = Label3D.new()
	_world_label.name = "HeatWorldLabel"
	_world_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_world_label.font_size = 40
	_world_label.modulate = Color(0.95, 0.85, 0.55)
	host.add_child(_world_label)
	_world_label.global_position = Vector3(18.0, 3.2, 1.0)


func _flash_banner(text: String, color: Color) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.visible = true
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate = Color(1, 1, 1, 1)
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(func():
		_banner.visible = false
		_banner.modulate.a = 1.0
	)


func _refresh_progress_ui() -> void:
	if _progress_bar == null or _progress_label == null:
		return
	if _investigating.is_empty():
		_hide_progress_ui()
		return
	var remaining := get_primary_investigation_remaining()
	var total := investigation_delay
	for id in _investigate_total.keys():
		total = float(_investigate_total[id])
		break
	var frac := 0.0
	if total > 0.001:
		frac = 1.0 - clampf(remaining / total, 0.0, 1.0)
	_progress_label.visible = true
	_progress_bar.visible = true
	_progress_label.text = "INVESTIGATING body — %.1f / %.1fs" % [remaining, total]
	_progress_bar.max_value = 1.0
	_progress_bar.value = frac


func _hide_progress_ui() -> void:
	if _progress_label:
		_progress_label.visible = false
	if _progress_bar:
		_progress_bar.visible = false


func _refresh_hud(reason: String) -> void:
	var tier := "calm"
	var color := Color(0.65, 0.85, 0.6)
	if heat >= 70.0:
		tier = "HOT"
		color = Color(0.95, 0.3, 0.22)
	elif heat >= 35.0:
		tier = "warm"
		color = Color(0.95, 0.78, 0.28)
	elif heat > 0.0:
		tier = "stirred"
		color = Color(0.85, 0.85, 0.55)
	var inv_n := _investigating.size()
	var text := "Heat %d / %d  [%s]" % [int(heat), int(max_heat), tier]
	if inv_n > 0:
		var rem := get_primary_investigation_remaining()
		text += "  · investigating %.1fs" % rem
	if _raid_alarm_raised:
		text += "  · RAID ALARM"
	if reason != "" and reason != "boot" and reason != "investigating":
		text += "\n(%s)" % reason
	if _hud_label:
		_hud_label.text = text
		_hud_label.add_theme_color_override("font_color", color)
	if _world_label and is_instance_valid(_world_label):
		_world_label.text = text
		_world_label.modulate = color
