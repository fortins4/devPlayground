# Factions

Faction goals, resources, relationships, and needs→quest stubs.

Runtime registry: `scripts/autoload/factions.gd`.

## Full roster (IDs)

| ID | Display |
|---|---|
| `ui_chennselaig` | Uí Chennselaig / Diarmait |
| `anglo_normans` | Strongbow & adventurers |
| `english_crown` | Henry II (inactive until late / 1171 pressure) |
| `high_kingship` | Ruaidrí / Connacht |
| `norse_dublin` | Norse-Gaelic Dublin |
| `norse_wexford_waterford` | Norse-Gaelic Wexford/Waterford |
| `church` | The Church |
| `local_clans` | Local Leinster túatha / rival clans |
| `fian` | Fían / outlaw bands |

## Slice (Leinster-active)

1. **Uí Chennselaig** — retake Leinster; use Norman allies
2. **Anglo-Normans** — land/power; hold Bannow beachhead
3. **Norse-Gaelic Wexford/Waterford** — protect trade / coastal autonomy

`norse_wexford_waterford` is the third active faction so Bannow Bay → Wexford pressure and the Norse trade contact in `systems/economy/cattle_economy.gd` share one coastal actor. Monolithic `norse_gaelic` was split into Dublin vs Wexford/Waterford. Full roster IDs remain registered; `LEINSTER_ACTIVE` gates quest generation. `english_crown` is registered but inactive until late.

`generate_quest_stubs()` returns 1–2 data-only quest dictionaries from current needs (no quest UI).
