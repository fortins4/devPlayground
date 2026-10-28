# Laigin (Leinster)

Starting open-world region: prologue home, Norman landing approaches (Bannow Bay).

Terrain3D landscape can replace the CSG/mesh greybox once the addon is installed.
Local scale is greybox meters (readable roam), not 1:1 km — see `docs/MAP_SCALE.md`.

## Greybox slice (open-world chunk 1: exile start)

F5 main instances `leinster_region.tscn` as the walkable floor + landmarks
(ground now spans x −60..125, z −60..60). It is May 1169, the morning after the raid.

**Spawn:** `ExileStart` (Marker3D, group `exile_start`) at **(67.5, 0.1, −4)**, yaw −1.886
(facing east-north-east toward the burned ráth). `ExileSpawn` on `main.tscn` puts the player
there on every load. That covers both a direct F5 run and the `Game.finish_prologue()` handoff.

| Direction from ExileStart | Landmark | Approx. |
|---|---|---|
| **ENE** | **Burned home ráth**: bank + ditch survive; house/byre burned to charred posts, fired daub, ash, embers; pen broken | centre (92, 4), ~25 m |
| **Behind / W** | Wood edge (oak/ash/hazel) | (61, −2) |
| **NW** | **Tóchar fen**: oak-plank causeway on runners, sedge, pools, alder carr | (46, −22) |
| **SSW gap → SW** | **Lane to Bannow**: poached cattle track + waymarks down to the strand, mudflats, FitzStephen's ships | lane (86.5, 26) → strand (19..64, 41..47) |
| **W ~65 m** | **Systems yard** (old centre): combat dummy, stealth lane, horse, ringfort, cattle-raid lane, central sign | around (0, 0) |

### How to walk it (F5)

1. Run main (F5). You start at the wood/fen edge, ~25 m WSW of the burned ráth, looking at its bank.
2. Walk **forward (ENE)** to the bank. Go round to the **south gap** (SSW side) to get into the yard and the ruined house/byre.
3. **Bannow:** leave by the south gap and follow the muddy lane **SW** past the waymarks to the strand and the three ships (~70 m).
4. **Tóchar:** turn **NW** from the start, through the wood edge, to the plank causeway across the fen.
5. **Systems yard:** walk **west ~65 m** to the old centre. The dummy is at (0, −6). The stealth lane is around (10, 2). The rest are as before:
   - S to the Bannow Bay label;
   - W to the ringfort stub;
   - N to the Dublin gate;
   - NE to the monastic tower;
   - NW to the hill fort.
6. **Handoff test:** in the F4 prologue (`opening_cattle_drive.tscn`), press **F3** (debug). It calls `Game.finish_prologue()`, which loads main and drops you at ExileStart.

### Files

- `leinster_region.tscn`: ground, road, landmarks, Label3D signposts, `ExilePatch` anchors + `ExileStart`
- `scripts/world/regions/leinster/exile_patch_greybox.gd`: @tool builder for the ráth ruin, wood edge, tóchar fen, Bannow lane and strand
- `scripts/world/exile_spawn.gd` (on main): places the player at `ExileStart`
- `scripts/world/regions/leinster/leinster_region.gd` — sets `Game.current_region = &"leinster"`
- Wired from `scenes/main/main.tscn` (`LeinsterRegion` instance)

### Non-goals here

- Terrain3D heightmap (optional later)
- Real travel-gate day costs (stubs live in `systems/traversal/`)
- Band muster ringfort is on main; west landmark points at it
