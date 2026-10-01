class_name LawDialogueSamples
extends RefCounted
## Authored honor↔law dialogue content samples for Godot / dialogue UI.
##
## Data only — no UI. Drive options through existing Honor gates:
##   Honor.can_choose_eraic / can_claim_sanctuary / available_law_options
## Director-facing unlock query:
##   list_unlocked_lines / list_unlocked_line_ids / query_unlocked / probe_unlocked
## Runtime resolve helpers mirror LawGateSample so dialogue owners can swap
## dispute ids without new gate logic.
##
## Schema per entry in DISPUTES:
##   id, title, counterparty, setting, prompt, speakers, options{eraic,sanctuary},
##   closed_line, honor_on_eraic{faction,overall}, honor_on_sanctuary{church},
##   flavor[] — optional threshold-gated lines (see _flavor_unlocked).

## Honor floors for optional flavor lines (tune with content; not law gates).
const FLAVOR_ESTEEM_MIN: float = 70.0
const FLAVOR_CONTEMPT_MAX: float = 35.0

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
		"flavor": [
			{
				"id": &"herdsman_esteem",
				"speaker": "herdsman",
				"text": (
					"Your name still carries weight on this fence-line. "
					+ "Speak law, lord — we would rather hear price than steel."
				),
				"gate": {"kind": &"faction_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"herdsman_contempt",
				"speaker": "herdsman",
				"text": (
					"Thin enech, thinner fence-manners. Pay blood-price if you can — "
					+ "else the green will settle this."
				),
				"gate": {"kind": &"faction_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
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
		"flavor": [
			{
				"id": &"assembly_esteem",
				"speaker": "brehon",
				"text": (
					"The túath will hear you. High enech buys patience on this green."
				),
				"gate": {"kind": &"overall_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"assembly_contempt",
				"speaker": "kin_elder",
				"text": (
					"Who is this thin-faced stranger to name price for our dead?"
				),
				"gate": {"kind": &"overall_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
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
		"flavor": [
			{
				"id": &"factor_esteem",
				"speaker": "norse_factor",
				"text": (
					"Your standing on this quay is known. Name price fair and we trade words, not axes."
				),
				"gate": {"kind": &"faction_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"factor_contempt",
				"speaker": "norse_factor",
				"text": (
					"A landless name and sticky fingers. Pay or bleed — harbor law is thin for the like of you."
				),
				"gate": {"kind": &"faction_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
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
		"flavor": [
			{
				"id": &"hall_esteem",
				"speaker": "retainer",
				"text": (
					"Diarmait's hall still names you with respect. Mend this with price, not pride."
				),
				"gate": {"kind": &"faction_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"hall_contempt",
				"speaker": "retainer",
				"text": (
					"Guest-right broken by a man of no standing — the hall remembers such insults."
				),
				"gate": {"kind": &"faction_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
	},
	{
		"id": &"church_tithe_arrears",
		"title": "Church tithe arrears",
		"counterparty": &"church",
		"setting": "monastery garth / tithe barn",
		"prompt": (
			"A monastic steward says your túath owes tithe cattle in arrears. "
			+ "Éraic can clear the debt under Brehon custom — or you may claim "
			+ "sanctuary inside the precinct while terms are written."
		),
		"speakers": {
			"opener": "steward",
			"brehon": "brehon",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "I will settle the tithe as éraic — name the cattle and cumals.",
				"success": (
					"Tithe arrears are weighed as éraic. The steward marks the debt paid; "
					+ "Church standing rises."
				),
				"fail": "The steward will not take éraic from thin enech — bring standing, or cattle under guard.",
			},
			"sanctuary": {
				"text": "I claim sanctuary in this house until the tithe is heard fairly.",
				"success": (
					"You cross the garth threshold. Collection waits; Church scribes draft "
					+ "a schedule of payment."
				),
				"fail": "Sanctuary refused — this house will not shelter a debtor of such standing.",
			},
		},
		"closed_line": "Tithe unpaid, gates shut — the barn locks and word goes to the abbot.",
		"honor_on_eraic": {"faction": 3.5, "overall": 1.5},
		"honor_on_sanctuary": {"church": 4.0},
		"flavor": [
			{
				"id": &"steward_esteem",
				"speaker": "steward",
				"text": (
					"Your gifts to this house are remembered. Let us name a fair price and keep peace."
				),
				"gate": {"kind": &"church_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"steward_contempt",
				"speaker": "steward",
				"text": (
					"A name the abbot barely knows, and cattle still owed. Do not waste holy ground."
				),
				"gate": {"kind": &"church_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
	},
	{
		"id": &"norman_safe_conduct",
		"title": "Norman safe-conduct dispute",
		"counterparty": &"anglo_normans",
		"setting": "Bannow camp / march road",
		"prompt": (
			"A Norman sergeant swears you broke a safe-conduct on the march road — "
			+ "a retainer cut, a banner slighted. Harbor-style honor-price may mend it, "
			+ "or Church sanctuary can hold steel until a hearing."
		),
		"speakers": {
			"opener": "sergeant",
			"brehon": "camp_clerk",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "I offer éraic for the broken conduct. Name the price in cattle and silver.",
				"success": (
					"Camp éraic is set. The sergeant stands down; Anglo-Norman attitude "
					+ "eases a notch on the road."
				),
				"fail": "Safe-conduct éraic refused — your enech buys no peace in this camp.",
			},
			"sanctuary": {
				"text": "I claim Church sanctuary until this conduct dispute is heard.",
				"success": (
					"You reach the camp chapel precinct. Norman steel waits outside while "
					+ "clerks draft terms."
				),
				"fail": "Sanctuary denied — raise Church or overall standing before you claim the chapel.",
			},
		},
		"closed_line": "Conduct broken, law shut — the march road answers with spears.",
		"honor_on_eraic": {"faction": 2.0, "overall": 1.5},
		"honor_on_sanctuary": {"church": 3.0},
		"flavor": [
			{
				"id": &"sergeant_esteem",
				"speaker": "sergeant",
				"text": (
					"Word of your enech reached the camp. Speak price cleanly and we may yet keep the road open."
				),
				"gate": {"kind": &"faction_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"sergeant_contempt",
				"speaker": "sergeant",
				"text": (
					"A man of no standing breaking our conduct — the knights will want blood, not talk."
				),
				"gate": {"kind": &"faction_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
	},
	{
		"id": &"fian_cattle_reave",
		"title": "Fían cattle-reave charge",
		"counterparty": &"fian",
		"setting": "woodland bothy / cattle path",
		"prompt": (
			"A fían captain says your spears lifted their reaved herd on the cattle path. "
			+ "Among outlaws, éraic is rare but known — or you may run for Church "
			+ "sanctuary before the bothy closes ranks."
		),
		"speakers": {
			"opener": "fian_captain",
			"brehon": "hedge_brehon",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "I name éraic for the herd. Take cattle-price; leave the feud.",
				"success": (
					"Even fían take price when enech is thick enough. Spears lower; "
					+ "the bothy marks the debt paid."
				),
				"fail": "The captain laughs — thin enech buys no peace among the fían.",
			},
			"sanctuary": {
				"text": "I claim Church sanctuary until a brehon hears this reave charge.",
				"success": (
					"You reach holy ground. Fían hunters halt at the precinct edge; "
					+ "mediation is promised."
				),
				"fail": "Sanctuary will not open for you — Church and overall standing are too low.",
			},
		},
		"closed_line": "No law among these trees. The bothy will hunt you at dusk.",
		"honor_on_eraic": {"faction": 2.0, "overall": 2.0},
		"honor_on_sanctuary": {"church": 3.5},
		"flavor": [
			{
				"id": &"captain_esteem",
				"speaker": "fian_captain",
				"text": (
					"Even wolves know a high name. Speak price — we prefer cattle to a famous corpse."
				),
				"gate": {"kind": &"overall_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"captain_contempt",
				"speaker": "fian_captain",
				"text": (
					"Nobody. No price. The path remembers thieves with thin faces."
				),
				"gate": {"kind": &"overall_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
	},
	{
		"id": &"dublin_market_slight",
		"title": "Dublin market slight",
		"counterparty": &"norse_dublin",
		"setting": "Dublin thing-mound / market stalls",
		"prompt": (
			"A Dublin factor claims your band slighted a bonded stall — goods spilled, "
			+ "honor stained. Thing custom allows éraic; the Christ-church hill offers "
			+ "sanctuary if your standing opens the gate."
		),
		"speakers": {
			"opener": "dublin_factor",
			"brehon": "thing_speaker",
			"player": "player",
		},
		"options": {
			"eraic": {
				"text": "I offer éraic for the market slight. Weigh the damage; spare the feud.",
				"success": (
					"Thing éraic is counted in silver and cloth. The factor nods; "
					+ "Dublin standing recovers a step."
				),
				"fail": "The thing will not hear éraic from a man of such thin enech.",
			},
			"sanctuary": {
				"text": "I claim sanctuary on the church hill until this slight is heard.",
				"success": (
					"You reach Christ-church ground. Market steel waits; clerks promise a hearing."
				),
				"fail": "Sanctuary refused — Dublin's church hill wants better standing.",
			},
		},
		"closed_line": "Market slight unanswered, law shut — the stalls will answer with knives.",
		"honor_on_eraic": {"faction": 2.5, "overall": 1.0},
		"honor_on_sanctuary": {"church": 3.0},
		"flavor": [
			{
				"id": &"dublin_esteem",
				"speaker": "dublin_factor",
				"text": (
					"Your name still buys credit at these stalls. Name a clean price and we reopen trade."
				),
				"gate": {"kind": &"faction_min", "min": FLAVOR_ESTEEM_MIN},
			},
			{
				"id": &"dublin_contempt",
				"speaker": "dublin_factor",
				"text": (
					"Spill our goods and offer nothing but a beggar's face? The thing has heard enough."
				),
				"gate": {"kind": &"faction_max", "max": FLAVOR_CONTEMPT_MAX},
			},
		],
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


## Open law option ids for a dispute under live Honor gates (&"eraic", &"sanctuary").
static func list_open_options(dispute_id: StringName, faction_id: StringName = &"") -> Array[StringName]:
	var dispute := get_dispute(dispute_id)
	if dispute.is_empty():
		return []
	var fid: StringName = faction_id if faction_id != &"" else dispute.get("counterparty", &"")
	return _open_options_for(fid)


## Which dialogue lines unlock right now (opener, flavor, options, or closed).
## Each row: id, speaker, text, kind, unlocked=true, optional option / gate_kind.
static func list_unlocked_lines(
	dispute_id: StringName,
	faction_id: StringName = &""
) -> Array[Dictionary]:
	var dispute := get_dispute(dispute_id)
	if dispute.is_empty():
		return []
	var fid: StringName = faction_id if faction_id != &"" else dispute.get("counterparty", &"")
	var open := _open_options_for(fid)
	return _collect_unlocked_lines(dispute, open, fid)


## Convenience: unlocked line ids only (director filter / UI keys).
static func list_unlocked_line_ids(
	dispute_id: StringName,
	faction_id: StringName = &""
) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row in list_unlocked_lines(dispute_id, faction_id):
		ids.append(row["id"] as StringName)
	return ids


## Director / remote probe: unlocked lines for one dispute, or a catalog of all.
## dispute_id empty → every dispute summarized under current Honor.
static func query_unlocked(
	dispute_id: StringName = &"",
	faction_id: StringName = &""
) -> Dictionary:
	var honor_snap := _honor_snapshot()
	if dispute_id != &"":
		var dispute := get_dispute(dispute_id)
		if dispute.is_empty():
			return {
				"ok": false,
				"reason": &"unknown_dispute",
				"dispute_id": String(dispute_id),
				"honor": honor_snap,
			}
		var fid: StringName = faction_id if faction_id != &"" else dispute.get("counterparty", &"")
		var open := _open_options_for(fid)
		var unlocked := _collect_unlocked_lines(dispute, open, fid)
		return {
			"ok": true,
			"dispute_id": String(dispute["id"]),
			"title": String(dispute.get("title", "")),
			"setting": String(dispute.get("setting", "")),
			"counterparty": String(fid),
			"honor": honor_snap,
			"available_law_options": _names_to_strings(Honor.available_law_options() if Honor else []),
			"sample_options": _names_to_strings(open),
			"gates_open": not open.is_empty(),
			"unlocked_line_ids": _line_ids(unlocked),
			"unlocked_lines": unlocked,
			"locked_line_ids": _locked_line_ids(dispute, unlocked),
		}
	# Catalog all disputes.
	var rows: Array = []
	for id in list_dispute_ids():
		var d := get_dispute(id)
		var fid2: StringName = faction_id if faction_id != &"" else d.get("counterparty", &"")
		var open2 := _open_options_for(fid2)
		var unlocked2 := _collect_unlocked_lines(d, open2, fid2)
		rows.append({
			"dispute_id": String(id),
			"title": String(d.get("title", "")),
			"counterparty": String(fid2),
			"sample_options": _names_to_strings(open2),
			"gates_open": not open2.is_empty(),
			"unlocked_line_ids": _line_ids(unlocked2),
			"unlocked_count": unlocked2.size(),
		})
	return {
		"ok": true,
		"dispute_count": DISPUTES.size(),
		"honor": honor_snap,
		"available_law_options": _names_to_strings(Honor.available_law_options() if Honor else []),
		"disputes": rows,
		"api": [
			"list_unlocked_lines",
			"list_unlocked_line_ids",
			"query_unlocked",
			"probe_unlocked",
			"list_open_options",
			"build_dialogue",
			"choose_option",
		],
	}


## Alias for F5 / remote docs — same payload as query_unlocked.
static func probe_unlocked(
	dispute_id: StringName = &"",
	faction_id: StringName = &""
) -> Dictionary:
	return query_unlocked(dispute_id, faction_id)


## Snapshot dialogue lines for a dispute using live Honor gates.
## Returns a payload Godot dialogue UI can consume directly (includes unlock ids).
static func build_dialogue(dispute_id: StringName, faction_id: StringName = &"") -> Dictionary:
	var dispute := get_dispute(dispute_id)
	if dispute.is_empty():
		return {"ok": false, "reason": &"unknown_dispute", "dispute_id": String(dispute_id)}
	var fid: StringName = faction_id if faction_id != &"" else dispute.get("counterparty", &"")
	var open := _open_options_for(fid)
	var unlocked := _collect_unlocked_lines(dispute, open, fid)
	var lines: Array = []
	for row in unlocked:
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
	return {
		"ok": true,
		"dispute_id": String(dispute["id"]),
		"title": String(dispute.get("title", "")),
		"setting": String(dispute.get("setting", "")),
		"counterparty": String(fid),
		"prompt": String(dispute.get("prompt", "")),
		"available_law_options": _names_to_strings(Honor.available_law_options() if Honor else []),
		"sample_options": _names_to_strings(open),
		"unlocked_line_ids": _line_ids(unlocked),
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
	var catalog := query_unlocked()
	return {
		"dispute_count": DISPUTES.size(),
		"dispute_ids": ids,
		"flavor_esteem_min": FLAVOR_ESTEEM_MIN,
		"flavor_contempt_max": FLAVOR_CONTEMPT_MAX,
		"gate_api": [
			"Honor.can_choose_eraic",
			"Honor.can_claim_sanctuary",
			"Honor.available_law_options",
		],
		"unlock_api": [
			"list_unlocked_lines",
			"list_unlocked_line_ids",
			"query_unlocked",
			"probe_unlocked",
			"list_open_options",
		],
		"catalog": catalog,
	}


static func get_debug_text() -> String:
	var catalog := query_unlocked()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Honor↔law dialogue samples ===")
	lines.append(
		"Disputes: %d   Open law: %s" % [
			int(catalog.get("dispute_count", 0)),
			", ".join(PackedStringArray(catalog.get("available_law_options", []))),
		]
	)
	var honor: Dictionary = catalog.get("honor", {})
	lines.append(
		"Honor overall=%.1f church=%.1f" % [
			float(honor.get("overall", -1.0)),
			float(honor.get("church", -1.0)),
		]
	)
	for row in catalog.get("disputes", []):
		var opts: Array = row.get("sample_options", [])
		var unlocked: Array = row.get("unlocked_line_ids", [])
		lines.append(
			"- %s [%s] gates=%s unlocked=%s" % [
				String(row.get("dispute_id", "")),
				String(row.get("counterparty", "")),
				(", ".join(PackedStringArray(opts)) if not opts.is_empty() else "none"),
				(", ".join(PackedStringArray(unlocked)) if not unlocked.is_empty() else "none"),
			]
		)
	lines.append("Remote: LawDialogueSamples.probe_unlocked() / .probe_unlocked(&\"id\")")
	return "\n".join(lines)


# --- internals ---------------------------------------------------------------

static func _open_options_for(faction_id: StringName) -> Array[StringName]:
	var open: Array[StringName] = []
	if Honor == null:
		return open
	var eraic_ok := Honor.can_choose_eraic(faction_id) if faction_id != &"" else Honor.can_choose_eraic()
	if eraic_ok or Honor.can_choose_eraic():
		open.append(&"eraic")
	if Honor.can_claim_sanctuary():
		open.append(&"sanctuary")
	return open


static func _collect_unlocked_lines(
	dispute: Dictionary,
	options: Array[StringName],
	faction_id: StringName
) -> Array[Dictionary]:
	var speakers: Dictionary = dispute.get("speakers", {})
	var unlocked: Array[Dictionary] = []
	# Opener always available.
	unlocked.append({
		"id": &"opener",
		"speaker": String(speakers.get("opener", "speaker")),
		"text": String(dispute.get("prompt", "")),
		"kind": &"opener",
		"unlocked": true,
	})
	# Threshold flavor (esteem / contempt) — mutually filtered by gate.
	for flavor in dispute.get("flavor", []):
		if typeof(flavor) != TYPE_DICTIONARY:
			continue
		var gate: Dictionary = flavor.get("gate", {})
		if _flavor_unlocked(gate, faction_id):
			unlocked.append({
				"id": flavor.get("id", &"flavor"),
				"speaker": String(flavor.get("speaker", speakers.get("opener", "speaker"))),
				"text": String(flavor.get("text", "")),
				"kind": &"flavor",
				"gate_kind": gate.get("kind", &""),
				"unlocked": true,
			})
	var opts: Dictionary = dispute.get("options", {})
	if &"eraic" in options:
		var eraic: Dictionary = opts.get(&"eraic", opts.get("eraic", {}))
		unlocked.append({
			"id": &"option_eraic",
			"speaker": String(speakers.get("player", "player")),
			"option": &"eraic",
			"text": String(eraic.get("text", "Offer éraic.")),
			"kind": &"option",
			"unlocked": true,
		})
	if &"sanctuary" in options:
		var sanctuary: Dictionary = opts.get(&"sanctuary", opts.get("sanctuary", {}))
		unlocked.append({
			"id": &"option_sanctuary",
			"speaker": String(speakers.get("player", "player")),
			"option": &"sanctuary",
			"text": String(sanctuary.get("text", "Claim sanctuary.")),
			"kind": &"option",
			"unlocked": true,
		})
	if options.is_empty():
		unlocked.append({
			"id": &"closed",
			"speaker": String(speakers.get("brehon", "brehon")),
			"text": String(dispute.get("closed_line", "No lawful path opens.")),
			"kind": &"closed",
			"unlocked": true,
		})
	return unlocked


static func _flavor_unlocked(gate: Dictionary, faction_id: StringName) -> bool:
	if gate.is_empty():
		return true
	if Honor == null:
		return false
	var kind: StringName = gate.get("kind", &"")
	match kind:
		&"overall_min":
			return Honor.get_honor() >= float(gate.get("min", FLAVOR_ESTEEM_MIN))
		&"overall_max":
			return Honor.get_honor() <= float(gate.get("max", FLAVOR_CONTEMPT_MAX))
		&"faction_min":
			var fid := faction_id if faction_id != &"" else &""
			return Honor.get_honor(fid) >= float(gate.get("min", FLAVOR_ESTEEM_MIN))
		&"faction_max":
			var fid2 := faction_id if faction_id != &"" else &""
			return Honor.get_honor(fid2) <= float(gate.get("max", FLAVOR_CONTEMPT_MAX))
		&"church_min":
			return Honor.get_honor(&"church") >= float(gate.get("min", FLAVOR_ESTEEM_MIN))
		&"church_max":
			return Honor.get_honor(&"church") <= float(gate.get("max", FLAVOR_CONTEMPT_MAX))
		&"always":
			return true
		_:
			return false


static func _honor_snapshot() -> Dictionary:
	if Honor == null:
		return {"overall": -1.0, "church": -1.0, "eraic": false, "sanctuary": false}
	return {
		"overall": Honor.get_honor(),
		"church": Honor.get_honor(&"church"),
		"eraic": Honor.can_choose_eraic(),
		"sanctuary": Honor.can_claim_sanctuary(),
		"eraic_min": Honor.ERAIC_MIN_OVERALL,
		"sanctuary_min_church": Honor.SANCTUARY_MIN_CHURCH,
		"sanctuary_min_overall": Honor.SANCTUARY_MIN_OVERALL,
		"flavor_esteem_min": FLAVOR_ESTEEM_MIN,
		"flavor_contempt_max": FLAVOR_CONTEMPT_MAX,
	}


static func _line_ids(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row.get("id", "")))
	return out


static func _locked_line_ids(dispute: Dictionary, unlocked: Array[Dictionary]) -> Array:
	var unlocked_set: Dictionary = {}
	for row in unlocked:
		unlocked_set[String(row.get("id", ""))] = true
	var locked: Array = []
	# Known authored ids that may be locked: flavor + option_* when gate shut.
	for flavor in dispute.get("flavor", []):
		if typeof(flavor) != TYPE_DICTIONARY:
			continue
		var fid := String(flavor.get("id", ""))
		if fid != "" and not unlocked_set.has(fid):
			locked.append(fid)
	if not unlocked_set.has("option_eraic"):
		locked.append("option_eraic")
	if not unlocked_set.has("option_sanctuary"):
		locked.append("option_sanctuary")
	if not unlocked_set.has("closed") and not unlocked.is_empty():
		# closed only appears when all law gates shut — treat as locked when options open.
		var has_option := unlocked_set.has("option_eraic") or unlocked_set.has("option_sanctuary")
		if has_option:
			locked.append("closed")
	return locked


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
