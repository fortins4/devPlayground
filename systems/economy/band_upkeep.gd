class_name BandUpkeep
extends RefCounted
## Band size / morale / readiness + cattle upkeep + recruitment data hooks.
##
## Systems data only — no UI. CattleEconomy (or ringfort owner) pays via
## `apply_daily_upkeep(economy)`. Ambush confidence: `skirmish_confidence()`.
## Who-can-join / cost: `RECRUIT_POOL`, `list_recruit_options`, `try_recruit_option`
## (Honor enech 0..100 gates + optional cattle cost tiers).

signal band_changed(size: int, morale: float, readiness: float)
signal upkeep_failed(shortfall_cattle: int)
signal warrior_recruited(new_size: int)
signal warrior_dismissed(new_size: int)
signal recruit_option_denied(option_id: StringName, reason: StringName)

## Warrior count in Cian's band (0 until recruitment lands).
var size: int = 0
## Cohesion / willingness to fight (0..100).
var morale: float = 50.0
## Gear, rest, drill — gates skirmish confidence (0..100).
var readiness: float = 40.0

## Soft cap for slice recruitment (ringfort barracks upgrade later).
var max_size: int = 8

## Cattle cost per warrior per day (slice tuning knobs).
var cattle_per_warrior_per_day: float = 0.15
## Flat cattle cost even for an empty band (camp overhead); 0 while size == 0.
var base_camp_cattle_per_day: float = 0.0

## Slice recruit archetypes: who can join + cattle cost (+ Honor enech gates).
## Honor scale matches autoload Honor overall (0..100). Callers pass honor /
## faction attitudes in; CattleEconomy auto-resolves Honor when omitted.
## Schema keys: id, display_name, cattle_cost, count, honor_min, honor_max,
##   readiness_min, required_attitudes {faction_id → min}, tags, note,
##   optional cost tiers: honor_cost_low_below + cattle_cost_low_honor,
##   honor_cost_high_at + cattle_cost_high_honor
const RECRUIT_POOL: Array[Dictionary] = [
	{
		"id": &"local_kerne",
		"display_name": "Local kerne",
		"cattle_cost": 2,
		"count": 1,
		"honor_min": 15.0,
		"honor_max": 100.0,
		"readiness_min": 0.0,
		"required_attitudes": {},
		"tags": [&"gaelic", &"light"],
		"honor_cost_low_below": 25.0,
		"cattle_cost_low_honor": 3,
		"note": "Túatha youth; thin enech pays +1 cattle.",
	},
	{
		"id": &"ringfort_veteran",
		"display_name": "Ringfort veteran",
		"cattle_cost": 4,
		"count": 1,
		"honor_min": 35.0,
		"honor_max": 100.0,
		"readiness_min": 25.0,
		"required_attitudes": {},
		"tags": [&"gaelic", &"drilled"],
		"honor_cost_low_below": 40.0,
		"cattle_cost_low_honor": 6,
		"honor_cost_high_at": 70.0,
		"cattle_cost_high_honor": 3,
		"note": "Experienced spear; needs solid enech. High enech discounts.",
	},
	{
		"id": &"ui_chennselaig_retainer",
		"display_name": "Uí Chennselaig retainer",
		"cattle_cost": 5,
		"count": 1,
		"honor_min": 50.0,
		"honor_max": 100.0,
		"readiness_min": 20.0,
		"required_attitudes": {&"ui_chennselaig": 15.0},
		"tags": [&"gaelic", &"retainer"],
		"honor_cost_high_at": 75.0,
		"cattle_cost_high_honor": 4,
		"note": "Warm Diarmait attitude + respectable enech; lofty enech discounts.",
	},
	{
		"id": &"fian_outlaw",
		"display_name": "Fían outlaw",
		"cattle_cost": 3,
		"count": 1,
		"honor_min": 0.0,
		"honor_max": 40.0,
		"readiness_min": 0.0,
		"required_attitudes": {},
		"tags": [&"fian", &"light"],
		"note": "Only when enech is thin — outlaws shun a lofty lord (honor_max).",
	},
	{
		"id": &"norse_coastal_axe",
		"display_name": "Norse coastal axeman",
		"cattle_cost": 6,
		"count": 1,
		"honor_min": 30.0,
		"honor_max": 100.0,
		"readiness_min": 15.0,
		"required_attitudes": {&"norse_wexford_waterford": 10.0},
		"tags": [&"norse", &"axe"],
		"honor_cost_low_below": 40.0,
		"cattle_cost_low_honor": 8,
		"note": "Harbor hireling; thin enech pays a premium.",
	},
]


