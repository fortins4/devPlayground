extends CanvasLayer
## Toggleable CharacterHealth vitals readout for greybox F5.
##
## Mid-left panel (Honor is top-left; Rumors bottom-left; Timeline top-right;
## Travel bottom-right).
##
## Keys (when this node is in the tree):
##   V — show / hide panel (includes StaminaEconomy fight numbers)
##   ` (backtick / QuoteLeft) — print StaminaEconomy dump to Output
##   F6 — print HatchetAttackTable dump + last resolved dir/tier/dmg/reach
##   F7 — print CombatTags catalog + last applied stagger/wound tags
##   F8 — print BlockPostureTable dump + current posture / last resolve
##   F9 — print FlankBonusTable dump + last open-side resolve
##   F10 — print WoundDecayTable dump + CharacterHealth live bleed/soft accum
##   F11 — print posture-break → CombatTags stagger link + live timers
##   9 / 0 — HP −10 / +10
##   7 / 8 — stamina −10 / +10
##   6 — add wound
##   5 — restore_full()
##   4 — set_downed(true, true) stub

@onready var panel: PanelContainer = $Margin/Panel
@onready var label: Label = $Margin/Panel/Margin/Label

var _refresh_accum: float = 0.0
const REFRESH_INTERVAL := 0.25


func _ready() -> void:
	layer = 24
	visible = true
	_apply_visibility(CharacterHealth.debug_visible if CharacterHealth else false)
	if CharacterHealth:
		if not CharacterHealth.health_changed.is_connected(_on_vitals):
			CharacterHealth.health_changed.connect(_on_vitals)
		if not CharacterHealth.stamina_changed.is_connected(_on_vitals):
			CharacterHealth.stamina_changed.connect(_on_vitals)
		if not CharacterHealth.wounds_changed.is_connected(_on_wounds):
			CharacterHealth.wounds_changed.connect(_on_wounds)
		if not CharacterHealth.downed_changed.is_connected(_on_downed):
			CharacterHealth.downed_changed.connect(_on_downed)
		if not CharacterHealth.died.is_connected(_on_died):
			CharacterHealth.died.connect(_on_died)
		if not CharacterHealth.companion_changed.is_connected(_on_companion):
			CharacterHealth.companion_changed.connect(_on_companion)
		if not CharacterHealth.companion_health_changed.is_connected(_on_vitals):
			CharacterHealth.companion_health_changed.connect(_on_vitals)
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
			KEY_V:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_QUOTELEFT:
				_dump_stamina_economy()
				get_viewport().set_input_as_handled()
			KEY_F6:
				_dump_hatchet_attack_table()
				get_viewport().set_input_as_handled()
			KEY_F7:
				_dump_combat_tags()
				get_viewport().set_input_as_handled()
			KEY_F8:
				_dump_block_posture_table()
				get_viewport().set_input_as_handled()
			KEY_F9:
				_dump_flank_bonus_table()
				get_viewport().set_input_as_handled()
			KEY_F10:
				_dump_wound_decay_table()
				get_viewport().set_input_as_handled()
			KEY_F11:
				_dump_posture_break_stagger()
				get_viewport().set_input_as_handled()
			KEY_9:
				if CharacterHealth:
					CharacterHealth.modify_hp(-10.0)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_0:
				if CharacterHealth:
					CharacterHealth.modify_hp(10.0)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_7:
				if CharacterHealth:
					CharacterHealth.modify_stamina(-10.0)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_8:
				if CharacterHealth:
					CharacterHealth.modify_stamina(10.0)
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_6:
				if CharacterHealth:
					CharacterHealth.add_wound()
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_5:
				if CharacterHealth:
					CharacterHealth.restore_full()
					_refresh()
				get_viewport().set_input_as_handled()
			KEY_4:
				if CharacterHealth:
					CharacterHealth.set_downed(true, true)
					_refresh()
				get_viewport().set_input_as_handled()


func _toggle() -> void:
	var show := true
	if CharacterHealth:
		show = CharacterHealth.toggle_debug_visible()
	else:
		show = not (panel.visible if panel else false)
	_apply_visibility(show)
	_refresh()


func _apply_visibility(show: bool) -> void:
	if panel:
		panel.visible = show


func _on_vitals(_a = null, _b = null) -> void:
	_refresh()


func _on_wounds(_count: int) -> void:
	_refresh()


func _on_downed(_downed: bool) -> void:
	_refresh()


func _on_died() -> void:
	_refresh()


func _on_companion(_active: bool, _id: StringName) -> void:
	_refresh()


