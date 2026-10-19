# ld60 ledger

Open work for ld60 (the Ludum Dare 60 game): follow-ups, known
residuals, decisions waiting on Levi, and ideas. Convention:
`.claude/rules/ledger.md`. IDs (`LX<n>`) are stable and never reused.

## Waiting on Levi

- **LX47** · Flathead calls from the m1-screws handoff
  (`docs/design/m1_agents.md`), my picks in brackets: 2 install twists of
  101.25 degrees from a 22.5 degree tilt [keep]; the ratchet only between
  twists [keep]. Decided by Levi (2026-10-17, rev. 2026-10-18): the
  tip unseats only while the screw is turning, by its drift or the
  player's push; at rest the push stops at the slot's end. Touch
  drags move the tip at `flathead_touch_gain` 2.0, the mouse 1 to 1.

## In progress

<!-- Each item is a resume handle: owner, branch + last commit, evidence,
next, brief, env (`.claude/rules/ledger.md`). -->

- **LX58** · Hook up the new decal textures: tinted sets for dents,
  cracks, scratches, rust, dust (two sets), grime (two sets) and glue;
  sprite dirt points with set and color config; hammer dents and
  cracks fitted onto parts. (LX24 follow-on.)
  owner: Levi (Muse Code)
  branch: mainline
  next: Levi to review and commit the working tree, then move this
    to Done. Implemented, uncommitted on purpose (no commit ask).
  brief: `docs/design/decals.md`, `docs/design/hammer.md`.
  evidence: `src/decals/`, `src/interaction_points/dirt_spot.gd`,
    `tests/decals/` (43 checks pass; tools/phillips/glue/audio too).

- **LX56** · Recurring itch deploys until Mon 2026-10-19 13:00 PDT:
  Muse cron job `90714525` (every 2 h at :17) pushes the working
  tree to `levilindsey/repair-shop:html5` via `scripts/deploy_itch.ps1`,
  gated on `scripts/check.ps1 -Tests` and skipped when the tree is
  unchanged (`build/last-itch-push.txt`); it deletes itself after the
  deadline. Stop early with `cron_delete 90714525`. Still Levi's, on
  the itch Edit game page: Kind of project = HTML and "This file will
  be played in the browser" (1280x720) on the html5 upload - without
  those the page shows a broken download button instead of the game.

## Next

- **LX41** · Play M1 by hand, with a mouse and on a touch screen: the
  receipt's click-to-close and 3 s auto-close, and the card and "-N"
  placement (LX12). From m1-core: the pick-up ease, the auto put-away
  near the rack (too eager?), the cursor and mouse visibility (also
  paused), the booklet, the screw's turn and its 22.5 degree loose
  angle, the set-aside spot at (362, 188). From m1-flow: the drag and
  its tilt, the drag cursor shown while an item is held, the ticket's
  look, the outbox at the left edge. From m1-screws: correcting the tip
  with a mouse and with a finger, and the touch drags on the Pixel
  (LX47). From LX53 and LX54: the slide's size (the first key of
  `RemoveScrew`, about 6 px), pressing a raised screw, whose hit shape
  moves up with it, the trip to the bench and its ease, the resting
  screw's glow, the rest spots (placeholders from (-440, 80), which may
  overlap the parts drawer or the rack), and the bench art's draw order
  against a held tool, the set-aside cover and the other resting screws.
  From LX14, LX18 and LX20: the rag drag feel and its reversal bonus,
  the bulb aim and squeeze, the hammer ring timing, band width and
  recoil, and the rack spots at (430, 80), (541, 120) and (460, 220).
  From LX17: circling a Phillips screw with a mouse and a finger,
  the band at 3 to 7 rad/s, the gauge at (100, -100) from the head,
  and the Phillips holder at (460, 40). From LX22: tracing glue
  along a crack, the flood point, the 3 s dry, and the glue
  holder at (209, 301).
  The sounds wait for LX25 (no streams yet), the screw art for LX24.
- **LX16** · First item end to end: the virtual pet egg
  (`docs/design/items.md`). It replaces the three test items in
  `settings.tres` `item_queue`.
- **LX19** · Pliers for stripped screws (`docs/design/pliers.md`). They
  replace m1-screws' stand-in pry: a pried screw comes back as new, and
  one that strips going in is pried home with `Screw.install()`. The
  stand-in also snaps the rest of the slide in one frame (LX53). Since
  LX54 a screw pried out goes to the bench like a removed one.
- **LX21** · Oil can: drops, pivots, squeaks, misuse
  (`docs/design/oil_can.md`).
- **LX23** · Items 2 to 5: rotary phone, Walkman, CRT TV, ray gun
  (`docs/design/items.md` "The jam cut").
