extends SceneTree
## Headless / Remote probe for Crowd town presence stub.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_crowd_towns.gd
##
## No Godot binary in CI agents — after F5, in Editor Remote:
##   print(Crowd.probe_remote(true))
##   print(Crowd.list_by_region(&"wexford_waterford"))
##   Crowd.set_density(&"dublin", 0.9)
##   print(Crowd.get_tier(&"dublin"))
##   print(Crowd.get_debug_text())

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_CROWD_TOWNS start")

	if Crowd == null:
		push_error("PROBE_FAIL Crowd autoload missing")
		quit(1)
		return

	var ids: Array[StringName] = Crowd.list_site_ids()
	print("sites=", ids.size())
	if ids.size() < 11:
		push_error("PROBE_FAIL expected >= 11 seeded sites, got %d" % ids.size())
		quit(1)
		return

	if not Crowd.is_known_site(&"dublin") or not Crowd.is_known_site(&"wexford"):
		push_error("PROBE_FAIL dublin/wexford missing")
		quit(1)
		return

	if Crowd.region_for(&"dublin") != &"dublin":
		push_error("PROBE_FAIL dublin region_id")
		quit(1)
		return
	if Crowd.region_for(&"wexford") != &"wexford_waterford":
		push_error("PROBE_FAIL wexford region_id")
		quit(1)
		return

	for sid in CrowdSites.SITE_IDS:
		if not CrowdSites.region_link_ok(sid):
			push_error("PROBE_FAIL region_link_ok false for %s" % String(sid))
			quit(1)
			return

	var ww: Array[Dictionary] = Crowd.list_by_region(&"wexford_waterford")
	print("wexford_waterford sites=", ww.size())
	if ww.size() < 2:
		push_error("PROBE_FAIL expected wexford+waterford under region")
		quit(1)
		return

	var before := Crowd.get_density(&"dublin")
	var prev_tier := int(Crowd.get_tier(&"dublin"))
	var set_out: Dictionary = Crowd.set_density(&"dublin", 0.95)
	print("set_density=", set_out)
	if not bool(set_out.get("ok", false)):
		push_error("PROBE_FAIL set_density")
		quit(1)
		return
	if Crowd.get_density(&"dublin") < 0.94:
		push_error("PROBE_FAIL density not applied")
		quit(1)
		return
	if int(Crowd.get_tier(&"dublin")) != int(CrowdSites.Tier.THRONG):
		push_error("PROBE_FAIL expected THRONG at 0.95")
		quit(1)
		return

	var tier_out: Dictionary = Crowd.set_tier(&"wexford", CrowdSites.Tier.SPARSE)
	print("set_tier wexford sparse=", tier_out.get("density", -1))
	if int(Crowd.get_tier(&"wexford")) != int(CrowdSites.Tier.SPARSE):
		push_error("PROBE_FAIL set_tier")
		quit(1)
		return

	var reg: Dictionary = Crowd.register_site(
		&"probe_fair", "Probe fair", &"leinster", &"market", 0.4
	)
	print("register=", reg)
	if not bool(reg.get("ok", false)) or not Crowd.is_known_site(&"probe_fair"):
		push_error("PROBE_FAIL register_site")
		quit(1)
		return

	var unknown: Dictionary = Crowd.set_density(&"not_a_site", 0.5)
	if bool(unknown.get("ok", true)):
		push_error("PROBE_FAIL unknown site should fail")
		quit(1)
		return

	Crowd.reset_density(&"dublin")
	print("dublin reset dens=", Crowd.get_density(&"dublin"), " (was ", before, " tier ", prev_tier, ")")

	var probe: Dictionary = Crowd.probe_remote(false)
	print("probe_remote=", probe)
	if not bool(probe.get("ok", false)):
		push_error("PROBE_FAIL probe_remote")
		quit(1)
		return

	print(Crowd.get_debug_text())
	print("PROBE_CROWD_TOWNS_OK")
	quit(0)
