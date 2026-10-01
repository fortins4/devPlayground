# Factions

Faction goals, resources, relationships, and needs→quest stubs.

Runtime registry: `scripts/autoload/factions.gd`.

## Slice (Leinster-active)

1. **Uí Chennselaig** — retake Leinster; use Norman allies
2. **Anglo-Normans** — land/power; hold Bannow beachhead
3. **Norse-Gaelic** — protect trade / Wexford–Waterford autonomy

Norse-Gaelic is the third active faction (not local clans) so Bannow Bay → Wexford pressure and the Norse trade contact in `systems/economy/cattle_economy.gd` share one coastal actor. Full roster IDs remain registered; `LEINSTER_ACTIVE` gates quest generation.

`generate_quest_stubs()` returns 1–2 data-only quest dictionaries from current needs (no quest UI).
