# Ríocht — World Map Scale (Leinster → Ireland)

Design note for greybox → full Ireland. Companion to `docs/SCOPE.md` (regions &
traversal) and `docs/VISION.md`. Runtime stubs: `systems/traversal/`.

**Region layout viz** (inventory + ASCII/mermaid map picture): [`docs/MAP_REGIONS.md`](MAP_REGIONS.md).
This file owns scale math and travel days; MAP_REGIONS owns relative geography.

Status: **draft** (2026-10-01). Numbers are playable fiction calibrated to
history, not a GIS reconstruction.

---

## Goals

1. **Leinster greybox first** — one walkable start region that teaches foot +
   horseback without feeling like a hallway or an empty continent.
2. **Readable travel cost** — days on the road matter (upkeep, rumors, timeline
   events) without punishing every hop.
3. **Honest expansion path** — same distance table grows from Leinster-dense
   slice → full nine-region Ireland without re-authoring every road.
4. **Load strategy agnostic** — distances work for travel-gate loads *or*
   additive streaming; do not lock streaming here (SCOPE still owns that call).

Non-goals: every-túath accuracy; photoreal Terrain3D scale before systems prove
out; naval logistics as the everyday loop.

---

## Real-world anchors (compressed, not copied)

| Real reference | Approx. | Greybox stance |
|---|---|---|
| Ireland N–S | ~480 km | Full map spans **~12–16 in-game travel days** horseback coast-to-coast feel, not 1:1 km |
| Ireland E–W | ~270 km | East (Wexford) → west (Connacht) is a **major expedition**, not a afternoon ride |
| Bannow → Wexford | ~25–40 km | **Same Leinster region** — landmark walk / short ride |
| Wexford → Waterford | ~50–60 km | **Same coastal band** or one overnight on foot |
| Waterford → Dublin | ~140 km | **2–4 days** horseback in slice fiction |
| Dublin → Athlone / Shannon | ~120 km | **Midlands crossing** |
| Dublin → Connacht heartland | ~180+ km | **Late-game pressure** travel |

We compress real km into **region graph edges** measured in **travel days**
(foot vs horse vs currach later). Greybox meters inside a region are local
level scale — they do **not** equal the graph’s day costs 1:1.

---

## Region size tiers

| Tier | Playable ground (greybox intent) | Role | Examples |
|---|---|---|---|
| **A — Dense** | ~1.5–3 km across authored play space (expand later) | Start loop, siege set pieces | Laigin (Leinster), Dublin |
| **B — Destination** | ~1–2 km authored + wild fringe | Sanctuary, guerrilla, pilgrimage | Wicklow/Glendalough, Midlands bogs, Clonmacnoise corridor |
| **C — Pressure / light** | Smaller authored pockets + roads | Political pressure, secondary conflict | Munster fringe (east), Connacht (late denser) |
| **Spine** | Linear water / road links | Traversal, not a “place to live” | Shannon / river ways |

**Leinster slice:** ship **Tier A** only as open roam; treat Wexford/Waterford
coasts as **landmarks + travel stubs** inside/near Leinster until region loads
exist. Bannow Bay is a landmark inside the Leinster greybox, not its own region
row.

### Leinster greybox layout (slice)

```
                    [north → Dublin road gate]
                              |
     [wilderness exile fringe]--+--[ringfort home]
                              |
        [inland túatha]----+--[central Leinster roam]
                              |
              [Bannow Bay beachhead landmark]
                              |
                    [south → Wexford/Waterford stub]
```

- **Playable diameter:** aim ~2 km of interesting ground (paths, ringfort,
  cattle targets, one Norman patrol route, Bannow overlook).
- **Horseback:** cross the greybox in minutes of real time; graph days apply when
  leaving through a **travel gate**.
- **Foot:** same space should feel hike-able; horseback is convenience + band
  logistics, not a teleport.

---

## Travel times (design defaults)

Units: **days** on the living clock (`WorldClock.day`). Round up partial days
when the player commits to a gate. Weather / band size / honor heat can modify
later; stubs use base values.

### Modes (slice → full)

| Mode | Slice | Full |
|---|---|---|
| Foot | yes | yes |
| Horseback | yes | yes |
| Currach / river | deferred | Shannon spine + coasts |
| Sea coastal hop | deferred | Wexford ↔ Waterford ↔ Dublin flavor |

