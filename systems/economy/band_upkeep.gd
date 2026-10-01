class_name BandUpkeep
extends RefCounted
## Band upkeep API stubs for later recruitment (Systems data only — no UI).
##
## Slice later: recruit warriors; size/morale/readiness gate ambush confidence.
## CattleEconomy (or ringfort owner) should call apply_daily_upkeep each WorldClock day.

signal band_changed(size: int, morale: float, readiness: float)
signal upkeep_failed(shortfall_cattle: int)

## Warrior count in Cian's band (0 until recruitment lands).
var size: int = 0
## Cohesion / willingness to fight (0..100).
var morale: float = 50.0
## Gear, rest, drill — gates skirmish confidence (0..100).
var readiness: float = 40.0

## Cattle cost per warrior per day (slice tuning knobs).
var cattle_per_warrior_per_day: float = 0.15
## Flat cattle cost even for an empty band (camp overhead); 0 while size == 0.
var base_camp_cattle_per_day: float = 0.0


func daily_cattle_cost() -> int:
	if size <= 0:
		return 0
	var raw := base_camp_cattle_per_day + float(size) * cattle_per_warrior_per_day
	return maxi(1, int(ceil(raw)))


func set_band(new_size: int, new_morale: float = -1.0, new_readiness: float = -1.0) -> void:
	size = maxi(0, new_size)
	if new_morale >= 0.0:
		morale = clampf(new_morale, 0.0, 100.0)
	if new_readiness >= 0.0:
		readiness = clampf(new_readiness, 0.0, 100.0)
	band_changed.emit(size, morale, readiness)


func modify_morale(delta: float) -> void:
	morale = clampf(morale + delta, 0.0, 100.0)
	band_changed.emit(size, morale, readiness)


func modify_readiness(delta: float) -> void:
	readiness = clampf(readiness + delta, 0.0, 100.0)
	band_changed.emit(size, morale, readiness)


## Confidence to ambush an Anglo-Norman patrol (0..1). Recruitment UI later.
func skirmish_confidence() -> float:
	if size <= 0:
		return 0.0
	var size_factor := clampf(float(size) / 6.0, 0.0, 1.0)
	return clampf((size_factor * 0.4) + (morale / 100.0 * 0.3) + (readiness / 100.0 * 0.3), 0.0, 1.0)


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
	return true


func to_debug_dict() -> Dictionary:
	return {
		"size": size,
		"morale": morale,
		"readiness": readiness,
		"daily_cattle_cost": daily_cattle_cost(),
		"skirmish_confidence": skirmish_confidence(),
	}
