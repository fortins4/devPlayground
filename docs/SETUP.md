# Setup — Ríocht (Godot 4)

## Requirements

- **Godot 4.4+** (Forward+). Download from https://godotengine.org/download  
  - Terrain3D 1.0.x targets Godot **4.4–4.6+**. If you stay on **4.3**, use Terrain3D **1.0.0**.
- A GPU that supports Vulkan (or Direct3D 12 / Metal). Forward+ is the project default.

## Open the project

1. Launch the Godot Project Manager.
2. **Import** → select `/path/to/devPlayground/project.godot` (this repo root).
3. Open **Ríocht**. The editor may generate `.godot/` and `*.import` files (gitignored).
4. Press **F5** (or Play). You should see a misty greybox plane, a capsule player, and a box landmark.
5. Controls: **WASD** move, **mouse** look, **Space** jump, **Esc** toggle mouse capture.

Main scene: `res://scenes/main/main.tscn`.

## Install Terrain3D (not vendored)

Terrain3D ships platform-specific GDExtension binaries. We **do not** commit them into this repo. Install locally into `addons/terrain_3d/`.

### Option A — Asset Library (recommended)

1. In the editor, open the **AssetLib** tab.
2. Search for **Terrain3D** (author: TokisanGames). Pick the build matching your Godot version.
3. Download → Install (keep `addons/`; `demo/` is optional but useful for smoke tests).
4. **Project → Project Settings → Plugins** → enable **Terrain3D**.
5. Restart the editor if prompted. Open `demo/Demo.tscn` and press **F6** to verify.

### Option B — GitHub release zip

1. Grab a binary release (not source) from https://github.com/TokisanGames/Terrain3D/releases  
   - e.g. `Terrain3D_v1.0.2-stable.zip` for Godot 4.4–4.6+.
2. Copy the release’s `addons/terrain_3d` folder into this project’s `addons/` directory so you have:
   `res://addons/terrain_3d/plugin.cfg`
3. Enable the plugin under **Project Settings → Plugins**.

Docs: https://terrain3d.readthedocs.io/en/stable/docs/installation.html

### After install

- Place a `Terrain3D` node in regional scenes under `scenes/world/regions/` (start with Leinster).
- Keep `addons/terrain_3d/` gitignored (already listed in `.gitignore`) so binaries stay machine-local.

## Folder map (vertical slice)

| Path | Role |
|------|------|
| `scenes/prologue/` | Authored opening sequence |
| `scenes/world/regions/leinster/` | Starting open-world greybox |
| `scenes/world/ringfort/` | Home túath / upgradeable base |
| `scenes/characters/` | Player + NPCs |
| `systems/combat/` | Directional combat (no stamina) |
| `systems/honor/` | Enech reputation (autoload: `Honor`) |
| `systems/factions/` | Faction AI & attitudes (autoload: `Factions`) |
| `systems/timeline/` | Living history / Bannow Bay (autoload: `WorldClock`) |
| `systems/economy/` | Cattle currency |
| `systems/raid/` | Cattle-raid mission loop |
| `systems/rumors/` | Offscreen news (autoload: `Rumors`) |
| `scripts/autoload/` | Global singletons registered in `project.godot` |
| `addons/` | Editor plugins (Terrain3D installed here locally) |

## Optional: C#

Gameplay is **GDScript-first**. Add a .NET Godot build and a `.csproj` only if simulation hotspots need C# later.
