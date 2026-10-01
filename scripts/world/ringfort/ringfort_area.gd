extends Node3D
## Greybox home ringfort: cattle pens stub, muster point, band recruit/follow.
## Owns a CattleEconomy instance (not an autoload) per economy README.

const SLICE_RECRUIT_OPTION := &"local_kerne"
const SLICE_VISUAL_CAP := 3

@onready var cattle: CattleEconomy = $CattleEconomy
@onready var band_runtime: Node = $BandRuntime
@onready var muster: Area3D = $MusterPoint
@onready var band_label: Label3D = $BandCountLabel
@onready var status_label: Label3D = $StatusLabel

var _player: Node3D = null


func _ready() -> void:
	# Slice: enough cattle for a few kernes; warm readiness for later veteran option.
	if cattle:
		cattle.herd_size = 16
		cattle.band.set_max_size(8)
		cattle.band.modify_readiness(5.0)
	_find_player()
	if band_runtime and band_runtime.has_method("setup"):
		band_runtime.call("setup", cattle, _player, muster, self)
		if band_runtime.has_signal("followers_changed"):
			band_runtime.followers_changed.connect(_on_followers_changed)
		if band_runtime.has_signal("mode_changed"):
			band_runtime.mode_changed.connect(_on_mode_changed)
	if cattle:
		cattle.band_changed.connect(_on_economy_band_changed)
	if muster:
		if muster.has_signal("player_in_range_changed"):
			muster.player_in_range_changed.connect(_on_muster_range)
		_refresh_muster_prompt()
	_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if muster and muster.has_method("is_player_in_range") and muster.is_player_in_range():
			try_muster_recruit()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("band_toggle"):
		if band_runtime and band_runtime.has_method("toggle_follow_hold"):
			band_runtime.toggle_follow_hold()
			get_viewport().set_input_as_handled()


## Recruit one local kerne (slice default) while under visual cap.
func try_muster_recruit() -> Dictionary:
	if cattle == null:
		return {"ok": false, "reason": &"no_economy"}
	var visual_count := 0
	if band_runtime and band_runtime.has_method("get_follower_count"):
		visual_count = int(band_runtime.get_follower_count())
	if visual_count >= SLICE_VISUAL_CAP:
		_flash_status("Band full at muster (3). Hold/follow with H.")
		_refresh_muster_prompt()
		return {"ok": false, "reason": &"visual_cap"}
	var honor: float = 50.0
	var honor_node := get_node_or_null("/root/Honor")
	if honor_node and honor_node.has_method("get_honor"):
		honor = float(honor_node.call("get_honor"))
	var result: Dictionary = cattle.try_recruit_option(SLICE_RECRUIT_OPTION, honor)
	if bool(result.get("ok", false)):
		_flash_status(
			"Recruited %s (−%d cattle). Band %d."
			% [
				String(result.get("option", {}).get("display_name", "warrior")),
				int(result.get("cattle_spent", 0)),
				cattle.get_band_size(),
			]
		)
	else:
		var reason: StringName = result.get("reason", &"denied")
		_flash_status("Cannot recruit: %s" % String(reason))
	_refresh_labels()
	_refresh_muster_prompt()
	return result


func _find_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group("player") as Node3D
	# Main may instance ringfort before player is ready; retry next frame.
	if _player == null:
		call_deferred("_find_player_deferred")


func _find_player_deferred() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group("player") as Node3D
	if band_runtime and band_runtime.has_method("setup") and _player:
		band_runtime.call("setup", cattle, _player, muster, self)


func _on_followers_changed(_count: int) -> void:
	_refresh_labels()
	_refresh_muster_prompt()


func _on_mode_changed(_follow: bool) -> void:
	_refresh_labels()
	_refresh_muster_prompt()


func _on_economy_band_changed(_size: int, _m: float, _r: float) -> void:
	_refresh_labels()


func _on_muster_range(_inside: bool) -> void:
	_refresh_muster_prompt()


func _refresh_muster_prompt() -> void:
	if muster == null or not muster.has_method("set_prompt"):
		return
	var size: int = cattle.get_band_size() if cattle else 0
	var vis: int = int(band_runtime.get_follower_count()) if band_runtime else 0
	if vis >= SLICE_VISUAL_CAP:
		muster.set_prompt("Muster full (3)\nH follow/hold")
	else:
		var cost := 2
		if cattle:
			cost = cattle.get_recruit_cattle_cost(SLICE_RECRUIT_OPTION)
		muster.set_prompt("E  Muster kerne (−%d cattle)\nBand %d · H follow/hold" % [cost, size])


func _refresh_labels() -> void:
	var size: int = cattle.get_band_size() if cattle else 0
	var morale: float = cattle.get_band_morale() if cattle else 0.0
	var ready: float = cattle.get_band_readiness() if cattle else 0.0
	var herd: int = cattle.get_herd_size() if cattle else 0
	var mode: String = "FOLLOW" if (band_runtime and band_runtime.is_following()) else "HOLD"
	if band_label:
		band_label.text = "Band %d/%d · %s" % [size, SLICE_VISUAL_CAP, mode]
	if status_label and status_label.get_meta("flashing", false) != true:
		status_label.text = "Cattle %d · Morale %.0f · Ready %.0f" % [herd, morale, ready]


func _flash_status(msg: String) -> void:
	if status_label == null:
		return
	status_label.set_meta("flashing", true)
	status_label.text = msg
	get_tree().create_timer(2.4).timeout.connect(_clear_flash)


func _clear_flash() -> void:
	if status_label:
		status_label.set_meta("flashing", false)
	_refresh_labels()
