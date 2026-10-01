# World Timeline

Historical clock and event definitions (Bannow Bay landing first).

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
- `force_resolve(event_id)` resolves immediately without advancing the calendar
  (debug / content hooks).

Design source: `docs/SCOPE.md` (lock one shared EventOutcome schema before content multiplies).

---

## F5 test path (Bannow day-advance debug)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **T** — Timeline debug panel appears (top-right). Confirm:
   - `Day: 0`
   - `Bannow: resolved=false  tag=(pending)`
   - Leinster attitudes at seed values (ui_chennselaig ~10, anglo_normans ~-25,
     norse_wexford_waterford ~0)
   - `Rumors (0 active)`
3. Press **Y** once — advances to day 1 and resolves Bannow (absent-player,
   history-weighted → typically `norman_foothold`).
4. Panel should now show:
   - `Day: 1`, `Bannow: resolved=true  tag=norman_foothold` (or contested/checked
     if you lowered troops/morale/supplies first)
   - Attitude deltas (e.g. anglo_normans up, norse_wexford_waterford down on foothold)
   - Several active rumors (critical landing summary + survivors + Wexford pressure)
   - A line under `Recent resolves`
5. Optional checks:
   - **U** force-resolves Bannow without advancing (no-op if already resolved).
   - Remote: `print(WorldClock.to_debug_dict())` / `print(WorldClock.get_debug_text())`
   - Pre-resolve mutation example (Debugger / temp script before Y):
     ```gdscript
     WorldClock.set_player_present(&"bannow_bay_landing", true)
     WorldClock.adjust_event_variable(&"bannow_bay_landing", &"troops", 0.2)
     WorldClock.adjust_event_variable(&"bannow_bay_landing", &"morale", 0.2)
     WorldClock.adjust_event_variable(&"bannow_bay_landing", &"supplies", 0.2)
     WorldClock.advance_day(1)  # expect landing_checked
     ```
6. Press **T** again to hide the panel.

Keys: **T** toggle panel · **Y** advance day · **U** force-resolve Bannow.
