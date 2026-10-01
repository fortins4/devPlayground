# World Timeline

Historical clock and event definitions (Bannow Bay landing → Wexford/Waterford → Aífe/Strongbow marriage).

Runtime: `scripts/autoload/world_clock.gd`.

## EventOutcome schema

Shared resource: [`event_outcome.gd`](event_outcome.gd) (`class_name EventOutcome`).

| Field | Role |
|---|---|
| `event_id`, `display_name`, `scheduled_day` | Identity + calendar slot |
| `player_present` | Absent → history-weighted resolve; present → gameplay/world state |
| `troops`, `morale`, `supplies` | Force variables (0..1 normalized in slice) |
| `key_survivors` | `StringName → bool` (lived / died-or-captured) |
| `clan_allegiance` | `StringName → StringName` (clan → allegiance tag) |
| `historical_bias` + `historical_*` | Weights used when the player is absent |
| `result_tag`, `result_summary`, `resolved` | Post-resolve outputs for factions / rumors |

`WorldClock.adjust_event_variable()` mutates live fields before resolve.
`WorldClock.set_player_present()` toggles history bias.
On resolve, outcomes call `apply_history_weight()` when absent; result ripples into
`Factions` attitudes + need pressures, and multiple `Rumors` entries (critical
summary + survivor / coastal flavor).

### Day-advance semantics

- Calendar starts at **day 0** (Bannow landing day; event seeded unresolved).
- `advance_day(n)` increments `day`, emits `day_advanced`, then resolves **all**
  unresolved events with `scheduled_day <= day` (overdue-inclusive).
- Therefore the **first** `advance_day(1)` resolves Bannow Bay (scheduled day 0).
- **Event #2** `wexford_waterford_struggle` is scheduled on **day 14** (after Bannow).
- **Event #3** `aife_strongbow_marriage` is scheduled on **day 28** (after Wexford/Waterford).
- `force_resolve(event_id)` resolves immediately without advancing the calendar
  (debug / content hooks).

Design source: `docs/SCOPE.md` (lock one shared EventOutcome schema before content multiplies).

---

## Seeded events

| ID | Day | Historical lean | Result tags |
|---|---|---|---|
| `bannow_bay_landing` | 0 | Norman foothold | `norman_foothold` / `contested_landing` / `landing_checked` |
| `wexford_waterford_struggle` | 14 | Ports fall to Norman–Diarmait pressure | `towns_fall` / `towns_contested` / `towns_hold` |
| `aife_strongbow_marriage` | 28 | Dynastic seal via Aífe ↔ Strongbow | `marriage_sealed` / `marriage_contested` / `marriage_blocked` |

Events #2 and #3 use the same EventOutcome variables. Absent-player resolve blends toward
historical troops/morale/supplies; present-player content mutates via
`adjust_event_variable` / `set_player_present` before the scheduled day (or `force_resolve`).

Ripples on resolve (attitudes, need pressures, rumors) are tagged per `result_tag`
— see `_ripple_attitudes`, `_ripple_need_pressures`, `_emit_outcome_rumors` in
`world_clock.gd`. Marriage seals lean Norman/Uí Chennselaig up and High Kingship /
Dublin down; blocked flips that pressure.

---

## F5 test path (Bannow → Wexford → Marriage debug)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **T** — Timeline debug panel appears (top-right). Confirm:
   - `Day: 0`
   - `Bannow: … resolved=false`
   - `Wexford/Waterford: day=14 resolved=false`
   - `Aífe/Strongbow: day=28 resolved=false`
   - Leinster attitudes at seed values
   - `Rumors (0 active)`
3. Press **Y** once — advances to day 1 and resolves Bannow (absent-player,
   history-weighted → typically `norman_foothold`).
4. Keep pressing **Y** (or `WorldClock.advance_day(14)` from the remote) until
   day ≥ 14 — Wexford/Waterford resolves (typically `towns_fall`).
5. Continue to day ≥ 28 — Aífe/Strongbow marriage resolves (typically `marriage_sealed`).
6. Optional force keys:
   - **U** force-resolves Bannow without advancing
   - **I** force-resolves Wexford/Waterford without advancing
   - **O** force-resolves Aífe/Strongbow marriage without advancing
7. Pre-resolve mutation example (before the marriage day):
   ```gdscript
   WorldClock.set_player_present(&"aife_strongbow_marriage", true)
   WorldClock.adjust_event_variable(&"aife_strongbow_marriage", &"troops", 0.2)
   WorldClock.adjust_event_variable(&"aife_strongbow_marriage", &"morale", 0.2)
   WorldClock.adjust_event_variable(&"aife_strongbow_marriage", &"supplies", 0.2)
   WorldClock.force_resolve(&"aife_strongbow_marriage")  # expect marriage_blocked
   ```
8. Press **T** again to hide the panel.

Keys: **T** toggle · **Y** advance day · **U** Bannow · **I** Wexford/Waterford · **O** Marriage.
