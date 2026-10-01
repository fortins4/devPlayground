extends Node
## Global game session state for Ríocht.

signal game_started
signal prologue_finished

enum GamePhase { BOOT, PROLOGUE, OPEN_WORLD }

var phase: GamePhase = GamePhase.BOOT
var current_region: StringName = &"leinster"


func _ready() -> void:
	_ensure_default_input()
	phase = GamePhase.OPEN_WORLD
	game_started.emit()


func enter_prologue() -> void:
	phase = GamePhase.PROLOGUE


func finish_prologue() -> void:
	phase = GamePhase.OPEN_WORLD
	prologue_finished.emit()


func _ensure_default_input() -> void:
	var binds := {
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"jump": KEY_SPACE,
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event := InputEventKey.new()
			event.physical_keycode = binds[action]
			InputMap.action_add_event(action, event)
