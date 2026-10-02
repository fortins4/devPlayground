class_name ChargeStaminaTable
extends RefCounted
## Hatchet charge ↔ stamina spend table — greybox data / API.
##
## Maps hold-release charge tiers onto discrete STA costs. Tier names match
## HatchetAttackTable (&"tap" / &"charged" / &"max"); aliases light/mid/full
## accepted. Feel + input timing stay Godot-owned — this file is DATA + spend
## lookup only.
##
## WHEN SPEND FIRES (contract for Godot / CombatSystem):
##   - ON RELEASE / strike commit only (`release_charged_attack` → `try_attack`,
##     or an explicit `CombatSystem.spend_for_charge` / `try_spend_for_charge`).
##   - NOT while holding charge (`begin_charge` / charge tick).
##   - NOT on `cancel_charge` (sprint / hit-stun drop).
##   Insufficient STA → spend returns false; Godot must refuse the strike.
##
## Aligned with CombatSystem charge window (~0.75 s full hold):
##   tap     — short release (held < ~0.08 s or ratio < 0.22)
##   charged — mid hold (ratio >= 0.55, < 0.95)
##   max     — full hold (ratio >= 0.95 / ~0.75 s)

## Documented full-charge hold (matches CombatSystem.charge_full_secs default).
const CHARGE_FULL_SECS: float = 0.75
## Documented tap ceiling (matches CombatSystem.charge_min_release_secs).
const CHARGE_TAP_HOLD_SECS: float = 0.08
## Ratio below this → tap (matches release_charged_attack).
const RATIO_TAP_MAX: float = 0.22
## Ratio at/above this → charged mid tier (matches try_attack tier resolve).
const RATIO_CHARGED_MIN: float = 0.55
## Ratio at/above this → max / full tier.
const RATIO_MAX_MIN: float = 0.95

## Tier names — same as HatchetAttackTable.TIERS.
const TIERS: Array[StringName] = [&"tap", &"charged", &"max"]

const DEFAULT_TIER: StringName = &"tap"
const WEAPON: StringName = &"hatchet"

## Discrete STA cost per charge tier (hatchet hold-release).
## light/tap keeps StaminaEconomy light (12); mid/charged keeps heavy (28);
## full/max bumps above charged (~+21%) so a full 0.75 s commit costs more.
const COSTS: Dictionary = {
	&"tap": 12.0, ## light
	&"charged": 28.0, ## mid
	&"max": 34.0, ## full
}

## Alias map: design language light/mid/full → table tiers.
const ALIASES: Dictionary = {
	&"light": &"tap",
	&"mid": &"charged",
	&"full": &"max",
	&"heavy": &"charged",
}


static func normalize_tier(tier: StringName) -> StringName:
	if tier in TIERS:
		return tier
	if ALIASES.has(tier):
		return ALIASES[tier]
	# Fall back through HatchetAttackTable naming when available.
	return HatchetAttackTable.normalize_tier(tier)


static func cost_for_tier(tier: StringName) -> float:
	var t := normalize_tier(tier)
	return float(COSTS.get(t, COSTS[DEFAULT_TIER]))


## Resolve tier from hold-release charge ratio (+ optional held seconds).
## Matches CombatSystem.release_charged_attack / try_attack thresholds.
static func tier_from_charge(ratio: float, held_secs: float = -1.0) -> StringName:
	var r := clampf(ratio, 0.0, 1.0)
	if held_secs >= 0.0 and held_secs < CHARGE_TAP_HOLD_SECS:
		return &"tap"
	if r < RATIO_TAP_MAX:
		return &"tap"
	if r >= RATIO_MAX_MIN:
		return &"max"
	if r >= RATIO_CHARGED_MIN:
		return &"charged"
	# Partial mid hold below charged threshold — still tap cost (damage may blend).
	return &"tap"


static func can_afford(current_stamina: float, tier: StringName) -> bool:
	return current_stamina >= cost_for_tier(tier)


