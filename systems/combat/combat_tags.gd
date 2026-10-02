class_name CombatTags
extends RefCounted
## Stagger / wound tag catalog — greybox combat-support data surface.
##
## Named tags hits can apply (alongside CharacterHealth's integer wound counter).
## Feel (anims, hitstop, telegraph cancel) stays Godot-owned — this file is
## DATA + lookup helpers. CombatSystem wires a small apply path on hatchet hit;
## knife/goad get simple defaults.
##
## Bleed / decay rates live in WoundDecayTable (cut/deep bleed; bruise=0).
## Out of scope here: full injury/limb sim, permanent scars, medical minigame.

## Short CC / interrupt tags (duration + optional interrupt_strength).
const STAGGER: Dictionary = {
	&"stagger_light": {
		"duration_sec": 0.35,
		"interrupt_strength": 1,
		"notes": "tap / jab interrupt — brief recover hitch",
	},
	&"stagger_heavy": {
		"duration_sec": 0.75,
		"interrupt_strength": 2,
		"notes": "charged / max interrupt — longer recover hitch",
	},
}

## Soft wound flavour tags. wound_delta feeds CharacterHealth.add_wound (0 = tag only).
const WOUND: Dictionary = {
	&"bruise": {
		"wound_delta": 0,
		"notes": "blunt / glancing — tag only; WoundDecayTable bleed=0, decays ~20s",
	},
	&"cut": {
		"wound_delta": 1,
		"notes": "edge bite — +1 soft wound; bleed from WoundDecayTable (cut)",
	},
	&"deep": {
		"wound_delta": 2,
		"notes": "charged overhead / heavy bite — +2 soft wounds; bleed from WoundDecayTable (deep)",
	},
}

## Hatchet direction × charge tier → default tags on successful hit (data only).
## tap → bruise + stagger_light; charged/max top → deep + stagger_heavy;
## charged/max sides → cut + stagger_heavy.
const HATCHET_HIT_TAGS: Dictionary = {
	&"top": {
		&"tap": [&"bruise", &"stagger_light"],
		&"charged": [&"deep", &"stagger_heavy"],
		&"max": [&"deep", &"stagger_heavy"],
	},
	&"left": {
		&"tap": [&"bruise", &"stagger_light"],
		&"charged": [&"cut", &"stagger_heavy"],
		&"max": [&"cut", &"stagger_heavy"],
	},
	&"right": {
		&"tap": [&"bruise", &"stagger_light"],
		&"charged": [&"cut", &"stagger_heavy"],
		&"max": [&"cut", &"stagger_heavy"],
	},
}

## Knife / goad simple defaults (kind light|heavy). Empty = skip.
const WEAPON_HIT_TAGS: Dictionary = {
	&"knife": {
		&"light": [&"cut", &"stagger_light"],
		&"heavy": [&"cut", &"stagger_light"],
	},
	&"goad": {
		&"light": [&"bruise", &"stagger_light"],
		&"heavy": [&"bruise", &"stagger_heavy"],
	},
}


static func is_stagger(tag: StringName) -> bool:
	return STAGGER.has(tag)


static func is_wound(tag: StringName) -> bool:
	return WOUND.has(tag)


static func stagger_entry(tag: StringName) -> Dictionary:
	if not STAGGER.has(tag):
		return {}
	var e: Dictionary = STAGGER[tag]
	return {
		"tag": tag,
		"kind": &"stagger",
		"duration_sec": float(e.get("duration_sec", 0.35)),
		"interrupt_strength": int(e.get("interrupt_strength", 1)),
		"notes": String(e.get("notes", "")),
	}


static func wound_entry(tag: StringName) -> Dictionary:
	if not WOUND.has(tag):
		return {}
	var e: Dictionary = WOUND[tag]
	var out := {
		"tag": tag,
		"kind": &"wound",
		"wound_delta": int(e.get("wound_delta", 0)),
		"notes": String(e.get("notes", "")),
	}
	# Optional link to WoundDecayTable bleed / decay (do not retune here).
	var decay: Dictionary = WoundDecayTable.entry(tag)
	if not decay.is_empty():
		out["bleed_hp_per_sec"] = float(decay.get("bleed_hp_per_sec", 0.0))
		out["decay_sec"] = float(decay.get("decay_sec", 0.0))
	return out


static func entry(tag: StringName) -> Dictionary:
	if is_stagger(tag):
		return stagger_entry(tag)
	if is_wound(tag):
		return wound_entry(tag)
	return {}


static func duration_sec(tag: StringName) -> float:
	return float(stagger_entry(tag).get("duration_sec", 0.0))


static func interrupt_strength(tag: StringName) -> int:
	return int(stagger_entry(tag).get("interrupt_strength", 0))


