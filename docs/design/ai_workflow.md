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

## Stage B: tracked probes (after `m1-screws` merges)

Both stage 2 agents change m1-core's probe in their worktrees, so the
probes move into the repo once both have merged:
- `tests/` with the m1-core probe (merged with both agents' edits) and
  the m1-flow and m1-screws probes, `tests/run.ps1`, and
  `check.ps1 -Tests`.
- The export presets exclude `tests/*`. Probe scripts have no
  `class_name`.
- CLAUDE.md: how to write and run a probe.
- A sweep that loads every `.gd` and `.tscn` under `src/`, since import
  and boot miss errors in scripts nothing loads yet (the stage A
  handoff's "Coverage gap").
- Items tween in, so a probe waits for the item to land (m1-core's
  `_wait_for_landing`) before it presses on it.

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
