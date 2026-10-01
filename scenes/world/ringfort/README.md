# Ringfort (Home Túath)

Upgradeable player base: craftsmen, cattle, defenses, raid vulnerability.

## Greybox slice — band muster

F5 main loads this ringfort west of spawn (`scenes/main/main.tscn`).

| Control | Action |
|---|---|
| Walk west along the path | Reach the ringfort gate (east opening) |
| **E** (at muster stone) | Recruit one local kerne (−2 cattle) into Cian's band (cap 3 visible) |
| **H** | Toggle band **FOLLOW** (near player) / **HOLD** (stand at muster) |

Owns a `CattleEconomy` node (not an autoload) and uses `try_recruit_option(&"local_kerne")` — see `systems/economy/README.md`. Band upkeep / skirmish confidence stay data-side; this task is **muster**, not ambush combat.

Scenes / scripts:
- `ringfort.tscn` + `scripts/world/ringfort/ringfort_area.gd`
- `muster_point.gd` — interact Area3D
- `scripts/band/band_runtime.gd` — follower spawn / follow-hold
- `scenes/characters/npcs/band_warrior.tscn` — greybox spear kerne
