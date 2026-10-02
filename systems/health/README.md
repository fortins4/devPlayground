# Character health (vitals stub)

Session-level vitals for **Cian Ó Braonáin** (protagonist) plus an optional
single companion slot. Runtime API: `scripts/autoload/character_health.gd`
(autoload **`CharacterHealth`**).

| Piece | Role |
|---|---|
| `scripts/autoload/character_health.gd` | HP / stamina / wounds + downed/death stub + companion slot |
| `systems/health/health_combat_bridge.gd` | Optional player-only bridge: `CombatSystem` ↔ `CharacterHealth` |
| `scenes/ui/health_debug_hud.tscn` | F5 greybox panel (instanced on `scenes/main/main.tscn`) |

**Not** a combat sim — per-entity melee lives in [`systems/combat/`](../combat/)
(`CombatSystem`). **Not** band roster / upkeep — that is
[`BandUpkeep`](../economy/band_upkeep.gd) / CattleEconomy. This stub is the
data + signals surface HUD / feel systems bind to later.

Stealth remains first-class; combat exists, but HUD binding should prefer
`CharacterHealth` signals over reaching into `CombatSystem` internals.
Player greybox wires `HealthCombatBridge` on the player only so melee damage
mirrors into this autoload (NPCs stay on independent `CombatSystem` vitals).

---

## Public API

### Player (Cian)

| API | Meaning |
|---|---|
| `get_hp()` / `get_max_hp()` | Current / max HP |
| `set_hp(value)` / `modify_hp(delta)` | Set or delta; clamp 0..max; returns applied delta |
| `set_max_hp(value, fill := false)` | Raise / lower ceiling |
| `get_stamina()` / `modify_stamina(delta)` / `set_stamina(value)` | Same pattern for stamina |
| `get_wounds()` / `add_wound()` / `modify_wounds(delta)` / `clear_wounds()` | Soft injury counter 0..`MAX_WOUNDS` (5) |
| `is_alive()` / `get_is_downed()` / `get_is_dead()` | Stub flags for HUD |
| `set_downed(downed, mark_dead := false)` | Scripted downed / dead without fancy scene |
| `revive(fill_vitals := true)` | Clear dead/downed; optional full refill |
| `restore_full()` | Full HP/STA, clear wounds; revive if needed |

Clamp is always applied. HP ≤ 0 sets **downed** + **dead** stub and emits
`died` (no death scene / load flow yet). Use `revive()` to stand back up.

### Companion slot (optional, single)

| API | Meaning |
|---|---|
| `set_companion(id, display_name := "", max_health := 80, current_hp := -1)` | Activate slot |
| `clear_companion()` | Empty slot |
| `has_companion()` / `get_companion_hp()` / `modify_companion_hp(delta)` | Query / tick |

Band warriors stay in `BandUpkeep` — this slot is for a named companion beat
(story / escort), not muster size.

### Signals (HUD bind)

```gdscript
CharacterHealth.health_changed.connect(func(cur, mx): ...)
CharacterHealth.stamina_changed.connect(func(cur, mx): ...)
CharacterHealth.wounds_changed.connect(func(count): ...)
CharacterHealth.vital_depleted.connect(func(vital): ...)   # &"hp" | &"stamina"
CharacterHealth.vital_restored.connect(func(vital): ...)
CharacterHealth.downed_changed.connect(func(is_downed): ...)
CharacterHealth.died.connect(func(): ...)                  # stub — no scene
CharacterHealth.companion_changed.connect(func(active, id): ...)
CharacterHealth.companion_health_changed.connect(func(cur, mx): ...)
```

### Example bind (future HUD)

```gdscript
func _ready() -> void:
	CharacterHealth.health_changed.connect(_on_hp)
	CharacterHealth.stamina_changed.connect(_on_sta)
	CharacterHealth.downed_changed.connect(_on_downed)
	_on_hp(CharacterHealth.hp, CharacterHealth.max_hp)

func _on_hp(cur: float, mx: float) -> void:
	hp_bar.value = cur / mx

# Damage / heal from gameplay:
CharacterHealth.modify_hp(-14.0)
CharacterHealth.modify_stamina(-22.0)
CharacterHealth.add_wound()
```

### HealthCombatBridge (player ↔ session)

`class_name HealthCombatBridge` — Node under the **player** (`scenes/characters/player/player.tscn`).
Do **not** add it to NPC / dummy scenes; their `CombatSystem` stays independent.

