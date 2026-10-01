class_name LawDialogueSamples
extends RefCounted
## Authored honor↔law dialogue content samples for Godot / dialogue UI.
##
## Data only — no UI. Drive options through existing Honor gates:
##   Honor.can_choose_eraic / can_claim_sanctuary / available_law_options
## Runtime resolve helpers mirror LawGateSample (cattle_trespass_brehon) so
## dialogue owners can swap dispute ids without new gate logic.
##
## Schema per entry in DISPUTES:
##   id, title, counterparty, setting, prompt, speakers, options{eraic,sanctuary},
##   closed_line, honor_on_eraic{faction,overall}, honor_on_sanctuary{church}

const DISPUTES: Array[Dictionary] = [
	{
		"id": &"cattle_trespass_brehon",
		"title": "Cattle trespass",
		"counterparty": &"local_clans",
		"setting": "neighbour fence / herd boundary",
		"prompt": (
			"A neighbour's herdsman swears your cattle broke his fence. "
			+ "Blood would settle it — or Brehon custom, if your enech still holds."
		),
		"speakers": {
			"opener": "herdsman",
			"brehon": "brehon",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "Name the éraic. I will pay honor-price, not blood.",
				"success": (
					"Brehon names an éraic: cattle and silver settle the trespass. "
					+ "Blood is stayed; standing with local_clans holds."
				),
				"fail": "Éraic refused — enech too thin for honor-price.",
			},
			"sanctuary": {
				"text": "I claim sanctuary of the Church until this is heard.",
				"success": (
					"You claim monastic sanctuary. Steel stays sheathed at the precinct; "
					+ "the dispute waits on Church mediation."
				),
				"fail": "Sanctuary refused — Church and overall enech too low.",
			},
		},
		"closed_line": "No lawful path opens. Raise your enech, or steel will speak.",
		"honor_on_eraic": {"faction": 2.0, "overall": 1.0},
		"honor_on_sanctuary": {"church": 3.0},
	},
	{
		"id": &"blood_feud_mediation",
		"title": "Blood-feud mediation",
		"counterparty": &"local_clans",
		"setting": "túath assembly green",
		"prompt": (
			"Two kin-groups stand ready to spear over a kinsman's death. "
			+ "A brehon will hear éraic — or the Church will shelter the accused — "
			+ "if your standing opens either gate."
		),
		"speakers": {
			"opener": "brehon",
			"brehon": "brehon",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "Let éraic end this feud. Name the honor-price for the dead.",
				"success": (
					"Éraic is set in cattle and cumals. Spears lower; the dead man's "
					+ "kin accept price instead of blood."
				),
				"fail": "The assembly will not hear éraic from a man of thin enech.",
			},
			"sanctuary": {
				"text": "Take the accused under Church protection until tempers cool.",
				"success": (
					"The accused crosses the monastic threshold. Feud steel stays "
					+ "outside the precinct while Church terms are drafted."
				),
				"fail": "Sanctuary is denied — neither Church nor overall enech opens the gate.",
			},
		},
		"closed_line": "Without law-gates open, the green will drink blood by nightfall.",
		"honor_on_eraic": {"faction": 3.0, "overall": 2.0},
		"honor_on_sanctuary": {"church": 4.0},
	},
	{
		"id": &"norse_harbor_theft",
		"title": "Harbor theft accusation",
		"counterparty": &"norse_wexford_waterford",
		"setting": "Wexford quay / Norse warehouse",
		"prompt": (
			"A Norse factor swears your band lifted silver from a bonded chest. "
			+ "Harbor custom allows honor-price — or you may claim sanctuary on the "
			+ "church hill above the town."
		),
		"speakers": {
			"opener": "norse_factor",
			"brehon": "harbor_brehon",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "I offer éraic for the chest. Count the price; spare the axe.",
				"success": (
					"Harbor éraic is weighed in silver and cattle. The factor stands "
					+ "down; Norse attitude softens a notch."
				),
				"fail": "The factor sneers — your enech will not buy harbor peace.",
			},
			"sanctuary": {
				"text": "I claim Church sanctuary until a brehon hears this on holy ground.",
				"success": (
					"You reach the church hill. Norse blades halt at the precinct; "
					+ "Church mediation is promised at dawn."
				),
				"fail": "Sanctuary refused — climb the hill with better standing, or face the quay.",
			},
		},
		"closed_line": "No law opens. The quay will settle this with iron.",
		"honor_on_eraic": {"faction": 2.5, "overall": 1.5},
		"honor_on_sanctuary": {"church": 3.0},
	},
	{
		"id": &"hospitality_breach",
		"title": "Hospitality breach",
		"counterparty": &"ui_chennselaig",
		"setting": "ringfort guest-hall",
		"prompt": (
			"A Uí Chennselaig retainer says you broke guest-right — steel drawn "
			+ "under a host's roof. Brehon éraic can mend it; Church sanctuary "
			+ "can pause the demand for blood."
		),
		"speakers": {
			"opener": "retainer",
			"brehon": "brehon",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "I will pay éraic for the breach of hospitality.",
				"success": (
					"Éraic restores guest-right. The retainer sheathes; Diarmait's "
					+ "people note that you honor the hall."
				),
				"fail": "Hospitality éraic is refused — your enech does not open that door.",
			},
			"sanctuary": {
				"text": "I claim sanctuary until the Church and a brehon hear the hall's complaint.",
				"success": (
					"Sanctuary is granted. Blood-debt waits outside the precinct while "
					+ "terms are spoken."
				),
				"fail": "Sanctuary will not cover a hospitality breach with standing this low.",
			},
		},
		"closed_line": "Guest-right broken, law shut — only steel answers now.",
		"honor_on_eraic": {"faction": 3.0, "overall": 2.0},
		"honor_on_sanctuary": {"church": 2.5},
	},
]


