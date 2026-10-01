class_name CattleEconomy
extends Node
## Cattle as primary wealth + herd/band daily upkeep for Godot gameplay.
##
## Slice: herd + pens + daily tick + Norse Wexford/Waterford trade contact.
## Cattle-raid outcomes: `resolve_raid_success` / `resolve_raid_failure` via
## `raid_outcomes` (systems/raid/cattle_raid_outcomes.gd). Big heat swings
## auto-seed tagged Rumors (raid/heat/faction) inside those resolve paths.
## Not an autoload — ringfort / Game / sim owner instantiates and owns this node.
## Prefer explicit `apply_daily_tick()`; optionally `subscribe_world_clock()`.
##
## Norse trade shares faction id `norse_wexford_waterford` with Factions.

signal herd_changed(count: int)
signal pens_changed(capacity: int, free_slots: int)
## Emitted after each daily tick (herd + band).
signal upkeep_applied(cattle_spent: int, band_spent: int)
signal daily_tick_applied(day: int, report: Dictionary)
signal trade_completed(goods_id: StringName, cattle_delta: int)
signal cattle_gained(amount: int, reason: StringName)
signal cattle_lost(amount: int, reason: StringName)
## Forwarded from BandUpkeep for UI that only holds CattleEconomy.
signal band_changed(size: int, morale: float, readiness: float)
signal band_upkeep_failed(shortfall_cattle: int)
## Forwarded from CattleRaidOutcomes (raid loot / heat / retaliation).
signal raid_resolved(outcome: Dictionary)
signal raid_loot_applied(cattle_gained: int, goods: Dictionary)
signal raid_honor_heat_applied(victim_faction: StringName, honor_delta: float, attitude_delta: float)
signal raid_retaliation_queued(hook: Dictionary)

## Current herd headcount (primary wealth).
var herd_size: int = 12
## Named trade goods held from Norse contact (goods_id → count).
var trade_goods: Dictionary = {}

## Soft cap from ringfort pens (upgrade via set_pen_capacity / upgrade_pens).
var pen_capacity: int = 40
## Cattle consumed by the herd itself per day (feed / natural loss), per 10 head.
var herd_upkeep_per_10: float = 0.5

## Norse coastal trade contact (slice actor: Wexford/Waterford faction).
var norse_trade_contact_id: StringName = &"norse_wexford_waterford"
var norse_trade_unlocked: bool = true

## Band upkeep + recruitment data hooks (no gameplay UI here).
var band: BandUpkeep = BandUpkeep.new()
## Cattle-raid loot / upkeep / honor-heat resolver (systems/raid/).
var raid_outcomes: CattleRaidOutcomes = CattleRaidOutcomes.new()

var _clock_subscribed: Node = null
var _last_tick_day: int = -1


func _ready() -> void:
	if not band.band_changed.is_connected(_on_band_changed):
		band.band_changed.connect(_on_band_changed)
	if not band.upkeep_failed.is_connected(_on_band_upkeep_failed):
		band.upkeep_failed.connect(_on_band_upkeep_failed)
	_wire_raid_outcomes()


func _exit_tree() -> void:
	unsubscribe_world_clock()


func _on_band_changed(size: int, morale: float, readiness: float) -> void:
	band_changed.emit(size, morale, readiness)


func _on_band_upkeep_failed(shortfall: int) -> void:
	band_upkeep_failed.emit(shortfall)


func _wire_raid_outcomes() -> void:
	if raid_outcomes == null:
		raid_outcomes = CattleRaidOutcomes.new()
	if not raid_outcomes.raid_resolved.is_connected(_on_raid_resolved):
		raid_outcomes.raid_resolved.connect(_on_raid_resolved)
	if not raid_outcomes.loot_applied.is_connected(_on_raid_loot_applied):
		raid_outcomes.loot_applied.connect(_on_raid_loot_applied)
	if not raid_outcomes.honor_heat_applied.is_connected(_on_raid_honor_heat):
		raid_outcomes.honor_heat_applied.connect(_on_raid_honor_heat)
	if not raid_outcomes.retaliation_queued.is_connected(_on_raid_retaliation):
		raid_outcomes.retaliation_queued.connect(_on_raid_retaliation)