func get_size() -> int:
	return size


func get_morale() -> float:
	return morale


func get_readiness() -> float:
	return readiness


func get_max_size() -> int:
	return max_size


func daily_cattle_cost() -> int:
	if size <= 0:
		return 0
	var raw := base_camp_cattle_per_day + float(size) * cattle_per_warrior_per_day
	return maxi(1, int(ceil(raw)))


## Replace band state. Pass morale/readiness < 0 to leave that field unchanged.
func set_band(new_size: int, new_morale: float = -1.0, new_readiness: float = -1.0) -> void:
	size = clampi(new_size, 0, max_size)
	if new_morale >= 0.0:
		morale = clampf(new_morale, 0.0, 100.0)
	if new_readiness >= 0.0:
		readiness = clampf(new_readiness, 0.0, 100.0)
	band_changed.emit(size, morale, readiness)


func set_max_size(cap: int) -> void:
	max_size = maxi(0, cap)
	if size > max_size:
		size = max_size
		band_changed.emit(size, morale, readiness)


func modify_morale(delta: float) -> void:
	morale = clampf(morale + delta, 0.0, 100.0)
	band_changed.emit(size, morale, readiness)


func modify_readiness(delta: float) -> void:
	readiness = clampf(readiness + delta, 0.0, 100.0)
	band_changed.emit(size, morale, readiness)


## Recruit one (or more) warriors if under cap. Returns false if full.
func recruit(count: int = 1, morale_bonus: float = 2.0) -> bool:
	if count <= 0 or size >= max_size:
		return false
	var added := mini(count, max_size - size)
	size += added
	morale = clampf(morale + morale_bonus * float(added), 0.0, 100.0)
	# Fresh recruits drag readiness slightly until drilled.
	readiness = clampf(readiness - 1.5 * float(added), 0.0, 100.0)
	band_changed.emit(size, morale, readiness)
	warrior_recruited.emit(size)
	return true


## Dismiss warriors (voluntary leave / death bookkeeping). Returns false if empty.
func dismiss(count: int = 1, morale_penalty: float = 3.0) -> bool:
	if count <= 0 or size <= 0:
		return false
	var removed := mini(count, size)
	size -= removed
	morale = clampf(morale - morale_penalty * float(removed), 0.0, 100.0)
	band_changed.emit(size, morale, readiness)
	warrior_dismissed.emit(size)
	return true


## Confidence to ambush an Anglo-Norman patrol (0..1). Recruitment UI later.
func skirmish_confidence() -> float:
	if size <= 0:
		return 0.0
	var size_factor := clampf(float(size) / 6.0, 0.0, 1.0)
	return clampf(
		(size_factor * 0.4) + (morale / 100.0 * 0.3) + (readiness / 100.0 * 0.3),
		0.0,
		1.0
	)


## True when confidence clears the slice ambush gate (default 0.35).
func can_attempt_skirmish(min_confidence: float = 0.35) -> bool:
	return skirmish_confidence() >= min_confidence


## Pay daily upkeep from a CattleEconomy-like object (duck-typed: spend_cattle).
func apply_daily_upkeep(economy: Object) -> bool:
	var cost := daily_cattle_cost()
	if cost <= 0:
		return true
	if economy == null or not economy.has_method("spend_cattle"):
		return false
	if not bool(economy.spend_cattle(cost)):
		# Unpaid upkeep erodes morale / readiness — recruitment loop later.
		modify_morale(-5.0)
		modify_readiness(-8.0)
		upkeep_failed.emit(cost)
		return false
	# Paid: slight readiness recovery from fed / rested camp.
	modify_readiness(1.0)
	return true




# --- Recruitment data hooks (who / cost) -------------------------------------

func get_recruit_pool() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in RECRUIT_POOL:
		out.append(entry.duplicate(true))
	return out


func get_recruit_option(option_id: StringName) -> Dictionary:
	for entry in RECRUIT_POOL:
		if entry.get("id") == option_id:
			return entry.duplicate(true)
	return {}


## Base cattle_cost from pool (ignores Honor tiers). Prefer effective_recruit_cattle_cost.
func get_recruit_cattle_cost(option_id: StringName) -> int:
	var opt := get_recruit_option(option_id)
	if opt.is_empty():
		return -1
	return maxi(0, int(opt.get("cattle_cost", 0)))


## Cattle cost after Honor enech tiers (low premium / high discount).
## Pass Honor.get_honor() (0..100). Unknown option → -1.
func effective_recruit_cattle_cost(option_id: StringName, honor_score: float = 50.0) -> int:
	var opt := get_recruit_option(option_id)
	if opt.is_empty():
		return -1
	return _effective_cattle_cost(opt, honor_score)


