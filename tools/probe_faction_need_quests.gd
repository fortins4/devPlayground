extends SceneTree
## Remote / headless probe for Factions need → quest stub hook board.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_faction_need_quests.gd
##
## No Godot binary in CI agents — paste the same calls in the Editor Remote
## debugger after F5, or press / on the Timeline HUD (T) to dump probe_quest_stubs (Q is cycle_weapon).

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_FACTION_NEED_QUESTS start")
	if Factions == null:
		push_error("PROBE_FAIL Factions autoload missing")
		quit(1)
		return
	print("needs=", Factions.to_needs_debug_dict())
	print("board_before=", Factions.to_quest_stubs_debug_dict())
	var synced: Array = Factions.sync_offered_quest_stubs()
	print("synced_count=", synced.size())
	print("available=", Factions.list_available_quest_stubs().size())
	var probe: Dictionary = Factions.probe_quest_stubs()
	print(
		"probe ok=", probe.get("ok", false),
		" synced=", probe.get("synced_count", 0),
		" sample_id=", probe.get("sample_id", &""),
		" picked_status=", (probe.get("picked", {}) as Dictionary).get("status", &"")
	)
	print(Factions.get_quest_stubs_debug_text())
	# Threshold-cross path: drop a need below clear line, then climb past quest floor.
	var fid := &"anglo_normans"
	var nid := Factions.NEED_HUNGER
	var clear_line := Factions.NEED_QUEST_THRESHOLD - Factions.NEED_HOOK_CLEAR_GAP
	Factions.set_need_pressure(fid, nid, maxf(clear_line - 0.05, 0.0))
	var before_board := Factions.count_offered_quest_stubs()
	Factions.set_need_pressure(fid, nid, Factions.NEED_QUEST_THRESHOLD + 0.05)
	var after_offer := Factions.get_quest_stub(Factions.quest_stub_id(fid, nid))
	print(
		"threshold_cross_offer id=", after_offer.get("id", &""),
		" source=", after_offer.get("source", &""),
		" board_delta=", Factions.count_offered_quest_stubs() - before_board
	)
	print("PROBE_FACTION_NEED_QUESTS_OK")
	quit(0)
