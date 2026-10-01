extends Node
## Spawns / despawns greybox warrior followers and toggles follow vs hold-at-muster.
## Keeps visual party size in sync with CattleEconomy.band (capped for slice).

signal followers_changed(count: int)
signal mode_changed(follow: bool)

const VISUAL_CAP := 3
const WARRIOR_SCENE := preload("res://scenes/characters/npcs/band_warrior.tscn")

## Follow offsets behind / beside the player (local space).
const FOLLOW_SLOTS: Array[Vector3] = [
	Vector3(-1.1, 0.0, 1.7),
	Vector3(1.1, 0.0, 1.7),
	Vector3(0.0, 0.0, 2.5),
]

@export var visual_cap: int = VISUAL_CAP

var economy = null  # CattleEconomy
var player: Node3D = null
var muster_point: Node3D = null
var follow_enabled: bool = true

var _followers: Array[CharacterBody3D] = []
var _parent_for_spawn: Node3D = null


func setup(
	econ: Node,
	player_node: Node3D,
	muster: Node3D,
	spawn_parent: Node3D
) -> void:
	economy = econ
	player = player_node
	muster_point = muster
	_parent_for_spawn = spawn_parent
	if economy and not economy.band_changed.is_connected(_on_band_changed):
		economy.band_changed.connect(_on_band_changed)
	_sync_to_economy()


func get_follower_count() -> int:
	return _followers.size()


func is_following() -> bool:
	return follow_enabled


func toggle_follow_hold() -> void:
	set_follow_enabled(not follow_enabled)


func set_follow_enabled(enabled: bool) -> void:
	follow_enabled = enabled
	_apply_mode_to_all()
	mode_changed.emit(follow_enabled)


func muster_slot_world(index: int) -> Vector3:
	var origin := Vector3.ZERO
	if muster_point and is_instance_valid(muster_point):
		origin = muster_point.global_position
	var angles := [0.0, 2.0944, -2.0944]  # 120° apart
	var a: float = angles[clampi(index, 0, angles.size() - 1)]
	return origin + Vector3(cos(a) * 1.8, 0.0, sin(a) * 1.8)


func _on_band_changed(_size: int, _morale: float, _readiness: float) -> void:
	_sync_to_economy()


func _sync_to_economy() -> void:
	if economy == null:
		return
	var want := mini(economy.get_band_size(), visual_cap)
	while _followers.size() < want:
		_spawn_follower(_followers.size())
	while _followers.size() > want:
		var w: CharacterBody3D = _followers.pop_back()
		if is_instance_valid(w):
			w.queue_free()
	_apply_mode_to_all()
	followers_changed.emit(_followers.size())


func _spawn_follower(index: int) -> void:
	if _parent_for_spawn == null:
		return
	var warrior: CharacterBody3D = WARRIOR_SCENE.instantiate()
	_parent_for_spawn.add_child(warrior)
	warrior.global_position = muster_slot_world(index) + Vector3(0.0, 0.1, 0.0)
	if warrior.has_method("set_display_name"):
		warrior.call("set_display_name", "Kerne %d" % (index + 1))
	_followers.append(warrior)
	_apply_mode_to_warrior(warrior, index)


func _apply_mode_to_all() -> void:
	for i in _followers.size():
		_apply_mode_to_warrior(_followers[i], i)


func _apply_mode_to_warrior(warrior: CharacterBody3D, index: int) -> void:
	if not is_instance_valid(warrior):
		return
	if follow_enabled and player and is_instance_valid(player):
		var offset: Vector3 = FOLLOW_SLOTS[clampi(index, 0, FOLLOW_SLOTS.size() - 1)]
		if warrior.has_method("set_follow"):
			warrior.call("set_follow", player, offset)
	else:
		if warrior.has_method("set_hold"):
			warrior.call("set_hold", muster_slot_world(index))