func _effective_cattle_cost(opt: Dictionary, honor_score: float) -> int:
	var cost := maxi(0, int(opt.get("cattle_cost", 0)))
	var low_below := float(opt.get("honor_cost_low_below", -1.0))
	if low_below >= 0.0 and honor_score < low_below:
		cost = maxi(0, int(opt.get("cattle_cost_low_honor", cost)))
	var high_at := float(opt.get("honor_cost_high_at", -1.0))
	if high_at >= 0.0 and honor_score >= high_at:
		cost = maxi(0, int(opt.get("cattle_cost_high_honor", cost)))
	return cost


## Eligibility without paying. Pass Honor overall (0..100) + faction attitude map.
## `faction_attitudes` is faction_id → float (player attitude), e.g. Factions.attitudes.
## cattle_cost in the result is Honor-tier effective cost.
func can_recruit_option(
	option_id: StringName,
	honor_score: float = 50.0,
	faction_attitudes: Dictionary = {}
) -> Dictionary:
	var opt := get_recruit_option(option_id)
	if opt.is_empty():
		return {"ok": false, "reason": &"unknown_option", "option": {}}
	if size >= max_size:
		return {"ok": false, "reason": &"band_full", "option": opt}
	var count := maxi(1, int(opt.get("count", 1)))
	if size + count > max_size:
		return {"ok": false, "reason": &"band_capacity", "option": opt}
	var honor_min := float(opt.get("honor_min", 0.0))
	var honor_max := float(opt.get("honor_max", 100.0))
	var cost := _effective_cattle_cost(opt, honor_score)
	if honor_score < honor_min:
		return {
			"ok": false,
			"reason": &"honor_too_low",
			"option": opt,
			"honor_score": honor_score,
			"honor_min": honor_min,
			"honor_max": honor_max,
			"cattle_cost": cost,
			"cattle_cost_base": int(opt.get("cattle_cost", 0)),
		}
	if honor_score > honor_max:
		return {
			"ok": false,
			"reason": &"honor_too_high",
			"option": opt,
			"honor_score": honor_score,
			"honor_min": honor_min,
			"honor_max": honor_max,
			"cattle_cost": cost,
			"cattle_cost_base": int(opt.get("cattle_cost", 0)),
		}
	if readiness < float(opt.get("readiness_min", 0.0)):
		return {
			"ok": false,
			"reason": &"readiness_too_low",
			"option": opt,
			"honor_score": honor_score,
			"cattle_cost": cost,
		}
	var required: Dictionary = opt.get("required_attitudes", {})
	for faction_id in required.keys():
		# Skip pure floor sentinels (≤ -100 means "no attitude gate").
		var need := float(required[faction_id])
		if need <= -100.0:
			continue
		var have := float(faction_attitudes.get(faction_id, 0.0))
		if have < need:
			return {
				"ok": false,
				"reason": &"faction_attitude",
				"faction_id": faction_id,
				"need": need,
				"have": have,
				"option": opt,
				"honor_score": honor_score,
				"cattle_cost": cost,
			}
	return {
		"ok": true,
		"reason": &"ok",
		"option": opt,
		"cattle_cost": cost,
		"cattle_cost_base": int(opt.get("cattle_cost", 0)),
		"count": count,
		"honor_score": honor_score,
		"honor_min": honor_min,
		"honor_max": honor_max,
	}


