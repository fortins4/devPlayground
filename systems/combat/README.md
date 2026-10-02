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

Key map (no collision with Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**, hatchet **F6**, tags **F7**, block **F8**, flank **F9**, wound decay **F10**, break→stagger **F11**, charge STA **F12**):
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

| Tier | Alias | Maps from (~0.75 s hold-release) | STA cost | Recovery kind |
|---|---|---|---|---|
| `&"tap"` | light | short release (held < ~0.08 s or ratio < 0.22) | **12** (`ChargeStaminaTable`) | `light` |
| `&"charged"` | mid | mid hold (ratio ≥ 0.55, < 0.95) | **28** | `heavy` |
| `&"max"` | full | full hold (ratio ≥ 0.95 / ~0.75 s) | **34** | `heavy` |

Discrete charge STA lives in **`ChargeStaminaTable`** (spend on release commit).
Recovery still comes from `StaminaEconomy` via `kind_from_tier`.

API:

- `CombatSystem.try_attack(kind, direction = &"top")` — legacy light/heavy; maps
  kind → tier, optional direction.
- `CombatSystem.try_attack_directional(direction, tier)` — explicit direction×tier.
- `CombatSystem.spend_for_charge(tier)` / `try_spend_for_charge(tier)` — STA spend
  on release commit; returns `false` if insufficient (refuse strike).
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

