# Sanctuary (Church precincts)

Monastic / Church **sanctuary site** data for Honor claims, **breach → Honor /
Rumors** hooks, and map / dialogue directors. Runtime registry:
[`sanctuary_locations.gd`](sanctuary_locations.gd) (`class_name SanctuaryLocations`).

**Scope:** data + API stubs only — no level geometry, no scene loads. Stealth /
combat / mission directors call `report_breach` / `resolve_breach` when steel
enters a precinct; this slice does not detect that itself.

Design: [`docs/MAP_SCALE.md`](../../docs/MAP_SCALE.md) ·
[`docs/SCOPE.md`](../../docs/SCOPE.md) (Glendalough / Clonmacnoise destinations).
Honor gates: [`scripts/autoload/honor.gd`](../../scripts/autoload/honor.gd).
Rumors tags: [`scripts/autoload/rumors.gd`](../../scripts/autoload/rumors.gd).
Region ids: [`TravelDistances`](../traversal/travel_distances.gd).

| Piece | Role |
|---|---|
| `SanctuaryLocations` | Extensible site table; query by id / region / list |
| `Honor.can_claim_sanctuary()` | Existing church / overall gate reused by sites |
| `report_breach` / `resolve_breach` | Honor deltas + tagged church/sanctuary/breach rumor |
| `Factions` id `&"church"` | Owning faction for every authored precinct |

---

## Seeded sites

| ID | Display | Region (`TravelDistances`) | Role |
|---|---|---|---|
| `glendalough` | Glendalough (Gleann Dá Loch) | `wicklow_glendalough` | Highland monastic sanctuary / pilgrimage |
| `clonmacnoise` | Clonmacnoise (Cluain Mhic Nóis) | `clonmacnoise` | Shannon corridor monastic center |

Add rows to `SITES` (+ `SITE_IDS`) to extend. Keep `region_id` in
`TravelDistances.REGION_IDS`.

### Claim rules (per site)

| Field | Meaning |
|---|---|
| `requires_honor_gate` | When true, `Honor.can_claim_sanctuary()` must pass |
| `claimant` | Slice stub: `&"player"` (who may ask for refuge) |
| `honor_on_claim` | Delta applied on successful `try_claim` (church enech) |
| `notes` | Author reminder — presence / scene checks deferred |

Thresholds live on Honor (slice defaults): `SANCTUARY_MIN_CHURCH=30`,
`SANCTUARY_MIN_OVERALL=35` — church **or** overall.

### Breach rules (per site)

| Field | Meaning |
|---|---|
| `honor_on_breach` | `{church, overall}` deltas on resolve (defaults −12 / −6) |
| `rumor_priority` | Rumors priority (default **HIGH** = 3) |
| `rumor_decay_days` | Bus lifetime (default **12**) |
| `notes` | Author reminder — detection deferred to directors |

Repeat breaches at the same site escalate: each prior count adds
`BREACH_ESCALATION_CHURCH` (−3) / `BREACH_ESCALATION_OVERALL` (−1).

---

## Public API

```gdscript
SanctuaryLocations.list_site_ids()
SanctuaryLocations.list_sanctuaries()                 # all rows (duped)
SanctuaryLocations.get_by_id(&"glendalough")
SanctuaryLocations.list_by_region(&"wicklow_glendalough")
SanctuaryLocations.list_by_region(&"clonmacnoise")
SanctuaryLocations.display_name(&"clonmacnoise")
SanctuaryLocations.region_for(&"glendalough")         # → wicklow_glendalough
SanctuaryLocations.owner_faction()                    # → church
SanctuaryLocations.region_link_ok(&"glendalough")     # TravelDistances check
SanctuaryLocations.can_claim(&"glendalough")          # Honor gate + known site
SanctuaryLocations.probe_claim(&"clonmacnoise")       # UI / debug payload
SanctuaryLocations.try_claim(&"glendalough")          # stub resolve + honor tick
SanctuaryLocations.list_in_current_region()           # via Game.current_region

# Breach → Honor + Rumors (directors / stealth / combat)
SanctuaryLocations.probe_breach(&"glendalough")       # preview deltas + tags
SanctuaryLocations.report_breach(&"glendalough")      # alias of resolve_breach
SanctuaryLocations.resolve_breach(&"clonmacnoise", &"steel")
SanctuaryLocations.resolve_breach(&"glendalough", &"blood", true, true)
SanctuaryLocations.get_breach_count(&"glendalough")
SanctuaryLocations.reset_breach_tracking()
SanctuaryLocations.build_breach_rumor_tags(&"glendalough")
print(SanctuaryLocations.to_debug_dict())
print(SanctuaryLocations.get_debug_text())
print(SanctuaryLocations.probe_remote(true))          # optional live resolve
```

