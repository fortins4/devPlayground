extends CanvasLayer
## Minimal stamina / HP / weapon readout for the greybox slice.

@onready var label: Label = $Margin/Label

var _combat: CombatSystem


func _ready() -> void:
	await get_tree().process_frame
	_bind_player()


func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_combat = player.get_node_or_null("CombatSystem") as CombatSystem
	if _combat == null:
		return
	_combat.stamina_changed.connect(_on_stats)
	_combat.health_changed.connect(_on_stats)
	_combat.weapon_changed.connect(func(_w): _refresh())
	_combat.died.connect(func(_v): _refresh())
	_refresh()


func _on_stats(_a = null, _b = null) -> void:
	_refresh()


func _process(_delta: float) -> void:
	# Keep drag stamina + charge readout live.
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var dragging := player and player.has_method("is_dragging") and bool(player.call("is_dragging"))
	if dragging or (_combat and (_combat.is_charging or _combat.is_shaft_blocking)):
		_refresh()


func _refresh() -> void:
	if label == null or _combat == null:
		return
	var w := String(_combat.weapon_name())
	var extra := ""
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_drag_status_text"):
		var drag_line: String = str(player.call("get_drag_status_text"))
		if drag_line != "":
			extra = "\n" + drag_line
	var charge_line := ""
	if _combat.is_charging:
		var dir := String(_combat.direction_name())
		charge_line = "\nCHARGE %.2f / %.2fs  dir=%s  (release to strike)" % [_combat.charge_time, _combat.charge_full_secs, dir]
	elif _combat.is_shaft_blocking:
		charge_line = "\nSHAFT BLOCK  hold F  (release to idle)"
	label.text = "HP %d/%d   STA %d/%d   [%s]%s%s\nGoad: hold LMB (look L/R/up shaft, look-down stab; tap=light, 0.75s=full)  hold F shaft-block  Knife: tap LMB  RMB heavy  Q cycle  1 hatchet hold-charge  2 knife  3 goad" % [
		int(_combat.health), int(_combat.max_health),
		int(_combat.stamina), int(_combat.max_stamina),
		w,
		extra,
		charge_line,
	]
