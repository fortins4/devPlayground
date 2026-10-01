# Combat (greybox slice)

Stamina-based, directional melee for Ríocht’s cattle-farm starter kit.

## Starting kit (Cian)

| Weapon | Role | Notes |
|---|---|---|
| **Hatchet** (default) | Primary | Directional chop arcs; light jab-swing / heavy overhead |
| **Knife** | Fast / low damage | Lower stamina cost, short reach |
| **Cattle goad / staff** | Reach | Longer hitbox, moderate damage |
| Spear / shield | **Later** | Not starting gear — unlock via scavenge / craft / life path |

No starting sword or shield. `CombatSystem.enable_block` stays off until shield gear exists.

## Controls

| Input | Action |
|---|---|
| WASD | Move (camera-relative yaw on body) |
| Mouse | Look |
| Space | Jump |
| Shift | Sprint (drains stamina) |
| LMB | Light attack |
| RMB | Heavy attack |
| Q | Cycle weapon (hatchet → knife → goad) |
| 1 / 2 / 3 | Select hatchet / knife / goad |
| Esc | Capture / release mouse |

## Component

`CombatSystem` (`systems/combat/combat_system.gd`) is a reusable child node for player and NPCs.

- **Stamina** regen when not attacking; costs on light/heavy/sprint
- **Health** + `died` signal
- **Hit detection** via sibling `Hitbox` Area3D (short-lived monitoring during active frames)
- **Teams** (`team` export): same team does not hurt each other
- Signals: `attack_performed`, `hit_landed`, `stamina_changed`, `health_changed`, `weapon_changed`, `died` (`blocked` reserved for later shield)

Wire under a `CharacterBody3D` with optional `Hitbox`, `Hurtbox`, and `WeaponVisual` (children named `Hatchet`, `Knife`, `Goad`).

## Test

Open `scenes/main/main.tscn` (F5). A dummy fighter stands a few meters ahead — swing the hatchet, swap weapons, sprint, and watch HP/STA on the HUD.
