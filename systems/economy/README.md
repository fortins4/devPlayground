# Economy

Cattle as primary wealth. Band upkeep lives alongside for later recruitment.

| Script | Role |
|---|---|
| `cattle_economy.gd` (`class_name CattleEconomy`) | Herd, pens, daily tick, Norse trade (`norse_wexford_waterford`), band facade, **raid outcome facade** |
| `band_upkeep.gd` (`class_name BandUpkeep`) | Band size / morale / readiness, cattle cost, skirmish confidence |
| [`../raid/cattle_raid_outcomes.gd`](../raid/cattle_raid_outcomes.gd) | Cattle-raid loot / upkeep snapshot / honor heat / retaliation **data** |

**Ownership:** not an autoload. Ringfort / Game / sim owner instantiates a `CattleEconomy` node. Ringfort greybox (`scenes/world/ringfort/`) owns one for muster/recruit in F5. Prefer **explicit** `apply_daily_tick()` so Game keeps control of when the day resolves. Optional `subscribe_world_clock()` auto-applies on `WorldClock.day_advanced` if you want hands-off wiring.

Norse trade contact id stays **`norse_wexford_waterford`** (same coastal actor as Factions).

---

## Call contract (Godot)

### Daily cattle tick

```gdscript
# Explicit (preferred — call from Game / ringfort when the sim day advances):
var report: Dictionary = cattle.apply_daily_tick(WorldClock.day)
# report keys: day, herd_cost, herd_paid, starvation_loss, band_cost, band_paid,
#              herd_size, pen_capacity, pen_free_slots, band (debug dict)

# Optional auto-subscribe (does not fight Game if you never call this):
cattle.subscribe_world_clock()           # uses WorldClock autoload
cattle.subscribe_world_clock(WorldClock)
cattle.unsubscribe_world_clock()
```

`apply_daily_upkeep()` remains as an alias of `apply_daily_tick()`.

### Herd / pens / raid hooks

| Method | Returns | Notes |
|---|---|---|
| `get_herd_size()` | `int` | Current headcount |
| `get_pen_capacity()` / `get_pen_free_slots()` | `int` | Pen soft cap |
| `set_pen_capacity(capacity)` / `upgrade_pens(delta)` | — | Ringfort upgrade |
| `add_cattle(amount)` / `spend_cattle(amount)` | `int` / `bool` | Low-level; spend fails if short |
| `gain_cattle(amount, reason)` / `lose_cattle(amount, reason)` | `int` | Raid / mission hooks; emit gain/loss signals |

### Band query / update

Via facade on `CattleEconomy` (or `cattle.band` directly):

| Method | Notes |
|---|---|
| `get_band_size()` / `get_band_morale()` / `get_band_readiness()` | Queries |
| `get_band_daily_cost()` / `daily_total_upkeep_cost()` | Cattle costs |
| `get_skirmish_confidence()` → `float` 0..1 | Ambush gate input |
| `can_attempt_skirmish(min := 0.35)` | Slice ambush readiness check |
| `set_band(size, morale := -1, readiness := -1)` | Replace state (−1 = leave field) |
| `recruit_warriors(count)` / `dismiss_warriors(count)` | Size change stubs |
| `modify_band_morale(delta)` / `modify_band_readiness(delta)` | Deltas |

### Norse trade

```gdscript
cattle.trade_with_norse(&"amber", -2)  # sell 2 cattle → +1 amber
cattle.trade_with_norse(&"amber", 3)   # spend 1 amber (if held) / buy up to 3 cattle into pens
cattle.get_norse_trade_contact_id()    # &"norse_wexford_waterford"
```

### Signals (UI later)

`herd_changed`, `pens_changed`, `upkeep_applied`, `daily_tick_applied`, `trade_completed`, `cattle_gained`, `cattle_lost`, `band_changed`, `band_upkeep_failed`, `raid_resolved`, `raid_loot_applied`, `raid_honor_heat_applied`, `raid_retaliation_queued`.

---

## F5 / debug usage

Attach or instance under the main scene (or run from a debug button / `_unhandled_input`):

```gdscript
# e.g. in a ringfort or debug Node
var cattle := CattleEconomy.new()
add_child(cattle)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept"):  # Enter — advance one day + tick
        WorldClock.advance_day(1)
        print(cattle.apply_daily_tick(WorldClock.day))
    if event is InputEventKey and event.pressed and event.keycode == KEY_B:
        cattle.recruit_warriors(1)
        print("band=", cattle.band.to_debug_dict())
    if event is InputEventKey and event.pressed and event.keycode == KEY_C:
        print(cattle.to_debug_dict())
```

Or subscribe once and only advance the clock:

```gdscript
cattle.subscribe_world_clock()
WorldClock.advance_day(3)  # three daily ticks applied automatically
print(cattle.to_debug_dict())
```