func _on_raid_resolved(outcome: Dictionary) -> void:
	raid_resolved.emit(outcome)


func _on_raid_loot_applied(cattle_gained: int, goods: Dictionary) -> void:
	raid_loot_applied.emit(cattle_gained, goods)


func _on_raid_honor_heat(victim: StringName, honor_delta: float, attitude_delta: float) -> void:
	raid_honor_heat_applied.emit(victim, honor_delta, attitude_delta)


func _on_raid_retaliation(hook: Dictionary) -> void:
	raid_retaliation_queued.emit(hook)


# --- Herd / pens -------------------------------------------------------------

func get_herd_size() -> int:
	return herd_size


func get_pen_capacity() -> int:
	return pen_capacity


func get_pen_free_slots() -> int:
	return maxi(0, pen_capacity - herd_size)


func set_pen_capacity(capacity: int) -> void:
	pen_capacity = maxi(0, capacity)
	if herd_size > pen_capacity:
		herd_size = pen_capacity
		herd_changed.emit(herd_size)
	pens_changed.emit(pen_capacity, get_pen_free_slots())


## Grow pens by delta (ringfort upgrade hook).
func upgrade_pens(delta: int) -> void:
	if delta == 0:
		return
	set_pen_capacity(pen_capacity + delta)


func add_cattle(amount: int) -> int:
	if amount <= 0:
		return 0
	var room := get_pen_free_slots()
	var added := mini(amount, room)
	if added <= 0:
		return 0
	herd_size += added
	herd_changed.emit(herd_size)
	pens_changed.emit(pen_capacity, get_pen_free_slots())
	return added


func spend_cattle(amount: int) -> bool:
	if amount <= 0:
		return true
	if herd_size < amount:
		return false
	herd_size -= amount
	herd_changed.emit(herd_size)
	pens_changed.emit(pen_capacity, get_pen_free_slots())
	return true


## Raid / mission gain hook. Caps at pens; returns heads actually added.
func gain_cattle(amount: int, reason: StringName = &"raid") -> int:
	var added := add_cattle(amount)
	if added > 0:
		cattle_gained.emit(added, reason)
	return added


## Raid loss / theft / disease hook. Returns heads actually removed.
func lose_cattle(amount: int, reason: StringName = &"raid") -> int:
	if amount <= 0:
		return 0
	var removed := mini(amount, herd_size)
	if removed <= 0:
		return 0
	herd_size -= removed
	herd_changed.emit(herd_size)
	pens_changed.emit(pen_capacity, get_pen_free_slots())
	cattle_lost.emit(removed, reason)
	return removed


func daily_herd_upkeep_cost() -> int:
	if herd_size <= 0:
		return 0
	var raw := (float(herd_size) / 10.0) * herd_upkeep_per_10
	return maxi(1, int(ceil(raw)))


func daily_band_upkeep_cost() -> int:
	return band.daily_cattle_cost()


func daily_total_upkeep_cost() -> int:
	return daily_herd_upkeep_cost() + daily_band_upkeep_cost()


# --- Daily tick --------------------------------------------------------------

## Primary Godot entry: run herd + band upkeep once per sim day.
## Pass WorldClock.day when known (stored on report / last tick). Idempotent
## for the same day if `skip_if_same_day` is true (default false for explicit calls).
func apply_daily_tick(day: int = -1, skip_if_same_day: bool = false) -> Dictionary:
	if skip_if_same_day and day >= 0 and day == _last_tick_day:
		return {
			"skipped": true,
			"day": day,
			"herd_size": herd_size,
			"band": band.to_debug_dict(),
		}

	var herd_cost := daily_herd_upkeep_cost()
	var herd_paid := true
	var starvation_loss := 0
	if herd_cost > 0:
		herd_paid = spend_cattle(herd_cost)
		if not herd_paid:
			# Starvation: lose a head instead of a clean pay.
			starvation_loss = lose_cattle(1, &"starvation")

	var band_cost := band.daily_cattle_cost()
	var band_paid := band.apply_daily_upkeep(self)
	var spent_band := band_cost if band_paid else 0
	var spent_herd := herd_cost if herd_paid else 0

	if day >= 0:
		_last_tick_day = day

	var report := {
		"skipped": false,
		"day": day if day >= 0 else _last_tick_day,
		"herd_cost": herd_cost,
		"herd_paid": herd_paid,
		"starvation_loss": starvation_loss,
		"band_cost": band_cost,
		"band_paid": band_paid,
		"herd_size": herd_size,
		"pen_capacity": pen_capacity,
		"pen_free_slots": get_pen_free_slots(),
		"band": band.to_debug_dict(),
	}
	upkeep_applied.emit(spent_herd, spent_band)
	daily_tick_applied.emit(int(report["day"]), report)
	return report


