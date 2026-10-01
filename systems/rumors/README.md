# Rumors

News of offscreen events and opportunities. Runtime: `scripts/autoload/rumors.gd`
(autoload **`Rumors`**).

| Piece | Role |
|---|---|
| `scripts/autoload/rumors.gd` | Priority + decay bus; Godot list/filter/tick API |
| `scenes/ui/rumors_debug_hud.tscn` | Optional F5 greybox panel (bottom-left; **N**) |

---

## Priority

| Const | Value | Use |
|---|---|---|
| `PRIORITY_LOW` | 1 | Flavor / ambient |
| `PRIORITY_NORMAL` | 2 | Default swings (honor, mild attitude) |
| `PRIORITY_HIGH` | 3 | Coastal pressure, survivor word |
| `PRIORITY_CRITICAL` | 4 | Major timeline resolves (e.g. Bannow summary) |

`get_top_rumors()` / the active list sort **high → low**. Equal priority: fresher
(`age_days` lower) first, then newer `added_day`.

`Rumors.priority_label(p)` → `"low"|"normal"|"high"|"critical"`.

---

## Decay

| Field | Meaning |
|---|---|
| `decay_days` | Lifetime on the bus (≥ 1) |
| `age_days` | Days since add/refresh |
| `days_remaining` | `decay_days - age_days` (helper) |

- `tick_decay(n)` ages every rumor by `n` and **drops** when `age_days >= decay_days`.
- Wired automatically on `WorldClock.day_advanced` (same day tick as Bannow / cattle).
- Call `tick_decay(1)` explicitly in tests or the Rumors debug HUD (**,** key).
- Refresh via `add_rumor` with the same id resets `age_days` to 0 and may raise priority.

Soft cap: `MAX_ACTIVE_RUMORS` (32) — lowest-priority tail is expired first.

---

## Godot call contract

```gdscript
# Emit / refresh (optional tags for diplomatic coupling)
Rumors.add_rumor(&"id", "Text…", &"source", Rumors.PRIORITY_HIGH, 10)
Rumors.add_rumor(
	&"id", "Text…", &"source", Rumors.PRIORITY_HIGH, 10,
	[Rumors.faction_tag(&"anglo_normans"), Rumors.TAG_DIRECTION_WARMER]
)

# List / query
Rumors.get_top_rumors(5)           # priority-sorted
Rumors.list_recent(10)            # newest added_day first
Rumors.filter_rumors(Rumors.PRIORITY_HIGH)                 # min priority
Rumors.filter_rumors(0, &"honor")                          # by source_event
Rumors.filter_rumors(0, &"", true)                         # unheard only
Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_GRAPH)
Rumors.filter_by_faction(&"norse_wexford_waterford")
Rumors.get_rumor(&"id") / Rumors.has_rumor(&"id")
Rumors.count_active()
Rumors.mark_heard(&"id")

# Decay
var expired: Array[StringName] = Rumors.tick_decay(1)
Rumors.days_remaining(rumor_dict)

# Debug / greybox
Rumors.seed_demo_rumors()
print(Rumors.to_debug_dict())
print(Rumors.get_debug_text())
```

### Signals

`rumor_added(rumor_id)`, `rumor_expired(rumor_id)`, `rumors_decayed(expired_ids)`.

### Rumor dict keys

`id`, `text`, `source_event`, `heard`, `priority`, `decay_days`, `age_days`, `added_day`, `tags`.

---

## Emit hooks (already wired)

