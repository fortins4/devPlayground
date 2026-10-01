extends SceneTree
## Headless / Remote probe for HealthCombatBridge (CharacterHealth ↔ CombatSystem).
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_health_combat_bridge.gd
##
## No Godot binary in CI agents — after F5, in Editor Remote:
##   var b = get_tree().get_first_node_in_group("player").get_node("HealthCombatBridge")
##   print(b.get_debug_text()); b.apply_damage(14.0); print(b.get_debug_text())
## Or press V (CharacterHealth panel) and take a hit from the dummy — HP should match.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_HEALTH_COMBAT_BRIDGE start")
	if CharacterHealth == null:
		push_error("PROBE_FAIL CharacterHealth autoload missing")
		quit(1)
		return

	# Synthetic CombatSystem (no scene) — proves bind + mirror without F5 world.
	var combat := CombatSystem.new()
	combat.name = "CombatSystem"
	combat.max_health = 100.0
	combat.health = 100.0
	combat.max_stamina = 100.0
	combat.stamina = 100.0
	var probe_player := Node.new()
	probe_player.name = "ProbePlayer"
	probe_player.add_child(combat)
	var bridge := HealthCombatBridge.new()
	bridge.name = "HealthCombatBridge"
	bridge.auto_bind_on_ready = false
	bridge.sync_combat_to_session = true
	bridge.sync_session_to_combat = true
	bridge.sync_stamina = true
	bridge.seed_session_from_combat_on_bind = true
	probe_player.add_child(bridge)
	root.add_child(probe_player)

	await process_frame
	if not bridge.bind_player_combat(combat):
		push_error("PROBE_FAIL bind_player_combat")
		quit(1)
		return
	print(bridge.get_debug_text())
	var d0: Dictionary = bridge.to_debug_dict()
	if not bool(d0.get("bound", false)) or not bool(d0.get("hp_match", false)):
		push_error("PROBE_FAIL after bind match=%s" % str(d0))
		quit(1)
		return

	var dealt: float = bridge.apply_damage(14.0)
	print("apply_damage(14) dealt=", dealt, " combat.hp=", combat.health, " session.hp=", CharacterHealth.hp)
	if not is_equal_approx(combat.health, CharacterHealth.hp):
		push_error("PROBE_FAIL combat→session HP mismatch")
		quit(1)
		return

	CharacterHealth.modify_hp(10.0)
	await process_frame
	print("session modify_hp(+10) combat.hp=", combat.health, " session.hp=", CharacterHealth.hp)
	if not is_equal_approx(combat.health, CharacterHealth.hp):
		push_error("PROBE_FAIL session→combat HP mismatch")
		quit(1)
		return

	var healed: float = bridge.apply_heal(5.0)
	print("apply_heal(5) healed=", healed, " hp=", combat.health)
	print(bridge.get_debug_text())
	print("CharacterHealth.to_debug_dict hp=", CharacterHealth.to_debug_dict().get("hp"))
	print("PROBE_HEALTH_COMBAT_BRIDGE_OK")
	quit(0)
