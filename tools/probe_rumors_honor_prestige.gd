extends SceneTree
## Headless / Remote probe for Rumors ↔ Honor prestige tags.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_rumors_honor_prestige.gd
##
## No Godot binary in CI agents — after F5, in Editor Remote:
##   print(Rumors.probe_prestige(true))
##   print(Honor.demo_seed_prestige_swing())
##   print(Rumors.filter_by_prestige(Rumors.PRIORITY_HIGH))
##   # Reverse nudge (source not in skip list):
##   var before := Honor.get_honor()
##   Rumors.add_rumor(
##     &"probe_prestige_praise", "Hall talk lifts Cian\'s enech.",
##     &"probe", Rumors.PRIORITY_HIGH, 0,
##     Rumors.build_prestige_tags(true)
##   )
##   print(Honor.get_honor() - before)  # +1.5 if honor_nudge_enabled

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_RUMORS_HONOR_PRESTIGE start")

	if Honor == null:
		push_error("PROBE_FAIL Honor autoload missing")
		quit(1)
		return
	if Rumors == null:
		push_error("PROBE_FAIL Rumors autoload missing")
		quit(1)
		return

	Rumors.clear_all()
	Rumors.honor_nudge_enabled = true

	# --- Honor → tagged prestige rumors (HIGH when |Δ| >= 15) ---
	var swing: Dictionary = Honor.demo_seed_prestige_swing()
	print("demo_seed_prestige_swing=", swing)
	if int(swing.get("rumors_active", 0)) < 1:
		push_error("PROBE_FAIL no prestige rumors after swing")
		quit(1)
		return

	var prestige: Array = Rumors.filter_by_prestige()
	if prestige.is_empty():
		push_error("PROBE_FAIL filter_by_prestige empty")
		quit(1)
		return
	var high: Array = Rumors.filter_by_prestige(Rumors.PRIORITY_HIGH)
	if high.is_empty():
		push_error("PROBE_FAIL no HIGH+ prestige rumors")
		quit(1)
		return

	var sample: Dictionary = high[0]
	for required in [&"honor", &"prestige", &"enech"]:
		if not Rumors.rumor_has_tag(sample, required):
			push_error("PROBE_FAIL missing tag %s in %s" % [String(required), str(sample.get("tags", []))])
			quit(1)
			return
	print("HIGH prestige sample id=", sample.get("id"), " tags=", sample.get("tags", []))

	# --- Loop guard: Honor-sourced rumors must NOT reverse-nudge ---
	var overall_after_swing := Honor.get_honor()
	# Re-add a refresh of an honor-sourced id should not nudge; fresh honor source skip:
	Honor.modify_honor(16.0, &"")  # another HIGH prestige seed
	var overall_mid := Honor.get_honor()
	# Delta applied is 16; if reverse nudged from the new rumor we'd see extra —
	# but source=honor is skipped, so overall should be exactly +16 from mid-1 path.
	# overall_mid - overall_after_swing should be 16 (clamped).
	var applied := overall_mid - overall_after_swing
	if absf(applied - 16.0) > 0.01 and overall_mid < 99.9:
		# Allow clamp at ceiling
		if overall_mid < 100.0 - 0.01:
			push_error("PROBE_FAIL unexpected overall delta %s (loop?)" % applied)
			quit(1)
			return
	print("honor→rumor loop guard ok applied=", applied, " honor_sources=", Rumors.filter_rumors(0, &"honor").size())

	# --- Reverse: non-honor HIGH+ prestige rumor lightly nudges Honor ---
	Rumors.clear_all()
	var before := Honor.get_honor()
	Rumors.add_rumor(
		&"probe_prestige_praise",
		"Hall talk lifts Cian's enech across the ringforts.",
		&"probe",
		Rumors.PRIORITY_HIGH,
		0,
		Rumors.build_prestige_tags(true)
	)
	var after := Honor.get_honor()
	var nudge := after - before
	print("reverse nudge delta=", nudge, " expect=", Rumors.HONOR_NUDGE_AMOUNT)
	if absf(nudge - Rumors.HONOR_NUDGE_AMOUNT) > 0.01:
		push_error("PROBE_FAIL reverse honor nudge expected %.2f got %.2f" % [Rumors.HONOR_NUDGE_AMOUNT, nudge])
		quit(1)
		return

	# Nudge must not have seeded an honor-sourced rumor (seed_rumor=false).
	if not Rumors.filter_rumors(0, &"honor").is_empty():
		push_error("PROBE_FAIL reverse nudge seeded honor rumor (loop)")
		quit(1)
		return

	var probe: Dictionary = Rumors.probe_prestige(false)
	print("probe_prestige=", probe)
	if not bool(probe.get("ok", false)):
		push_error("PROBE_FAIL probe_prestige")
		quit(1)
		return

	print("PROBE_RUMORS_HONOR_PRESTIGE_OK")
	quit(0)