| API | Meaning |
|---|---|
| `bind_player_combat(combat)` | Bind a `CombatSystem` to `CharacterHealth` |
| `bind_player_entity(entity)` | Find `CombatSystem` under entity, then bind |
| `unbind()` / `is_bound()` / `get_bound_combat()` | Lifecycle |
| `apply_damage(amount, from := null, frontal := true)` | Forward through combat (or session if unbound) |
| `apply_heal(amount)` | Heal combat + session (soft-clears combat `is_dead` if HP > 0) |
| `push_combat_to_session()` / `push_session_to_combat()` | One-shot mirror |
| `to_debug_dict()` / `get_debug_text()` | Probe / F5 |

Exports (defaults on for player stub):

| Flag | Default | Role |
|---|---|---|
| `sync_combat_to_session` | `true` | Melee / combat HP·STA → `CharacterHealth` |
| `sync_session_to_combat` | `true` | Session (V-panel keys, heals) → bound combat |
| `sync_stamina` | `true` | Include stamina in both directions |
| `seed_session_from_combat_on_bind` | `true` | Seed autoload from combat on bind |
| `auto_bind_on_ready` | `true` | Resolve sibling `CombatSystem` and bind |

```gdscript
# Player scene already instances HealthCombatBridge as sibling of CombatSystem.
var bridge: HealthCombatBridge = player.get_node("HealthCombatBridge")
bridge.apply_damage(14.0)   # combat.apply_damage → CharacterHealth.hp
bridge.apply_heal(10.0)     # both surfaces
print(bridge.get_debug_text())
```

Signals: `bound_changed(is_bound)`, `synced(direction, hp, stamina)` where
`direction` is `&"combat_to_session"`, `&"session_to_combat"`, or `&"heal"`.

---

## F5 test path (CharacterHealth debug)

1. Open `project.godot` in **Godot 4.4+** and press **F5** (main scene).
2. Press **V** — CharacterHealth panel (mid-left). Confirm seed:
   - `HP 100/100   STA 100/100   Wounds 0/5`
   - `Flags: downed=false  dead=false  alive=true`
   - `Companion: (none)`
3. Press **9** — HP −10. Panel updates; `health_changed` fires (watch Remote if needed).
4. Press **9** repeatedly until HP hits 0 — panel shows `downed=true dead=true alive=false`.
5. Press **5** — `restore_full()` / revive path; flags clear, vitals full.
6. Press **7** / **8** — stamina ±10; at 0, `vital_depleted("stamina")`.
7. Press **6** — add a wound (caps at 5).
8. Press **4** — force downed stub without necessarily zeroing HP first (toggle-style force); **5** clears via restore.
9. Remote / Debugger alternatives (no HUD):
   ```gdscript
   print(CharacterHealth.to_debug_dict())
   print(CharacterHealth.get_debug_text())
   CharacterHealth.modify_hp(-40.0)
   CharacterHealth.set_companion(&"eoin", "Eoin", 80.0)
   CharacterHealth.modify_companion_hp(-20.0)
   CharacterHealth.revive()
   ```
10. Press **V** again to hide the panel.

Keys: **V** toggle (includes `StaminaEconomy` fight numbers) · **backtick** print stamina dump ·
**9** / **0** HP −10 / +10 · **7** / **8** STA −10 / +10 ·
**6** wound+ · **5** restore full · **4** force downed stub.

Session `max_stamina` defaults from `StaminaEconomy.MAX_STAMINA` (see [`systems/combat/README.md`](../combat/README.md#stamina-economy-fight-numbers)).

Layout: Honor **H** top-left · Timeline **T** top-right · Rumors **N** bottom-left ·
Travel **G** bottom-right · **CharacterHealth V** mid-left (below Honor).

Combat HUD (always-on HP/STA from `CombatSystem`) stays wired to the component;
with the bridge on the player, those values should stay in lockstep with this
panel when you take a hit or press **9** / **0**.

### F5 bridge check (CombatSystem ↔ CharacterHealth)

1. F5 main scene. Press **V** — panel should show bridge status lines when the
   player `HealthCombatBridge` is bound (`bound=true`, `match hp=true`).
2. Walk into the dummy and take a hit (or Remote:
   `player.health_bridge.apply_damage(14.0)`).
3. Confirm Combat HUD HP and V-panel HP match; `match hp=true` on the panel.
4. Press **9** (session −10) — Combat HUD HP should drop too (`session→combat`).
5. Press **5** restore — both surfaces refill.
6. Headless (when Godot is available):
   `godot --headless --path . --script res://tools/probe_health_combat_bridge.gd`
