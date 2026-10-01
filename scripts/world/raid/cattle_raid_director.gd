extends Node3D
## Greybox cattle-raid loop: approach herd → start raid → drive cattle home → resolve.
## Wires into ringfort CattleEconomy.resolve_raid_success / resolve_raid_failure.
## Watchmen on the lane raise shared HeatTracker during DRIVING (see raid_heat_bridge.gd).
## Does not touch band muster caps; presentational drove only.

enum Phase {
	IDLE,
	APPROACH,
	RAIDING,
	DRIVING,
	SUCCESS,
	FAILED,
}

const TARGET_ID := &"local_clan_herd"
const MIN_DELIVER := 3
const RAID_TIME_LIMIT := 90.0
const ABANDON_DIST := 55.0

signal phase_changed(phase: int, label: String)
signal raid_outcome(outcome: Dictionary)
signal hud_refresh(text: String)

@export var return_zone_path: NodePath = ^"ReturnZone"
@export var start_zone_path: NodePath = ^"StartZone"
@export var herd_root_path: NodePath = ^"Herd"

var phase: Phase = Phase.IDLE
var time_left: float = RAID_TIME_LIMIT
var last_outcome: Dictionary = {}

var _player: Node3D = null
var _cattle_economy: CattleEconomy = null
var _cows: Array[Node] = []
var _start_zone: Area3D = null
var _return_zone: Area3D = null
var _player_in_start: bool = false
var _player_in_return: bool = false
var _banner_timer: float = 0.0
var _heat_bridge: Node = null

@onready var lane_label: Label3D = $LaneLabel
@onready var status_label: Label3D = $StatusLabel
@onready var prompt_label: Label3D = $PromptLabel


func _ready() -> void:
	add_to_group("cattle_raid")
	_heat_bridge = get_node_or_null("RaidHeatBridge")
	_start_zone = get_node_or_null(start_zone_path) as Area3D
	_return_zone = get_node_or_null(return_zone_path) as Area3D
	_collect_cows()
	_find_player()
	_find_economy()
	if _start_zone:
		_start_zone.body_entered.connect(_on_start_entered)
		_start_zone.body_exited.connect(_on_start_exited)
	if _return_zone:
		_return_zone.body_entered.connect(_on_return_entered)
		_return_zone.body_exited.connect(_on_return_exited)
	_set_phase(Phase.IDLE)
	_refresh_labels()
	call_deferred("_deferred_bind")


func _deferred_bind() -> void:
	_find_player()
	_find_economy()
	for cow in _cows:
		if cow and cow.has_method("set_player"):
			cow.call("set_player", _player)


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
	if phase == Phase.DRIVING or phase == Phase.RAIDING:
		time_left -= delta
		if time_left <= 0.0:
			_fail_raid(&"timeout")
			return
		if _player and is_instance_valid(_player):
			var dist := global_position.distance_to(_player.global_position)
			if dist > ABANDON_DIST and _driven_count() == 0:
				_fail_raid(&"abandoned")
				return
		if phase == Phase.DRIVING and _player_in_return and _driven_count() >= MIN_DELIVER:
			_succeed_raid()
			return
		_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if phase == Phase.APPROACH or (phase == Phase.IDLE and _player_in_start):
			_begin_raid()
			get_viewport().set_input_as_handled()
		elif phase == Phase.SUCCESS or phase == Phase.FAILED:
			if _player_in_start:
				_reset_raid()
				get_viewport().set_input_as_handled()


func get_phase_name() -> String:
	match phase:
		Phase.IDLE:
			return "idle"
		Phase.APPROACH:
			return "approach"
		Phase.RAIDING:
			return "raiding"
		Phase.DRIVING:
			return "driving"
		Phase.SUCCESS:
			return "success"
		Phase.FAILED:
			return "failed"
	return "unknown"


func get_driven_count() -> int:
	return _driven_count()


func get_hud_text() -> String:
	var driven := _driven_count()
	var delivered := _delivered_count()
	match phase:
		Phase.IDLE:
			return "Cattle raid → south  ·  approach pens · E start"
		Phase.APPROACH:
			return "E — Start cattle raid (local túath pens)"
		Phase.RAIDING, Phase.DRIVING:
			var base := "Drive cattle to home pens  ·  %d/%d head  ·  %.0fs" % [
				driven + delivered, MIN_DELIVER, maxf(0.0, time_left)
			]
			return base + _heat_hud_suffix()
		Phase.SUCCESS:
			var gained := int(last_outcome.get("cattle_gained", 0))
			return "RAID SUCCESS — +%d cattle to pens  ·  E retry at herd" % gained
		Phase.FAILED:
			var reason := String(last_outcome.get("reason", "failed"))
			return "RAID FAILED — %s  ·  E retry at herd" % reason
	return ""


