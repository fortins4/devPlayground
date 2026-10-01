extends Node
## World news bus for offscreen events and opportunity hooks.
##
## Priority + decay keep the bus useful (docs/SCOPE.md). Emit from timeline,
## honor, and faction stubs when those systems fire.

signal rumor_added(rumor_id: StringName)
signal rumor_expired(rumor_id: StringName)

const PRIORITY_LOW: int = 1
const PRIORITY_NORMAL: int = 2
const PRIORITY_HIGH: int = 3
const PRIORITY_CRITICAL: int = 4

## Active rumor dictionaries (see add_rumor).
var active_rumors: Array[Dictionary] = []


func _ready() -> void:
	if WorldClock and not WorldClock.day_advanced.is_connected(_on_day_advanced):
		WorldClock.day_advanced.connect(_on_day_advanced)


func _on_day_advanced(_day: int) -> void:
	tick_decay(1)


## Add or refresh a rumor. higher priority wins; decay_days is lifetime on the bus.
func add_rumor(
	rumor_id: StringName,
	text: String,
	source_event: StringName = &"",
	priority: int = PRIORITY_NORMAL,
	decay_days: int = 7
) -> void:
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			rumor["text"] = text
			rumor["source_event"] = source_event
			rumor["priority"] = maxi(int(rumor.get("priority", PRIORITY_NORMAL)), priority)
			rumor["decay_days"] = maxi(int(rumor.get("decay_days", decay_days)), decay_days)
			rumor["age_days"] = 0
			_sort_by_priority()
			rumor_added.emit(rumor_id)
			return
	var entry := {
		"id": rumor_id,
		"text": text,
		"source_event": source_event,
		"heard": false,
		"priority": priority,
		"decay_days": maxi(1, decay_days),
		"age_days": 0,
	}
	active_rumors.append(entry)
	_sort_by_priority()
	rumor_added.emit(rumor_id)


func mark_heard(rumor_id: StringName) -> void:
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			rumor["heard"] = true
			return


func tick_decay(days: int = 1) -> void:
	var remaining: Array[Dictionary] = []
	for rumor in active_rumors:
		rumor["age_days"] = int(rumor.get("age_days", 0)) + days
		if int(rumor.get("age_days", 0)) >= int(rumor.get("decay_days", 7)):
			rumor_expired.emit(rumor.get("id"))
		else:
			remaining.append(rumor)
	active_rumors = remaining
	_sort_by_priority()


func get_top_rumors(limit: int = 5) -> Array[Dictionary]:
	_sort_by_priority()
	var out: Array[Dictionary] = []
	for i in mini(limit, active_rumors.size()):
		out.append(active_rumors[i])
	return out


func _sort_by_priority() -> void:
	active_rumors.sort_custom(func(a, b):
		var pa := int(a.get("priority", PRIORITY_NORMAL))
		var pb := int(b.get("priority", PRIORITY_NORMAL))
		if pa == pb:
			return int(a.get("age_days", 0)) < int(b.get("age_days", 0))
		return pa > pb
	)
