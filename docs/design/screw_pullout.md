# Screw pull-out: from the hole to the bench and back (LX54)

Levi's flow (2026-10-17), with his animation in
`src/interaction_points/flat_head_screw_with_slide_out_clipping.tscn`
(4e44a86). The screw has two looks: a top-down head
(`screweeeeeeeeddddddd.png`) and an angled top/side view
(`screwwwzzzzzzflat.png`). `ClippingSpace` (`clip_children`, mask
`circle-with-rectangle.png`) hides the part of the angled screw that is
still in the hole. `RemoveScrew` (0.3 s) pulls the screw out while the
top-down head squashes and fades into the angled view.

## The flow

1. Unscrewing: the twists raise the screw out of its hole (`Screw.slide`,
   0 to 1) as they do now.
2. After the last twist the screw pulls itself out: `RemoveScrew` plays
   forward from where the twists left it.
3. At its end, `ClippingSpace` hides and `UnclippedAnglePerspective`
   shows (it matches the animation's end pose). The screw slides off to
   its own rest spot on the bench.
4. It waits there while its layer is off. Once the layer is back on
   (`set_install_mode()`), a press on the resting screw sends it back
   over its hole.
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