## Headless / smoke helper: force-start without standing in the zone.
func debug_begin_raid() -> void:
	_player_in_start = true
	_begin_raid()


## Headless / smoke helper: teleport drove cattle into return and resolve.
func debug_force_deliver() -> Dictionary:
	if phase != Phase.DRIVING and phase != Phase.RAIDING:
		_begin_raid()
	for cow in _cows:
		if cow == null or not is_instance_valid(cow):
			continue
		if cow.get("delivered"):
			continue
		if _return_zone:
			cow.global_position = _return_zone.global_position + Vector3(
				randf_range(-1.5, 1.5), 0.1, randf_range(-1.5, 1.5)
			)
		if cow.has_method("start_driven"):
			cow.call("start_driven")
	_player_in_return = true
	_succeed_raid()
	return last_outcome


func _begin_raid() -> void:
	if phase == Phase.RAIDING or phase == Phase.DRIVING:
		return
	if phase == Phase.SUCCESS or phase == Phase.FAILED:
		_reset_raid()
	_find_economy()
	_find_player()
	time_left = RAID_TIME_LIMIT
	last_outcome = {}
	_player_in_return = false
	if _heat_bridge and _heat_bridge.has_method("reset_for_new_raid"):
		_heat_bridge.call("reset_for_new_raid")
	var started := 0
	for cow in _cows:
		if cow and cow.has_method("set_player"):
			cow.call("set_player", _player)
		if cow and cow.has_method("start_driven"):
			cow.call("start_driven")
			started += 1
	_set_phase(Phase.DRIVING if started > 0 else Phase.RAIDING)
	_flash_status("Raid on — drive the herd west to home pens!")
	_refresh_labels()


func _succeed_raid() -> void:
	if phase == Phase.SUCCESS or phase == Phase.FAILED:
		return
	var heads := maxi(_driven_count(), MIN_DELIVER)
	# Mark driven as delivered visually.
	for cow in _cows:
		if cow and bool(cow.get("driven")) and cow.has_method("mark_delivered"):
			cow.call("mark_delivered")
	_find_economy()
	var outcome: Dictionary = {}
	if _cattle_economy:
		outcome = _cattle_economy.resolve_raid_success(TARGET_ID, heads)
	else:
		outcome = {
			"ok": true,
			"success": true,
			"reason": &"ok",
			"target_id": TARGET_ID,
			"cattle_gained": heads,
			"cattle_loot": heads,
			"note": "no CattleEconomy — visual-only resolve",
		}
	last_outcome = outcome
	_set_phase(Phase.SUCCESS)
	_banner_timer = 8.0
	_flash_status(
		"Success! +%d cattle · heat on local clans"
		% int(outcome.get("cattle_gained", heads))
	)
	raid_outcome.emit(outcome)
	_refresh_labels()


func _fail_raid(reason: StringName) -> void:
	if phase == Phase.SUCCESS or phase == Phase.FAILED:
		return
	for cow in _cows:
		if cow and cow.has_method("stop_driven"):
			cow.call("stop_driven")
	_find_economy()
	var outcome: Dictionary = {}
	if _cattle_economy:
		outcome = _cattle_economy.resolve_raid_failure(TARGET_ID)
	else:
		outcome = {
			"ok": true,
			"success": false,
			"reason": reason,
			"target_id": TARGET_ID,
			"cattle_lost": 0,
		}
	outcome["fail_reason"] = reason
	last_outcome = outcome
	_set_phase(Phase.FAILED)
	_banner_timer = 8.0
	_flash_status("Raid failed (%s)." % String(reason))
	raid_outcome.emit(outcome)
	_refresh_labels()


func _reset_raid() -> void:
	var herd := get_node_or_null(herd_root_path) as Node3D
	var i := 0
	for cow in _cows:
		if cow == null or not is_instance_valid(cow):
			continue
		var pen := global_position + Vector3(-2.0 + float(i % 3) * 2.0, 0.1, 2.0 + float(i / 3) * 2.0)
		if herd:
			pen = herd.global_position + Vector3(-2.0 + float(i % 3) * 2.0, 0.1, float(i / 3) * 2.0)
		if cow.has_method("reset_to_pen"):
			cow.call("reset_to_pen", pen)
		i += 1
	time_left = RAID_TIME_LIMIT
	last_outcome = {}
	_player_in_return = false
	_set_phase(Phase.APPROACH if _player_in_start else Phase.IDLE)
	_flash_status("Herd resettled — E to raid again.")
	_refresh_labels()


