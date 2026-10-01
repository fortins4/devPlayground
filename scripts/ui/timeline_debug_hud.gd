extends CanvasLayer
## Toggleable WorldClock / Bannow / rumors / attitudes readout for greybox F5.
##
## Keys (when this node is in the tree):
##   T — show / hide panel
##   Y — WorldClock.advance_day(1)  (also ticks Factions need pressure)
##   U — force-resolve Bannow Bay (skips calendar)
##   I — force-resolve Wexford/Waterford struggle (skips calendar)
##   O — force-resolve Aífe/Strongbow marriage (skips calendar)
##   Z — force-resolve Dublin approaches (skips calendar)
##   X — force-resolve Dublin siege (skips calendar)
##   P — Factions.demo_need_pressure_surge(5)  (need tick without calendar events)
##   / — Factions.probe_quest_stubs()  (sync board + sample pick_up; Q is cycle_weapon)

@onready var panel: PanelContainer = $Margin/Panel
@onready var label: Label = $Margin/Panel/Margin/Label

var _refresh_accum: float = 0.0
const REFRESH_INTERVAL := 0.25


func _ready() -> void:
	layer = 20
	visible = true
	_apply_visibility(WorldClock.debug_visible if WorldClock else false)
	if WorldClock and not WorldClock.day_advanced.is_connected(_on_clock):
		WorldClock.day_advanced.connect(_on_clock)
	if WorldClock and not WorldClock.event_resolved.is_connected(_on_resolved):
		WorldClock.event_resolved.connect(_on_resolved)
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
			KEY_T:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_Y:
				if WorldClock:
					WorldClock.advance_day(1)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_U:
				if WorldClock:
					WorldClock.force_resolve(&"bannow_bay_landing")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_I:
				if WorldClock:
					WorldClock.force_resolve(&"wexford_waterford_struggle")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_O:
				if WorldClock:
					WorldClock.force_resolve(&"aife_strongbow_marriage")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_Z:
				if WorldClock:
					WorldClock.force_resolve(&"dublin_approaches")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_X:
				if WorldClock:
					WorldClock.force_resolve(&"dublin_siege")
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_P:
				if Factions:
					Factions.demo_need_pressure_surge(5)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_SLASH:
				if Factions:
					print(Factions.probe_quest_stubs())
					_refresh()
				get_viewport().set_input_as_handled()


func _toggle() -> void:
	var show := true
	if WorldClock:
		show = WorldClock.toggle_debug_visible()
	else:
		show = not (panel.visible if panel else false)
	_apply_visibility(show)
	_refresh()


func _apply_visibility(show: bool) -> void:
	if panel:
		panel.visible = show


func _on_clock(_day: int) -> void:
	_refresh()


func _on_resolved(_event_id: StringName, _outcome: EventOutcome) -> void:
	_refresh()


func _refresh() -> void:
	if label == null:
		return
	if WorldClock:
		label.text = WorldClock.get_debug_text()
	else:
		label.text = "WorldClock autoload missing"
