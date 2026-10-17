# M1 agent briefs

M1 is LX7 to LX13; LX14 to LX16 are out for now. Each item's design is
its own doc in this folder. This file says which agent builds what, in
which files, and how to check it. Levi chose parallel agents on
2026-10-17. The coordinator (claude session 194d3b69) merges each branch
to `main` and pauses the work at 98% weekly usage.

| Stage | Agent | Model | Items | Owns |
|---|---|---|---|---|
| 1 | `m1-core` | Opus | LX7, LX8, with LX1 to LX5 | `src/level/`, `src/tools/`, `src/interaction_points/`, `src/repairables/` (not `repair_quality.gd`), `project.godot`, `CLAUDE.md` |
| 1 | `m1-quality` | Sonnet | LX12 | `src/repairables/repair_quality.gd`, `src/ui/receipt/`, `src/ui/defect_popup/` |
| 1 | `m1-decals` | Sonnet | LX13 | `src/decals/` |
| 2 | `m1-screws` | Opus | LX10, LX11 | `src/interaction_points/`, `src/tools/flat_head_screw_driver.*` |
| 2 | `m1-flow` | Sonnet | LX9, and wiring LX12 into the level | `src/level/`, `src/repairables/repairable.gd`, `CLAUDE.md` |

Stage 2 starts once stage 1 is on `main` and the coordinator has added
`%Decals`, `Level.spawn_decal()` and `Repairable.quality` to it.

## Rules for every agent

- **Branch.** You run in your own git worktree. First run
  `git branch -m <your agent name>`. Commit work in progress at every
  milestone, broken or not. Never push, and never edit `LEDGER.md`.
- **Godot.** Run it from PowerShell only. A fresh worktree has no
  `.godot/` cache, so run `godot --headless --path . --import` first.
  Run it again after adding or renaming a `class_name`. Never kill Godot
  by name. Kill only a PID you launched.
- **Files.** Touch only the files you own. Two files are shared, so keep
  your changes in them small and in your own spot so the branches merge
  cleanly:
  - In `src/core/settings.gd`, your exports go in your own export group,
    placed where your section says.
  - In `settings.tres`, add only your own lines.
- **Sounds.** `G.audio.play_sound(name)` already knows these names:
  `click`, `clunk`, `thud`, `ding`, `hmm`, `creak`, `ratchet`, `scrape`,
  `skid`, `pop`, `grind`, `whoosh` and `snap`. They have no streams yet,
  so they're silent. Don't edit `src/core/audio_main.*`. If you need
  another name, use the nearest one and say so in your report.
- **World Controls eat clicks.** A `ColorRect` placeholder in the world
  takes mouse presses before `_unhandled_input` and physics picking see
  them. Set `mouse_filter` to Ignore on every world Control, or use a
  `Polygon2D` instead.
- **Checking.** Verify headless. Keep probes in
  `.claude/probes/<your agent name>/`, which is untracked. A probe is a
  scene whose script does this:
  1. Instantiates `res://src/core/main.tscn`.
  2. Brings the game to GAME with
     `G.state.transition(StateMain.State.GAME)`.
  3. Drives it with `get_viewport().push_input()` or with direct calls.
     A mouse event's `position` is in viewport pixels, and world (0, 0)
     is (640, 360).
  4. Asserts what should have happened, then quits with an exit code.

  Run probes with `Start-Process -PassThru` and `--log-file`, and wait
  with a timeout. Any `SCRIPT ERROR` or `ERROR:` in the log is a
  failure.

  Headless can't render. For a visual check, run windowed with
  `--quit-after` and save `get_viewport().get_texture().get_image()` to
  your probe folder. Keep those runs few and short, because Levi is at
  this desktop.
- **Leave to Levi** anything that needs a real mouse, a touch screen or
  ears. List it in your report.
- **Stop rule.** Stop when your items are done or when you reach your
  cap, whichever comes first. The cap is 2 h for Opus and 1 h for
  Sonnet. Run `Get-Date` at the start and at each milestone. A
  compaction is not a stop. After one, re-read this brief and
  `git log`. When you stop:
  1. Commit your work.
  2. Add a short handoff under your section here: what works and what's
     left. Commit that too.
  3. Report.
- **Report.** End your report with:
  - what you built (files and public API);
  - how you checked it;
  - `Ledger items`: follow-ups, residuals, decisions for Levi, and any
    "Later" ideas from your docs worth keeping;
  - your items' handle fields: branch, last commit, evidence and next
    step.
- Don't start helper agents.

