extends CanvasLayer
## Toggleable Crowd town-presence readout for greybox F5.
##
## Mid-right panel (Travel is bottom-right; Timeline top-right; Health mid-left).
##
## Keys (when this node is in the tree):
##   \\ — show / hide panel
##   PageUp / PageDown — cycle focused site
##   Home / End — density −0.1 / +0.1
##   Insert — bump tier +1 (wrap)
##   Delete — reset focused site to base density

@onready var panel: PanelContainer = $Margin/Panel
@onready var label: Label = $Margin/Panel/Margin/Label

var _site_index: int = 0
var _refresh_accum: float = 0.0
const REFRESH_INTERVAL := 0.25


func _ready() -> void:
	layer = 25
	visible = true
	_apply_visibility(Crowd.debug_visible if Crowd else false)
	if Crowd:
		if not Crowd.density_changed.is_connected(_on_crowd_signal):
			Crowd.density_changed.connect(_on_crowd_signal)
		if not Crowd.tier_changed.is_connected(_on_crowd_tier):
			Crowd.tier_changed.connect(_on_crowd_tier)
		if not Crowd.presence_refreshed.is_connected(_on_refreshed):
			Crowd.presence_refreshed.connect(_on_refreshed)
		if not Crowd.site_registered.is_connected(_on_registered):
			Crowd.site_registered.connect(_on_registered)
	_ensure_site_index()
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
			KEY_BACKSLASH:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_PAGEUP:
				_cycle_site(-1)
				get_viewport().set_input_as_handled()
			KEY_PAGEDOWN:
				_cycle_site(1)
				get_viewport().set_input_as_handled()
			KEY_HOME:
				_adjust_density(-0.1)
				get_viewport().set_input_as_handled()
			KEY_END:
				_adjust_density(0.1)
				get_viewport().set_input_as_handled()
			KEY_INSERT:
				_bump_tier(1)
				get_viewport().set_input_as_handled()
			KEY_DELETE:
				_reset_site()
				get_viewport().set_input_as_handled()


func _toggle() -> void:
	var show := true
	if Crowd:
		show = Crowd.toggle_debug_visible()
	else:
		show = not (panel.visible if panel else false)
	_apply_visibility(show)
	_refresh()


func _apply_visibility(show: bool) -> void:
	if panel:
		panel.visible = show


func _on_crowd_signal(_site_id: StringName, _density: float, _previous: float) -> void:
	_refresh()


func _on_crowd_tier(_site_id: StringName, _tier: int, _previous: int) -> void:
	_refresh()


func _on_refreshed(_reason: StringName) -> void:
	_refresh()


func _on_registered(_site_id: StringName) -> void:
	_ensure_site_index()
	_refresh()


func _site_ids() -> Array[StringName]:
	if Crowd == null:
		return []
	return Crowd.list_site_ids()


func _ensure_site_index() -> void:
	var ids := _site_ids()
	if ids.is_empty():
		_site_index = 0
		return
	_site_index = clampi(_site_index, 0, ids.size() - 1)


func _focused_site() -> StringName:
	var ids := _site_ids()
	if ids.is_empty():
		return &""
	_ensure_site_index()
	return ids[_site_index]


func _cycle_site(delta: int) -> void:
	var ids := _site_ids()
	if ids.is_empty():
		return
	_site_index = wrapi(_site_index + delta, 0, ids.size())
	_refresh()


func _adjust_density(delta: float) -> void:
	if Crowd == null:
		return
	var sid := _focused_site()
	if sid == &"":
		return
	Crowd.adjust_density(sid, delta)
	_refresh()


func _bump_tier(delta: int) -> void:
	if Crowd == null:
		return
	var sid := _focused_site()
	if sid == &"":
		return
	var t := int(Crowd.get_tier(sid))
	var next := wrapi(t + delta, 0, CrowdSites.TIER_IDS.size())
	Crowd.set_tier(sid, next as CrowdSites.Tier)
	_refresh()


func _reset_site() -> void:
	if Crowd == null:
		return
	var sid := _focused_site()
	if sid == &"":
		return
	Crowd.reset_density(sid)
	_refresh()


func _refresh() -> void:
	if label == null:
		return
	if Crowd == null:
		label.text = "Crowd autoload missing"
		return
	var sid := _focused_site()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Crowd presence (\\) ===")
	lines.append("Focus: %s (%d/%d)" % [
		String(sid) if sid != &"" else "(none)",
		_site_index + 1 if sid != &"" else 0,
		_site_ids().size(),
	])
	if sid != &"":
		var row := Crowd.get_by_id(sid)
		lines.append("%s · %s" % [Crowd.display_name(sid), String(row.get("kind", &""))])
		lines.append("region=%s link_ok=%s" % [
			String(Crowd.region_for(sid)),
			str(TravelDistances.is_known_region(Crowd.region_for(sid))),
		])
		lines.append("dens=%.2f  eff=%.2f  tier=%s" % [
			Crowd.get_density(sid),
			Crowd.get_effective_density(sid),
			CrowdSites.tier_id(Crowd.get_tier(sid)),
		])
		var season := ""
		if WorldClock and WorldClock.has_method("get_season_id"):
			season = String(WorldClock.get_season_id())
		else:
			season = "(no season API)"
		lines.append("soft_season=%s bias=%s" % [season, str(Crowd.season_bias_enabled)])
	lines.append("PgUp/Dn site · Home/End dens · Ins tier · Del reset")
	lines.append("")
	# Compact roster
	for id in _site_ids():
		var mark := ">" if id == sid else " "
		lines.append("%s %s %.2f %s" % [
			mark,
			String(id),
			Crowd.get_density(id),
			CrowdSites.tier_id(Crowd.get_tier(id)),
		])
	label.text = "\n".join(lines)