## Options the band could take right now (gates only — does not check cattle).
## Row cattle_cost is Honor-tier effective; cattle_cost_base is pool base.
func list_recruit_options(
	honor_score: float = 50.0,
	faction_attitudes: Dictionary = {},
	affordable_only: bool = false,
	available_cattle: int = -1
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in RECRUIT_POOL:
		var option_id: StringName = entry.get("id")
		var gate := can_recruit_option(option_id, honor_score, faction_attitudes)
		var row := entry.duplicate(true)
		row["eligible"] = bool(gate.get("ok", false))
		row["deny_reason"] = gate.get("reason", &"")
		var base_cost := int(entry.get("cattle_cost", 0))
		var cost := int(gate.get("cattle_cost", base_cost))
		row["cattle_cost_base"] = base_cost
		row["cattle_cost"] = cost
		row["honor_score"] = honor_score
		row["can_afford"] = available_cattle < 0 or available_cattle >= cost
		if affordable_only and available_cattle >= 0 and available_cattle < cost:
			continue
		if bool(gate.get("ok", false)):
			out.append(row)
		elif not affordable_only:
			# Still list ineligible rows when not filtering — UI can grey them.
			out.append(row)
	return out


## Eligible-only convenience (ignores cattle unless available_cattle >= 0).
func list_eligible_recruits(
	honor_score: float = 50.0,
	faction_attitudes: Dictionary = {},
	available_cattle: int = -1
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in list_recruit_options(honor_score, faction_attitudes, false, available_cattle):
		if not bool(row.get("eligible", false)):
			continue
		if available_cattle >= 0 and not bool(row.get("can_afford", true)):
			continue
		out.append(row)
	return out


## Pay cattle (via economy.spend_cattle) then grow the band. Returns result dict.
## Charges Honor-tier effective cattle_cost.
func try_recruit_option(
	option_id: StringName,
	economy: Object,
	honor_score: float = 50.0,
	faction_attitudes: Dictionary = {}
) -> Dictionary:
	var gate := can_recruit_option(option_id, honor_score, faction_attitudes)
	if not bool(gate.get("ok", false)):
		var reason: StringName = gate.get("reason", &"denied")
		recruit_option_denied.emit(option_id, reason)
		return {
			"ok": false,
			"reason": reason,
			"option": gate.get("option", {}),
			"honor_score": honor_score,
			"cattle_cost": gate.get("cattle_cost", -1),
		}
	var opt: Dictionary = gate.get("option", {})
	var cost := int(gate.get("cattle_cost", _effective_cattle_cost(opt, honor_score)))
	var count := maxi(1, int(opt.get("count", 1)))
	if cost > 0:
		if economy == null or not economy.has_method("spend_cattle"):
			recruit_option_denied.emit(option_id, &"no_economy")
			return {"ok": false, "reason": &"no_economy", "option": opt, "honor_score": honor_score}
		if not bool(economy.spend_cattle(cost)):
			recruit_option_denied.emit(option_id, &"cannot_afford")
			return {
				"ok": false,
				"reason": &"cannot_afford",
				"option": opt,
				"cattle_cost": cost,
				"honor_score": honor_score,
			}
	# Drilled retainers add a touch of readiness; green kernes still drag via recruit().
	var morale_bonus := 2.0
	var tags: Array = opt.get("tags", [])
	if &"drilled" in tags or &"retainer" in tags:
		morale_bonus = 3.0
		modify_readiness(2.0 * float(count))
	if not recruit(count, morale_bonus):
		# Extremely unlikely after capacity gate; refund if we charged.
		if cost > 0 and economy != null and economy.has_method("add_cattle"):
			economy.add_cattle(cost)
		recruit_option_denied.emit(option_id, &"recruit_failed")
		return {"ok": false, "reason": &"recruit_failed", "option": opt, "honor_score": honor_score}
	return {
		"ok": true,
		"reason": &"ok",
		"option_id": option_id,
		"cattle_spent": cost,
		"cattle_cost_base": int(opt.get("cattle_cost", 0)),
		"count": count,
		"band_size": size,
		"option": opt,
		"honor_score": honor_score,
	}


## Snapshot pool gates at a given Honor overall (default seed 50).
func probe_recruit_honor_gates(honor_score: float = 50.0, faction_attitudes: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	for row in list_recruit_options(honor_score, faction_attitudes, false, -1):
		rows.append({
			"id": String(row.get("id", &"")),
			"eligible": bool(row.get("eligible", false)),
			"deny_reason": String(row.get("deny_reason", &"")),
			"honor_min": float(row.get("honor_min", 0.0)),
			"honor_max": float(row.get("honor_max", 100.0)),
			"cattle_cost": int(row.get("cattle_cost", 0)),
			"cattle_cost_base": int(row.get("cattle_cost_base", row.get("cattle_cost", 0))),
		})
	return {
		"honor_score": honor_score,
		"honor_scale": "Honor.overall 0..100",
		"options": rows,
	}


func to_debug_dict() -> Dictionary:
	var option_ids: Array[String] = []
	for entry in RECRUIT_POOL:
		option_ids.append(String(entry.get("id", &"")))
	return {
		"size": size,
		"max_size": max_size,
		"morale": morale,
		"readiness": readiness,
		"daily_cattle_cost": daily_cattle_cost(),
		"skirmish_confidence": skirmish_confidence(),
		"can_attempt_skirmish": can_attempt_skirmish(),
		"recruit_pool_size": RECRUIT_POOL.size(),
		"recruit_option_ids": option_ids,
		"recruit_honor_scale": "Honor.overall 0..100",
	}
