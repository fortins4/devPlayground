class_name CrowdSites
extends RefCounted
## Static town / settlement presence registry for the NPC crowd stub.
##
## Site ids are settlement-scoped; `region_id` must match TravelDistances.REGION_IDS
## where natural (dublin, wexford_waterford, leinster, …). Runtime density lives on
## the Crowd autoload — this table is seed / metadata only.
##
## Design: docs/MAP_REGIONS.md · docs/MAP_SCALE.md · systems/crowd/README.md

## Crowd density tiers (visual bind targets). Density 0..1 maps via Crowd.tier_for_density.
enum Tier { EMPTY, SPARSE, MODERATE, BUSY, THRONG }

const TIER_IDS: Array[StringName] = [
	&"empty",
	&"sparse",
	&"moderate",
	&"busy",
	&"throng",
]

const TIER_LABELS: Array[String] = [
	"Empty",
	"Sparse",
	"Moderate",
	"Busy",
	"Throng",
]

## Midpoint densities used when set_tier snaps a site.
const TIER_DENSITY_MID: Array[float] = [
	0.0,   # EMPTY
	0.15,  # SPARSE
	0.38,  # MODERATE
	0.62,  # BUSY
	0.88,  # THRONG
]

## Upper bounds (exclusive except last) for density → tier.
const TIER_DENSITY_CEIL: Array[float] = [
	0.05,  # EMPTY
	0.25,  # SPARSE
	0.5,   # MODERATE
	0.75,  # BUSY
	1.01,  # THRONG (inclusive 1.0)
]

## Canonical site ids (extend by appending SITES rows + this list).
const SITE_IDS: Array[StringName] = [
	&"dublin",
	&"wexford",
	&"waterford",
	&"leinster_ringfort_market",
	&"bannow_beachhead_camp",
	&"glendalough_pilgrim",
	&"clonmacnoise_fair",
	&"midlands_drove_camp",
	&"shannon_landing",
	&"connacht_host_camp",
	&"munster_fringe_steading",
]

## Authored settlement / town presence sites. Schema:
##   id, display_name, irish_name, region_id, kind, base_density, tags, summary
## kind: town | port | market | monastic_fair | camp | river | steading
const SITES: Array[Dictionary] = [
	{
		"id": &"dublin",
		"display_name": "Áth Cliath (Dublin)",
		"irish_name": "Áth Cliath",
		"region_id": &"dublin",
		"kind": &"town",
		"base_density": 0.72,
		"tags": [&"norse_gaelic", &"harbor", &"dense"],
		"summary": (
			"Norse-Gaelic town on the Liffey — densest urban presence after Leinster "
			+ "opens north. Visual crowds bind here later; data stub only."
		),
	},
	{
		"id": &"wexford",
		"display_name": "Wexford",
		"irish_name": "Loch Garman",
		"region_id": &"wexford_waterford",
		"kind": &"port",
		"base_density": 0.58,
		"tags": [&"norse_gaelic", &"port", &"coast"],
		"summary": (
			"Norse-Gaelic port on the south-east coast. Early Norman foothold pressure; "
			+ "harbor traffic sets busy tier when ports hold."
		),
	},
	{
		"id": &"waterford",
		"display_name": "Waterford",
		"irish_name": "Port Láirge",
		"region_id": &"wexford_waterford",
		"kind": &"port",
		"base_density": 0.55,
		"tags": [&"norse_gaelic", &"port", &"coast"],
		"summary": (
			"Sister port to Wexford on the same TravelDistances region. Marriage / "
			+ "struggle events may later nudge density via directors."
		),
	},
	{
		"id": &"leinster_ringfort_market",
		"display_name": "Leinster ringfort market",
		"irish_name": "Aonach Laighean",
		"region_id": &"leinster",
		"kind": &"market",
		"base_density": 0.42,
		"tags": [&"slice", &"market", &"ui_chennselaig"],
		"summary": (
			"Local market / muster crowd near the slice ringfort. Authored roam "
			+ "presence target for first visual binds."
		),
	},
	{
		"id": &"bannow_beachhead_camp",
		"display_name": "Bannow beachhead camp",
		"irish_name": "Cuan an Bhainbh",
		"region_id": &"leinster",
		"kind": &"camp",
		"base_density": 0.35,
		"tags": [&"norman", &"landing", &"landmark"],
		"summary": (
			"Landing-window camp inside leinster greybox (landmark, not own region). "
			+ "Sparse→moderate host presence after day 0."
		),
	},
	{
		"id": &"glendalough_pilgrim",
		"display_name": "Glendalough pilgrim crowd",
		"irish_name": "Gleann Dá Loch",
		"region_id": &"wicklow_glendalough",
		"kind": &"monastic_fair",
		"base_density": 0.28,
		"tags": [&"church", &"pilgrimage", &"highland"],
		"summary": (
			"Pilgrim / monastic fair presence near Glendalough sanctuary. Seasonal "
			+ "hooks may lift summer density when WorldClock season is available."
		),
	},
	{
		"id": &"clonmacnoise_fair",
		"display_name": "Clonmacnoise fair",
		"irish_name": "Cluain Mhic Nóis",
		"region_id": &"clonmacnoise",
		"kind": &"monastic_fair",
		"base_density": 0.32,
		"tags": [&"church", &"shannon", &"fair"],
		"summary": (
			"Shannon-corridor monastic fair / market days. Graph stub until region loads."
		),
	},
	{
		"id": &"midlands_drove_camp",
		"display_name": "Midlands drove camp",
		"irish_name": "Longphort na Móna",
		"region_id": &"midlands_bogs",
		"kind": &"camp",
		"base_density": 0.18,
		"tags": [&"drove", &"sparse", &"guerrilla"],
		"summary": (
			"Sparse cattle-drove / guerrilla camps on the bog approaches — low throng."
		),
	},
	{
		"id": &"shannon_landing",
		"display_name": "Shannon river landing",
		"irish_name": "Caladh na Sionainne",
		"region_id": &"shannon",
		"kind": &"river",
		"base_density": 0.22,
		"tags": [&"river", &"boat", &"spine"],
		"summary": (
			"River-way landing presence (currach traffic stub). Not a place to live."
		),
	},
	{
		"id": &"connacht_host_camp",
		"display_name": "Connacht host camp",
		"irish_name": "Longphort Chonnacht",
		"region_id": &"connacht",
		"kind": &"camp",
		"base_density": 0.25,
		"tags": [&"high_king", &"late", &"host"],
		"summary": (
			"Late-game western host presence. Starts sparse; directors may raise tier."
		),
	},
	{
		"id": &"munster_fringe_steading",
		"display_name": "Munster fringe steading",
		"irish_name": "Bailte na Mumhan",
		"region_id": &"munster_fringe",
		"kind": &"steading",
		"base_density": 0.2,
		"tags": [&"coastal", &"light", &"fringe"],
		"summary": (
			"Light coastal steading / túath gathering on the Munster fringe."
		),
	},
]


