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
	var key_binds := {
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"jump": KEY_SPACE,
		&"sprint": KEY_SHIFT,
		&"cycle_weapon": KEY_Q,
		&"weapon_hatchet": KEY_1,
		&"weapon_knife": KEY_2,
		&"weapon_goad": KEY_3,
		&"interact": KEY_E,
		&"band_toggle": KEY_H,
		&"crouch": KEY_CTRL,
	}
	for action in key_binds:
		_ensure_key_action(action, key_binds[action])

	_ensure_mouse_action(&"attack_light", MOUSE_BUTTON_LEFT)
	_ensure_mouse_action(&"attack_heavy", MOUSE_BUTTON_RIGHT)


func _ensure_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)


func _ensure_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var event := InputEventMouseButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)
