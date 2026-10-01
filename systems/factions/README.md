# Factions

Faction goals, resources, **relationship graph**, player attitudes, and needs→quest stubs.

Runtime registry: `scripts/autoload/factions.gd` (autoload **`Factions`**).

## Full roster (IDs)

| ID | Display |
|---|---|
| `ui_chennselaig` | Uí Chennselaig / Diarmait |
| `anglo_normans` | Strongbow & adventurers |
| `english_crown` | Henry II (inactive until late / 1171 pressure) |
| `high_kingship` | Ruaidrí / Connacht |
| `norse_dublin` | Norse-Gaelic Dublin |
| `norse_wexford_waterford` | Norse-Gaelic Wexford/Waterford |
| `church` | The Church |
| `local_clans` | Local Leinster túatha / rival clans |
| `fian` | Fían / outlaw bands |

## Slice (Leinster-active)

1. **Uí Chennselaig** — retake Leinster; use Norman allies
2. **Anglo-Normans** — land/power; hold Bannow beachhead
3. **Norse-Gaelic Wexford/Waterford** — protect trade / coastal autonomy

`norse_wexford_waterford` is the third active faction so Bannow Bay → Wexford pressure and the Norse trade contact in `systems/economy/cattle_economy.gd` share one coastal actor. Monolithic `norse_gaelic` was split into Dublin vs Wexford/Waterford. Full roster IDs remain registered; `LEINSTER_ACTIVE` gates quest generation. `english_crown` is registered but inactive until late.

`generate_quest_stubs()` returns 1–2 data-only quest dictionaries from current needs (no quest UI).

---

## Need-pressure tick (hunger / security)

Daily pressure evolves with **WorldClock day commits** — wired inside `Factions`
on `WorldClock.day_advanced`, so missions / greybox never need a second call
(same pattern as `Rumors.tick_decay`).

### Canonical + related needs (Leinster)

| Faction | Canonical | Related (also tick) | Slice flavour |
|---|---|---|---|
| `ui_chennselaig` | `hunger`, `security` | `cattle_tribute`, `warrior_host` | Exile cattle shortfall; rebuilding host |
| `anglo_normans` | `hunger`, `security` | `supplies_landing`, `local_guides` | Beachhead supplies burn; hostile coast |
| `norse_wexford_waterford` | `hunger`, `security` | `harbor_defense`, `trade_cattle` | Harbor threat leads; trade hunger slower |

Rates live in `Factions.need_daily_rates` (per-day pressure deltas, 0…1 scale).
Defaults (tunable via `set_need_daily_rate`):

| Faction | hunger/d | security/d | notes |
|---|---|---|---|
| Uí Chennselaig | **0.035** | **0.028** | Steady exile pressure |
| Anglo-Normans | **0.055** | **0.045** | Fastest hunger climb |
| Norse Wexford/Waterford | **0.025** | **0.065** | Fastest security climb |

Related-need rates are slightly lower mirrors so the trio diverges over a few
**Y** presses instead of starving identically.

### Thresholds (quest / rumor / attitude)

| Constant | Default | Effect (latched per faction+need until pressure clears) |
|---|---|---|
| `NEED_QUEST_THRESHOLD` | **0.4** | Emits `need_threshold_crossed(..., &"quest")` + `generate_quest_stubs(faction)` |
| `NEED_RUMOR_THRESHOLD` | **0.75** | Seeds Rumors (`source=&"faction_need"`, tags `need_pressure` + `faction:*` + `need:*`) |
| `NEED_ATTITUDE_THRESHOLD` | **0.9** | `modify_attitude(id, NEED_ATTITUDE_DELTA)` with `NEED_ATTITUDE_DELTA = -3` (silent; below attitude-rumor floor) |
| `NEED_HOOK_CLEAR_GAP` | **0.15** | Hooks re-arm when pressure falls below `threshold - gap` |

Event resolve still **sets** absolute pressures via `WorldClock` →
`Factions.set_need_pressure` (Bannow / Wexford / Marriage ripples). The daily
tick **adds** rates on top so pressure keeps evolving between authored beats.

### Public API

```gdscript
Factions.apply_need_pressure_tick()                 # usually automatic on day_advanced
Factions.apply_need_pressure_tick(3, WorldClock.day, false)  # force 3 days
Factions.get_need_pressure(&"anglo_normans", Factions.NEED_HUNGER)
Factions.modify_need_pressure(&"anglo_normans", Factions.NEED_SECURITY, 0.1)
Factions.set_need_pressure(&"norse_wexford_waterford", &"harbor_defense", 0.9)
Factions.get_need_daily_rate(&"ui_chennselaig", Factions.NEED_HUNGER)
Factions.set_need_daily_rate(&"ui_chennselaig", Factions.NEED_HUNGER, 0.05)
Factions.to_needs_debug_dict()
Factions.get_needs_debug_text()
Factions.demo_need_pressure_surge(5)               # F5 greybox helper
Factions.generate_quest_stubs()                    # 1–2 stubs when pressure >= 0.4
```

Signals: `need_changed`, `need_threshold_crossed(faction_id, need_id, kind, pressure)`,
`need_pressure_ticked(day, report)`.

### F5 check (need pressure)

1. F5 main scene → **T** (Timeline panel). Confirm Needs block lists Leinster
   hunger/security with per-day rates.
