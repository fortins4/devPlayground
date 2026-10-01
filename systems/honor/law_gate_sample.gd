class_name LawGateSample
extends Node
## Sample gated law / dialogue path for the Leinster greybox.
##
## Demonstrates wiring Honor.can_choose_eraic / can_claim_sanctuary /
## available_law_options into a dispute beat Godot (or dialogue UI) can call.
## Not an autoload — instance under Main / ringfort / debug HUD owner.

signal law_option_chosen(option: StringName, result: Dictionary)
signal gates_probed(options: Array)

## Authored sample dispute (cattle trespass under Brehon custom).
const DISPUTE_ID := &"cattle_trespass_brehon"
const DISPUTE_PROMPT := (
	"A neighbour's herdsman swears your cattle broke his fence. "
	+ "Blood would settle it — or Brehon custom, if your enech still holds."
)

## Faction context for faction-scoped éraic checks (optional).
@export var counterparty_faction: StringName = &"local_clans"

## Last probe / resolve for UI / debug.
var last_result: Dictionary = {}


func get_dispute_id() -> StringName:
	return DISPUTE_ID


func get_dispute_prompt() -> String:
	return DISPUTE_PROMPT


## Snapshot of gates dialogue / UI should present right now.
func probe_gates(faction_id: StringName = &"") -> Dictionary:
	var fid := faction_id if faction_id != &"" else counterparty_faction
	var options: Array[StringName] = []
	# Prefer faction-scoped éraic when a counterparty is known.
	var eraic_ok := Honor.can_choose_eraic(fid) if fid != &"" else Honor.can_choose_eraic()
	if eraic_ok:
		options.append(&"eraic")
	elif Honor.can_choose_eraic():
		# Overall still allows generic éraic even if faction standing is thin.
		options.append(&"eraic")
	if Honor.can_claim_sanctuary():
		options.append(&"sanctuary")
	# Always expose the open list from the autoload for UI parity.
	var open := Honor.available_law_options()
	var payload := {
		"dispute_id": String(DISPUTE_ID),
		"prompt": DISPUTE_PROMPT,
		"counterparty": String(fid),
		"overall": Honor.get_honor(),
		"church": Honor.get_honor(&"church"),
		"faction_honor": Honor.get_honor(fid) if fid != &"" else Honor.get_honor(),
		"can_choose_eraic": eraic_ok or Honor.can_choose_eraic(),
		"can_claim_sanctuary": Honor.can_claim_sanctuary(),
		"available_law_options": _names_to_strings(open),
		"sample_options": _names_to_strings(options),
		"lines": _dialogue_lines(options),
	}
	gates_probed.emit(options)
	return payload


## Attempt éraic (honor-price) path. Fails closed if gate is shut.
func choose_eraic(faction_id: StringName = &"") -> Dictionary:
	var fid := faction_id if faction_id != &"" else counterparty_faction
	var allowed := Honor.can_choose_eraic(fid) if fid != &"" else Honor.can_choose_eraic()
	if not allowed and not Honor.can_choose_eraic():
		return _fail(&"eraic", "Éraic refused — enech too thin for honor-price.")
	var summary := (
		"Brehon names an éraic: cattle and silver settle the trespass. "
		+ "Blood is stayed; standing with %s holds." % String(fid)
	)
	# Small positive ripple — paying éraic honors the law.
	Honor.modify_honor(2.0, fid)
	Honor.modify_honor(1.0, &"")
	return _succeed(&"eraic", summary, {
		"counterparty": String(fid),
		"honor_delta_faction": 2.0,
		"honor_delta_overall": 1.0,
	})


## Attempt monastic / Church sanctuary. Fails closed if gate is shut.
func choose_sanctuary() -> Dictionary:
	if not Honor.can_claim_sanctuary():
		return _fail(&"sanctuary", "Sanctuary refused — Church and overall enech too low.")
	var summary := (
		"You claim monastic sanctuary. Steel stays sheathed at the precinct; "
		+ "the dispute waits on Church mediation."
	)
	Honor.modify_honor(3.0, &"church")
	return _succeed(&"sanctuary", summary, {
		"honor_delta_church": 3.0,
	})


## Dialogue helper: pick one open option by id (&"eraic" / &"sanctuary").
func choose_option(option: StringName, faction_id: StringName = &"") -> Dictionary:
	match option:
		&"eraic":
			return choose_eraic(faction_id)
		&"sanctuary":
			return choose_sanctuary()
		_:
			return _fail(option, "Unknown law option: %s" % String(option))


func to_debug_dict() -> Dictionary:
	var probe := probe_gates()
	return {
		"dispute_id": String(DISPUTE_ID),
		"counterparty": String(counterparty_faction),
		"probe": probe,
		"last_result": last_result.duplicate(true),
	}


func _dialogue_lines(options: Array[StringName]) -> Array:
	var lines: Array = [
		{"speaker": "herdsman", "text": DISPUTE_PROMPT},
	]
	if &"eraic" in options:
		lines.append({
			"speaker": "player",
			"option": "eraic",
			"text": "Name the éraic. I will pay honor-price, not blood.",
		})
	if &"sanctuary" in options:
		lines.append({
			"speaker": "player",
			"option": "sanctuary",
			"text": "I claim sanctuary of the Church until this is heard.",
		})
	if options.is_empty():
		lines.append({
			"speaker": "brehon",
			"text": "No lawful path opens. Raise your enech, or steel will speak.",
		})
	return lines


func _succeed(option: StringName, summary: String, extras: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"option": String(option),
		"dispute_id": String(DISPUTE_ID),
		"summary": summary,
	}
	for k in extras.keys():
		result[k] = extras[k]
	last_result = result
	if Honor:
		Honor.last_law_result = result.duplicate(true)
	law_option_chosen.emit(option, result)
	return result


func _fail(option: StringName, summary: String) -> Dictionary:
	var result := {
		"ok": false,
		"option": String(option),
		"dispute_id": String(DISPUTE_ID),
		"summary": summary,
		"available_law_options": _names_to_strings(Honor.available_law_options()),
	}
	last_result = result
	if Honor:
		Honor.last_law_result = result.duplicate(true)
	law_option_chosen.emit(option, result)
	return result


func _names_to_strings(names: Array) -> Array:
	var out: Array = []
	for n in names:
		out.append(String(n))
	return out
