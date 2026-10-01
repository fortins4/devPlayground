extends CanvasLayer
## Toggleable Rumors bus readout for greybox F5 (bottom-left — avoids Honor/Timeline).
##
## Keys (when this node is in the tree):
##   N — show / hide panel
##   M — Rumors.seed_demo_rumors() (L/N/H/C table lifetimes)
##   , — Rumors.tick_decay(1) — watch left=/life=/hl+; LOW demo drops after 4 ticks
##   . — Factions.demo_seed_diplomatic_swing() (attitude + graph → tagged rumors)
## Remote: Rumors.probe_decay(true) — decay table + severity buckets + tick notes.

@onready var panel: PanelContainer = $Margin/Panel
@onready var label: Label = $Margin/Panel/Margin/Label

var _refresh_accum: float = 0.0
const REFRESH_INTERVAL := 0.25


func _ready() -> void:
	layer = 22
	visible = true
	_apply_visibility(Rumors.debug_visible if Rumors else false)
	if Rumors:
		if not Rumors.rumor_added.is_connected(_on_bus):
			Rumors.rumor_added.connect(_on_bus)
		if not Rumors.rumor_expired.is_connected(_on_bus):
			Rumors.rumor_expired.connect(_on_bus)
		if not Rumors.rumors_decayed.is_connected(_on_decayed):
			Rumors.rumors_decayed.connect(_on_decayed)
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
			KEY_N:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_M:
				if Rumors:
					Rumors.seed_demo_rumors()
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_COMMA:
				if Rumors:
					Rumors.tick_decay(1)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_PERIOD:
				if Factions:
					Factions.demo_seed_diplomatic_swing()
					_refresh()
				get_viewport().set_input_as_handled()


func _toggle() -> void:
	var show := true
	if Rumors:
		show = Rumors.toggle_debug_visible()
	else:
		show = not (panel.visible if panel else false)
	_apply_visibility(show)
	_refresh()


func _apply_visibility(show: bool) -> void:
	if panel:
		panel.visible = show


func _on_bus(_rumor_id: StringName) -> void:
	_refresh()


func _on_decayed(_expired: Array) -> void:
	_refresh()


func _refresh() -> void:
	if label == null:
		return
	if Rumors:
		label.text = Rumors.get_debug_text()
	else:
		label.text = "Rumors autoload missing"
