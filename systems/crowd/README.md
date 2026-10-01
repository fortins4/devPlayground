# Crowd (town NPC presence stub)

Data / API for **town and settlement crowd density** that Godot may bind visuals
to later. **Not** full crowd AI, navigation, or spawn directors.

| Piece | Role |
|---|---|
| [`crowd_sites.gd`](crowd_sites.gd) (`class_name CrowdSites`) | Seeded site table + tier ladder |
| `scripts/autoload/crowd.gd` (autoload **`Crowd`**) | Live density / tier, signals, soft season |
| `scenes/ui/crowd_debug_hud.tscn` | Optional F5 greybox panel (**\\** backslash) |
| `tools/probe_crowd_towns.gd` | Headless / Remote smoke |

Region ids align with [`TravelDistances`](../traversal/travel_distances.gd)
(`dublin`, `wexford_waterford`, `leinster`, …). Map context:
[`docs/MAP_REGIONS.md`](../../docs/MAP_REGIONS.md).

---

## Seeded sites

| Site id | Kind | Region (`TravelDistances`) | Base dens |
|---|---|---|---|
| `dublin` | town | `dublin` | 0.72 |
| `wexford` | port | `wexford_waterford` | 0.58 |
| `waterford` | port | `wexford_waterford` | 0.55 |
| `leinster_ringfort_market` | market | `leinster` | 0.42 |
| `bannow_beachhead_camp` | camp | `leinster` | 0.35 |
| `glendalough_pilgrim` | monastic_fair | `wicklow_glendalough` | 0.28 |
| `clonmacnoise_fair` | monastic_fair | `clonmacnoise` | 0.32 |
| `midlands_drove_camp` | camp | `midlands_bogs` | 0.18 |
| `shannon_landing` | river | `shannon` | 0.22 |
| `connacht_host_camp` | camp | `connacht` | 0.25 |
| `munster_fringe_steading` | steading | `munster_fringe` | 0.20 |

Extend: append `CrowdSites.SITES` + `SITE_IDS`, or call `Crowd.register_site(...)`
at runtime.

---

## Tiers (density → visual rung)

| Tier | Id | Density range | Mid (set_tier snap) |
|---|---|---|---|
| EMPTY | `empty` | `[0, 0.05)` | 0.00 |
| SPARSE | `sparse` | `[0.05, 0.25)` | 0.15 |
| MODERATE | `moderate` | `[0.25, 0.50)` | 0.38 |
| BUSY | `busy` | `[0.50, 0.75)` | 0.62 |
| THRONG | `throng` | `[0.75, 1.0]` | 0.88 |

---

## Public API

```gdscript
Crowd.list_site_ids()
Crowd.list_sites()                          # rows + live density/tier
Crowd.list_by_region(&"dublin")
Crowd.list_by_region(&"wexford_waterford")  # wexford + waterford
Crowd.get_by_id(&"dublin")
Crowd.display_name(&"wexford")
Crowd.region_for(&"leinster_ringfort_market")
Crowd.is_known_site(&"dublin")

Crowd.get_density(&"dublin")
Crowd.set_density(&"dublin", 0.85)
Crowd.adjust_density(&"wexford", -0.1)
Crowd.get_tier(&"dublin")                   # CrowdSites.Tier
Crowd.set_tier(&"dublin", CrowdSites.Tier.THRONG)
Crowd.set_tier_id(&"wexford", &"busy")
Crowd.reset_density(&"dublin")
Crowd.reset_all_densities()

# Visual bind — stored + soft season bias (does not mutate storage)
Crowd.get_effective_density(&"dublin")
Crowd.get_effective_tier(&"glendalough_pilgrim")
Crowd.season_bias_enabled = true            # default

Crowd.register_site(
	&"carlow_fair", "Carlow fair", &"leinster", &"market", 0.3,
	[&"fair"], "Runtime example"
)

print(Crowd.to_debug_dict())
print(Crowd.get_debug_text())
print(Crowd.probe_remote(true))
```

### Signals

| Signal | When |
|---|---|
| `density_changed(site_id, density, previous)` | Stored density mutates |
| `tier_changed(site_id, tier, previous)` | Tier rung crosses a boundary |
| `site_registered(site_id)` | Runtime `register_site` for a new id |
| `presence_refreshed(reason)` | Soft `day_advanced` / `season_changed` / `reset_all` |

Connect visuals to `density_changed` / `tier_changed` / `presence_refreshed`, then
sample `get_effective_density` (or stored `get_density`) for the site the camera
is near.

---

## How Godot binds visuals later

1. **Author a crowd skin** (MultiMesh / GPUParticles / sparse NPC props) per town
   scene — *not* owned by this stub.
2. **On site enter** (region load / trigger): read `Crowd.get_effective_tier(site_id)`
   or `get_effective_density` and pick a spawn count / LOD preset.
3. **Subscribe**:
   ```gdscript
   func _ready() -> void:
   	Crowd.density_changed.connect(_on_crowd)
   	Crowd.tier_changed.connect(_on_crowd_tier)
   	Crowd.presence_refreshed.connect(func(_r): _refresh_crowd_visuals())

   func _refresh_crowd_visuals() -> void:
   	var dens := Crowd.get_effective_density(&"leinster_ringfort_market")
   	# map dens 0..1 → instance count / animation blend
   ```
4. **Directors** (raid heat, siege, fair days) call `set_density` / `set_tier` —
   visuals react via signals. No pathfinding here.
5. **Season** (optional): when `WorldClock.get_season_id()` exists (sibling
   season stub / future merge), `get_effective_density` applies a small bias by
   site `kind`. If season API is absent, effective == stored. Flip
   `Crowd.season_bias_enabled = false` to disable.

Non-goals: navigation agents, avoidance, schedule sims, mesh streaming.

---

## Soft WorldClock hooks

| Hook | Behavior |
|---|---|
| `day_advanced` | Emits `presence_refreshed(&"day_advanced")` only |
| `season_changed` | Same with `&"season_changed"` (if signal exists) |
| `get_season_id()` | Used by effective-density bias when present |

Season is **soft optional** — this branch does not depend on unmerged season code.

---

## F5 / Remote probe

**No Godot binary in this ticket** — Lead runs F5; Remote is enough for smoke.

1. F5 main scene.
2. Press **\\** (backslash) — Crowd panel (mid-right; Travel is bottom-right).
3. **PgUp / PgDn** — cycle site focus.
4. **Home / End** — density −0.1 / +0.1 on focused site (watch tier flip).
5. **Insert** — bump tier one rung via `set_tier`.
6. **Delete** — `reset_density` to authored base.
7. **\\** again to hide.

### Remote / debugger

```gdscript
print(Crowd.probe_remote(true))
print(Crowd.list_by_region(&"wexford_waterford"))
Crowd.set_density(&"dublin", 0.9)
print(Crowd.get_tier(&"dublin"))  # THRONG
print(Crowd.get_debug_text())
```

### Headless (when Godot available)

```bash
godot --headless --path . --script res://tools/probe_crowd_towns.gd
```
