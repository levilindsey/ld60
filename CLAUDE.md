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
  and items, tool holders, set-aside spot, win flow), `hand.gd`,
  `tool_holder.gd`, `camera_shaker.gd`, `zaven_demo/` (booklet demo).
- `src/tools/` - `tool.gd` (Tool base), plus a script and scene per tool.
- `src/repairables/` - `repairable.gd`, `repair_layer.gd`,
  `surface.gd`, plus a script and scene per item.
- `src/interaction_points/` - `interaction_point.gd`, `screw.gd`
  (`Screw`), `part_socket.gd`, plus a script and scene per point.
- `src/parts/` - `part.gd` (drawer parts the hand holds like tools),
  `wiggle.gd` (shared swing counter).
- `src/manual/` - Zaven's page-turning `InstructionManual`.
- `src/props/` - `LiftableProp` (rests flat on the desk in perspective,
  lifts into view when tapped; base of `InstructionManual` and
  `TicketCard`) and the shared `PropCloseButton`.
- `src/ui/hud/` - `hud.gd`/`hud.tscn`: title/pause/credits overlays.
- `src/ui/super_hud/` - Top-level HUD host with `debug_console`.
- `assets/` - `fonts/` (Special Elite for menus and printed paper,
  Reenie Beanie for handwriting), `images/` (tool art, `props/` background + Krita source, `gui/`
  buttons, `placeholders/`), `shaders/sprite_outline.gdshader`.
- `docs/design/` - One design doc per piece of work.
- `scripts/` - `check.ps1` (run after every change), `godot_helpers.ps1`
  (shared by `check.ps1` and `tests/run.ps1`), `export_web.ps1`,
  `serve_web.py`. `build/` holds export and check outputs (gitignored).
- `tests/` - Headless probes that play the game (`run.ps1`,
  `probe_base.gd`, one folder per probe) and the `sweep/` that loads
  every file under `src/`. Excluded from exports.
- `.claude/rules/` - Path-scoped Claude Code rules: the GDScript style
  guide, the ledger convention and how to write tests.

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
6. `Level._ready` centers the camera anchor, spawns the flathead
   driver, then the items of `settings.item_queue` one at a time
   (arrive, ticket, repair, outbox, receipt: `docs/design/outbox.md`).

**Running a level directly** (F6 / "Run Current Scene"): `Level`
sees no `G.main`, frees its children before they enter the tree,
skips its own setup, and calls
`G.boot_from_level()`. That records the level's path in
`G.level_scene_override_path` and swaps to `main.tscn`, which boots
normally but skips TITLE and loads that level instead of
`settings.default_level_scene`. No `settings.tres` edits needed.

State machine (`StateMain.State`): `TITLE`, `GAME`, `PAUSE`,
`CREDITS`. Non-GAME states pause the SceneTree. `StateMain` runs
with `process_mode = ALWAYS` and handles the `pause` action plus
jump/ability on the TITLE screen. `CREDITS` is terminal: no
transition leaves it, so a run cannot start again in the same
session. `transition()` branches are deliberately idempotent;
there is no same-state early return.

Game flow helpers: `G.level.win()` -> the credits card floats
down (the CREDITS state is terminal; the HUD overlay is unused);
`G.game_panel.restart_level()` -> a fresh Level instance.

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
- **Camera and decals:** `G.level.shake_camera(amplitude_px, duration_sec)`
  shakes the camera. `G.level.spawn_decal(...)` stamps a decal on a
  part, and `Repairable.quality` scores the repair for the receipt.
- **Hand** (`G.level.hand`, `docs/design/tools.md` "The hand"): one
  `_unhandled_input` routes every left press, holds one thing and
  owns the cursor. A microgame calls `set_input_owner(self)` to get
  the presses. A point's `engage(tool)` places the tool until
  `finish()`. The item emits `landed`, `layer_removed`,
  `layer_installed`, `point_finished`, `finished` and `departed`.
- **Screws** (`Screw`, `docs/design/screws.md`): `take_damage()`,
  `unseize()`, `remove()`, `install()`, and the signals `damaged`,
  `stripped`, `removed` and `installed`. `FlatHeadScrew` runs the
  twist cycle (`docs/design/flathead.md`), timed by the "Flathead"
  group in `settings.gd`.
- **Dev hotkeys** (`settings.dev_mode`): `P` screenshot (to
  `user://screenshots/`), `O` toggle HUD, `C` complete the item on the
  bench, `R` toggle the radio glitch, `N` swap the item on the bench for the
  next one in `item_queue`, `M` mute the music (remembered in
  `user://dev.cfg`). `Esc` pauses in any mode.

## Configuration