Horseback ≈ **0.5×** foot days on road edges (min 1 day if foot ≥ 2).
Currach on Shannon ≈ horseback on parallel road, sometimes faster upstream/down.

### Base horse days (region graph)

Symmetric undirected edges for stubs. “—” = no direct stub (route via another
region). Ids match `Game.current_region` / future region scenes.

| From → To | Horse days | Foot days | Notes |
|---|---|---|---|
| `leinster` → `wexford_waterford` | 1 | 2 | Coastal south; early Norman pressure |
| `leinster` → `dublin` | 2 | 4 | North road; rumor spine |
| `leinster` → `wicklow_glendalough` | 1 | 2 | Highland sanctuary detour |
| `leinster` → `midlands_bogs` | 2 | 4 | Guerrilla payoff approach |
| `wexford_waterford` → `dublin` | 3 | 6 | Coastal / inland choice |
| `dublin` → `wicklow_glendalough` | 1 | 2 | South from Áth Cliath |
| `dublin` → `midlands_bogs` | 2 | 3 | West toward Shannon approaches |
| `midlands_bogs` → `clonmacnoise` | 1 | 2 | Bog → monastic corridor |
| `clonmacnoise` → `shannon` | 0* | 1 | *horse: same-day river embark |
| `shannon` → `connacht` | 2 | 4 | West political pressure |
| `leinster` → `munster_fringe` | 3 | 5 | Secondary conflict |
| `wexford_waterford` → `munster_fringe` | 2 | 4 | Coastal Munster edge |
| `dublin` → `connacht` | 5 | 9 | Expedition; prefer Shannon route |
| `clonmacnoise` → `connacht` | 2 | 4 | Via Shannon corridor |

Full matrix + helpers: `systems/traversal/travel_distances.gd`.

### Timeline coupling

Compressed historical beats already on the clock:

| Event | Day | Map implication |
|---|---|---|
| Bannow landing | 0 | Inside `leinster` |
| Wexford/Waterford struggle | 14 | Player may be in `leinster` or coastal stub |
| Aífe/Strongbow marriage | 28 (when seeded) | Waterford / coastal — travel days should not make presence impossible if the player left on day 20 |
| Dublin approaches / siege | later | Budget **≥ 2 horse days** from Leinster before siege content expects presence |

Rule of thumb: **major event spacing ≥ longest common player hop** on the early
graph (Leinster ↔ Dublin = 2 horse days), so absent-player resolve stays the
default when the player is elsewhere.

---

## Greybox meters vs graph days

| Layer | Unit | Owns |
|---|---|---|
| Local scene | meters (Godot) | Traversal feel, ambush spacing, ringfort yard |
| Region graph | travel days | `WorldClock`, upkeep, rumor age while on the road |
| UI map | abstract nodes + edges | Player planning; do not show fake km |

Do **not** derive graph days from Terrain3D meters. When Terrain3D lands, keep
local scale for readability; keep the day table as the source of truth for
overland cost.

---

## Load strategy (open)

SCOPE defers additive regions vs travel gates until Dublin content. Map scale
assumes:

- **Travel gate (safe default):** choosing a destination advances `WorldClock` by
  edge days, runs band upkeep, then loads the destination scene.
- **Additive later:** same day cost can play as a road montage / simulated
  transit without changing the table.

Shannon as spine = special gate type (boat) when currach ships.

---

## Implementation stubs

| File | Role |
|---|---|
| [`systems/traversal/travel_distances.gd`](../systems/traversal/travel_distances.gd) | Region ids, day matrix, foot/horse lookup |
| [`systems/traversal/README.md`](../systems/traversal/README.md) | API + F5/remote probe notes |
| [`docs/MAP_REGIONS.md`](MAP_REGIONS.md) | Region inventory + layout diagrams (complements this scale doc) |

`Game.current_region` already seeds `&"leinster"`. Callers (map UI, camp rest,
debug) should read distances from `TravelDistances` — do not hardcode days in UI.

---

## Open questions

1. Is Wexford/Waterford a **separate loadable region** in slice, or only landmarks
   + event site tags inside Leinster? (Stubs register it either way.)
2. Does road travel advance **one clock day per edge day** atomically, or allow
   interrupt encounters mid-route?
3. Band size: flat day cost vs `+0.25 day` per N warriors?

Decide before Dublin content; Leinster greybox can ship with gates that only
log “would travel N days” until a second region scene exists.
