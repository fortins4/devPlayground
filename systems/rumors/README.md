# Rumors

News of offscreen events and opportunities. Runtime: `scripts/autoload/rumors.gd`
(autoload **`Rumors`**).

| Piece | Role |
|---|---|
| `scripts/autoload/rumors.gd` | Priority/severity + decay bus; Godot list/filter/tick API |
| `scenes/ui/rumors_debug_hud.tscn` | Optional F5 greybox panel (bottom-left; **N**) |
| `tools/probe_rumors_honor_prestige.gd` | Headless / remote prestige ↔ Honor probe |

Severity is a **documented alias of priority** (same ints / ladder). High-severity
rumors linger; low ones fade via the default decay table below.

---

## Priority / severity

| Const | Severity alias | Value | Use |
|---|---|---|---|
| `PRIORITY_LOW` | `SEVERITY_LOW` | 1 | Flavor / ambient |
| `PRIORITY_NORMAL` | `SEVERITY_NORMAL` | 2 | Default swings (honor, mild attitude) |
| `PRIORITY_HIGH` | `SEVERITY_HIGH` | 3 | Coastal pressure, survivor word, need spikes |
| `PRIORITY_CRITICAL` | `SEVERITY_CRITICAL` | 4 | Major timeline resolves (e.g. Bannow summary) |

`get_top_rumors()` / the active list sort **high → low**. Equal priority: fresher
(`age_days` lower) first, then newer `added_day`.

`Rumors.priority_label(p)` / `Rumors.severity_label(p)` → `"low"|"normal"|"high"|"critical"`.

---

## Decay (severity → lifetime / half-life)

Default full lifetime and informational half-life by severity. Callers may still
pass an explicit `decay_days`; pass **`0` / omit** to use this table
(`add_rumor` default is now `0` → table resolve).

| Severity | Priority | Lifetime `decay_days` | Half-life (midpoint) | Per-day rate |
|---|---|---|---|---|
| low | 1 | **4** | 2 | 0.250 |
| normal | 2 | **7** | 4 | ≈0.143 |
| high | 3 | **12** | 6 | ≈0.083 |
| critical | 4 | **18** | 9 | ≈0.056 |

Constants: `DEFAULT_DECAY_DAYS_BY_PRIORITY`, `DEFAULT_HALF_LIFE_DAYS_BY_PRIORITY`.
Helpers: `default_decay_days(p)`, `default_half_life_days(p)`, `resolve_decay_days(p, override)`,
`decay_table()`.

| Field / helper | Meaning |
|---|---|
| `decay_days` | Lifetime on the bus (≥ 1 after resolve) |
| `age_days` | Days since add/refresh |
| `days_remaining` | `decay_days - age_days` |
| `half_life_days(rumor)` | `ceil(decay_days / 2)` — midpoint only |
| `decay_progress(rumor)` | `age_days / decay_days` (0 fresh → 1 at drop) |
| `decay_rate_per_day(rumor)` | `1 / decay_days` |
| `is_past_half_life(rumor)` | `age_days >= half_life` (still on the bus) |

### `tick_decay` behavior

- `tick_decay(n)` ages every rumor by `n` and **hard-drops** when `age_days >= decay_days`.
- **Half-life is informational only** — no stochastic drop at the midpoint.
- Wired automatically on `WorldClock.day_advanced` → `tick_decay(1)`.
- Call `tick_decay(1)` explicitly in tests or the Rumors debug HUD (**,** key).
- Per expired id: `rumor_expired`; then `rumors_decayed(expired_ids)` if any dropped.
- Refresh via `add_rumor` with the same id resets `age_days` to 0 and may raise priority
  / extend lifetime (`maxi` of old vs new `decay_days`).

Soft cap: `MAX_ACTIVE_RUMORS` (32) — lowest-priority tail is expired first.

Emitter override note: Timeline / Honor / Factions / raid heat still pass explicit
lifetimes where authored (e.g. attitude 5d, graph 6d, raid 8–10d, Bannow summary 14d).
Those stay as-written; new emitters can pass `0` to adopt the table.

---

## Godot call contract

