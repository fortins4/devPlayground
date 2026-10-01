extends Node
## Bridges cattle-lane watchmen (DetectionSensor) → HeatTracker during an active drove.
## Extends stealth heat rather than forking a second meter. Non-raid phases: sensors still
## paint UNAWARE/SUSPICIOUS/ALERT for feel, but do not bump raid heat.

signal watchman_stirred(sentry: Node3D, awareness: int)
signal raid_heat_pressure(heat: float)

@export var fail_on_hot_heat: bool = true
@export var fail_heat_threshold: float = 85.0
@export var pressure_warn_threshold: float = 50.0

var _director: Node = null
var _heat: Node = null
var _wired: Dictionary = {}  # instance_id -> true
var _failed_from_heat: bool = false


func _ready() -> void:
	add_to_group("raid_heat_bridge")
	_director = get_parent()
	call_deferred("_bind_all")


func _process(_delta: float) -> void:
	if not _raid_active():
		return
	_ensure_heat()
	if _heat == null:
		return
	var h := float(_heat.get("heat"))
	if h >= pressure_warn_threshold:
		raid_heat_pressure.emit(h)
	if fail_on_hot_heat and not _failed_from_heat and h >= fail_heat_threshold:
		_failed_from_heat = true
		_request_fail_from_heat()


func reset_for_new_raid() -> void:
	_failed_from_heat = false
	_ensure_heat()
	if _heat and _heat.has_method("reset_raid_spot_state"):
		_heat.call("reset_raid_spot_state")


func get_heat() -> float:
	_ensure_heat()
	if _heat:
		return float(_heat.get("heat"))
	return 0.0


func is_alarm_raised() -> bool:
	_ensure_heat()
	if _heat and _heat.has_method("is_raid_alarm_raised"):
		return bool(_heat.call("is_raid_alarm_raised"))
	return false


func debug_force_spot(sentry: Node3D = null) -> void:
	## Smoke / screenshot helper: treat as ALERT mid-drove.
	_ensure_heat()
	if _heat == null:
		return
	var target := sentry
	if target == null:
		var nodes := get_tree().get_nodes_in_group("raid_watchman")
		if nodes.size() > 0:
			target = nodes[0] as Node3D
	if target and _heat.has_method("note_raid_alert"):
		_heat.call("note_raid_alert", target)
		# Also force visual ALERT on the sensor.
		var sensor := target.get_node_or_null("DetectionSensor")
		if sensor and sensor.has_method("force_awareness"):
			sensor.call("force_awareness", 2, 1.0)


func _bind_all() -> void:
	_ensure_heat()
	_wire_watchmen()
	if _director and _director.has_signal("phase_changed"):
		if not _director.phase_changed.is_connected(_on_phase_changed):
			_director.phase_changed.connect(_on_phase_changed)


func _wire_watchmen() -> void:
	var root := get_parent()
	if root == null:
		return
	var watch_root := root.get_node_or_null("Watchmen")
	var candidates: Array = []
	if watch_root:
		for child in watch_root.get_children():
			candidates.append(child)
	for node in get_tree().get_nodes_in_group("raid_watchman"):
		if node not in candidates:
			candidates.append(node)
	for sentry in candidates:
		_wire_one(sentry as Node)


func _wire_one(sentry: Node) -> void:
	if sentry == null or not is_instance_valid(sentry):
		return
	var id := sentry.get_instance_id()
	if _wired.has(id):
		return
	if not sentry.is_in_group("raid_watchman"):
		sentry.add_to_group("raid_watchman")
	if not sentry.is_in_group("sentry"):
		sentry.add_to_group("sentry")
	var sensor := sentry.get_node_or_null("DetectionSensor")
	if sensor == null:
		return
	if sensor.has_signal("awareness_changed"):
		var cb := _on_awareness.bind(sentry)
		if not sensor.awareness_changed.is_connected(cb):
			sensor.awareness_changed.connect(cb)
	_wired[id] = true


func _on_phase_changed(phase: int, _label: String) -> void:
	# IDLE=0 APPROACH=1 RAIDING=2 DRIVING=3 SUCCESS=4 FAILED=5
	if phase == 2 or phase == 3:
		_failed_from_heat = false
		# Fresh drove: clear spot cooldowns so first LOS can alarm again.
		_ensure_heat()
		if _heat and _heat.has_method("reset_raid_spot_state"):
			_heat.call("reset_raid_spot_state")
	elif phase == 0 or phase == 1:
		_failed_from_heat = false


func _on_awareness(prev: int, next: int, sentry: Node) -> void:
	if not _raid_active():
		return
	_ensure_heat()
	if _heat == null:
		return
	watchman_stirred.emit(sentry as Node3D, next)
	# DetectionSensor.Awareness: UNAWARE=0 SUSPICIOUS=1 ALERT=2
	if next == 1 and prev < 1 and _heat.has_method("note_raid_suspicious"):
		_heat.call("note_raid_suspicious", sentry)
	elif next == 2 and _heat.has_method("note_raid_alert"):
		_heat.call("note_raid_alert", sentry)


func _raid_active() -> bool:
	if _director == null:
		_director = get_parent()
	if _director == null:
		return false
	var p = _director.get("phase")
	if p == null:
		return false
	var pi := int(p)
	return pi == 2 or pi == 3  # RAIDING / DRIVING


func _ensure_heat() -> void:
	if _heat and is_instance_valid(_heat):
		return
	var tree := get_tree()
	if tree == null:
		return
	_heat = tree.get_first_node_in_group("heat_tracker")


func _request_fail_from_heat() -> void:
	if _director == null:
		return
	if _director.has_method("fail_from_watchmen_heat"):
		_director.call("fail_from_watchmen_heat")
