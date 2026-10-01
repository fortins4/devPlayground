extends CanvasLayer
## Toggleable Honor / law-gate readout for greybox F5.
##
## Keys (when this node is in the tree):
##   H — show / hide panel
##   [ / ] — overall honor −5 / +5
##   ; / ' — church honor −5 / +5  (semicolon / apostrophe)
##   E — attempt sample éraic path
##   R — attempt sample sanctuary (refuge) path

@onready var panel: PanelContainer = $Margin/Panel
@onready var label: Label = $Margin/Panel/Margin/Label

var _sample: LawGateSample
var _refresh_accum: float = 0.0
const REFRESH_INTERVAL := 0.25


func _ready() -> void:
	layer = 21
	visible = true
	_ensure_sample()
	_apply_visibility(Honor.debug_visible if Honor else false)
	if Honor and not Honor.honor_changed.is_connected(_on_honor):
		Honor.honor_changed.connect(_on_honor)
	_refresh()


func _process(delta: float) -> void:
	if not visible or panel == null or not panel.visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				if Honor:
					Honor.modify_honor(-5.0)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				if Honor:
					Honor.modify_honor(5.0)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_SEMICOLON:
				if Honor:
					Honor.modify_honor(-5.0, &"church")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_APOSTROPHE:
				if Honor:
					Honor.modify_honor(5.0, &"church")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_E:
				_ensure_sample()
				if _sample:
					_sample.choose_eraic()
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_R:
				_ensure_sample()
				if _sample:
					_sample.choose_sanctuary()
					_refresh()
				get_viewport().set_input_as_handled()


func _toggle() -> void:
	var show := true
	if Honor:
		show = Honor.toggle_debug_visible()
	else:
		show = not (panel.visible if panel else false)
	_apply_visibility(show)
	_refresh()


func _apply_visibility(show: bool) -> void:
	if panel:
		panel.visible = show


func _on_honor(_faction_id: StringName, _value: float) -> void:
	_refresh()


func _ensure_sample() -> void:
	if _sample != null and is_instance_valid(_sample):
		return
	_sample = LawGateSample.new()
	_sample.name = "LawGateSample"
	add_child(_sample)


func _refresh() -> void:
	if label == null:
		return
	if Honor == null:
		label.text = "Honor autoload missing"
		return
	var text := Honor.get_debug_text()
	if _sample:
		text += "\n--- sample dispute ---\n"
		text += "id: %s  counterparty: %s\n" % [
			String(_sample.get_dispute_id()),
			String(_sample.counterparty_faction),
		]
		text += "prompt: %s\n" % _sample.get_dispute_prompt()
		var open := Honor.available_law_options()
		if open.is_empty():
			text += "dialogue: (no open law options)\n"
		else:
			for opt in open:
				text += "dialogue option: [%s]\n" % String(opt)
	label.text = text
