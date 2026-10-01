extends Node
## Faction registry, attitudes, goals/needs, and quest-generation stubs.
##
## Slice (Leinster-active): Uí Chennselaig, Anglo-Normans, Norse-Gaelic.
## Norse-Gaelic chosen as third because Bannow Bay → Wexford/Waterford pressure
## and the cattle-economy Norse trade contact (see docs/SCOPE.md). Local clans
## remain in the full roster but are inactive for slice quest generation.

signal attitude_changed(faction_id: StringName, value: float)
signal need_changed(faction_id: StringName, need_id: StringName)
signal quest_stub_generated(faction_id: StringName, quest: Dictionary)

const FACTION_IDS: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"high_kingship",
	&"norse_gaelic",
	&"church",
	&"local_clans",
]

## Vertical-slice active set in Leinster.
const LEINSTER_ACTIVE: Array[StringName] = [
	&"ui_chennselaig",
	&"anglo_normans",
	&"norse_gaelic",
]

## Attitude toward the player: -100 hostile … +100 allied.
var attitudes: Dictionary = {}
## faction_id → { display_name, goals: Array, needs: Array, resources: Dictionary }
var profiles: Dictionary = {}


func _ready() -> void:
	for id in FACTION_IDS:
		attitudes[id] = 0.0
	_seed_profiles()
	_seed_leinster_attitudes()


func _seed_profiles() -> void:
	profiles[&"ui_chennselaig"] = {
		"display_name": "Uí Chennselaig",
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
		"display_name": "Anglo-Normans",
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
	profiles[&"norse_gaelic"] = {
		"display_name": "Norse-Gaelic towns",
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
	# Inactive in slice quest gen — roster stubs for later regions.
	profiles[&"high_kingship"] = {
		"display_name": "High Kingship",
		"active_in_leinster": false,
		"goals": [&"resist_invasion", &"hold_ireland"],
		"needs": [],
		"resources": {},
	}
	profiles[&"church"] = {
		"display_name": "The Church",
		"active_in_leinster": false,
		"goals": [&"protect_monasteries", &"political_influence"],
		"needs": [],
		"resources": {},
	}
	profiles[&"local_clans"] = {
		"display_name": "Local clans / fían",
		"active_in_leinster": false,
		"goals": [&"survival", &"feuds", &"opportunity"],
		"needs": [],
		"resources": {},
	}


func _seed_leinster_attitudes() -> void:
	# Cian is Gaelic cattle-stock: mild kinship with Uí Chennselaig, distrust of Normans.
	attitudes[&"ui_chennselaig"] = 10.0
	attitudes[&"anglo_normans"] = -25.0
	attitudes[&"norse_gaelic"] = 0.0


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
