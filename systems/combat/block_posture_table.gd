class_name BlockPostureTable
extends RefCounted
## Face-guard / posture numbers for sparring — greybox data surface.
##
## Face guards ≠ full shield block. Shield stubs stay on StaminaEconomy
## (BLOCK_DRAIN / BLOCK_HIT_COST / BLOCK_MIN) with CombatSystem.enable_block off
## for the cattle-farm starter kit. This table is the sparring foe resource:
## hold a face aligned with HatchetAttackTable dirs (&"top"/&"left"/&"right");
## matching attack dir → mitigate + chip posture + stamina cost; mismatch or
## &"open" → full damage + FlankBonusTable open-side multiplier (see flank_bonus_table.gd).
##
## Feel (anims, dummy face-switch AI, telegraph) stays Godot-owned — DATA +
## lookup helpers only. CombatSystem.enable_face_guard (default false) opts in.

## Guard faces. Aligned with HatchetAttackTable.DIRECTIONS + open / no guard.
const FACES: Array[StringName] = [&"top", &"left", &"right", &"open"]

const DEFAULT_FACE: StringName = &"open"

## Shared posture pool (separate from stamina). Break when emptied.
const MAX_POSTURE: float = 100.0
const REGEN_PER_SEC: float = 12.0
## Stun / open window after posture hits 0.
## Aligned to CombatTags stagger_heavy (0.75s) — break applies that existing stagger
## tag via CombatSystem (no parallel CC). Prefer break_stun_sec() so retunes follow
## the CombatTags catalog.
const BREAK_STUN_SEC: float = 0.75
## Existing CombatTags stagger applied on posture break (reuse — do not invent new).
const BREAK_STAGGER_TAG: StringName = &"stagger_heavy"

## Per-face numbers.
## damage_mitigation: fraction stripped on face-match (0..1). Remaining = full*(1-m).
## stamina_cost_on_block_hit: STA spend on successful face-match absorb.
## posture_chip: posture pool damage on successful face-match absorb.
## recover_rate: multiplier on POSTURE regen while holding this face.
## window_sec: how long a held face stays up before Godot should refresh (data).
##
## Tuned lighter than full shield (shield stub ~0.75 mitigate / hit cost 12):
## top denser overhead cover; sides snappier / cheaper; open = no cover.
const FACE_TABLE: Dictionary = {
	&"top": {
		"damage_mitigation": 0.60,
		"stamina_cost_on_block_hit": 8.0,
		"posture_chip": 22.0,
		"recover_rate": 1.00,
		"window_sec": 1.40,
		"notes": "overhead high guard — denser cover, heavier posture chip",
	},
	&"left": {
		"damage_mitigation": 0.55,
		"stamina_cost_on_block_hit": 6.0,
		"posture_chip": 18.0,
		"recover_rate": 1.05,
		"window_sec": 1.20,
		"notes": "left face — sideswing cover; open right/top",
	},
	&"right": {
		"damage_mitigation": 0.55,
		"stamina_cost_on_block_hit": 6.0,
		"posture_chip": 18.0,
		"recover_rate": 1.05,
		"window_sec": 1.20,
		"notes": "right face — sideswing cover; open left/top",
	},
	&"open": {
		"damage_mitigation": 0.0,
		"stamina_cost_on_block_hit": 0.0,
		"posture_chip": 0.0,
		"recover_rate": 1.15,
		"window_sec": 0.0,
		"notes": "no guard — full damage + FlankBonusTable open_guard mult; faster posture regen",
	},
}


static func normalize_face(face: StringName) -> StringName:
	if face in FACES:
		return face
	# Accept hatchet dirs; anything else → open (safer than inventing a guard).
	if face == &"top" or face == &"left" or face == &"right":
		return face
	return DEFAULT_FACE


static func is_open(face: StringName) -> bool:
	return normalize_face(face) == &"open"


static func faces_match(guard_face: StringName, attack_dir: StringName) -> bool:
	## Match only when both are a real face (not open) and equal.
	var g := normalize_face(guard_face)
	var a := normalize_face(attack_dir)
	if g == &"open" or a == &"open":
		return false
	return g == a


