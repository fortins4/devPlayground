extends Node
## Cattle as primary wealth + herd upkeep. Band upkeep hooks live alongside.
##
## Slice: herd + daily upkeep + one Norse town trade contact stub.
## Recruitment UI later — use `band` (BandUpkeep) for size/morale/readiness costs.

signal herd_changed(count: int)
signal upkeep_applied(cattle_spent: int, band_spent: int)
signal trade_completed(goods_id: StringName, cattle_delta: int)

var herd_size: int = 12
var trade_goods: Dictionary = {}

## Soft cap from ringfort pens (upgrade later).
var pen_capacity: int = 40
## Cattle consumed by the herd itself per day (feed / loss).
var herd_upkeep_per_10: float = 0.5

## Norse town trade contact stub (Wexford / Waterford coast).
var norse_trade_contact_id: StringName = &"wexford_norse_trader"
var norse_trade_unlocked: bool = true

## Band upkeep API for later recruitment (no gameplay UI here).
var band: BandUpkeep = BandUpkeep.new()


func add_cattle(amount: int) -> void:
	herd_size = maxi(0, herd_size + amount)
	if herd_size > pen_capacity:
		herd_size = pen_capacity
	herd_changed.emit(herd_size)


func spend_cattle(amount: int) -> bool:
	if herd_size < amount:
		return false
	herd_size -= amount
	herd_changed.emit(herd_size)
	return true


func daily_herd_upkeep_cost() -> int:
	if herd_size <= 0:
		return 0
	var raw := (float(herd_size) / 10.0) * herd_upkeep_per_10
	return maxi(1, int(ceil(raw)))


## Call from WorldClock.day_advanced owner / ringfort when simulation ticks.
func apply_daily_upkeep() -> Dictionary:
	var herd_cost := daily_herd_upkeep_cost()
	var herd_paid := spend_cattle(herd_cost) if herd_cost > 0 else true
	if not herd_paid and herd_cost > 0:
		# Starvation: lose a head instead of a clean pay.
		herd_size = maxi(0, herd_size - 1)
		herd_changed.emit(herd_size)
	var band_cost := band.daily_cattle_cost()
	var band_paid := band.apply_daily_upkeep(self)
	var spent_band := band_cost if band_paid else 0
	var spent_herd := herd_cost if herd_paid else 0
	upkeep_applied.emit(spent_herd, spent_band)
	return {
		"herd_cost": herd_cost,
		"herd_paid": herd_paid,
		"band_cost": band_cost,
		"band_paid": band_paid,
		"herd_size": herd_size,
		"band": band.to_debug_dict(),
	}


## Simple trade stub: sell cattle for a named Norse trade good, or buy cattle.
func trade_with_norse(goods_id: StringName, cattle_delta: int) -> bool:
	if not norse_trade_unlocked:
		return false
	if cattle_delta < 0:
		if not spend_cattle(-cattle_delta):
			return false
		trade_goods[goods_id] = int(trade_goods.get(goods_id, 0)) + 1
	elif cattle_delta > 0:
		add_cattle(cattle_delta)
		var have := int(trade_goods.get(goods_id, 0))
		if have <= 0:
			# Buying cattle for silver/goods not yet modeled — allow cattle-only stub credit.
			pass
		else:
			trade_goods[goods_id] = have - 1
	else:
		return false
	trade_completed.emit(goods_id, cattle_delta)
	return true


func to_debug_dict() -> Dictionary:
	return {
		"herd_size": herd_size,
		"pen_capacity": pen_capacity,
		"daily_herd_upkeep": daily_herd_upkeep_cost(),
		"norse_trade_contact_id": norse_trade_contact_id,
		"trade_goods": trade_goods.duplicate(true),
		"band": band.to_debug_dict(),
	}
