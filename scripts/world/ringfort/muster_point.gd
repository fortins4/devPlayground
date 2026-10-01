extends Area3D
## Walk-up muster stone — E to recruit a kerne into Cian's band.

signal recruit_requested
signal player_in_range_changed(inside: bool)

@onready var prompt: Label3D = $PromptLabel

var _player_inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	monitoring = true
	monitorable = false
	if prompt:
		prompt.visible = false


func is_player_in_range() -> bool:
	return _player_inside


func set_prompt(text: String) -> void:
	if prompt:
		prompt.text = text
		prompt.visible = _player_inside and text != ""


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		player_in_range_changed.emit(true)
		if prompt:
			prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		player_in_range_changed.emit(false)
		if prompt:
			prompt.visible = false