- `settings.tres` - Runtime settings resource (`Settings` script).
  Key fields: `default_level_scene`, `start_in_game`, `dev_mode`,
  `show_debug_console`, `mute_music`, `full_screen`,
  `pauses_on_focus_out`, `item_queue` (the day's items), the timing
  groups ("Hand", "Layers", "Item flow"), and one scene per tool and
  item (`get_tool_scene_from_type`, `get_repairable_scene_from_type`).
- `default_bus_layout.tres` - Audio buses (Master/Music/SFX).
- `project.godot` - Input actions, physics layers, rendering.
- Renderer: `gl_compatibility`; linear texture filtering (Godot
  default; the art is hand-drawn, not pixel art); `canvas_items`
  stretch at 1280x720 with aspect `keep` (scales to fit the window,
  black bars on the sides or top/bottom); physics interpolation on.

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
6. `surfaces`
7. `parts`

`Settings.PhysicsLayer` mirrors these as bit flags; keep the two in
sync.

## UI

The game is designed for **mouse and touch screen** input first.
Interactions are click/tap driven; keyboard and gamepad support is
not a requirement. Touch arrives as emulated mouse events, so handle
`InputEventMouseButton` (left button) for clicks and taps. Shared
button art lives in `assets/images/gui/`
and is wired into `src/core/main_theme.tres` (Special Elite font +
textured buttons). `src/ui/super_hud/` hosts the `debug_console` overlay on
a CanvasLayer above the in-game HUD.

## Web + Windows Builds

```powershell
# Export web build + zip for itch.io upload.
powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1

# Serve build/web/ locally on port 8060.
python scripts/serve_web.py

# Windows export.
godot --headless --export-release "Windows Desktop" build/windows/loose-screw.exe
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

The GDScript style rules (formatting, naming, type annotations, file
structure, scene templates over scripts) live in
`.claude/rules/gdscript-style.md`. Claude Code loads that file by itself
when it reads, edits or writes a `.gd`, `.tscn` or `.tres` file, so it
is not repeated here. Anyone writing code by hand should read it first.

## Working with Claude Code

Levi and Zaven both build this game with Claude Code on Windows. The repo
carries what Claude needs to check its own work.

- **Run `scripts/check.ps1` after every change**, before you commit or
  push. It finds Godot (see "CLI Tool Availability"), imports the
  project, boots it headless for 1200 frames and reads Godot's log. A
  `SCRIPT ERROR` or `ERROR:` line fails it (exit 1); each is printed with
  the `at:` line after it (a file and line). For a parse error in a
  `class_name` script, Godot names the file ("Could not parse global
  class") but not the faulty line, so open that file. The script ignores
  Godot's exit code, which is non-zero on some good runs. `-SkipImport`
  skips the import, `-Frames <n>` changes the boot length and
  `-Godot <exe>` picks the Godot. The logs are in `build/check/`
  (git-ignored). A sweep then loads every `.gd`, `.tscn` and `.tres` under
  `src/`, so a parse error in a script nothing loads yet fails it too.
- **Before pushing a gameplay change, run `scripts/check.ps1 -Tests`.**
  It adds the probes in `tests/` (about 90 s): each plays the game
  headless with pushed input and fails on a broken check. Add a probe for
  new behavior; `.claude/rules/tests.md` says how (it loads on `tests/`).
- **A fresh clone or worktree has no `.godot/` cache.** Import before
  anything else (`check.ps1` does), and again after adding or renaming a
  `class_name`; until then Godot reports the new class as unknown.
- **World `Control` nodes eat clicks.** A `ColorRect` placeholder in the
  world takes mouse presses before `_unhandled_input` and physics
  picking see them. Set `mouse_filter` to Ignore on every world Control,
  or use a `Polygon2D` instead.
- **Headless can't render.** For a visual check, run windowed with
  `--quit-after <frames>` and save
  `get_viewport().get_texture().get_image()` to a file. Keep those runs
  few and short: they open a window on the developer's screen.
- **A scripted input test drives the game, not the mouse.** Instantiate
  `res://src/core/main.tscn`, call
  `G.state.transition(StateMain.State.GAME)`, then send events with
  `get_viewport().push_input()`. A mouse event's `position` is in
  viewport pixels, and world (0, 0) is (640, 360). Keep the real mouse
  still during a windowed run: it is suspected of breaking one (LX44).
- **Say what you could not check.** Anything that needs a real mouse, a
  touch screen or ears (feel, sound, a drag on a phone) is left to a
  person. List it in your report instead of calling it verified.
- **Shared files.** `src/core/settings.gd` and `settings.tres` change in
  almost every feature. Put new exports in your own `@export_group` and
  add only your own lines to `settings.tres`, so branches merge cleanly.
- **The ledger.** `LEDGER.md` is the list of open work and who is on it.
  Claim an item in "In progress" before starting it, and move it to
  "Done" in the commit that finishes it. The convention is in
  `.claude/rules/ledger.md`, which Claude Code loads when it reads
  `LEDGER.md`.
- **`.claude/` is invisible to Godot.** The editor scan skips folders
  that start with a dot, so `.claude/` (these rules, plus the git-ignored
  `.claude/probes/` and `.claude/worktrees/`) never shows in the editor
  or an export.

## CLI Tool Availability

Scripts find Godot through the `GODOT` environment variable (the path to
a Godot 4.7 `.exe`), or else through `godot` on the PATH. Set it once
with `setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"` and
open a new terminal. `scripts/check.ps1 -Godot <exe>` overrides both. If
Godot is not found, the script says how to set it and exits 2.

Run Godot and the scripts from **PowerShell**. `godot` is not reliably
on the bash PATH, so **never run `godot` directly from bash.** From Git
Bash (Claude Code's Bash tool on Windows), call a script as
`powershell -ExecutionPolicy Bypass -File <script>`, or run a command
with `powershell -Command "<command>"`.

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
