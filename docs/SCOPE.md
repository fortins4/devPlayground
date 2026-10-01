# Ríocht — Full Intended Scope

Companion to [VISION.md](VISION.md). Vision answers *what the game is*; this document answers *what we intend to ship*, in layers from now → vertical slice → full game.

Status: **draft** (2026-10-01; Systems + Godot folded; product locks applied). Locked design decisions live in VISION.md; open product questions are listed at the end.

---

## Scope layers

| Layer | Purpose |
|---|---|
| **Now (scaffold)** | Runnable Godot 4.4 Forward+ project, folder layout, autoload stubs, greybox main scene |
| **Vertical slice** | One playable Leinster loop that proves living history, honor, combat, raid, and home base |
| **Full game (intended)** | Authored prologue + multi-region Ireland, 1169–1171, with emergent faction sandbox and personal story threads |
| **Explicitly out of scope** | Overt fantasy magic, multiplayer, character creator, authored post-1171 campaign (sandbox after the arc is in) |

---

## Now — what exists

- Godot 4.4 Forward+ project named **Ríocht**
- Autoloads: `Game`, `WorldClock`, `Honor`, `Factions`, `Rumors`
- Folder map for prologue, Leinster, ringfort, combat, honor, factions, timeline, economy, raid, rumors
- Greybox main scene + stylized primitive player
- Design bible: `docs/VISION.md`
- Terrain3D intended as local addon (not vendored)

Not yet: real combat loop, authored prologue beats, Terrain3D landscapes, faction AI, cattle missions, UI, audio, content beyond stubs.

---

## Vertical slice — prove the fantasy

Ship criteria: a player can finish the greybox prologue, roam a small Leinster greybox, fight, raid cattle, **recruit a small warrior band**, feel honor consequences, hear rumors of one historical event, **ambush an Anglo-Norman patrol in a minor skirmish**, and return to an upgradeable ringfort — without leaving the intended pillars.

### Content

1. **Prologue (greybox)** — authored opening tragedy; handoff via `Game.finish_prologue()` into open world
2. **Leinster greybox** — walkable starting region; Bannow Bay as landmark / event site; Terrain3D once installed
3. **Home ringfort** — rebuild after prologue; recruit at least smith + warrior; cattle pens; vulnerable to raid

### Systems (slice versions)

| System | Slice target |
|---|---|
| Combat | Third-person stamina + directional attacks; spear / shield basics; terrain modifiers stubbed |
| Honor (Enech) | Per-faction + overall reputation; gates at least dialogue tone and one law option |
| Factions | **3 active** in Leinster (Uí Chennselaig, Anglo-Normans, local clans or Norse-Gaelic); attitudes −100…+100; basic needs → 1–2 dynamic quests |
| Timeline | Calendar clock; **one** event: Bannow Bay landing; absent-player weighted historical resolve; present-player can shift variables (troops, morale, survivors) |
| Economy | Cattle as primary wealth; upkeep; simple trade stub in one Norse town contact |
| Raid | Night cattle-raid loop: watchmen, dogs, fog, escape route |
| Rumors | Offscreen event news + pointers toward raid / faction opportunities |
| Band / recruitment | Recruit a few warriors over time; band is visible at ringfort and on the road |
| Ambush / skirmish | One minor ambush vs an Anglo-Norman patrol using the band (confidence gated by band size/readiness) |
| Traversal | Foot + horseback (boat / towers can wait) |

### Slice non-goals

- Full Ireland map, Connacht, Glendalough/Clonmacnoise as destinations
- Full Brehon court simulation, filí satire combat
- Branching multi-ending climax at Henry II
- High-fidelity art, full VO, cinematic polish beyond greybox readability

---

## Full game — intended ship scope

Everything below is the **intended** product if the slice succeeds. It expands systems and geography without changing locked pillars in VISION.md.

### Narrative & structure

- Fixed authored protagonist: **Cian** (placeholder) — young Gaelic man, traumatized by an Anglo-Norman raid on his village, forced into wilderness exile
- Mandatory emotional prologue (raid + exile) → personal story is **player-driven** (what you make of it); no mandatory critical path
- Living history 1169 → 1171 (Bannow Bay → Waterford → Aífe/Strongbow marriage → Siege of Dublin → Henry II arrival)
- Main story **not** required to enjoy the sandbox
- **No hard end:** after the historical / main-story arc, the game continues as an open sandbox

### Regions (full)

No fixed unlock order. Intended list:

| Region | Role |
|---|---|
| Laigin (Leinster) | Start; prologue; Cian's wilderness exile; Norman beachhead (Bannow Bay) |
| Wexford / Waterford coasts | Early Norman footholds; ports; raid & trade pressure |
| Áth Cliath (Dublin) | Norse-Gaelic intrigue; Siege of Dublin set piece |
| Wicklow / Glendalough | Monastic sanctuary; Church; pilgrimage; highland cover |
| Midlands bogs | Guerrilla terrain payoff for Gaelic combat |
| Clonmacnoise corridor | Shannon monastic center; pilgrimage / Church influence |
| Munster fringe (east) | Secondary conflict pressure (lighter depth) |
| Connacht | High King Ruaidrí; late political pressure; western coast |
| Shannon / river ways | Currach / river traversal spine |

Depth varies: Laigin and Dublin densest. Not every túath simulated.

### Factions (full roster)

Uí Chennselaig · Anglo-Normans · High Kingship · Norse-Gaelic towns · Church · Local clans / fían outlaws

Each: goals, resources, relationship graph, attitude toward player, and quest generation from current needs. Slice’s 3 factions expand to the full set as regions open.

### Historical events (intended schedule)

Minimum set on the living clock (player-absent = history-weighted; player-present = gameplay + world state):

1. Norman landing at Bannow Bay (1169)
2. Fall / struggle for Wexford and Waterford
3. Marriage of Aífe and Strongbow
4. Approaches on Dublin; Siege of Dublin (1171)
5. Arrival of Henry II

Each event exposes variables: troop strength, morale, supplies, key character survival, clan allegiance. Outcomes ripple into territory, attitudes, quests, and NPC fates.

`WorldClock` (autoload) plus event resources are the source of truth. Before content multiplies, lock one shared **EventOutcome** schema used by timeline, factions, and rumors.

Early on, prefer **one active pressure window** at a time; deep multi-event concurrency is deferred.

### Player paths (emergent)

Warlord · Cattle Lord · Mercenary · Brehon / fili influence · Outlaw · Pilgrim — no class lock; paths are labels for playstyles earned through actions.

### Systems (full)

| System | Full intent |
|---|---|
| Combat | Gaelic arms (spear, axe, javelin, light armor, ambush) vs Norman knights / crossbows; stamina, directionality, shield breaks, terrain (bog / forest / open) |
| Stealth & raiding | Night raids, watchmen, dogs, weather/fog, retaliation risk |
| Honor & Brehon law | Éraic / honor-price tables, hospitality, sanctuary; law as alternative to bloodshed; breaking law has lasting cost |
| Economy | Cattle core; Norse town trade goods; upkeep + faction retaliation against endless raiding |
| Poets & satire | Filí raise standing or damage enemy morale / support |
| Rumors | World news bus for offscreen events and opportunity hooks |
| Traversal | Foot, horseback, currach boats, climbable round towers |
| Home túath | Persistent ringfort: craftsmen, brehon, fili, warriors, cattle; can be raided; upgrades matter |
| Faction AI | Autonomous agenda on the clock; create dynamic quests; react to player honor and interference |

### Tone & presentation

- Stylized 3D (not photoreal): muted greens, peat, mist; Celtic enamel / manuscript accents
- Music: uilleann pipes, bodhrán, sean-nós, Old Irish chant
- Supernatural only as ambiguous folklore — never overt magic systems
- References (feel, not clone): Kingdom Come, Ghost of Tsushima, Bannerlord, RDR2

### Platform & tech (intended)

- Godot 4 Forward+; GDScript-first; C# only if simulation hotspots demand it
- Terrain3D for landscapes
- Single-player only

---


## Systems simulation — IN vs deferred

Systems-owned clarity for living history, factions, honor, rumors, and economy. **IN** = full intended ship. **Deferred** = after slice / later phase / out unless vision changes.

### Timeline / sim
- **IN:** Living calendar 1169→1171 with ≥5 major events; per-event variables; absent → history-weighted resolve, present → gameplay + world state; outcome ripples; `WorldClock` + event resources as source of truth
- **Deferred:** Every-túath Ireland sim; real-time grand-strategy map; authored post-1171 campaign beats (sandbox clock continues with no hard end); deep multi-event concurrency beyond one active pressure window early

### Factions
- **IN:** Full roster of 6; goals, resources, relationship graph, player attitude, needs→dynamic quests; autonomous agenda on the clock; react to honor + player interference; slice = 3 active in Leinster only, expand with regions
- **Deferred:** Full AI for all 6 from day one; nation-scale logistics; every minor túath as a sim actor

### Honor / Brehon
- **IN:** Per-faction + overall Enech; gates dialogue, alliances, law options; éraic / honor-price tables, hospitality, sanctuary as real resolution paths; law as alternative to bloodshed with lasting cost for breaking it
- **Deferred:** Full court simulation / every dispute type; filí satire as combat-adjacent system until systems-depth phase proves need

