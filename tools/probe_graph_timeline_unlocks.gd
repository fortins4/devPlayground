extends SceneTree
## Headless / Remote probe for GraphTimelineUnlocks ↔ Factions live graph.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_graph_timeline_unlocks.gd
##
## No Godot binary in CI agents — after F5, Timeline HUD (T):
##   print(Factions.to_timeline_unlocks_debug_dict())
##   print(Factions.list_unlocked_timeline_events())
##   print(Factions.demo_seed_graph_timeline_unlocks(true, false))
## Or press **J** to open unlock_dublin_road without chilling the alliance.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_GRAPH_TIMELINE_UNLOCKS start")
	if Factions == null:
		push_error("PROBE_FAIL Factions autoload missing")
		quit(1)
		return

	var seed_report: Dictionary = Factions.to_timeline_unlocks_debug_dict()
	print("seed_open=", (seed_report.get("open_unlocks", []) as Array).size())
	print("seed_events=", seed_report.get("available_event_ids", []))
	print("seed_flags=", seed_report.get("available_content_flags", []))
	print(Factions.get_timeline_unlocks_debug_text())

	# Seed should already unlock port pressure + dynastic seal + norse coast + bannow.
	if not Factions.is_timeline_unlock_open(&"unlock_port_pressure"):
		push_error("PROBE_FAIL unlock_port_pressure should be open at seed")
		quit(1)
		return
	if not Factions.is_timeline_event_unlocked(&"wexford_waterford_struggle"):
		push_error("PROBE_FAIL wexford event should be available at seed")
		quit(1)
		return
	if not Factions.is_timeline_event_unlocked(&"aife_strongbow_marriage"):
		push_error("PROBE_FAIL marriage event should be available at seed")
		quit(1)
		return
	if Factions.is_timeline_unlock_open(&"unlock_dublin_road"):
		push_error("PROBE_FAIL unlock_dublin_road should be closed at seed")
		quit(1)
		return

	var swung: Dictionary = Factions.demo_seed_graph_timeline_unlocks(true, false)
	print("after_dublin_swing=", swung)
	if not Factions.is_timeline_unlock_open(&"unlock_dublin_road"):
		push_error("PROBE_FAIL unlock_dublin_road should open after hostility bump")
		quit(1)
		return
	if not Factions.is_timeline_event_unlocked(&"dublin_approaches"):
		push_error("PROBE_FAIL dublin_approaches should be available after swing")
		quit(1)
		return

	# Exercise marriage gate: chill alliance below 25.
	var gated: Dictionary = Factions.demo_seed_graph_timeline_unlocks(false, true)
	print("after_alliance_chill=", gated)
	if not Factions.is_timeline_gate_active(&"gate_marriage_if_alliance_cold"):
		push_error("PROBE_FAIL marriage gate should activate when alliance cold")
		quit(1)
		return
	if Factions.is_timeline_event_unlocked(&"aife_strongbow_marriage"):
		push_error("PROBE_FAIL marriage event should be gated when alliance cold")
		quit(1)
		return

	# Snapshot evaluate without live Factions (registry purity).
	var snap := GraphTimelineUnlocks.evaluate_registry([])
	if not (snap.get("available_event_ids", []) as Array).is_empty():
		push_error("PROBE_FAIL empty edges should unlock nothing")
		quit(1)
		return

	print(Factions.get_timeline_unlocks_debug_text())
	print("PROBE_GRAPH_TIMELINE_UNLOCKS_OK")
	quit(0)