2. **Y** — advances day; need pressures climb (Anglo hunger fastest; Norse
   security fastest). Bannow still resolves on first advance as before.
3. **P** — `demo_need_pressure_surge(5)` without calendar events; watch pressures
   + quest/rumor hooks once past 0.75.
4. Remote: `print(Factions.to_needs_debug_dict())` /
   `print(Factions.apply_need_pressure_tick(2, WorldClock.day, false))`.

Keys (Timeline HUD): **T** toggle · **Y** day (+ need tick) · **P** need surge ·
**U/I/O** force events.

---

## Relationship graph (faction↔faction)

Directed edges among the 9 roster IDs. **Player attitude** stays on `attitudes` / `get_attitude` / `modify_attitude` — the graph is faction-to-faction only.

| Kind constant | Meaning |
|---|---|
| `REL_ALLIANCE` | Formal or wartime alliance |
| `REL_HOSTILITY` | Open enmity / military pressure |
| `REL_OBLIGATION` | Debt, guest-right, treaty terms |
| `REL_PATRONAGE` | Overlord / vassal pull (e.g. crown ↔ barons) |
| `REL_RIVALRY` | Competing claims without open war |
| `REL_TRADE` | Commercial contact |
| `REL_KINSHIP` | Shared blood / cultural affinity |
| `REL_FEUD` | Blood-feud / outlaw predation |

Each edge: `{ from, to, kind, strength (−100…+100), note }`. Multiple kinds may exist on the same directed pair (e.g. alliance + obligation).

### Seed (Leinster-dense)

- Uí Chennselaig ↔ Anglo-Normans: alliance / obligation (Diarmait's invitation)
- Anglo-Normans ↔ Norse Wexford/Waterford: mutual hostility (harbor prizes)
- Uí Chennselaig ↔ High Kingship: rivalry / hostility (exile feud)
- High Kingship → Anglo-Normans: hostility
- Norse Dublin ↔ Wexford/Waterford: kinship / trade
- Anglo-Normans ↔ English crown: patronage (latent 1171)
- Church / local clans / fían: soft obligation, kinship, feud scaffolding

### Query API

```gdscript
Factions.list_relationships()                          # all edges
Factions.list_relationships(&"anglo_normans")          # from filter
Factions.list_relationships(&"", &"ui_chennselaig")     # to filter
Factions.list_leinster_relationships()                 # both ends in LEINSTER_ACTIVE
Factions.list_relationships_involving(&"fian")
Factions.get_relationship(&"ui_chennselaig", &"anglo_normans", Factions.REL_ALLIANCE)
Factions.set_relationship(a, b, Factions.REL_HOSTILITY, 40.0, "note")
Factions.modify_relationship_strength(a, b, Factions.REL_TRADE, 5.0)
# Optional silent write (no rumor seed):
Factions.set_relationship(a, b, Factions.REL_TRADE, 40.0, "", false)
Factions.modify_relationship_strength(a, b, Factions.REL_TRADE, 5.0, false)
Factions.are_allied(&"ui_chennselaig", &"anglo_normans")
Factions.are_hostile(&"anglo_normans", &"norse_wexford_waterford")
Factions.to_relationship_debug_dict()
Factions.demo_seed_diplomatic_swing()                  # F5 greybox helper
```

Signal: `relationship_changed(from_id, to_id, edge)`.

---

## Rumors ↔ graph coupling

Primary direction: **attitude / graph changes → Rumors**. Wired inside the
existing mutate APIs so gameplay callers never need a second rumor call.

| Trigger API | Threshold | Direction rule | Rumor source / tags |
|---|---|---|---|
| `modify_attitude(id, delta)` | `\|delta\| >= RUMOR_ATTITUDE_THRESHOLD` (**10**) | delta > 0 → warmer | `&"faction"` · `attitude` + `faction:<id>` + `direction:*` |
| `set_relationship` / `modify_relationship_strength` | `\|Δstrength\| >= RUMOR_GRAPH_DELTA_THRESHOLD` (**15**) | Amicable kinds (alliance/obligation/patronage/trade/kinship): strength up → warmer. Hostile/rival/feud: strength up → colder | `&"faction_graph"` · `graph` + both `faction:*` + `direction:*` + `kind:<rel>` |

- Graph rumor priority elevates to **HIGH** when `\|Δstrength\| >= RUMOR_GRAPH_HIGH_DELTA` (**30**).
- Boot seed (`_seed_relationship_graph` / `_add_edge_raw`) does **not** emit rumors.
- `modify_attitude(..., seed_rumor=false)` / `set_relationship(..., seed_rumor=false)` skip seeding (used by reverse nudge).

Optional reverse (gated on Rumors): HIGH+ faction-tagged rumors from non-Factions
sources can apply ±2 attitude — see [systems/rumors/README.md](../rumors/README.md).

### F5 check (diplomatic coupling)

1. F5 main scene → **N** (Rumors panel).
2. **.** — runs `Factions.demo_seed_diplomatic_swing()`:
   - Anglo-Normans attitude +12 → tagged attitude rumor (`direction:warmer`)
   - Hostility vs Norse Wexford/Waterford +18 → tagged graph rumor (`direction:colder`)
3. Confirm panel lines show `{attitude,...}` / `{graph,...}` tag suffixes.
4. Remote alternative: the `modify_attitude` / `modify_relationship_strength` calls above.
