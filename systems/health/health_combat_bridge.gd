class_name HealthCombatBridge
extends Node
## Optional glue: player CombatSystem ↔ CharacterHealth (session vitals).
##
## Attach on the **player only**. NPCs keep independent CombatSystem HP/STA —
## do not add this node to dummy / sentry / band scenes.
##
## Default: combat melee damage/heal mirrors into CharacterHealth for HUD/feel.
## Optional reverse sync lets CharacterHealth debug keys / heals push back into
## the bound CombatSystem without rewriting either system.

signal bound_changed(is_bound: bool)
signal synced(direction: StringName, hp: float, stamina: float)

## Empty = auto-resolve sibling/parent `CombatSystem` (player layout).
@export var combat_path: NodePath = NodePath("")
@export var auto_bind_on_ready: bool = true
## CombatSystem HP/STA changes → CharacterHealth (autoload).
@export var sync_combat_to_session: bool = true
## CharacterHealth changes → bound CombatSystem (optional reverse).
@export var sync_session_to_combat: bool = true
@export var sync_stamina: bool = true
## On bind, copy combat max/current into CharacterHealth (session seeds from greybox).
@export var seed_session_from_combat_on_bind: bool = true

var _combat: CombatSystem
var _bound: bool = false
## Re-entrancy guard so combat↔session mirrors do not echo forever.
var _echo: bool = false


func _ready() -> void:
	if auto_bind_on_ready:
		call_deferred("bind_from_exports")


func _exit_tree() -> void:
	unbind()


func bind_from_exports() -> bool:
	var combat := _resolve_combat()
	if combat == null:
		push_warning("HealthCombatBridge: no CombatSystem found to bind")
		return false
	return bind_player_combat(combat)


## Bind a player (or companion) CombatSystem to the CharacterHealth session bus.
func bind_player_combat(combat: CombatSystem) -> bool:
	if combat == null or not is_instance_valid(combat):
		return false
	if _bound and _combat == combat:
		return true
	unbind()
	_combat = combat
	_connect_combat(_combat)
	_connect_session()
	_bound = true
	if seed_session_from_combat_on_bind:
		push_combat_to_session()
	bound_changed.emit(true)
	return true


## Convenience: find CombatSystem under an entity (CharacterBody3D) and bind it.
func bind_player_entity(entity: Node) -> bool:
	if entity == null:
		return false
	var combat := _find_combat_under(entity)
	return bind_player_combat(combat)


func unbind() -> void:
	if _combat != null and is_instance_valid(_combat):
		_disconnect_combat(_combat)
	_disconnect_session()
	_combat = null
	if _bound:
		_bound = false
		bound_changed.emit(false)


func is_bound() -> bool:
	return _bound and _combat != null and is_instance_valid(_combat)


func get_bound_combat() -> CombatSystem:
	return _combat if is_bound() else null


# --- Forward helpers (gameplay / probes) ---------------------------------------

## Apply damage through CombatSystem (melee path). Session mirrors via signals
## when sync_combat_to_session is on. If unbound, forwards to CharacterHealth only.
func apply_damage(amount: float, from: Node = null, frontal: bool = true) -> float:
	if amount <= 0.0:
		return 0.0
	if is_bound():
		return _combat.apply_damage(amount, from, frontal)
	if CharacterHealth:
		return -CharacterHealth.modify_hp(-amount)
	return 0.0


