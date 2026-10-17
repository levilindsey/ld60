# Sharing the AI workflow (LX42, LX45)

Ledger: **LX42**, **LX45**. Zaven develops with Claude Code on Windows,
like Levi. Levi's sessions also read his private config repo (user-level
rules, skills, tools). A teammate's Claude reads only this repo, so the
repo must carry what it needs to build and check a feature the way
Levi's agents do.

## What a teammate's Claude is missing today

- A one-command check. Every agent brief spells out the import, the boot
  and the log scan by hand (`m1_agents.md` "Rules for every agent").
- Regression probes. m1-core's input probe is untracked, in an agent
  worktree (`.claude/probes/m1-core/`).
- The ledger convention. `LEDGER.md` points at a file in Levi's private
  repo.
- The gotchas the M1 briefs teach: world Controls eat clicks, import
  after a new `class_name`, headless can't render, a real mouse over a
  windowed probe breaks it (LX44).
- A Godot path that works off Levi's machines. CLAUDE.md says `godot`
  is on the PowerShell PATH.

Not needed: `AGENTS.md` (only other AI tools read it), and Levi's agent
supervision (worktrees, the watcher, merge rounds).

## Stage A: check script, rules, CLAUDE.md

Agent `lx42-workflow` (Sonnet). Owns `scripts/check.ps1` (new),
`.claude/rules/` (new), `README.md`, and in `CLAUDE.md` only the parts
named below. Don't touch `src/`, scenes, `settings.tres`, `LEDGER.md` or
`docs/design/m1_agents.md`. `m1-flow` edits CLAUDE.md's Boot Flow, Core
APIs and Configuration at the same time; stay out of those sections so
the two merge cleanly.

1. **`scripts/check.ps1`**, the one command to run after any change.
   - It runs under Windows PowerShell 5.1 (`powershell.exe`, on every
     Windows machine), so no `??`, ternaries or `&&`. Test it as
     `powershell -ExecutionPolicy Bypass -File scripts/check.ps1`, from
     PowerShell and from Git Bash (Claude Code's Bash tool on Windows).
   - It finds Godot: `-Godot <exe>`, else `$env:GODOT`, else `godot` on
     PATH. With none, it says how to set `$env:GODOT` and exits 2. It
     prints `godot --version` and warns (doesn't fail) if it isn't 4.7.x.
   - It imports (`--headless --path <repo> --import`) unless
     `-SkipImport`. That is needed after a clone, a pull that adds a
     `class_name`, or new assets.
   - It boots (`--headless --path <repo> --quit-after <Frames>
     --log-file build/check/boot.log`), with `-Frames` 1200 by default.
   - Every Godot run uses `Start-Process -PassThru` and waits with a
     timeout (import 300 s, boot 120 s). On timeout it kills only that
     PID, never by name: Levi's editor is usually open.
   - It judges by the log, not Godot's exit code (ObjectDB-leak warnings
     make that non-zero on success). It fails on `SCRIPT ERROR` and
     `ERROR:` lines: it prints each with the line after it and exits 1.
     Otherwise it prints the warning count and `check: OK` and exits 0.
     If a benign line fails a clean boot (a leak report at exit, say),
     allow that one pattern narrowly and say so in the handoff.
   - Prove it both ways: clean on your worktree, then failing on a
     deliberate parse error (revert it after).
   - Reuse what works in m1-core's runner, `run_probe.ps1` (path in your
     prompt).
2. **`.claude/rules/ledger.md`**, path-scoped to `LEDGER.md`: the ledger
   convention for teammates in at most 40 lines, condensed from Levi's
   `~/Repositories/claude-config/rules/ledger.md`. Keep what goes in,
   the sections and their order, the item format and IDs (highest ever
   used plus one, counting `docs/ledger_done.md`), claiming an item in
   In progress (owner, branch and last commit, next step, brief),
   closing into Done with the commit, the union-merge duplicates rule,
   and no secrets. Say that a nightly job on Levi's desktop archives Done
   entries older than a week and commits `LEDGER: nightly upkeep`. Leave
   out his other tools and jobs (`ledger.mjs`, `LEDGERS.md`, the
   transcript audit, session-id owners).
