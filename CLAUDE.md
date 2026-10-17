# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LD60 is a single-player 2D game for the Ludum Dare 60 game jam,
built with **Godot 4.7.2-stable**. The theme is "old tech": a repair
shop where broken gadgets arrive on the bench, each tool is a small
microgame, and each repair earns 1 to 3 stars. The design is in
`docs/design/` (start at `overview.md`). **No GDExtensions and no
networking** (see "Deliberately omitted" below).

The skeleton was extracted 2026-10-05 from the `ld59` repo (core
autoloads, scaffolder utilities, HUD/debug-console shells, web
tooling) with conventions from `hopnbop` (thread-less web preset,
physics interpolation). Both live as workspace siblings under
`~/Repositories/`.

**Team note:** Levi is joined this jam by a teammate who is new to
Godot and git. Keep `README.md` beginner-friendly, prefer simple
explicit code over clever code, and don't assume the reader knows
the codebase history.

## Claude Code Settings

Do NOT use the local memory system (`~/.claude/projects/*/memory/`).
This project is worked on across multiple machines. All persistent
context belongs in this file so it stays in sync via git.

## Status

The jam is on. `PLAN.md` has the build order (M1 to M4) and the
team's working rules. `LEDGER.md` has the open work and who is on
it; each item points at its design doc. Claim an item in "In
progress" before starting it, and move it to "Done" in the commit
that finishes it.

## Commit Policy

- All work lands directly on `main`. No feature branches, no PRs.
  Ignore harness-generated `claude/<slug>` branch names; only an
  explicit request from Levi justifies a non-main branch.
- Do not commit partial or broken work. All changes for a feature
  must be working end-to-end before committing.
- Commit and push to `main` at natural stopping points without
  asking, once work is verified.
- Force-push still needs explicit confirmation.
- Teammates often have uncommitted work in the tree. Commit only
  your files, by pathspec; never stash, reset or check out theirs.

## Project Structure

- `src/core/` - App spine: `global.gd` (the `G` autoload), entry
  scene (`main.tscn`/`main.gd`), `state_main` (state machine),
  `game_panel` (level lifecycle), `audio_main` (music/SFX),
  `session`, `settings.gd`, `main_theme.tres`.
- `src/scaffolder/` - Reusable framework: `scaffolder.gd` (boot
  validation), `scaffolder_log.gd`, `geometry.gd`, `draw_utils.gd`,
  `utils.gd`, `time/` (ScaffolderTime + tween/timer primitives).
- `src/level/` - `level.gd`/`level.tscn` (the bench: spawns tools
  and items, tool holders, win flow), `tool_holder.gd`,
  `camera_shaker.gd`, `zaven_demo/` (the booklet demo level).
- `src/tools/` - `tool.gd` (Tool base), plus a script and scene per tool.
- `src/repairables/` - `repairable.gd`, plus a script and scene per item.
- `src/interaction_points/` - `interaction_point.gd`, plus the
  points tools act on (`flat_head_screw.gd` declares `Screw`).
