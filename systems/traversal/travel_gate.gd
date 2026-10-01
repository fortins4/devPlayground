class_name TravelGate
extends RefCounted
## Travel gate stub: origin → destination day cost → WorldClock commit.
##
## Data: TravelDistances. Calendar: WorldClock.advance_day. Region: Game.current_region.
## No scene loads — callers (or the debug HUD) handle greybox swaps later.
##
## Gate reasons (preview / commit fail closed):
##   same_region       — origin == destination
##   unknown_region    — id not in TravelDistances.REGION_IDS
##   blocked_edge      — direct_edges_only and no stub edge
##   unreachable       — no path on the region graph
##   insufficient_days — expedition_day_budget >= 0 and days exceed it
##   missing_clock     — WorldClock autoload unavailable on commit
##   missing_game      — Game autoload unavailable on commit

## Soft expedition budget in calendar days. -1 = unlimited (slice default).
## When >= 0, preview/commit fail closed with insufficient_days if trip cost exceeds it;
## a successful commit spends the trip days from the budget (remaining = budget - days).
## Supplies / band logistics can tighten this later.
static var expedition_day_budget: int = -1

## When true, only direct TravelDistances edges (no multi-hop path).
static var direct_edges_only: bool = false

## Last preview or commit payload (debug / Remote).
static var last_result: Dictionary = {}

## HUD poll flag (mirrors WorldClock / Honor / Rumors).
static var debug_visible: bool = false


## Set expedition day budget. days < 0 → unlimited (-1).
static func set_expedition_day_budget(days: int) -> void:
	expedition_day_budget = -1 if days < 0 else maxi(0, days)


## Clear budget back to unlimited.
static func clear_expedition_day_budget() -> void:
	expedition_day_budget = -1


## Adjust budget by delta. Leaving unlimited: start at 0 then apply delta (clamped >= 0).
## Returns the new budget value (-1 only if still unlimited — clear via clear_expedition_day_budget).
static func adjust_expedition_day_budget(delta: int) -> int:
	if expedition_day_budget < 0:
		expedition_day_budget = maxi(0, delta)
	else:
		expedition_day_budget = maxi(0, expedition_day_budget + delta)
	return expedition_day_budget


## Snapshot budget vs an optional planned trip cost (days). planned_days < 0 → no trip compared.
## Keys: budget, unlimited, planned_days, remaining_after, spare_days, insufficient_days, summary.
static func get_expedition_budget_status(planned_days: int = -1) -> Dictionary:
	var unlimited := expedition_day_budget < 0
	var insufficient := (not unlimited) and planned_days >= 0 and planned_days > expedition_day_budget
	var remaining_after := -1
	var spare := -1
	if not unlimited and planned_days >= 0:
		remaining_after = expedition_day_budget - planned_days
		spare = maxi(0, remaining_after)
	var summary := ""
	if unlimited:
		summary = "Budget unlimited" if planned_days < 0 else "Budget unlimited · planned %d d" % planned_days
	elif planned_days < 0:
		summary = "Budget remaining: %d d" % expedition_day_budget
	elif insufficient:
		summary = "INSUFFICIENT: need %d d, budget %d d (short %d)" % [
			planned_days, expedition_day_budget, planned_days - expedition_day_budget,
		]
	else:
		summary = "OK: planned %d d · remaining after %d d" % [planned_days, remaining_after]
	return {
		"budget": expedition_day_budget,
		"unlimited": unlimited,
		"planned_days": planned_days,
		"remaining_after": remaining_after,
		"spare_days": spare,
		"insufficient_days": insufficient,
		"summary": summary,
	}


## Preview a trip without advancing the clock or changing region.
## allow_path=false forces a direct-edge check (same as direct_edges_only).
static func preview_travel(
	from_region: StringName,
	to_region: StringName,
	mode: StringName = &"horse",
	allow_path: bool = true
) -> Dictionary:
	var payload := _evaluate(from_region, to_region, mode, allow_path)
	last_result = payload.duplicate(true)
	return payload


## Request from the live session region (Game.current_region → destination).
static func request_travel(
	to_region: StringName,
	mode: StringName = &"horse",
	allow_path: bool = true
) -> Dictionary:
	var from_region := _session_region()
	return preview_travel(from_region, to_region, mode, allow_path)


