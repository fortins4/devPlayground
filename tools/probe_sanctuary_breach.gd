extends SceneTree
## Headless / Remote probe for SanctuaryLocations breach → Honor / Rumors hooks.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_sanctuary_breach.gd
##
## No Godot binary in CI agents — after F5, in Editor Remote:
##   print(SanctuaryLocations.probe_remote())
##   print(SanctuaryLocations.resolve_breach(&"glendalough", &"steel"))
##   print(Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_BREACH))
##   print(Honor.last_law_result)

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_SANCTUARY_BREACH start")

	if Honor == null:
		push_error("PROBE_FAIL Honor autoload missing")
		quit(1)
		return
	if Rumors == null:
		push_error("PROBE_FAIL Rumors autoload missing")
		quit(1)
		return

	SanctuaryLocations.reset_breach_tracking()
	Rumors.clear_all()

	var preview: Dictionary = SanctuaryLocations.probe_breach(&"glendalough")
	print("probe_breach glendalough ok=", preview.get("ok", false))
	print(
		"  deltas church=",
		preview.get("honor_delta_church", 0.0),
		" overall=",
		preview.get("honor_delta_overall", 0.0),
		" tags=",
		preview.get("rumor_tags", [])
	)
	if not bool(preview.get("ok", false)):
		push_error("PROBE_FAIL probe_breach unknown site")
		quit(1)
		return

	var church_before := Honor.get_honor(&"church")
	var overall_before := Honor.get_honor()
	var out: Dictionary = SanctuaryLocations.resolve_breach(&"glendalough", &"steel")
	print("resolve_breach=", out)
	if not bool(out.get("ok", false)):
		push_error("PROBE_FAIL resolve_breach")
		quit(1)
		return
	if not bool(out.get("rumor_seeded", false)):
		push_error("PROBE_FAIL rumor not seeded")
		quit(1)
		return

	var rumor_id: StringName = out.get("rumor_id", &"")
	if not Rumors.has_rumor(rumor_id):
		push_error("PROBE_FAIL Rumors.has_rumor false for %s" % String(rumor_id))
		quit(1)
		return
	var rumor: Dictionary = Rumors.get_rumor(rumor_id)
	var tags: Array = rumor.get("tags", [])
	for required in [&"church", &"sanctuary", &"breach"]:
		var found := false
		for t in tags:
			if String(t) == String(required):
				found = true
				break
		if not found:
			push_error("PROBE_FAIL missing tag %s in %s" % [String(required), str(tags)])
			quit(1)
			return

	var church_after := Honor.get_honor(&"church")
	var overall_after := Honor.get_honor()
	print(
		"Honor church %.1f → %.1f  overall %.1f → %.1f" % [
			church_before, church_after, overall_before, overall_after,
		]
	)
	if church_after >= church_before:
		push_error("PROBE_FAIL expected church honor drop")
		quit(1)
		return

	# Alias path + escalation
	var out2: Dictionary = SanctuaryLocations.report_breach(&"glendalough", &"blood")
	print("report_breach (escalated)=", out2.get("escalated", false), " count=", out2.get("breach_count", 0))
	if not bool(out2.get("escalated", false)) or int(out2.get("breach_count", 0)) != 2:
		push_error("PROBE_FAIL escalation expected")
		quit(1)
		return

	var unknown: Dictionary = SanctuaryLocations.resolve_breach(&"not_a_site")
	if bool(unknown.get("ok", true)):
		push_error("PROBE_FAIL unknown site should fail")
		quit(1)
		return

	print(SanctuaryLocations.get_debug_text())
	print("probe_remote=", SanctuaryLocations.probe_remote(false))
	print("PROBE_SANCTUARY_BREACH_OK")
	quit(0)