| Source | When | Typical priority / life | Tags |
|---|---|---|---|
| **Timeline** (`WorldClock._emit_outcome_rumors`) | Event resolve | CRITICAL/HIGH, 7–14d | — |
| **Honor** (`Honor._maybe_rumor_honor`) | `\|delta\| >= RUMOR_HONOR_THRESHOLD` | NORMAL, 7d · source `&"honor"` | — |
| **Factions attitude** (`Factions.modify_attitude`) | `\|delta\| >= RUMOR_ATTITUDE_THRESHOLD` (10) | NORMAL, 5d · source `&"faction"` | `attitude`, `faction:<id>`, `direction:warmer\|colder` |
| **Factions graph** (`set_relationship` / `modify_relationship_strength`) | `\|strength delta\| >= RUMOR_GRAPH_DELTA_THRESHOLD` (15) | NORMAL (HIGH if \|Δ\|≥30), 6d · source `&"faction_graph"` | `graph`, both `faction:<id>`, `direction:*`, `kind:<rel>` |

Callers only touch Factions APIs — rumor seeding is automatic. See
[systems/factions/README.md](../factions/README.md) for thresholds and direction rules.

---

## Tags (diplomatic coupling)

Optional `tags` array on each rumor dict (also accepted by `add_rumor(..., tags)`).

| Tag | Meaning |
|---|---|
| `attitude` | Seeded from player-attitude swing |
| `graph` | Seeded from faction↔faction edge swing |
| `faction:<id>` | Involves roster id (one or two) |
| `direction:warmer` / `direction:colder` | Diplomatic direction |
| `kind:<rel>` | Graph edge kind (`alliance`, `hostility`, …) |

```gdscript
Rumors.faction_tag(&"anglo_normans")           # → &"faction:anglo_normans"
Rumors.filter_by_faction(&"ui_chennselaig")
Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_GRAPH)
Rumors.rumor_has_tag(rumor, Rumors.TAG_DIRECTION_WARMER)
```

### Optional reverse (rumor → light attitude nudge)

When `Rumors.faction_nudge_enabled` (default **true**):

- Priority ≥ `FACTION_NUDGE_MIN_PRIORITY` (**HIGH**)
- At least one `faction:<id>` tag **and** a `direction:warmer|colder` tag
- Source **not** in `{faction, faction_graph}` (avoids feedback loops)

→ applies `±FACTION_NUDGE_AMOUNT` (**2.0**) via `Factions.modify_attitude(..., seed_rumor=false)`.
Nudge runs only on **first add** of that rumor id (refresh does not re-nudge).

Flip off with `Rumors.faction_nudge_enabled = false` if the slice feels noisy.

---

## F5 test path (Rumors debug)

Timeline (**T**) already shows a short rumor list after Bannow (**Y**). For a
dedicated bus panel that does **not** sit on top of Honor (top-left) or Timeline
(top-right):

1. F5 main scene.
2. Press **N** — Rumors panel (bottom-left). Empty until seeded or resolved.
3. **M** — `seed_demo_rumors()` (low/normal/high demo lines).
4. **.** — `Factions.demo_seed_diplomatic_swing()` — attitude + hostility swing;
   panel should show tagged lines (`attitude` / `graph`, `direction:*`, `faction:*`).
5. **,** — `tick_decay(1)` once (watch `left=` / Expired lately).
6. Or **Y** (Timeline) to resolve Bannow and fill CRITICAL/HIGH rumors via the
   timeline emit hook; **N** panel mirrors the bus.
7. **N** again to hide.

Keys: **N** toggle · **M** seed demo · **.** diplomatic swing · **,** decay tick.

Remote / debugger:

```gdscript
print(Rumors.get_debug_text())
Factions.modify_attitude(&"anglo_normans", 12.0)
Factions.modify_relationship_strength(
	&"anglo_normans", &"norse_wexford_waterford", Factions.REL_HOSTILITY, 18.0
)
print(Rumors.filter_by_faction(&"anglo_normans"))
# Reverse nudge probe (outside Factions sources):
Rumors.add_rumor(
	&"probe_harbor_praise",
	"Harbor talk praises the Normans.",
	&"probe",
	Rumors.PRIORITY_HIGH,
	7,
	[Rumors.faction_tag(&"anglo_normans"), Rumors.TAG_DIRECTION_WARMER]
)
print(Factions.get_attitude(&"anglo_normans"))  # +2 if nudge enabled
```
