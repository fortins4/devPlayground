extends CanvasLayer
## Minimal HUD for the opening cattle drive: objective line, pen count, controls, banners.

@export var director_path: NodePath = ^"../OpeningDriveDirector"

var _director: Node = null
var _objective: Label
var _status: Label
var _banner: Label
var _flash: Label
var _controls: Label
var _weapon: Label
var _chore: Node = null
var _knife_chore: Node = null
var _maire_chore: Node = null


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_objective = _make_label(root, 20, Color(0.96, 0.9, 0.7))
	_objective.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective.offset_left = 18
	_objective.offset_right = -18
	_objective.offset_top = 14
	_objective.offset_bottom = 70
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = _make_label(root, 18, Color(0.8, 0.95, 0.65))
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.offset_left = -360
	_status.offset_right = -18
	_status.offset_top = 78
	_status.offset_bottom = 140
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon = _make_label(root, 18, Color(0.92, 0.86, 0.66))
	_weapon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_weapon.offset_left = 18
	_weapon.offset_top = 78
	_weapon.offset_right = 420
	_weapon.offset_bottom = 110
	_flash = _make_label(root, 22, Color(1.0, 0.9, 0.5))
	_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash.offset_left = -480
	_flash.offset_right = 480
	_flash.offset_top = 150
	_flash.offset_bottom = 190
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner = _make_label(root, 34, Color(0.8, 0.97, 0.6))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -520
	_banner.offset_right = 520
	_banner.offset_top = -70
	_banner.offset_bottom = 10
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_controls = _make_label(root, 16, Color(0.88, 0.86, 0.78))
	_controls.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_controls.offset_left = 18
	_controls.offset_right = -18
	_controls.offset_top = -36
	_controls.offset_bottom = -10
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls.text = "WASD move · Shift sprint · mouse look · 3 goad · 2 knife · Q cycle · LMB/RMB prod · E interact · R reset herd · T restart · Esc mouse"
	call_deferred("_bind")


func _bind() -> void:
	_director = get_node_or_null(director_path)
	if _director and _director.has_signal("soft_success"):
		_director.connect("soft_success", _on_success)
	if _director and _director.has_signal("stage_changed"):
		_director.connect("stage_changed", _on_stage)
	_chore = get_tree().get_first_node_in_group("opening_bucket_trough")
	_knife_chore = get_tree().get_first_node_in_group("opening_knife_hitch")
	_maire_chore = get_tree().get_first_node_in_group("opening_maire_door_talk")


func _process(_delta: float) -> void:
	if _director == null:
		return
	_objective.text = String(_director.call("objective_text"))
	_status.text = String(_director.call("status_text"))
	var f := String(_director.call("flash_text"))
	if f == "":
		f = _chore_prompt(_chore)
	if f == "":
		f = _chore_prompt(_knife_chore)
	if f == "":
		f = _chore_prompt(_maire_chore)
	_flash.text = f
	_flash.visible = f != ""
	if _chore_active(_chore) or _chore_active(_knife_chore) or _chore_active(_maire_chore):
		_controls.text = "WASD move · Shift sprint · mouse look · 3 goad · 2 knife · Q cycle · LMB/RMB prod · E interact · R reset herd · T restart · Esc mouse"
	else:
		_controls.text = "WASD move · Shift sprint · mouse look · 3 goad · 2 knife · Q cycle · LMB/RMB prod · R reset herd · T restart · Esc mouse"
	var player := get_tree().get_first_node_in_group("player")
	var combat := player.get_node_or_null("CombatSystem") if player else null
	if combat and combat.has_method("weapon_name"):
		_weapon.text = "In hand: %s   (kit: goad · knife)" % String(combat.call("weapon_name"))



func _chore_prompt(chore: Node) -> String:
	if chore and chore.has_method("interact_prompt"):
		return String(chore.call("interact_prompt"))
	return ""


func _chore_active(chore: Node) -> bool:
	return chore != null and chore.has_method("is_active") and bool(chore.call("is_active"))

func _on_success(home: int, total: int) -> void:
	_banner.text = "HERD HOME  ·  %d / %d head in the pen" % [home, total]
	_banner.visible = true


func _on_stage(_stage: int, stage_name: String) -> void:
	if stage_name != "success":
		_banner.visible = false


func _make_label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l