## Alias kept for earlier stub callers.
func apply_daily_upkeep() -> Dictionary:
	return apply_daily_tick()


## Optional: connect to WorldClock.day_advanced without claiming Game ownership.
## Pass null to use the WorldClock autoload when present.
## Auto-tick uses skip_if_same_day so double-subscribe is harmless.
func subscribe_world_clock(clock: Node = null) -> void:
	if clock == null:
		clock = _resolve_world_clock()
	if clock == null:
		push_warning("CattleEconomy.subscribe_world_clock: no WorldClock found")
		return
	if not clock.has_signal("day_advanced"):
		push_warning("CattleEconomy.subscribe_world_clock: clock missing day_advanced")
		return
	unsubscribe_world_clock()
	clock.day_advanced.connect(_on_world_day_advanced)
	_clock_subscribed = clock


func unsubscribe_world_clock() -> void:
	if _clock_subscribed != null and is_instance_valid(_clock_subscribed):
		if _clock_subscribed.day_advanced.is_connected(_on_world_day_advanced):
			_clock_subscribed.day_advanced.disconnect(_on_world_day_advanced)
	_clock_subscribed = null


func is_subscribed_to_world_clock() -> bool:
	return _clock_subscribed != null and is_instance_valid(_clock_subscribed)


func _on_world_day_advanced(day: int) -> void:
	apply_daily_tick(day, true)


func _resolve_world_clock() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	return root.get_node_or_null("WorldClock")


# --- Band facade (typed convenience for Godot callers) -----------------------

func get_band_size() -> int:
	return band.get_size()


func get_band_morale() -> float:
	return band.get_morale()


func get_band_readiness() -> float:
	return band.get_readiness()


func get_band_daily_cost() -> int:
	return band.daily_cattle_cost()


func get_skirmish_confidence() -> float:
	return band.skirmish_confidence()


func can_attempt_skirmish(min_confidence: float = 0.35) -> bool:
	return band.can_attempt_skirmish(min_confidence)


func set_band(new_size: int, new_morale: float = -1.0, new_readiness: float = -1.0) -> void:
	band.set_band(new_size, new_morale, new_readiness)


func recruit_warriors(count: int = 1) -> bool:
	return band.recruit(count)


func dismiss_warriors(count: int = 1) -> bool:
	return band.dismiss(count)


func modify_band_morale(delta: float) -> void:
	band.modify_morale(delta)


func modify_band_readiness(delta: float) -> void:
	band.modify_readiness(delta)




# --- Recruitment data hooks (who / cost) + Honor enech gates -----------------

## Sentinel: omit / pass this so facade resolves Honor.overall (0..100).
const HONOR_RESOLVE_AUTO: float = -1000.0


func get_recruit_pool() -> Array[Dictionary]:
	return band.get_recruit_pool()


func get_recruit_option(option_id: StringName) -> Dictionary:
	return band.get_recruit_option(option_id)


## Base pool cost (no Honor tier). Prefer effective_recruit_cattle_cost.
func get_recruit_cattle_cost(option_id: StringName) -> int:
	return band.get_recruit_cattle_cost(option_id)


## Honor-tier cattle cost. honor_score defaults to Honor.overall when auto.
func effective_recruit_cattle_cost(
	option_id: StringName,
	honor_score: float = HONOR_RESOLVE_AUTO
) -> int:
	return band.effective_recruit_cattle_cost(option_id, _resolve_honor_score(honor_score))


