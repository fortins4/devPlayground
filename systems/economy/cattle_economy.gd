extends Node
## Cattle as primary currency. Stub inventory for raids and ringfort upkeep.

signal herd_changed(count: int)

var herd_size: int = 0
var trade_goods: Dictionary = {}


func add_cattle(amount: int) -> void:
	herd_size = maxi(0, herd_size + amount)
	herd_changed.emit(herd_size)


func spend_cattle(amount: int) -> bool:
	if herd_size < amount:
		return false
	herd_size -= amount
	herd_changed.emit(herd_size)
	return true
