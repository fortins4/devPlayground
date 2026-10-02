extends SceneTree
## Smoke: sparring foe defaults API enables face-guard + BlockPostureTable soak.

const BlockPostureTableScript := preload("res://systems/combat/block_posture_table.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var defaults: Dictionary = BlockPostureTableScript.get_sparring_foe_posture_defaults()
	if not bool(defaults.get("enable_face_guard", false)):
		push_error("SMOKE_FAIL defaults.enable_face_guard expected true")
		quit(1)
		return
	if float(defaults.get("max_posture", 0.0)) != 100.0:
		push_error("SMOKE_FAIL max_posture expected 100")
		quit(1)
		return
	if float(defaults.get("regen_per_sec", 0.0)) != 12.0:
		push_error("SMOKE_FAIL regen_per_sec expected 12")
		quit(1)
		return
	if float(defaults.get("break_stun_sec", 0.0)) < 0.69:
		push_error("SMOKE_FAIL break_stun_sec expected ~0.70")
		quit(1)
		return
	if String(defaults.get("starting_face", &"")) != "top":
		push_error("SMOKE_FAIL starting_face expected top")
		quit(1)
		return
	print("SMOKE defaults_ok max=", defaults["max_posture"], " regen=", defaults["regen_per_sec"])

	var combat_script := load("res://systems/combat/combat_system.gd") as Script
	if combat_script == null:
		push_error("SMOKE_FAIL missing combat_system")
		quit(1)
		return

	var body := CharacterBody3D.new()
	body.name = "SparringDummy"
	root.add_child(body)
	var def = combat_script.new()
	def.name = "CombatSystem"
	def.team = 1
	def.enable_hit_feedback = false
	body.add_child(def)

	await process_frame

	if def.enable_face_guard:
		push_error("SMOKE_FAIL face_guard should start false before apply")
		quit(1)
		return

	var applied: Dictionary = def.apply_sparring_foe_guard_defaults()
	if not def.enable_face_guard:
		push_error("SMOKE_FAIL apply did not enable_face_guard")
		quit(1)
		return
	if def.enable_block:
		push_error("SMOKE_FAIL apply should leave enable_block false")
		quit(1)
		return
	if float(def.posture) < 99.0:
		push_error("SMOKE_FAIL posture not reset to max")
		quit(1)
		return
	if def.guard_face != &"top":
		push_error("SMOKE_FAIL starting face expected top, got %s" % String(def.guard_face))
		quit(1)
		return
	print("SMOKE apply_ok face=", def.guard_face, " posture=", def.posture, " applied=", applied.get("applied_to", ""))

	# Via BlockPostureTable on body (resolve child CombatSystem).
	def.enable_face_guard = false
	def.posture = 10.0
	def.set_face_guard(&"open")
	var via_body: Dictionary = BlockPostureTableScript.apply_sparring_foe_guard_defaults(body)
	if not def.enable_face_guard or def.guard_face != &"top" or float(def.posture) < 99.0:
		push_error("SMOKE_FAIL body apply failed face=%s posture=%s enable=%s" % [
			String(def.guard_face), str(def.posture), str(def.enable_face_guard)
		])
		quit(1)
		return
	print("SMOKE body_apply_ok applied_to=", via_body.get("applied_to", ""))

	# Matched face mitigates via table (not enable_block 0.85 stub).
	def.health = 100.0
	def.set_guard_direction(0)  # StrikeDirection.TOP
	var dealt_match: float = def.apply_damage(20.0, null, true, 0)
	# top mitigation 0.60 → remaining 8.0
	if dealt_match < 7.5 or dealt_match > 8.5:
		push_error("SMOKE_FAIL matched top expected ~8 remaining, got %.2f" % dealt_match)
		quit(1)
		return
	if float(def.posture) > 100.0 - 20.0:
		push_error("SMOKE_FAIL posture chip expected (~78), got %.1f" % float(def.posture))
		quit(1)
		return
	print("SMOKE match_mitigate dealt=", dealt_match, " posture=", def.posture)

	def.health = 100.0
	var posture_before: float = float(def.posture)
	def.set_guard_direction(0)
	var dealt_miss: float = def.apply_damage(20.0, null, true, 1)  # LEFT vs TOP guard
	# mismatch → full * wrong_face flank 1.20 = 24
	if dealt_miss < 23.0 or dealt_miss > 25.0:
		push_error("SMOKE_FAIL mismatch expected ~24 (flank), got %.2f" % dealt_miss)
		quit(1)
		return
	if absf(float(def.posture) - posture_before) > 0.01:
		push_error("SMOKE_FAIL mismatch should not chip posture")
		quit(1)
		return
	print("SMOKE mismatch_flank dealt=", dealt_miss)

	print("SMOKE_OK face_guard_foe_defaults")
	quit(0)
