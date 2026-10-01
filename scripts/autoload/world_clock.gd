extends Node
## Living-history calendar. Major events resolve on this clock (e.g. Bannow Bay).

signal day_advanced(day: int)
signal event_triggered(event_id: StringName)

## In-game day index from the Norman landing window (1169).
var day: int = 0
## Placeholder schedule — expand into data resources later.
var scheduled_events: Dictionary = {
	0: &"bannow_bay_landing",
}


func _ready() -> void:
	pass


func advance_day(amount: int = 1) -> void:
	for _i in amount:
		day += 1
		day_advanced.emit(day)
		_resolve_events_for_day(day)


func _resolve_events_for_day(d: int) -> void:
	if scheduled_events.has(d):
		event_triggered.emit(scheduled_events[d])