```gdscript
# Emit / refresh — decay_days <= 0 uses severity table (HIGH → 12d, CRITICAL → 18d, …)
Rumors.add_rumor(&"id", "Text…", &"source", Rumors.PRIORITY_HIGH)  # table default
Rumors.add_rumor(&"id", "Text…", &"source", Rumors.SEVERITY_CRITICAL, 0)
Rumors.add_rumor(
	&"id", "Text…", &"source", Rumors.PRIORITY_HIGH, 10,
	[Rumors.faction_tag(&"anglo_normans"), Rumors.TAG_DIRECTION_WARMER]
)

# List / query
Rumors.get_top_rumors(5)           # priority-sorted
Rumors.list_recent(10)            # newest added_day first
Rumors.filter_rumors(Rumors.PRIORITY_HIGH)                 # min priority
Rumors.filter_by_severity(Rumors.SEVERITY_HIGH)            # same floor, severity name
Rumors.get_active_by_severity(Rumors.SEVERITY_CRITICAL, true)  # exact rung
Rumors.get_active_by_severity(Rumors.SEVERITY_HIGH)            # HIGH+
Rumors.severity_counts()           # {low, normal, high, critical, total}
Rumors.peek_expiring(1)           # hard-drop within 1 more tick
Rumors.filter_rumors(0, &"honor")                          # by source_event
Rumors.filter_rumors(0, &"", true)                         # unheard only
Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_GRAPH)
Rumors.filter_by_faction(&"norse_wexford_waterford")
Rumors.filter_by_prestige()                          # honor/prestige/enech tags
Rumors.filter_by_prestige(Rumors.PRIORITY_HIGH)      # HIGH+ prestige only
Rumors.build_prestige_tags(true, &"church")          # honor+prestige+enech+warmer+faction
Rumors.rumor_has_prestige_tag(rumor_dict)
Rumors.get_rumor(&"id") / Rumors.has_rumor(&"id")
Rumors.count_active()
Rumors.mark_heard(&"id")

# Decay helpers
var expired: Array[StringName] = Rumors.tick_decay(1)
Rumors.days_remaining(rumor_dict)
Rumors.half_life_days(rumor_dict)
Rumors.decay_progress(rumor_dict)
Rumors.is_past_half_life(rumor_dict)
Rumors.decay_table()
Rumors.resolve_decay_days(Rumors.PRIORITY_LOW, 0)  # → 4

# Debug / greybox / remote
Rumors.seed_demo_rumors()          # one line per severity, table lifetimes
print(Rumors.probe_decay(true))    # seed if empty + table + by_severity + tick notes
print(Rumors.probe_prestige(true)) # Honor prestige swing + HIGH+ prestige rows + loop_guard
print(Rumors.to_debug_dict())
print(Rumors.get_debug_text())
```

### Signals

`rumor_added(rumor_id)`, `rumor_expired(rumor_id)`, `rumors_decayed(expired_ids)`.

### Rumor dict keys

`id`, `text`, `source_event`, `heard`, `priority`, `decay_days`, `age_days`, `added_day`, `tags`.

Debug rows also expose `severity`, `severity_label`, `half_life_days`, `decay_progress`,
`decay_rate_per_day`, `past_half_life`.

---

## Emit hooks (already wired)

| Source | When | Typical priority / life | Tags |
|---|---|---|---|
| **Timeline** (`WorldClock._emit_outcome_rumors`) | Event resolve | CRITICAL/HIGH, 7–14d (explicit) | — |
| **Honor** (`Honor._maybe_rumor_honor` / `modify_honor`) | `\|delta\| >= RUMOR_HONOR_THRESHOLD` (8); HIGH if `\|delta\| >= RUMOR_HONOR_HIGH_THRESHOLD` (15) | NORMAL 7d / HIGH 12d · source `&"honor"` | `honor`, `prestige`, `enech`, `direction:warmer\|colder`, optional `faction:<id>` |
| **Factions attitude** (`Factions.modify_attitude`) | `\|delta\| >= RUMOR_ATTITUDE_THRESHOLD` (10) | NORMAL, 5d · source `&"faction"` | `attitude`, `faction:<id>`, `direction:warmer\|colder` |
| **Factions graph** (`set_relationship` / `modify_relationship_strength`) | `\|strength delta\| >= RUMOR_GRAPH_DELTA_THRESHOLD` (15) | NORMAL (HIGH if \|Δ\|≥30), 6d · source `&"faction_graph"` | `graph`, both `faction:<id>`, `direction:*`, `kind:<rel>` |
| **Cattle-raid heat** (`CattleRaidOutcomes.resolve_success` / `resolve_failure`) | `\|attitude\| ≥ 10` **or** honor heat mag ≥ 8 **or** (past mercy **and** retaliation severity ≥ 0.5) | NORMAL (HIGH if escalated), 8–10d · source `&"raid"` | `raid`, `heat`, `faction:<victim>`, `direction:colder`, optional `retaliation` |
| **Sanctuary breach** (`SanctuaryLocations.report_breach` / `resolve_breach`) | Director / stealth / combat reports steel-in-precinct at a known site | HIGH, 12d · source `&"sanctuary_breach"` | `church`, `sanctuary`, `breach`, `heat`, `faction:church`, `direction:colder`, `site:<id>` |

