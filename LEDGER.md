# ld60 ledger

Open work for ld60 (the Ludum Dare 60 game): follow-ups, known
residuals, decisions waiting on Levi, and ideas. Convention:
`.claude/rules/ledger.md`. IDs (`LX<n>`) are stable and never reused.

## Waiting on Levi

- **LX47** · Confirm m1-screws' flathead calls in play: a screw goes back
  in with 2 twists of 101.25 degrees (it comes back 202.5 degrees off
  home, which the slot shows as 22.5; out is 4 twists of 90); the ratchet
  plays only between twists; an overcorrection can unseat, even in the
  pause; the driver turns 360 degrees with the screw on the way out
  (`docs/design/m1_agents.md`, the m1-screws handoff).

## In progress

<!-- Each item is a resume handle: owner, branch + last commit, evidence,
next, brief, env (`.claude/rules/ledger.md`). -->


## Next

- **LX42** · AI workflow stage B, once m1-screws merges: tracked probes
  in `tests/` with `check.ps1 -Tests`, and a sweep that loads every
  script and scene (`docs/design/ai_workflow.md` "Stage B"). Stage A
  (the check script and the rules) is in 8410091.
- **LX41** · Play M1 by hand, with a mouse and on a touch screen: the
  receipt's click-to-close and 3 s auto-close, and the card and "-N"
  placement (LX12). From m1-core: the pick-up ease, the auto put-away
  near the rack (too eager?), the cursor and mouse visibility (also
  paused), the booklet, the screw's turn and its 22.5 degree loose
  angle, the set-aside spot at (360,100). From m1-flow: the drag and
  its tilt, the drag cursor shown while an item is held, the ticket's
  look, the outbox at the left edge, the thud, ding and hmm sounds.
  From m1-screws: correcting the tip with a mouse and with a finger, the
  size of touch drags on the Pixel, the sounds, and the look of the head
  frames, rust, skid and sparks.
- **LX14** · Canned air: spray cone, dust clumps, fans
  (`docs/design/canned_air.md`).
- **LX15** · Parts bin and part swap: hotspots, sockets, wiggle-out
  (`docs/design/parts_bin.md`).
- **LX16** · First item end to end: the virtual pet egg
  (`docs/design/items.md`). It replaces the three test items in
  `settings.tres` `item_queue`.
- **LX17** · Phillips pressure gauge (`docs/design/phillips.md`).
- **LX18** · Hammer: wind-up ring, strength bands, jog, realign, reseat
  (`docs/design/hammer.md`).
- **LX19** · Pliers for stripped screws (`docs/design/pliers.md`). They
  replace m1-screws' stand-in pry: a pried screw comes back as new, and
  one that strips going in is pried home with `Screw.install()`.
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
  `ColorRect` placeholders only get the glow. Taryn's six new screw and
  driver PNGs in `assets/images/` (one in `gui/`) are not used yet.
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
- **LX48** · Flathead stand-ins: the seized and stripped judder is
  `tool.nope()`, and the tip follows screen positions, not
  `event.relative` (`src/interaction_points/flat_head_screw.gd`).
- **LX49** · Every run that loads the level logs "Camera2D overridden to
  physics process mode due to use of physics interpolation". Untested
  fix: `process_callback = 0` on the Camera2D in `src/level/level.tscn`.

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