### Rumors
- **IN:** World news bus for offscreen events + opportunity hooks (raid, faction, timeline); primary anti-aimlessness tool with visible timeline + faction quests; priority and decay so the bus stays useful
- **Deferred:** Social-graph gossip simulation; rumor as a deep economy of its own

### Economy
- **IN:** Cattle as core wealth + herd upkeep; ringfort pens; raid gain/loss; Norse town trade goods; retaliation + honor hit vs endless raiding; slice = herd + upkeep + one trade stub contact
- **Deferred:** Full commodity markets, mint coinage, every port as a sim node

---

## Gameplay / scenes — IN vs deferred

Godot-owned clarity for scenes, player, combat, raid, ringfort, and regions. **IN** = full intended ship. **Deferred** = after slice / later phase / out unless vision changes.

### Scenes / structure
- **IN:** Authored prologue pack → `Game.finish_prologue()` into open world; region scenes under `scenes/world/regions/` (Leinster densest; Dublin siege-capable; monastic, bog, Connacht as destinations with varying depth); session flow BOOT → PROLOGUE → OPEN_WORLD; UI shell for honor, cattle, map/timeline, rumors, dialogue
- **Slice:** Greybox prologue + small Leinster greybox + ringfort + runnable main scene only
- **Deferred:** Full cinematic polish / VO beyond greybox readability; seamless contiguous all-Ireland stream at launch (region loads / travel gates OK); high-fidelity art before systems prove out

### Player
- **IN:** Fixed authored third-person protagonist (stylized 3D; locked voice/personality; player chooses alliances and methods); controller baseline WASD + look + jump, then combat / stealth / interact; emergent path labels (not classes); optional personal story threads after prologue
- **Slice:** Move / look / jump + enter combat + interact with raid / ringfort / NPC stubs (capsule → final mesh later)
- **Deferred:** Character creator / blank-slate protagonist; deep skill trees / class locks; full body IK / photoreal fidelity

### Combat (`systems/combat/`)
- **IN:** Stamina + directional attacks; shield breaks; thrown spears/javelins; Gaelic kit vs Norman knights/crossbows; terrain modifiers (bog/forest favor Gael; open favors Norman)
- **Slice:** Stamina + directional basics + spear/shield; terrain modifiers stubbed
- **Deferred:** Large-scale army battles as the everyday loop (rare major-battle set pieces **are** intended later); full mounted combat depth before foot combat feels good; filí satire as combat-adjacent until systems-depth phase

### Raid (`systems/raid/`)
- **IN:** Night cattle-raid loop with watchmen, dogs, fog/weather, escape routes; gain/loss ties to cattle economy + ringfort pens; retaliation + honor hit
- **Slice:** One complete night-raid loop with those pillars readable in greybox
- **Deferred:** Endless procedural raid generator with no authored anchors; naval cattle raids / island targets before currach traversal ships

### Ringfort (`scenes/world/ringfort/`)
- **IN:** Persistent upgradeable base after prologue: craftsmen (smith+), warriors, cattle pens, defenses; recruit brehon + fili in full game; base can be raided
- **Slice:** Rebuild stub + smith + warrior + pens + raid vulnerability
- **Deferred:** Full settlement builder / city sim; multiple simultaneous player bases

### World regions & traversal
- **IN:** Laigin (start, Bannow Bay; Terrain3D once addon installed); Dublin (intrigue + siege); Glendalough/Clonmacnoise; Midlands bogs; Connacht; traversal foot + horseback, plus currach boats and climbable round towers in full
- **Slice traversal:** Foot + horseback only
- **Deferred:** Connacht + full monastic/bog depth before Leinster loop is proven; accurate every-túath geography; photoreal Terrain3D before greybox gameplay locks (no fixed region unlock order)

### Band / recruitment & skirmish strategy
- **IN (core):** Recruit warriors into Cian's band over time; band size, morale, and readiness build **confidence to confront the English**; ambush patrols and fight **minor skirmishes** as the everyday strategy loop
- **IN (occasional):** **Major battles** as rare timeline / story events (sieges, named clashes) that reshape faction outcomes and narrative direction; when Cian's band is present, participation can tip variables — when absent, history-weighted resolve still applies
- **Slice:** Small recruitable party; one ambush/skirmish vs an Anglo-Norman patrol gated by band readiness; band ties to ringfort; major-battle *hook* only (full set piece can wait for systems-depth / climax phases)
- **Deferred:** Mass army battles as the *everyday* primary loop; full campaign-map army logistics; dozens of simultaneous AI warbands before slice combat + small-band skirmish feel good

### First-hour / tech notes (Godot)
- Prologue handoff needs a concrete first-hour checklist so pillars teach without a long forced tour
- Keep greybox as landscape truth until Terrain3D is installed locally (addon not vendored)
- Decide region load strategy (additive regions vs travel gates) before Dublin content
- Slice UI must make combat telegraphs, honor, cattle, and timeline readable or systems feel invisible
- Raid retaliation needs a mercy window in slice so new players are not soft-locked before they understand upkeep

