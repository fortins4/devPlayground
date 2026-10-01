class_name CorpseSpawner
extends RefCounted
## Spawn a draggable corpse from combat death (or anywhere). FULL bog-drag hook.

const CORPSE_SCENE := preload("res://scenes/characters/npcs/draggable_corpse.tscn")


static func spawn_at(parent: Node, world_pos: Vector3, yaw: float = 0.0, source_name: String = "kill") -> Node3D:
	if parent == null:
		return null
	var corpse: Node3D = CORPSE_SCENE.instantiate() as Node3D
	parent.add_child(corpse)
	corpse.global_position = world_pos
	corpse.rotation = Vector3(0.0, yaw, 0.0)
	if corpse.has_method("_apply_ground_pose"):
		corpse.call("_apply_ground_pose")
	if corpse.has_method("_refresh_labels"):
		corpse.call("_refresh_labels")
	corpse.set_meta("spawn_source", source_name)
	return corpse


static func spawn_from_combatant(combatant: Node3D) -> Node3D:
	if combatant == null or not is_instance_valid(combatant):
		return null
	var parent := combatant.get_parent()
	if parent == null:
		parent = combatant.get_tree().current_scene
	if parent == null:
		return null
	var pos := combatant.global_position
	pos.y = maxf(pos.y, 0.1)
	return spawn_at(parent, pos, combatant.rotation.y, "combat_kill")
