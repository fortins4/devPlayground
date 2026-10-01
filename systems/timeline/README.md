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
On resolve day, absent outcomes call `apply_history_weight()`; result ripples into `Factions` attitudes and a critical `Rumors` entry.

Design source: `docs/SCOPE.md` (lock one shared EventOutcome schema before content multiplies).
