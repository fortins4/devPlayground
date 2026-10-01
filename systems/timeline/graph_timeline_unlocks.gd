class_name GraphTimelineUnlocks
extends RefCounted
## Thresholded unlock / gate registry: relationship-graph conditions → timeline
## event ids + living-history content flags.
##
## Directors query via Factions (live graph) or evaluate_registry(edges) with a
## snapshot. Data hooks only — no scene loads, no WorldClock resolve side effects.
##
## Complements: Factions relationship graph · WorldClock EventOutcome stubs.
## Design: systems/timeline/README.md · systems/factions/README.md.

## effect: conditions met → targets become available to directors.
const EFFECT_UNLOCK: StringName = &"unlock"
## effect: conditions met → targets are blocked even if another row unlocks them.
const EFFECT_GATE: StringName = &"gate"

const OP_GTE: StringName = &"gte"
const OP_LTE: StringName = &"lte"
const OP_ABS_GTE: StringName = &"abs_gte"

## Authored registry. Schema per row:
##   id, display_name, effect (unlock|gate), require_all (AND), summary,
##   conditions: [{from, to, kind, op, strength, bidirectional}],
##   timeline_event_ids: Array[StringName],
##   content_flags: Array[StringName]
##
## Seed strengths in Factions._seed_relationship_graph are the reference:
## alliance ui→anglo 55, obligation anglo→ui 45, hostility anglo↔norse_ww 70/65,
## hostility high→anglo 45, kinship/trade dublin↔ww 40/35.
const REGISTRY: Array[Dictionary] = [
	{
		"id": &"unlock_port_pressure",
		"display_name": "Port-pressure content",
		"effect": EFFECT_UNLOCK,
		"require_all": true,
		"summary": (
			"Norman ↔ Norse Wexford/Waterford hostility high enough to surface "
			+ "port-struggle living-history stubs."
		),
		"conditions": [
			{
				"from": &"anglo_normans",
				"to": &"norse_wexford_waterford",
				"kind": &"hostility",
				"op": OP_GTE,
				"strength": 60.0,
				"bidirectional": true,
			},
		],
		"timeline_event_ids": [&"wexford_waterford_struggle"],
		"content_flags": [&"port_raid_hooks", &"harbor_struggle_briefings"],
	},
	{
		"id": &"unlock_dynastic_seal",
		"display_name": "Dynastic seal path",
		"effect": EFFECT_UNLOCK,
		"require_all": true,
		"summary": (
			"Diarmait–Norman alliance + landing obligation open Aífe/Strongbow "
			+ "marriage stubs and dynastic content flags."
		),
		"conditions": [
			{
				"from": &"ui_chennselaig",
				"to": &"anglo_normans",
				"kind": &"alliance",
				"op": OP_GTE,
				"strength": 50.0,
				"bidirectional": true,
			},
			{
				"from": &"anglo_normans",
				"to": &"ui_chennselaig",
				"kind": &"obligation",
				"op": OP_GTE,
				"strength": 40.0,
				"bidirectional": false,
			},
		],
		"timeline_event_ids": [&"aife_strongbow_marriage"],
		"content_flags": [&"dynastic_marriage_path", &"strongbow_host_muster"],
	},
	{
		"id": &"unlock_dublin_road",
		"display_name": "Dublin approaches road",
		"effect": EFFECT_UNLOCK,
		"require_all": true,
		"summary": (
			"High Kingship hostility toward Anglo-Normans past threshold unlocks "
			+ "Dublin approaches/siege content stubs (event ids + flags). "
			+ "Seed hostility is 45 — needs a diplomatic swing to open."
		),
		"conditions": [
			{
				"from": &"high_kingship",
				"to": &"anglo_normans",
				"kind": &"hostility",
				"op": OP_GTE,
				"strength": 55.0,
				"bidirectional": false,
			},
		],
		"timeline_event_ids": [&"dublin_approaches", &"dublin_siege"],
		"content_flags": [&"dublin_road_intel", &"ath_cliath_pressure"],
	},
	{
		"id": &"unlock_norse_coast_word",
		"display_name": "Norse coast word",
		"effect": EFFECT_UNLOCK,
		"require_all": false,
		"summary": (
			"Kinship or trade between Dublin and Wexford/Waterford opens coastal "
			+ "intelligence content flags (OR of conditions)."
		),
		"conditions": [
			{
				"from": &"norse_dublin",
				"to": &"norse_wexford_waterford",
				"kind": &"kinship",
				"op": OP_GTE,
				"strength": 35.0,
				"bidirectional": true,
			},
			{
				"from": &"norse_wexford_waterford",
				"to": &"norse_dublin",
				"kind": &"trade",
				"op": OP_GTE,
				"strength": 30.0,
				"bidirectional": true,
			},
		],
		"timeline_event_ids": [],
		"content_flags": [&"norse_coast_intelligence", &"east_coast_trade_word"],
	},
	{
		"id": &"gate_marriage_if_alliance_cold",
		"display_name": "Cold alliance marriage gate",
		"effect": EFFECT_GATE,
		"require_all": true,
		"summary": (
			"When Diarmait–Norman alliance falls cold, gate marriage timeline "
			+ "stubs even if unlock_dynastic_seal would otherwise open them."
		),
		"conditions": [
			{
				"from": &"ui_chennselaig",
				"to": &"anglo_normans",
				"kind": &"alliance",
				"op": OP_LTE,
				"strength": 25.0,
				"bidirectional": true,
			},
		],
		"timeline_event_ids": [&"aife_strongbow_marriage"],
		"content_flags": [&"dynastic_marriage_path"],
	},
	{
		"id": &"unlock_bannow_foothold_word",
		"display_name": "Bannow foothold word",
		"effect": EFFECT_UNLOCK,
		"require_all": true,
		"summary": (
			"Landing-obligation strength keeps Bannow living-history briefings "
			+ "available as content flags (event already calendar-seeded)."
		),
		"conditions": [
			{
				"from": &"anglo_normans",
				"to": &"ui_chennselaig",
				"kind": &"obligation",
				"op": OP_GTE,
				"strength": 35.0,
				"bidirectional": false,
			},
		],
		"timeline_event_ids": [&"bannow_bay_landing"],
		"content_flags": [&"bannow_foothold_briefings"],
	},
]