### Breach outcome Dictionary

| Key | Meaning |
|---|---|
| `ok` | Known site / resolve ran |
| `option` | `&"sanctuary_breach"` |
| `reason` | `&"breached"` or `&"unknown_site"` |
| `site_id` / `display_name` / `region_id` / `faction_id` | Where |
| `kind` | Caller tag (`steel`, `blood`, `theft`, …) |
| `escalated` | True when `breach_count` was already ≥ 1 before this resolve |
| `breach_count` | Session tally after this resolve |
| `honor_delta_church` / `honor_delta_overall` | Applied through `Honor.modify_honor` |
| `rumor_seeded` / `rumor_id` | Whether a tagged bus entry was added |
| `rumor_tags` | `church`, `sanctuary`, `breach`, `heat`, `faction:church`, `direction:colder`, `site:<id>` |
| `summary` | Human line for UI / Honor `Last:` |

`try_claim` and `resolve_breach` both stamp `Honor.last_law_result` so the Honor
F5 panel `Last:` line can show site-scoped claim or breach outcomes.
`last_breach_result` mirrors the latest breach payload on the registry.

Rumor source: `&"sanctuary_breach"` (skipped by Rumors reverse faction-nudge so
Honor / attitude do not double-loop). Large church deltas may still trip
`Honor._maybe_rumor_honor` (generic `&"honor"` line) — directors should filter on
`church` / `sanctuary` / `breach` tags for the rich entry.

---

## How Godot / Honor / Rumors uses it

1. **Map / travel UI** — list sanctuaries or filter by region when showing
   Wicklow / Clonmacnoise destinations (`list_by_region`, `region_for`).
2. **Dialogue / law UI** — when the player is at (or chooses) a precinct, call
   `can_claim` / `probe_claim` instead of only the global Honor option; still
   driven by `Honor.can_claim_sanctuary()` and `Honor.available_law_options()`.
3. **Church faction** — `faction_id` / `OWNER_FACTION` is `&"church"` so
   attitude / relationship graph hooks stay consistent with `Factions`.
4. **Breach directors** — stealth detection, combat-in-precinct, or mission
   scripts call `report_breach(site_id)` / `resolve_breach(site_id, kind)` when
   sanctuary is violated. No geometry here; pass the site id from the mission.
5. **Law samples** — `LawGateSample` / `LawDialogueSamples` keep using the
   global gate; site-aware content can call `SanctuaryLocations.try_claim(id)`
   when a dispute names a precinct.

Not an autoload — `class_name` registry (same pattern as `TravelDistances` /
`LawDialogueSamples`).

---

## F5 / remote probe

**No Godot binary in this ticket** — Lead runs F5; remote console is enough.

No dedicated HUD keys yet. After **F5** on the main scene, use the Remote /
Debugger console (or `tools/probe_sanctuary_breach.gd`):

```gdscript
print(SanctuaryLocations.get_debug_text())
print(SanctuaryLocations.probe_breach(&"glendalough"))
print(SanctuaryLocations.probe_remote())

# Resolve a breach (Honor church/overall drop + tagged rumor):
var out := SanctuaryLocations.resolve_breach(&"glendalough", &"steel")
print(out)
# out.ok / honor_delta_church / rumor_id / rumor_tags

print(Rumors.get_rumor(out.rumor_id))
print(Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_BREACH))
print(Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_SANCTUARY))

# Honor panel (H) Last: should show sanctuary_breach summary
print(Honor.last_law_result)
print(Honor.get_honor(&"church"), Honor.get_honor())

# Second breach escalates deltas:
print(SanctuaryLocations.resolve_breach(&"glendalough", &"blood"))
print(SanctuaryLocations.get_breach_count(&"glendalough"))  # 2

SanctuaryLocations.reset_breach_tracking()
```

Headless / remote script (when Godot is available):

```bash
godot --headless --path . --script res://tools/probe_sanctuary_breach.gd
```

Honor panel (**H**): gates still show global `sanctuary=true/false`; site claims
reuse that gate; breach stamps `Last:`. Rumors panel (**N**): look for
`{church,sanctuary,breach,heat,faction:church,direction:colder,site:*}`.

TravelDistances remote check for region links:

```gdscript
print(TravelDistances.is_known_region(&"wicklow_glendalough"))
print(TravelDistances.is_known_region(&"clonmacnoise"))
```

---

## Non-goals (this slice)

- Full monastic level geometry / round-tower climbables
- Auto-detect player combat inside a precinct volume
- Auto-travel to sanctuary on claim
- NPC abbots / liturgy simulation
- Extra sanctuary sites beyond Glendalough + Clonmacnoise (registry is ready)
- Clearing / atoning a breach (penance reverse path) — Honor claim stays separate