Remote inspect: `print(cattle.to_debug_dict())` / `print(cattle.band.to_debug_dict())`.

---

## Recruitment data hooks (who / cost) ↔ Honor enech gates

Data/API only — **no recruitment UI**. Pool lives on `BandUpkeep.RECRUIT_POOL`;
`CattleEconomy` exposes a typed facade that pays from the herd and **auto-resolves
`Honor.overall` (0..100)** when honor is omitted (`HONOR_RESOLVE_AUTO`).

Honor scale is the same as the [`Honor`](../honor/README.md) autoload (enech),
**not** the signed faction-attitude scale. Low / high enech changes who is
recruitable and can raise or discount cattle cost.

| Option id | Base cattle | Honor gate (overall 0..100) | Cost tiers / notes |
|---|---|---|---|
| `local_kerne` | 2 | ≥ 15 | < 25 → 3 cattle |
| `ringfort_veteran` | 4 | ≥ 35, readiness ≥ 25 | < 40 → 6; ≥ 70 → 3 |
| `ui_chennselaig_retainer` | 5 | ≥ 50 + Uí Chennselaig attitude ≥ 15 | ≥ 75 → 4 |
| `fian_outlaw` | 3 | **0…40 only** (`honor_max`) | Locked at seed enech 50 — drop Honor to unlock |
| `norse_coastal_axe` | 6 | ≥ 30 + Norse attitude ≥ 10 | < 40 → 8 |

```gdscript
# Inspect (Honor auto-resolved from autoload when omitted)
cattle.get_recruit_pool()
cattle.get_recruit_cattle_cost(&"local_kerne")           # base 2
cattle.effective_recruit_cattle_cost(&"local_kerne")     # Honor-tier
cattle.list_recruit_options()                            # eligible + grey; Factions + herd
cattle.list_eligible_recruits()
cattle.probe_recruit_honor_gates()                       # remote / F5 snapshot
cattle.probe_recruit_honor_gates(20.0)                   # simulate thin enech

# Gate + pay + grow band (same API as before — now enech-gated)
var gate := cattle.can_recruit_option(&"ui_chennselaig_retainer")
var result := cattle.try_recruit_option(&"local_kerne")
# result: { ok, reason, cattle_spent, count, band_size, option, honor_score }
# Optional override: cattle.try_recruit_option(&"fian_outlaw", 25.0)
```

Direct band access: `cattle.band.can_recruit_option(id, honor, attitudes)` /
`effective_recruit_cattle_cost` / `probe_recruit_honor_gates`.
Signal: `BandUpkeep.recruit_option_denied(option_id, reason)`.

Deny reasons: `unknown_option`, `band_full`, `band_capacity`, `honor_too_low`,
`honor_too_high`, `readiness_too_low`, `faction_attitude`, `cannot_afford`,
`no_economy`, `recruit_failed`.

### F5 / remote probe (band ↔ Honor)

1. Open project in **Godot 4.4+**, press **F5** (main scene with ringfort muster).
2. Press **H** (Honor debug HUD, top-left) — confirm `Overall: 50.0` seed.
3. Remote / Debugger:
   ```gdscript
   var cattle := get_tree().get_first_node_in_group("player") # or find ringfort CattleEconomy
   # Prefer: locate RingfortArea → cattle
   print(cattle.probe_recruit_honor_gates())
   # At seed 50: fian_outlaw eligible=false deny=honor_too_high; kerne/veteran open (readiness permitting)
   ```
4. Drop enech with Honor HUD **[** (overall −5) until ~30:
   - `probe_recruit_honor_gates()` → `fian_outlaw` eligible; veteran/retainer may deny `honor_too_low`
   - Muster **E** still recruits `local_kerne` (cost may rise to 3 if < 25)
5. Raise enech with **]** to ≥ 70 — veteran cattle cost discounts; fian locks again (`honor_too_high`).
6. Ringfort muster prompt shows **effective** cattle cost for the slice kerne option.

No Godot binary in CI agents — Lead runs F5; remote `probe_recruit_honor_gates` is enough for smoke.

---

## Cattle-raid outcomes (loot / upkeep / honor heat)

Data/API only — mission stealth stays in raid scenes. Full contract:
[`systems/raid/README.md`](../raid/README.md).

```gdscript
# After a successful night raid:
var outcome := cattle.resolve_raid_success(&"local_clan_herd")
# outcome: cattle_gained (via gain_cattle), goods_gained, upkeep snapshot,
#          honor/attitude deltas, retaliation data hook, mercy_active

cattle.resolve_raid_failure(&"norse_coastal_pen")  # optional fail path
cattle.preview_raid_success(&"anglo_norman_forage", 6)
cattle.list_raid_targets()
```

Mercy: first two successes per victim faction use softer honor/attitude heat and
longer retaliation `delay_days`. Escalation stacks after the mercy window.
