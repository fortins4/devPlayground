# Stealth (greybox slice)

First-class pillar alongside combat (VISION / SCOPE): **crouch, cover, detection**. Bog body-hide is a light stub only.

## Controls

| Input | Action |
|---|---|
| **Ctrl** or **C** | Crouch (hold) — lower capsule + camera, slower move, quieter footprint |
| WASD | Move (crouch walk ≈ 2.4 m/s; walk 5; sprint 8) |
| Shift | Sprint (disabled while crouched) |

Combat inputs unchanged (LMB/RMB hatchet, Q cycle, etc.).

## Pieces

| Path | Role |
|---|---|
| `scripts/characters/player/player_controller.gd` | Crouch blend, `get_noise_level()`, `get_visibility_point()`, `get_visibility_factor()` |
| `systems/stealth/detection_sensor.gd` | Vision cone + LOS ray (world layer) + hearing → meter → UNAWARE / SUSPICIOUS / ALERT |
| `scenes/characters/npcs/sentry.tscn` | Stationary watchman with sensor + eye/label indicator |
| `systems/stealth/bog_hide_stub.gd` | Wetland marker only — drag/hide deferred |

## Detection

1. **Vision:** player inside half-angle + distance, and PhysicsRay (mask = world) clear → raise meter fast. Crouch cuts silhouette (`visibility_factor` ≈ 0.55).
2. **Hearing:** omnidirectional within `hearing_range`; stimulus scales with player noise (still = 0, crouch walk low, sprint loud).
3. **Cover:** stand behind the greybox crates in the stealth lane — LOS blocked → meter decays.
4. **Indicator:** Label3D above sentry — `[o] UNAWARE` (green) → `[?] SUSPICIOUS` (yellow) → `[!] ALERT` (red) + optional `[LOS]` / `[hear]`. Ground wedge shows look FOV.

Thresholds (defaults): suspicious ≥ 0.35, alert ≥ 0.85. Meter decays when unseen/unheard.

## F5 demo

`scenes/main/main.tscn` — combat dummy stays on −Z. **Stealth lane** is on +X:

- Cover crates between spawn and the sentry
- Sentry faces roughly toward the cover approach (−X)
- Bog stub patch beyond the sentry (label only)

Walk/sprint into the cone to alert; crouch behind crates and creep past for UNAWARE / SUSPICIOUS reads.

## Out of scope (this greybox)

- Full social investigation / dogs / night FOV
- Drag corpse + bog heat delay (stub marker only)
- Stealth takedowns