static func list_dispute_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for row in DISPUTES:
		ids.append(row["id"] as StringName)
	return ids


static func get_dispute(dispute_id: StringName) -> Dictionary:
	for row in DISPUTES:
		if row["id"] == dispute_id:
			return row.duplicate(true)
	return {}


## Snapshot dialogue lines for a dispute using live Honor gates.
## Returns a payload Godot dialogue UI can consume directly.
static func build_dialogue(dispute_id: StringName, faction_id: StringName = &"") -> Dictionary:
	var dispute := get_dispute(dispute_id)
	if dispute.is_empty():
		return {"ok": false, "reason": &"unknown_dispute", "dispute_id": String(dispute_id)}
	var fid: StringName = faction_id if faction_id != &"" else dispute.get("counterparty", &"")
	var open: Array[StringName] = []
	if Honor:
		var eraic_ok := Honor.can_choose_eraic(fid) if fid != &"" else Honor.can_choose_eraic()
		if eraic_ok or Honor.can_choose_eraic():
			open.append(&"eraic")
		if Honor.can_claim_sanctuary():
			open.append(&"sanctuary")
	var lines: Array = _dialogue_lines(dispute, open)
	return {
		"ok": true,
		"dispute_id": String(dispute["id"]),
		"title": String(dispute.get("title", "")),
		"setting": String(dispute.get("setting", "")),
		"counterparty": String(fid),
		"prompt": String(dispute.get("prompt", "")),
		"available_law_options": _names_to_strings(Honor.available_law_options() if Honor else []),
		"sample_options": _names_to_strings(open),
		"lines": lines,
		"gates_open": not open.is_empty(),
	}


