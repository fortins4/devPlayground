extends Node
## F4 toggles between the F5 main greybox and the opening cattle-drive tutorial.
## F3 in the prologue (debug, until the raid's end hands over by itself): Game.finish_prologue(),
## the handoff into the open world at ExileStart.
## Does not touch cattle_raid_lane / combat. Health-debug F6–F12 dumps stay free.
##
## Mark the key handled *before* change_scene_to_file — after the swap this node is
## freed and get_viewport() is null (crash on the old post-swap call).

const OPENING := "res://scenes/prologue/opening_cattle_drive.tscn"
const MAIN := "res://scenes/main/main.tscn"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var scene_path := String(get_tree().current_scene.scene_file_path) if get_tree().current_scene else ""
	if (event as InputEventKey).keycode == KEY_F3 and scene_path.ends_with("opening_cattle_drive.tscn"):
		get_viewport().set_input_as_handled()
		Game.finish_prologue()
		return
	if (event as InputEventKey).keycode != KEY_F4:
		return
	if scene_path.ends_with("main.tscn"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(OPENING)
	elif scene_path.ends_with("opening_cattle_drive.tscn"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MAIN)