func _set_phase(next: Phase) -> void:
	phase = next
	phase_changed.emit(int(phase), get_phase_name())
	hud_refresh.emit(get_hud_text())


func _driven_count() -> int:
	var n := 0
	for cow in _cows:
		if cow and bool(cow.get("driven")) and not bool(cow.get("delivered")):
			n += 1
	return n


func _delivered_count() -> int:
	var n := 0
	for cow in _cows:
		if cow and bool(cow.get("delivered")):
			n += 1
	return n


func _collect_cows() -> void:
	_cows.clear()
	var herd := get_node_or_null(herd_root_path)
	if herd == null:
		return
	for child in herd.get_children():
		if child.is_in_group("raid_cattle") or child.has_method("start_driven"):
			_cows.append(child)


func _find_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group("player") as Node3D


func _find_economy() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var ringfort := tree.get_first_node_in_group("ringfort")
	if ringfort:
		_cattle_economy = ringfort.get_node_or_null("CattleEconomy") as CattleEconomy


func _on_start_entered(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_in_start = true
	if phase == Phase.IDLE:
		_set_phase(Phase.APPROACH)
	_refresh_labels()


func _on_start_exited(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_in_start = false
	if phase == Phase.APPROACH:
		_set_phase(Phase.IDLE)
	_refresh_labels()


func _on_return_entered(body: Node3D) -> void:
	if _is_player(body):
		_player_in_return = true
		if (phase == Phase.DRIVING or phase == Phase.RAIDING) and _driven_count() >= MIN_DELIVER:
			_succeed_raid()
		_refresh_labels()
		return
	# Cattle crossing the home pens while driven also counts.
	if body.is_in_group("raid_cattle") and bool(body.get("driven")):
		if body.has_method("mark_delivered"):
			body.call("mark_delivered")
		if (phase == Phase.DRIVING or phase == Phase.RAIDING) and _delivered_count() >= MIN_DELIVER:
			_succeed_raid()


func _on_return_exited(body: Node3D) -> void:
	if _is_player(body):
		_player_in_return = false



func fail_from_watchmen_heat() -> void:
	## Called by RaidHeatBridge when shared heat crosses the fail threshold mid-drove.
	_fail_raid(&"watchmen_alarm")


func debug_force_watchman_spot() -> void:
	## Smoke / screenshot: force ALERT heat bump as if mid-drove LOS.
	if phase != Phase.DRIVING and phase != Phase.RAIDING:
		_begin_raid()
	if _heat_bridge and _heat_bridge.has_method("debug_force_spot"):
		_heat_bridge.call("debug_force_spot")


func get_raid_heat() -> float:
	if _heat_bridge and _heat_bridge.has_method("get_heat"):
		return float(_heat_bridge.call("get_heat"))
	var ht := get_tree().get_first_node_in_group("heat_tracker") if get_tree() else null
	if ht:
		return float(ht.get("heat"))
	return 0.0


func _heat_hud_suffix() -> String:
	var h := get_raid_heat()
	if h <= 0.05:
		return ""
	var bit := "  ·  raid heat %d" % int(h)
	if _heat_bridge and _heat_bridge.has_method("is_alarm_raised") and bool(_heat_bridge.call("is_alarm_raised")):
		bit += " ALARM"
	elif h >= 70.0:
		bit += " HOT"
	elif h >= 50.0:
		bit += " pressure"
	return bit


func _is_player(body: Node) -> bool:
	return body != null and body.is_in_group("player")


func _flash_status(text: String) -> void:
	if status_label:
		status_label.text = text
	hud_refresh.emit(get_hud_text())


func _refresh_labels() -> void:
	if prompt_label:
		match phase:
			Phase.APPROACH:
				prompt_label.text = "E  Start cattle raid"
				prompt_label.visible = true
			Phase.SUCCESS, Phase.FAILED:
				prompt_label.text = "E  Reset herd / retry" if _player_in_start else ""
				prompt_label.visible = _player_in_start
			_:
				prompt_label.visible = false
	if status_label and phase != Phase.SUCCESS and phase != Phase.FAILED:
		if phase == Phase.DRIVING or phase == Phase.RAIDING:
			var st := "Drove %d · need %d · %.0fs · home pens ← west" % [
				_driven_count() + _delivered_count(), MIN_DELIVER, maxf(0.0, time_left)
			]
			var hs := _heat_hud_suffix()
			if hs != "":
				st += hs
			status_label.text = st
		elif phase == Phase.APPROACH:
			status_label.text = "Local túath pens — cut out a drove"
		elif phase == Phase.IDLE:
			status_label.text = "Cattle raid lane"
	hud_refresh.emit(get_hud_text())
