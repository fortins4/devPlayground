extends Node
## Faction registry, attitudes, goals/needs, and quest-generation stubs.
##
## Full roster (historically truer): Uí Chennselaig, Anglo-Normans, English crown,
## High Kingship, Norse Dublin, Norse Wexford/Waterford, Church, local clans, fían.
## Leinster slice ACTIVE (quest gen): ui_chennselaig, anglo_normans,
## norse_wexford_waterford. english_crown stays inactive until late / 1171 pressure.

signal attitude_changed(faction_id: StringName, value: float)
signal need_changed(faction_id: StringName, need_id: StringName)
signal quest_stub_generated(faction_id: StringName, quest: Dictionary)
signal relationship_changed(from_id: StringName, to_id: StringName, edge: Dictionary)

const FACTION_IDS: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"english_crown",
	&"high_kingship",
	&"norse_dublin",
	&"norse_wexford_waterford",
	&"church",
	&"local_clans",
	&"fian",
]

## Vertical-slice active set in Leinster (quest generation only).
const LEINSTER_ACTIVE: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"norse_wexford_waterford",
]

## Directed relationship edge kinds (faction↔faction, not player attitude).
const REL_ALLIANCE: StringName = &"alliance"
const REL_HOSTILITY: StringName = &"hostility"
const REL_OBLIGATION: StringName = &"obligation"
const REL_PATRONAGE: StringName = &"patronage"
const REL_RIVALRY: StringName = &"rivalry"
const REL_TRADE: StringName = &"trade"
const REL_KINSHIP: StringName = &"kinship"
const REL_FEUD: StringName = &"feud"

const RELATIONSHIP_KINDS: Array[StringName] = [
	REL_ALLIANCE,
	REL_HOSTILITY,
	REL_OBLIGATION,
	REL_PATRONAGE,
	REL_RIVALRY,
	REL_TRADE,
	REL_KINSHIP,
	REL_FEUD,
]

## Attitude toward the player: -100 hostile … +100 allied.
var attitudes: Dictionary = {}
## faction_id → { display_name, goals: Array, needs: Array, resources: Dictionary, ... }
var profiles: Dictionary = {}
## Directed edges: Array of { from, to, kind, strength (−100…+100), note }.
## Multiple kinds allowed between the same pair (e.g. alliance + obligation).
var relationship_edges: Array[Dictionary] = []


func _ready() -> void:
	for id in FACTION_IDS:
		attitudes[id] = 0.0
	_seed_profiles()
	_seed_leinster_attitudes()
	_seed_relationship_graph()


func _seed_profiles() -> void:
	profiles[&"ui_chennselaig"] = {
		"display_name": "Uí Chennselaig / Diarmait",
		"active_in_leinster": true,
		"goals": [
			&"retake_leinster",
			&"use_norman_allies",
			&"secure_diarmait_kingship",
		],
		"needs": [
			{"id": &"cattle_tribute", "priority": 2, "pressure": 0.6},
			{"id": &"warrior_host", "priority": 3, "pressure": 0.7},
		],
		"resources": {"cattle": 40, "warriors": 25, "silver": 10},
	}
	profiles[&"anglo_normans"] = {
		"display_name": "Strongbow & adventurers",
		"active_in_leinster": true,
		"goals": [
			&"gain_land",
			&"hold_bannow_beachhead",
			&"expand_from_wexford",
		],
		"needs": [
			{"id": &"supplies_landing", "priority": 3, "pressure": 0.8},
			{"id": &"local_guides", "priority": 2, "pressure": 0.5},
		],
		"resources": {"troops": 30, "ships": 5, "silver": 40},
	}
	# Inactive until late / 1171 pressure — registered for honor + attitude tables.
	profiles[&"english_crown"] = {
		"display_name": "Henry II / English crown",
		"active_in_leinster": false,
		"inactive_until_late": true,
		"goals": [
			&"control_barons",
			&"claim_overlordship",
		],
		"needs": [],
		"resources": {},
	}
	profiles[&"high_kingship"] = {
		"display_name": "Ruaidrí / Connacht (High Kingship)",
		"active_in_leinster": false,
		"goals": [&"resist_invasion", &"hold_ireland"],
		"needs": [],
		"resources": {},
	}
	profiles[&"norse_dublin"] = {
		"display_name": "Norse-Gaelic Dublin",
		"active_in_leinster": false,
		"goals": [
			&"protect_trade",
			&"hold_ath_cliath",
			&"preserve_autonomy",
		],
		"needs": [],
		"resources": {"ships": 20, "trade_goods": 40, "silver": 50},
	}
	# Slice coastal actor (replaces monolithic norse_gaelic for Leinster).
	profiles[&"norse_wexford_waterford"] = {
		"display_name": "Norse-Gaelic Wexford/Waterford",
		"active_in_leinster": true,
		"goals": [
			&"protect_trade",
			&"hold_wexford_waterford",
			&"preserve_autonomy",
		],
		"needs": [
			{"id": &"harbor_defense", "priority": 3, "pressure": 0.75},
			{"id": &"trade_cattle", "priority": 2, "pressure": 0.55},
		],
		"resources": {"ships": 12, "trade_goods": 20, "silver": 35},
	}
	profiles[&"church"] = {
		"display_name": "The Church",
		"active_in_leinster": false,
		"goals": [&"protect_monasteries", &"political_influence", &"reform"],
		"needs": [],
		"resources": {},
	}
	profiles[&"local_clans"] = {
		"display_name": "Local Leinster túatha / rival clans",
		"active_in_leinster": false,
		"goals": [&"survival", &"feuds", &"shifting_loyalty"],
		"needs": [],
		"resources": {},
	}
	profiles[&"fian"] = {
		"display_name": "Fían / outlaw bands",
		"active_in_leinster": false,
		"goals": [&"survival", &"opportunity", &"wilderness_raids"],
		"needs": [],
		"resources": {},
	}


