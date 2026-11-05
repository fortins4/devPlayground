extends SceneTree
## Headless / Remote probe for WorldClock season stub.
##
## Usage (Godot 4.4+, from repo root):
##   godot --headless --path . --script res://tools/probe_worldclock_season.gd
##
## No Godot binary in CI agents — after F5, Timeline HUD (T):
##   print(WorldClock.get_season_id(), WorldClock.days_into_season())
##   WorldClock.advance_day(90)
##   print(WorldClock.get_season_id())  # expect summer
## Or press **Y** repeatedly and watch the Season line on the Day readout.

## Enum mirrors of WorldClock.Season (autoload globals are not visible at
## compile time for --script entry points).
const SEASON_SPRING := 0
const SEASON_SUMMER := 1
const SEASON_AUTUMN := 2
const SEASON_WINTER := 3

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	print("PROBE_WORLDCLOCK_SEASON start")
	var wc: Node = root.get_node_or_null("WorldClock")
	if wc == null:
		push_error("PROBE_FAIL WorldClock autoload missing")
		quit(1)
		return

	if wc.DAYS_PER_SEASON != 90 or wc.DAYS_PER_YEAR != 360:
		push_error("PROBE_FAIL unexpected calendar constants")
		quit(1)
		return

	if wc.day != 0:
		push_error("PROBE_FAIL expected day 0 at probe start")
		quit(1)
		return
	if wc.get_season() != SEASON_SPRING:
		push_error("PROBE_FAIL day 0 should be spring")
		quit(1)
		return
	if wc.get_season_id() != &"spring":
		push_error("PROBE_FAIL season id spring")
		quit(1)
		return
	if wc.days_into_season() != 0 or wc.days_remaining_in_season() != 90:
		push_error("PROBE_FAIL days_into/remaining at day 0")
		quit(1)
		return

	# Boundaries: last day of spring, first day of summer, wrap to spring year 1.
	if wc.get_season(89) != SEASON_SPRING:
		push_error("PROBE_FAIL day 89 should still be spring")
		quit(1)
		return
	if wc.get_season(90) != SEASON_SUMMER:
		push_error("PROBE_FAIL day 90 should be summer")
		quit(1)
		return
	if wc.get_season(180) != SEASON_AUTUMN:
		push_error("PROBE_FAIL day 180 should be autumn")
		quit(1)
		return
	if wc.get_season(270) != SEASON_WINTER:
		push_error("PROBE_FAIL day 270 should be winter")
		quit(1)
		return
	if wc.get_season(360) != SEASON_SPRING:
		push_error("PROBE_FAIL day 360 should wrap to spring")
		quit(1)
		return
	if wc.get_year_index(360) != 1 or wc.day_of_year(360) != 0:
		push_error("PROBE_FAIL year wrap at day 360")
		quit(1)
		return

	var flipped := {"from": null, "to": null}
	var on_season := func(season, previous) -> void:
		flipped["from"] = previous
		flipped["to"] = season
	wc.season_changed.connect(on_season)

	wc.advance_day(90)
	if wc.day != 90:
		push_error("PROBE_FAIL advance_day(90) day")
		quit(1)
		return
	if wc.get_season() != SEASON_SUMMER:
		push_error("PROBE_FAIL after advance 90 should be summer")
		quit(1)
		return
	if flipped["to"] != SEASON_SUMMER or flipped["from"] != SEASON_SPRING:
		push_error("PROBE_FAIL season_changed did not fire spring→summer")
		quit(1)
		return

	var dbg: Dictionary = wc.to_debug_dict()
	if str(dbg.get("season", "")) != "summer":
		push_error("PROBE_FAIL to_debug_dict season")
		quit(1)
		return
	print(wc.get_debug_text().split("\n")[1])
	print("PROBE_WORLDCLOCK_SEASON ok season=", wc.get_season_id(),
		" into=", wc.days_into_season(),
		" year=", wc.get_year_index())
	quit(0)
