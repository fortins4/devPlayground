# Laigin (Leinster)

Starting open-world region: prologue home, Norman landing approaches (Bannow Bay).

Terrain3D landscape can replace the CSG/mesh greybox once the addon is installed.
Local scale is greybox meters (readable roam), not 1:1 km — see `docs/MAP_SCALE.md`.

## Greybox slice (this branch)

F5 main instances `leinster_region.tscn` as the walkable floor + landmarks.
Combat dummy (−Z) and stealth lane (+X) stay on `scenes/main/main.tscn`.

| Direction | Landmark | Approx. from spawn |
|---|---|---|
| **S (+Z)** | **Bannow Bay** beachhead + water | ~40–50 m |
| **SE** | Norse contact hint (longship stub) | near Bannow |
| **W (−X)** | Home túath / ringfort link | ~38 m |
| **N (−Z)** | Dublin road gate (travel stub) | ~42 m |
| **NE** | Monastic stub (round tower) | ~(24, −26) |
| **NW** | Hill fort overlook | ~(−22, −30) |
| Center | N–S road + west fork to home | path mesh |

### How to walk landmarks (F5)

1. Run main scene (F5). Spawn is central Laigin roam.
2. Face the central signpost (−X a few meters) for the compass legend.
3. **South** along the dirt road → Bannow Bay label + beach / water; SE for Norse hull.
4. **West** along the fork → home túath ring stub (links to playable ringfort muster on main (−X ~24m)).
5. **North** along the road → Dublin gate posts (travel stub only).
6. **NE** toward the stone tower → monastic cell; **NW** mound → hill fort.
7. Combat: walk **−Z** to the dummy (~6 m). Stealth: walk **+X** to cover/sentry.

### Files

- `leinster_region.tscn` — ground, road, landmarks, Label3D signposts
- `scripts/world/regions/leinster/leinster_region.gd` — sets `Game.current_region = &"leinster"`
- Wired from `scenes/main/main.tscn` (`LeinsterRegion` instance)

### Non-goals here

- Terrain3D heightmap (optional later)
- Real travel-gate day costs (stubs live in `systems/traversal/`)
- Band muster ringfort is on main; west landmark points at it