- **LX24** · Art: screw states, decals, part states, effects, UI
  (`docs/design/decals.md` "The art list"). Placeholders to replace:
  the skid texture (`src/decals/skid_decal_set.tres`), the receipt's
  oof / ok / great stamps (`TicketCard.stamp_textures`, empty), the hand's
  `%NopeIcon` (`src/level/level.tscn`), the layers' ready glow
  (`src/repairables/repair_layer.gd`), and the screw's tinted head frames
  and polygon rust (`src/interaction_points/screw.gd`). The finished
  item's outline needs `Sprite2D` art with transparent margins;
  `ColorRect` placeholders only get the glow. Of Taryn's six new screw and
  driver PNGs, `rrrrrrrrrrrrrevird wercs.png` is the driver's second frame
  (cb47839) and `screweeeeeeeeddddddd.png` is in `flat_head_screw.tscn`;
  the other four (one in `gui/`) are not used yet. With new screw art,
  pose the bench art like `RemoveScrew`'s last key (`screw_pullout.md`).
  Also: the real glue bottle for `glue_bottle_placeholder.png`, a
  crack decal for the drawn `Crack` line, and the grime and dust
  sprites for the placeholder blobs (`grime_spot.tscn`,
  `dust_clump.tscn`).
- **LX25** · Sounds: collect each design doc's "Feedback" list and add
  the streams to `src/core/audio_main.tscn`. Levi's cleaned foley is in
  `assets/audio/foley_cleaned/`; the flathead's scrape wants a rising
  pitch.
- **LX26** · Web export and itch.io upload (`scripts/export_web.ps1`).
  Check decal clipping in Firefox, Safari and the Pixel's Chrome; only
  Chrome and Edge are verified (`docs/design/decals.md` "Clipping").
- **LX60** · Bench polish, stage 2 (stage 1 drag core landed;
  the roll on set-down after a drag, the pick-up turn and
  shape-matching drop shadows are done: tools pick a holder
  treatment by enum, screws/parts cast silhouettes that follow
  their rotation, ticket/manual have their authored shadows):
  overlap-aware draw order inside each group (a piece rises
  only once dragged clear of what covers it).

- **LX71** · Authored Shapes now exist on points and broken pieces
  (TV antenna, piano key, Atari socket's good/bad parts). The other
  BrokenPieces (radio dial, toaster wheels) still grab by their
  middle reach: give each a `Shape` child and assign
  `BrokenPiece.shape` when their art lands. (The Game n Watch
  d-pad, its point, its chip socket and its screws got theirs in
  the Game n Watch grab-shapes pass.)
## Residuals (known, not fixed)

- **LX68** · The toaster's late beats (the hammer target that appears
  once it wanders, the second wheel knocked off mid-repair) are outside
  the `RepairSequence` built at spawn, so idle hints may skip them.
- **LX72** · `tests/bench_drag/` fails 2 checks at 86e24cc plus the
  holder-shadow working tree (verified identical on a stashed
  baseline, 2026-10-19): "a resting screw's shadow keeps its turn
  with it" and "a loose cover's shadow keeps its turn with it".
  Owner: whoever next works `src/props/drop_shadow.gd`.
- **LX59** · `full_loop`, `full_loop_booklet`, `item_flow`, `screws`
  and `parts` probes fail at HEAD 2d0096b (checked 2026-10-18 on a
  clean worktree, so not LX58 fallout): the Phillips-in-test-box and
  tuning commits (10927f5, 2d0096b) moved the game, and the probe
  updates are still uncommitted in the main tree
  (`tests/screws/probe.gd`). Owner: whoever lands the tuning.

- **LX27** · Source art is huge (3508x2480 PNGs, 0.6 to 2.2 MB each, drawn
  at about 0.2 scale): downscale it or cap the import size before the
  web build (`assets/images/`).
- **LX37** · 2b3fa3a committed Krita and PNG backups (`*.kra~`,
  `radio.png~`) and a 69 MB `.kra` (GitHub warns over 50 MB and
  rejects over 100 MB). Levi: leave them for now (2026-10-17). Since
  then: a 20 MB `window.kra-autosave.kra` (cb47839, deleted in 2d71113)
  a 9.6 MB `room!!!!!!.png5857331650.tmp` (2d71113), and
  `screwwwzzzzzzflat.png~` (4e44a86). `.gitignore` now skips `*~`,
  `*.kra-autosave.kra` and `*.tmp`; the files already committed stay.
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
- **LX55** · `tests/screws/probe.gd` is 1010 lines, past gdlint's default
  1000 (nothing runs gdlint here). Split it before more screw checks land
  (LX17 to LX19; the LX54 handoff in `docs/design/screw_pullout.md`).

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
- **LX57** · Solvent bottle and soaking for the rag: wetness, drying,
  drips (`docs/design/solvent.md` "Soaking (later, not built)"). The
  rag wipes dry until a bottle prop lands.

## Done

- **LX70** · Dragging the main repairable body: the empty hand
  drags the item by its innermost layer once exposed, at any
  time mid-repair; it rests where it is dropped inside the
  workable area and flies back in when let go outside it, like
  a loose layer. Points, sockets and the finished item's
  outbox drag keep their presses. Probe: `tests/misuse/`.
  Done (2026-10-19).
- **LX71** · Gear, bolt and nut art wired in as real parts (new
  BOLT/NUT kinds with dedicated scenes; the shrink ray's hook
  socket takes a bolt now). There is no spring part: the SPRING
  kind and its scene are removed, and every socket's serialized
  `accepted_part` shifted with the enum. Loose parts and broken
  pieces also cast a single-layer silhouette shadow now, so a
  small part like the bulb no longer shows two. Done
  (2026-10-19).