func _dump_stamina_economy() -> void:
	var combat := _find_player_combat()
	if combat and combat.has_method("dump_stamina_economy"):
		combat.dump_stamina_economy()
	else:
		var cur := CharacterHealth.stamina if CharacterHealth else -1.0
		print(StaminaEconomy.get_debug_text(cur))
	_refresh()


func _dump_hatchet_attack_table() -> void:
	var combat := _find_player_combat()
	if combat and combat.has_method("dump_hatchet_attack_table"):
		combat.dump_hatchet_attack_table()
	else:
		print(HatchetAttackTable.get_debug_text())
	_refresh()


func _dump_combat_tags() -> void:
	var combat := _find_player_combat()
	if combat and combat.has_method("dump_combat_tags"):
		combat.dump_combat_tags()
	else:
		print(CombatTags.get_debug_text())
	_refresh()


func _dump_block_posture_table() -> void:
	var combat := _find_player_combat()
	if combat and combat.has_method("dump_block_posture_table"):
		combat.dump_block_posture_table()
	else:
		print(BlockPostureTable.get_debug_text())
	_refresh()


func _dump_flank_bonus_table() -> void:
	var combat := _find_player_combat()
	if combat and combat.has_method("dump_flank_bonus_table"):
		combat.dump_flank_bonus_table()
	else:
		print(FlankBonusTable.get_debug_text())
	_refresh()


func _dump_wound_decay_table() -> void:
	if CharacterHealth and CharacterHealth.has_method("dump_wound_decay_table"):
		CharacterHealth.dump_wound_decay_table()
	else:
		print(WoundDecayTable.get_debug_text())
	_refresh()


func _dump_posture_break_stagger() -> void:
	var combat := _find_player_combat()
	if combat and combat.has_method("dump_posture_break_stagger"):
		combat.dump_posture_break_stagger()
	elif combat and combat.has_method("get_posture_break_stagger_debug_text"):
		print(combat.get_posture_break_stagger_debug_text())
	else:
		print(
			"Posture break → CombatTags %s (dur %.2fs) — CombatSystem dump unavailable" % [
				String(BlockPostureTable.BREAK_STAGGER_TAG),
				BlockPostureTable.break_stun_sec(),
			]
		)
	_refresh()


func _refresh() -> void:
	if label == null:
		return
	var text := ""
	if CharacterHealth:
		text = CharacterHealth.get_debug_text()
	else:
		text = "CharacterHealth autoload missing"
	var bridge := _find_player_bridge()
	if bridge:
		text += "\n" + bridge.get_debug_text()
	var combat := _find_player_combat()
	if combat and combat.has_method("get_stamina_economy_debug_text"):
		text += "\n" + combat.get_stamina_economy_debug_text()
	else:
		var cur := CharacterHealth.stamina if CharacterHealth else -1.0
		text += "\n" + StaminaEconomy.get_debug_text(cur)
	if combat and combat.has_method("get_hatchet_attack_table_debug_text"):
		text += "\n" + combat.get_hatchet_attack_table_debug_text()
	else:
		text += "\n" + HatchetAttackTable.get_debug_text()
	if combat and combat.has_method("get_combat_tags_debug_text"):
		text += "\n" + combat.get_combat_tags_debug_text()
	else:
		text += "\n" + CombatTags.get_debug_text()
	if combat and combat.has_method("get_block_posture_debug_text"):
		text += "\n" + combat.get_block_posture_debug_text()
	else:
		text += "\n" + BlockPostureTable.get_debug_text()
	if combat and combat.has_method("get_flank_bonus_debug_text"):
		text += "\n" + combat.get_flank_bonus_debug_text()
	else:
		text += "\n" + FlankBonusTable.get_debug_text()
	if CharacterHealth and CharacterHealth.has_method("get_wound_decay_debug_text"):
		text += "\n" + CharacterHealth.get_wound_decay_debug_text()
	else:
		text += "\n" + WoundDecayTable.get_debug_text()
	if combat and combat.has_method("get_posture_break_stagger_debug_text"):
		text += "\n" + combat.get_posture_break_stagger_debug_text()
	label.text = text


func _find_player_bridge() -> HealthCombatBridge:
	if not is_inside_tree():
		return null
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("HealthCombatBridge") as HealthCombatBridge


func _find_player_combat() -> CombatSystem:
	if not is_inside_tree():
		return null
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	var node := player.get_node_or_null("CombatSystem")
	return node as CombatSystem if node is CombatSystem else null
