# Character model & animations (fluid-anims slice)

Playable-feel upgrade for the greybox protagonist (and combat dummy): a more readable
early-medieval **Irish kerne** silhouette plus procedural locomotion / combat body motion.

## Asset source

**Original procedural greybox meshes** built at runtime by
`scripts/characters/shared/kerne_mesh_builder.gd` (primitive `BoxMesh` / `CapsuleMesh` /
`SphereMesh` only). No third-party FBX/GLTF in this slice.

- Palette reads as soft léine (tunic) + brat (cloak fold) + soft shoes + belt kit.
- Visible kit: **hatchet** in hand (`WeaponVisual`), **knife** sheathed on left hip,
  **cattle goad** stowed on the back when not selected. No starting sword/shield.
- Hostile dummy uses the same builder with a red-brown `PALETTE_HOSTILE`.

Follow-up: replace with authored skeletal kerne (CC0 / commissioned) when art pipeline exists.

## How anims are driven

| Layer | Driver | Notes |
|---|---|---|
| **Locomotion** | `KerneLocomotion` (`kerne_locomotion.gd`) | Procedural joint sinusoids each physics frame from speed / crouch / sprint. States: `idle`, `walk`, `sprint`, `crouch_idle`, `crouch_walk`, `turn`, `attack`. Idle breath + light turn-in-place when yaw changes while nearly still. |
| **Combat weapon** | `CombatSystem._play_weapon_swing` | Existing Tween on `WeaponVisual` (windup → contact → follow → recovery). Hitbox timing unchanged. |
| **Combat body** | `player_controller._on_attack_performed` | Tweened **additive** euler offsets on `right_arm` / `right_forearm` / `torso` via `KerneLocomotion.set_combat_additive`, locked for the full attack window so walk arms do not fight the swing. |

Player calls `locomotion.tick(...)` after `move_and_slide()`. Dummy does the same for chase walk.

### Why not AnimationTree yet

Full skeletal import + AnimationTree blend space is the right long-term path, but too heavy
for this feel slice. Procedural joints already give readable walk/sprint/crouch and clearer
hatchet / knife / goad body English while keeping stamina light/heavy timings.

## Key files

- `scripts/characters/shared/kerne_mesh_builder.gd`
- `scripts/characters/shared/kerne_locomotion.gd`
- `scripts/characters/player/player_controller.gd`
- `scenes/characters/player/player.tscn`
- `scenes/characters/npcs/dummy_fighter.tscn`
- `systems/combat/combat_system.gd` (weapon Tween + hit feedback; unchanged contract)

## Controls (unchanged)

WASD move · mouse look · Space jump · Shift sprint · Ctrl/C crouch · LMB light · RMB heavy ·
Q cycle weapon · 1/2/3 hatchet/knife/goad · Esc mouse capture.
