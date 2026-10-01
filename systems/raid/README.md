# Cattle Raid

Night raid **mission** loop (watchmen, dogs, fog, escape) can grow later.
This folder ships:

1. **Economy outcome API** — loot / upkeep / honor heat after a raid resolves.
2. **Greybox playable loop** (this ticket) — approach herd → drive cattle → home pens → success/fail HUD.

| Piece | Role |
|---|---|
| `cattle_raid_outcomes.gd` (`class_name CattleRaidOutcomes`) | Loot via `gain_cattle`, goods, band deltas, Honor/Factions heat, retaliation **data** hooks |
| `../economy/cattle_economy.gd` | Owns a `raid_outcomes` instance + facade (`resolve_raid_success` / `resolve_raid_failure`) |
| `../../scripts/world/raid/cattle_raid_director.gd` | F5 greybox state machine (phases + E start + deliver) |
| `../../scripts/world/raid/raid_cow.gd` | Placeholder cattle (idle wander → driven follow) |
| `../../scenes/world/raid/cattle_raid_lane.tscn` | Victim pens, herd, path stubs, home return zone |
| `../../scenes/ui/cattle_raid_hud.tscn` | Phase strip + outcome banner |

Design: [`docs/SCOPE.md`](../../docs/SCOPE.md) (Raid · Economy · cattle-raid feedback loop).
Mercy window before full retaliation is intentional for the slice.

---

## Playable greybox (F5)

Lane is instanced on `scenes/main/main.tscn` as **CattleRaidLane** at roughly **(−8, 0, 26)** — south of spawn, clear of combat (−Z dummy), stealth (+X), and ringfort (−X).

| Step | What to do |
|---|---|
| 1 Approach | Follow the gold **Cattle raid ↓ south** sign from spawn |
| 2 Start | Enter victim pens · **E** start raid (5 placeholder head) |
| 3 Drive | Cattle follow as a drove · walk the path markers **west / NW** |
| 4 Deliver | Reach **Home pens** pad (near ringfort) with ≥3 head · auto-resolve success |
| 5 Outcome | HUD banner + `CattleEconomy.resolve_raid_success(&"local_clan_herd", heads)` |
| Fail | 90s timeout (or abandon with no drove) → `resolve_raid_failure` |
| Retry | Back at victim pens · **E** resets herd |

### Controls

| Input | Action |
|---|---|
| WASD / mouse | Move / look (unchanged) |
| **E** (interact) | Start raid at pens · reset/retry after resolve |
| 3 / goad | Optional flavour (goad weapon exists; drive is proximity follow this slice) |

Combat lane (−Z), stealth (+X), ringfort muster (−X / E recruit / H follow) stay intact.
Band slice locks unchanged: cap 3, kerne-only, presentational, no save — this raid does **not** spawn followers.

### Phases

`idle → approach → driving → success|failed` (see `CattleRaidDirector.Phase`).

---

## Public API (economy outcomes)

### Prefer CattleEconomy facade (ringfort / Game)

```gdscript
var cattle := CattleEconomy.new()
add_child(cattle)  # wires raid signal forwards in _ready

# Inspect targets
cattle.list_raid_targets()
cattle.get_raid_target(&"local_clan_herd")
cattle.preview_raid_success(&"norse_coastal_pen")

# After a successful night-raid mission / greybox deliver:
var outcome: Dictionary = cattle.resolve_raid_success(&"local_clan_herd")
# Optional explicit loot size (else target base + variance/2):
outcome = cattle.resolve_raid_success(&"anglo_norman_forage", 7)

# Failed raid (lighter heat, possible cattle loss, band hit):
var fail: Dictionary = cattle.resolve_raid_failure(&"local_clan_herd")

# Retaliation payload only (no mutate):
cattle.get_raid_retaliation_hook(&"local_clans", &"counter_raid", 4)
```

### Direct CattleRaidOutcomes

```gdscript
var resolver := CattleRaidOutcomes.new()
resolver.resolve_success(cattle, &"norse_coastal_pen")
resolver.resolve_failure(cattle, &"ui_chennselaig_drove")
resolver.preview_success(cattle, &"fian_camp_stock", 3)
resolver.build_retaliation_hook(&"fian", &"counter_raid", 1, 3, true)
resolver.reset_heat_tracking()
print(resolver.to_debug_dict())
```

### Director smoke hooks

```gdscript
var lane = get_tree().get_first_node_in_group("cattle_raid")
lane.debug_begin_raid()
lane.debug_force_deliver()  # teleports drove into return zone + resolves
```

---

## Slice targets

| Target id | Victim faction | Base cattle | Extra | Retaliation kind |
|---|---|---|---|---|
| `local_clan_herd` | `local_clans` | 5 | — | `counter_raid` |
| `ui_chennselaig_drove` | `ui_chennselaig` | 6 | — | `tribute_demand` |
| `norse_coastal_pen` | `norse_wexford_waterford` | 4 | +1 amber goods | `patrol_heat` |
| `anglo_norman_forage` | `anglo_normans` | 5 | — | `patrol_heat` |
| `fian_camp_stock` | `fian` | 3 | — | `counter_raid` |

Greybox lane uses `local_clan_herd` and passes delivered head count into `resolve_raid_success`.

---

## Outcome Dictionary (success)

| Key | Meaning |
|---|---|
| `ok` | Target known / resolve ran |
| `success` | `true` for win path |
| `target_id` / `victim_faction` / `display_name` | Who was hit |
| `cattle_loot` | Heads attempted |
| `cattle_gained` | Heads actually added via `gain_cattle` (pen-capped) |
| `cattle_spilled` | Loot that did not fit pens |
| `goods_gained` | Trade goods applied onto `CattleEconomy.trade_goods` |
| `honor_delta_overall` / `honor_delta_victim` | Applied through `Honor.modify_honor` |
| `attitude_delta` | Applied through `Factions.modify_attitude` |
| `band_morale_delta` / `band_readiness_delta` | Raid fatigue / cheer |
| `upkeep` | Snapshot: herd size, daily herd/band/total costs after loot |
| `retaliation` | Data hook — **not** executed AI |
| `mercy_active` | First `MERCY_SUCCESS_COUNT` (2) successes per victim are softer |
| `raid_count_on_victim` | Running success tally for that faction |
| `day` | `WorldClock.day` when available |

Failure outcomes add `cattle_lost` and set `success: false` / `reason: raid_failed`.

---

## Tools

| Script | Purpose |
|---|---|
| `tools/capture_cattle_raid_screenshots.gd` | Headless SubViewport proof shots → `/workspace/riocht-builds/screenshots/cattle-raid/` |
| `tools/smoke_cattle_raid.gd` | Begin → force deliver → assert economy loot |

```bash
cd /workspace/riocht-wt/cattle-raid
# Smoke OK headless (Dummy renderer).
DISPLAY=:1 /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path . --script res://tools/smoke_cattle_raid.gd
# Screenshots need a real GL context (omit --headless on Xvfb).
DISPLAY=:1 /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --path . --script res://tools/capture_cattle_raid_screenshots.gd
```

---

## Out of scope (still)

- Watchmen / dogs / fog / bog body heat during the drove
- Executing counter-raids or patrol spawns (retaliation is data-only)
- Full procedural raid generator
- Mounted cattle-drive / goad physics herding (goad weapon exists; follow-drove is the greybox stand-in)