static func can_travel(
	from_region: StringName,
	to_region: StringName,
	mode: StringName = &"horse",
	allow_path: bool = true
) -> bool:
	return bool(_evaluate(from_region, to_region, mode, allow_path).get("ok", false))


## Commit travel: spend TravelDistances days on WorldClock, then set region.
## Days == 0 (same-day embark) still changes region but does not advance the clock.
static func commit_travel(
	to_region: StringName,
	mode: StringName = &"horse",
	from_region: StringName = &"",
	allow_path: bool = true
) -> Dictionary:
	var origin := from_region if from_region != &"" else _session_region()
	var preview := _evaluate(origin, to_region, mode, allow_path)
	if not bool(preview.get("ok", false)):
		last_result = preview.duplicate(true)
		return preview
	if Game == null:
		preview["ok"] = false
		preview["reason"] = &"missing_game"
		preview["summary"] = "Travel commit failed — Game autoload missing."
		last_result = preview.duplicate(true)
		return preview
	if WorldClock == null:
		preview["ok"] = false
		preview["reason"] = &"missing_clock"
		preview["summary"] = "Travel commit failed — WorldClock autoload missing."
		last_result = preview.duplicate(true)
		return preview

	var days := int(preview.get("days", 0))
	var day_before := int(WorldClock.day)
	if days > 0:
		WorldClock.advance_day(days)
	var day_after := int(WorldClock.day)

	Game.set_current_region(to_region)

	var budget_before := expedition_day_budget
	if expedition_day_budget >= 0 and days > 0:
		expedition_day_budget = maxi(0, expedition_day_budget - days)

	var result := preview.duplicate(true)
	result["ok"] = true
	result["committed"] = true
	result["day_before"] = day_before
	result["day_after"] = day_after
	result["days_advanced"] = day_after - day_before
	result["region"] = String(to_region)
	result["budget_before"] = budget_before
	result["budget_remaining"] = expedition_day_budget
	result["summary"] = _commit_summary(origin, to_region, days, mode, day_before, day_after)
	last_result = result.duplicate(true)
	return result


static func list_destinations(
	from_region: StringName = &"",
	mode: StringName = &"horse",
	allow_path: bool = true
) -> Array[Dictionary]:
	var origin := from_region if from_region != &"" else _session_region()
	var out: Array[Dictionary] = []
	if not TravelDistances.is_known_region(origin):
		return out
	for other in TravelDistances.REGION_IDS:
		if other == origin:
			continue
		var preview := _evaluate(origin, other, mode, allow_path)
		out.append({
			"to": other,
			"display_name": TravelDistances.display_name(other),
			"ok": bool(preview.get("ok", false)),
			"reason": preview.get("reason", &""),
			"days": int(preview.get("days", -1)),
			"mode": String(mode),
			"path": preview.get("path", []),
		})
	return out


static func toggle_debug_visible() -> bool:
	debug_visible = not debug_visible
	return debug_visible


static func set_debug_visible(visible: bool) -> void:
	debug_visible = visible


static func to_debug_dict() -> Dictionary:
	var origin := _session_region()
	var dests: Array = []
	for row in list_destinations(origin, &"horse", true):
		dests.append({
			"to": String(row["to"]),
			"ok": row["ok"],
			"days": row["days"],
			"reason": String(row.get("reason", &"")),
		})
	var sample := preview_travel(&"leinster", &"dublin")
	return {
		"current_region": String(origin),
		"expedition_day_budget": expedition_day_budget,
		"budget_status": get_expedition_budget_status(int(sample.get("days", -1))),
		"direct_edges_only": direct_edges_only,
		"world_day": int(WorldClock.day) if WorldClock else -1,
		"destinations_horse": dests,
		"last_result": last_result.duplicate(true),
		"sample_leinster_dublin": sample,
	}