Key map (no collision with stamina **V** / **backtick**, tags **F7**, block
**F8**, flank **F9**, wound decay **F10**, break→stagger **F11**, Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
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
| `&"bruise"` | 0 | Tag only — no soft-counter tick; bleed 0 via WoundDecayTable |
| `&"cut"` | +1 | Edge bite; bleed rate from WoundDecayTable |
| `&"deep"` | +2 | Charged overhead / heavy bite; bleed rate from WoundDecayTable |

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

Key map (no collision with stamina **V** / **backtick**, hatchet **F6**, block
**F8**, flank **F9**, wound decay **F10**, break→stagger **F11**, Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F7** print combat tags dump.

## Block / posture face-guard numbers (sparring)

Tunable greybox data — **`systems/combat/block_posture_table.gd`**
(`class_name BlockPostureTable`). Face guards ≠ full shield block. Shield stubs
stay on `StaminaEconomy` (`BLOCK_DRAIN_PER_SEC` 8 / `BLOCK_HIT_COST` 12 /
`BLOCK_MIN_STAMINA` 5) with `CombatSystem.enable_block` **off** for the player
kit. This table is the **sparring** resource: hold a face aligned with hatchet
dirs; matching attack → mitigate + chip posture + stamina cost; mismatch /
`&"open"` → full damage.

Feel (anims, dummy face-switch AI) stays Godot-owned. Systems owns table +
lookup helpers + a light opt-in path on `CombatSystem`.

### Guard faces

| Face | Meaning |
|---|---|
| `&"top"` | Overhead high guard |
| `&"left"` | Left face (sideswing cover) |
| `&"right"` | Right face (sideswing cover) |
| `&"open"` | No guard — full damage; faster posture regen |

Default face: **`&"open"`**.

### Posture pool

| Knob | Value | Notes |
|---|---|---|
| **Max posture** | `100` | Separate from stamina |
| **Regen /s** | `12` | × per-face `recover_rate` |
| **Break stun** | `0.75 s` | After posture hits 0 — forced open; **aligned to** `CombatTags.stagger_heavy` |
| **Break stagger** | `&"stagger_heavy"` | Existing CombatTags tag applied on break (no parallel CC) |

### Per-face numbers

| Face | Mitigation | STA cost on hit | Posture chip | Recover rate | Window sec |
|---|---|---|---|---|---|
| top | 0.60 | 8 | 22 | 1.00 | 1.40 |
| left | 0.55 | 6 | 18 | 1.05 | 1.20 |
| right | 0.55 | 6 | 18 | 1.05 | 1.20 |
| open | 0.00 | 0 | 0 | 1.15 | 0.00 |

Design notes:

- **Face match**: `guard_face == attack_dir` (both `top`/`left`/`right`) →
  strip `damage_mitigation` fraction, spend STA, chip posture.
- **Open / mismatch**: full damage, then **FlankBonusTable** multiplier (see
  flank section below). Matched face absorb → no flank bonus.
- **~4 matched top absorbs** to break (`floor(100/22)`). Empty → full ~8.3 s at
  12/s (before face recover_rate / break stun).
- Lighter than full shield stub (~0.75 mitigate / hit cost 12) — face covers one
  line, not the whole front.

### CombatSystem wire (opt-in)

- `enable_face_guard` (**default false** — player kit stays shield-off). Sparring
  foe / Godot can set true.
- `set_face_guard(face)` / `set_guard_direction(StrikeDirection)` — hold a face.
- `mitigation_for(guard_face, attack_dir)` / `apply_guard_hit_cost(attack_dir, dmg)`
  — Godot-callable resolve helpers without forcing player shield on.
- `apply_damage(..., attack_dir)` uses the table when `enable_face_guard` and
  posture is not broken. Existing `enable_block` shield stubs **unchanged**.

### Posture break → CombatTags stagger (feel hook)

When the posture pool empties, `CombatSystem._on_posture_break()`:

1. Sets `posture_break_left` from `BlockPostureTable.break_stun_sec()` (driven by
   `CombatTags.duration_sec(&"stagger_heavy")`, fallback `BREAK_STUN_SEC` **0.75**).
2. Forces `guard_face = &"open"`.
3. Calls existing `apply_stagger_tag(&"stagger_heavy")` — sets `stagger_left` and
   `last_stagger_*`. **Reuses CombatTags** — no second stagger system.
4. Keeps `posture_break_left` and `stagger_left` on the same window.
5. Emits `posture_broken(victim, stagger_tag, duration_sec)` for Godot VFX / AI.
6. If the broken entity is the player, also mirrors via `CharacterHealth.apply_stagger_tag`.

Godot sparring: `can_move()` is already false while `stagger_left > 0` — dummy AI
that respects it pauses on break. Connect `posture_broken` for hitch anim / SFX.
Do **not** invent a parallel break-stun feel path.

Helpers: `faces_match`, `is_open_side`, `face_entry`, `resolve_guard_hit`,
`break_stagger_tag`, `break_stun_sec`, `break_stagger_entry`,
`to_debug_dict()`, `get_debug_text(...)`.

Edit numbers in `BlockPostureTable` / `CombatTags.STAGGER` only — do not retune
`StaminaEconomy` shield stubs or `HatchetAttackTable` here.

### Sparring foe defaults API (Godot)

**Face-guard is the proper path** when `enable_face_guard` is true. The older
`enable_block` + `set_blocking` frontal/directional stubs stay intact for legacy
smoke / shield-later — do not delete them; prefer face-guard for the sparring
dummy.

Outfit a sparring dummy (or any CombatSystem) from Systems numbers — **no
hardcoded posture/mitigation in foe scripts**:

```gdscript
# Preferred — typed CombatSystem already in hand:
combat.apply_sparring_foe_guard_defaults()

# Or pass a CombatSystem / CharacterBody3D that owns one:
BlockPostureTable.apply_sparring_foe_guard_defaults(dummy_body)
# equivalent:
CombatSystem.apply_sparring_foe_guard_defaults_to(dummy_body)

# Dict only (read numbers without mutating):
var d := CombatSystem.get_sparring_foe_posture_defaults()
# d.enable_face_guard, d.max_posture (100), d.regen_per_sec (12),
# d.break_stun_sec (0.70), d.starting_face ("top"), d.faces[...]
```

What `apply_sparring_foe_guard_defaults` does:

| Field | Value |
|---|---|
| `enable_face_guard` | `true` |
| `enable_block` | **unchanged** (stubs intact; not required for sparring) |
| `posture` | `BlockPostureTable.MAX_POSTURE` (**100**) |
| `posture_break_left` | `0` |
| `guard_face` / `guard_direction` | starting **`top`** / `StrikeDirection.TOP` |

Per-face soak (mitigation / STA cost / posture chip / recover / window) stays on
`BlockPostureTable.FACE_TABLE` — apply does not copy magic floats into the foe.

`scripts/characters/npcs/dummy_fighter.gd` calls this in `_ready`. While holding
guard it cycles TOP→LEFT→RIGHT via `set_guard_direction`; when not holding it
sets `&"open"` so face-guard stops mitigating (unlike the older `is_blocking`
gate).

No new F-key — **F8** already dumps BlockPostureTable + live posture / last
resolve (`CombatSystem.dump_block_posture_table()`).

### F5 probe (block / posture)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — panel appends the BlockPostureTable + current posture / last resolve
   (+ posture-break→stagger link dump).
3. Press **F8** — prints the same dump to the Output panel
   (`CombatSystem.dump_block_posture_table()` /
   `BlockPostureTable.get_debug_text()`).
4. Press **F11** — prints the posture-break → CombatTags stagger link + live
   `break_left` / `stagger_left` (`CombatSystem.dump_posture_break_stagger()`).
5. (Optional) Enable `enable_face_guard` on a sparring foe CombatSystem, set a
   face, swing matching dirs until posture breaks; confirm `stagger_heavy`
   applied, `can_move()` gated, and F11 shows last break.

Key map (no collision with stamina **V** / **backtick**, hatchet **F6**, tags
**F7**, flank **F9**, wound decay **F10**, break→stagger **F11**, Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F8** print block/posture dump · **F11** posture-break→stagger link.

## Flank bonus (open-side hits)

Tunable greybox data — **`systems/combat/flank_bonus_table.gd`**
(`class_name FlankBonusTable`). When attack direction does not match the
defender's face guard (or guard is `&"open"`), multiply remaining damage.
Godot owns sparring feel; Systems owns this table / lookup + a light wire on
`CombatSystem.apply_damage`.

### Resolve order (locked)

1. **Face-guard mitigate first** via `BlockPostureTable` (matched face only).
2. **Flank bonus applies only when face guard does NOT mitigate** — open guard,
   wrong-face mismatch, or posture-broken (treated as open). Matched absorb →
   multiplier `1.0` (no flank).
3. Optional **rear** (world-space behind defender, `frontal == false`) uses the
   rear mult when the hit is already open-side. Hatchet has no dedicated back
   strike axis — rear is facing, not a table direction.

### Multipliers (greybox defaults)

| Kind | When | Mult |
|---|---|---|
| matched | `guard_face == attack_dir` (real faces) | **1.00** |
| open_guard | guard is `&"open"` (or broken posture) | **1.25** |
| wrong_face | holding a face, hit on a different axis | **1.20** |
| rear | open-side + attacker behind defender | **1.35** |

Examples (tap top dmg 15, face-guard on):

- Guard **top**, atk **top** → mitigate 60% → remaining 6.0 × **1.00** = 6.0
- Guard **top**, atk **left** → no mitigate → 15 × **1.20** = 18.0
- Guard **open**, atk **left** → 15 × **1.25** = 18.75
- Guard **open**, atk **left**, rear → 15 × **1.35** = 20.25

API: `bonus_for(guard_face, attack_dir, is_rear := false) -> float`,
`classify(...)`, `resolve(...)`, `to_debug_dict()`, `get_debug_text(...)`.

Edit numbers in `FlankBonusTable` only — do not retune `BlockPostureTable` /
`StaminaEconomy` / `HatchetAttackTable` here.

### F5 probe (flank bonus)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — panel appends the FlankBonusTable + last open-side resolve.
3. Press **F9** — prints the same dump to the Output panel
   (`CombatSystem.dump_flank_bonus_table()` /
   `FlankBonusTable.get_debug_text()`).
4. (Optional) Enable `enable_face_guard` on a sparring foe, set a face, swing
   matching / mismatching / from behind; confirm matched = no flank, open /
   wrong-face / rear multiply remaining damage.

Key map (no collision with stamina **V** / **backtick**, hatchet **F6**, tags
**F7**, block **F8**, wound decay **F10**, break→stagger **F11**, Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F9** print flank bonus dump.

## Bleed / wound decay over time

Tunable greybox data — **`systems/combat/wound_decay_table.gd`**
(`class_name WoundDecayTable`). Bleed HP drain + named-tag clear times + soft
wound-counter decay. Godot owns feel (VFX, limp, bandage UI); Systems owns this
table + a light tick on `CharacterHealth` when wounds/tags are present.

**Not** a full injury sim — no scars, limb loss, or medical minigame.

### Per-tag numbers (greybox)

| Tag | `bleed_hp_per_sec` | `decay_sec` | `tick_interval` | Notes |
|---|---|---|---|---|
| `&"bruise"` | **0.0** | 20 s | 0.5 s | No bleed — tag fades |
| `&"cut"` | **1.0** | 45 s | 0.5 s | Edge bleed (CombatTags cut) |
| `&"deep"` | **2.5** | 70 s | 0.5 s | Heavy bleed (CombatTags deep) |

Shared cadence default: `TICK_INTERVAL_SEC` **0.5 s**. Bleed applies as
`sum(bleed rates) × elapsed` each tick while tags are present.

### Soft wound counter decay

| Knob | Value | Rule |
|---|---|---|
| `SOFT_WOUND_DECAY_SEC` | **30 s** | −1 soft wound every 30 s while `wounds > 0` |
| `SOFT_WOUND_DECAY_OUT_OF_COMBAT_ONLY` | **false** | **ALWAYS** decay (stub). Set true + `CharacterHealth.set_in_combat` to gate later |

Tag clear after `decay_sec` does **not** auto-adjust the integer wound counter
(counter has its own timer). `clear_wounds` / `restore_full` / `clear_wound_tags`
wipe tags, ages, and bleed/soft accumulators.

### CharacterHealth wire (stub)

- `_process` → `_tick_wound_decay` when `enable_wound_decay` (default true) and not dead
- Ages parallel `wound_tags`; expired tags drop off the list
- `get_wound_decay_debug_text()` / `dump_wound_decay_table()` for F5
- CombatTags `wound_entry` optionally surfaces `bleed_hp_per_sec` / `decay_sec` from this table (link only — do not retune flank/posture/stamina/hatchet numbers here)

API: `entry(tag)`, `bleed_hp_per_sec`, `decay_sec`, `total_bleed_hp_per_sec(tags)`,
`resolve_tick_interval(tags)`, `to_debug_dict()`, `get_debug_text(...)`.

Edit numbers in `WoundDecayTable` only.

### F5 probe (wound decay)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — panel appends the WoundDecayTable + live bleed/soft accum.
3. Press **F10** — prints the same dump to the Output panel
   (`CharacterHealth.dump_wound_decay_table()` /
   `WoundDecayTable.get_debug_text()`).
4. Apply a cut/deep (take a charged hit, or Remote:
   `CharacterHealth.apply_wound_tag(&"cut")`). Confirm bleed_rate > 0 and HP
   ticks down; wait / Remote advance soft_accum toward 30 s for −1 wound;
   **5** restore wipes state.

Key map (no collision with stamina **V** / **backtick**, hatchet **F6**, tags
**F7**, block **F8**, flank **F9**, Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F10** print wound decay dump.

## Charge ↔ stamina spend (hatchet hold-release)

Tunable greybox data — **`systems/combat/charge_stamina_table.gd`**
(`class_name ChargeStaminaTable`). Discrete STA cost per hatchet charge tier,
aligned with the existing **~0.75 s** hold-release window and
`HatchetAttackTable` tier names (`tap` / `charged` / `max`). Godot owns feel /
input timing; Systems owns this table + the spend-on-release API.

### Costs (greybox defaults)

| Tier | Alias | STA cost | ~Swings to empty (100 STA) |
|---|---|---|---|
| `&"tap"` | light | **12** | ~8 |
| `&"charged"` | mid | **28** | ~3 |
| `&"max"` | full | **34** | ~2 |

`tap` / `charged` match `StaminaEconomy` hatchet light/heavy; `max` bumps above
charged so a full 0.75 s commit costs more than a mid release.

### When spend fires (Godot contract)

| Moment | Spend? |
|---|---|
| `begin_charge` / while holding | **No** — no continuous drain |
| `cancel_charge` (sprint / hit-stun) | **No** |
| `release_charged_attack` → `try_attack` commit | **Yes** — discrete tier cost |
| Explicit `spend_for_charge` / `try_spend_for_charge` | **Yes** — same path |

Insufficient STA → API returns **`false`**; Godot must **refuse the strike**
(no swing, no recovery lock). Do not call spend while the button is held.

Thresholds (match `CombatSystem` defaults / `ChargeStaminaTable` constants):

- tap: held < `0.08` s **or** ratio < `0.22`
- charged (mid): ratio ≥ `0.55` and < `0.95`
- max (full): ratio ≥ `0.95` (~full `charge_full_secs` 0.75 s)

API: `cost_for_tier`, `tier_from_charge(ratio, held_secs)`, `can_afford`,
`try_spend_preview`, `CombatSystem.can_afford_charge` /
`spend_for_charge` / `try_spend_for_charge`, `to_debug_dict()`,
`get_debug_text(...)`.

Edit numbers in `ChargeStaminaTable` only — do not retune knife/goad
`StaminaEconomy.ATTACK` or `HatchetAttackTable` damage/reach here.

### F5 probe (charge ↔ stamina)

1. Open `scenes/main/main.tscn` and press **F5**.
2. Press **V** — panel appends the ChargeStaminaTable + last release spend.
3. Press **F12** — prints the same dump to the Output panel
   (`CombatSystem.dump_charge_stamina_table()` /
   `ChargeStaminaTable.get_debug_text()`).
4. Hold-release tap / mid / full; confirm STA drops by 12 / 28 / 34 only on
   release. Drain STA below cost and confirm strike refuses (`false`).

Key map (no collision with stamina **V** / **backtick**, hatchet **F6**, tags
**F7**, block **F8**, flank **F9**, wound decay **F10**, break→stagger **F11**, Honor **H**, Timeline **T**/**U**, Rumors **N**, Travel **G**, Crowd **\\**):
**F12** print charge↔stamina spend dump.

## Dummy counter

`dummy_fighter` telegraphs every swing (weapon cock + warm tint + `!` / `...` Label3D), then releases a weak light hatchet. Taking a hit in range triggers a reactive counter telegraph (shorter). Hitting the dummy during telegraph staggers/cancels — learnable timing, still beatable.

Guard: `_ready` calls `combat.apply_sparring_foe_guard_defaults()` so soak/posture
come from `BlockPostureTable` (face-guard path). See **Sparring foe defaults API**
above.

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
- **Stamina cost + recovery:** `StaminaEconomy` (knife/goad + hatchet recovery 0.34 / 0.58)
- **Charge ↔ STA spend (hatchet):** `ChargeStaminaTable` (tap 12 / charged 28 / max 34; spend on release)
- **Face-guard / posture:** `BlockPostureTable` (sparring; `enable_face_guard`; `apply_sparring_foe_guard_defaults`)
- **Posture break → stagger:** `BREAK_STAGGER_TAG` = `stagger_heavy` via `apply_stagger_tag` (F11)
- **Open-side flank mult:** `FlankBonusTable` (only when face does not mitigate)
- **Bleed / wound decay:** `WoundDecayTable` (CharacterHealth tick; cut/deep bleed)
- **Charge full:** 0.75s hold
- **Side hitboxes:** widened for flank chops vs face-blocking sparring foe

## Switchable block faces (#4)

Sparring dummy cycles **TOP → LEFT → RIGHT** every ~2.75s while holding
face-guard. Matching hatchet dirs mitigate via `BlockPostureTable`; mismatch /
`&"open"` take full damage (+ FlankBonusTable when face-guard is on).

## Charge footwork step (#5)

While charging, **tap WASD** for a short step (does not cancel). Holding still drifts slowly. **Sprint still cancels** charge.

## Charged hit-stop / impact juice (#6)

Charged hatchet contacts use longer hit-stop (`hit_stop_charged`), deeper time scale freeze, a short weapon kick, and a stronger camera punch.