3. **`.claude/rules/gdscript-style.md` (LX45)**: move CLAUDE.md's whole
   "Code Style" section there unchanged, path-scoped to `**/*.gd`,
   `**/*.tscn` and `**/*.tres`. Copy the frontmatter format from a
   path-scoped rule in `~/Repositories/claude-config/rules/`. Leave a
   short "Code Style" section in CLAUDE.md that points at the file and
   says Claude Code loads it when it reads a matching file.
4. **CLAUDE.md**:
   - A new "Working with Claude Code" section before "CLI Tool
     Availability": run `scripts/check.ps1` after every change; the
     gotchas from `m1_agents.md` "Rules for every agent" that apply to
     any session (not Levi's agent coordination); the ledger and its rule
     file; Godot's editor scan skips dot-folders, so `.claude/` never
     shows in the editor or an export.
   - "CLI Tool Availability": scripts find Godot through `$env:GODOT` or
     `godot` on PATH; from Git Bash, call a script as `powershell
     -ExecutionPolicy Bypass -File <script>`. Keep the never-kill-by-name
     rule.
   - Stay under 400 lines, and report the count.
5. **README.md**: a short, beginner-friendly "Check your change" note:
   run `scripts/check.ps1` before pushing, and how to point it at Godot.

Done when `check.ps1` passes clean and fails on the planted error from
both shells, CLAUDE.md has the new section and the pointer, and the two
rule files exist. Commit by pathspec. Append a handoff to this doc.

## Stage B: tracked probes

Agent `lx42-tests` (Sonnet), after `m1-screws` merged (8c8e354). Owns
`tests/` (new), `scripts/check.ps1`, `export_presets.cfg`,
`.claude/rules/tests.md` (new), `README.md`, and in `CLAUDE.md` only
"Working with Claude Code". Don't touch `src/`, scenes, `settings.tres`
or `LEDGER.md`.

The probes are untracked, in the main checkout's `.claude/probes/`:
`m1-core` (the full loop), `m1-flow` (the item flow) and `m1-screws`.
Each is a `probe.gd` and `probe.tscn` with a `run_probe.ps1`, and
`m1-screws/run_all.ps1` runs them all. Headless, they pass 73 (and 6
with m1-core's `-Booklet`), 72 and 64 checks today.

1. **`tests/`**: one folder per probe, named for what it covers rather
   than the agent that wrote it (`tests/full_loop/`, say). Move the
   checks over unchanged except for paths. Probe scripts have no
   `class_name`. Shared helpers (the check and summary functions,
   `_wait_for_landing()`, `_tap_at()`) may move to one base script that
   the probes extend by path. Logs and screenshots go to `build/tests/`
   (git-ignored), never under `tests/`.
2. **`tests/run.ps1`** runs every probe headless (the `-Booklet` run
   too), or one with `-Name`. A probe passes when its `PROBE SUMMARY`
   line shows 0 failed and its log has no `SCRIPT ERROR` or `ERROR:`
   line. One result line per probe, exit 1 on any failure. The rules of
   `check.ps1` hold: Windows PowerShell 5.1, a timeout per run, and kill
   only the PID tree it started. Windowed options (screenshots) stay
   opt-in.
3. **The sweep**: a scene that loads every `.gd`, `.tscn` and `.tres`
   under `res://src/` and reports any that fail, since the import and
   the boot miss errors in scripts nothing loads yet (the stage A
   handoff's "Coverage gap"). `check.ps1` runs it every time, after the
   boot. Report its run time; if it is over 10 s, make it a flag.
4. **`check.ps1 -Tests`** runs `tests/run.ps1` after the sweep. Reuse
   `Invoke-Godot`, `Read-Lines`, `Get-ErrorIndexes`, `Show-Errors` and
   `Fail` (stage A handoff).
5. **Export presets** exclude `tests/*` in both presets'
   `exclude_filter`. Prove it with `--export-pack` into `build/` and a
   search of the pack for `tests/`.
6. **Docs.** CLAUDE.md "Working with Claude Code" gains at most 6
   lines: run `scripts/check.ps1 -Tests` before pushing a gameplay
   change, and add a probe for new behavior. The details go in a new
   `.claude/rules/tests.md` scoped to `tests/**`: how a probe drives the
   game (instantiate `main.tscn`, go to GAME, wait for the item to land
   since items tween in, then `push_input()` in viewport pixels), the
   summary line, no `class_name`, headless by default, and LX44 (keep
   the real mouse still over a windowed run). README "Check your
   change" gets one line on `-Tests`.

Done when `check.ps1` is clean; it fails on a parse error planted in a
new script that nothing loads; `-Tests` runs all three probes green, and
exits 1 on a planted failing check (revert both plants); the exported
pack holds no `tests/` file; CLAUDE.md stays under 400 lines. Run the
final `check.ps1 -Tests` once from Git Bash too. Commit by pathspec on
branch `lx42-tests` and never push. Append a handoff to this doc.

LX38's web clipping probe stays separate: it needs a web export and
Chrome.

## Stage A handoff (lx42-workflow, 2026-10-17)

Stage A is done on branch `lx42-workflow` (worktree
`.claude/worktrees/agent-a8f63ffe7ef1a65fc`, never pushed). It adds
`scripts/check.ps1`, `.claude/rules/ledger.md` (39 lines) and
`.claude/rules/gdscript-style.md` (164 lines, CLAUDE.md's Code Style moved
unchanged), a "Working with Claude Code" section and a rewritten "CLI Tool
Availability" in CLAUDE.md (317 lines, was 411), and a README "Check your
change" section.

Proof with the final script: clean from no `.godot/` (`check: OK`, exit 0,
about 16 s) from Windows PowerShell and from Git Bash; a planted parse error
in `src/core/session.gd` exits 1 by default (import log) and with
`-SkipImport` (boot log); a planted error in `src/core/main.gd` exits 1 from
Git Bash; all reverted. A bad `-Godot`, a bad `$env:GODOT`, `-Frames 0` and
no Godot at all exit 2, a hung run is killed by PID, and a quoted or padded
path works.

- **Allowed in the scan:** nothing (`$AllowedErrorPatterns` is empty). A
  clean import and a clean boot have no `ERROR:` lines and 0 warnings.
- **Coverage gap:** the import and the boot parse only the autoloads, the
  main scene and what they reference, so an error in a script nothing loads
  yet passes. Godot reports a parse error in a `class_name` script as
  "Could not parse global class" with no line number.
- **Timeouts** kill the PID tree (`taskkill /PID <pid> /T /F`): the
  `_console.exe` Godot is a wrapper that starts the real Godot as a child.
- **For Stage B**, `-Tests` fits after the boot step, before the warning
  count. Reuse `Invoke-Godot` (name, arguments, timeout; returns
  `StartError`, `TimedOut`, `ExitCode`, `Seconds`, `ProcessId`,
  `StdoutPath`, `StderrPath`), `Read-Lines`, `Get-ErrorIndexes`,
  `Show-Errors` and `Fail`. A windowed probe is a separate `Invoke-Godot`
  call without `--headless`.
- **Not mine, left for the coordinator:** `LEDGER.md` still says its
  convention is in claude-config; it is now `.claude/rules/ledger.md`.
  CLAUDE.md's Project Structure `scripts/` line does not list `check.ps1`
  or `.claude/rules/`.
- **Harness note:** in a worktree-isolated agent the Bash tool refused every
  `powershell ...` command, so Git Bash was run as `bash.exe -c '...'` from
  the PowerShell tool. Someone should run the Git Bash line once from a
  normal session.

## Stage B handoff (lx42-tests, 2026-10-17)

Stage B is done on branch `lx42-tests` (worktree
`.claude/worktrees/agent-a7be10a80ffc743e1`, never pushed), on top of main's
9bfa18f, which holds Levi's d0f4255 (the driver's twist mode). Five commits,
oldest first: `97ec84e` moves the probes into `tests/` with a shared base,
`38719d7` adds the sweep, `tests/run.ps1` and `check.ps1 -Tests`, `416c15e`
edits the export filters, `117a5d0` writes the docs, and `3f7fed4` is LX51.

- **`tests/`:** `probe_base.gd` (the check, summary, input and screenshot
  helpers) and one folder per probe with a `probe.gd` and `probe.tscn`:
  `full_loop/` (73 checks, plus 6 with `--booklet`), `item_flow/` (72) and
  `screws/` (65). No `class_name`; a probe starts with
  `extends "res://tests/probe_base.gd"`. The checks moved unchanged except
  for paths, and the one LX51 replaced. The `.gd.uid` files are committed.
- **`tests/run.ps1`:** four runs (`full_loop`, `full_loop_booklet`,
  `item_flow`, `screws`), all headless, one `PASS` or `FAIL` line each, then
  `tests: OK (4 run(s), 85.2 s)`. A run passes on a `PROBE SUMMARY` with 0
  failed, no `SCRIPT ERROR` or `ERROR:` line and no `PROBE TIMEOUT`. It runs
  every row even after a failure, exits 1 on a failure and 2 on a setup
  problem, and stops with 2 when a folder has a `probe.tscn` and no row.
  `-Name <run>` runs one, and with `-Screenshots` runs it windowed and saves
  PNGs to `build/tests/<folder>/`.
- **`scripts/godot_helpers.ps1` (new):** the helpers that were in
  `check.ps1` (`Invoke-Godot`, `Read-Lines`, `Get-ErrorIndexes`,
  `Show-Errors`, `Fail`, `Find-Godot`, ...). `check.ps1` and `tests/run.ps1`
  dot-source it after they set `$RepoRoot`, `$LogDirectory` and `$LogPrefix`.
- **The sweep:** `tests/sweep/sweep.tscn` loads every `.gd`, `.tscn` and
  `.tres` under `res://src/` (67 files) and prints `SWEEP FAIL: <path>:
  <reason>` and `SWEEP SUMMARY: <n> loaded, <m> failed`. `check.ps1` runs it
  after the boot every time. **It takes 0.9 s**, so it is not a flag.
- **`check.ps1 -Tests`** runs `tests/run.ps1` after the sweep, and a failed
  run makes `check.ps1` exit 1.
- **Export:** `tests/*` is in both presets' `exclude_filter`.
- **Docs:** CLAUDE.md "Working with Claude Code" (6 lines added, 2 removed;
  the file is 329 lines, main's was 325), `.claude/rules/tests.md`
  (`paths: ["tests/**"]`), and README (the `-Tests` paragraph, plus a
  `tests/` bullet in the layout list, which the brief did not ask for).

Proof, from the worktree (Windows PowerShell 5.1 unless noted):

- `scripts/check.ps1 -Tests`: import 3.5 s, boot 9.9 s, sweep 0.9 s (67
  loaded, 0 failed), full_loop 73, booklet 6, item_flow 72 and screws 64
  checks PASS (before LX51), 85.2 s, 0 warnings, `check: OK`, exit 0. The
  final run, after LX51, was from Git Bash (`bash.exe -c 'powershell
  -ExecutionPolicy Bypass -File scripts/check.ps1 -Tests'`, started from the
  PowerShell tool as in stage A): 73, 6, 72 and 65 checks, `check: OK`,
  exit 0.
- A parse error planted in a new script that nothing loads
  (`src/core/zz_plant.gd`): the import and the boot passed, the sweep printed
  `SCRIPT ERROR: Parse Error: Expected grouping expression.`
  (`zz_plant.gd:5`) and `SWEEP FAIL: res://src/core/zz_plant.gd: does not
  compile`, and `check.ps1` exited 1. Deleted.
- A failing check planted in `tests/item_flow/probe.gd` (`_expect(false,
  "PLANTED failing check")`): `tests: FAIL item_flow: 1 of 73 check(s)
  failed`, `PROBE FAILED: PLANTED failing check`, the other three runs PASS,
  `check: FAIL: the probes failed (see above).`, exit 1. Reverted.
- The packs: `godot --headless --export-pack <preset> build/pack/<x>.pck`
  (no export templates needed, about 5 s each), then a search of the bytes.
  With the old filters (the control): 517 `res://` entries, 14 of them under
  `res://tests/`, 28 raw `tests/` hits, in both the Web and the Windows
  Desktop pack. With `tests/*` excluded: 499 entries, 0 under `res://tests/`,
  0 raw hits, in both. The packs are deleted.
- LX51 (the coordinator's note, after the rebase onto d0f4255): the screws
  check "the driver turns with the head" and its `_drive_rotation_*`
  sampling are replaced by two checks. On every sampled frame while the
  driver is engaged its `%AnimatedSprite2D` plays `twisting` (`0 of 321
  frames did not`), and once it is back in the hand it shows `default`. Every
  other check passes unchanged, "the driver eases back to the hand the short
  way" among them. With a wrong animation name the first check fails on all
  321 frames (`PROBE FAILED: LX51: the driver plays twisting while in use
  (321 of 321 frames did not)`, run exit 1). Reverted.
- One windowed run, `tests/run.ps1 -Name item_flow -Screenshots`: a window
  was open for 20.8 s, the PNGs landed in `build/tests/item_flow/` (deleted
  after), and it printed `PROBE REAL INPUT: blocked 70 motions and 0 buttons
  []`. Real mouse motion arrived and `_RealInputBlocker` dropped it (LX44).

Not done:

- `-Screenshots` ran for `item_flow` only. The windowed `full_loop` run (with
  `--debug-collisions`) and the windowed `screws` run are untried.
- Only `--export-pack` ran, never a full web or Windows export (the export
  templates are per machine), and nothing ran on a machine without
  `$env:GODOT` (`Find-Godot` is the stage A code).
- Feel, sound, a real mouse and a touch screen are still for a person.
- The Git Bash run was `bash.exe -c` from the PowerShell tool again, so the
  stage A request stands: run `check.ps1 -Tests` once from the Bash tool of
  a normal session.
- LX38's web clipping probe stays separate (it needs a web export and
  Chrome).

At merge, for the coordinator (all of it outside my files):

1. When this was written the branch was main's 9bfa18f plus six commits (the
   five above and this handoff), so it fast-forwards. If main moved, rebase
   it: only CLAUDE.md's "Working with Claude Code" could conflict.
2. LEDGER.md: close LX42 (stage B) and LX51 with the merge commit. LX44's
   pointer `.claude/probes/m1-core/` becomes `tests/full_loop/`; the
   real-input blocker is in `tests/probe_base.gd`.
3. Retire the untracked `m1-core`, `m1-flow` and `m1-screws` folders in the
   main checkout's `.claude/probes/`, with their `run_probe.ps1` and
   `run_all.ps1`. They are copies now, and the `m1-screws` one still holds
   the retired "driver turns" check. `.claude/probes/` stays git-ignored for
   other probes; the paths to it in `docs/design/m1_agents.md` are history.
4. CLAUDE.md "Project Structure": add a `tests/` line and put `check.ps1`
   and `godot_helpers.ps1` on the `scripts/` line (stage A flagged the
   `scripts/` line too).
5. Run `scripts/check.ps1 -Tests` on main after the merge.