static func get_debug_text() -> String:
	var origin := _session_region()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== TravelGate / region travel ===")
	lines.append("Region: %s (%s)" % [
		String(origin),
		TravelDistances.display_name(origin),
	])
	var day_str := str(WorldClock.day) if WorldClock else "?"
	var budget_label := str(expedition_day_budget) + " d remaining" if expedition_day_budget >= 0 else "unlimited"
	lines.append("WorldClock day: %s   direct_only: %s" % [day_str, str(direct_edges_only)])
	lines.append("Day budget: %s" % budget_label)
	lines.append("Keys: G toggle · J/K dest · F horse/foot · -/= budget · L unlimited · B commit")
	lines.append("Destinations (horse, path allowed):")
	var shown := 0
	for row in list_destinations(origin, &"horse", true):
		if shown >= 8:
			lines.append("  …")
			break
		var mark := "ok" if row["ok"] else String(row.get("reason", &"blocked"))
		lines.append("  → %s  %d d  [%s]" % [
			String(row["to"]),
			int(row["days"]),
			mark,
		])
		shown += 1
	if last_result.is_empty():
		lines.append("Last: (none)")
	else:
		lines.append("Last: ok=%s reason=%s days=%s → %s" % [
			str(last_result.get("ok", false)),
			String(last_result.get("reason", &"")),
			str(last_result.get("days", "?")),
			String(last_result.get("to", last_result.get("region", "?"))),
		])
		if last_result.has("summary"):
			lines.append("  %s" % str(last_result["summary"]))
	return "\n".join(lines)


static func _evaluate(
	from_region: StringName,
	to_region: StringName,
	mode: StringName,
	allow_path: bool
) -> Dictionary:
	var use_path := allow_path and not direct_edges_only
	var base := {
		"ok": false,
		"committed": false,
		"from": String(from_region),
		"to": String(to_region),
		"from_display": TravelDistances.display_name(from_region),
		"to_display": TravelDistances.display_name(to_region),
		"mode": String(mode),
		"days": -1,
		"planned_days": -1,
		"path": [],
		"reason": &"",
		"summary": "",
		"expedition_day_budget": expedition_day_budget,
		"insufficient_days": false,
	}
	if not TravelDistances.is_known_region(from_region) or not TravelDistances.is_known_region(to_region):
		base["reason"] = &"unknown_region"
		base["summary"] = "Unknown region id (see TravelDistances.REGION_IDS)."
		return base
	if from_region == to_region:
		base["reason"] = &"same_region"
		base["days"] = 0
		base["path"] = [from_region]
		base["summary"] = "Already in %s — no travel gate." % TravelDistances.display_name(from_region)
		return base

	if use_path:
		var route: Dictionary = TravelDistances.shortest_path(from_region, to_region, mode)
		if not bool(route.get("ok", false)):
			base["reason"] = route.get("reason", &"unreachable")
			base["summary"] = "No route from %s to %s (%s)." % [
				String(from_region), String(to_region), String(base["reason"]),
			]
			return base
		base["days"] = int(route["days"])
		base["path"] = route.get("path", [])
	else:
		var direct := TravelDistances.travel_days(from_region, to_region, mode)
		if direct < 0:
			base["reason"] = &"blocked_edge"
			base["summary"] = "No direct %s edge %s → %s." % [
				String(mode), String(from_region), String(to_region),
			]
			return base
		base["days"] = direct
		base["path"] = [from_region, to_region]

	var days := int(base["days"])
	base["planned_days"] = days
	var status := get_expedition_budget_status(days)
	base["expedition_day_budget"] = expedition_day_budget
	base["insufficient_days"] = bool(status["insufficient_days"])
	base["budget_remaining_after"] = status["remaining_after"]
	if bool(status["insufficient_days"]):
		base["reason"] = &"insufficient_days"
		base["summary"] = str(status["summary"])
		return base

	base["ok"] = true
	base["reason"] = &"ok"
	base["summary"] = "Ready: %s → %s in %d %s-day(s). %s" % [
		TravelDistances.display_name(from_region),
		TravelDistances.display_name(to_region),
		days,
		String(mode),
		str(status["summary"]),
	]
	return base


static func _session_region() -> StringName:
	if Game:
		return Game.current_region
	return &"leinster"


static func _commit_summary(
	from_region: StringName,
	to_region: StringName,
	days: int,
	mode: StringName,
	day_before: int,
	day_after: int
) -> String:
	if days <= 0:
		return "Same-day embark %s → %s (%s). Clock stays day %d." % [
			TravelDistances.display_name(from_region),
			TravelDistances.display_name(to_region),
			String(mode),
			day_after,
		]
	return "Travelled %s → %s (%d %s-days). Calendar %d → %d." % [
		TravelDistances.display_name(from_region),
		TravelDistances.display_name(to_region),
		days,
		String(mode),
		day_before,
		day_after,
	]
