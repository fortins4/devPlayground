# World Timeline

Historical clock and event definitions (Bannow Bay landing first; Wexford/Waterford struggle second).

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
- `force_resolve(event_id)` resolves immediately without advancing the calendar
  (debug / content hooks).

Design source: `docs/SCOPE.md` (lock one shared EventOutcome schema before content multiplies).

---

## Seeded events

| ID | Day | Historical lean | Result tags |
|---|---|---|---|
| `bannow_bay_landing` | 0 | Norman foothold | `norman_foothold` / `contested_landing` / `landing_checked` |
| `wexford_waterford_struggle` | 14 | Ports fall to Norman–Diarmait pressure | `towns_fall` / `towns_contested` / `towns_hold` |

Event #2 uses the same EventOutcome variables. Absent-player resolve blends toward
historical troops/morale/supplies; present-player content mutates via
`adjust_event_variable` / `set_player_present` before day 14 (or `force_resolve`).

Ripples on resolve (attitudes, need pressures, rumors) are tagged per `result_tag`
— see `_ripple_attitudes`, `_ripple_need_pressures`, `_emit_outcome_rumors` in
`world_clock.gd`.

---

## F5 test path (Bannow → Wexford debug)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **T** — Timeline debug panel appears (top-right). Confirm:
   - `Day: 0`
   - `Bannow: … resolved=false`
   - `Wexford/Waterford: day=14 resolved=false`
   - Leinster attitudes at seed values
   - `Rumors (0 active)`
3. Press **Y** once — advances to day 1 and resolves Bannow (absent-player,
   history-weighted → typically `norman_foothold`).
4. Keep pressing **Y** (or `WorldClock.advance_day(14)` from the remote) until
   day ≥ 14 — Wexford/Waterford resolves (typically `towns_fall`).
5. Optional force keys:
   - **U** force-resolves Bannow without advancing
   - **I** force-resolves Wexford/Waterford without advancing
6. Pre-resolve mutation example (before the event's day):
   ```gdscript
   WorldClock.set_player_present(&"wexford_waterford_struggle", true)
   WorldClock.adjust_event_variable(&"wexford_waterford_struggle", &"troops", 0.2)
   WorldClock.adjust_event_variable(&"wexford_waterford_struggle", &"morale", 0.2)
   WorldClock.adjust_event_variable(&"wexford_waterford_struggle", &"supplies", 0.2)
   WorldClock.force_resolve(&"wexford_waterford_struggle")  # expect towns_hold
   ```
7. Press **T** again to hide the panel.

Keys: **T** toggle · **Y** advance day · **U** force Bannow · **I** force Wexford/Waterford.
