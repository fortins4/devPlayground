class_name StaminaEconomy
extends RefCounted
## Fight stamina / recover numbers — greybox tunable source of truth.
##
## CombatSystem reads max / regen / delay / sprint / attack costs+recovery /
## block stubs from here. Knife/goad damage/reach + all windup/active stay on
## CombatSystem PROFILES; hatchet damage/reach live in HatchetAttackTable.
## Feel (anims, hitstop polish, telegraph) is Godot-owned — this file is DATA only.

## Pool size (CombatSystem + CharacterHealth session default).
const MAX_STAMINA: float = 100.0
## Passive refill rate while idle (not attacking / not blocking) after delay.
const REGEN_PER_SEC: float = 18.0
## Gate after last stamina spend and when attack recovery ends — recover windows matter.
const REGEN_DELAY_SEC: float = 0.35
## Continuous drain while sprinting.
const SPRINT_DRAIN_PER_SEC: float = 22.0

## Block path stubs (CombatSystem.enable_block stays false until shield gear).
const BLOCK_DRAIN_PER_SEC: float = 8.0
const BLOCK_HIT_COST: float = 12.0
const BLOCK_MIN_STAMINA: float = 5.0

## Per-weapon light / heavy stamina cost + recovery seconds (source of truth).
## Keys match CombatSystem.WEAPON_NAMES values.
const ATTACK: Dictionary = {
	&"hatchet": {
		# Synced with CombatSystem hatchet timing polish (base TOP recovery).
		&"light": {"cost": 12.0, "recovery": 0.34},
		&"heavy": {"cost": 28.0, "recovery": 0.58},
	},
	&"knife": {
		&"light": {"cost": 8.0, "recovery": 0.16},
		&"heavy": {"cost": 18.0, "recovery": 0.28},
	},
	&"goad": {
		&"light": {"cost": 10.0, "recovery": 0.26},
		&"heavy": {"cost": 22.0, "recovery": 0.40},
	},
}


static func attack_entry(weapon: StringName, kind: StringName) -> Dictionary:
	var kit: Dictionary = ATTACK.get(weapon, ATTACK[&"hatchet"])
	return kit.get(kind, kit[&"light"])


static func attack_cost(weapon: StringName, kind: StringName) -> float:
	return float(attack_entry(weapon, kind).get("cost", 12.0))


static func attack_recovery(weapon: StringName, kind: StringName) -> float:
	return float(attack_entry(weapon, kind).get("recovery", 0.28))


## ~N light swings to empty at full STA (floor).
static func light_swings_to_empty(weapon: StringName = &"hatchet") -> int:
	var cost := attack_cost(weapon, &"light")
	if cost <= 0.0:
		return 0
	return int(floor(MAX_STAMINA / cost))


## Seconds to refill empty → full at REGEN_PER_SEC (ignores delay / attack gates).
static func regen_empty_to_full_sec() -> float:
	if REGEN_PER_SEC <= 0.0:
		return INF
	return MAX_STAMINA / REGEN_PER_SEC


static func to_debug_dict(current_stamina: float = -1.0) -> Dictionary:
	var cur := current_stamina if current_stamina >= 0.0 else MAX_STAMINA
	return {
		"max_stamina": MAX_STAMINA,
		"regen_per_sec": REGEN_PER_SEC,
		"regen_delay_sec": REGEN_DELAY_SEC,
		"sprint_drain_per_sec": SPRINT_DRAIN_PER_SEC,
		"block_drain_per_sec": BLOCK_DRAIN_PER_SEC,
		"block_hit_cost": BLOCK_HIT_COST,
		"block_min_stamina": BLOCK_MIN_STAMINA,
		"attack": ATTACK.duplicate(true),
		"current_stamina": cur,
		"hatchet_light_swings_to_empty": light_swings_to_empty(&"hatchet"),
		"regen_empty_to_full_sec": regen_empty_to_full_sec(),
	}


static func get_debug_text(current_stamina: float = -1.0) -> String:
	var d := to_debug_dict(current_stamina)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== StaminaEconomy (fight numbers) ===")
	lines.append(
		"STA %.0f/%.0f   regen %.0f/s   delay %.2fs   sprint %.0f/s" % [
			float(d["current_stamina"]), float(d["max_stamina"]),
			float(d["regen_per_sec"]), float(d["regen_delay_sec"]),
			float(d["sprint_drain_per_sec"]),
		]
	)
	lines.append(
		"block (off): drain %.0f/s  hit cost %.0f  min hold %.0f" % [
			float(d["block_drain_per_sec"]),
			float(d["block_hit_cost"]),
			float(d["block_min_stamina"]),
		]
	)
	for weapon in [&"hatchet", &"knife", &"goad"]:
		var light: Dictionary = attack_entry(weapon, &"light")
		var heavy: Dictionary = attack_entry(weapon, &"heavy")
		lines.append(
			"%s  L cost %.0f recover %.2fs  |  H cost %.0f recover %.2fs" % [
				String(weapon),
				float(light["cost"]), float(light["recovery"]),
				float(heavy["cost"]), float(heavy["recovery"]),
			]
		)
	lines.append(
		"design: ~%d light hatchet to empty · empty→full ~%.1fs (+ delay) · recover gates next swing" % [
			int(d["hatchet_light_swings_to_empty"]),
			float(d["regen_empty_to_full_sec"]),
		]
	)
	lines.append("F5 probe: press ` (backtick) — stamina economy dump (see systems/combat/README.md)")
	return "\n".join(lines)
