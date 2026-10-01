# Sanctuary (Church precincts)

Monastic / Church **sanctuary site** data for Honor claims and map / dialogue
hooks. Runtime registry: [`sanctuary_locations.gd`](sanctuary_locations.gd)
(`class_name SanctuaryLocations`).

**Scope:** data + API stubs only — no level geometry, no scene loads.

Design: [`docs/MAP_SCALE.md`](../../docs/MAP_SCALE.md) ·
[`docs/SCOPE.md`](../../docs/SCOPE.md) (Glendalough / Clonmacnoise destinations).
Honor gates: [`scripts/autoload/honor.gd`](../../scripts/autoload/honor.gd).
Region ids: [`TravelDistances`](../traversal/travel_distances.gd).

| Piece | Role |
|---|---|
| `SanctuaryLocations` | Extensible site table; query by id / region / list |
| `Honor.can_claim_sanctuary()` | Existing church / overall gate reused by sites |
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
print(SanctuaryLocations.to_debug_dict())
print(SanctuaryLocations.get_debug_text())
```

`try_claim` stamps `Honor.last_law_result` the same way law-gate samples do, so
the Honor F5 panel `Last:` line can show a site-scoped sanctuary resolve.

---

## How Godot / Honor uses it

1. **Map / travel UI** — list sanctuaries or filter by region when showing
   Wicklow / Clonmacnoise destinations (`list_by_region`, `region_for`).
2. **Dialogue / law UI** — when the player is at (or chooses) a precinct, call
   `can_claim` / `probe_claim` instead of only the global Honor option; still
   driven by `Honor.can_claim_sanctuary()` and `Honor.available_law_options()`.
3. **Church faction** — `faction_id` / `OWNER_FACTION` is `&"church"` so
   attitude / relationship graph hooks stay consistent with `Factions`.
4. **Law samples** — `LawGateSample` / `LawDialogueSamples` keep using the
   global gate; site-aware content can call `SanctuaryLocations.try_claim(id)`
   when a dispute names a precinct.

Not an autoload — `class_name` registry (same pattern as `TravelDistances` /
`LawDialogueSamples`).

---

## F5 / remote probe

No dedicated HUD keys yet. After **F5** on the main scene, use the Remote /
Debugger console (or a temporary script):

```gdscript
print(SanctuaryLocations.get_debug_text())
print(SanctuaryLocations.list_sanctuaries())
print(SanctuaryLocations.probe_claim(&"glendalough"))
print(SanctuaryLocations.can_claim(&"clonmacnoise"))
# Close Honor sanctuary gate (; church −5 / [ overall −5), then:
print(SanctuaryLocations.try_claim(&"glendalough"))  # ok=false
# Re-open ( ' / ] ) and:
print(SanctuaryLocations.try_claim(&"clonmacnoise")) # ok=true; Honor Last: updates
```

Honor panel (**H**): gates still show global `sanctuary=true/false`; site claims
reuse that gate. TravelDistances remote check for region links:

```gdscript
print(TravelDistances.is_known_region(&"wicklow_glendalough"))
print(TravelDistances.is_known_region(&"clonmacnoise"))
```

---

## Non-goals (this slice)

- Full monastic level geometry / round-tower climbables
- Auto-travel to sanctuary on claim
- NPC abbots / liturgy simulation
- Extra sanctuary sites beyond Glendalough + Clonmacnoise (registry is ready)