static func is_open_side(guard_face: StringName, attack_dir: StringName) -> bool:
	## True when attack does not hit the guarded face (mismatch or open guard).
	## Open-side hits get FlankBonusTable.bonus_for (CombatSystem applies when unmitigated).
	return not faces_match(guard_face, attack_dir)


static func face_entry(face: StringName) -> Dictionary:
	var f := normalize_face(face)
	var raw: Dictionary = FACE_TABLE.get(f, FACE_TABLE[DEFAULT_FACE])
	return {
		"face": f,
		"damage_mitigation": float(raw.get("damage_mitigation", 0.0)),
		"stamina_cost_on_block_hit": float(raw.get("stamina_cost_on_block_hit", 0.0)),
		"posture_chip": float(raw.get("posture_chip", 0.0)),
		"recover_rate": float(raw.get("recover_rate", 1.0)),
		"window_sec": float(raw.get("window_sec", 0.0)),
		"notes": String(raw.get("notes", "")),
	}


static func mitigation_for(guard_face: StringName, attack_dir: StringName) -> float:
	## Fraction of incoming damage stripped on face-match; 0 on open/mismatch.
	if not faces_match(guard_face, attack_dir):
		return 0.0
	return float(face_entry(guard_face)["damage_mitigation"])


static func stamina_cost_for(guard_face: StringName, attack_dir: StringName) -> float:
	if not faces_match(guard_face, attack_dir):
		return 0.0
	return float(face_entry(guard_face)["stamina_cost_on_block_hit"])


static func posture_chip_for(guard_face: StringName, attack_dir: StringName) -> float:
	if not faces_match(guard_face, attack_dir):
		return 0.0
	return float(face_entry(guard_face)["posture_chip"])


static func recover_rate_for(guard_face: StringName) -> float:
	return float(face_entry(guard_face)["recover_rate"])


static func window_sec_for(guard_face: StringName) -> float:
	return float(face_entry(guard_face)["window_sec"])


static func break_stagger_tag() -> StringName:
	## CombatTags stagger applied when posture pool empties.
	return BREAK_STAGGER_TAG


static func break_stun_sec() -> float:
	## Break open-window duration — driven by CombatTags stagger duration when known.
	var d := CombatTags.duration_sec(BREAK_STAGGER_TAG)
	return d if d > 0.0 else BREAK_STUN_SEC


static func break_stagger_entry() -> Dictionary:
	## Catalog entry for the break → stagger link (empty if tag missing).
	return CombatTags.stagger_entry(BREAK_STAGGER_TAG)


## Resolve a guard absorb attempt. Pure data — caller applies costs / HP.
## Returns matched, open_side, mitigation, mitigated_amount, remaining_damage,
## stamina_cost, posture_chip, face entry fields.
static func resolve_guard_hit(
	guard_face: StringName,
	attack_dir: StringName,
	incoming_damage: float,
) -> Dictionary:
	var g := normalize_face(guard_face)
	var a := normalize_face(attack_dir)
	var matched := faces_match(g, a)
	var entry := face_entry(g)
	var mitigation := float(entry["damage_mitigation"]) if matched else 0.0
	var incoming := maxf(0.0, incoming_damage)
	var mitigated_amount := incoming * mitigation
	var remaining := maxf(0.0, incoming - mitigated_amount)
	return {
		"guard_face": g,
		"attack_dir": a,
		"matched": matched,
		"open_side": not matched,
		"mitigation": mitigation,
		"incoming_damage": incoming,
		"mitigated_amount": mitigated_amount,
		"remaining_damage": remaining,
		"stamina_cost": float(entry["stamina_cost_on_block_hit"]) if matched else 0.0,
		"posture_chip": float(entry["posture_chip"]) if matched else 0.0,
		"recover_rate": float(entry["recover_rate"]),
		"window_sec": float(entry["window_sec"]),
	}


## Seconds empty → full at base REGEN_PER_SEC (ignores face recover_rate / break).
static func regen_empty_to_full_sec() -> float:
	if REGEN_PER_SEC <= 0.0:
		return INF
	return MAX_POSTURE / REGEN_PER_SEC


