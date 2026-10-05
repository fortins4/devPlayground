extends SceneTree
## Smoke: F4 toggles main ↔ opening cattle drive without crashing on set_input_as_handled.
## Simulates the launcher's _unhandled_input path (KEY_F4 pressed) both directions.

const MAIN := "res://scenes/main/main.tscn"
const OPENING := "res://scenes/prologue/opening_cattle_drive.tscn"


func _initialize() -> void:
	_run()


func _fail(msg: String) -> void:
	push_error("SMOKE_FAIL " + msg)
	print("SMOKE_FAIL " + msg)
	quit(1)


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _current_path() -> String:
	if current_scene == null:
		return ""
	return String(current_scene.scene_file_path)


func _press_f4() -> void:
	## Same signal the launcher listens on — must not crash after change_scene.
	var ev := InputEventKey.new()
	ev.keycode = KEY_F4
	ev.pressed = true
	ev.echo = false
	root.propagate_call("_unhandled_input", [ev], true)
	# Also push through the viewport unhandled path if available.
	var vp := root.get_viewport()
	if vp:
		vp.push_input(ev, true)


func _run() -> void:
	var err := change_scene_to_file(MAIN)
	if err != OK:
		_fail("could not load main: %s" % err)
		return
	await _wait_frames(8)
	if not _current_path().ends_with("main.tscn"):
		_fail("expected main after boot, got %s" % _current_path())
		return
	var launcher := current_scene.get_node_or_null("OpeningDriveLauncher")
	if launcher == null:
		_fail("main missing OpeningDriveLauncher")
		return
	print("SMOKE on_main ok")

	# F4 → opening
	_press_f4()
	await _wait_frames(12)
	if not _current_path().ends_with("opening_cattle_drive.tscn"):
		_fail("F4 from main did not reach opening (got %s)" % _current_path())
		return
	if get_first_node_in_group("opening_drive") == null:
		_fail("opening scene loaded but no opening_drive group")
		return
	print("SMOKE f4_to_opening ok")

	# F4 → main
	launcher = current_scene.get_node_or_null("OpeningDriveLauncher")
	if launcher == null:
		_fail("opening missing OpeningDriveLauncher")
		return
	_press_f4()
	await _wait_frames(12)
	if not _current_path().ends_with("main.tscn"):
		_fail("F4 from opening did not return to main (got %s)" % _current_path())
		return
	if get_first_node_in_group("cattle_raid") == null:
		_fail("main after return missing cattle_raid lane")
		return
	print("SMOKE f4_to_main ok")

	# One more round-trip to catch orphaned-viewport regressions.
	_press_f4()
	await _wait_frames(12)
	if not _current_path().ends_with("opening_cattle_drive.tscn"):
		_fail("second F4 to opening failed (got %s)" % _current_path())
		return
	print("SMOKE f4_roundtrip ok")
	print("OPENING_DRIVE_F4_SMOKE_OK")
	quit(0)