func _seed_leinster_attitudes() -> void:
	# Cian is Gaelic cattle-stock: mild kinship with Uí Chennselaig, distrust of Normans.
	attitudes[&"ui_chennselaig"] = 10.0
	attitudes[&"anglo_normans"] = -25.0
	attitudes[&"norse_wexford_waterford"] = 0.0
	attitudes[&"english_crown"] = 0.0
	attitudes[&"high_kingship"] = 5.0
	attitudes[&"norse_dublin"] = 0.0
	attitudes[&"church"] = 5.0
	attitudes[&"local_clans"] = 0.0
	attitudes[&"fian"] = -5.0


func is_leinster_active(faction_id: StringName) -> bool:
	return faction_id in LEINSTER_ACTIVE


func get_attitude(faction_id: StringName) -> float:
	return float(attitudes.get(faction_id, 0.0))


func modify_attitude(faction_id: StringName, delta: float) -> void:
	var value := clampf(get_attitude(faction_id) + delta, -100.0, 100.0)
	attitudes[faction_id] = value
	attitude_changed.emit(faction_id, value)
	if Rumors and absf(delta) >= 10.0:
		var direction := "warmer" if delta > 0.0 else "colder"
		Rumors.add_rumor(
			StringName("attitude_%s_%d" % [String(faction_id), WorldClock.day if WorldClock else 0]),
			"Relations with %s grow %s." % [_display_name(faction_id), direction],
			&"faction",
			Rumors.PRIORITY_NORMAL,
			5
		)


func get_goals(faction_id: StringName) -> Array:
	var profile: Dictionary = profiles.get(faction_id, {})
	return profile.get("goals", [])


func get_needs(faction_id: StringName) -> Array:
	var profile: Dictionary = profiles.get(faction_id, {})
	return profile.get("needs", [])


func set_need_pressure(faction_id: StringName, need_id: StringName, pressure: float) -> void:
	var profile: Dictionary = profiles.get(faction_id, {})
	if profile.is_empty():
		return
	var needs: Array = profile.get("needs", [])
	for need in needs:
		if need.get("id") == need_id:
			need["pressure"] = clampf(pressure, 0.0, 1.0)
			need_changed.emit(faction_id, need_id)
			return


## Build 1–2 dynamic quest stubs from current needs (data only — no quest UI).
func generate_quest_stubs(faction_id: StringName = &"") -> Array[Dictionary]:
	var stubs: Array[Dictionary] = []
	var targets: Array[StringName] = []
	if faction_id != &"":
		targets.append(faction_id)
	else:
		targets.append_array(LEINSTER_ACTIVE)
	for id in targets:
		if not is_leinster_active(id):
			continue
		var needs := get_needs(id)
		needs.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
		var count := 0
		for need in needs:
			if count >= 2:
				break
			if float(need.get("pressure", 0.0)) < 0.4:
				continue
			var quest := {
				"id": StringName("%s_%s" % [String(id), String(need.get("id", &"need"))]),
				"faction_id": id,
				"need_id": need.get("id"),
				"title": _quest_title(id, need.get("id")),
				"pressure": need.get("pressure"),
				"priority": need.get("priority"),
				"status": &"available",
			}
			stubs.append(quest)
			quest_stub_generated.emit(id, quest)
			count += 1
	return stubs


