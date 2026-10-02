# Cattle Raid

Night raid **mission** loop (watchmen, dogs, fog, escape) can grow later.
This folder ships:

1. **Economy outcome API** — loot / upkeep / honor heat after a raid resolves.
2. **Greybox playable loop** (this ticket) — approach herd → drive cattle → home pens → success/fail HUD.

| Piece | Role |
|---|---|
| `cattle_raid_outcomes.gd` (`class_name CattleRaidOutcomes`) | Loot via `gain_cattle`, goods, band deltas, Honor/Factions heat, retaliation **data** hooks, **heat → tagged Rumors** |
| `../economy/cattle_economy.gd` | Owns a `raid_outcomes` instance + facade (`resolve_raid_success` / `resolve_raid_failure`) |
| `../../scripts/world/raid/cattle_raid_director.gd` | F5 greybox state machine (phases + E start + deliver) |
| `../../scripts/world/raid/raid_cow.gd` | Hybrid cattle (idle → herded → **goad / proximity drove** + light path bias) |
| `../../scenes/world/raid/cattle_raid_lane.tscn` | Victim pens, herd, path stubs, home return zone, **watchmen** |
| `raid_heat_bridge.gd` | Drove-gated watchmen → shared HeatTracker · heat≥85 ATTACK (no auto-fail) |
| `../../scenes/ui/cattle_raid_hud.tscn` | Phase strip + outcome banner + raid alert line |

Design: [`docs/SCOPE.md`](../../docs/SCOPE.md) (Raid · Economy · cattle-raid feedback loop).
Mercy window before full retaliation is intentional for the slice.

---

## Playable greybox (F5)

Lane is instanced on `scenes/main/main.tscn` as **CattleRaidLane** at roughly **(−8, 0, 26)** — south of spawn, clear of combat (−Z dummy), stealth (+X), and ringfort (−X).

| Step | What to do |
|---|---|
| 1 Approach | Follow the gold **Cattle raid ↓ south** sign from spawn |
| 2 Start | Enter victim pens · **E** start raid (5 placeholder head) |
| 3 Drive | Draw **goad (3)** · LMB/RMB prod (or face+near pressure) · herd peels along path **west / NW** · skirt **watchmen** LOS |
| 4 Heat | Pre-raid light pens heat · mid-drove LOS → SUSPICIOUS / **RAID ALARM** · heat ≥85 → watchmen **ATTACK** (raid still completable) |
| 5 Deliver | Reach **Home pens** pad (near ringfort) with ≥3 head · auto-resolve success (if not blown) |
| 6 Outcome | HUD banner + `CattleEconomy.resolve_raid_success(&"local_clan_herd", heads)` |
| Fail | 90s timeout · abandon → `resolve_raid_failure` (watchmen heat no longer auto-fails) |
| Retry | Back at victim pens · **E** resets herd (raid spot cooldowns clear) |

### Controls

| Input | Action |
|---|---|
| WASD / mouse | Move / look (unchanged) |
| **E** (interact) | Start raid at pens · reset/retry after resolve |
| **3 / goad** | Select cattle goad (reach staff) |
| **LMB / RMB** | Prod / heavy prod — impulse + peel on herd |
| Face + near | Soft proximity steer while goad is drawn (marks drove after ~0.45s) |

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
| `heat_magnitude` | `\|honor_overall\| + \|honor_victim\| × 0.25` when heat applied |
| `rumor_seeded` / `rumor_id` | Whether resolve auto-seeded a tagged raid-heat rumor |

Failure outcomes add `cattle_lost` and set `success: false` / `reason: raid_failed`.

---


---

## Goad physics (hybrid drove)

Standing polish after the follow-drove stand-in: cattle no longer auto-trail the player on raid start.

| Layer | Behaviour |
|---|---|
| **Raid start (E)** | `begin_herd()` — cows marked **herd**, idle mill at pens |
| **Goad hit** | Combat hitbox → `apply_goad` (Hurtbox layer 4) — impulse along facing + lateral peel by `cow_id` |
| **Proximity** | Goad drawn + facing toward cow within ~3.4 m → soft push; after ~0.45 s marks **drove** |
| **Path bias** | Driven cows take a light steer toward Path0→1→2 → ReturnZone (completable without pixel-perfect prods) |
| **Soft follow** | Weak trail slot only while driven — goad + path own authority |
| **Feedback** | Flash + `prodded!` / `drove!` label + spark VFX; HUD tip `Goad (3) · LMB/RMB prod` |
| **Hooks** | `CattleRaidDirector.cow_goaded` reserved for later watchmen / raid-heat (unmerged) |