static func is_known_site(site_id: StringName) -> bool:
	return site_id in SITE_IDS


static func tier_id(tier: Tier) -> StringName:
	var i := int(tier)
	if i < 0 or i >= TIER_IDS.size():
		return &"empty"
	return TIER_IDS[i]


static func tier_label(tier: Tier) -> String:
	var i := int(tier)
	if i < 0 or i >= TIER_LABELS.size():
		return "Empty"
	return TIER_LABELS[i]


static func tier_from_id(tier_name: StringName) -> Tier:
	for i in TIER_IDS.size():
		if TIER_IDS[i] == tier_name:
			return i as Tier
	return Tier.EMPTY


static func density_for_tier(tier: Tier) -> float:
	var i := clampi(int(tier), 0, TIER_DENSITY_MID.size() - 1)
	return TIER_DENSITY_MID[i]


static func tier_for_density(density: float) -> Tier:
	var d := clampf(density, 0.0, 1.0)
	for i in TIER_DENSITY_CEIL.size():
		if d < TIER_DENSITY_CEIL[i]:
			return i as Tier
	return Tier.THRONG


static func get_site_row(site_id: StringName) -> Dictionary:
	for row in SITES:
		if row.get("id", &"") == site_id:
			return row.duplicate(true)
	return {}


static func list_site_ids() -> Array[StringName]:
	return SITE_IDS.duplicate()


static func list_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in SITES:
		out.append(row.duplicate(true))
	return out


static func list_by_region(region_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in SITES:
		if row.get("region_id", &"") == region_id:
			out.append(row.duplicate(true))
	return out


static func display_name(site_id: StringName) -> String:
	var row := get_site_row(site_id)
	if row.is_empty():
		return String(site_id)
	return str(row.get("display_name", String(site_id)))


static func region_for(site_id: StringName) -> StringName:
	var row := get_site_row(site_id)
	return row.get("region_id", &"") as StringName


static func kind_for(site_id: StringName) -> StringName:
	var row := get_site_row(site_id)
	return row.get("kind", &"") as StringName


static func base_density(site_id: StringName) -> float:
	var row := get_site_row(site_id)
	if row.is_empty():
		return 0.0
	return float(row.get("base_density", 0.0))


static func region_link_ok(site_id: StringName) -> bool:
	var rid := region_for(site_id)
	if rid == &"":
		return false
	return TravelDistances.is_known_region(rid)


static func to_debug_dict() -> Dictionary:
	var rows: Array = []
	for row in SITES:
		var sid: StringName = row.get("id", &"")
		rows.append({
			"id": String(sid),
			"display_name": str(row.get("display_name", "")),
			"region_id": String(row.get("region_id", &"")),
			"kind": String(row.get("kind", &"")),
			"base_density": float(row.get("base_density", 0.0)),
			"region_link_ok": region_link_ok(sid),
		})
	return {
		"site_count": SITE_IDS.size(),
		"sites": rows,
	}
