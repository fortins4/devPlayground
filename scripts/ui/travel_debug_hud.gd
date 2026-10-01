extends CanvasLayer
## Toggleable TravelGate / TravelDistances readout for greybox F5.
##
## Bottom-right panel (Timeline is top-right; Honor top-left; Rumors bottom-left).
##
## Keys (when this node is in the tree):
##   G — show / hide panel
##   J / K — cycle destination among REGION_IDS (skip current)
##   F — toggle horse / foot mode
##   - / = — expedition day budget −1 / +1 (leaves unlimited on first adjust)
##   L — clear budget → unlimited (−1)
##   B — commit previewed travel (advances WorldClock, sets Game.current_region;
##       spends trip days from budget when limited)

@onready var panel: PanelContainer = $Margin/Panel
@onready var label: Label = $Margin/Panel/Margin/Label

var _dest_index: int = 0
var _mode: StringName = &"horse"
var _refresh_accum: float = 0.0
const REFRESH_INTERVAL := 0.25


func _ready() -> void:
	layer = 23
	visible = true
	_apply_visibility(TravelGate.debug_visible if TravelGate else false)
	if Game and not Game.region_changed.is_connected(_on_region):
		Game.region_changed.connect(_on_region)
	if WorldClock and not WorldClock.day_advanced.is_connected(_on_clock):
		WorldClock.day_advanced.connect(_on_clock)
	_ensure_dest_index()
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
			KEY_G:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_J:
				_cycle_dest(-1)
				get_viewport().set_input_as_handled()
			KEY_K:
				_cycle_dest(1)
				get_viewport().set_input_as_handled()
			KEY_F:
				_mode = &"foot" if _mode == &"horse" else &"horse"
				_refresh()
				get_viewport().set_input_as_handled()
			KEY_MINUS:
				if TravelGate:
					TravelGate.adjust_expedition_day_budget(-1)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_EQUAL:
				if TravelGate:
					TravelGate.adjust_expedition_day_budget(1)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_L:
				if TravelGate:
					TravelGate.clear_expedition_day_budget()
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_B:
				_commit()
				get_viewport().set_input_as_handled()


func _toggle() -> void:
	var show := true
	if TravelGate:
		show = TravelGate.toggle_debug_visible()
	else:
		show = not (panel.visible if panel else false)
	_apply_visibility(show)
	_refresh()


func _apply_visibility(show: bool) -> void:
	if panel:
		panel.visible = show


func _on_region(_region_id: StringName) -> void:
	_ensure_dest_index()
	_refresh()


func _on_clock(_day: int) -> void:
	_refresh()


func _destination_ids() -> Array[StringName]:
	var origin := Game.current_region if Game else &"leinster"
	var out: Array[StringName] = []
	for id in TravelDistances.REGION_IDS:
		if id == origin:
			continue
		out.append(id)
	return out


func _ensure_dest_index() -> void:
	var ids := _destination_ids()
	if ids.is_empty():
		_dest_index = 0
		return
	_dest_index = clampi(_dest_index, 0, ids.size() - 1)


func _cycle_dest(delta: int) -> void:
	var ids := _destination_ids()
	if ids.is_empty():
		return
	_dest_index = (_dest_index + delta) % ids.size()
	if _dest_index < 0:
		_dest_index += ids.size()
	_refresh()


func _selected_dest() -> StringName:
	var ids := _destination_ids()
	if ids.is_empty():
		return &""
	return ids[_dest_index]


func _commit() -> void:
	var dest := _selected_dest()
	if dest == &"":
		return
	TravelGate.commit_travel(dest, _mode)
	_ensure_dest_index()
	_refresh()


func _refresh() -> void:
	if label == null:
		return
	var origin := Game.current_region if Game else &"leinster"
	var dest := _selected_dest()
	var lines: PackedStringArray = PackedStringArray()
	if TravelGate:
		lines.append(TravelGate.get_debug_text())
	else:
		lines.append("TravelGate missing")
	lines.append("")
	lines.append("--- Preview / day budget ---")
	lines.append("Mode: %s   (F toggles)" % String(_mode))
	if dest == &"":
		lines.append("Dest: (none)")
		if TravelGate:
			var idle := TravelGate.get_expedition_budget_status(-1)
			lines.append(str(idle.get("summary", "")))
	else:
		var preview: Dictionary = TravelGate.request_travel(dest, _mode) if TravelGate else {}
		var planned := int(preview.get("planned_days", preview.get("days", -1)))
		var status: Dictionary = (
			TravelGate.get_expedition_budget_status(planned) if TravelGate else {}
		)
		lines.append("Dest [%d]: %s (%s)" % [
			_dest_index,
			String(dest),
			TravelDistances.display_name(dest),
		])
		var budget_str := (
			"unlimited" if bool(status.get("unlimited", true))
			else "%d d remaining" % int(status.get("budget", 0))
		)
		lines.append("Budget: %s" % budget_str)
		lines.append("Planned trip cost: %s d" % (str(planned) if planned >= 0 else "?"))
		if bool(status.get("insufficient_days", false)) or String(preview.get("reason", &"")) == "insufficient_days":
			lines.append("Status: INSUFFICIENT_DAYS — %s" % str(status.get("summary", preview.get("summary", ""))))
		else:
			lines.append("Preview ok=%s reason=%s" % [
				str(preview.get("ok", false)),
				String(preview.get("reason", &"")),
			])
			if status.has("summary"):
				lines.append("  %s" % str(status["summary"]))
		var path_ids: Array = preview.get("path", [])
		if not path_ids.is_empty():
			var hops: PackedStringArray = PackedStringArray()
			for p in path_ids:
				hops.append(String(p))
			lines.append("Path: %s" % " → ".join(hops))
		lines.append("B commits %s → %s" % [String(origin), String(dest)])
		lines.append("Keys: -/= budget · L unlimited")
	label.text = "\n".join(lines)