func _quest_title(faction_id: StringName, need_id: Variant) -> String:
	var need := String(need_id) if need_id != null else "aid"
	return "%s seeks help: %s" % [_display_name(faction_id), need.replace("_", " ")]


func _display_name(faction_id: StringName) -> String:
	var profile: Dictionary = profiles.get(faction_id, {})
	return str(profile.get("display_name", String(faction_id)))



# --- Faction↔faction relationship graph --------------------------------------

## Seed historically flavoured directed edges. Leinster-active pairs are denser;
## full roster gets sparse scaffolding so later regions inherit the graph.
func _seed_relationship_graph() -> void:
	relationship_edges.clear()
	# Diarmait invited Strongbow's adventurers — alliance with land-for-service debt.
	_add_edge_raw(&"ui_chennselaig", &"anglo_normans", REL_ALLIANCE, 55.0,
		"Diarmait seeks Norman arms to retake Leinster.")
	_add_edge_raw(&"anglo_normans", &"ui_chennselaig", REL_OBLIGATION, 45.0,
		"Landing terms: land and marriage claims owed for service.")
	# Coastal Norse towns are early Norman targets.
	_add_edge_raw(&"anglo_normans", &"norse_wexford_waterford", REL_HOSTILITY, 70.0,
		"Wexford and Waterford are the beachhead prizes.")
	_add_edge_raw(&"norse_wexford_waterford", &"anglo_normans", REL_HOSTILITY, 65.0,
		"Harbor towns brace against the landing.")
	# Diarmait vs Ruaidrí (exile / High Kingship feud).
	_add_edge_raw(&"ui_chennselaig", &"high_kingship", REL_RIVALRY, 50.0,
		"Exile feud with Ruaidrí / Connacht overlordship.")
	_add_edge_raw(&"high_kingship", &"ui_chennselaig", REL_HOSTILITY, 60.0,
		"High Kingship treats Diarmait's restoration as rebellion.")
	_add_edge_raw(&"high_kingship", &"anglo_normans", REL_HOSTILITY, 45.0,
		"Foreign adventurers threaten Irish overlordship.")
	# Norse kin/trade across the Irish Sea towns.
	_add_edge_raw(&"norse_dublin", &"norse_wexford_waterford", REL_KINSHIP, 40.0,
		"Shared Norse-Gaelic coastal identity.")
	_add_edge_raw(&"norse_wexford_waterford", &"norse_dublin", REL_TRADE, 35.0,
		"Cattle and harbor goods along the east coast.")
	# Baronial patronage under Henry II (latent until 1171 pressure).
	_add_edge_raw(&"anglo_normans", &"english_crown", REL_PATRONAGE, 30.0,
		"Adventurers still owe fealty to Henry II.")
	_add_edge_raw(&"english_crown", &"anglo_normans", REL_PATRONAGE, 50.0,
		"Crown expects to rein in over-mighty barons.")
	# Soft Church / local scaffolding.
	_add_edge_raw(&"church", &"ui_chennselaig", REL_OBLIGATION, 20.0,
		"Sanctuary and reform politics in Leinster.")
	_add_edge_raw(&"local_clans", &"ui_chennselaig", REL_KINSHIP, 25.0,
		"Túatha kinship under shifting kingship claims.")
	_add_edge_raw(&"ui_chennselaig", &"norse_wexford_waterford", REL_RIVALRY, 25.0,
		"Coastal dues and cattle-trade friction.")
	_add_edge_raw(&"fian", &"local_clans", REL_FEUD, 30.0,
		"Outlaw bands prey on túatha herds.")
	_add_edge_raw(&"local_clans", &"fian", REL_HOSTILITY, 35.0,
		"Clan reprisals against fían raiders.")


func _add_edge_raw(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	strength: float,
	note: String = ""
) -> void:
	relationship_edges.append({
		"from": from_id,
		"to": to_id,
		"kind": kind,
		"strength": clampf(strength, -100.0, 100.0),
		"note": note,
	})