Hatchet / knife swings **ignore** `raid_cattle` (no slaughtering the loot). Delivery / timeout / CattleEconomy resolve unchanged. Completable: prod ≥3 head (or proximity-mark them), walk west; path bias keeps the drove moving toward home pens within the 90 s window.

```gdscript
# Per-cow
cow.apply_goad(player.global_position, -player.global_transform.basis.z, 1.0, &"light")
cow.begin_herd()
cow.set_path_bias([path0, path1, path2], return_zone.global_position)
```

## Tools

| Script | Purpose |
|---|---|
| `tools/capture_cattle_raid_screenshots.gd` | Headless SubViewport proof shots → `/workspace/riocht-builds/screenshots/cattle-raid/` |
| `tools/capture_watchmen_heat_screenshots.gd` | Watchmen idle / spotted / heat UI / calm success → `…/watchmen-heat/` |
| `tools/smoke_cattle_raid.gd` | Begin → force deliver → assert economy loot |
| `tools/smoke_watchmen_raid_heat.gd` | Spot mid-drove → heat rises; undetected deliver still succeeds |
| `tools/smoke_goad_physics.gd` | Begin herd (0 driven) → goad ≥3 → force deliver |
| `tools/capture_goad_physics_screenshots.gd` | Proof shots → `/workspace/riocht-builds/screenshots/goad-physics/` |

```bash
cd /workspace/riocht-wt/goad-physics
# Smoke OK headless (Dummy renderer).
DISPLAY=:1 /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path . --script res://tools/smoke_cattle_raid.gd
DISPLAY=:1 /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path . --script res://tools/smoke_goad_physics.gd
# Screenshots need a real GL context (omit --headless on Xvfb).
DISPLAY=:1 /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --path . --script res://tools/capture_goad_physics_screenshots.gd
```

---


---

## Cattle-raid heat → Rumors (tagged)

When `resolve_raid_success` / `resolve_raid_failure` apply **significant** honor /
attitude heat (or retaliation escalates past mercy), the resolve path auto-seeds
a tagged Rumors entry. Callers need no second call — same pattern as
Factions attitude/graph → Rumors.

### Thresholds (`CattleRaidOutcomes`)

| Const | Value | Seeds when |
|---|---|---|
| `RUMOR_HEAT_ATTITUDE_THRESHOLD` | **10.0** | `\|attitude_delta\|` ≥ 10 (same floor as `Factions.RUMOR_ATTITUDE_THRESHOLD`) |
| `RUMOR_HEAT_HONOR_THRESHOLD` | **8.0** | `honor_heat_magnitude` = `\|overall\| + \|victim\| × 0.25` ≥ 8 |
| `RUMOR_HEAT_RETALIATION_SEVERITY` | **0.5** | Past mercy window **and** retaliation `severity` ≥ 0.5 |

Mercy-window successes (first `MERCY_SUCCESS_COUNT` = 2 per victim) soft-scale
heat below these floors for most targets — so the **first soft raids stay quiet**
on the bus; the **third+** (full heat / escalation) light up tagged rumors.

Failure heat (attitude −4, light honor) is normally **below** threshold — no
spam on bungled nights unless severity somehow escalates.

### Tags / source

| Tag | Meaning |
|---|---|
| `raid` | Cattle-raid sourced (`Rumors.TAG_RAID`) |
| `heat` | Diplomatic / honor heat swing (`Rumors.TAG_HEAT`) |
| `faction:<victim>` | Victim roster id |
| `direction:colder` | Raids chill relations |
| `retaliation` | Present when past mercy (escalated) |

- `source_event`: `&"raid"`
- Priority: **HIGH** when escalated (or attitude ≥ 1.5× threshold); else **NORMAL**
- Lifetime: 8d (10d escalated)
- When the raid path seeds, `Factions.modify_attitude(..., seed_rumor=false)` so
  the bus does not also post a plain `attitude` rumor for the same swing.