static func wound_delta(tag: StringName) -> int:
	return int(wound_entry(tag).get("wound_delta", 0))


## Resolve default tags for a weapon hit. Hatchet uses direction×tier; others use kind.
static func tags_for_hit(
	weapon: StringName,
	kind: StringName = &"light",
	direction: StringName = &"",
	tier: StringName = &"",
) -> Array[StringName]:
	var out: Array[StringName] = []
	if weapon == &"hatchet":
		var d := direction if direction != &"" else HatchetAttackTable.DEFAULT_DIRECTION
		var t := tier if tier != &"" else HatchetAttackTable.tier_from_kind(kind)
		d = HatchetAttackTable.normalize_direction(d)
		t = HatchetAttackTable.normalize_tier(t)
		var row: Dictionary = HATCHET_HIT_TAGS.get(d, HATCHET_HIT_TAGS[&"top"])
		var cell: Variant = row.get(t, row.get(&"tap", []))
		_append_tag_names(out, cell)
		return out
	var kit: Dictionary = WEAPON_HIT_TAGS.get(weapon, {})
	if kit.is_empty():
		return out
	var k := kind
	if k != &"light" and k != &"heavy":
		k = HatchetAttackTable.kind_from_tier(k)
	var cell2: Variant = kit.get(k, kit.get(&"light", []))
	_append_tag_names(out, cell2)
	return out


static func hatchet_tags(direction: StringName, tier: StringName) -> Array[StringName]:
	return tags_for_hit(&"hatchet", &"light", direction, tier)


static func _append_tag_names(out: Array[StringName], cell: Variant) -> void:
	if cell is Array:
		for item in cell:
			var sn: StringName
			if typeof(item) == TYPE_STRING_NAME:
				sn = item
			else:
				sn = StringName(str(item))
			if sn != &"" and not out.has(sn):
				out.append(sn)


static func to_debug_dict() -> Dictionary:
	var stagger_out: Dictionary = {}
	for k in STAGGER.keys():
		stagger_out[String(k)] = stagger_entry(k)
	var wound_out: Dictionary = {}
	for k in WOUND.keys():
		wound_out[String(k)] = wound_entry(k)
	var hatchet_out: Dictionary = {}
	for d in HATCHET_HIT_TAGS.keys():
		var row_out: Dictionary = {}
		var row: Dictionary = HATCHET_HIT_TAGS[d]
		for t in row.keys():
			var names: PackedStringArray = PackedStringArray()
			for tag in row[t]:
				names.append(String(tag))
			row_out[String(t)] = names
		hatchet_out[String(d)] = row_out
	return {
		"stagger": stagger_out,
		"wound": wound_out,
		"hatchet_hit_tags": hatchet_out,
		"weapon_hit_tags": WEAPON_HIT_TAGS.duplicate(true),
	}


static func get_debug_text(
	last_tags: Array = [],
	last_weapon: StringName = &"",
	last_direction: StringName = &"",
	last_tier: StringName = &"",
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== CombatTags (stagger / wound) ===")
	lines.append("stagger:")
	for k in STAGGER.keys():
		var e := stagger_entry(k)
		lines.append(
			"  %-14s dur=%.2fs  interrupt=%d  — %s" % [
				String(k), float(e["duration_sec"]), int(e["interrupt_strength"]), String(e["notes"]),
			]
		)
	lines.append("wound:")
	for k in WOUND.keys():
		var w := wound_entry(k)
		var bleed := float(w.get("bleed_hp_per_sec", 0.0))
		var dsec := float(w.get("decay_sec", 0.0))
		lines.append(
			"  %-14s delta=%+d  bleed=%.2f hp/s  decay=%.0fs  — %s" % [
				String(k), int(w["wound_delta"]), bleed, dsec, String(w["notes"]),
			]
		)
	lines.append("hatchet dir×tier → tags:")
	for d in [&"top", &"left", &"right"]:
		var row: Dictionary = HATCHET_HIT_TAGS.get(d, {})
		for t in [&"tap", &"charged", &"max"]:
			var tags: Array = row.get(t, [])
			var names: PackedStringArray = PackedStringArray()
			for tag in tags:
				names.append(String(tag))
			lines.append("  %-6s %-8s  %s" % [String(d), String(t), ", ".join(names)])
	if last_tags.size() > 0 or last_weapon != &"":
		var applied: PackedStringArray = PackedStringArray()
		for tag in last_tags:
			applied.append(String(tag))
		lines.append(
			"last applied: weapon=%s dir=%s tier=%s tags=[%s]" % [
				String(last_weapon), String(last_direction), String(last_tier), ", ".join(applied),
			]
		)
	else:
		lines.append("last applied: (none yet)")
	lines.append("F5 probe: press F7 — combat tags dump (see systems/combat/README.md)")
	return "\n".join(lines)