func _edge_matches(
	edge: Dictionary,
	from_id: StringName,
	to_id: StringName,
	kind: StringName
) -> bool:
	if from_id != &"" and edge.get("from") != from_id:
		return false
	if to_id != &"" and edge.get("to") != to_id:
		return false
	if kind != &"" and edge.get("kind") != kind:
		return false
	return true


## Upsert a directed edge (match on from+to+kind). Emits relationship_changed.
func set_relationship(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	strength: float,
	note: String = ""
) -> Dictionary:
	if from_id not in FACTION_IDS or to_id not in FACTION_IDS:
		push_warning("Factions.set_relationship: unknown faction id")
		return {}
	if kind not in RELATIONSHIP_KINDS:
		push_warning("Factions.set_relationship: unknown kind %s" % String(kind))
		return {}
	var clamped := clampf(strength, -100.0, 100.0)
	for i in relationship_edges.size():
		var edge: Dictionary = relationship_edges[i]
		if _edge_matches(edge, from_id, to_id, kind):
			edge["strength"] = clamped
			if note != "":
				edge["note"] = note
			relationship_edges[i] = edge
			relationship_changed.emit(from_id, to_id, edge)
			return edge
	var created := {
		"from": from_id,
		"to": to_id,
		"kind": kind,
		"strength": clamped,
		"note": note,
	}
	relationship_edges.append(created)
	relationship_changed.emit(from_id, to_id, created)
	return created


func modify_relationship_strength(
	from_id: StringName,
	to_id: StringName,
	kind: StringName,
	delta: float
) -> Dictionary:
	var edge := get_relationship(from_id, to_id, kind)
	var current := float(edge.get("strength", 0.0)) if not edge.is_empty() else 0.0
	var note := str(edge.get("note", "")) if not edge.is_empty() else ""
	return set_relationship(from_id, to_id, kind, current + delta, note)


## First matching edge (optional kind filter). Empty Dictionary if none.
func get_relationship(
	from_id: StringName,
	to_id: StringName,
	kind: StringName = &""
) -> Dictionary:
	for edge in relationship_edges:
		if _edge_matches(edge, from_id, to_id, kind):
			return edge.duplicate(true)
	return {}


## Filter edges by optional from / to / kind (&"" = any).
func list_relationships(
	from_id: StringName = &"",
	to_id: StringName = &"",
	kind: StringName = &""
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in relationship_edges:
		if _edge_matches(edge, from_id, to_id, kind):
			out.append(edge.duplicate(true))
	return out


## Edges touching a faction as either endpoint.
func list_relationships_involving(faction_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in relationship_edges:
		if edge.get("from") == faction_id or edge.get("to") == faction_id:
			out.append(edge.duplicate(true))
	return out


func has_relationship(
	from_id: StringName,
	to_id: StringName,
	kind: StringName = &"",
	min_strength: float = 0.0
) -> bool:
	for edge in list_relationships(from_id, to_id, kind):
		if absf(float(edge.get("strength", 0.0))) >= min_strength:
			return true
	return false


func are_allied(a: StringName, b: StringName, min_strength: float = 25.0) -> bool:
	return (
		has_relationship(a, b, REL_ALLIANCE, min_strength)
		or has_relationship(b, a, REL_ALLIANCE, min_strength)
	)


func are_hostile(a: StringName, b: StringName, min_strength: float = 25.0) -> bool:
	return (
		has_relationship(a, b, REL_HOSTILITY, min_strength)
		or has_relationship(b, a, REL_HOSTILITY, min_strength)
		or has_relationship(a, b, REL_FEUD, min_strength)
		or has_relationship(b, a, REL_FEUD, min_strength)
	)


## Leinster-slice pairs (both endpoints in LEINSTER_ACTIVE).
func list_leinster_relationships() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in relationship_edges:
		var fr: StringName = edge.get("from")
		var to: StringName = edge.get("to")
		if fr in LEINSTER_ACTIVE and to in LEINSTER_ACTIVE:
			out.append(edge.duplicate(true))
	return out


func relationship_count() -> int:
	return relationship_edges.size()


func to_relationship_debug_dict() -> Dictionary:
	var by_kind: Dictionary = {}
	for kind in RELATIONSHIP_KINDS:
		by_kind[String(kind)] = 0
	for edge in relationship_edges:
		var k := String(edge.get("kind", &""))
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	return {
		"edge_count": relationship_edges.size(),
		"by_kind": by_kind,
		"leinster_edges": list_leinster_relationships(),
		"edges": list_relationships(),
	}