Callers touch Factions / CattleEconomy / SanctuaryLocations resolve APIs — rumor seeding
is automatic on those paths. See [systems/factions/README.md](../factions/README.md),
[systems/raid/README.md](../raid/README.md), and
[systems/sanctuary/README.md](../sanctuary/README.md) for thresholds and tags.

---

## Tags (diplomatic coupling)

Optional `tags` array on each rumor dict (also accepted by `add_rumor(..., tags)`).

| Tag | Meaning |
|---|---|
| `attitude` | Seeded from player-attitude swing |
| `graph` | Seeded from faction↔faction edge swing |
| `raid` | Seeded from cattle-raid economy heat (`Rumors.TAG_RAID`) |
| `heat` | Honor / attitude heat swing from a raid (`Rumors.TAG_HEAT`) |
| `retaliation` | Escalated raid heat past mercy (`Rumors.TAG_RETALIATION`) |
| `church` | Church / monastic domain (`Rumors.TAG_CHURCH`) |
| `sanctuary` | Monastic precinct / refuge (`Rumors.TAG_SANCTUARY`) |
| `breach` | Sanctuary violated — steel/blood in precinct (`Rumors.TAG_BREACH`) |
| `honor` | Seeded from Honor / enech swing (`Rumors.TAG_HONOR`) |
| `prestige` | Prestige-relevant bus entry — HIGH+ or Honor swing (`Rumors.TAG_PRESTIGE`) |
| `enech` | Brehon honor-price standing (`Rumors.TAG_ENECH`) |
| `faction:<id>` | Involves roster id (one or two) |
| `site:<id>` | SanctuaryLocations site id (e.g. `site:glendalough`) |
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
- Source **not** in `{faction, faction_graph, raid, sanctuary_breach}` (avoids feedback loops)

→ applies `±FACTION_NUDGE_AMOUNT` (**2.0**) via `Factions.modify_attitude(..., seed_rumor=false)`.
Nudge runs only on **first add** of that rumor id (refresh does not re-nudge).

Flip off with `Rumors.faction_nudge_enabled = false` if the slice feels noisy.

### Optional reverse (rumor → light Honor / prestige nudge)

When `Rumors.honor_nudge_enabled` (default **true**):

- Priority ≥ `HONOR_NUDGE_MIN_PRIORITY` (**HIGH**)
- At least one of `honor` / `prestige` / `enech` **and** a `direction:warmer|colder` tag
- Source **not** in `{honor, raid, sanctuary_breach}` (avoids feedback loops)

→ applies `±HONOR_NUDGE_AMOUNT` (**1.5**) via `Honor.modify_honor(..., seed_rumor=false)`.
- No `faction:*` → nudges **overall** enech.
- With `faction:*` → nudges each tagged faction (overall still drifts ×0.25 inside `modify_honor`).
- Nudge runs only on **first add** of that rumor id (refresh does not re-nudge).

**Loop guard:** Honor→Rumors uses `source=&"honor"` (skipped by reverse). Reverse always
passes `seed_rumor=false` so the nudge cannot re-seed prestige rumors.

Flip off with `Rumors.honor_nudge_enabled = false` if the slice feels noisy.

---

## F5 test path (Rumors debug)

**No Godot binary in this ticket** — Lead runs F5; remote `probe_decay` is enough for smoke.

Timeline (**T**) already shows a short rumor list after Bannow (**Y**). For a
dedicated bus panel that does **not** sit on top of Honor (top-left) or Timeline
(top-right):