---
## Content budget (order-of-magnitude, full game)

Rough targets to keep scope honest (adjust after slice):

- **1** authored prologue sequence
- **9** world regions / travel spines (depth varies: Leinster and Dublin densest; see list above)
- **6** faction templates with relationship graph
- **5+** major timeline events with outcome variables
- **Personal story**: multiple optional threads, not a mandatory critical path
- **Ringfort** upgrade tree (defenses, crafts, cattle, people)
- **Combat** kit: Gaelic set + recognizable Norman opposition
- **Band:** recruitable warriors that grow over time; ambush / minor skirmish loop vs English patrols
- **UI**: honor, cattle, map/timeline awareness, rumors feed, dialogue

Exact quest / NPC counts TBD after slice proves systems cost.

---

## Delivery phasing (suggested)

| Phase | Outcome |
|---|---|
| **0 Scaffold** | Done / in progress — project runs, stubs, vision docs |
| **1 Vertical slice** | Items in VISION.md “Prototype Scope” playable end-to-end |
| **2 Leinster content** | Real landscape, 3 factions live, Bannow Bay event, raid + ringfort loop polished |
| **3 Systems depth** | Full honor/law, economy, rumors, combat feel; filí / boats as they earn their keep |
| **4 Multi-region** | Dublin + one monastic or bog region; expand faction roster |
| **5 Climax window** | Siege of Dublin + Henry II arrival as major-battle / story events; sandbox continues after |
| **6 Polish** | Art pass, audio, UX, historical consult pass, performance |

---

## Explicitly out of scope (unless vision changes)

- Multiplayer / co-op / MMO features
- Full character creator or silent blank-slate protagonist
- Overt magic, mythic monsters as gameplay systems
- Real-time grand strategy map replacing third-person adventure
- Mass army battles as the *everyday* primary loop (ambushes/skirmishes are regular; **major battles are rare story events**)
- Accurate every-túath simulation of all Ireland at launch
- Post-1171 *authored main campaign* (sandbox after the arc **is** intended — no hard end)

---

## Risks (scope-facing)

| Risk | Mitigation |
|---|---|
| Sandbox aimlessness | Rumors, visible timeline, faction-driven quests |
| Faction AI cost | Hard-gate expansion past 3 factions × 1 region on slice metrics |
| History vs agency | Tunable history weights so living history is neither railroad nor chaos |
| Cattle-raid feedback loop | Upkeep + retaliation + honor hit early (wealth→power→more raids) |
| Rumor spam vs silence | Priority and decay on the news bus |
| Invisible honor | Slice ships with readable honor UI and at least one gated law/dialogue beat |
| Event plumbing drift | Lock one shared EventOutcome schema before content multiplies |
| Combat feel (slice make-or-break) | Do not expand regions until stamina/directional + Gael-vs-Norman read clearly |
| Prologue → world handoff | Concrete first-hour checklist after `Game.finish_prologue()` |
| Raid soft-lock for new players | Mercy window before full retaliation / upkeep pressure |
| Terrain3D install gate | Greybox landscapes remain truth until local addon install |
| Region streaming | Lock load strategy (additive vs travel gates) before Dublin content |
| UI debt | Combat telegraphs + honor/cattle/timeline readable in slice |
| Band too weak forever / too strong early | Gate English confidence on readiness; slice teaches one clear ambush win |
| Skirmish vs personal combat identity | Keep Cian playable in skirmish; band is force multiplier, not autopilot |
| Doc drift | VISION = locked pillars; SCOPE = intended ship layers; update both when decisions change |

---

## Locked product decisions (2026-10-01)

1. **Protagonist:** Cian (placeholder) — young man; village destroyed by Anglo-Norman raid; wilderness exile  
2. **Ending:** No hard end — sandbox continues after the main/historical arc  
3. **Personal story:** Player-authored through play (“what you make of it”); no mandatory critical path after prologue  
4. **Regions:** List compiled (see Regions above); **no fixed unlock order**

## Still open

1. Final name (replace placeholder when ready)  
2. How strongly the prologue teaches wilderness survival vs faction play  
3. Content depth budget per region after the slice

---

## Doc ownership

| Doc | Owns |
|---|---|
| `docs/VISION.md` | Pitch, locked design decisions, pillars, tone |
| `docs/SCOPE.md` | This file — layers of intended ship scope (Lead maintains; Systems/Godot contribute domain IN/DEFERRED) |
| `docs/SETUP.md` | Engineer onboarding / Terrain3D |

When a design decision locks, update VISION.md. When ship targets or phasing change, update this file.
