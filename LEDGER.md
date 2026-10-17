# ld60 ledger

Open work for ld60 (the Ludum Dare 60 game): follow-ups, known
residuals, decisions waiting on Levi, and ideas. Convention:
claude-config `rules/ledger.md`. IDs (`LX<n>`) are stable and never
reused.

## Waiting on Levi

## In progress

<!-- Each item is a resume handle: owner, branch + last commit, evidence,
next, brief, env (claude-config rules/ledger.md). -->

- **LX42** · Share the AI workflow for Zaven (Claude Code on Windows): a
  check script, a ledger rule, the gotchas in CLAUDE.md (stage A), then
  tracked probes in `tests/` (stage B, after m1-screws merges).
  - owner: claude agent `lx42-workflow` (Sonnet) of session 194d3b69
    (Levi), since 2026-10-17 14:05
  - branch: `lx42-workflow`, in an agent worktree; last commit: none yet
    (base: the commit that added the brief)
  - evidence: the brief's "Done when" checks
  - next: stage A per the brief
  - brief: `docs/design/ai_workflow.md`
- **LX45** · CLAUDE.md is 411 lines (budget about 400): move Code Style
  to a path-scoped `.claude/rules/gdscript-style.md`.
  - owner, branch, evidence, next, brief: as LX42 (stage A, step 3)

- **LX12** · Quality score, stars and receipt (`docs/design/quality.md`).
  - owner: claude session 194d3b69 (Levi); agent `m1-quality` built
    the pieces (done 12:41), and `m1-flow` wires them into the level
  - branch: mainline; last commit: 3831dc7
  - evidence: `.claude/probes/m1-quality/` (`run.ps1`) in the
    `m1-quality` worktree
  - next: `m1-flow` wires the receipt and popups in stage 2 (LX9)
  - brief: `docs/design/m1_agents.md` "m1-quality" and its handoff
- **LX9** · Item flow: arrival tween, finished-only drag, outbox area,
  item queue (`docs/design/outbox.md`).
  - owner: claude agent `m1-flow` (Sonnet) of session 194d3b69 (Levi),
    since 2026-10-17 13:30
  - branch: `m1-flow`, worktree
    `.claude/worktrees/agent-a540a5b6d42f0267e`; last commit: `cd678fb`
    (WIP: arrival, ticket, payoff, drag, outbox, queue; unpushed)
  - evidence: `.claude/probes/m1-flow/` in that worktree
  - next: wire the receipt and popups (LX12), then probes and handoff
  - brief: `docs/design/m1_agents.md` "m1-flow"
- **LX10** · Screw health: damage frames, stripped, seized, install mode
  (`docs/design/screws.md`).
  - owner: claude agent `m1-screws` (Opus) of session 194d3b69 (Levi),
    since 2026-10-17 13:30
  - branch: `m1-screws`, worktree
    `.claude/worktrees/agent-aad34b3179ae3d1e5`; last commit: none yet
    (base: 5312311)
  - evidence: `.claude/probes/m1-screws/` in that worktree
  - next: build and check per the brief
  - brief: `docs/design/m1_agents.md` "m1-screws"
- **LX11** · Flathead rework: 1 s eased twists, eased drift (at most 0.6
  of the tolerance per twist), correction along the slot, unseat
  (`docs/design/flathead.md`).
  - owner, branch, evidence, next, brief: as LX10 (agent `m1-screws`)

## Next

- **LX41** · Play M1 by hand, with a mouse and on a touch screen: the
  receipt's click-to-close and 3 s auto-close, and the card and "-N"
  placement (LX12). From m1-core: the pick-up ease, the auto put-away
  near the rack (too eager?), the cursor and mouse visibility (also
  paused), the booklet, the screw's turn and its 22.5 degree loose
  angle, the set-aside spot at (360,100). More from the stage 2
  reports.
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
  (`docs/design/solvent.md`). Smears pass their surface as
  `RepairQuality.add_defect()`'s `source`, so a ruined smear replaces
  the minor one.
