extends Node
## Spreads news of offscreen timeline events and opportunities.

signal rumor_added(rumor_id: StringName)

var active_rumors: Array[Dictionary] = []


func add_rumor(rumor_id: StringName, text: String, source_event: StringName = &"") -> void:
	var entry := {
		"id": rumor_id,
		"text": text,
		"source_event": source_event,
		"heard": false,
	}
	active_rumors.append(entry)
	rumor_added.emit(rumor_id)


func mark_heard(rumor_id: StringName) -> void:
	for rumor in active_rumors:
		if rumor.get("id") == rumor_id:
			rumor["heard"] = true
			return
