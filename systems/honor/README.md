# Honor (Enech)

Brehon-law honor / reputation. Runtime API: `scripts/autoload/honor.gd` (autoload **`Honor`**).

| Piece | Role |
|---|---|
| `scripts/autoload/honor.gd` | Per-faction + overall standing; law gates; rumor on big swings |
| [`law_gate_sample.gd`](law_gate_sample.gd) (`class_name LawGateSample`) | Runtime sample beat for one dispute (`cattle_trespass_brehon`) |
| [`law_dialogue_samples.gd`](law_dialogue_samples.gd) (`class_name LawDialogueSamples`) | Authored multi-dispute dialogue content Godot can drive via the same gates |
| `scenes/ui/honor_debug_hud.tscn` | F5 greybox panel (instanced on `scenes/main/main.tscn`) |

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

## Sample: gated dispute path

`LawGateSample` is **not** an autoload. Instance it (debug HUD does this for F5) or call from a dialogue owner:

```gdscript
var sample := LawGateSample.new()
add_child(sample)

var probe: Dictionary = sample.probe_gates()
# probe.available_law_options / probe.lines — feed a dialogue UI

var eraic: Dictionary = sample.choose_eraic()       # fails closed if gate shut
var sanctuary: Dictionary = sample.choose_sanctuary()
# or: sample.choose_option(&"eraic") / sample.choose_option(&"sanctuary")
```

Sample dispute id: `cattle_trespass_brehon` (neighbour fence / cattle trespass).  
Success paths apply a small positive honor ripple; failures return `ok=false` and leave standing unchanged.

---

## Dialogue content samples

[`law_dialogue_samples.gd`](law_dialogue_samples.gd) holds **authored** dispute packs that
reuse the same Honor gates (`éraic` / `sanctuary`). Dialogue UI / Godot owners should:

1. Pick a dispute id from `LawDialogueSamples.list_dispute_ids()`
2. Call `LawDialogueSamples.build_dialogue(id)` → `lines` + open options
3. On player choice, call `LawDialogueSamples.choose_option(id, &"eraic"|"sanctuary")`

| Dispute id | Counterparty | Setting |
|---|---|---|
| `cattle_trespass_brehon` | `local_clans` | neighbour fence (same beat as `LawGateSample`) |
| `blood_feud_mediation` | `local_clans` | túath assembly green |
| `norse_harbor_theft` | `norse_wexford_waterford` | Wexford quay |
| `hospitality_breach` | `ui_chennselaig` | ringfort guest-hall |

Gates fail closed when Honor standing is too low — same thresholds as
`ERAIC_MIN_OVERALL` / `SANCTUARY_MIN_*`. Success paths apply the per-dispute
`honor_on_eraic` / `honor_on_sanctuary` deltas and stamp `Honor.last_law_result`.

```gdscript
# List + build lines for a dialogue balloon / choice UI
print(LawDialogueSamples.list_dispute_ids())
var dlg := LawDialogueSamples.build_dialogue(&"blood_feud_mediation")
# dlg.lines — opener + gated player options (or closed_line)
var result := LawDialogueSamples.choose_option(&"blood_feud_mediation", &"eraic")
# result.ok / result.summary / honor deltas
```

`LawGateSample` remains the F5 debug single-dispute runner; content packs live here
so writers can add disputes without touching the autoload.

---

## F5 test path (Honor law-gate debug)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **H** — Honor law-gate panel (top-left). Confirm seed standing:
   - `Overall: 50.0`, `Church: 50.0` (faction table mirrors overall at boot)
   - `Gates: eraic=true  sanctuary=true`
   - `Open options: eraic, sanctuary`
   - Sample dispute id `cattle_trespass_brehon` listed
3. Press **E** — attempt éraic. Panel `Last:` should show `ok=true option=eraic` and a brief summary; overall/faction enech ticks up slightly.
4. Press **R** — attempt sanctuary. `ok=true option=sanctuary`; church honor rises.
5. Close the gates, then retry:
   - **[** several times — drop overall below 40 (and below sanctuary overall floor)
   - **;** several times — drop church honor
   - Panel should show `eraic=false`, `sanctuary=false`, `Open options: (none …)`
   - **E** / **R** now fail closed (`ok=false`) with refusal summaries
6. Re-open with **]** (overall +5) and **'** (church +5), confirm options return.
7. Remote / Debugger alternatives (no HUD):
   ```gdscript
   print(Honor.to_debug_dict())
   print(Honor.available_law_options())
   var s := LawGateSample.new()
   print(s.probe_gates())
   print(s.choose_eraic())
   ```
8. Press **H** again to hide the panel.

Keys: **H** toggle · **[** / **]** overall −5 / +5 · **;** / **'** church −5 / +5 · **E** éraic · **R** sanctuary.

Timeline debug remains on **T** / **Y** / **U** (top-right); Honor panel uses top-left so both can be open together.

Remote check for multi-dispute content (no HUD keys yet):

```gdscript
print(LawDialogueSamples.to_debug_dict())
print(LawDialogueSamples.build_dialogue(&"norse_harbor_theft"))
print(LawDialogueSamples.choose_option(&"hospitality_breach", &"sanctuary"))
```
