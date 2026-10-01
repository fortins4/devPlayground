extends Area3D
## Light stub for the SCOPE bog body-hide pillar. Full drag/hide deferred.
## Press Interact near this volume later; for now it just labels the wetland greybox.

@export var label_text: String = "Bog (hide body — stub)"

var _label: Label3D


func _ready() -> void:
	monitoring = false
	monitorable = false
	_label = Label3D.new()
	_label.text = label_text
	_label.position = Vector3(0.0, 1.2, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.modulate = Color(0.45, 0.55, 0.4)
	add_child(_label)
