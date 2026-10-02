class_name HatchetAttackTable
extends RefCounted
## Hatchet damage / reach table — directional axes × charge tiers (greybox data).
##
## Directions match SCOPE directional combat (overhead / sideswing). Charge tiers
## map onto existing light/heavy inputs for now; Godot will drive real aim/stick
## direction later. Feel (anims, hitstop, telegraph) stays Godot-owned — this
## file is DATA / lookup API only.
##
## Input stub mapping (CombatSystem):
##   LMB hold-release → tier &"tap" / &"charged" / &"max" from charge ratio
##   STA costs: ChargeStaminaTable (tap 12 / charged 28 / max 34) on release commit
##   Recovery still StaminaEconomy light/heavy via kind_from_tier
## Default direction when aim unknown: &"top".

## Overhead chop / left sideswing / right sideswing.
const DIRECTIONS: Array[StringName] = [&"top", &"left", &"right"]

## Tap = light; charged = heavy; max = optional full-charge bump.
const TIERS: Array[StringName] = [&"tap", &"charged", &"max"]

## Baseline: prior PROFILES hatchet light 14/1.35, heavy 28/1.5.
## Top: slightly higher damage, shorter lateral reach (overhead).
## Left/right: balanced sideswing — tap/charged match prior light/heavy.
## Max: modest bump over charged (~+14% dmg, +0.05 reach).
const TABLE: Dictionary = {
	&"top": {
		&"tap": {"damage": 15.0, "reach": 1.25},
		&"charged": {"damage": 30.0, "reach": 1.40},
		&"max": {"damage": 34.0, "reach": 1.45},
	},
	&"left": {
		&"tap": {"damage": 14.0, "reach": 1.35},
		&"charged": {"damage": 28.0, "reach": 1.50},
		&"max": {"damage": 32.0, "reach": 1.55},
	},
	&"right": {
		&"tap": {"damage": 14.0, "reach": 1.35},
		&"charged": {"damage": 28.0, "reach": 1.50},
		&"max": {"damage": 32.0, "reach": 1.55},
	},
}

const DEFAULT_DIRECTION: StringName = &"top"
const DEFAULT_TIER: StringName = &"tap"


## Map legacy light/heavy kind → charge tier.
static func tier_from_kind(kind: StringName) -> StringName:
	match kind:
		&"heavy":
			return &"charged"
		&"max":
			return &"max"
		&"charged":
			return &"charged"
		&"tap":
			return &"tap"
		_:
			# light / unknown
			return &"tap"


## Map charge tier → StaminaEconomy recovery / PROFILES kind (light|heavy).
## Discrete STA cost for hatchet hold-release: ChargeStaminaTable.cost_for_tier.
static func kind_from_tier(tier: StringName) -> StringName:
	match tier:
		&"charged", &"max", &"heavy":
			return &"heavy"
		_:
			return &"light"


static func normalize_direction(direction: StringName) -> StringName:
	if direction in DIRECTIONS:
		return direction
	return DEFAULT_DIRECTION


static func normalize_tier(tier: StringName) -> StringName:
	if tier in TIERS:
		return tier
	return tier_from_kind(tier)


static func entry(direction: StringName, tier: StringName) -> Dictionary:
	var d := normalize_direction(direction)
	var t := normalize_tier(tier)
	var row: Dictionary = TABLE.get(d, TABLE[DEFAULT_DIRECTION])
	var cell: Dictionary = row.get(t, row[DEFAULT_TIER])
	return {
		"direction": d,
		"tier": t,
		"damage": float(cell.get("damage", 14.0)),
		"reach": float(cell.get("reach", 1.35)),
	}


static func damage(direction: StringName, tier: StringName) -> float:
	return float(entry(direction, tier)["damage"])


static func reach(direction: StringName, tier: StringName) -> float:
	return float(entry(direction, tier)["reach"])


static func to_debug_dict() -> Dictionary:
	var cells: Dictionary = {}
	for d in DIRECTIONS:
		var row: Dictionary = {}
		for t in TIERS:
			var e := entry(d, t)
			row[String(t)] = {"damage": e["damage"], "reach": e["reach"]}
		cells[String(d)] = row
	return {
		"directions": [&"top", &"left", &"right"],
		"tiers": [&"tap", &"charged", &"max"],
		"default_direction": DEFAULT_DIRECTION,
		"input_map": {
			"light": &"tap",
			"heavy": &"charged",
			"max_stamina_kind": &"heavy",
			"charge_sta": "ChargeStaminaTable",
		},
		"table": cells,
	}


static func get_debug_text(
	last_direction: StringName = &"",
	last_tier: StringName = &"",
	last_damage: float = -1.0,
	last_reach: float = -1.0,
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== HatchetAttackTable (damage/reach) ===")
	lines.append("dir×tier          dmg    reach")
	for d in DIRECTIONS:
		for t in TIERS:
			var e := entry(d, t)
			lines.append(
				"%-8s %-8s  %5.1f   %5.2f" % [
					String(d), String(t), float(e["damage"]), float(e["reach"]),
				]
			)
	lines.append("map: hold-release→tap/charged/max · STA ChargeStaminaTable · default dir top")
	if last_direction != &"" and last_tier != &"":
		lines.append(
			"last resolved: dir=%s tier=%s dmg=%.1f reach=%.2f" % [
				String(last_direction), String(last_tier), last_damage, last_reach,
			]
		)
	else:
		lines.append("last resolved: (none yet)")
	lines.append("F5 probe: press F6 — hatchet table dump (see systems/combat/README.md)")
	return "\n".join(lines)
