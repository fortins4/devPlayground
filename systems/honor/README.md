# Honor (Enech)

Brehon-law honor / reputation. Runtime API: `scripts/autoload/honor.gd` (autoload **`Honor`**).

| Piece | Role |
|---|---|
| `scripts/autoload/honor.gd` | Per-faction + overall standing; law gates; rumor on big swings |
| [`law_gate_sample.gd`](law_gate_sample.gd) (`class_name LawGateSample`) | F5 single-dispute runner (cycles `LawDialogueSamples` packs) |
| [`law_dialogue_samples.gd`](law_dialogue_samples.gd) (`class_name LawDialogueSamples`) | Authored multi-dispute packs + **unlocked-lines** query API |
| `scenes/ui/honor_debug_hud.tscn` | F5 greybox panel (instanced on `scenes/main/main.tscn`) |
| `tools/probe_honor_law_dialogue.gd` | Headless / remote unlock probe |

## Law / dialogue gates

| API | Meaning |
|---|---|
| `Honor.can_choose_eraic(faction_id := &"")` | Min overall (and faction when given) to offer/accept **éraic** |
| `Honor.can_claim_sanctuary()` | Church **or** overall threshold for monastic sanctuary |
| `Honor.can_claim_sanctuary_at(site_id)` | Site-aware: known `SanctuaryLocations` id + global gate |
| `Honor.available_law_options()` | `Array[StringName]` of open options (`eraic`, `sanctuary`) for dialogue UI |

Thresholds (slice defaults): `ERAIC_MIN_OVERALL=40`, `SANCTUARY_MIN_CHURCH=30`, `SANCTUARY_MIN_OVERALL=35`.

Significant honor swings (`|delta| >= RUMOR_HONOR_THRESHOLD`) emit rumors via the Rumors bus.

Sanctuary **sites** (Glendalough / Clonmacnoise) live in [`systems/sanctuary/`](../sanctuary/) —
`SanctuaryLocations.can_claim` / `try_claim` reuse `Honor.can_claim_sanctuary()` and Church faction `&"church"`.

---

## Unlocked-lines query API (dialogue directors)

Primary contract for “which lines unlock under current Honor?” — polish on top of
the existing éraic / sanctuary gates (not a full dialogue rewrite).

| API | Returns |
|---|---|
| `LawDialogueSamples.list_unlocked_lines(id, faction := &"")` | `Array[Dictionary]` rows: `id`, `speaker`, `text`, `kind` (`opener`/`flavor`/`option`/`closed`), optional `option` / `gate_kind` |
| `LawDialogueSamples.list_unlocked_line_ids(id, faction := &"")` | `Array[StringName]` — UI keys / filter |
| `LawDialogueSamples.list_open_options(id, faction := &"")` | Open law options for that dispute (`eraic`, `sanctuary`) |
| `LawDialogueSamples.query_unlocked(id := &"", faction := &"")` | One dispute detail **or** full catalog when `id` empty |
| `LawDialogueSamples.probe_unlocked(...)` | Alias of `query_unlocked` for F5 / remote docs |
| `LawDialogueSamples.build_dialogue(id, faction := &"")` | UI payload; includes `unlocked_line_ids` + `lines` |
| `LawDialogueSamples.choose_option(id, &"eraic"\|&"sanctuary", faction := &"")` | Resolve; fails closed when gate shut |

`LawGateSample.list_unlocked_lines()` / `probe_gates()` bridge the same shapes for the
active F5 dispute (`cycle_dispute` walks the pack list).

### Line kinds

| Kind | When unlocked |
|---|---|
| `opener` | Always (dispute prompt) |
| `flavor` | Honor threshold (`faction_min`/`max`, `overall_min`/`max`, `church_min`/`max`) — esteem ≥70 / contempt ≤35 |
| `option` | Honor law gate open (`option_eraic`, `option_sanctuary`) |
| `closed` | All law gates shut |

```gdscript
# Which lines unlock right now?
print(LawDialogueSamples.list_unlocked_line_ids(&"norse_harbor_theft"))
print(LawDialogueSamples.list_unlocked_lines(&"blood_feud_mediation"))

# Catalog every dispute under current Honor (remote / director dashboard)
print(LawDialogueSamples.probe_unlocked())
print(LawDialogueSamples.probe_unlocked(&"church_tithe_arrears"))

# Build UI balloon, then resolve a choice
var dlg := LawDialogueSamples.build_dialogue(&"norman_safe_conduct")
# dlg.unlocked_line_ids / dlg.lines / dlg.sample_options
var result := LawDialogueSamples.choose_option(&"norman_safe_conduct", &"eraic")
```

---

## Sample: gated dispute path

`LawGateSample` is **not** an autoload. Instance it (debug HUD does this for F5) or call from a dialogue owner:

```gdscript
var sample := LawGateSample.new()
add_child(sample)

var probe: Dictionary = sample.probe_gates()
# probe.unlocked_line_ids / probe.lines / probe.available_law_options

sample.cycle_dispute(1)   # next LawDialogueSamples pack
var eraic: Dictionary = sample.choose_eraic()
var sanctuary: Dictionary = sample.choose_sanctuary()
```

Default dispute id: `cattle_trespass_brehon`. Success paths apply per-pack honor
deltas; failures return `ok=false` and leave standing unchanged.

---

## Dialogue content samples

| Dispute id | Counterparty | Setting |
|---|---|---|
| `cattle_trespass_brehon` | `local_clans` | neighbour fence |
| `blood_feud_mediation` | `local_clans` | túath assembly green |
| `norse_harbor_theft` | `norse_wexford_waterford` | Wexford quay |
| `hospitality_breach` | `ui_chennselaig` | ringfort guest-hall |
| `church_tithe_arrears` | `church` | monastery garth / tithe barn |
| `norman_safe_conduct` | `anglo_normans` | Bannow camp / march road |
| `fian_cattle_reave` | `fian` | woodland bothy / cattle path |
| `dublin_market_slight` | `norse_dublin` | Dublin thing-mound / market |

Each pack ships opener + éraic/sanctuary option lines + esteem/contempt **flavor**
lines gated by standing (not law gates). Writers add disputes to `DISPUTES` without
touching the Honor autoload.

Flavor floors (content defaults): `FLAVOR_ESTEEM_MIN=70`, `FLAVOR_CONTEMPT_MAX=35`.

---

## F5 test path (Honor law-gate + dialogue polish)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **H** — Honor law-gate panel (top-left). Confirm seed standing:
   - `Overall: 50.0`, `Church: 50.0`
   - `Gates: eraic=true  sanctuary=true`
   - `Open options: eraic, sanctuary`
   - Active dispute id + **unlocked lines:** `opener, option_eraic, option_sanctuary`
     (no esteem/contempt flavor at mid standing)
3. Press **D** — cycle dispute packs; confirm counterparty / title / unlocked ids update.
4. Press **E** — attempt éraic on the active pack. `Last: ok=true option=eraic`.
5. Press **R** — attempt sanctuary. `ok=true option=sanctuary`; church honor rises.
6. Close the gates, then retry:
   - **[** several times — drop overall below 40
   - **;** several times — drop church honor
   - Panel: `eraic=false`, `sanctuary=false`, unlocked includes `closed`, options locked
   - **E** / **R** fail closed (`ok=false`)
7. Esteem / contempt flavor:
   - **]** until overall (or faction via play) ≥ 70 → esteem flavor id appears in unlocked
   - **[** until ≤ 35 → contempt flavor id; esteem locks
8. Press **F** — dump `LawDialogueSamples.probe_unlocked()` + active `probe_gates()` to Output.
9. Press **H** again to hide the panel.

Keys: **H** toggle · **[** / **]** overall −5 / +5 · **;** / **'** church −5 / +5 ·
**E** éraic · **R** sanctuary · **D** cycle dispute · **F** dump unlock probe.

Timeline debug remains on **T** / **Y** / **U** (top-right); Honor panel uses top-left.

### Remote / Debugger (no HUD)

```gdscript
print(Honor.to_debug_dict())
print(LawDialogueSamples.probe_unlocked())
print(LawDialogueSamples.probe_unlocked(&"dublin_market_slight"))
print(LawDialogueSamples.list_unlocked_line_ids(&"fian_cattle_reave"))
print(LawDialogueSamples.build_dialogue(&"church_tithe_arrears"))
var s := LawGateSample.new()
print(s.probe_gates())
print(s.list_unlocked_lines())
```

### Headless probe script (when Godot binary available)

```bash
godot --headless --path . --script res://tools/probe_honor_law_dialogue.gd
```

Expect `PROBE_HONOR_LAW_OK` and unlocked/locked ids after the thin-enech pass.
No Godot binary on agent boxes — use F5 + **F** / Remote paste instead.

---

## Band recruitment ↔ Honor gates

Band who-can-join / cattle cost live on `BandUpkeep.RECRUIT_POOL` and the
`CattleEconomy` facade — **same recruit API**, thresholds aligned to
`Honor.overall` (0..100). See [`systems/economy/README.md`](../economy/README.md)
§ Recruitment data hooks.

| Behavior | Detail |
|---|---|
| Floor (`honor_min`) | Respectable spears / retainers need solid enech |
| Ceiling (`honor_max`) | Fían outlaws only join when enech is thin (≤ 40) |
| Cost tiers | Low enech can raise cattle cost; high enech can discount |
| Facade default | `CattleEconomy.try_recruit_option(id)` resolves `Honor.get_honor()` |

```gdscript
print(Honor.get_honor())
# From a CattleEconomy owner (ringfort):
print(cattle.probe_recruit_honor_gates())
print(cattle.probe_recruit_honor_gates(20.0))  # thin enech → fian open, retainer shut
```
