# Stealth (greybox slice)

First-class pillar alongside combat (VISION / SCOPE): **crouch, cover, detection**, plus **bog body-drag**.

## Prototype vs FULL

| | **Prototype** (`gameplay/bog-body-hide-prototype`) | **FULL** (`gameplay/bog-body-drag-full`) |
|---|---|---|
| Grab | Tap **E** toggle drag / drop | **Hold E** to drag; **release** to drop (or hide in bog) |
| Cost | Speed only (~1.75) | Speed + **stamina drain** (−11/s); exhausted → crawl-drag |
| Bodies | Spoof corpse in stealth lane | Spoof **+ combat kill → CorpseSpawner** (dummy death) |
| Discovery | Once-only heat bump on LOS | **Investigation delay** then bump; **rediscovery** bumps while still seen |
| Bog VFX | Shallow sink / fade | Deeper sink + **splash/ripple stub** |
| UI | Basic `[concealed]` / `[DISCOVERED]` | Stronger labels + heat **banner**; HUD drag line |
| Honor | None | Light stub: discover −honor, hide +honor (toggleable) |

> FULL is still greybox — not Midlands traversal payoff, dogs, or social investigation chains.

## Controls

| Input | Action |
|---|---|
| **Ctrl** or **C** | Crouch (hold) — lower capsule + camera, slower move, quieter footprint |
| **Hold E** | Drag body (must stay held). Release outside bog = drop; release in bog = hide |
| WASD | Move (crouch walk ≈ 2.4 m/s; walk 5; sprint 8; **drag ≈ 1.75**, exhausted ≈ 0.96) |
| Shift | Sprint (disabled while crouched or dragging) |

Combat inputs unchanged (LMB/RMB hatchet, Q cycle, etc.) — blocked while dragging.

## Pieces

| Path | Role |
|---|---|
| `scripts/characters/player/player_controller.gd` | Crouch + drag slowdown + **drag stamina** |
| `systems/stealth/detection_sensor.gd` | Vision cone + LOS + hearing → UNAWARE / SUSPICIOUS / ALERT |
| `scenes/characters/npcs/sentry.tscn` | Stationary watchman with sensor |
| `systems/stealth/bog_zone.gd` | Wetland Area3D — hide, deep sink, splash/ripple stub |
| `scripts/characters/npcs/draggable_corpse.gd` | Hold-drag corpse: ground → drag → hide |
| `systems/stealth/corpse_spawner.gd` | Spawn corpse from combatant death |
| `systems/stealth/heat_tracker.gd` | Investigation timer, rediscovery bumps, Honor stub, HUD · **also** `note_raid_*` for cattle-lane watchmen |
| `systems/stealth/bog_hide_stub.gd` | Deprecated marker (use `bog_zone.gd`) |

## FULL bog body-drag loop

1. **Kill** the combat-lane dummy (−Z) → tip-over → **draggable corpse** spawns (or use the spoof body in the stealth lane).
2. Approach → **hold E** to drag (slow move, stamina drains; Combat HUD shows drag line).
3. Drag into the **bog pocket** (+X of stealth lane) → **release E** to hide.
4. Splash/ripple stub + deep peat sink → `[CONCEALED]`; heat relief + tiny Honor bump.
5. **Investigation:** sentry LOS on unhidden body → short investigate window → heat bump + `[DISCOVERED]` + Honor hit.
6. **Rediscovery:** if body stays visible, smaller heat bumps repeat on an interval.
7. Hidden bodies are skipped by discovery scan.

### Hide vs discovered (feel)

| State | Heat | Sentry | Readout |
|---|---|---|---|
| Body left in open + seen (after delay) | **+discover_bump** (28) | Forced ALERT | Banner + `[DISCOVERED]`; Honor −4 stub |
| Body still visible later | **+rediscovery_bump** (12) | Stays alert | Banner “seen again”; count on corpse |
| Body hidden in bog | **−hidden_relief** (10) | No corpse LOS | `[CONCEALED]`; Honor +1.5 stub |

## F5 demo layout

`scenes/main/main.tscn`:

| Lane | Direction | Contents |
|---|---|---|
| Combat | −Z | Dummy fighter → **corpse on kill** |
| Stealth | +X | Cover crates, sentry, spoof corpse, bog zone |
| NE bog pocket | +X −Z (~14, −8) | Extra wetland greybox |
| Heat HUD | screen TL + world label + banner | `Heat N / 100 [tier]` |

## Screenshots

FULL proof shots: `/workspace/riocht-builds/screenshots/bog-full/`  
(capture: `tools/capture_bog_full_screenshots.gd`)

Cattle-raid watchmen (south lane) reuse this HeatTracker via `systems/raid/raid_heat_bridge.gd` —
see [`systems/raid/README.md`](../raid/README.md). One shared heat meter for the F5 demo.

## Out of scope (even FULL)

- Midlands region traversal payoff
- Dogs, night FOV, multi-sentry social chains
- Stealth takedowns (melee silent kill) — combat kill path only for now
- Deep Brehon law / éraic resolution (Honor stub only)


### Cattle-lane watchmen (raid)
Heat ≥85 raises **RAID ALARM** and watchmen **ATTACK**; the drove stays completable. Separate raid meter is a post-merge follow-up.
