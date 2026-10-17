# ld60 ledger

Open work for ld60 (the Ludum Dare 60 game): follow-ups, known
residuals, decisions waiting on Levi, and ideas. Convention:
claude-config `rules/ledger.md`. IDs (`LX<n>`) are stable and never
reused.

## Waiting on Levi

- **LX6** · Confirm the defaults in `docs/design/overview.md` "Open
  decisions": shop theme, jam item cut, parts bin placement, flathead
  unseat rule, sensitive-surface warning.

## In progress

<!-- Each item is a resume handle: owner, branch + last commit, evidence,
next, brief, env (claude-config rules/ledger.md). -->

- **LX7** · The hand owns the held thing and cursor; touch-first press
  routing, wrong-tool nope, holders by `Tool.Type`; folds in LX1 to LX5
  and a real-mouse test of 929db18 (`docs/design/tools.md`).
  - owner: claude agent `m1-core` (Opus) of session 194d3b69 (Levi),
    since 2026-10-17
  - branch: `m1-core`, in an agent worktree under `.claude/worktrees/`;
    last commit: none yet (base: the M1 claim on `main`)
  - evidence: `.claude/probes/m1-core/` in that worktree
  - next: build and check per the brief
  - brief: `docs/design/m1_agents.md` "m1-core"
- **LX8** · Repair layers: `RepairLayer`, point roles, lift-off,
  reassembly, `Surface`, finishing (`docs/design/repairables.md`).
  - owner, branch, evidence, next, brief: as LX7 (agent `m1-core`)
- **LX12** · Quality score, stars and receipt (`docs/design/quality.md`).
  - owner: claude agent `m1-quality` (Sonnet) of session 194d3b69
    (Levi), since 2026-10-17
  - branch: `m1-quality`, in an agent worktree under
    `.claude/worktrees/`; last commit: none yet
  - evidence: `.claude/probes/m1-quality/` in that worktree
  - next: build and check per the brief
  - brief: `docs/design/m1_agents.md` "m1-quality"
- **LX13** · Decal spawner; first check `clip_children` in a web export
  (`docs/design/decals.md`).
  - owner: claude agent `m1-decals` (Sonnet) of session 194d3b69
    (Levi), since 2026-10-17
  - branch: `m1-decals`, in an agent worktree under
    `.claude/worktrees/`; last commit: none yet
  - evidence: `.claude/probes/m1-decals/` in that worktree
  - next: the web clipping check, then the spawner
  - brief: `docs/design/m1_agents.md` "m1-decals"
- **LX9** · Item flow: arrival tween, finished-only drag, outbox area,
  item queue (`docs/design/outbox.md`).
  - owner: claude session 194d3b69 (Levi), queued for stage 2 (agent
    `m1-flow`)
  - branch: none yet; last commit: none
  - evidence: none yet
  - next: launch `m1-flow` once stage 1 is on `main`
  - brief: `docs/design/m1_agents.md` "m1-flow" (written at that merge)
- **LX10** · Screw health: damage frames, stripped, seized, install mode
  (`docs/design/screws.md`).
  - owner: claude session 194d3b69 (Levi), queued for stage 2 (agent
    `m1-screws`, with LX11)
  - branch: none yet; last commit: none
  - evidence: none yet
  - next: launch `m1-screws` once stage 1 is on `main`
  - brief: `docs/design/m1_agents.md` "m1-screws" (written at that
    merge)
- **LX11** · Flathead rework: 1 s eased twists, eased drift (at most 0.6
  of the tolerance per twist), correction along the slot, unseat
  (`docs/design/flathead.md`).
  - owner, branch, evidence, next, brief: as LX10 (agent `m1-screws`)

## Next

- **LX1** · Tool collision shapes aren't scaled to the 0.2 visual (grab
  area 5x the tool, put-away drop off-screen); part of LX7
  (`src/tools/flat_head_screw_driver.tscn`, `docs/ledger_notes.md`).
- **LX5** · Pick-up teleports the tool under the cursor: ease a follow
  offset to zero, also after IN_USE exits and hammer recoil (TODO in
  `src/tools/tool.gd`; `docs/design/tools.md` "Follow offset").
- **LX14** · Canned air: spray cone, dust clumps, fans
  (`docs/design/canned_air.md`).
- **LX15** · Parts bin and part swap: hotspots, sockets, wiggle-out
  (`docs/design/parts_bin.md`).
- **LX16** · First item end to end: the virtual pet egg
  (`docs/design/items.md`).
- **LX17** · Phillips pressure gauge (`docs/design/phillips.md`).
- **LX18** · Hammer: wind-up ring, strength bands, jog, realign, reseat
  (`docs/design/hammer.md`).
- **LX19** · Pliers for stripped screws (`docs/design/pliers.md`).
- **LX20** · Rag and solvent, sensitive surfaces
  (`docs/design/solvent.md`).
- **LX21** · Oil can: drops, pivots, squeaks, misuse
  (`docs/design/oil_can.md`).
- **LX22** · Glue along cracks and clips (`docs/design/glue.md`).
- **LX23** · Items 2 to 5: rotary phone, Walkman, CRT TV, ray gun
  (`docs/design/items.md` "The jam cut").
- **LX24** · Art: screw states, decals, part states, effects, UI
  (`docs/design/decals.md` "The art list").
- **LX25** · Sounds: collect each design doc's "Feedback" list and add
  the streams to `src/core/audio_main.tscn`.
- **LX26** · Web export and itch.io upload (`scripts/export_web.ps1`).

## Residuals (known, not fixed)

- **LX2** · Cursor shape and mouse mode are global but set per tool, and
  never reset when a held tool is freed; fix: the hand in LX7
  (`src/tools/tool.gd` `_update_cursor`, `docs/ledger_notes.md`).
- **LX3** · Any mouse button, including the wheel, picks a tool up:
  `_on_grab_area_input_event` has no MOUSE_BUTTON_LEFT check. Pointer:
  `src/tools/tool.gd`. Fix: LX7's press routing.
- **LX4** · `Tool._set_mode` (STORED) takes `holder_area_offset` from the
  HolderArea node (always zero), not its shape offset (0,-600), so the
  tool origin lines up with the holder (`src/tools/tool.gd`). Part of LX7.
- **LX27** · Source art is huge (3508x2480 PNGs, 0.6 to 2.2 MB each, drawn
  at about 0.2 scale): downscale it or cap the import size before the
  web build (`assets/images/`).

## Ideas (not scheduled)

- **LX28** · Instruction booklet with missing and unclear pages; Zaven
  will probably own it (`docs/design/booklet.md`).
- **LX29** · Tweezers (`docs/design/stretch_tools.md`).
- **LX30** · Soldering iron (`docs/design/stretch_tools.md`).
- **LX31** · Belt replacement with a stretchy belt
  (`docs/design/parts_bin.md` "Stretch: belts").
- **LX32** · Part orientation (polarity) (`docs/design/parts_bin.md`).
- **LX33** · Test switch: run the item any time to see its symptoms
  (`docs/design/repairables.md` "Later").
- **LX34** · More depth: workday queue, screw map, hidden second fault,
  donor junk, tool upgrades, shop cat, stories inside items
  (`docs/design/overview.md` "Depth").
- **LX35** · Items beyond the jam cut, up to atompunk and a finale
  (`docs/design/items.md` "More items").

## Done
