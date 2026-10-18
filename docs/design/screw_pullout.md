# Screw pull-out: from the hole to the bench and back (LX54)

Levi's flow (2026-10-17), with his animation in
`src/interaction_points/flat_head_screw_with_slide_out_clipping.tscn`
(4e44a86). The screw has two looks: a top-down head
(`screweeeeeeeeddddddd.png`) and an angled top/side view
(`screwwwzzzzzzflat.png`). `ClippingSpace` (`clip_children`, mask
`circle-with-rectangle.png`) hides the part of the angled screw that is
still in the hole. `RemoveScrew` (0.3 s) pulls the screw out while the
top-down head squashes and fades into the angled view.

## Amendment (2026-10-18, bench drag stage 1)

Levi replaced the automatic travel below with dragging. Steps 3
and 4 now read: at the end of the pull-out the screw comes to rest
where it landed and does not slide to a rest spot, and there is no
press to send it back. The player drags resting screws and loose
layers anywhere inside the level's bench polygon (`Level.bench_
polygon`); a drag that leaves the bench drops the piece at the
edge. When the layer is back on, dropping a screw within
`screw_seat_snap_px` of its hole seats it: it arcs down into the
hole from above (`screw_seat_arc_px`). Since LX64 the hole need
not be its own: any empty hole of the same type on its layer
seats it, and the two screws trade holes. The twists also raise the
head twice as far (the `RemoveScrew` first key doubled, about
12 px). The rest-spot row is unused. Stage 2 (rolling set-down,
shadows, overlap-aware draw order, drawer parts on the bench) is
LX60.

## The flow

1. Unscrewing: the twists raise the screw out of its hole (`Screw.slide`,
   0 to 1) as they do now.
2. After the last twist the screw pulls itself out: `RemoveScrew` plays
   forward from where the twists left it.
3. At its end, `ClippingSpace` hides and `UnclippedAnglePerspective`
   shows (it matches the animation's end pose). The screw slides off to
   its own rest spot on the bench, turning to a fresh random angle as
   it goes.
4. It waits there while its layer is off. Once the layer is back on
   (`set_install_mode()`), a press on the resting screw sends it back
   over its hole, turning back to its home turn on the way.
5. There the sprites swap back and `RemoveScrew` plays backwards: the
   screw sinks into the hole and turns back into the top-down head.
6. It now sits loose in its hole, raised (`slide` 1) and turned back
   (`LOOSE_TURN_RAD`), and the install microgame threads it in as today.

This replaces today's `_hop_off()` (hop, fade, hide) and the snap back
into the hole in `set_install_mode()`.

## Decisions

Taken by the coordinator. Levi may still change them.

- **Height.** `RemoveScrew` raises `PositioningWrapper` 230 units, which
  is 21.6 px under `ClippingSpace`'s 0.094 scale. The twists keep their
  6 px and do it inside the clip space: they move the wrapper from home
  to `RemoveScrew`'s first key. That key becomes the backed-out pose
  (about -64 units) instead of 0. The pull-out then starts where the
  twists stop and ends where Levi put it. Read the twist height from that
  key, so there is one number to tune in the animation editor, and drop
  `screw_slide_px`.
- **What moves.** The root stays at the hole. It carries `Hole` and the
  clip mask, which belong to the layer and go wherever it goes. The slide
  moves the screw's art and its hit shape.
- **The rest spot.** Each removed screw takes its own spot in a row on
  the bench, in removal order, clear of the set-aside spot, the rack and
  the item. The spots and the travel time are settings in their own
  `@export_group`. The resting screw stays on the bench when its layer
  lifts off (`RepairLayer.lift_off()` reparents the layer to
  `G.level.get_set_aside_spot()`), so reparent its art or make it
  `top_level`. It draws above the bench and the item, below a held tool.
- **The press.** A press on a resting screw brings it back whatever the
  hand holds, but only once its layer is back on. Before that it does
  nothing. The set-aside layer is the precedent: `RepairLayer.has_point()`
  and the hand's `_press_set_aside_layer()`. The screw can't be engaged
  until it has sunk into its hole.
- **The pry.** The stand-in pry (`_pry()` calls `remove()`) uses the same
  pull-out.
- **One scene.** Fold Levi's nodes into `flat_head_screw.tscn`, keeping
  its uid (`settings.tres` and `test_flat_head_screw_repairable.tscn`
  reference it), then delete the copy.
- **RESET.** It keys `PositioningWrapper` at -230 (pulled out), and the
  saved node sits there too, while `RemoveScrew` starts it at 0. Both
  must be the fully-in pose, or an idle screw floats 21.6 px above its
  hole.
- **The head.** `head` points at the old polygon `Head` (Disc, Slot). It
  must be the top-down art, so the twists turn it. `RemoveScrew` squashes
  `TopDownHead` vertically, so the turn goes on a child sprite, and the
  squash and the fade stay on `TopDownHead`. The polygon head goes. The
  rust overlay and the damage tint move to the new head (placeholders
  until LX24).
- **Upright.** A screw node's own rotation only sets its slot angle. Move
  it onto the head in `_ready()`, so the art and the slide stay upright in
  the parent's frame (the 33-degree check).
- **Timing.** Physics interpolation is on. Run the AnimationPlayer and the
  tweens in physics process, and call `reset_physics_interpolation()`
  after a jump.
- **Reuse.** The Phillips screw (LX17) gets the same flow with its own
  art, so the mechanics live in `screw.gd` and the nodes are exports.

## To settle in the code

- `remove()` calls `finish()` and emits `removed` before anything moves,
  so the layer could lift off while its screw is still pulling out.
  Decide whether the layer waits for the pull-out.
- `ClippingSpace` has `clip_children = 2`, which draws the mask texture as
  well as clipping to it. Check whether the mask shows; `1` only clips.
- How a resting screw shows it can be pressed (a pulse like the layers'
  glow, or nothing).

## Done means

- `scripts/check.ps1 -Tests` passes. The probes that drive install mode
  (check `full_loop`, `item_flow` and `screws`) press the resting screw
  first, and the slide checks read the art, not the root.
- New checks go in their own script under `tests/screws/`, since
  `probe.gd` is 933 lines. They cover each step in turn:
  - the pull-out plays after the last twist, and the sprites swap at its
    end;
  - the screw reaches its rest spot and stays there when its layer lifts;
  - a press does nothing before install mode and brings the screw back
    after it;
  - the reverse plays, and the screw ends at its hole with the clip space
    shown and `slide` 1;
  - the install microgame ends at home.

  Break each step once and see a check fail.
- A few short windowed runs save frames of the pull-out, the trip and the
  return to `.claude/probes/LX54/`. Look for a pop at the swap, and check
  how the 6 px slide looks inside the clip space.
- `docs/design/screws.md` (Removal, Install mode) and
  `docs/design/flathead.md` describe the new flow.

## Brief for the agent

- Work on branch `lx54-pullout` (`git switch -c lx54-pullout` in your
  worktree). Commit WIP at every milestone, broken or not. Never push.
  Don't edit `LEDGER.md`.
- Shared files: `flat_head_screw.tscn` and the copy are yours for this.
  Touch `level.tscn` only if there is no other way. In `settings.gd` use
  your own group, and in `settings.tres` add only your own lines.
- Stop when this is done or after 2 hours (`Get-Date` at the start and at
  each milestone), whichever comes first. Then commit WIP, append a
  handoff below, and report. A compaction is not a stop: after one,
  re-read this brief and `git log`.
- Report: the commits, the checks and their results, what you could not
  check (feel, mouse, touch), and a `Ledger items` list.

## Handoff

2026-10-17, agent `screw-pullout` on branch `lx54-pullout`: done, in
about 1.5 hours.

- **Commits.** `aff4ab4` folds the scene into `flat_head_screw.tscn` and
  builds the pull-out in `screw.gd`, the rest spots in `level.gd` and
  the hand's hook. `da99453` makes the probes press the resting screw
  back and adds the new checks (`tests/screws/pull_out_recorder.gd`).
  `0c2a0fb` makes the no-pop check compare scale and turn too. The docs
  and this handoff come last.
- **Settled in the code.**
  - The layer waits for the pull-out. `remove()` still emits `removed`
    as the pull-out starts, but the screw stays ACTIVE until
    `_leave_hole()` calls `finish()`.
  - `ClippingSpace` has `clip_children = 1`: it clips, and its mask
    doesn't show.
  - A resting screw in install mode glows (a looped tween on
    `bench_art.modulate`), and `pulse()` scales it once when the item
    shows what still needs work.
- **Checks.** `scripts/check.ps1 -Tests` passes: full_loop 76,
  full_loop_booklet 6, item_flow 72, screws 178. Each step was broken
  once in `screw.gd` (`.claude/probes/LX54/break_checks.ps1`, results in
  `break_results_1.md` and `break_results.md`), and checks failed every
  time: the swap (7), a 1.1x pop (3), the rest spot (6), the press gate
  (3), the reverse slide (16) and install ending off home (4).
- **Frames.** A windowed full_loop run with `capture_frames.diff`
  applied saved crops to `.claude/probes/LX54/frames/`, and
  `contact_sheet.ps1` tiled them into `sheet_out.png`, `sheet_back.png`
  and `sheet_wide.png`. Neither swap pops. The twists raise the head
  about 5 px between `slide` 0.17 and 0.99, as expected (6 px at 1), and
  the clip space hides the shank below the hole. At the swap the bench
  art's home is 0.078 px from the side view's end, at a scale ratio of
  1.0013 and no turn.
- **Not checked** (needs a person): the feel and ease of the trip, how
  the glow looks, the bench art's draw order against a held tool and the
  set-aside cover, where the rest spots sit on screen, sound and touch.
- **Open.**
  - `tests/screws/probe.gd` is 998 lines, just under gdlint's 1000.
    Split it before adding checks.
  - The rest spots are placeholders and may collide with the parts
    drawer (LX15) or the rack.
  - The LX15 rebase meets this branch in `hand.gd` (the resting-screw
    press comes first in `_handle_press`, plus a line in `_can_take`),
    `level.gd` (the rest-spot functions) and `settings.gd` (the "Screw
    rest" group, and `screw_slide_px` is gone).
  - Optional: pose the bench art exactly like `RemoveScrew`'s last frame
    to remove the 0.078 px and 1.0013 residual.
