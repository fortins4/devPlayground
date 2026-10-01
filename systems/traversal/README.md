# Traversal / map scale

Overland region graph for Leinster → Ireland. Design: [`docs/MAP_SCALE.md`](../../docs/MAP_SCALE.md)
(scale & days) · [`docs/MAP_REGIONS.md`](../../docs/MAP_REGIONS.md) (layout viz / inventory).

| Piece | Role |
|---|---|
| [`travel_distances.gd`](travel_distances.gd) (`class_name TravelDistances`) | Region ids, horse/foot day matrix, shortest path |
| [`travel_gate.gd`](travel_gate.gd) (`class_name TravelGate`) | Preview / request / commit travel → `WorldClock` + `Game.current_region` |
| `Game.current_region` | Live region id (seeds `&"leinster"`); `Game.set_current_region` / `region_changed` |
| `scenes/ui/travel_debug_hud.tscn` | F5 greybox panel (instanced on `scenes/main/main.tscn`) |
| Horse greybox (this slice) | Local mount/dismount + ride loop on F5 main |

No scene loads here — the gate advances the living calendar and updates the
session region id. Greybox / streaming swaps stay caller-owned.

Church sanctuary sites that hang off these region ids: [`systems/sanctuary/`](../sanctuary/) (`glendalough` → `wicklow_glendalough`, `clonmacnoise` → `clonmacnoise`).

Calendar / event resolve that travel days can trigger: [`systems/timeline/`](../timeline/) (`WorldClock.advance_day`).

## Local horse (greybox)

Playable mount for open-world traversal feel — not full cavalry combat.

| Piece | Path |
|---|---|
| Horse scene | [`scenes/characters/horse/horse.tscn`](../../scenes/characters/horse/horse.tscn) |
| Controller | [`scripts/characters/horse/horse_controller.gd`](../../scripts/characters/horse/horse_controller.gd) |
| Player mount hooks | `prepare_for_mount` / `clear_mount` on `player_controller.gd` |
| F5 wiring | `HorseLane` near spawn in [`scenes/main/main.tscn`](../../scenes/main/main.tscn) (+Z / SE of player) |

### Controls

| Input | Action |
|---|---|
| **E** (interact) | Mount when near / dismount when riding |
| WASD | Ride (horse-local; mouse yaws the horse) |
| Mouse | Look (yaw → horse, pitch → camera) |
| Shift | Gallop (~14 m/s vs trot ~7.5) |
| Space | Short hop while mounted |
| LMB / RMB / weapons | **Blocked** while mounted — dismount to fight |

Combat lane (−Z dummy) and stealth lane (+X) stay intact. FULL bog corpse-drag is live; mounting clears an active drag and mounted state blocks new drags / melee.

Speeds are local greybox meters (feel), separate from `TravelDistances` calendar days on the region graph.

## API — distances

```gdscript
TravelDistances.horse_days(&"leinster", &"dublin")     # 2
TravelDistances.foot_days(&"leinster", &"dublin")      # 4
TravelDistances.list_connections(&"leinster")          # neighbour rows
TravelDistances.shortest_path(&"leinster", &"connacht", &"horse")
TravelDistances.shortest_horse_path(&"leinster", &"connacht")  # wrapper
print(TravelDistances.get_debug_text())
```

Days are **calendar days** on the living clock when the player commits a travel
gate. Local greybox meters are separate (see MAP_SCALE).

## API — travel gate

```gdscript
# Preview / request (no clock change)
var preview := TravelGate.preview_travel(&"leinster", &"dublin")
# preview.ok / preview.days / preview.path / preview.reason

var req := TravelGate.request_travel(&"dublin")  # from Game.current_region
TravelGate.can_travel(&"leinster", &"dublin")

# Commit: WorldClock.advance_day(days) then Game.set_current_region(to)
var result := TravelGate.commit_travel(&"dublin")  # horse, path allowed
# result.day_before / result.day_after / result.summary

# Gate knobs (slice stubs)
TravelGate.expedition_day_budget = 3   # -1 unlimited; over → insufficient_days
TravelGate.set_expedition_day_budget(5)
TravelGate.adjust_expedition_day_budget(-1)  # also leaves unlimited on first press
TravelGate.clear_expedition_day_budget()     # back to -1 unlimited
TravelGate.direct_edges_only = true    # no multi-hop; missing edge → blocked_edge

# Budget vs planned trip (HUD / Remote)
var st := TravelGate.get_expedition_budget_status(2)
# st.budget / st.unlimited / st.planned_days / st.remaining_after
# st.insufficient_days / st.spare_days / st.summary
```

