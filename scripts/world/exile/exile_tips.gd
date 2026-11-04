extends CanvasLayer
## Open-world (F5) transient screen layer for camp / hunger (2026-11 camp + hunger pass).
## Minimal UI (2026-10-28): only one-off first-use tips that fade by themselves, and the black
## fade used when Cian sleeps. No meters, no always-on text. Each tip id shows once per run.

const TIP_SECONDS := 4.5

var _label: Label
var _black: ColorRect
var _shown := {}
var _tip_left := 0.0
var current_tip := ""


func _ready() -> void:
	add_to_group("exile_tips")
	layer = 40
	_black = ColorRect.new()
	_black.name = "Fade"
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_label = Label.new()
	_label.name = "Tip"
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.offset_top = -120
	_label.offset_bottom = -80
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)


## Show `text` once for `id` (never again this run). Returns true if it showed.
func tip_once(id: StringName, text: String) -> bool:
	if _shown.has(id):
		return false
	_shown[id] = true
	current_tip = text
	_label.text = text
	_tip_left = TIP_SECONDS
	return true


func has_shown(id: StringName) -> bool:
	return _shown.has(id)


func fade_to(alpha: float, seconds: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", alpha, maxf(0.01, seconds))
	return tw


func fade_alpha() -> float:
	return _black.color.a


func _process(delta: float) -> void:
	if _tip_left > 0.0:
		_tip_left -= delta
		_label.modulate.a = clampf(minf(_tip_left, TIP_SECONDS - _tip_left) / 0.4, 0.0, 1.0)
		if _tip_left <= 0.0:
			current_tip = ""
			_label.modulate.a = 0.0