## ~N matched top absorbs to empty posture at full (floor).
static func top_absorbs_to_break() -> int:
	var chip := float(FACE_TABLE[&"top"].get("posture_chip", 22.0))
	if chip <= 0.0:
		return 0
	return int(floor(MAX_POSTURE / chip))


static func to_debug_dict(current_posture: float = -1.0, guard_face: StringName = &"") -> Dictionary:
	var cur := current_posture if current_posture >= 0.0 else MAX_POSTURE
	var faces_out: Dictionary = {}
	for f in FACES:
		faces_out[String(f)] = face_entry(f)
	var stagger_e := break_stagger_entry()
	return {
		"max_posture": MAX_POSTURE,
		"regen_per_sec": REGEN_PER_SEC,
		"break_stun_sec": break_stun_sec(),
		"break_stun_sec_const": BREAK_STUN_SEC,
		"break_stagger_tag": String(BREAK_STAGGER_TAG),
		"break_stagger_duration_sec": float(stagger_e.get("duration_sec", 0.0)),
		"break_stagger_interrupt": int(stagger_e.get("interrupt_strength", 0)),
		"faces": faces_out,
		"default_face": DEFAULT_FACE,
		"current_posture": cur,
		"guard_face": String(normalize_face(guard_face)) if guard_face != &"" else "",
		"top_absorbs_to_break": top_absorbs_to_break(),
		"regen_empty_to_full_sec": regen_empty_to_full_sec(),
		"open_side_note": "mismatch/open → full damage × FlankBonusTable (flank only when unmitigated)",
		"break_stagger_note": "posture break → CombatTags %s (stagger_left + can_move gate)" % String(BREAK_STAGGER_TAG),
	}


static func get_debug_text(
	current_posture: float = -1.0,
	guard_face: StringName = &"",
	last_resolve: Dictionary = {},
) -> String:
	var d := to_debug_dict(current_posture, guard_face)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== BlockPostureTable (face-guard / posture) ===")
	lines.append(
		"POSTURE %.0f/%.0f   regen %.0f/s   break_stun %.2fs" % [
			float(d["current_posture"]), float(d["max_posture"]),
			float(d["regen_per_sec"]), float(d["break_stun_sec"]),
		]
	)
	lines.append(
		"break → CombatTags stagger: %s  dur=%.2fs  interrupt=%d" % [
			str(d["break_stagger_tag"]),
			float(d["break_stagger_duration_sec"]),
			int(d["break_stagger_interrupt"]),
		]
	)
	lines.append("face            mit   sta   chip  recov  window")
	for f in FACES:
		var e: Dictionary = d["faces"][String(f)]
		lines.append(
			"%-8s        %4.2f  %4.0f  %5.0f  %4.2f   %4.2f" % [
				String(f),
				float(e["damage_mitigation"]),
				float(e["stamina_cost_on_block_hit"]),
				float(e["posture_chip"]),
				float(e["recover_rate"]),
				float(e["window_sec"]),
			]
		)
	lines.append(
		"match: guard_face == attack_dir (top/left/right) → mitigate; open/mismatch → full dmg"
	)
	lines.append(
		"design: ~%d matched top absorbs to break · empty→full ~%.1fs · open-side → FlankBonusTable" % [
			int(d["top_absorbs_to_break"]),
			float(d["regen_empty_to_full_sec"]),
		]
	)
	if guard_face != &"":
		lines.append("current guard_face=%s" % String(normalize_face(guard_face)))
	if not last_resolve.is_empty():
		lines.append(
			"last resolve: guard=%s atk=%s matched=%s mit=%.2f rem=%.1f chip=%.0f sta=%.0f open=%s" % [
				String(last_resolve.get("guard_face", &"")),
				String(last_resolve.get("attack_dir", &"")),
				str(last_resolve.get("matched", false)),
				float(last_resolve.get("mitigation", 0.0)),
				float(last_resolve.get("remaining_damage", 0.0)),
				float(last_resolve.get("posture_chip", 0.0)),
				float(last_resolve.get("stamina_cost", 0.0)),
				str(last_resolve.get("open_side", true)),
			]
		)
	else:
		lines.append("last resolve: (none yet)")
	lines.append("F5 probe: press F8 — block/posture · F11 — posture-break→stagger link (see systems/combat/README.md)")
	return "\n".join(lines)
