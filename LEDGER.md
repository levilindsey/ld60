# ld60 ledger

Open work for ld60 (the Ludum Dare 60 game): follow-ups, known
residuals, decisions waiting on Levi, and ideas. Convention:
`.claude/rules/ledger.md`. IDs (`LX<n>`) are stable and never reused.

## Waiting on Levi

- **LX47** · Flathead calls from the m1-screws handoff
  (`docs/design/m1_agents.md`), my picks in brackets: 2 install twists of
  101.25 degrees from a 22.5 degree tilt [keep]; the ratchet only between
  twists [keep]; overcorrecting unseats, in the pause too [stop the push
  at the slot's end, so only a drift skids]; the 12 px seat tolerance is
  about 1 mm of finger travel, inferred [a touch gain, as a setting].

## In progress

<!-- Each item is a resume handle: owner, branch + last commit, evidence,
next, brief, env (`.claude/rules/ledger.md`). -->

- **LX54** · Screws pull out to a rest spot on the bench after the last
  twist; a press brings one back to sink into its hole before the install
  twists (Levi's `RemoveScrew` and clip space, 4e44a86).
  - owner: claude 194d3b69 (coordinator), agent `screw-pullout`
  - branch: `lx54-pullout`, worktree
    `.claude/worktrees/agent-a890b2f6c313d03a6`; last commit: `aff4ab4`
    (WIP, unpushed)
  - evidence: `.claude/probes/LX54/` (frames), new checks in `tests/screws/`
  - next: the agent finishes the probes and the new checks, then reports
  - brief: `docs/design/screw_pullout.md`
- **LX15** · Parts drawer and part swap: drawer below the ticket,
  parts menu, wiggle-out, sockets (`docs/design/parts_bin.md`).
  - owner: claude (Levi session), since 2026-10-17
  - branch: `main` (working tree)
  - evidence: `tests/parts/` (18 checks; the full suite is green)
  - next: Levi plays it (menu feel, drawer look with real art);
    sounds wait for LX25, part art for LX24

## Next

- **LX41** · Play M1 by hand, with a mouse and on a touch screen: the
  receipt's click-to-close and 3 s auto-close, and the card and "-N"
  placement (LX12). From m1-core: the pick-up ease, the auto put-away
  near the rack (too eager?), the cursor and mouse visibility (also
  paused), the booklet, the screw's turn and its 22.5 degree loose
  angle, the set-aside spot at (360,100). From m1-flow: the drag and
  its tilt, the drag cursor shown while an item is held, the ticket's
  look, the outbox at the left edge. From m1-screws: correcting the tip
  with a mouse and with a finger, and the touch drags on the Pixel
  (LX47). From LX53: the slide's size (`screw_slide_px`, 6 px), and
  pressing a raised screw, whose hit shape moves up with it. The sounds
  wait for LX25 (no streams yet), the screw art for LX24.
- **LX14** · Canned air: spray cone, dust clumps, fans
  (`docs/design/canned_air.md`).
- **LX16** · First item end to end: the virtual pet egg
  (`docs/design/items.md`). It replaces the three test items in
  `settings.tres` `item_queue`.
- **LX17** · Phillips pressure gauge (`docs/design/phillips.md`). Feed
  `Screw.slide` from its turn like the flathead, generalize
  `tests/screws/slide_recorder.gd` (typed to `FlatHeadScrew`), and put
  new checks in their own script: `tests/screws/probe.gd` is 933 lines.
- **LX18** · Hammer: wind-up ring, strength bands, jog, realign, reseat
  (`docs/design/hammer.md`).
- **LX19** · Pliers for stripped screws (`docs/design/pliers.md`). They
  replace m1-screws' stand-in pry: a pried screw comes back as new, and
  one that strips going in is pried home with `Screw.install()`. The
  stand-in also snaps the rest of the slide in one frame (LX53).
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
  `%NopeIcon` (`src/level/level.tscn`), the layers' ready glow
  (`src/repairables/repair_layer.gd`), and the screw's tinted head frames
  and polygon rust (`src/interaction_points/screw.gd`). The finished
  item's outline needs `Sprite2D` art with transparent margins;
  `ColorRect` placeholders only get the glow. Of Taryn's six new screw and
  driver PNGs, `rrrrrrrrrrrrrevird wercs.png` is the driver's second frame
  (cb47839); the other five (one in `gui/`) are not used yet.
- **LX25** · Sounds: collect each design doc's "Feedback" list and add
  the streams to `src/core/audio_main.tscn`. Levi's cleaned foley is in
  `assets/audio/foley_cleaned/`; the flathead's scrape wants a rising
  pitch.
- **LX26** · Web export and itch.io upload (`scripts/export_web.ps1`).
  Check decal clipping in Firefox, Safari and the Pixel's Chrome; only
  Chrome and Edge are verified (`docs/design/decals.md` "Clipping").

## Residuals (known, not fixed)

- **LX27** · Source art is huge (3508x2480 PNGs, 0.6 to 2.2 MB each, drawn
  at about 0.2 scale): downscale it or cap the import size before the
  web build (`assets/images/`).
- **LX37** · 2b3fa3a committed Krita and PNG backups (`*.kra~`,
  `radio.png~`) and a 69 MB `.kra` (GitHub warns over 50 MB and
  rejects over 100 MB). Levi: leave them for now (2026-10-17). Since
  then: a 20 MB `window.kra-autosave.kra` (cb47839, deleted in 2d71113)
  a 9.6 MB `room!!!!!!.png5857331650.tmp` (2d71113), and
  `screwwwzzzzzzflat.png~` (4e44a86). Ignoring `*~`,
  `*autosave*` and `*.tmp` in `.gitignore` would stop new ones.
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
  events and the reruns passed. The blocker is now in
  `tests/probe_base.gd`, and a windowed `item_flow` run blocked 70 real
  motions and passed (LX42 stage B).
- **LX48** · Flathead stand-ins: the seized and stripped judder is
  `tool.nope()`, and the tip follows screen positions, not
  `event.relative` (`src/interaction_points/flat_head_screw.gd`).
- **LX49** · Every run that loads the level logs "Camera2D overridden to
  physics process mode due to use of physics interpolation". Untested
  fix: `process_callback = 0` on the Camera2D in `src/level/level.tscn`.
- **LX52** · LX42 stage B left untried: the windowed `full_loop` and
  `screws` runs (`tests/run.ps1 -Name <run> -Screenshots`), Godot found
  on PATH alone, and a real export without `tests/` (only
  `--export-pack` was searched; LX26).

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
- **LX46** · Outbox extras: a flick to send, FRAGILE items, trash
  basketball, a pneumatic tube (`docs/design/outbox.md`).
- **LX50** · Screw extras: a handle lean, a grippier flathead, a screw
  dish, security screws (`docs/design/m1_agents.md`, the m1-screws
  handoff).

## Done

- **LX53** · Screws slide up the screen as they turn out and back down as
  they turn in (`Screw.slide`, `screw_slide_px`). Done in 3c4522f to
  4deac21 (2026-10-17).
- **LX51** · The screws test checks the driver's "twisting" frames instead
  of its turn (d0f4255). Done in 31153a3 (2026-10-17).
- **LX42** · AI workflow stage B: `tests/` and `tests/run.ps1`, the `src/`
  sweep in every `check.ps1`, `check.ps1 -Tests`, and exports without
  `tests/`. Done in f209751 to 7a2155b (2026-10-17).
- **LX10** · Screw health: damage frames, stripped, seized, install mode.
  Done in 8c8e354 (2026-10-17).
- **LX11** · Flathead rework: eased twists and drift, correcting along the
  slot, the unseat. Done in 8c8e354 (2026-10-17).
- **LX45** · Code Style moved to `.claude/rules/gdscript-style.md`;
  CLAUDE.md went from 411 to 317 lines. Done in 8410091 (2026-10-17).
- **LX9** · Item flow: arrival, ticket card, finish payoff, drag to the
  outbox, item queue. Done in 01b980d (2026-10-17).
- **LX12** · Quality score, stars, receipt and "-N" popups, wired into
  the level. Done in 3831dc7 and 01b980d (2026-10-17).
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