## Attempt a gated option for a dispute. Fails closed when the Honor gate is shut.
static func choose_option(
	dispute_id: StringName,
	option: StringName,
	faction_id: StringName = &""
) -> Dictionary:
	var dispute := get_dispute(dispute_id)
	if dispute.is_empty():
		return _fail(dispute_id, option, "Unknown dispute: %s" % String(dispute_id))
	var fid: StringName = faction_id if faction_id != &"" else dispute.get("counterparty", &"")
	var opts: Dictionary = dispute.get("options", {})
	if not opts.has(String(option)) and not opts.has(option):
		return _fail(dispute_id, option, "Unknown law option: %s" % String(option))
	var opt_row: Dictionary = opts.get(option, opts.get(String(option), {}))
	match option:
		&"eraic":
			var allowed := true
			if Honor:
				allowed = Honor.can_choose_eraic(fid) if fid != &"" else Honor.can_choose_eraic()
				if not allowed and not Honor.can_choose_eraic():
					return _fail(dispute_id, option, String(opt_row.get("fail", "Éraic refused.")))
			var honor_cfg: Dictionary = dispute.get("honor_on_eraic", {})
			if Honor:
				Honor.modify_honor(float(honor_cfg.get("faction", 2.0)), fid)
				Honor.modify_honor(float(honor_cfg.get("overall", 1.0)), &"")
			return _succeed(dispute_id, option, String(opt_row.get("success", "")), {
				"counterparty": String(fid),
				"honor_delta_faction": float(honor_cfg.get("faction", 2.0)),
				"honor_delta_overall": float(honor_cfg.get("overall", 1.0)),
			})
		&"sanctuary":
			if Honor and not Honor.can_claim_sanctuary():
				return _fail(dispute_id, option, String(opt_row.get("fail", "Sanctuary refused.")))
			var church_cfg: Dictionary = dispute.get("honor_on_sanctuary", {})
			if Honor:
				Honor.modify_honor(float(church_cfg.get("church", 3.0)), &"church")
			return _succeed(dispute_id, option, String(opt_row.get("success", "")), {
				"honor_delta_church": float(church_cfg.get("church", 3.0)),
			})
		_:
			return _fail(dispute_id, option, "Unknown law option: %s" % String(option))


static func to_debug_dict() -> Dictionary:
	var ids: Array = []
	for id in list_dispute_ids():
		ids.append(String(id))
	return {
		"dispute_count": DISPUTES.size(),
		"dispute_ids": ids,
		"gate_api": ["Honor.can_choose_eraic", "Honor.can_claim_sanctuary", "Honor.available_law_options"],
	}


static func _dialogue_lines(dispute: Dictionary, options: Array[StringName]) -> Array:
	var speakers: Dictionary = dispute.get("speakers", {})
	var opener := String(speakers.get("opener", "speaker"))
	var lines: Array = [
		{"speaker": opener, "text": String(dispute.get("prompt", ""))},
	]
	var opts: Dictionary = dispute.get("options", {})
	if &"eraic" in options:
		var eraic: Dictionary = opts.get(&"eraic", opts.get("eraic", {}))
		lines.append({
			"speaker": String(speakers.get("player", "player")),
			"option": "eraic",
			"text": String(eraic.get("text", "Offer éraic.")),
		})
	if &"sanctuary" in options:
		var sanctuary: Dictionary = opts.get(&"sanctuary", opts.get("sanctuary", {}))
		lines.append({
			"speaker": String(speakers.get("player", "player")),
			"option": "sanctuary",
			"text": String(sanctuary.get("text", "Claim sanctuary.")),
		})
	if options.is_empty():
		lines.append({
			"speaker": String(speakers.get("brehon", "brehon")),
			"text": String(dispute.get("closed_line", "No lawful path opens.")),
		})
	return lines


static func _succeed(
	dispute_id: StringName,
	option: StringName,
	summary: String,
	extras: Dictionary = {}
) -> Dictionary:
	var result := {
		"ok": true,
		"option": String(option),
		"dispute_id": String(dispute_id),
		"summary": summary,
	}
	for k in extras.keys():
		result[k] = extras[k]
	if Honor:
		Honor.last_law_result = result.duplicate(true)
	return result


static func _fail(dispute_id: StringName, option: StringName, summary: String) -> Dictionary:
	var open: Array = []
	if Honor:
		open = _names_to_strings(Honor.available_law_options())
	var result := {
		"ok": false,
		"option": String(option),
		"dispute_id": String(dispute_id),
		"summary": summary,
		"available_law_options": open,
	}
	if Honor:
		Honor.last_law_result = result.duplicate(true)
	return result


static func _names_to_strings(names: Array) -> Array:
	var out: Array = []
	for n in names:
		out.append(String(n))
	return out