static func list_registry() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in REGISTRY:
		out.append(row.duplicate(true))
	return out


static func get_registry_row(unlock_id: StringName) -> Dictionary:
	for row in REGISTRY:
		if row.get("id", &"") == unlock_id:
			return row.duplicate(true)
	return {}


static func registry_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in REGISTRY:
		out.append(row.get("id", &"") as StringName)
	return out


## Evaluate one condition against an edges snapshot (Factions.relationship_edges style).
static func condition_met(condition: Dictionary, edges: Array) -> bool:
	var from_id: StringName = condition.get("from", &"")
	var to_id: StringName = condition.get("to", &"")
	var kind: StringName = condition.get("kind", &"")
	var op: StringName = condition.get("op", OP_GTE)
	var threshold := float(condition.get("strength", 0.0))
	var bidirectional := bool(condition.get("bidirectional", false))
	var strength := _best_edge_strength(edges, from_id, to_id, kind, bidirectional)
	# Missing edge → strength 0.0 for gte/abs; for lte a missing edge counts as 0.
	match op:
		OP_LTE:
			return strength <= threshold
		OP_ABS_GTE:
			return absf(strength) >= threshold
		_:
			return strength >= threshold


static func _best_edge_strength(
	edges: Array,
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	bidirectional: bool
) -> float:
	var best := 0.0
	var found := false
	for edge in edges:
		if typeof(edge) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = edge
		var fr: StringName = e.get("from", &"")
		var to: StringName = e.get("to", &"")
		var k: StringName = e.get("kind", &"")
		if kind != &"" and k != kind:
			continue
		var match_fwd := fr == from_id and to == to_id
		var match_rev := bidirectional and fr == to_id and to == from_id
		if not match_fwd and not match_rev:
			continue
		var s := float(e.get("strength", 0.0))
		if not found or absf(s) > absf(best):
			best = s
			found = true
	return best if found else 0.0


static func row_conditions_met(row: Dictionary, edges: Array) -> bool:
	var conditions: Array = row.get("conditions", [])
	if conditions.is_empty():
		return true
	var require_all := bool(row.get("require_all", true))
	if require_all:
		for cond in conditions:
			if typeof(cond) != TYPE_DICTIONARY:
				return false
			if not condition_met(cond, edges):
				return false
		return true
	for cond in conditions:
		if typeof(cond) == TYPE_DICTIONARY and condition_met(cond, edges):
			return true
	return false