- **LX72** · Shrink ray (`src/repairables/shrink_ray_repairable.tscn`):
  the first hammer hit sets it off and the beam shrinks the hammer for
  the rest of the run (higher hits, never dents). Then four tiny-hammer
  hits on the jam, wipe the grime off the crystal, and replace the
  crystal (new CRYSTAL part) and the bolt in the hook. Done
  (2026-10-19). Zaven still to play it with a mouse (LX41).
- **LX69** · Radio arc, built differently from the old design: the shop
  radio breaks on its shelf, the music cuts out, it flies down to the
  bench as the item, the music returns once it is fixed, and it goes
  back to the shelf (HERE) instead of the outbox. Done (2026-10-19).
- **LX67** · Toaster on wheels (`src/repairables/toaster.tscn`, last in
  `item_queue`): glue the fallen wheel, it wanders, two hammer hits stop it
  and knock the other wheel off, glue that, wipe grime, the face appears.
  Done (2026-10-18). Zaven still to play it with a mouse (LX41).
- **LX66** · Broken interaction points and pieces for glue:
  placeable `BrokenPoint` + `BrokenPiece` (attached, hidden behind
  a covering layer, or falling separately on arrival with the bench
  pieces' flight), glue first, then a hold still ring game
  (`hold_sec` per point, default 5); off target glue leaves a rag
  cleanable `GlueSmear`, charged as a blob only if left when the
  item finishes. Done (2026-10-18), covered in
  `tests/broken_glue/` (25 checks). Levi still to play it by hand
  (LX41). Design: `docs/design/glue.md` "Broken pieces".
- **LX63** · `level.tscn` loaded `drawer.tscn` for `Drawer.tscn`. Done
  in fd489cd (2026-10-18).
- **LX64** · Screws of a given type are interchangeable: a resting
  screw dropped near any empty same-type hole on its layer seats
  there, and the two screws trade holes. It did not work that way
  before: a screw only seated into its own hole. Done (2026-10-18)
  in `Screw.find_seat_target()`/`come_back(target)` and the hand's
  drop, with the `tests/screw_swap/` probe (23 checks). Levi still
  to play it by hand (LX41).
- **LX65** · The lid (cover layer) no longer renders behind the
  item's main part after being put back on. `RepairLayer.put_back()`
  restored a raw child index read at ready, before each layer's
  drop shadow moved in beside it, so the cover landed in front of
  the inside layer in draw order. It now restores its place among
  the item's layers. Done (2026-10-18), covered in
  `tests/screw_swap/` and `tests/bench_drag/`.
- **LX62** · Idle hints on a derived repair sequence: each item's
  steps are autodetermined from its layers, fasteners, faults and
  sockets (`RepairSequence`); after 7 s without a correct
  interaction the current step's target lights, after 16 s its
  tool (or the fitting socket) too, every drawer for a fetch, the
  outbox for shipping. Done in the working-tree landing
  (2026-10-18). Levi still to play it for the delays' feel (LX41).
  Design: `docs/design/hints.md`, probe: `tests/hints/`.
- **LX61** · Diegetic parts drawers: three clip-masked art drawers
  replace the parts menu; parts hide in them per item, drag out to
  the bench, drag back to put away, leftovers cleaned up at the
  outbox. Done in the working-tree landing (2026-10-18). Levi
  still to play it and align the drawers with the room art (LX41).
- **LX22** · Glue along cracks: squeeze, trace, dry, blobs
  (`docs/design/glue.md`). Done in 37959f3 (2026-10-17) with the
  placeholder bottle. Levi still to play it (LX41).
- **LX17** · Phillips circular drag: circle speed in the band
  turns the screw, an empty grip cams out (`docs/design/
  phillips.md`). Done in a71ec36 (2026-10-17). Levi still to
  play it (LX41).
- **LX14** · Air blower bulb: tap puffs, dust clumps and fans
  (`docs/design/canned_air.md`). Done in b96ebaa (2026-10-17). Levi
  still to play it (LX41).
- **LX18** · Hammer: wind-up ring, strength bands, jog, realign,
  reseat (`docs/design/hammer.md`). Done in b96ebaa (2026-10-17).
  Levi still to play it (LX41).
- **LX20** · Rag and sensitive surfaces, dry until solvent lands
  (`docs/design/solvent.md`). Done in b96ebaa (2026-10-17). Levi
  still to play it (LX41).
- **LX54** · Screws pull out to a rest spot on the bench after the last
  twist, and a press brings one back to sink into its hole before the
  install twists (`docs/design/screw_pullout.md`). Done in c0e493d to
  6988520 (2026-10-17). Levi still to play it (LX41).
- **LX15** · Parts drawer and part swap: drawer below the ticket,
  parts menu, wiggle-out, sockets (`docs/design/parts_bin.md`). Done in
  392c842 (2026-10-17). Levi still to play it (menu feel, drawer look
  with real art); sounds wait for LX25, part art for LX24.
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