Preview / commit payloads include `planned_days`, `expedition_day_budget`,
`insufficient_days`, and (on success) `budget_remaining_after`. A successful
`commit_travel` **spends** trip days from a limited budget (`budget_remaining`
on the result).

### Gate reasons (fail closed)

| Reason | When |
|---|---|
| `same_region` | origin == destination |
| `unknown_region` | id not in `REGION_IDS` |
| `blocked_edge` | `direct_edges_only` (or `allow_path=false`) and no stub edge |
| `unreachable` | no path on the region graph |
| `insufficient_days` | `expedition_day_budget >= 0` and cost exceeds it |
| `missing_clock` / `missing_game` | autoload missing on commit |

Same-day edges (`days == 0`, e.g. clonmacnoise → shannon on horse) still change
`Game.current_region` but do **not** call `advance_day`.

Multi-day commits call `WorldClock.advance_day(n)` once per day so factions /
needs / rumors / cattle ticks and overdue timeline events resolve along the road
(see timeline README day-advance semantics).

## Day budget (expeditions)

`TravelGate.expedition_day_budget` is the soft allotment for overland hops
(complements the gate already on main via PR #38):

| Value | Meaning |
|---|---|
| `-1` | Unlimited (default) |
| `>= 0` | Remaining calendar days the party may spend |

- Preview compares **planned trip cost** (`days` / `planned_days`) to the budget.
- Cost over budget → reason `insufficient_days` (fail closed; no clock / region change).
- Successful commit subtracts spent days from a limited budget.
- Debug HUD (**G**) shows budget remaining, planned cost, and insufficient status;
  **-** / **=** tune the budget; **L** resets to unlimited.

## Slice stance

- Only `leinster` is an authored roam region in the vertical slice.
- Other ids exist so UI / timeline / rumors can talk about destinations and so
  event spacing (Bannow → ports → marriage → Dublin) stays honest against travel cost.
- Travel gate does **not** load other region scenes yet — region id + calendar only.
- Horse entity is a **hobby / pony** greybox stand-in (Irish early-medieval vibe), not a warhorse combat mount yet.

## F5 test path (Travel gate debug)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **G** — Travel gate panel (bottom-right). Confirm:
   - `Region: leinster`
   - `WorldClock day: 0`
   - `Day budget: unlimited`
   - Destinations list includes `dublin` at 2 horse-days
3. Press **K** until dest is `dublin`, confirm preview `ok=true` and **Planned trip cost: 2 d**.
4. Press **-** twice (leaves unlimited → budget 0, then stays 0) then **=** until budget is **1**.
   Preview for `dublin` (2 d) should show **Status: INSUFFICIENT_DAYS**.
5. Press **=** once more (budget 2) — preview OK again; **remaining after 0 d**.
6. Press **B** — commits travel:
   - `Game.current_region` → `dublin`
   - WorldClock advances to day **2** (and Bannow resolves on the first advance)
   - Day budget remaining → **0** (spent 2)
7. Press **L** — budget back to **unlimited**. Press **T** — Timeline shows `Day: 2` + Bannow resolved.
8. Optional gate probes (Remote / Debugger):
   ```gdscript
   print(TravelGate.preview_travel(&"dublin", &"dublin"))           # same_region
   TravelGate.direct_edges_only = true
   print(TravelGate.preview_travel(&"leinster", &"connacht", &"horse", false))  # blocked_edge
   TravelGate.direct_edges_only = false
   TravelGate.set_expedition_day_budget(1)
   print(TravelGate.request_travel(&"munster_fringe"))              # insufficient_days if from leinster (3)
   print(TravelGate.get_expedition_budget_status(3))
   TravelGate.clear_expedition_day_budget()
   print(TravelGate.commit_travel(&"wicklow_glendalough"))
   print(TravelGate.to_debug_dict())
   ```
9. Press **F** to toggle foot mode; **J** / **K** cycle destinations; **G** hide.

Keys: **G** toggle · **J** / **K** cycle dest · **F** horse/foot · **-** / **=** budget · **L** unlimited · **B** commit.

Timeline debug remains **T** / **Y** / **U** / **I** / **O** (top-right).

Horse greybox: walk to **HorseLane** (+Z / SE of spawn), **E** mount/dismount, WASD ride, Shift gallop.

## Remote probe

```gdscript
print(TravelDistances.to_debug_dict())
print(TravelDistances.list_connections(&"dublin", &"foot"))
print(TravelGate.request_travel(&"wexford_waterford"))
print(TravelGate.commit_travel(&"wexford_waterford"))
print(TravelGate.to_debug_dict())
```
