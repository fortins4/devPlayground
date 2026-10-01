# Cattle Raid

Night raid **mission** loop (watchmen, dogs, fog, escape) lives in scenes later.
This folder ships the **economy outcome API** so Godot can resolve loot / upkeep /
honor heat after a raid succeeds or fails — without implementing stealth gameplay here.

| Script | Role |
|---|---|
| `cattle_raid_outcomes.gd` (`class_name CattleRaidOutcomes`) | Loot via `gain_cattle`, goods, band deltas, Honor/Factions heat, retaliation **data** hooks |
| `../economy/cattle_economy.gd` | Owns a `raid_outcomes` instance + facade (`resolve_raid_success` / `resolve_raid_failure`) |

Design: [`docs/SCOPE.md`](../../docs/SCOPE.md) (Raid · Economy · cattle-raid feedback loop).
Mercy window before full retaliation is intentional for the slice.

---

## Public API

### Prefer CattleEconomy facade (ringfort / Game)

```gdscript
var cattle := CattleEconomy.new()
add_child(cattle)  # wires raid signal forwards in _ready

# Inspect targets
cattle.list_raid_targets()
cattle.get_raid_target(&"local_clan_herd")
cattle.preview_raid_success(&"norse_coastal_pen")

# After a successful night-raid mission:
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

---

## Slice targets

| Target id | Victim faction | Base cattle | Extra | Retaliation kind |
|---|---|---|---|---|
| `local_clan_herd` | `local_clans` | 5 | — | `counter_raid` |
| `ui_chennselaig_drove` | `ui_chennselaig` | 6 | — | `tribute_demand` |
| `norse_coastal_pen` | `norse_wexford_waterford` | 4 | +1 amber goods | `patrol_heat` |
| `anglo_norman_forage` | `anglo_normans` | 5 | — | `patrol_heat` |
| `fian_camp_stock` | `fian` | 3 | — | `counter_raid` |

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
| `retaliation` | Data hook (see below) — **not** executed AI |
| `mercy_active` | First `MERCY_SUCCESS_COUNT` (2) successes per victim are softer |
| `raid_count_on_victim` | Running success tally for that faction |
| `day` | `WorldClock.day` when available |

Failure outcomes add `cattle_lost` and set `success: false` / `reason: raid_failed`.

Deny: `{ ok: false, reason: unknown_target, ... }`.

---

## Retaliation hook (data only)

```gdscript
{
  "kind": &"counter_raid",   # or tribute_demand / patrol_heat
  "victim_faction": &"local_clans",
  "delay_days": 8,           # longer under mercy
  "severity": 0.2,            # 0..1
  "cattle_at_risk": 2,
  "raid_count": 1,
  "mercy_active": true,
  "queued_day": 12,
  "note": "Victim may counter-raid pens (mercy window — delayed soft response)."
}
```

Mission / timeline / faction AI later **consumes** this dictionary. This module only
queues the payload and emits `retaliation_queued` / `raid_retaliation_queued`.

---

## Signals

On `CattleRaidOutcomes`: `raid_resolved`, `loot_applied`, `honor_heat_applied`,
`retaliation_queued`.

Forwarded on `CattleEconomy`: `raid_resolved`, `raid_loot_applied`,
`raid_honor_heat_applied`, `raid_retaliation_queued`.

Loot also trips existing `cattle_gained` / `cattle_lost` on the economy.

Rumors: successful raids post `&"raid"` source rumors (priority rises after mercy).

---

## How raid success should call it

1. Mission scene / raid director decides **success** (or failure) — stealth/bog stay there.
2. Pick a `target_id` from `list_raid_targets()` (or author one into `RAID_TARGETS`).
3. Call `cattle.resolve_raid_success(target_id)` (optionally pass exact cattle count).
4. Read `outcome.cattle_gained`, `outcome.upkeep`, `outcome.retaliation` for UI / sim.
5. Later systems schedule the retaliation hook using `delay_days` / `severity`.

```gdscript
func _on_night_raid_won(target_id: StringName, heads: int) -> void:
    var outcome := cattle.resolve_raid_success(target_id, heads)
    if not outcome.get("ok", false):
        push_warning("raid resolve failed: %s" % outcome.get("reason"))
        return
    print("Looted %d (spilled %d). Upkeep/day=%s Heat mercy=%s" % [
        outcome["cattle_gained"],
        outcome["cattle_spilled"],
        outcome["upkeep"].get("daily_total_upkeep", -1),
        outcome["mercy_active"],
    ])
    # Queue outcome["retaliation"] on your faction/timeline bus when ready.
```

---

## Out of scope (this ticket)

- Watchmen / dogs / fog / escape routes / bog body heat
- Executing counter-raids or patrol spawns
- Full procedural raid generator