- **LX21** · Oil can: drops, pivots, squeaks, misuse
  (`docs/design/oil_can.md`).
- **LX22** · Glue along cracks and clips (`docs/design/glue.md`).
- **LX23** · Items 2 to 5: rotary phone, Walkman, CRT TV, ray gun
  (`docs/design/items.md` "The jam cut").
- **LX24** · Art: screw states, decals, part states, effects, UI
  (`docs/design/decals.md` "The art list"). Placeholders to replace:
  the skid texture (`src/decals/skid_decal_set.tres`), the receipt's
  code-drawn star (`src/ui/receipt/star_icon.gd`), the hand's
  `%NopeIcon` (`src/level/level.tscn`) and the layers' ready glow
  (`src/repairables/repair_layer.gd`).
- **LX25** · Sounds: collect each design doc's "Feedback" list and add
  the streams to `src/core/audio_main.tscn`.
- **LX26** · Web export and itch.io upload (`scripts/export_web.ps1`).
  Check decal clipping in Firefox, Safari and the Pixel's Chrome; only
  Chrome and Edge are verified (`docs/design/decals.md` "Clipping").

## Residuals (known, not fixed)

- **LX27** · Source art is huge (3508x2480 PNGs, 0.6 to 2.2 MB each, drawn
  at about 0.2 scale): downscale it or cap the import size before the
  web build (`assets/images/`).
- **LX37** · 2b3fa3a committed Krita and PNG backups (`*.kra~`,
  `radio.png~`) and a 69 MB `.kra` (GitHub warns over 50 MB and
  rejects over 100 MB). Levi: leave them for now (2026-10-17).
- **LX36** · Decals have no cap per part, so repeated unseats pile up,
  and a part that draws nothing (a plain `Node2D`) shows its decals
  unclipped, with no warning (`src/decals/decal_spawner.gd`).
- **LX43** · An installed screw can't come out again, and a press on the
  rack while a tool is IN_USE does nothing (`src/level/hand.gd`,
  `src/interaction_points/screw.gd`; the m1-core handoff).
- **LX44** · m1-core's first windowed probe run failed 34 of 68 checks:
  the cursor pointed over the empty desk, and a press on the item left
  the driver in hand. Suspected, not confirmed: real mouse input mixed
  with the pushed events. A probe-side input blocker then caught 0
  events and the reruns passed (`.claude/probes/m1-core/` in the
  m1-core worktree).

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
- **LX38** · Keep the web clipping probe as a tracked check to rerun
  after Godot upgrades. It lives only in the `m1-decals` worktree, in
  `.claude/probes/m1-decals/` (`clip_web/`, `cdp_shot.mjs`).
- **LX40** · Quality extras: a day summary, a corkboard of customer
  reviews, bonuses for perfect work up to 100 (`docs/design/quality.md`
  "Later").

## Done

- **LX7** · The hand: the held thing, the cursor, touch-first press
  routing, the wrong-tool nope, holders by `Tool.Type`. Done in c9923cf
  (2026-10-17).
- **LX8** · Repair layers, point roles, surfaces, reassembly and
  finishing. Done in c9923cf (2026-10-17).
- **LX5** · Pick-up eases the follow offset instead of teleporting.
  Done in c9923cf (2026-10-17).
- **LX4** · A stored tool lines up with its holder's shape. Done in
  c9923cf (2026-10-17).
- **LX3** · Only the left button picks a tool up. Done in c9923cf
  (2026-10-17).
- **LX2** · The hand owns the cursor and resets it when the level exits.
  Done in c9923cf (2026-10-17).
- **LX1** · Tool shapes match the 0.2 visual. Done in d530e79, checked
  by m1-core's collision screenshots (2026-10-17).
- **LX6** · Levi confirmed the defaults in `overview.md` "Decisions",
  and the design docs say so now (2026-10-17).
- **LX39** · Levi: the receipt card keeps eating presses until it closes
  (2026-10-17).
- **LX13** · Decal spawner and sets (`src/decals/`); `clip_children`
  works in the web export and on desktop. Done in 0cc0332 (2026-10-17).