- `src/manual/` - Zaven's page-turning `InstructionManual`.
- `src/ui/hud/` - `hud.gd`/`hud.tscn`: title/pause/credits overlays.
- `src/ui/super_hud/` - Top-level HUD host with `debug_console`.
- `assets/` - `fonts/pxlzr/` (Levi's own SIL-OFL pixel font),
  `images/` (tool art, `props/` background + Krita source, `gui/`
  buttons, `placeholders/`), `shaders/sprite_outline.gdshader`.
- `docs/design/` - One design doc per piece of work.
- `scripts/` - `export_web.ps1`, `serve_web.py`. `build/` holds
  export outputs (gitignored).

## Boot Flow

1. Autoload `G` loads; it creates `time`/`log`/`utils`/`geometry`
   children and exposes typed slots for the other systems.
2. `main.tscn` (the main scene) instantiates. `Main._enter_tree`
   assigns `G.main`/`G.settings`, wires log filtering from
   `settings.tres`, and runs `Scaffolder.set_up()` (validates the
   input map).
3. Children self-register in their own `_enter_tree`: `StateMain`
   (`G.state`), `AudioMain` (`G.audio`), `GamePanel`
   (`G.game_panel`, creates `G.session`), `Hud` (`G.hud`).
4. `Main._ready` pauses the tree, positions the window
   (editor-only), then calls `G.state.start_game()`.
5. `StateMain.transition(GAME)` (or `TITLE` when
   `settings.start_in_game` is false) -> `GamePanel.start_game()`
   -> instantiates `settings.default_level_scene`.
6. `Level._ready` centers the camera anchor, then spawns the
   flathead driver and the test repairable (hard-coded until LX9's
   item queue).

**Running a level directly** (F6 / "Run Current Scene"): `Level`
sees no `G.main`, skips its own setup, and calls
`G.boot_from_level()`. That records the level's path in
`G.level_scene_override_path` and swaps to `main.tscn`, which boots
normally but skips TITLE and loads that level instead of
`settings.default_level_scene`. No `settings.tres` edits needed.

State machine (`StateMain.State`): `TITLE`, `GAME`, `PAUSE`,
`CREDITS`. Non-GAME states pause the SceneTree. `StateMain` runs
with `process_mode = ALWAYS` and handles the `pause` action plus
jump/ability on the TITLE/CREDITS screens. `transition()` branches
are deliberately idempotent; there is no same-state early return.

Game flow helpers: `G.level.win()` -> CREDITS overlay (jump/ability
restarts); `G.game_panel.restart_level()` -> a fresh Level instance.

## Core APIs Worth Knowing

- **Logging:** `G.print/verbose/warning/error/fatal` with categories
  (`ScaffolderLog.CATEGORY_*`); `G.ensure(cond, msg)` /
  `G.check(cond, msg)`. Category filtering + verbosity come from
  `settings.tres` and are wired in `Main._enter_tree`. The debug
  console (`settings.show_debug_console`) mirrors the log stream
  in-game.
- **Time:** `G.time.set_timeout/clear_timeout`,
  `set_interval/clear_interval`, `throttle`, `debounce`,
  `tween_method/tween_property`, scaled time. Prefer these over ad
  hoc `Timer` nodes.
- **Audio:** `G.audio.play_sound(name)`, `stop_sound`,
  `play_sound_delayed`, and theme crossfades
  (`fade_to_menu_theme/fade_to_main_theme/fade_to_end_theme`,
  `fade_to_end_theme_after(delay)`). The stream players in
  `audio_main.tscn` ship **without streams**; assign `.wav`s there
  and extend `STREAM_PLAYERS_BY_NAME` as audio lands. Buses:
  `Master`, `Music`, `SFX`.
- **Camera:** `shake_camera(amplitude_px, duration_sec)` on the
  level's `CameraShaker` node (LX9 adds a `G.level` pass-through).
- **Dev hotkeys** (`settings.dev_mode`): `P` screenshot (to
  `user://screenshots/`), `O` toggle HUD, `Esc` pause.

## Configuration

- `settings.tres` - Runtime settings resource (`Settings` script).
  Key fields: `default_level_scene`, `start_in_game`, `dev_mode`,
  `show_debug_console`, `mute_music`, `full_screen`,
  `pauses_on_focus_out`, plus one scene per tool and item in the
  "Tools" and "Repairables" groups (`get_tool_scene_from_type`,
  `get_repairable_scene_from_type`).
- `default_bus_layout.tres` - Audio buses (Master/Music/SFX).
- `project.godot` - Input actions, physics layers, rendering.
- Renderer: `gl_compatibility`; linear texture filtering (Godot
  default; the art is hand-drawn, not pixel art); `canvas_items`
  stretch at 1280x720; physics interpolation on.

### Input Actions

Defined in `project.godot`: `move_up`, `move_down`, `move_left`,
`move_right` (WASD + arrows + sticks + D-pad), `jump` (Z/W/Up +
gamepad A), `ability` (Space/LMB + gamepad B), `pause` (Esc +
Start). `Scaffolder.set_up()` fails loudly at boot if one goes
missing. Add new actions there too.

### Physics Layers

1. `tools`
2. `repairables`
3. `interaction_points`
4. `table`
5. `tool_holders`

`Settings.PhysicsLayer` mirrors these as bit flags; keep the two in
sync.

## UI

The game is designed for **mouse and touch screen** input first.
Interactions are click/tap driven; keyboard and gamepad support is
not a requirement. Touch arrives as emulated mouse events, so handle
`InputEventMouseButton` (left button) for clicks and taps. Shared
button art lives in `assets/images/gui/`
and is wired into `src/core/main_theme.tres` (pxlzr font + textured
buttons). `src/ui/super_hud/` hosts the `debug_console` overlay on
a CanvasLayer above the in-game HUD.

## Web + Windows Builds

```powershell
# Export web build + zip for itch.io upload.
powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1

# Serve build/web/ locally on port 8060.
python scripts/serve_web.py

# Windows export.
godot --headless --export-release "Windows Desktop" build/windows/ld60.exe
```

The Web preset has `thread_support=false` and
`extensions_support=false`, so the build runs from **any plain
static host**. No COOP/COEP headers or SharedArrayBuffer are
required (serve_web.py still sends the headers; they're harmless).
On itch.io, do NOT check "SharedArrayBuffer support". If threads
ever get re-enabled, revisit this (see ld59's web/ directory for
the full COOP/COEP + Safari-fallback apparatus).

Godot's headless export can return non-zero even on success
(ObjectDB-leak warnings); `export_web.ps1` treats the presence of
`build/web/index.html` as the source of truth.

Versioning: `config/version` in `project.godot` is display-only
(shows in the boot log banner). Bump it freely on uploads; nothing
enforces it.

## Deliberately Omitted (and where to get it)

| Need | Source |
|---|---|
| GUT tests + CI workflow | `ld59:addons/gut/` + `ld59:.github/workflows/test.yml` (bump its Godot version) |
| Persisted user settings (ConfigFile in `user://`) | `hopnbop:src/core/local_settings.gd` (strip the Netcode logging) |
| Screen-transition shader wipes | `hopnbop:src/ui/screen_transition.gd` + `hopnbop:assets/shaders/` (strip the `Netcode.is_server` guard) |
| Pixel-perfect integer-scale viewport | `hopnbop:addons/snoringcat_platform_client/util/pixel_viewport_manager.gd` (pre-decoupled) |
| Toast / confirm-dialog overlays | `hopnbop:addons/snoringcat_platform_client/ui/overlays/` and `hopnbop:src/ui/confirm_overlay/` |
| i18n CSV pipeline | `hopnbop:translations/` + its `project.godot` locale block |
| Procedural level generation | `ld59:src/level/procgen/` (tied to ld59's tile pipeline; adapt) |

When pulling any of these in, re-read the source repo's CLAUDE.md
section about it first.

## Code Style

Follow the
[Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
with the project-specific additions below.

### Formatting

- **Indentation:** Tabs (4-space width).
- **Line length:** 80 characters maximum.
- **Blank lines:** Two blank lines between functions/methods.
- **Line wrapping:** Prefer parentheses over backslashes for
  line continuation. Conversely, unwrap lines onto a single
  line when they fit within the 80-character limit.
- **Operator placement:** When wrapping expressions across
  multiple lines, place operators at the start of the next
  line, not the end of the previous line.
- **Trailing commas:** Include trailing commas in multi-line
  function calls, arrays, and dictionaries.

```gdscript
# Correct: parens for wrapping, operator at start of line.
var is_valid := (
	is_instance_valid(node)
	and node.is_inside_tree()
	and not node.is_queued_for_deletion()
)

# Correct: trailing comma in multi-line call.
some_function(
	first_arg,
	second_arg,
)

# Wrong: backslash continuation.
var is_valid := is_instance_valid(node) \
	and node.is_inside_tree()

# Wrong: operator at end of line.
var is_valid := (
	is_instance_valid(node) and
	node.is_inside_tree()
)
```

### Naming Conventions

- **Classes/enums:** `PascalCase`
- **Functions/variables:** `snake_case`
- **Constants:** `UPPER_SNAKE_CASE`
- **Private members:** Prefix with underscore (`_my_var`,
  `_my_method`)
- **Signals:** Past tense (`player_died`, `match_started`)
- **Booleans:** Prefix with `is_`, `can_`, `has_`
- **No prefixes:** Avoid prefixes in variable names (e.g., use
  `speed` not `player_speed` when already inside a player
  class). The underscore prefix for private members is the
  exception.
- **No abbreviations:** Use full words in identifiers (e.g.,
  `diagnostic` not `diag`, `configuration` not `config`,
  `information` not `info`). Standard domain abbreviations
  (`fps`, `rpc`, `usec`, `id`) are acceptable.

### Type Annotations

- Use `:=` for inferred types on variable declarations.
- Always specify return types on functions.
- Use explicit type hints for `@export` vars and function
  parameters.

```gdscript
var speed := 10.0
const _MAX_SPEED := 200.0
@export var jump_height: float = 64.0

func get_speed() -> float:
	return speed
```

### Negation

- Prefer `not` over `!` for boolean negation.
- Do use `!=` for inequality comparisons.

### Comments and Prose

- End all comments with a period.
- Use `##` for doc comments (Godot documentation comments),
  `#` for regular comments.
- Never use em dashes, en dashes, or hyphens as grammatical
  em dashes. Use a period and start a new sentence instead.
- Wrap comments at 80 characters, matching the code line
  limit.

### File Structure

Follow the Godot-recommended ordering within each script:

1. `@tool`
2. `class_name`
3. `extends`
4. Doc comment (`##`)
5. `signal` declarations
6. `enum` declarations
7. `const` declarations
8. `@export` variables
9. Public variables
10. Private variables (`_`-prefixed)
11. `@onready` variables
12. `_init()`, `_enter_tree()`, `_exit_tree()`, `_ready()`
13. `_process()`, `_physics_process()`
14. Other virtual/callback methods
15. Public methods
16. Private methods

### Constants Over Inline Values

Use file-level `const` declarations instead of hard-coding
static values inline in functions. Private constants use
underscore prefix.

### Scene Templates Over Scripts

Prefer configuring state in `.tscn` scene files rather than
in scripts:

- **Animations:** Configure `AnimatedSprite2D.sprite_frames`
  animations in the scene editor, not in code.
- **Resource references:** Use `@export` vars and assign
  resources in the scene inspector. NEVER use `preload()` or
  `load()` for resource references in scripts.
- **Node references:** Use `%NodeName` unique-name syntax in
  scenes when referencing sibling/child nodes.

**Editing `.tscn` files directly (without the Godot editor):**
Scene files can be edited as text. The key fields are:
- `load_steps=N` in the header. Increment N for each new
  `[ext_resource]` entry added.
- `[ext_resource type="PackedScene" path="res://..." id="X"]`
  declares a scene dependency. Use a unique `id` string.
  `uid=` is optional; omit it if the scene has no UID yet.
- `[node name="Foo" parent="." instance=ExtResource("X")]`
  instantiates the scene as a child node.
- Export vars on an instanced node are set directly on the
  node entry. Enum values are integers matching declaration
  order.

### Direct Access Over Local Copies

Do not assign local or class-level variable copies of
autoload properties (`G`) or unique-name nodes (`%`). Access
them directly where needed.

### Performance

- Prefer `distance_squared_to()` over `distance_to()` when
  feasible, to avoid unnecessary `sqrt` calculations.

## CLI Tool Availability

`godot` and other Godot tooling are only in the PowerShell
PATH, not the bash PATH. **Never run `godot` directly from
bash.** Always use `powershell -ExecutionPolicy Bypass -File
<script>` or `powershell -Command "<command>"` when invoking
it.

**Never kill Godot processes by name or wildcard** (e.g.
`Stop-Process -Name godot*`). The developer usually has the editor
open, and killing it loses unsaved work. To stop a hung headless run,
kill only the specific PID you launched.

## Engine Version

Target: **Godot 4.7.2-stable** (`config/features` declares 4.7; any
4.7.x works for development). Exports need the matching export
templates installed per machine
(`%APPDATA%\Godot\export_templates\<version>\`). No GDExtensions,
no submodules, no native builds.
