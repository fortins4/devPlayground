# Economy

Cattle as primary wealth.

| Script | Role |
|---|---|
| `cattle_economy.gd` | Herd size, pen capacity, daily herd upkeep, Norse trade contact stub |
| `band_upkeep.gd` | Band size / morale / readiness + cattle upkeep hooks for later recruitment |

Call `CattleEconomy.apply_daily_upkeep()` from the ringfort / sim owner on each `WorldClock` day. No recruitment UI here.
