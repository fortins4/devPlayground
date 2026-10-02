class_name FlankBonusTable
extends RefCounted
## Open-side / flank damage multipliers — greybox data surface.
##
## When attack direction does not match the defender's face guard (or guard is
## &"open"), apply a damage multiplier on the **unmitigated** hit. Matched face
## guard → 1.0 (no flank bonus). Feel (anims, telegraph, dummy AI) stays
## Godot-owned — DATA + lookup helpers only.
##
## Resolve order (CombatSystem.apply_damage):
##   1. Face-guard mitigate via BlockPostureTable (matched only).
##   2. Flank bonus applies **only when face guard does NOT mitigate**
##      (open / mismatch / posture-broken). Matched absorb → no flank.
##   3. Optional rear (world-space behind defender, `frontal == false`) uses
##      REAR_MULT when the hit is already open-side.
##
## Hatchet dirs are top/left/right only — no dedicated "back" strike axis.
## Rear is world facing from CombatSystem._is_frontal, not a table direction.

## Categories (mutually exclusive face outcomes; rear overlays open-side).
## open_guard: defender holds &"open" (or broken posture treated as open).
## wrong_face: holding a real face, attack hits a different axis.
## rear: open-side + attacker behind defender (world space).
const OPEN_GUARD_MULT: float = 1.25
const WRONG_FACE_MULT: float = 1.20
const REAR_MULT: float = 1.35
const MATCHED_MULT: float = 1.0

## Kind tags returned by classify() / resolve().
const KIND_MATCHED: StringName = &"matched"
const KIND_OPEN_GUARD: StringName = &"open_guard"
const KIND_WRONG_FACE: StringName = &"wrong_face"
const KIND_REAR: StringName = &"rear"


static func _norm_guard(guard_face: StringName) -> StringName:
	return BlockPostureTable.normalize_face(guard_face)


static func _norm_attack(attack_dir: StringName) -> StringName:
	## Hatchet axes only (top/left/right). Unknown → default top.
	if attack_dir in HatchetAttackTable.DIRECTIONS:
		return attack_dir
	return HatchetAttackTable.normalize_direction(attack_dir)


static func classify(guard_face: StringName, attack_dir: StringName, is_rear: bool = false) -> StringName:
	## Face outcome first; rear only labels open-side hits from behind.
	var g := _norm_guard(guard_face)
	var a := _norm_attack(attack_dir)
	if BlockPostureTable.faces_match(g, a):
		return KIND_MATCHED
	if is_rear:
		return KIND_REAR
	if BlockPostureTable.is_open(g):
		return KIND_OPEN_GUARD
	return KIND_WRONG_FACE


static func bonus_for(
	guard_face: StringName,
	attack_dir: StringName,
	is_rear: bool = false,
) -> float:
	## Damage multiplier. 1.0 when face-matched / guarded; >1 on open-side.
	var kind := classify(guard_face, attack_dir, is_rear)
	match kind:
		KIND_MATCHED:
			return MATCHED_MULT
		KIND_REAR:
			return REAR_MULT
		KIND_OPEN_GUARD:
			return OPEN_GUARD_MULT
		_:
			return WRONG_FACE_MULT


static func resolve(
	guard_face: StringName,
	attack_dir: StringName,
	incoming_damage: float,
	is_rear: bool = false,
) -> Dictionary:
	## Pure data — caller multiplies HP. Assumes incoming is already
	## post-mitigation remaining (or full damage when unmitigated).
	var g := _norm_guard(guard_face)
	var a := _norm_attack(attack_dir)
	var kind := classify(g, a, is_rear)
	var mult := bonus_for(g, a, is_rear)
	var incoming := maxf(0.0, incoming_damage)
	var dealt := incoming * mult
	return {
		"guard_face": g,
		"attack_dir": a,
		"is_rear": is_rear,
		"kind": kind,
		"open_side": kind != KIND_MATCHED,
		"multiplier": mult,
		"incoming_damage": incoming,
		"dealt_damage": dealt,
		"bonus_damage": maxf(0.0, dealt - incoming),
	}


static func to_debug_dict(last_resolve: Dictionary = {}) -> Dictionary:
	return {
		"matched_mult": MATCHED_MULT,
		"open_guard_mult": OPEN_GUARD_MULT,
		"wrong_face_mult": WRONG_FACE_MULT,
		"rear_mult": REAR_MULT,
		"resolve_order": "face-guard mitigate first; flank only when unmitigated",
		"kinds": {
			"matched": MATCHED_MULT,
			"open_guard": OPEN_GUARD_MULT,
			"wrong_face": WRONG_FACE_MULT,
			"rear": REAR_MULT,
		},
		"last_resolve": last_resolve.duplicate() if not last_resolve.is_empty() else {},
	}


static func get_debug_text(last_resolve: Dictionary = {}) -> String:
	var d := to_debug_dict(last_resolve)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== FlankBonusTable (open-side multipliers) ===")
	lines.append(
		"matched %.2f · open_guard %.2f · wrong_face %.2f · rear %.2f" % [
			float(d["matched_mult"]),
			float(d["open_guard_mult"]),
			float(d["wrong_face_mult"]),
			float(d["rear_mult"]),
		]
	)
	lines.append(
		"order: BlockPosture mitigate first → flank ONLY when face does NOT mitigate"
	)
	lines.append(
		"open_side = mismatch or open guard; rear = open_side + attacker behind (world)"
	)
	if not last_resolve.is_empty():
		lines.append(
			"last resolve: guard=%s atk=%s rear=%s kind=%s mult=%.2f in=%.1f dealt=%.1f" % [
				String(last_resolve.get("guard_face", &"")),
				String(last_resolve.get("attack_dir", &"")),
				str(last_resolve.get("is_rear", false)),
				String(last_resolve.get("kind", &"")),
				float(last_resolve.get("multiplier", 1.0)),
				float(last_resolve.get("incoming_damage", 0.0)),
				float(last_resolve.get("dealt_damage", 0.0)),
			]
		)
	else:
		lines.append("last resolve: (none yet)")
	lines.append("F5 probe: press F9 — flank bonus dump (see systems/combat/README.md)")
	return "\n".join(lines)
