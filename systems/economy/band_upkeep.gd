class_name BandUpkeep
extends RefCounted
## Band size / morale / readiness + cattle upkeep for later recruitment.
##
## Systems data only — no UI. CattleEconomy (or ringfort owner) pays via
## `apply_daily_upkeep(economy)`. Ambush confidence: `skirmish_confidence()`.

signal band_changed(size: int, morale: float, readiness: float)
signal upkeep_failed(shortfall_cattle: int)
signal warrior_recruited(new_size: int)
signal warrior_dismissed(new_size: int)

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


func to_debug_dict() -> Dictionary:
	return {
		"size": size,
		"max_size": max_size,
		"morale": morale,
		"readiness": readiness,
		"daily_cattle_cost": daily_cattle_cost(),
		"skirmish_confidence": skirmish_confidence(),
		"can_attempt_skirmish": can_attempt_skirmish(),
	}
