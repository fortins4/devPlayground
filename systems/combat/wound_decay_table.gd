class_name WoundDecayTable
extends RefCounted
## Bleed / wound decay over time — greybox DATA surface.
##
## Per wound-tag bleed rates + tag clear times, plus soft wound-counter decay.
## CharacterHealth ticks this when wounds/tags are present (stub — no full
## injury sim). Feel (VFX, limp, bandage UI) stays Godot-owned.
##
## Soft wound counter rule (stub):
##   ALWAYS decay −1 every SOFT_WOUND_DECAY_SEC while wounds > 0.
##   Independent of named tags. clear_wounds / restore_full wipe timers.
##   Godot may later gate with out-of-combat; table exposes the flag for that.
##
## Tag rule:
##   Each active CombatTags wound tag ages; after decay_sec it is removed
##   (softens/clears). While present, bleed_hp_per_sec contributes to HP drain
##   (bruise = 0). Tag clear does NOT auto-adjust the integer wound counter.
##
## Out of scope: permanent scars, limb loss, medical minigame.

## Shared bleed apply cadence (seconds between HP ticks).
const TICK_INTERVAL_SEC: float = 0.5

## Soft integer wound counter: −1 every this many seconds while wounds > 0.
const SOFT_WOUND_DECAY_SEC: float = 30.0

## When true, soft-counter decay only runs while CharacterHealth reports
## not-in-combat. Stub default false = always decay (no combat gate required).
const SOFT_WOUND_DECAY_OUT_OF_COMBAT_ONLY: bool = false

## Per CombatTags wound id: bleed_hp_per_sec, decay_sec (tag clear), notes.
## tick_interval falls back to TICK_INTERVAL_SEC when omitted / ≤ 0.
const BY_TAG: Dictionary = {
	&"bruise": {
		"bleed_hp_per_sec": 0.0,
		"decay_sec": 20.0,
		"tick_interval": 0.5,
		"notes": "no bleed — tag fades after decay_sec",
	},
	&"cut": {
		"bleed_hp_per_sec": 1.0,
		"decay_sec": 45.0,
		"tick_interval": 0.5,
		"notes": "edge bleed — links CombatTags cut → table rate",
	},
	&"deep": {
		"bleed_hp_per_sec": 2.5,
		"decay_sec": 70.0,
		"tick_interval": 0.5,
		"notes": "heavy bleed — links CombatTags deep → table rate",
	},
}


static func has_tag(tag: StringName) -> bool:
	return BY_TAG.has(tag)


static func entry(tag: StringName) -> Dictionary:
	if not BY_TAG.has(tag):
		return {}
	var e: Dictionary = BY_TAG[tag]
	var tick := float(e.get("tick_interval", TICK_INTERVAL_SEC))
	if tick <= 0.0:
		tick = TICK_INTERVAL_SEC
	return {
		"tag": tag,
		"bleed_hp_per_sec": float(e.get("bleed_hp_per_sec", 0.0)),
		"decay_sec": float(e.get("decay_sec", 0.0)),
		"tick_interval": tick,
		"notes": String(e.get("notes", "")),
	}


static func bleed_hp_per_sec(tag: StringName) -> float:
	return float(entry(tag).get("bleed_hp_per_sec", 0.0))


static func decay_sec(tag: StringName) -> float:
	return float(entry(tag).get("decay_sec", 0.0))


static func tick_interval(tag: StringName = &"") -> float:
	if tag != &"" and BY_TAG.has(tag):
		return float(entry(tag).get("tick_interval", TICK_INTERVAL_SEC))
	return TICK_INTERVAL_SEC


## Sum bleed rates for a list of wound tags (unknown tags contribute 0).
static func total_bleed_hp_per_sec(tags: Array) -> float:
	var total := 0.0
	for item in tags:
		var sn: StringName = item as StringName if typeof(item) == TYPE_STRING_NAME else StringName(str(item))
		total += bleed_hp_per_sec(sn)
	return total


## Shortest positive tick interval among tags; else global default.
static func resolve_tick_interval(tags: Array) -> float:
	var best := TICK_INTERVAL_SEC
	var found := false
	for item in tags:
		var sn: StringName = item as StringName if typeof(item) == TYPE_STRING_NAME else StringName(str(item))
		var e := entry(sn)
		if e.is_empty():
			continue
		var t := float(e.get("tick_interval", TICK_INTERVAL_SEC))
		if t <= 0.0:
			continue
		if not found or t < best:
			best = t
			found = true
	return best


static func soft_wound_decay_sec() -> float:
	return SOFT_WOUND_DECAY_SEC


static func soft_wound_decay_out_of_combat_only() -> bool:
	return SOFT_WOUND_DECAY_OUT_OF_COMBAT_ONLY


static func to_debug_dict() -> Dictionary:
	var by_tag: Dictionary = {}
	for k in BY_TAG.keys():
		by_tag[String(k)] = entry(k)
	return {
		"tick_interval_sec": TICK_INTERVAL_SEC,
		"soft_wound_decay_sec": SOFT_WOUND_DECAY_SEC,
		"soft_wound_decay_out_of_combat_only": SOFT_WOUND_DECAY_OUT_OF_COMBAT_ONLY,
		"soft_wound_rule": (
			"−1 wound every %.0fs ALWAYS while wounds>0 (stub; OOC gate off)"
			% SOFT_WOUND_DECAY_SEC
			if not SOFT_WOUND_DECAY_OUT_OF_COMBAT_ONLY
			else "−1 wound every %.0fs only when out of combat" % SOFT_WOUND_DECAY_SEC
		),
		"by_tag": by_tag,
	}


static func get_debug_text(
	active_tags: Array = [],
	wounds: int = -1,
	bleed_accum: float = -1.0,
	soft_accum: float = -1.0,
) -> String:
	var d := to_debug_dict()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== WoundDecayTable (bleed / soft decay) ===")
	lines.append(
		"tick=%.2fs  soft_counter −1 / %.0fs  ooc_only=%s" % [
			float(d["tick_interval_sec"]),
			float(d["soft_wound_decay_sec"]),
			str(d["soft_wound_decay_out_of_combat_only"]),
		]
	)
	lines.append("rule: %s" % str(d["soft_wound_rule"]))
	lines.append("tag: bleed while present; after decay_sec tag clears (counter separate)")
	lines.append("by tag:")
	for k in [&"bruise", &"cut", &"deep"]:
		var e := entry(k)
		if e.is_empty():
			continue
		lines.append(
			"  %-8s bleed=%.2f hp/s  decay=%.0fs  tick=%.2fs  — %s" % [
				String(k),
				float(e["bleed_hp_per_sec"]),
				float(e["decay_sec"]),
				float(e["tick_interval"]),
				String(e["notes"]),
			]
		)
	if active_tags.size() > 0 or wounds >= 0:
		var names: PackedStringArray = PackedStringArray()
		for t in active_tags:
			names.append(String(t))
		var bleed_rate := total_bleed_hp_per_sec(active_tags)
		var live := "tags=[%s] bleed_rate=%.2f hp/s" % [", ".join(names), bleed_rate]
		if wounds >= 0:
			live += "  wounds=%d" % wounds
		if bleed_accum >= 0.0:
			live += "  bleed_accum=%.2f" % bleed_accum
		if soft_accum >= 0.0:
			live += "  soft_accum=%.1f" % soft_accum
		lines.append("live: %s" % live)
	else:
		lines.append("live: (no session probe)")
	lines.append("F5 probe: press F10 — wound decay dump (see systems/combat/README.md)")
	return "\n".join(lines)
