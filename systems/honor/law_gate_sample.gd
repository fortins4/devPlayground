class_name LawGateSample
extends Node
## Sample gated law / dialogue path for the Leinster greybox.
##
## Demonstrates wiring Honor.can_choose_eraic / can_claim_sanctuary /
## available_law_options into a dispute beat Godot (or dialogue UI) can call.
## Not an autoload — instance under Main / ringfort / debug HUD owner.
##
## Multi-dispute authored content + unlock query live on LawDialogueSamples;
## this node remains the F5 single-dispute runner (default cattle_trespass_brehon).

signal law_option_chosen(option: StringName, result: Dictionary)
signal gates_probed(options: Array)

## Authored sample dispute (cattle trespass under Brehon custom).
## Prefer LawDialogueSamples.get_dispute(DISPUTE_ID) for full content packs.
const DISPUTE_ID := &"cattle_trespass_brehon"
const DISPUTE_PROMPT := (
	"A neighbour's herdsman swears your cattle broke his fence. "
	+ "Blood would settle it — or Brehon custom, if your enech still holds."
)

## Faction context for faction-scoped éraic checks (optional).
@export var counterparty_faction: StringName = &"local_clans"

## Optional override — cycle F5 HUD across LawDialogueSamples packs.
var active_dispute_id: StringName = DISPUTE_ID

## Last probe / resolve for UI / debug.
var last_result: Dictionary = {}


func get_dispute_id() -> StringName:
	return active_dispute_id if active_dispute_id != &"" else DISPUTE_ID


func get_dispute_prompt() -> String:
	var pack := LawDialogueSamples.get_dispute(get_dispute_id())
	if not pack.is_empty():
		return String(pack.get("prompt", DISPUTE_PROMPT))
	return DISPUTE_PROMPT


## Cycle active dispute across LawDialogueSamples (F5 HUD helper).
func cycle_dispute(delta: int = 1) -> StringName:
	var ids := LawDialogueSamples.list_dispute_ids()
	if ids.is_empty():
		active_dispute_id = DISPUTE_ID
		return active_dispute_id
	var current := get_dispute_id()
	var idx := ids.find(current)
	if idx < 0:
		idx = 0
	idx = (idx + delta) % ids.size()
	if idx < 0:
		idx = ids.size() - 1
	active_dispute_id = ids[idx]
	var pack := LawDialogueSamples.get_dispute(active_dispute_id)
	if not pack.is_empty():
		counterparty_faction = pack.get("counterparty", counterparty_faction)
	return active_dispute_id


## Snapshot of gates dialogue / UI should present right now.
func probe_gates(faction_id: StringName = &"") -> Dictionary:
	var fid := faction_id if faction_id != &"" else counterparty_faction
	var dispute_id := get_dispute_id()
	# Prefer content-pack unlock query when the dispute is authored.
	var pack := LawDialogueSamples.get_dispute(dispute_id)
	if not pack.is_empty():
		var unlocked_probe := LawDialogueSamples.query_unlocked(dispute_id, fid)
		var options: Array[StringName] = []
		for s in unlocked_probe.get("sample_options", []):
			options.append(StringName(String(s)))
		var payload := {
			"dispute_id": String(dispute_id),
			"title": String(unlocked_probe.get("title", "")),
			"prompt": get_dispute_prompt(),
			"counterparty": String(fid),
			"overall": Honor.get_honor() if Honor else -1.0,
			"church": Honor.get_honor(&"church") if Honor else -1.0,
			"faction_honor": Honor.get_honor(fid) if Honor and fid != &"" else (Honor.get_honor() if Honor else -1.0),
			"can_choose_eraic": bool((unlocked_probe.get("honor", {}) as Dictionary).get("eraic", false)),
			"can_claim_sanctuary": bool((unlocked_probe.get("honor", {}) as Dictionary).get("sanctuary", false)),
			"available_law_options": unlocked_probe.get("available_law_options", []),
			"sample_options": unlocked_probe.get("sample_options", []),
			"unlocked_line_ids": unlocked_probe.get("unlocked_line_ids", []),
			"locked_line_ids": unlocked_probe.get("locked_line_ids", []),
			"unlocked_lines": unlocked_probe.get("unlocked_lines", []),
			"lines": _lines_from_unlocked(unlocked_probe.get("unlocked_lines", [])),
			"gates_open": bool(unlocked_probe.get("gates_open", false)),
		}
		gates_probed.emit(options)
		return payload
	# Fallback: legacy single-dispute path.
	var options2: Array[StringName] = []
	var eraic_ok := Honor.can_choose_eraic(fid) if fid != &"" else Honor.can_choose_eraic()
	if eraic_ok:
		options2.append(&"eraic")
	elif Honor.can_choose_eraic():
		options2.append(&"eraic")
	if Honor.can_claim_sanctuary():
		options2.append(&"sanctuary")
	var open := Honor.available_law_options()
	var payload2 := {
		"dispute_id": String(DISPUTE_ID),
		"prompt": DISPUTE_PROMPT,
		"counterparty": String(fid),
		"overall": Honor.get_honor(),
		"church": Honor.get_honor(&"church"),
		"faction_honor": Honor.get_honor(fid) if fid != &"" else Honor.get_honor(),
		"can_choose_eraic": eraic_ok or Honor.can_choose_eraic(),
		"can_claim_sanctuary": Honor.can_claim_sanctuary(),
		"available_law_options": _names_to_strings(open),
		"sample_options": _names_to_strings(options2),
		"unlocked_line_ids": _legacy_unlocked_ids(options2),
		"lines": _dialogue_lines(options2),
	}
	gates_probed.emit(options2)
	return payload2