## Full evaluation report for directors / probes.
## Returns:
##   open_unlocks, active_gates (row dicts with met=true),
##   unlocked_event_ids, gated_event_ids, available_event_ids,
##   unlocked_content_flags, gated_content_flags, available_content_flags,
##   by_id (id → {met, effect, ...})
static func evaluate_registry(edges: Array) -> Dictionary:
	var open_unlocks: Array[Dictionary] = []
	var active_gates: Array[Dictionary] = []
	var unlocked_events: Dictionary = {}
	var gated_events: Dictionary = {}
	var unlocked_flags: Dictionary = {}
	var gated_flags: Dictionary = {}
	var by_id: Dictionary = {}

	for row in REGISTRY:
		var met := row_conditions_met(row, edges)
		var effect: StringName = row.get("effect", EFFECT_UNLOCK)
		var entry := row.duplicate(true)
		entry["met"] = met
		by_id[String(row.get("id", &""))] = {
			"met": met,
			"effect": effect,
			"display_name": row.get("display_name", ""),
		}
		if not met:
			continue
		if effect == EFFECT_GATE:
			active_gates.append(entry)
			_accumulate_targets(entry, gated_events, gated_flags)
		else:
			open_unlocks.append(entry)
			_accumulate_targets(entry, unlocked_events, unlocked_flags)

	var available_events: Array[StringName] = []
	for eid in unlocked_events.keys():
		if not gated_events.has(eid):
			available_events.append(StringName(eid))
	available_events.sort_custom(func(a, b): return String(a) < String(b))

	var available_flags: Array[StringName] = []
	for fid in unlocked_flags.keys():
		if not gated_flags.has(fid):
			available_flags.append(StringName(fid))
	available_flags.sort_custom(func(a, b): return String(a) < String(b))

	return {
		"open_unlocks": open_unlocks,
		"active_gates": active_gates,
		"unlocked_event_ids": _dict_keys_sorted(unlocked_events),
		"gated_event_ids": _dict_keys_sorted(gated_events),
		"available_event_ids": available_events,
		"unlocked_content_flags": _dict_keys_sorted(unlocked_flags),
		"gated_content_flags": _dict_keys_sorted(gated_flags),
		"available_content_flags": available_flags,
		"by_id": by_id,
		"edge_count": edges.size(),
		"registry_count": REGISTRY.size(),
	}


static func _accumulate_targets(row: Dictionary, events: Dictionary, flags: Dictionary) -> void:
	for eid in row.get("timeline_event_ids", []):
		events[String(eid)] = true
	for fid in row.get("content_flags", []):
		flags[String(fid)] = true


static func _dict_keys_sorted(d: Dictionary) -> Array[StringName]:
	var keys: Array[StringName] = []
	for k in d.keys():
		keys.append(StringName(k))
	keys.sort_custom(func(a, b): return String(a) < String(b))
	return keys


static func is_unlock_open(unlock_id: StringName, edges: Array) -> bool:
	var row := get_registry_row(unlock_id)
	if row.is_empty():
		return false
	if row.get("effect", EFFECT_UNLOCK) == EFFECT_GATE:
		return false
	return row_conditions_met(row, edges)


static func is_gate_active(unlock_id: StringName, edges: Array) -> bool:
	var row := get_registry_row(unlock_id)
	if row.is_empty():
		return false
	if row.get("effect", EFFECT_UNLOCK) != EFFECT_GATE:
		return false
	return row_conditions_met(row, edges)


static func is_timeline_event_available(event_id: StringName, edges: Array) -> bool:
	var report := evaluate_registry(edges)
	var available: Array = report.get("available_event_ids", [])
	return event_id in available


static func is_content_flag_available(flag: StringName, edges: Array) -> bool:
	var report := evaluate_registry(edges)
	var available: Array = report.get("available_content_flags", [])
	return flag in available


static func list_open_unlocks(edges: Array) -> Array[Dictionary]:
	var report := evaluate_registry(edges)
	var out: Array[Dictionary] = []
	for row in report.get("open_unlocks", []):
		out.append(row)
	return out


static func list_available_timeline_events(edges: Array) -> Array[StringName]:
	var report := evaluate_registry(edges)
	var out: Array[StringName] = []
	for eid in report.get("available_event_ids", []):
		out.append(eid as StringName)
	return out


static func list_available_content_flags(edges: Array) -> Array[StringName]:
	var report := evaluate_registry(edges)
	var out: Array[StringName] = []
	for fid in report.get("available_content_flags", []):
		out.append(fid as StringName)
	return out


static func to_debug_dict(edges: Array) -> Dictionary:
	return evaluate_registry(edges)


static func get_debug_text(edges: Array) -> String:
	var report := evaluate_registry(edges)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Graph→timeline unlocks:")
	lines.append(
		"  open=%d gate=%d events=%s flags=%s" % [
			(report.get("open_unlocks", []) as Array).size(),
			(report.get("active_gates", []) as Array).size(),
			str(report.get("available_event_ids", [])),
			str(report.get("available_content_flags", [])),
		]
	)
	var by_id: Dictionary = report.get("by_id", {})
	for unlock_id in registry_ids():
		var info: Dictionary = by_id.get(String(unlock_id), {})
		var met := bool(info.get("met", false))
		var effect: StringName = info.get("effect", EFFECT_UNLOCK)
		var mark := "Y" if met else "n"
		lines.append(
			"  [%s] %s (%s) — %s" % [
				mark,
				String(unlock_id),
				String(effect),
				str(info.get("display_name", "")),
			]
		)
	return "\n".join(lines)
