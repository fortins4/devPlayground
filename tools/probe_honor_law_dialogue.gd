extends SceneTree
## Remote / headless probe for Honor↔law dialogue unlock API.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_honor_law_dialogue.gd
##
## No Godot binary in CI agents — paste the same calls in the Editor Remote
## debugger after F5, or press F on the Honor HUD (H) to dump probe_unlocked.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_HONOR_LAW start")
	if Honor == null:
		push_error("PROBE_FAIL Honor autoload missing")
		quit(1)
		return
	print("Honor.to_debug_dict=", Honor.to_debug_dict())
	print("LawDialogueSamples.to_debug_dict keys ok dispute_count=", LawDialogueSamples.list_dispute_ids().size())
	var catalog: Dictionary = LawDialogueSamples.probe_unlocked()
	print("probe_unlocked catalog ok=", catalog.get("ok", false), " disputes=", catalog.get("dispute_count", 0))
	for row in catalog.get("disputes", []):
		print(
			"  ",
			row.get("dispute_id", ""),
			" unlocked=",
			row.get("unlocked_line_ids", []),
			" options=",
			row.get("sample_options", [])
		)
	var sample_id := &"cattle_trespass_brehon"
	var one: Dictionary = LawDialogueSamples.probe_unlocked(sample_id)
	print("probe_unlocked(", sample_id, ") unlocked=", one.get("unlocked_line_ids", []))
	print("list_unlocked_line_ids=", LawDialogueSamples.list_unlocked_line_ids(sample_id))
	var dlg: Dictionary = LawDialogueSamples.build_dialogue(sample_id)
	print("build_dialogue lines=", dlg.get("lines", []).size(), " unlocked_line_ids=", dlg.get("unlocked_line_ids", []))
	# Gate-closed path: drop overall + church, re-probe.
	Honor.modify_honor(-60.0)
	Honor.modify_honor(-60.0, &"church")
	var closed: Dictionary = LawDialogueSamples.probe_unlocked(sample_id)
	print(
		"after thin enech unlocked=",
		closed.get("unlocked_line_ids", []),
		" locked=",
		closed.get("locked_line_ids", []),
		" gates_open=",
		closed.get("gates_open", true)
	)
	print(LawDialogueSamples.get_debug_text())
	print("PROBE_HONOR_LAW_OK")
	quit(0)