## Director helper — unlocked line rows for the active dispute.
func list_unlocked_lines(faction_id: StringName = &"") -> Array[Dictionary]:
	var fid := faction_id if faction_id != &"" else counterparty_faction
	return LawDialogueSamples.list_unlocked_lines(get_dispute_id(), fid)


func list_unlocked_line_ids(faction_id: StringName = &"") -> Array[StringName]:
	var fid := faction_id if faction_id != &"" else counterparty_faction
	return LawDialogueSamples.list_unlocked_line_ids(get_dispute_id(), fid)


## Attempt éraic (honor-price) path. Fails closed if gate is shut.
func choose_eraic(faction_id: StringName = &"") -> Dictionary:
	var fid := faction_id if faction_id != &"" else counterparty_faction
	var dispute_id := get_dispute_id()
	if not LawDialogueSamples.get_dispute(dispute_id).is_empty():
		var result := LawDialogueSamples.choose_option(dispute_id, &"eraic", fid)
		last_result = result
		law_option_chosen.emit(&"eraic", result)
		return result
	var allowed := Honor.can_choose_eraic(fid) if fid != &"" else Honor.can_choose_eraic()
	if not allowed and not Honor.can_choose_eraic():
		return _fail(&"eraic", "Éraic refused — enech too thin for honor-price.")
	var summary := (
		"Brehon names an éraic: cattle and silver settle the trespass. "
		+ "Blood is stayed; standing with %s holds." % String(fid)
	)
	Honor.modify_honor(2.0, fid)
	Honor.modify_honor(1.0, &"")
	return _succeed(&"eraic", summary, {
		"counterparty": String(fid),
		"honor_delta_faction": 2.0,
		"honor_delta_overall": 1.0,
	})


## Attempt monastic / Church sanctuary. Fails closed if gate is shut.
func choose_sanctuary() -> Dictionary:
	var dispute_id := get_dispute_id()
	if not LawDialogueSamples.get_dispute(dispute_id).is_empty():
		var result := LawDialogueSamples.choose_option(dispute_id, &"sanctuary", counterparty_faction)
		last_result = result
		law_option_chosen.emit(&"sanctuary", result)
		return result
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
		"dispute_id": String(get_dispute_id()),
		"counterparty": String(counterparty_faction),
		"probe": probe,
		"last_result": last_result.duplicate(true),
		"catalog": LawDialogueSamples.probe_unlocked(),
	}


func _lines_from_unlocked(unlocked: Array) -> Array:
	var lines: Array = []
	for row in unlocked:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry := {
			"speaker": String(row.get("speaker", "")),
			"text": String(row.get("text", "")),
		}
		if row.has("option"):
			entry["option"] = String(row["option"])
		if row.has("id"):
			entry["id"] = String(row["id"])
		if row.has("kind"):
			entry["kind"] = String(row["kind"])
		lines.append(entry)
	return lines


func _legacy_unlocked_ids(options: Array[StringName]) -> Array:
	var ids: Array = ["opener"]
	if &"eraic" in options:
		ids.append("option_eraic")
	if &"sanctuary" in options:
		ids.append("option_sanctuary")
	if options.is_empty():
		ids.append("closed")
	return ids


func _dialogue_lines(options: Array[StringName]) -> Array:
	var lines: Array = [
		{"speaker": "herdsman", "text": DISPUTE_PROMPT, "id": "opener", "kind": "opener"},
	]
	if &"eraic" in options:
		lines.append({
			"speaker": "player",
			"option": "eraic",
			"id": "option_eraic",
			"kind": "option",
			"text": "Name the éraic. I will pay honor-price, not blood.",
		})
	if &"sanctuary" in options:
		lines.append({
			"speaker": "player",
			"option": "sanctuary",
			"id": "option_sanctuary",
			"kind": "option",
			"text": "I claim sanctuary of the Church until this is heard.",
		})
	if options.is_empty():
		lines.append({
			"speaker": "brehon",
			"id": "closed",
			"kind": "closed",
			"text": "No lawful path opens. Raise your enech, or steel will speak.",
		})
	return lines


func _succeed(option: StringName, summary: String, extras: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"option": String(option),
		"dispute_id": String(get_dispute_id()),
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
		"dispute_id": String(get_dispute_id()),
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
