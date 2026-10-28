extends Node
## Puts Cian at the exile start in the F5 open world (open-world chunk 1).
## The pose is the `ExileStart` Marker3D (group "exile_start") in leinster_region.tscn: the wood /
## fen edge west of the burned home ráth, facing the ruin. Used both for a direct F5 run and when
## Game.finish_prologue() hands over from the F4 prologue — one coherent start, not the old centre
## spawn by the combat dummy (the systems yard is still there, ~65 m west).

@export var player_path: NodePath = ^"../Player"


func _ready() -> void:
	# The region's builders run deferred; the marker itself is authored, so it can be read now.
	place_player()


func place_player() -> bool:
	var marker := get_tree().get_first_node_in_group("exile_start") as Node3D
	var player := get_node_or_null(player_path) as Node3D
	if marker == null or player == null:
		push_warning("ExileSpawn: no ExileStart marker or player")
		return false
	player.global_position = marker.global_position
	player.rotation.y = marker.global_rotation.y
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	print("EXILE_SPAWN at=%s yaw=%.2f" % [marker.global_position, marker.global_rotation.y])
	return true
