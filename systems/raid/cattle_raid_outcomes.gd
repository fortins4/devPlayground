class_name CattleRaidOutcomes
extends RefCounted
## Cattle-raid economy outcomes: loot / upkeep / honor heat (data + API).
##
## Godot calls resolve_success / resolve_failure after a raid mission resolves.
## Applies CattleEconomy.gain_cattle (pens-capped), optional goods, band deltas,
## Honor + Factions heat, and returns retaliation hooks as data (no AI).
## Not stealth / bog / watchmen gameplay — those stay in mission scenes.
##
## Ownership: ringfort / Game / CattleEconomy may hold an instance. Prefer
## CattleEconomy.resolve_raid_success() facade when an economy node exists.

signal raid_resolved(outcome: Dictionary)
signal loot_applied(cattle_gained: int, goods: Dictionary)
signal honor_heat_applied(victim_faction: StringName, honor_delta: float, attitude_delta: float)
signal retaliation_queued(hook: Dictionary)

## First N successful raids on a victim stay under the mercy window (softer heat).
const MERCY_SUCCESS_COUNT: int = 2

## Default loot / heat knobs (per-target rows may override).
const DEFAULT_BASE_CATTLE: int = 4
const DEFAULT_CATTLE_VARIANCE: int = 2
const SUCCESS_HONOR_OVERALL: float = -5.0
const SUCCESS_HONOR_VICTIM: float = -8.0
const SUCCESS_ATTITUDE: float = -12.0
const FAIL_HONOR_OVERALL: float = -2.0
const FAIL_HONOR_VICTIM: float = -3.0
const FAIL_ATTITUDE: float = -4.0
const SUCCESS_BAND_MORALE: float = 4.0
const SUCCESS_BAND_READINESS: float = -5.0
const FAIL_BAND_MORALE: float = -6.0
const FAIL_BAND_READINESS: float = -8.0
const FAIL_CATTLE_LOSS_CHANCE_HEADS: int = 1

## Escalation: each success past mercy adds this to attitude / honor magnitude.
const HEAT_ESCALATION_ATTITUDE: float = -4.0
const HEAT_ESCALATION_HONOR: float = -2.0

## Slice raid targets (victim herds / pens). Schema:
##   id, display_name, victim_faction, base_cattle, cattle_variance,
##   goods {goods_id → count}, honor_overall, honor_victim, attitude,
##   retaliation_kind, tags, note
const RAID_TARGETS: Array[Dictionary] = [
	{
		"id": &"local_clan_herd",
		"display_name": "Local túath cattle pens",
		"victim_faction": &"local_clans",
		"base_cattle": 5,
		"cattle_variance": 2,
		"goods": {},
		"honor_overall": -5.0,
		"honor_victim": -8.0,
		"attitude": -14.0,
		"retaliation_kind": &"counter_raid",
		"tags": [&"gaelic", &"pens"],
		"note": "Neighbour feud stock — classic cattle raid.",
	},
	{
		"id": &"ui_chennselaig_drove",
		"display_name": "Uí Chennselaig tribute drove",
		"victim_faction": &"ui_chennselaig",
		"base_cattle": 6,
		"cattle_variance": 2,
		"goods": {},
		"honor_overall": -6.0,
		"honor_victim": -10.0,
		"attitude": -16.0,
		"retaliation_kind": &"tribute_demand",
		"tags": [&"gaelic", &"tribute"],
		"note": "Raiding Diarmait's clients costs political capital.",
	},
	{
		"id": &"norse_coastal_pen",
		"display_name": "Norse coastal trade pens",
		"victim_faction": &"norse_wexford_waterford",
		"base_cattle": 4,
		"cattle_variance": 2,
		"goods": {&"amber": 1},
		"honor_overall": -4.0,
		"honor_victim": -7.0,
		"attitude": -12.0,
		"retaliation_kind": &"patrol_heat",
		"tags": [&"norse", &"harbor"],
		"note": "Harbor pens; may scoop trade goods with the herd.",
	},
	{
		"id": &"anglo_norman_forage",
		"display_name": "Anglo-Norman forage herd",
		"victim_faction": &"anglo_normans",
		"base_cattle": 5,
		"cattle_variance": 3,
		"goods": {},
		"honor_overall": -3.0,
		"honor_victim": -6.0,
		"attitude": -10.0,
		"retaliation_kind": &"patrol_heat",
		"tags": [&"norman", &"beachhead"],
		"note": "Landing forage stock — less Brehon shame, more steel heat.",
	},
	{
		"id": &"fian_camp_stock",
		"display_name": "Fían camp stock",
		"victim_faction": &"fian",
		"base_cattle": 3,
		"cattle_variance": 1,
		"goods": {},
		"honor_overall": -2.0,
		"honor_victim": -4.0,
		"attitude": -8.0,
		"retaliation_kind": &"counter_raid",
		"tags": [&"fian", &"outlaw"],
		"note": "Outlaw herds — lighter honor hit, still invites reprisal.",
	},
]

