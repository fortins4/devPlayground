# Prologue

Tightly authored opening sequence (greybox first). Keep cinematic scenes and beat scripts here; hand off to open world when `Game.finish_prologue()` runs.

## Opening morning (set sequence)

The first morning on the farm, played as a fixed sequence with Máire as the hub. See `/STATUS.md` for where things stand and `/GET_UP_TO_SPEED.md` for the locked rules.

| | |
|---|---|
| **Scene** | `scenes/prologue/opening_cattle_drive.tscn` |
| **Run** | **F4** from the F5 main greybox, **or** open this scene and Play (F6 in the editor = Run Current Scene). F5 still loads `main.tscn` with the cattle-raid lane untouched. |
| **F4** (return) | From the opening scene, F4 returns to main. Esc still frees / recaptures the mouse. |
| **Success** | The drive ends only when **all 6 of 6** head are in the home pen and Cian latches the pen gate (`OPENING_DRIVE_PEN_LATCHED`). No fail / no timer. |
| **Kit** | Goad (3) only. Starts on goad. No hatchet and **no knife** anywhere in the opening (the knife first appears in the later raid). |

### Sequence

Máire waves when she has a line waiting and speaks it automatically when Cian comes near. After each step Cian goes back to her; the next step unlocks only after her talk.

1. **Máire at the door.** Her talk hands out the bucket job.
2. **Water the trough.** Pick up the stave bucket by the byre, fill it at the dug-out spring scoop west of the house, pour it at the trough. **Three trips**: each pour raises the water a third (HUD: "Trough n/3"). Cian stows the goad and carries the bucket by the handle with **both hands**. The load slows his walk and blocks sprint. The goad comes back after the pour.
3. **Bring the herd home.** No cow is tethered at the start; all six go on the drive. One of the **six** is bogged in the back paddock beyond the pasture, and her lowing leads there. Goad her out, drive her back to rejoin the other five, then drive all six home. The walk out is quiet. On the lane home a **stray dog ambushes** the herd and scatters the nearest head. Scare it off (E / goad prod up close), regather, pen **6/6**, then swing the gate shut and **latch** it.
4. **Tie the milk cow.** Máire wants the red milk cow (Cow1, the quiet one) kept by the house for the morning milking. E at the latched pen gate: Cian stows the goad, lifts the latch and swings the west leaf back by hand; the milk cow comes to the gateway, he slips the rope loop over her head and she steps out beside him; he swings the leaf shut and drops the latch so the other five stay penned. He leads her on the rope (goad on his back, rope in the right hand, slow walk, no sprint) — she follows his own track, so she goes round the pen corner, not through the fence — to the **tie post** in the yard by the house. E at the post: she comes up head to the post and he ties the rope off with **both hands**; then a rope runs from the post to the loop round her neck and she stands tied there.
5. **Stow and meal.** Stow the goad (1 / unarmed), then E to eat by the house: Cian sits on the ground at the low stool, eats, and rises back into normal walking. Máire has a closing line.

Interactions are on **E** (pick up / fill / pour, shout at the dog, latch the gate, rope the milk cow at the gate / tie her at the post, eat).

| Key | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift | Sprint |
| **1** | Unarmed / stow |
| **3** | Draw goad |
| Q | Cycle goad → unarmed |
| LMB / RMB | Prod / heavy prod |
| E | Interact |
| **R** | Failsafe: un-penned head back to the pasture (penned stay penned) |
| **T** | R + Cian back to the yard (does not reset the bucket chore) |

### Files

| File | Role |
|---|---|
| `opening_cattle_drive.tscn` | Farm scene root (house/byre/lane/pasture/bog/ráth + herd + player + director + HUD) |
| `opening_cow.tscn` | Instances `raid_cow.tscn`, swaps in `opening_cow.gd` |
| `../../scripts/prologue/opening_cow.gd` | Extends `raid_cow.gd` — freshness fade, bog drain, pen-slot walk (base AI untouched) |
| `../../scripts/prologue/opening_farm_greybox.gd` | Procedural farm: ráth, roundhouse, earth banks + wattle, woodland, plots + quern, fens + tóchar, mud track, carved post + cairn |
| `../../scripts/prologue/opening_drive_director.gd` | Drive beats (bogged cow, dog ambush/scatter), 6/6 pen count, R/T resets |
| `../../scripts/prologue/opening_family_caller.gd` | Máire, the sequence hub — wave + automatic talks |
| `../../scripts/prologue/opening_sequence.gd` | Set sequence: maire → bucket → drive → milk → meal |
| `../../scripts/prologue/opening_bucket_trough_chore.gd` | Bucket: spring scoop → trough, three pours, two-hand carry |
| `../../scripts/prologue/opening_rope_tie_chore.gd` | Milk cow: rope her out of the latched pen, lead her to the post by the house, tie her by hand |
| `../../scripts/prologue/opening_bogged_cow_chore.gd` | The bogged cow (one of the six) |
| `../../scripts/prologue/opening_stray_dog_chore.gd` | Stray dog ambush on the lane |
| `../../scripts/prologue/opening_pen_gate_chore.gd` | Home-pen gate + latch after 6/6 |
| `../../scripts/prologue/opening_stow_meal_chore.gd` | Stow goad, sit + eat, rise |
| `../../scripts/prologue/opening_cattle_look.gd` | Kerry/Dexter-type cattle look (herd) |
| `../../scripts/prologue/opening_terrain.gd` | Shared terrain height function |
| `../../scripts/prologue/opening_drive_hud.gd` | Objective / status / banner |
| `../../scripts/prologue/opening_drive_launcher.gd` | F4 main→opening, Esc opening→main |
| `../../tools/smoke_opening_cattle_drive.gd` | Headless smoke (+ bot drive) |
| `../../tools/capture_opening_cattle_drive.gd` | Stills → `/workspace/riocht-builds/opening-cattle-drive/` |