## List pool rows with eligible/can_afford flags.
## Honor defaults to Honor.overall; attitudes default to Factions if present.
func list_recruit_options(
	honor_score: float = HONOR_RESOLVE_AUTO,
	faction_attitudes: Dictionary = {},
	affordable_only: bool = false
) -> Array[Dictionary]:
	var honor := _resolve_honor_score(honor_score)
	var attitudes := faction_attitudes
	if attitudes.is_empty():
		attitudes = _default_faction_attitudes()
	return band.list_recruit_options(
		honor, attitudes, affordable_only, herd_size
	)


func list_eligible_recruits(
	honor_score: float = HONOR_RESOLVE_AUTO,
	faction_attitudes: Dictionary = {}
) -> Array[Dictionary]:
	var honor := _resolve_honor_score(honor_score)
	var attitudes := faction_attitudes
	if attitudes.is_empty():
		attitudes = _default_faction_attitudes()
	return band.list_eligible_recruits(honor, attitudes, herd_size)


func can_recruit_option(
	option_id: StringName,
	honor_score: float = HONOR_RESOLVE_AUTO,
	faction_attitudes: Dictionary = {}
) -> Dictionary:
	var honor := _resolve_honor_score(honor_score)
	var attitudes := faction_attitudes
	if attitudes.is_empty():
		attitudes = _default_faction_attitudes()
	var gate := band.can_recruit_option(option_id, honor, attitudes)
	if not bool(gate.get("ok", false)):
		return gate
	var cost := int(gate.get("cattle_cost", 0))
	if herd_size < cost:
		var denied := gate.duplicate(true)
		denied["ok"] = false
		denied["reason"] = &"cannot_afford"
		denied["herd_size"] = herd_size
		return denied
	return gate


## Pay from this herd and grow the band.
## Honor defaults to Honor.overall — same API, now enech-gated.
func try_recruit_option(
	option_id: StringName,
	honor_score: float = HONOR_RESOLVE_AUTO,
	faction_attitudes: Dictionary = {}
) -> Dictionary:
	var honor := _resolve_honor_score(honor_score)
	var attitudes := faction_attitudes
	if attitudes.is_empty():
		attitudes = _default_faction_attitudes()
	return band.try_recruit_option(option_id, self, honor, attitudes)


## Remote / F5 probe: who is recruitable at current (or override) enech.
func probe_recruit_honor_gates(honor_score: float = HONOR_RESOLVE_AUTO) -> Dictionary:
	var honor := _resolve_honor_score(honor_score)
	var attitudes := _default_faction_attitudes()
	var probe := band.probe_recruit_honor_gates(honor, attitudes)
	probe["herd_size"] = herd_size
	probe["band_size"] = band.get_size()
	probe["band_readiness"] = band.get_readiness()
	# Annotate affordability against current herd.
	var annotated: Array = []
	for row in probe.get("options", []):
		var r: Dictionary = row.duplicate(true)
		var cost := int(r.get("cattle_cost", 0))
		r["can_afford"] = herd_size >= cost
		annotated.append(r)
	probe["options"] = annotated
	return probe


func _resolve_honor_score(honor_score: float) -> float:
	if honor_score > HONOR_RESOLVE_AUTO + 0.5:
		return honor_score
	return _default_honor_score()


func _default_honor_score() -> float:
	# Resolve Honor via tree so --script / isolated tests still compile.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 50.0
	var honor := tree.root.get_node_or_null("Honor")
	if honor == null:
		return 50.0
	if honor.has_method("get_honor"):
		return float(honor.call("get_honor"))
	var overall = honor.get("overall")
	if typeof(overall) in [TYPE_FLOAT, TYPE_INT]:
		return float(overall)
	return 50.0


func _default_faction_attitudes() -> Dictionary:
	# Resolve Factions via tree so --script / isolated tests still compile.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {}
	var factions := tree.root.get_node_or_null("Factions")
	if factions == null:
		return {}
	var attitudes = factions.get("attitudes")
	if typeof(attitudes) != TYPE_DICTIONARY:
		return {}
	return attitudes.duplicate(true)

# --- Cattle-raid outcomes (loot / upkeep / honor heat) ------------------------