## Successful raids per victim faction (drives mercy + escalation).
var success_counts: Dictionary = {}
## Last outcome for debug / UI.
var last_outcome: Dictionary = {}


func list_target_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in RAID_TARGETS:
		out.append(row.get("id", &""))
	return out


func list_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in RAID_TARGETS:
		out.append(row.duplicate(true))
	return out


func get_target(target_id: StringName) -> Dictionary:
	for row in RAID_TARGETS:
		if row.get("id", &"") == target_id:
			return row.duplicate(true)
	return {}


func get_success_count(victim_faction: StringName) -> int:
	return int(success_counts.get(victim_faction, 0))


func is_mercy_active(victim_faction: StringName) -> bool:
	return get_success_count(victim_faction) < MERCY_SUCCESS_COUNT


## Preview loot/heat without mutating economy / honor / factions.
func preview_success(
	economy: Object,
	target_id: StringName,
	cattle_override: int = -1
) -> Dictionary:
	return _build_success_plan(economy, target_id, cattle_override, false)


## Resolve a successful cattle raid: loot + upkeep snapshot + honor heat + retaliation data.
func resolve_success(
	economy: Object,
	target_id: StringName,
	cattle_override: int = -1,
	apply_heat: bool = true,
	apply_band: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	var plan := _build_success_plan(economy, target_id, cattle_override, true)
	if not bool(plan.get("ok", false)):
		last_outcome = plan
		raid_resolved.emit(plan)
		return plan

	var victim: StringName = plan.get("victim_faction", &"")
	var cattle_loot := int(plan.get("cattle_loot", 0))
	var goods: Dictionary = plan.get("goods_loot", {})

	# --- Loot via existing CattleEconomy hooks --------------------------------
	var cattle_gained := 0
	if cattle_loot > 0 and economy != null and economy.has_method("gain_cattle"):
		cattle_gained = int(economy.gain_cattle(cattle_loot, &"cattle_raid"))
	var cattle_spilled := maxi(0, cattle_loot - cattle_gained)

	var goods_applied: Dictionary = {}
	if not goods.is_empty() and economy != null:
		goods_applied = _apply_goods(economy, goods)

	if cattle_gained > 0 or not goods_applied.is_empty():
		loot_applied.emit(cattle_gained, goods_applied.duplicate(true))

	# --- Band fatigue / morale after a night out ------------------------------
	var band_morale := 0.0
	var band_readiness := 0.0
	if apply_band:
		band_morale = SUCCESS_BAND_MORALE
		band_readiness = SUCCESS_BAND_READINESS
		_apply_band_deltas(economy, band_morale, band_readiness)

	# --- Honor / attitude heat ------------------------------------------------
	var honor_overall := float(plan.get("honor_delta_overall", 0.0))
	var honor_victim := float(plan.get("honor_delta_victim", 0.0))
	var attitude_delta := float(plan.get("attitude_delta", 0.0))
	if apply_heat:
		_apply_honor_heat(victim, honor_overall, honor_victim, attitude_delta)
		honor_heat_applied.emit(victim, honor_overall + honor_victim * 0.25, attitude_delta)

	# --- Bookkeeping + retaliation hook ---------------------------------------
	var prior_count := get_success_count(victim)
	success_counts[victim] = prior_count + 1
	var raid_count := get_success_count(victim)
	var mercy := prior_count < MERCY_SUCCESS_COUNT
	var retaliation := build_retaliation_hook(
		victim,
		StringName(plan.get("retaliation_kind", &"counter_raid")),
		raid_count,
		cattle_gained,
		mercy
	)
	retaliation_queued.emit(retaliation.duplicate(true))

	if spawn_rumor:
		_spawn_raid_rumor(true, victim, cattle_gained, mercy)

	var upkeep := _upkeep_snapshot(economy)
	var outcome := {
		"ok": true,
		"success": true,
		"reason": &"ok",
		"target_id": plan.get("target_id", target_id),
		"display_name": plan.get("display_name", ""),
		"victim_faction": victim,
		"cattle_loot": cattle_loot,
		"cattle_gained": cattle_gained,
		"cattle_spilled": cattle_spilled,
		"goods_loot": goods.duplicate(true),
		"goods_gained": goods_applied,
		"honor_delta_overall": honor_overall if apply_heat else 0.0,
		"honor_delta_victim": honor_victim if apply_heat else 0.0,
		"attitude_delta": attitude_delta if apply_heat else 0.0,
		"band_morale_delta": band_morale if apply_band else 0.0,
		"band_readiness_delta": band_readiness if apply_band else 0.0,
		"upkeep": upkeep,
		"retaliation": retaliation,
		"mercy_active": mercy,
		"raid_count_on_victim": raid_count,
		"day": _day_stamp(),
		"heat_applied": apply_heat,
		"band_applied": apply_band,
	}
	last_outcome = outcome.duplicate(true)
	raid_resolved.emit(outcome)
	return outcome


## Resolve a failed cattle raid: optional cattle loss, band hit, lighter heat.
func resolve_failure(
	economy: Object,
	target_id: StringName,
	cattle_lost_override: int = -1,
	apply_heat: bool = true,
	apply_band: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	var target := get_target(target_id)
	if target.is_empty():
		var denied := {
			"ok": false,
			"success": false,
			"reason": &"unknown_target",
			"target_id": target_id,
		}
		last_outcome = denied
		raid_resolved.emit(denied)
		return denied

	var victim: StringName = target.get("victim_faction", &"")
	var lose_n := cattle_lost_override
	if lose_n < 0:
		lose_n = FAIL_CATTLE_LOSS_CHANCE_HEADS

	var cattle_lost := 0
	if lose_n > 0 and economy != null and economy.has_method("lose_cattle"):
		cattle_lost = int(economy.lose_cattle(lose_n, &"cattle_raid_failed"))

	var band_morale := 0.0
	var band_readiness := 0.0
	if apply_band:
		band_morale = FAIL_BAND_MORALE
		band_readiness = FAIL_BAND_READINESS
		_apply_band_deltas(economy, band_morale, band_readiness)

	var honor_overall := FAIL_HONOR_OVERALL
	var honor_victim := FAIL_HONOR_VICTIM
	var attitude_delta := FAIL_ATTITUDE
	# Failed raids do not escalate success_counts; still a whisper of heat.
	if apply_heat:
		_apply_honor_heat(victim, honor_overall, honor_victim, attitude_delta)
		honor_heat_applied.emit(victim, honor_overall + honor_victim * 0.25, attitude_delta)

	var mercy := is_mercy_active(victim)
	var retaliation := build_retaliation_hook(
		victim,
		StringName(target.get("retaliation_kind", &"patrol_heat")),
		get_success_count(victim),
		0,
		true  # failures keep delay long (mercy-style)
	)
	# Soften failure retaliation: longer delay, lower severity.
	retaliation["severity"] = clampf(float(retaliation.get("severity", 0.2)) * 0.5, 0.0, 1.0)
	retaliation["delay_days"] = int(retaliation.get("delay_days", 5)) + 2
	retaliation["kind"] = &"patrol_heat"
	retaliation["note"] = "Failed raid — patrol word spreads; delayed soft heat."
	retaliation_queued.emit(retaliation.duplicate(true))

	if spawn_rumor:
		_spawn_raid_rumor(false, victim, cattle_lost, mercy)

	var outcome := {
		"ok": true,
		"success": false,
		"reason": &"raid_failed",
		"target_id": target_id,
		"display_name": String(target.get("display_name", "")),
		"victim_faction": victim,
		"cattle_loot": 0,
		"cattle_gained": 0,
		"cattle_spilled": 0,
		"cattle_lost": cattle_lost,
		"goods_loot": {},
		"goods_gained": {},
		"honor_delta_overall": honor_overall if apply_heat else 0.0,
		"honor_delta_victim": honor_victim if apply_heat else 0.0,
		"attitude_delta": attitude_delta if apply_heat else 0.0,
		"band_morale_delta": band_morale if apply_band else 0.0,
		"band_readiness_delta": band_readiness if apply_band else 0.0,
		"upkeep": _upkeep_snapshot(economy),
		"retaliation": retaliation,
		"mercy_active": mercy,
		"raid_count_on_victim": get_success_count(victim),
		"day": _day_stamp(),
		"heat_applied": apply_heat,
		"band_applied": apply_band,
	}
	last_outcome = outcome.duplicate(true)
	raid_resolved.emit(outcome)
	return outcome


## Data-only retaliation payload for mission / timeline / faction AI later.
func build_retaliation_hook(
	victim_faction: StringName,
	kind: StringName,
	raid_count: int,
	cattle_taken: int,
	mercy_active: bool
) -> Dictionary:
	var severity := clampf(0.25 + float(maxi(0, raid_count - 1)) * 0.15, 0.0, 1.0)
	var delay := 5
	if mercy_active:
		severity = clampf(severity * 0.45, 0.0, 1.0)
		delay = 8
	elif raid_count >= MERCY_SUCCESS_COUNT + 2:
		delay = 2
		severity = clampf(severity + 0.2, 0.0, 1.0)

	var cattle_at_risk := 0
	if kind == &"counter_raid":
		cattle_at_risk = maxi(2, int(ceil(float(cattle_taken) * 0.5 * severity)))
	elif kind == &"tribute_demand":
		cattle_at_risk = maxi(1, int(ceil(float(maxi(cattle_taken, 3)) * 0.35)))

	return {
		"kind": kind,
		"victim_faction": victim_faction,
		"delay_days": delay,
		"severity": severity,
		"cattle_at_risk": cattle_at_risk,
		"raid_count": raid_count,
		"mercy_active": mercy_active,
		"queued_day": _day_stamp(),
		"note": _retaliation_note(kind, mercy_active),
	}


func reset_heat_tracking() -> void:
	success_counts.clear()
	last_outcome.clear()


func to_debug_dict() -> Dictionary:
	var ids: Array[String] = []
	for id in list_target_ids():
		ids.append(String(id))
	var counts: Dictionary = {}
	for k in success_counts.keys():
		counts[String(k)] = int(success_counts[k])
	return {
		"target_ids": ids,
		"target_count": RAID_TARGETS.size(),
		"mercy_success_count": MERCY_SUCCESS_COUNT,
		"success_counts": counts,
		"last_outcome": last_outcome.duplicate(true),
	}


# --- Internals ----------------------------------------------------------------

func _build_success_plan(
	economy: Object,
	target_id: StringName,
	cattle_override: int,
	_for_apply: bool
) -> Dictionary:
	var target := get_target(target_id)
	if target.is_empty():
		return {
			"ok": false,
			"success": true,
			"reason": &"unknown_target",
			"target_id": target_id,
		}

	var victim: StringName = target.get("victim_faction", &"")
	var prior := get_success_count(victim)
	var mercy := prior < MERCY_SUCCESS_COUNT
	var escalations := maxi(0, prior - MERCY_SUCCESS_COUNT + 1) if prior >= MERCY_SUCCESS_COUNT else 0

	var base := int(target.get("base_cattle", DEFAULT_BASE_CATTLE))
	var variance := int(target.get("cattle_variance", DEFAULT_CATTLE_VARIANCE))
	var cattle_loot := cattle_override
	if cattle_loot < 0:
		# Deterministic mid-range for preview/tests; callers may override.
		cattle_loot = base + (variance / 2)

	var honor_overall := float(target.get("honor_overall", SUCCESS_HONOR_OVERALL))
	var honor_victim := float(target.get("honor_victim", SUCCESS_HONOR_VICTIM))
	var attitude := float(target.get("attitude", SUCCESS_ATTITUDE))
	if mercy:
		honor_overall *= 0.6
		honor_victim *= 0.6
		attitude *= 0.55
	else:
		honor_overall += HEAT_ESCALATION_HONOR * float(escalations)
		honor_victim += HEAT_ESCALATION_HONOR * float(escalations)
		attitude += HEAT_ESCALATION_ATTITUDE * float(escalations)

	var goods: Dictionary = {}
	var raw_goods: Dictionary = target.get("goods", {})
	for gid in raw_goods.keys():
		goods[gid] = int(raw_goods[gid])

	var free_slots := -1
	if economy != null and economy.has_method("get_pen_free_slots"):
		free_slots = int(economy.get_pen_free_slots())

	return {
		"ok": true,
		"success": true,
		"reason": &"ok",
		"target_id": target_id,
		"display_name": String(target.get("display_name", "")),
		"victim_faction": victim,
		"cattle_loot": cattle_loot,
		"pen_free_slots": free_slots,
		"goods_loot": goods,
		"honor_delta_overall": honor_overall,
		"honor_delta_victim": honor_victim,
		"attitude_delta": attitude,
		"retaliation_kind": target.get("retaliation_kind", &"counter_raid"),
		"mercy_active": mercy,
		"raid_count_on_victim": prior,
		"upkeep": _upkeep_snapshot(economy),
	}


func _apply_goods(economy: Object, goods: Dictionary) -> Dictionary:
	var applied: Dictionary = {}
	# Prefer a trade_goods Dictionary on CattleEconomy when present.
	if "trade_goods" in economy:
		var bag: Dictionary = economy.trade_goods
		for gid in goods.keys():
			var n := int(goods[gid])
			if n <= 0:
				continue
			bag[gid] = int(bag.get(gid, 0)) + n
			applied[gid] = n
		economy.trade_goods = bag
		return applied
	# Duck-typed add_trade_goods(goods_id, count) fallback.
	if economy.has_method("add_trade_goods"):
		for gid in goods.keys():
			var n := int(goods[gid])
			if n <= 0:
				continue
			economy.add_trade_goods(gid, n)
			applied[gid] = n
	return applied


func _apply_band_deltas(economy: Object, morale_delta: float, readiness_delta: float) -> void:
	if economy == null:
		return
	if economy.has_method("modify_band_morale") and morale_delta != 0.0:
		economy.modify_band_morale(morale_delta)
	elif "band" in economy and economy.band != null and economy.band.has_method("modify_morale"):
		economy.band.modify_morale(morale_delta)
	if economy.has_method("modify_band_readiness") and readiness_delta != 0.0:
		economy.modify_band_readiness(readiness_delta)
	elif "band" in economy and economy.band != null and economy.band.has_method("modify_readiness"):
		economy.band.modify_readiness(readiness_delta)


func _apply_honor_heat(
	victim: StringName,
	honor_overall: float,
	honor_victim: float,
	attitude_delta: float
) -> void:
	# Resolve via tree so --script / isolated stubs still compile without autoload globals.
	var honor := _autoload("Honor")
	var factions := _autoload("Factions")
	if honor != null:
		if honor_overall != 0.0 and honor.has_method("modify_honor"):
			honor.call("modify_honor", honor_overall, &"")
		if victim != &"" and honor_victim != 0.0 and honor.has_method("modify_honor"):
			honor.call("modify_honor", honor_victim, victim)
	if factions != null and victim != &"" and attitude_delta != 0.0 and factions.has_method("modify_attitude"):
		factions.call("modify_attitude", victim, attitude_delta)


func _upkeep_snapshot(economy: Object) -> Dictionary:
	if economy == null:
		return {}
	var snap := {
		"herd_size": int(economy.get_herd_size()) if economy.has_method("get_herd_size") else -1,
		"pen_free_slots": int(economy.get_pen_free_slots()) if economy.has_method("get_pen_free_slots") else -1,
		"daily_herd_upkeep": int(economy.daily_herd_upkeep_cost()) if economy.has_method("daily_herd_upkeep_cost") else -1,
		"daily_band_upkeep": int(economy.daily_band_upkeep_cost()) if economy.has_method("daily_band_upkeep_cost") else -1,
		"daily_total_upkeep": int(economy.daily_total_upkeep_cost()) if economy.has_method("daily_total_upkeep_cost") else -1,
	}
	return snap


func _spawn_raid_rumor(success: bool, victim: StringName, cattle: int, mercy: bool) -> void:
	var rumors := _autoload("Rumors")
	if rumors == null or not rumors.has_method("add_rumor"):
		return
	var who := String(victim) if victim != &"" else "rivals"
	var day := _day_stamp()
	var prio_high := 3
	var prio_normal := 2
	if success:
		var text := "Word of a cattle raid against %s — %d head driven off." % [who, cattle]
		if not mercy:
			text = "Heat rises: another cattle raid against %s is the talk of the túatha." % who
		rumors.call(
			"add_rumor",
			StringName("cattle_raid_%s_%d" % [who, day]),
			text,
			&"raid",
			prio_high if not mercy else prio_normal,
			8
		)
	else:
		rumors.call(
			"add_rumor",
			StringName("cattle_raid_fail_%s_%d" % [who, day]),
			"A bungled night raid near %s is whispered in the ringforts." % who,
			&"raid",
			prio_normal,
			5
		)


func _retaliation_note(kind: StringName, mercy_active: bool) -> String:
	var mercy_bit := "mercy window — delayed soft response" if mercy_active else "full heat"
	match kind:
		&"counter_raid":
			return "Victim may counter-raid pens (%s)." % mercy_bit
		&"tribute_demand":
			return "Victim may demand cattle tribute / éraic (%s)." % mercy_bit
		&"patrol_heat":
			return "Victim steps up patrols / forage screens (%s)." % mercy_bit
		_:
			return "Faction retaliation stub (%s)." % mercy_bit


func _day_stamp() -> int:
	var clock := _autoload("WorldClock")
	if clock != null and "day" in clock:
		return int(clock.get("day"))
	return 0


func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)