1. F5 main scene.
2. Press **N** — Rumors panel (bottom-left). Empty until seeded or resolved.
3. **M** — `seed_demo_rumors()` (low/normal/high/**critical** demo lines; table lifetimes 4/7/12/18).
   HIGH/CRITICAL demos carry `honor`/`prestige` tags (no `direction:*` — avoids reverse nudge on **M**).
4. Confirm panel shows severity counts + `Default life/half: L 4/2 · N 7/4 · H 12/6 · C 18/9`.
5. **,** — `tick_decay(1)` once (watch `left=` / `life=` / `hl+` after half-life / Expired lately).
   - After **4** commas, the LOW demo should drop; CRITICAL should still show `left=` high.
6. **.** — `Factions.demo_seed_diplomatic_swing()` — attitude + hostility swing;
   panel should show tagged lines (`attitude` / `graph`, `direction:*`, `faction:*`).
6b. **/** — `Honor.demo_seed_prestige_swing()` — overall +16 / church −16;
   panel should show `{honor,prestige,enech,direction:*,faction:church?}` at **HIGH**.
7. Or **Y** (Timeline) to resolve Bannow and fill CRITICAL/HIGH rumors via the
   timeline emit hook; **N** panel mirrors the bus.
8. Cattle-raid heat: deliver the south greybox drove **past mercy** (3rd success
   on the same victim) — bus should show `{raid,heat,faction:*,direction:colder,retaliation}`.
   See [systems/raid/README.md](../raid/README.md) F5 notes / thresholds.
9. Sanctuary breach (Remote): `SanctuaryLocations.resolve_breach(&"glendalough")` —
   bus should show `{church,sanctuary,breach,heat,faction:church,direction:colder,site:glendalough}`.
   See [systems/sanctuary/README.md](../sanctuary/README.md).
10. **N** again to hide.

Keys: **N** toggle · **M** seed demo · **.** diplomatic swing · **/** prestige swing · **,** decay tick.

### Remote / debugger probe

```gdscript
print(Rumors.probe_decay(true))
# → ok, decay_table.rows, severity_counts, by_severity.{low,normal,high,critical},
#   peek_expiring_1, tick_behavior

print(Rumors.get_debug_text())
print(Rumors.decay_table())
print(Rumors.get_active_by_severity(Rumors.SEVERITY_HIGH))
print(Rumors.severity_counts())

# Manual linger check (no F5):
Rumors.clear_all()
Rumors.seed_demo_rumors()
for i in 4:
	Rumors.tick_decay(1)
print(Rumors.severity_counts())
# Expect low=0; normal/high/critical still present (lives 7/12/18)

Factions.modify_attitude(&"anglo_normans", 12.0)
Factions.modify_relationship_strength(
	&"anglo_normans", &"norse_wexford_waterford", Factions.REL_HOSTILITY, 18.0
)
print(Rumors.filter_by_faction(&"anglo_normans"))
# Sanctuary breach tags (after SanctuaryLocations.resolve_breach):
print(Rumors.filter_rumors(0, &"", false, false, Rumors.TAG_BREACH))
print(SanctuaryLocations.probe_remote(true))
# Reverse nudge probe (outside Factions sources):
Rumors.add_rumor(
	&"probe_harbor_praise",
	"Harbor talk praises the Normans.",
	&"probe",
	Rumors.PRIORITY_HIGH,
	0,  # table → 12d
	[Rumors.faction_tag(&"anglo_normans"), Rumors.TAG_DIRECTION_WARMER]
)
print(Factions.get_attitude(&"anglo_normans"))  # +2 if nudge enabled

# Prestige / Honor coupling:
print(Rumors.probe_prestige(true))   # Honor.demo_seed_prestige_swing + filter rows
print(Honor.get_rumor_honor_thresholds())
print(Rumors.filter_by_prestige(Rumors.PRIORITY_HIGH))
# Reverse Honor nudge (outside honor/raid/sanctuary sources):
var before := Honor.get_honor()
Rumors.add_rumor(
	&"probe_prestige_praise",
	"Hall talk lifts Cian's enech.",
	&"probe",
	Rumors.PRIORITY_HIGH,
	0,
	Rumors.build_prestige_tags(true)
)
print(Honor.get_honor() - before)  # +1.5 if honor_nudge_enabled
```

### Headless probe script (when Godot binary available)

```bash
godot --headless --path . --script res://tools/probe_rumors_honor_prestige.gd
```

Expect `PROBE_RUMORS_HONOR_PRESTIGE_OK`. No Godot binary on agent boxes — use F5 + **/** / Remote paste instead.