## Pure lookup helper for callers that own the pool. Returns
## { ok, tier, cost, remaining } — does NOT mutate stamina.
## CombatSystem.spend_for_charge / try_spend_for_charge apply the spend.
static func try_spend_preview(current_stamina: float, tier: StringName) -> Dictionary:
	var t := normalize_tier(tier)
	var cost := cost_for_tier(t)
	var ok := current_stamina >= cost
	return {
		"ok": ok,
		"tier": t,
		"cost": cost,
		"remaining": current_stamina - cost if ok else current_stamina,
		"spend_fires": &"on_release_commit",
	}


static func swings_to_empty(tier: StringName, max_stamina: float = -1.0) -> int:
	var pool := max_stamina if max_stamina > 0.0 else StaminaEconomy.MAX_STAMINA
	var cost := cost_for_tier(tier)
	if cost <= 0.0:
		return 0
	return int(floor(pool / cost))


static func to_debug_dict(current_stamina: float = -1.0, last_tier: StringName = &"", last_cost: float = -1.0) -> Dictionary:
	var cur := current_stamina if current_stamina >= 0.0 else StaminaEconomy.MAX_STAMINA
	var costs: Dictionary = {}
	for t in TIERS:
		costs[String(t)] = cost_for_tier(t)
	return {
		"weapon": WEAPON,
		"charge_full_secs": CHARGE_FULL_SECS,
		"thresholds": {
			"tap_hold_secs": CHARGE_TAP_HOLD_SECS,
			"ratio_tap_max": RATIO_TAP_MAX,
			"ratio_charged_min": RATIO_CHARGED_MIN,
			"ratio_max_min": RATIO_MAX_MIN,
		},
		"tiers": [&"tap", &"charged", &"max"],
		"aliases": {"light": &"tap", "mid": &"charged", "full": &"max"},
		"costs": costs,
		"spend_fires": "on_release_commit",
		"current_stamina": cur,
		"swings_to_empty": {
			"tap": swings_to_empty(&"tap"),
			"charged": swings_to_empty(&"charged"),
			"max": swings_to_empty(&"max"),
		},
		"last_spend_tier": last_tier,
		"last_spend_cost": last_cost,
	}


static func get_debug_text(
	current_stamina: float = -1.0,
	last_tier: StringName = &"",
	last_cost: float = -1.0,
) -> String:
	var d := to_debug_dict(current_stamina, last_tier, last_cost)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== ChargeStaminaTable (hatchet hold-release STA) ===")
	lines.append(
		"window %.2fs full · tap <%.2fs / ratio<%.2f · charged >=%.2f · max >=%.2f" % [
			float(d["charge_full_secs"]),
			float(d["thresholds"]["tap_hold_secs"]),
			float(d["thresholds"]["ratio_tap_max"]),
			float(d["thresholds"]["ratio_charged_min"]),
			float(d["thresholds"]["ratio_max_min"]),
		]
	)
	lines.append("tier (alias)     STA cost   ~swings to empty")
	lines.append(
		"tap (light)      %5.0f      ~%d" % [
			cost_for_tier(&"tap"), swings_to_empty(&"tap"),
		]
	)
	lines.append(
		"charged (mid)    %5.0f      ~%d" % [
			cost_for_tier(&"charged"), swings_to_empty(&"charged"),
		]
	)
	lines.append(
		"max (full)       %5.0f      ~%d" % [
			cost_for_tier(&"max"), swings_to_empty(&"max"),
		]
	)
	lines.append("spend fires: ON RELEASE / strike commit — not while holding, not on cancel")
	lines.append(
		"STA now %.0f/%.0f · can afford tap=%s charged=%s max=%s" % [
			float(d["current_stamina"]),
			StaminaEconomy.MAX_STAMINA,
			str(can_afford(float(d["current_stamina"]), &"tap")),
			str(can_afford(float(d["current_stamina"]), &"charged")),
			str(can_afford(float(d["current_stamina"]), &"max")),
		]
	)
	if last_tier != &"" and last_cost >= 0.0:
		lines.append("last spend: tier=%s cost=%.0f" % [String(last_tier), last_cost])
	else:
		lines.append("last spend: (none yet)")
	lines.append("F5 probe: press F12 — charge↔stamina spend dump (see systems/combat/README.md)")
	return "\n".join(lines)
