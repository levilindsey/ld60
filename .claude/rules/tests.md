---
paths:
  - "tests/**"
---

# Probes: the tests in tests/

A probe boots the real game, plays it with pushed input and prints what
it checked. `scripts/check.ps1 -Tests` runs them all (about 90 s) after
the import, the boot and the `src/` sweep. `tests/run.ps1` runs them
without the check, and `-Name <run>` runs one.

## Layout

- One folder per probe, named for what it covers: `tests/<name>/probe.gd`
  and `probe.tscn`. Shared helpers live in `tests/probe_base.gd`, and a
  probe starts with `extends "res://tests/probe_base.gd"`.
- **No `class_name` in a probe script.** It would join the project's
  global classes. Extend the base by path instead.
- **A new probe needs a row** in the run table of `tests/run.ps1`. The
  script stops when a folder holds a `probe.tscn` without a row, so a
  probe cannot silently never run.
- `tests/sweep/` is not a probe. `check.ps1` runs it to load every script
  and scene under `src/`.
- Godot writes a `.gd.uid` file next to each new script on import. Commit
  it with the script.
- Both export presets exclude `tests/*`, so nothing here ships.

## How a probe drives the game

1. Instantiate `res://src/core/main.tscn` under the probe node. The probe
   scene's root has `process_mode` ALWAYS so the probe can step through
   the pause; set the instance to PAUSABLE so the game pauses as it does
   under the root window. Call `_start_timeout(<seconds>)` first, so a
   hang ends in a `PROBE TIMEOUT` line and not in a stuck run.
2. `G.state.transition(StateMain.State.GAME)`.
3. `await _wait_for_landing()`. Items tween in, and a press before the
   first item lands hits nothing.
4. Send input with the base helpers (`_press_at`, `_tap_at`, `_move_to`,
   `_press_down`, `_release_at`, `_push_mouse`). They call
   `get_viewport().push_input()`. A mouse event's position is in viewport
   pixels and world (0, 0) is (640, 360); `_to_screen()` converts a world
   point. Wait with `_physics_frames(n)` or `_seconds(s)`.
5. Check with `_expect(condition, "label")`. It prints `PROBE PASS:` or
   `PROBE FAIL:` and returns the condition.
6. End with `_finish(0 if _failures.is_empty() else 1)`.

## The summary line

`_finish` prints `PROBE SUMMARY: <n> passed, <m> failed`, then one
`PROBE FAILED: <label>` line for each failed check. A run passes when the
summary shows at least one check and 0 failed, the log has no
`SCRIPT ERROR` or `ERROR:` line, and there is no `PROBE TIMEOUT` line.
`run.ps1` judges by the log, not by Godot's exit code, which is non-zero
on some good runs. A probe's own exit codes are 0 (passed), 1 (a check
failed) and 2 (timeout).

## Headless by default

- `run.ps1` runs every probe with `--headless`: no window, and no
  rendering. Logs go to `build/tests/<run>.log`, and screenshots to
  `build/tests/<folder>/` (both git-ignored).
- `run.ps1 -Name <run> -Screenshots` runs one probe windowed and saves
  PNGs. It opens a window on the developer's screen, so keep those runs
  few and short.
- **Keep the real mouse still over a windowed run (LX44).** A real mouse
  event is suspected of breaking one. A probe with `_RealInputBlocker`
  drops real mouse events and counts them in a `PROBE REAL INPUT:` line.
- Anything that needs a real mouse, a touch screen or ears (feel, sound,
  a drag on a phone) is left to a person. Say so in the report.