## m1-core (LX7, LX8)

Read these first:
- `tools.md` and `repairables.md`;
- `overview.md` "Rules";
- LX1 and LX2 in `docs/ledger_notes.md`.

LX1 to LX5 in `LEDGER.md` fold into LX7.

- **The hand** lives in `src/level/hand.gd`. It is `%Hand` in
  `level.tscn` and is reached as `G.level.hand`. Build the API, cursor
  rules and press rules from tools.md, and:
  - Use one `_unhandled_input` for left presses and releases. Mark an
    event handled only when you used it, because the booklet in
    `zaven_demo_level.tscn` gets its presses by physics picking.
  - Track the pointer from mouse events. Convert it to world space with
    the canvas transform every frame, because the camera shakes.
  - Never warp the mouse.
  - Reset the cursor when the level exits (LX2), and show it while the
    game is paused.
- **Tools:**
  - Drop the per-tool cursor code and the grab area's input wiring.
  - Add the follow offset and the nope shake.
  - Take the LX4 holder offset from the holder's shape, not its node.
  - Fix the shape sizes (LX1).
  - In IN_USE the tool is a puppet: the point places it every frame.
  - `ToolHolder.type` becomes a `Tool.Type`, and
    `Level.get_tool_holder_position()` finds a holder by its type.
- **Points:**
  - `role`, `is_required`, `accepted_tools` and `broken_scene`.
  - `is_exposed()`, `engage(tool)`, `on_poked()` and `pulse()`.
  - Finishing a point tells its layer and the item.
- **Layers:**
  - `RepairLayer`: lift-off, the set-aside stack at a new
    `%SetAsideSpot` beside the mat, the ready glow, and putting a layer
    back with its fasteners in install mode.
  - `Surface`, on physics layer 6 `surfaces`. Add that layer to
    `project.godot` and `Settings.PhysicsLayer`.
  - The item's signals and `finished`, from repairables.md.
  - Give each layer an `art` export: the CanvasItem that decals will
    parent to and clip against. Keep points and surfaces as siblings of
    the art, not its children.
- **Screws, minimally:** split `Screw` (`screw.gd`) from `FlatHeadScrew`
  (`flat_head_screw.gd`) as screws.md "Building it" says. Give them only
  the remove and install states the layers need.

  The flathead's `engage()` is a stand-in: the tool goes IN_USE, and the
  screw rises and pops out after a short tween. In install mode it goes
  in the same way. Mark it `# Stand-in until LX11.` LX10 and LX11
  replace it in stage 2.
- **The test item** gets two layers:
  - `Inside`, the innermost;
  - `Cover`, with two flathead screws and a PLASTIC surface.

  Make the screws about 24 px across.
- **Rule 7:**
  - An unfinished item shakes, plays `hmm` and pulses its remaining
    required points.
  - A finished item calls an empty `Hand` method that LX9 fills in with
    dragging.

  Don't build the arrival, the outbox, the queue, the quality score or
  the receipt. Those belong to stage 2 and m1-quality.
- **Settings:** your groups are "Hand" and "Layers". Put them right
  after the `default_level_scene` line in `settings.gd`.
- **CLAUDE.md:** update Project Structure, Boot Flow step 6, Core APIs,
  Physics Layers and Configuration for what you built.