- `&"raid"` is in `Rumors.FACTION_NUDGE_SKIP_SOURCES` (no reverse attitude double-dip).

Outcome dict adds: `rumor_seeded`, `rumor_id`, `heat_magnitude`.

```gdscript
cattle.resolve_raid_success(&"local_clan_herd")  # mercy ×2 — usually no raid rumor
cattle.resolve_raid_success(&"local_clan_herd")
var hot: Dictionary = cattle.resolve_raid_success(&"local_clan_herd")  # heat → rumor
print(hot.get("rumor_seeded"), hot.get("rumor_id"), hot.get("heat_magnitude"))
print(Rumors.filter_rumors(0, &"raid"))
print(Rumors.filter_by_faction(&"local_clans"))
print(cattle.get_raid_rumor_heat_thresholds())
```

### F5 notes (no Godot binary in this ticket)

1. F5 main → drive a cattle raid south (**E** at pens → home pad) — first deliver
   is usually mercy (check HUD / outcome; Rumors **N** may stay quiet for raid tags).
2. Retry the same victim pens twice more past mercy — third success should seed a
   tagged line on the Rumors bus (**N**): look for `{raid,heat,faction:local_clans,direction:colder,retaliation}`.
3. Or remote / debugger without the lane:

```gdscript
var cattle := get_tree().get_first_node_in_group("ringfort").get_node("CattleEconomy")
cattle.raid_outcomes.reset_heat_tracking()
for i in 3:
	var o: Dictionary = cattle.resolve_raid_success(&"local_clan_herd", 5)
	print(i, " seeded=", o.get("rumor_seeded"), " att=", o.get("attitude_delta"), " mag=", o.get("heat_magnitude"))
print(Rumors.get_debug_text())
```

4. Confirm `spawn_rumor=false` skips seeding; `apply_heat=false` also skips.

## Watchmen / raid heat (this slice)

Lane watchmen reuse `scenes/characters/npcs/sentry.tscn` + `DetectionSensor` (same LOS/hearing as stealth).
During **DRIVING / RAIDING** only, `RaidHeatBridge` forwards SUSPICIOUS / ALERT into the shared
`systems/stealth/heat_tracker.gd` (extend, not fork):

| Event | Heat | Feedback |
|---|---|---|
| Watchman SUSPICIOUS mid-drove | `+raid_suspicious_bump` (8) | Banner + HUD “stirring” |
| First ALERT mid-drove | `+raid_alert_bump` (22) + **RAID ALARM** | Heat HUD · raid banner · watchman tint |
| Still seen later | `+raid_rediscovery_bump` (10) | “Watchmen still on you” |
| Heat ≥ **85** (bridge export) | Fail `watchmen_alarm` | Outcome banner “RAID BLOWN” |
| Undetected deliver | Unchanged success path | No alarm · economy resolve as before |

Calm path: crouch (Ctrl/C), skirt LOS cones (debug wedges on), keep heat under the fail threshold.
Shared heat also covers bog body discovery — one meter for the demo.

| Piece | Role |
|---|---|
| `raid_heat_bridge.gd` | Drove-gated wiring watchmen → HeatTracker · optional fail |
| `Watchmen/*` in `cattle_raid_lane.tscn` | 3 greybox sentries on pens / mid-path / home approach |
| `HeatTracker.note_raid_*` | Raid bump / alarm / cooldowns |
| `CattleRaidHUD` RaidAlertLabel | Mid-drove heat / ALARM strip |

### Debug

```gdscript
var lane = get_tree().get_first_node_in_group("cattle_raid")
lane.debug_begin_raid()
lane.debug_force_watchman_spot()  # ALERT bump + sensor force
lane.get_raid_heat()
```

## Out of scope (still)

- Dogs / fog / night FOV during the drove
- Executing counter-raids or patrol spawns (retaliation is data-only)
- Full procedural raid generator
- Mounted cattle-drive (on-foot goad hybrid is in; mounted combat deferred)
- Separate raid-only heat meter (**locked:** one shared HeatTracker — if one enemy alerted, all alerted)

### Follow-ups (locked)
- **Q3:** ~~split separate raid heat meter~~ — **rejected**; keep shared HeatTracker / shared Heat HUD.
- Q1/Q2/Q4 applied: soft-fail attack @85, light pre-raid pens heat, facing pass + light calm cover.
