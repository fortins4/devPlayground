extends Area3D
## DEPRECATED stub — replaced by bog_zone.gd for the body-hide prototype.
## Kept so old scene refs fail loudly toward the new script. Prefer BogZone.

func _ready() -> void:
	push_warning("bog_hide_stub is deprecated; use systems/stealth/bog_zone.gd")
	var label := Label3D.new()
	label.text = "Bog stub (deprecated)"
	label.position = Vector3(0.0, 1.2, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 24
	label.modulate = Color(0.6, 0.4, 0.3)
	add_child(label)