- **Check** with a probe that plays the loop with pushed presses:
  1. Take the driver from its holder.
  2. Press both screws.
  3. The cover lifts and moves to the set-aside spot.
  4. Press the cover to put it back.
  5. Drive both screws in.
  6. The item emits `finished`.

  Also check:
  - the driver goes back to its holder;
  - a wrong tool nopes (empty a point's `accepted_tools` in the probe);
  - the cursor shape and mouse mode in each state;
  - the cursor while paused.

## m1-quality (LX12)

Read `quality.md`. Build `RepairQuality`, the receipt card and the
floating "-N" as standalone pieces. m1-flow wires them into the level in
stage 2. Don't touch `src/level/` or `repairable.gd`.

- **`RepairQuality`** goes in `src/repairables/repair_quality.gd`.
  Build it as quality.md "Building it" says, and add:
  - `signal defect_added(defect, points, global_position)`;
  - `repair_time_sec` and `par_time_sec`, which the item fills in.

  Points come from settings.
- **The receipt** goes in `src/ui/receipt/`. It is a Control scene with
  `open(item_name: String, quality: RepairQuality)` and
  `signal closed`, laid out and animated as quality.md says. It will
  sit in a CanvasLayer in the level. Give it a full-rect root that
  stops mouse presses while open and ignores them while closed.
- **The popup** goes in `src/ui/defect_popup/`. It shows "-N" at a
  world position for about 1 s. Scripts can't `preload` or `load`, so
  either export its scene in your settings group or build it in code.
  Give m1-flow a one-line way to spawn one.
- **Settings:** your group is "Quality". Put it at the end of the export
  list in `settings.gd`, after the "Tools" group.
- **Check:**
  - A probe fills a `RepairQuality` with known defects and a known
    time. It asserts the score and the stars against quality.md's
    numbers.
  - It opens the receipt and waits for `closed`, both after a click and
    after the timeout.
  - A windowed screenshot of the receipt.

### Handoff (m1-quality, 2026-10-17)

LX12 is built and checked as standalone pieces. Nothing is wired into the
level yet; that is m1-flow's job in stage 2. The work is on branch
`m1-quality`, unpushed. The probe is `.claude/probes/m1-quality/run.ps1`
(untracked). It passes 144 checks headless, and `-Shots` saves screenshots
of the receipt and the popups.

**What works**

- `RepairQuality` (`src/repairables/repair_quality.gd`):
  `add_defect(defect, global_position, source = null) -> int` returns the
  points it cost and emits `defect_added(defect, points, global_position)`.
  `repair_time_sec` and `par_time_sec` are plain vars. Read it with
  `get_score()`, `get_stars()`, `get_time_penalty()`, `get_summary()` and
  `get_defect_points_total()`. The points come from the "Quality" group in
  `settings.gd` (`get_defect_points()`).
- The receipt (`src/ui/receipt/receipt.tscn`): `open(item_name, quality)`,
  `close()` and `signal closed`. It slides in from the right, lists the
  defects, the time and the total, pops the stars in one at a time (a
  sparkle at 3) and closes on a click or after 3 s. Its timings are
  exports on the scene root.
- The popup (`src/ui/defect_popup/`):
  `DefectPopup.spawn(parent, points, world_position)`. The scene is
  `Settings.defect_popup_scene`.

**Wiring for m1-flow**

1. Put `receipt.tscn` in a CanvasLayer in `level.tscn`. Layer 100 sits
   under the Hud (200).
2. Connect `quality.defect_added` to a one-liner:
   `DefectPopup.spawn(G.level, points, global_position)`.
3. When the item is finished, set `quality.repair_time_sec` (paused time
   excluded) and `quality.par_time_sec`, then call
   `receipt.open(name, quality)`. quality.md lets the next item drop in
   behind the card, so wait for `closed` only if something must.
4. Pass the damaged surface or screw as the third argument of
   `add_defect()` for smears. A ruined smear then replaces its minor one,
   and a minor smear on a ruined surface costs nothing.
5. An open card stops every mouse press, so nothing under it (the Hand,
   tools, points) sees a click until the card is dismissed. The first
   click only closes it.

**Left**

- Levi, with a real mouse, touch screen and ears: the feel of
  click-to-close, the whoosh and ding (silent until LX25), and the look
  and placement of the card and the popups.
- The star and sparkle art is code-drawn (LX24 can replace it).
- The edits to `settings.gd` and `settings.tres` only append, but they
  can still need a trivial merge with m1-core's.

## m1-decals (LX13)

Read `decals.md`.

1. **Check clipping on the web first.**
   - Make a probe scene with two parents set to `CLIP_CHILDREN_AND_DRAW`:
     a `ColorRect`, and a `Sprite2D` with transparent areas. Give each a
     child decal that hangs over its edge.
   - Export it for the web into your probe folder, with the probe as the
     main scene. Use the "Web" preset; the 4.7.2 templates are
     installed. Change `run/main_scene` in your worktree only, and never
     commit that change.
   - Serve it on a free port (`scripts/serve_web.py` shows how).
   - Screenshot it with headless Chrome or Edge. WebGL may need
     SwiftShader flags. Look at the image.
   - Check desktop too, with a windowed run.
   - Write the result into decals.md "Clipping".
2. **Build** `DecalSet` and `DecalSpawner` in `src/decals/` as decals.md
   says, with `spawn(kind, part, global_position, size, direction)`.
   Add `src/decals/decal_spawner.tscn` with its sets assigned.
   - M1 needs one kind, `SKID`, for the flathead's unseat. Adding a kind
     should take one enum entry, one export and one `.tres`.
   - `part` may be a Control or a Node2D. Place and scale the decal so
     `size` is in world pixels, whatever the part's scale.
   - The spawner sets up the part's clipping itself, or the fallback if
     the web check failed. Callers only pass the part.
3. **Texture:** make a placeholder inside the `.tres`, a
   `GradientTexture2D` for example. Don't add files under
   `assets/images/decals/`. The decal art belongs to LX24, and its
   `screwdriver_skid.png` will replace the placeholder.

Don't touch `src/level/`; `%Decals` goes into the level at the merge.

**Check** with a probe that spawns decals on both kinds of part, near
their edges and over them, at several part scales and rotations. It
asserts each decal's parent, position and size. Add the screenshots from
step 1.

### Handoff (2026-10-17, m1-decals)

**Works,** on branch `m1-decals`:
- `src/decals/decal_spawner.tscn` is the node to instance in the level
  as `%Decals`. `spawn(kind, part, global_position, size, direction)`
  returns the new `Sprite2D`, or null (with a logged error) on bad
  input. `part` is a Control or a Node2D. `size` is the decal's longer
  side in world pixels, whatever the part's scale, rotation or wrapper.
  The spawner turns on the part's clipping itself.
- One kind, `DecalSpawner.Kind.SKID`, from `skid_decal_set.tres`. Its
  texture is a `GradientTexture2D` placeholder, so LX24's
  `screwdriver_skid.png` goes into that `.tres`. A `DecalSet` also holds
  the scale range, whether it aligns to `direction`, flips, a tint and an
  optional multiply `blend_material`.
- A new kind is one `Kind` entry (say `DENT`), one export named after it
  (`dent_set`) and one `DecalSet` `.tres` assigned in
  `decal_spawner.tscn`. `_ready` stops the game if a kind has no set.
- Checked: the clipping probe (decals.md "Clipping"), then a spawner
  probe on `ColorRect` and `Sprite2D`-with-hole parts at several scales,
  rotations and wrappers, at edges, corners, holes and over them: 69
  checks headless and windowed, and 44 pixel checks in the windowed run
  (7 more were too close to an edge to call). Evidence is in the
  untracked `.claude/probes/m1-decals/` (`spawner_desktop.png`,
  `clip_*.png`, logs, the probe scripts).

**At the merge:**
- Instance `decal_spawner.tscn` in `level.tscn` and give it a unique
  name, `%Decals`. Nothing else in `src/level/` has to change. A `%`
  name only resolves inside its own scene, so tools reach it through a
  `Level` pass-through such as `spawn_decal(...)`, like the camera shake.
- Pass the node that draws the art as `part` (m1-core's layer `art`, or
  a `ColorRect` or `Sprite2D`). A plain `Node2D` wrapper clips nothing,
  so its decals would hang over the edge, with no error.

**Left:**
- No cap on decals per part, so many unseats on one layer pile up.
- Draw order follows the tree: a decal draws right after its part and
  above the part's other children, but below the part's later siblings,
  such as screw points that are siblings of the art.
- The clip applies to all of the part's children, so anything else under
  the part that sticks out past the art is cut off too.
- Firefox, Safari and a phone's browser are unchecked for clipping.
- The multiply `blend_material` works in the clip probe, but no set uses
  it yet.

## m1-screws (LX10, LX11), stage 2

Read these first:
- `screws.md` and `flathead.md`;
- `quality.md` "Defects";
- the m1-core handoff above, for the hand, the points and the `Screw`
  and `FlatHeadScrew` split as built.

Your settings group is "Flathead", at the end of `settings.gd`. Don't
edit `src/level/` or the item scenes. They are m1-flow's.

- **Screw health (LX10),** in `Screw`, as screws.md "Building it" says:
  - `max_health`, `health`, `take_damage()`, the signals and the four
    head frames. The damage art is LX24's, so make the frames differ
    with what exists (a tint per frame is fine) and mark it
    `# Placeholder until LX24.`
  - Each damage point adds `SCREW_DAMAGE` to the item's quality, and the
    strip adds `SCREW_STRIPPED` on top:
    `quality.add_defect(defect, global_position, self)`.
  - **Stripped:** the driver no longer bites, so a press grinds and
    nopes. The pliers come in M2 (LX19), and until then a stripped screw
    would block the item, so the next press pries it out after the
    grind. Mark it `# Stand-in until LX19.`
  - **Seized:** `is_seized`, a placeholder rust overlay, the warning
    grind, then 1 damage per stalled try. The oil can (LX21) will call
    an `unseize()` method. Nothing calls it yet.
  - **Removal and install mode,** replacing m1-core's stand-in tween.
- **The flathead (LX11),** in `FlatHeadScrew`, replacing the
  `# Stand-in until LX11.` engage: the twist cycle, the eased drift,
  correcting along the slot, the unseat and the feedback, as flathead.md
  says. Its "Tuning" table says which values are settings and which are
  per-screw exports.
  - **Unseat** follows LX6's default. The twists done are kept, the
    screw takes 1 damage, and a skid decal goes down where the tip left:
    `G.level.spawn_decal(DecalSpawner.Kind.SKID, part, position, size,
    direction)`, where `part` is the layer's `art`.
  - **Pointer motion:** use the hand's hook if m1-core built one.
    Otherwise read `InputEventMouseMotion` in the screw's own input
    callback while it is engaged, and don't mark it handled.
  - Sparks can be a `CPUParticles2D`. The scrape's rising pitch waits
    for streams (LX25), so just play it.
- **Check** with probes:
  - Correcting along the slot keeps the tip seated: 4 twists take the
    screw out, and 2 put it back in install mode.
  - Never correcting unseats it: 1 damage, the `SCREW_DAMAGE` defect, a
    skid decal on the layer's art, the tool back in HELD, the twists
    kept.
  - The drift code, run directly over many screws, matches the
    `slip_bias` table in flathead.md.
  - Three slips strip it: the frames, the points (2 per damage and 10
    for the strip), the grind and nope, then the pry.
  - A seized screw grinds once, then takes damage per stalled try.
  - m1-core's full-loop probe still passes, driving the real twists.

Leave to Levi: correcting by mouse and by finger, including how big
touch drags' `relative` values are on the Pixel.

## m1-flow (LX9), stage 2

Read these first:
- `outbox.md`, and `quality.md` "Receipt";
- the m1-quality handoff above, "Wiring for m1-flow";
- the m1-core handoff above, for the hand's empty drag method and the
  item's signals.

Your settings: `item_queue` goes in the "Repairables" group, and any new
group ("Item flow") right after m1-core's "Layers" group. Don't edit
`src/interaction_points/` or `src/tools/`. They are m1-screws'.

- **Arrival,** as outbox.md says, filling the TODO in
  `spawn_repairable()`. Add `Level.shake_camera()` and use it. Keep
  Levi's landing shake (7 px for 0.15 s) over the doc's 3 px. The item
  counts its repair time from landing to `finished`, unpaused time only.
- **Ticket:** a paper tag or a HUD card with the item's name and its
  complaint, from `Repairable` exports (`display_name` and
  `ticket_text`; add them if missing). A placeholder look is fine.
- **Finishing:** the ding, a sparkle, and the outline glow with
  `assets/shaders/sprite_outline.gdshader`, through an export rather
  than a `preload`. Then the item can be dragged.
- **Dragging:** fill m1-core's empty hand method. Only a finished item
  drags, only with an empty hand. The hand holds it at the grab offset,
  and it tilts with the drag speed, up to 8 degrees.
- **Outbox:** `%Outbox`, an `Area2D` on the left desk segment with its
  mask on REPAIRABLES and a `Polygon2D` placeholder. The release rules
  are outbox.md's.
- **Queue:** `item_queue: Array[Repairable.Type]` in `settings.gd` and
  `settings.tres`. `Level` keeps the index and calls `win()` after the
  last item. This replaces the hard-coded test item in `Level._ready`.
- **Quality wiring:** steps 1 to 3 of the m1-quality handoff. Give
  `Repairable` a `par_time_sec` export, 90 by default. Keep the card's
  press blocking as it is; LX39 asks Levi about it.
- **CLAUDE.md:** Boot Flow step 6, Core APIs (`shake_camera`,
  `spawn_decal` and `Repairable.quality`) and Configuration
  (`item_queue`).
- **Check** with a probe that sets a two-item queue:
  1. The item lands at `%ActiveItemPosition`, straight, in
     UNDER_REPAIR, and the camera shakes.
  2. Pressing it while unfinished doesn't drag it.
  3. Finish it, by pushed presses or by finishing its points directly.
  4. Dropped elsewhere, it eases back.
  5. Dragged into the outbox by pushed presses, it leaves, the receipt
     opens with the item's score, and the next item lands 0.5 s later.
  6. A defect spawns a popup.
  7. After the second item, the game reaches CREDITS.

  m1-core's full-loop probe still passes.

Leave to Levi: the drag and tilt feel, the ticket's look and where the
outbox sits.
