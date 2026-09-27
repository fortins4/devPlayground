# Ríocht — Game Vision (Working Title)

> *Ríocht* means "Kingdom" in Irish.

## Elevator Pitch
An open-world, historically grounded action-adventure set in **Ireland, 1169–1171 AD**, as the Anglo-Norman invasion begins. You play a set protagonist whose life is shattered in a gut-wrenching opening. Then you're released into a living sandbox where history moves forward whether you act or not. You can't stop the tide of history alone, but you can genuinely change how it plays out.

## Design Decisions (Locked)
| Decision | Choice |
|---|---|
| Historical fidelity | Stick closely to history. Real figures, real events, real places. Supernatural elements stay ambiguous folklore, never overt fantasy. |
| Protagonist | Fixed, authored character with a personal backstory and a defining opening tragedy |
| World structure | Open world sandbox. The main story is not mandatory to progress or enjoy the game. |
| Timeline model | **Living history.** Events progress on their own on a historical clock. The player can meaningfully affect outcomes (who wins, who dies, who allies with whom, local consequences), but major historical currents like the invasion itself will most likely still happen. |

## Setting
- **When:** 1169 (Norman landing at Bannow Bay) through 1171 (Siege of Dublin, arrival of Henry II).
- **Where:** Ireland, starting in Laigin (Leinster).
- **Who:** Diarmait Mac Murchada, Aífe, Richard de Clare ("Strongbow"), Ruaidrí Ua Conchobair (High King), Norse-Gaelic Dublin under Ascall mac Ragnaill, abbots, brehons, filí, and the common people of the túatha.

## The Protagonist & Opening
- A set character from a minor Gaelic clan in Leinster.
- The **opening sequence** is a tightly authored, emotional prologue. It ends in personal loss that gives the character a reason to act, then opens the full world.
- After the prologue, the character's personal story continues as **optional threads** the player can pursue at any pace, or not at all.
- The protagonist has a defined voice and personality, but the player controls choices, alliances, and methods.

## Core Pillars
1. **Living History:** Factions act on a historical timeline independent of the player. Events happen offscreen, rumors spread, and the map changes.
2. **Meaningful Influence:** Player actions change local and regional outcomes: battles, alliances, survivors, ownership of land, and how people remember you.
3. **Grounded, Weighty Combat:** Gaelic warfare (spears, axes, javelins, light armor, ambush) against armored Norman knights and crossbowmen. Terrain matters: bogs and forests favor the Gael.
4. **Honor & Law (Enech):** Brehon law gives consistent rules for every interaction: hospitality, sanctuary, honor-price (éraic). Honor is both reputation and currency.
5. **A Personal Story in a Big World:** The authored protagonist anchors the emotion. The sandbox supplies the scale.

## Structure

### World Timeline (Historical Clock)
- Major events are scheduled on an in-game calendar (e.g., Bannow Bay landing, Siege of Waterford, marriage of Aífe and Strongbow, Siege of Dublin).
- Each event has **conditions and variables** the player can influence, e.g. troop numbers, morale, supplies, whether key characters survive, and which clans join.
- **Outcome resolution:** if the player is absent, events resolve through simulation weighted toward the historical result. If the player takes part, the outcome is decided by gameplay and the state of the world.
- Consequences ripple forward: territory control, faction attitudes, available quests, and NPC fates.

### Factions
| Faction | Goals |
|---|---|
| Uí Chennselaig (Diarmait) | Retake Leinster, use Normans as allies |
| Anglo-Normans (Strongbow) | Gain land and power in Ireland |
| High Kingship (Ruaidrí) | Hold Ireland together, resist the invaders |
| Norse-Gaelic Towns (Dublin, Waterford, Wexford) | Protect trade and autonomy |
| The Church | Reform, protect monasteries, political influence |
| Local clans / outlaws (fían) | Survival, feuds, opportunity |

Each faction has goals, resources, relationships, and an attitude toward the player. Factions create dynamic quests from their current needs.

### Player Paths (Emergent, Not Classes)
Warlord · Cattle Lord · Mercenary · Brehon/Fili influence · Outlaw · Pilgrim. Players drift between these naturally through their actions.

### Home Settlement (Túath / Ringfort)
A persistent base the player rebuilds after the opening tragedy. Recruit smiths, a brehon, a fili, and warriors, and keep cattle. It can be raided, so it ties the player into the living world.

## Key Systems
| System | Description |
|---|---|
| Combat | Stamina-based and directional, with thrown spears, shield breaks, and terrain modifiers |
| Stealth & Raiding | Night cattle raids with watchmen, dogs, fog, and escape routes |
| Honor (Enech) | Reputation per faction and overall. Gates dialogue, alliances, and law options |
| Brehon Law | Resolve disputes with an honor-price instead of bloodshed. Breaking the law has consequences |
| Economy | Cattle are the main currency, plus trade goods in Norse towns |
| Poets & Satire | Filí raise your standing or damage enemies' morale and support |
| Rumors | Spread news of offscreen events and guide players toward opportunities |
| Traversal | Foot, horseback, currach boats, and climbing round towers |

## World Regions
- **Laigin (Leinster):** Starting region, home of the prologue, Norman landing site.
- **Áth Cliath (Dublin):** Norse-Gaelic trade city, center of intrigue and siege.
- **Glendalough / Clonmacnoise:** Monastic centers.
- **The Midlands Bogs:** Guerrilla country.
- **Connacht:** Seat of the High King, wild western coast.

## Tone & Art Direction
- Muted greens, peat browns, and mist, with vivid accents from Celtic enamel, illuminated manuscripts, and woven cloaks.
- Music: uilleann pipes, bodhrán, sean-nós singing, Old Irish chant.
- References: *Kingdom Come: Deliverance* (grounding), *Ghost of Tsushima* (mood), *Mount & Blade: Bannerlord* (faction sandbox), *Red Dead Redemption 2* (authored protagonist in an open world).

## Key Risks & Mitigations
| Risk | Mitigation |
|---|---|
| Sandbox aimlessness | Rumor system, visible timeline, faction-driven quests |
| Scope of faction AI | Start with 3 factions in 1 region |
| Historical accuracy vs. player agency | Weighted outcomes: history is the default, not a guarantee |
| Economy exploits (endless raiding) | Faction retaliation, honor penalties, cattle upkeep |

## Prototype Scope (Vertical Slice)
1. Prologue / opening sequence (greybox)
2. Leinster open-world region (small greybox)
3. Core third-person combat
4. Honor (Enech) reputation system
5. 3 factions with basic AI and relationships
6. World timeline with one event (Bannow Bay landing) and variable outcomes
7. Cattle raid mission loop
8. Cattle economy
9. Upgradeable home ringfort
10. Rumor system

## Open Questions
- Engine choice (Unity / Unreal / Godot)
- Protagonist name, gender, and backstory details
- Post-1171 ending: hard end at Henry II's arrival, or continued sandbox?