func list_raid_targets() -> Array[Dictionary]:
	return raid_outcomes.list_targets()


func get_raid_target(target_id: StringName) -> Dictionary:
	return raid_outcomes.get_target(target_id)


func preview_raid_success(target_id: StringName, cattle_override: int = -1) -> Dictionary:
	return raid_outcomes.preview_success(self, target_id, cattle_override)


## Primary Godot entry after a successful night raid mission.
## Returns outcome Dictionary (loot, upkeep snapshot, heat, retaliation hook).
func resolve_raid_success(
	target_id: StringName,
	cattle_override: int = -1,
	apply_heat: bool = true,
	apply_band: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	_wire_raid_outcomes()
	return raid_outcomes.resolve_success(
		self, target_id, cattle_override, apply_heat, apply_band, spawn_rumor
	)


## Optional: resolve a failed raid (cattle loss / band hit / lighter heat).
func resolve_raid_failure(
	target_id: StringName,
	cattle_lost_override: int = -1,
	apply_heat: bool = true,
	apply_band: bool = true,
	spawn_rumor: bool = true
) -> Dictionary:
	_wire_raid_outcomes()
	return raid_outcomes.resolve_failure(
		self, target_id, cattle_lost_override, apply_heat, apply_band, spawn_rumor
	)


func get_raid_retaliation_hook(
	victim_faction: StringName,
	kind: StringName = &"counter_raid",
	cattle_taken: int = 0
) -> Dictionary:
	var count := raid_outcomes.get_success_count(victim_faction)
	var mercy := raid_outcomes.is_mercy_active(victim_faction)
	return raid_outcomes.build_retaliation_hook(
		victim_faction, kind, count, cattle_taken, mercy
	)


## Documented raid→Rumors heat thresholds (attitude / honor / retaliation severity).
func get_raid_rumor_heat_thresholds() -> Dictionary:
	_wire_raid_outcomes()
	return raid_outcomes.get_rumor_heat_thresholds()


## Tag vocabulary preview for a victim (raid / heat / faction:* / direction:colder).
func build_raid_heat_rumor_tags(victim_faction: StringName, escalated: bool = false) -> Array:
	_wire_raid_outcomes()
	return raid_outcomes.build_raid_heat_tags(victim_faction, escalated)


# --- Norse trade -------------------------------------------------------------

## Simple trade stub: cattle_delta < 0 sells cattle for goods; > 0 buys cattle.
func trade_with_norse(goods_id: StringName, cattle_delta: int) -> bool:
	if not norse_trade_unlocked:
		return false
	if cattle_delta < 0:
		if not spend_cattle(-cattle_delta):
			return false
		trade_goods[goods_id] = int(trade_goods.get(goods_id, 0)) + 1
	elif cattle_delta > 0:
		var added := add_cattle(cattle_delta)
		if added <= 0:
			return false
		var have := int(trade_goods.get(goods_id, 0))
		if have > 0:
			trade_goods[goods_id] = have - 1
	else:
		return false
	trade_completed.emit(goods_id, cattle_delta)
	return true


func get_norse_trade_contact_id() -> StringName:
	return norse_trade_contact_id


# --- Debug -------------------------------------------------------------------

func to_debug_dict() -> Dictionary:
	return {
		"herd_size": herd_size,
		"pen_capacity": pen_capacity,
		"pen_free_slots": get_pen_free_slots(),
		"daily_herd_upkeep": daily_herd_upkeep_cost(),
		"daily_band_upkeep": daily_band_upkeep_cost(),
		"daily_total_upkeep": daily_total_upkeep_cost(),
		"norse_trade_contact_id": norse_trade_contact_id,
		"norse_trade_unlocked": norse_trade_unlocked,
		"trade_goods": trade_goods.duplicate(true),
		"subscribed_to_clock": is_subscribed_to_world_clock(),
		"last_tick_day": _last_tick_day,
		"band": band.to_debug_dict(),
		"recruit_pool_size": band.RECRUIT_POOL.size(),
		"recruit_honor": _default_honor_score(),
		"raid_outcomes": raid_outcomes.to_debug_dict() if raid_outcomes else {},
	}
