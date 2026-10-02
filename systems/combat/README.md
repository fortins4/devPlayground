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
| **Hold LMB** | **Charge** hatchet (power scales 0→1 over ~0.75s). Release to strike |
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

- **Stamina** from `StaminaEconomy` — regen when idle after delay (not attacking / charging / blocking); costs on light/heavy/sprint (see table below)
- **Charge** (`begin_charge` / `release_charged_attack`): power lerps light→heavy profiles
- **StrikeDirection** `TOP` / `LEFT` / `RIGHT` — hatchet swing poses + hitbox bias
- **Health** + `died` signal
- **Hit detection** via sibling `Hitbox` Area3D (short-lived monitoring during active frames)
- **Teams** (`team` export): same team does not hurt each other
- Signals: `attack_performed`, `hit_landed`, `damage_taken`, `stamina_changed`, `health_changed`, `weapon_changed`, `charge_started`, `charge_updated`, `charge_released`, `charge_cancelled`, `died` (`blocked` reserved for later shield)
- **Hit feedback** (greybox): hurt-mesh flash, knockback impulse (`consume_knockback()`), floating damage numbers, brief hit-stop on connect. Player also gets a light screen punch.

Wire under a `CharacterBody3D` with optional `Hitbox`, `Hurtbox`, and `WeaponVisual` (children named `Hatchet`, `Knife`, `Goad`).


## Stamina economy (fight numbers)

Tunable greybox pool — **data only** in `systems/combat/stamina_economy.gd`
(`class_name StaminaEconomy`). `CombatSystem` reads max / regen / delay / sprint /
attack **cost + recovery** / block stubs from that table. Knife/goad damage,
windup, active, and reach stay on `CombatSystem.PROFILES`. **Hatchet** damage/reach
come from `HatchetAttackTable` (direction × charge tier); windup/active stay on
PROFILES. Feel (anims, hitstop, telegraph) stays Godot-owned.

| Knob | Value | Notes |
|---|---|---|
| **Max stamina** | `100` | CombatSystem + CharacterHealth session default |
| **Regen /s** | `18` | Only when not attacking / not blocking **and** regen delay elapsed |
| **Regen delay** | `0.35 s` | Armed on stamina spend **and** when attack recovery ends |
| **Sprint drain /s** | `22` | Shift sprint |
| **Block drain /s** | `8` | Stub — `enable_block` stays **off** |
| **Block hit cost** | `12` | Stub on successful frontal block |
| **Block min hold** | `5` | Drop block below this |

### Attack cost + recover (source of truth)

| Weapon | Light cost | Light recover | Heavy cost | Heavy recover |
|---|---|---|---|---|
| Hatchet | 12 | 0.34 s | 28 | 0.58 s |
| Knife | 8 | 0.16 s | 18 | 0.28 s |
| Goad | 10 | 0.26 s | 22 | 0.40 s |

Design notes (hatchet-first):

- **~8 light hatchet swings** to empty (`floor(100/12)`).
- **Empty → full ~5.6 s** at 18/s (plus regen delay after last spend / recover).
- **Recover gates the next swing** — light hatchet total busy ≈ windup 0.16 + active 0.12 + recover 0.34 ≈ **0.62 s** (before dir scales), then **0.35 s** regen delay before passive refill.
- Heavies cost more than two lights and leave a longer recover window — commit tools, not spam.

Edit numbers in `StaminaEconomy` only; do not scatter magic floats back into
`CombatSystem` attack / sprint / block paths.

### F5 probe (stamina economy)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — CharacterHealth panel (mid-left) now appends the
   `StaminaEconomy` table + current STA (and bridge lines when bound).
3. Press **backtick** (`Key.QUOTELEFT`) — prints the same dump to the Output
   panel (`CombatSystem.dump_stamina_economy()` / `StaminaEconomy.get_debug_text()`).
4. Swing / sprint and confirm STA drops; after recover + delay, regen resumes at 18/s.

Key map (no collision with Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**, hatchet **F6**):
**V** show table · **backtick** print stamina dump.

## Hatchet damage / reach table (directional + charge)

Tunable greybox data — **`systems/combat/hatchet_attack_table.gd`**
(`class_name HatchetAttackTable`). Per-cell `damage` + `reach` for directional
axes × charge tiers. Godot owns feel (anims, hitstop, telegraph); Systems owns
this table / lookup API only.

### Directions (SCOPE directional combat)

| Direction | Meaning |
|---|---|
| `&"top"` | Overhead chop axis (default when aim unknown) |
| `&"left"` | Left sideswing |
| `&"right"` | Right sideswing |

Godot will drive direction from mouse-aim / stick later. Greybox stub defaults
to **`&"top"`** so existing LMB/RMB keep working without aim selection.

### Charge tiers + input mapping stub

| Tier | Maps from | StaminaEconomy kind |
|---|---|---|
| `&"tap"` | LMB **light** | `light` cost/recovery |
| `&"charged"` | RMB **heavy** | `heavy` cost/recovery |
| `&"max"` | full-charge hold (future) | `heavy` cost/recovery for now |

API:

- `CombatSystem.try_attack(kind, direction = &"top")` — legacy light/heavy; maps
  kind → tier, optional direction.
- `CombatSystem.try_attack_directional(direction, tier)` — explicit direction×tier.
- Knife / goad ignore the table and keep `PROFILES` damage/reach.

### Full table (greybox defaults)

Derived from prior hatchet light **14 / 1.35** and heavy **28 / 1.5**:
top = slightly higher damage, shorter lateral reach; left/right = balanced;
charged > tap; max = modest bump.

| Direction | Tier | Damage | Reach |
|---|---|---|---|
| top | tap | 15 | 1.25 |
| top | charged | 30 | 1.40 |
| top | max | 34 | 1.45 |
| left | tap | 14 | 1.35 |
| left | charged | 28 | 1.50 |
| left | max | 32 | 1.55 |
| right | tap | 14 | 1.35 |
| right | charged | 28 | 1.50 |
| right | max | 32 | 1.55 |

Helpers: `entry(direction, tier)`, `damage(...)`, `reach(...)`, `to_debug_dict()`,
`tier_from_kind` / `kind_from_tier`.

Edit numbers in `HatchetAttackTable.TABLE` only — do not retune `StaminaEconomy`
costs here (queue #1 owns those).

### F5 probe (hatchet table)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — CharacterHealth panel also appends the hatchet direction×tier
   table + last resolved cell (when a hatchet swing has fired).
3. Press **F6** — prints the same dump to the Output panel
   (`CombatSystem.dump_hatchet_attack_table()` /
   `HatchetAttackTable.get_debug_text()`).
4. Swing LMB/RMB with hatchet equipped; confirm last resolved shows
   `dir=top tier=tap|charged` with matching dmg/reach.

Key map (no collision with stamina **V** / **backtick**, Honor **H**, Timeline
**T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F6** print hatchet table dump.

## Stagger / wound tags (combat-support data)

Tunable greybox catalog — **`systems/combat/combat_tags.gd`** (`class_name CombatTags`).
Named tags hits can apply alongside `CharacterHealth`’s integer wound counter.
Feel (anims, hitstop, dummy telegraph cancel) stays Godot-owned; Systems owns
tag data + a small apply path on `CombatSystem` hit.

### Stagger tags (short CC / interrupt)

| Tag | Duration | Interrupt | Notes |
|---|---|---|---|
| `&"stagger_light"` | 0.35 s | 1 | Tap / jab hitch |
| `&"stagger_heavy"` | 0.75 s | 2 | Charged / max hitch |

`CombatSystem.apply_stagger_tag` sets `stagger_left` (countdown). `can_move()`
gates while staggered — minimal CC hook so dummy AI that already respects
`can_move` pauses without a full rewrite.

### Wound tags (soft counter flavour)

| Tag | `wound_delta` | Notes |
|---|---|---|
| `&"bruise"` | 0 | Tag only — no soft-counter tick |
| `&"cut"` | +1 | Edge bite |
| `&"deep"` | +2 | Charged overhead / heavy bite |

Player hits feed `CharacterHealth.apply_wound_tag` / `apply_stagger_tag` (signals
`wound_tag_applied`, `stagger_applied` + short tag list). NPCs get stagger stub
only (no session wound counter).

### Hatchet direction × tier → default tags

| Direction | Tier | Tags |
|---|---|---|
| top / left / right | tap | `bruise`, `stagger_light` |
| top | charged / max | `deep`, `stagger_heavy` |
| left / right | charged / max | `cut`, `stagger_heavy` |

Knife / goad simple defaults: knife → `cut` + `stagger_light`; goad light →
`bruise` + `stagger_light`; goad heavy → `bruise` + `stagger_heavy`.

API: `tags_for_hit(weapon, kind, direction, tier)`, `hatchet_tags(dir, tier)`,
`stagger_entry` / `wound_entry`, `to_debug_dict()`, `get_debug_text(...)`.

Edit catalog / mapping in `CombatTags` only — do not retune `StaminaEconomy` or
`HatchetAttackTable` numbers here.

### F5 probe (combat tags)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — panel appends the CombatTags catalog + last applied hit tags.
3. Press **F7** — prints the same dump (+ CharacterHealth last tags) to Output
   (`CombatSystem.dump_combat_tags()` / `CombatTags.get_debug_text()`).
4. Swing hatchet into the dummy (or take a hit); confirm last applied shows
   expected tags; player soft wounds tick on `cut` / `deep` when *you* are hit.

Key map (no collision with stamina **V** / **backtick**, hatchet **F6**, Honor
**H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F7** print combat tags dump.

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

## Systems data hooks

- **Damage / reach (hatchet):** `HatchetAttackTable` (direction × tap/charged/max)
- **Stamina cost + recovery:** `StaminaEconomy` (hatchet recovery synced to timing polish 0.34 / 0.58)
- **Charge full:** 0.75s hold
- **Side hitboxes:** widened for flank chops vs face-blocking sparring foe

## Switchable block faces (#4)

Sparring dummy cycles **TOP → LEFT → RIGHT** every ~2.75s while guarding. Only matching hatchet strike directions are blocked; other faces take full damage.
