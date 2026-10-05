# Prologue

Tightly authored opening sequence (greybox first). Keep cinematic scenes and beat scripts here; hand off to open world when `Game.finish_prologue()` runs.

## Opening cattle drive (this pass)

First-morning tutorial: walk the farm lane from the house to the pasture, stir the grazing herd with the goad, and drive enough head back into the home pen beside the byre.

| | |
|---|---|
| **Scene** | `scenes/prologue/opening_cattle_drive.tscn` |
| **Run** | **F4** from the F5 main greybox, **or** open this scene and Play (F6 in the editor = Run Current Scene). F5 still loads `main.tscn` with the cattle-raid lane untouched. |
| **F4** (return) | From the opening scene, F4 returns to main. Esc still frees / recaptures the mouse. |
| **Soft success** | ≥ **4 of 6** head inside the home pen (`HomeZone`) → print `OPENING_DRIVE_SOFT_SUCCESS` + HUD banner. No fail / no timer. |
| **Kit** | Goad (3) + knife (2). Starts on goad. No hatchet. |

### Loop

1. Spawn in the yard by the house / byre.
2. Walk the twisting lane south (rails + path-bias stakes; bog on the east side of the middle bends).
3. Find the herd idle-grazing at the pasture (~100 m from home).
4. Prod any cow (LMB/RMB with goad) — the herd lifts its heads (`begin_herd`).
5. Walk **behind** the drove with the goad drawn (facing them) and prod laggards; cattle stall / graze if you stop pushing (freshness fade).
6. Steer clear of the bog edge (bogged cows slow until goaded back out).
7. Get ≥4 head through the home-pen gate → soft success.

| Key | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift | Sprint |
| **3** | Draw goad |
| **2** | Knife |
| Q | Cycle goad → knife → unarmed |
| LMB / RMB | Prod / heavy prod |
| **R** | Reset herd to pasture |
| **T** | Reset herd + player to yard |

### Files

| File | Role |
|---|---|
| `opening_cattle_drive.tscn` | Farm scene root (house/byre/lane/pasture/bog/ráth + herd + player + director + HUD) |
| `opening_cow.tscn` | Instances `raid_cow.tscn`, swaps in `opening_cow.gd` |
| `../../scripts/prologue/opening_cow.gd` | Extends `raid_cow.gd` — freshness fade, bog drain, pen-slot walk (base AI untouched) |
| `../../scripts/prologue/opening_farm_greybox.gd` | Procedural greybox (boxes/rails/hedges/ráth) |
| `../../scripts/prologue/opening_drive_director.gd` | Stages, soft success, bog/home zones |
| `../../scripts/prologue/opening_drive_hud.gd` | Objective / status / banner |
| `../../scripts/prologue/opening_drive_launcher.gd` | F4 main→opening, Esc opening→main |
| `../../tools/smoke_opening_cattle_drive.gd` | Headless smoke (+ bot drive) |
| `../../tools/capture_opening_cattle_drive.gd` | Stills → `/workspace/riocht-builds/opening-cattle-drive/` |

### Out of scope (this pass)

Night raid, dogs, fog, night FOV, mounted drive, polishing meshes, combat anim / strike-pose / goad swing-guard timing changes. The F5 `cattle_raid_lane` is not modified.
