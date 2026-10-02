# Combat (greybox slice)

Stamina-based, **directional** melee for Ríocht’s cattle-farm starter kit.

## Starting kit (Cian)

| Weapon | Role | Notes |
|---|---|---|
| **Hatchet** (default) | Primary | Directional chop arcs (**top / left / right**); hold-to-charge power |
| **Knife** | Fast / low damage | Lower stamina cost, short reach (tap light / RMB heavy) |
| **Cattle goad / staff** | Reach + **drove** | Longer hitbox; on `raid_cattle` applies `apply_goad` impulse (no HP damage to herd) |
| Spear / shield | **Later** | Not starting gear — unlock via scavenge / craft / life path |

No starting sword or shield. `CombatSystem.enable_block` stays off until shield gear exists.

## Controls

| Input | Action |
|---|---|
| WASD | Move (camera-relative yaw on body). **Not** used for strike direction |
| Mouse | Look + **aim strike dir while charging** (look left/right/up → left/right/top) |
| **Hold LMB** | **Charge** hatchet (power scales 0→1 over ~0.55s). Release to strike |
| **Release LMB** | Strike in aimed direction; tap (~short hold) = light, long hold = power |
| Camera pitch up | Favors **top** overhead |
| RMB | Heavy for **knife/goad only** — hatchet has **no** instant full-power (hold-release only) |
| Sprint / hit-stun | **Cancels** an in-progress hatchet charge |
| Space | Jump |
| Shift | Sprint (drains stamina) |
| Q | Cycle weapon (hatchet → knife → goad) |
| 1 / 2 / 3 | Select hatchet / knife / goad |
| Esc | Capture / release mouse |
| **Ctrl / C** | Crouch (stealth — see `systems/stealth/README.md`) |

### Directional hatchet (feel notes)

Third-person scheme: **hold attack to charge**, **aim with the mouse** while holding (left/right/up), **release to commit**. Neutral defaults to **top**. Charging allows half-speed footwork. Sprint or taking a hit **cancels** charge. Knife/goad keep tap light / RMB heavy for now (scheme TBD later).

### Hatchet timing polish (#2)

Base TOP profile (then × `HATCHET_DIR_TIMING`):

| Kind | Windup | Active (contact) | Recovery |
|---|---|---|---|
| Light | 160 ms | 120 ms | 340 ms |
| Charged | 340 ms | 160 ms | 580 ms |

Direction scales: **top** 1.00 / 0.95 / 1.05 · **left** 0.82 / 1.10 / 0.90 · **right** 0.85 / 1.15 / 0.92.

Procedural pose phases: windup cock + brief hold telegraph → strike → contact hold → follow → recover. Charged holds longer at cock and contact so the telegraph and impact read; sides are snappier on the way in and slightly quicker to recover.

## Component

`CombatSystem` (`systems/combat/combat_system.gd`) is a reusable child node for player and NPCs.

- **Stamina** regen when not attacking / charging; costs on light/heavy/sprint
- **Charge** (`begin_charge` / `release_charged_attack`): power lerps light→heavy profiles
- **StrikeDirection** `TOP` / `LEFT` / `RIGHT` — hatchet swing poses + hitbox bias
- **Health** + `died` signal
- **Hit detection** via sibling `Hitbox` Area3D (short-lived monitoring during active frames)
- **Teams** (`team` export): same team does not hurt each other
- Signals: `attack_performed`, `hit_landed`, `damage_taken`, `stamina_changed`, `health_changed`, `weapon_changed`, `charge_started`, `charge_updated`, `charge_released`, `charge_cancelled`, `died` (`blocked` reserved for later shield)
- **Hit feedback** (greybox): hurt-mesh flash, knockback impulse (`consume_knockback()`), floating damage numbers, brief hit-stop on connect. Player also gets a light screen punch.

Wire under a `CharacterBody3D` with optional `Hitbox`, `Hurtbox`, and `WeaponVisual` (children named `Hatchet`, `Knife`, `Goad`).

## Dummy counter

`dummy_fighter` telegraphs every swing (weapon cock + warm tint + `!` / `...` Label3D), then releases a weak light hatchet. Taking a hit in range triggers a reactive counter telegraph (shorter). Hitting the dummy during telegraph staggers/cancels — learnable timing, still beatable.

## Test

Open `scenes/main/main.tscn` (F5). A dummy fighter stands a few meters ahead — hold LMB to charge the hatchet, aim left/right/up with the mouse, release for power. Sprint or getting hit cancels charge. Swap weapons and watch HP/STA + CHARGE% on the HUD.

Headless smoke:

```bash
godot --headless --path . -s res://tools/smoke_directional_hatchet.gd
```

Screenshot capture:

```bash
godot --headless --path . -s res://tools/capture_directional_hatchet_screenshots.gd
godot --headless --path . -s res://tools/capture_hatchet_timing_screenshots.gd
```

## Session vitals bridge (player only)

Player greybox adds `HealthCombatBridge` beside `CombatSystem` so melee HP/STA
mirror into the `CharacterHealth` autoload (HUD / feel). **NPCs are unchanged** —
do not attach the bridge to dummy / sentry / band scenes. See
[`systems/health/README.md`](../health/README.md#healthcombatbridge-player--session).

## Character anims

Locomotion / body swing driving for the kerne silhouette: [`docs/CHARACTER_ANIMS.md`](../../docs/CHARACTER_ANIMS.md).