## Heal HP on both surfaces when bound (combat + session). Soft-clears combat
## is_dead if HP rises above 0 (stub — no full revive flow).
func apply_heal(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if not is_bound():
		if CharacterHealth:
			return CharacterHealth.modify_hp(amount)
		return 0.0
	_echo = true
	var before := _combat.health
	_combat.health = minf(_combat.max_health, _combat.health + amount)
	var dealt := _combat.health - before
	if _combat.health > 0.0 and _combat.is_dead:
		_combat.is_dead = false
	_combat.health_changed.emit(_combat.health, _combat.max_health)
	if CharacterHealth and sync_combat_to_session:
		CharacterHealth.set_hp(_combat.health)
		if _combat.health > 0.0 and (CharacterHealth.is_downed or CharacterHealth.is_dead):
			CharacterHealth.revive(false)
	_echo = false
	synced.emit(&"heal", _combat.health, _combat.stamina if sync_stamina else -1.0)
	return dealt


## Push current combat vitals into CharacterHealth (one-shot).
func push_combat_to_session() -> void:
	if not is_bound() or CharacterHealth == null:
		return
	_echo = true
	if sync_combat_to_session:
		CharacterHealth.set_max_hp(_combat.max_health, false)
		CharacterHealth.set_hp(_combat.health)
		if sync_stamina:
			CharacterHealth.set_max_stamina(_combat.max_stamina, false)
			CharacterHealth.set_stamina(_combat.stamina)
		if _combat.is_dead or _combat.health <= 0.0:
			CharacterHealth.set_downed(true, true)
	_echo = false
	synced.emit(&"combat_to_session", _combat.health, _combat.stamina)


## Push CharacterHealth vitals into the bound CombatSystem (one-shot).
func push_session_to_combat() -> void:
	if not is_bound() or CharacterHealth == null:
		return
	_echo = true
	if sync_session_to_combat:
		_combat.max_health = CharacterHealth.get_max_hp()
		_combat.health = CharacterHealth.get_hp()
		if sync_stamina:
			_combat.max_stamina = CharacterHealth.get_max_stamina()
			_combat.stamina = CharacterHealth.get_stamina()
		if CharacterHealth.get_is_dead() or CharacterHealth.get_hp() <= 0.0:
			_combat.is_dead = true
		elif _combat.health > 0.0:
			_combat.is_dead = false
		_combat.health_changed.emit(_combat.health, _combat.max_health)
		_combat.stamina_changed.emit(_combat.stamina, _combat.max_stamina)
	_echo = false
	synced.emit(&"session_to_combat", _combat.health, _combat.stamina)


# --- Debug --------------------------------------------------------------------

func to_debug_dict() -> Dictionary:
	return {
		"bound": is_bound(),
		"sync_combat_to_session": sync_combat_to_session,
		"sync_session_to_combat": sync_session_to_combat,
		"sync_stamina": sync_stamina,
		"combat_hp": _combat.health if is_bound() else -1.0,
		"combat_max_hp": _combat.max_health if is_bound() else -1.0,
		"combat_sta": _combat.stamina if is_bound() else -1.0,
		"session_hp": CharacterHealth.hp if CharacterHealth else -1.0,
		"session_sta": CharacterHealth.stamina if CharacterHealth else -1.0,
		"hp_match": _hp_match(),
		"sta_match": _sta_match(),
	}


func get_debug_text() -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== HealthCombatBridge ===")
	lines.append(
		"bound=%s  combat→session=%s  session→combat=%s  stamina=%s" % [
			str(d["bound"]),
			str(d["sync_combat_to_session"]),
			str(d["sync_session_to_combat"]),
			str(d["sync_stamina"]),
		]
	)
	if bool(d["bound"]):
		lines.append(
			"Combat HP %.0f/%.0f  STA %.0f   Session HP %.0f  STA %.0f" % [
				float(d["combat_hp"]), float(d["combat_max_hp"]), float(d["combat_sta"]),
				float(d["session_hp"]), float(d["session_sta"]),
			]
		)
		lines.append(
			"match hp=%s sta=%s" % [str(d["hp_match"]), str(d["sta_match"])]
		)
	else:
		lines.append("(unbound — NPCs stay on CombatSystem only)")
	return "\n".join(lines)


# --- Internals ----------------------------------------------------------------

func _resolve_combat() -> CombatSystem:
	if combat_path != NodePath(""):
		var node := get_node_or_null(combat_path)
		if node is CombatSystem:
			return node as CombatSystem
	var parent := get_parent()
	if parent:
		var under := _find_combat_under(parent)
		if under:
			return under
	return _find_combat_under(self)


func _find_combat_under(node: Node) -> CombatSystem:
	if node == null:
		return null
	if node is CombatSystem:
		return node as CombatSystem
	var child := node.get_node_or_null("CombatSystem")
	if child is CombatSystem:
		return child as CombatSystem
	for c in node.get_children():
		if c is CombatSystem:
			return c as CombatSystem
	return null


func _connect_combat(combat: CombatSystem) -> void:
	if not combat.health_changed.is_connected(_on_combat_health):
		combat.health_changed.connect(_on_combat_health)
	if not combat.stamina_changed.is_connected(_on_combat_stamina):
		combat.stamina_changed.connect(_on_combat_stamina)
	if not combat.died.is_connected(_on_combat_died):
		combat.died.connect(_on_combat_died)


func _disconnect_combat(combat: CombatSystem) -> void:
	if combat.health_changed.is_connected(_on_combat_health):
		combat.health_changed.disconnect(_on_combat_health)
	if combat.stamina_changed.is_connected(_on_combat_stamina):
		combat.stamina_changed.disconnect(_on_combat_stamina)
	if combat.died.is_connected(_on_combat_died):
		combat.died.disconnect(_on_combat_died)


func _connect_session() -> void:
	if CharacterHealth == null:
		return
	if not CharacterHealth.health_changed.is_connected(_on_session_health):
		CharacterHealth.health_changed.connect(_on_session_health)
	if sync_stamina and not CharacterHealth.stamina_changed.is_connected(_on_session_stamina):
		CharacterHealth.stamina_changed.connect(_on_session_stamina)


func _disconnect_session() -> void:
	if CharacterHealth == null:
		return
	if CharacterHealth.health_changed.is_connected(_on_session_health):
		CharacterHealth.health_changed.disconnect(_on_session_health)
	if CharacterHealth.stamina_changed.is_connected(_on_session_stamina):
		CharacterHealth.stamina_changed.disconnect(_on_session_stamina)


func _on_combat_health(current: float, maximum: float) -> void:
	if _echo or not sync_combat_to_session or CharacterHealth == null:
		return
	_echo = true
	if not is_equal_approx(CharacterHealth.get_max_hp(), maximum):
		CharacterHealth.set_max_hp(maximum, false)
	CharacterHealth.set_hp(current)
	_echo = false
	synced.emit(&"combat_to_session", current, CharacterHealth.stamina if CharacterHealth else -1.0)


func _on_combat_stamina(current: float, maximum: float) -> void:
	if _echo or not sync_combat_to_session or not sync_stamina or CharacterHealth == null:
		return
	_echo = true
	if not is_equal_approx(CharacterHealth.get_max_stamina(), maximum):
		CharacterHealth.set_max_stamina(maximum, false)
	CharacterHealth.set_stamina(current)
	_echo = false


func _on_combat_died(_victim: Node) -> void:
	if _echo or not sync_combat_to_session or CharacterHealth == null:
		return
	_echo = true
	CharacterHealth.set_hp(0.0)
	CharacterHealth.set_downed(true, true)
	_echo = false


func _on_session_health(current: float, maximum: float) -> void:
	if _echo or not sync_session_to_combat or not is_bound():
		return
	_echo = true
	_combat.max_health = maximum
	_combat.health = current
	if current <= 0.0:
		if not _combat.is_dead:
			_combat.is_dead = true
	elif _combat.is_dead:
		_combat.is_dead = false
	_combat.health_changed.emit(_combat.health, _combat.max_health)
	_echo = false
	synced.emit(&"session_to_combat", current, _combat.stamina)


func _on_session_stamina(current: float, maximum: float) -> void:
	if _echo or not sync_session_to_combat or not sync_stamina or not is_bound():
		return
	_echo = true
	_combat.max_stamina = maximum
	_combat.stamina = current
	_combat.stamina_changed.emit(_combat.stamina, _combat.max_stamina)
	_echo = false


func _hp_match() -> bool:
	if not is_bound() or CharacterHealth == null:
		return false
	return is_equal_approx(_combat.health, CharacterHealth.hp)


func _sta_match() -> bool:
	if not sync_stamina or not is_bound() or CharacterHealth == null:
		return not sync_stamina
	return is_equal_approx(_combat.stamina, CharacterHealth.stamina)
