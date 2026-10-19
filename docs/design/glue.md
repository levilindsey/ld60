# Glue

Ledger: **LX22** (M2). Depends on [tools.md](tools.md) (LX7) and
[decals.md](decals.md) (LX13).

Built for LX22 with `glue_bottle_placeholder.png` standing in
for the bottle art. The crack is still a drawn line, not a
decal. `GrimeSpot` and `DustClump` work the same way, with
placeholder blobs until their sprites land.

## What the player does

Hold to squeeze the glue and trace along a crack. Cover the whole
crack without flooding it, then let it dry.

## Rules

- **Targets** (`Crack` points, role REPAIR): a crack is a `Path2D` (its
  `Curve2D`) drawn with a crack decal. Take sample points every 8 px
  along it, each with a `coverage` that starts at 0.
- **Squeeze:** while pressed, glue flows. Every sample within 10 px of
  the nozzle gains coverage at `flow_rate` (2.0/s). A glossy bead (a
  `Line2D`) follows the nozzle while it squeezes.
- **Covered:** once every sample reaches 1.0, the crack starts drying.
  A progress ring runs for about 3 s; then it is done, and the crack
  decal becomes a glued seam.
- **Too much:** a sample past 1.5 spawns a glue blob decal there and a
  glue blob defect (-5), once per sample.
- **Off target:** squeezing over a plain surface (or missing a broken
  point) leaves a `GlueSmear` there instead (see below).

## Broken pieces

Ledger: **LX66**. A snapped off piece is two placeable nodes.

- **The point** (`BrokenPoint`, role REPAIR): instance
  `broken_point.tscn` in a `RepairLayer` like any other point. Glue
  will not work on covered layers, as usual.
- **The piece** (`BrokenPiece`): instance `broken_piece.tscn`
  anywhere inside the repairable, apart from its point, and set its
  `target_point`. It rides in with the item. Redraw its `Art`
  polygon per piece.
- **Hidden pieces:** putting the piece on a layer under a cover
  already gates it on that cover being exposed. Setting
  `covering_layer` to the cover also hides the piece outright
  until that layer comes off.
- **Fallen pieces:** with `starts_detached` on, the piece leaves
  the item as it arrives and falls on its own to the item's landing
  spot plus `fall_target_offset`, with a random turn. It lands with
  the loose pieces' flight, bounce and skid (`Level` bench returns).
- **Reattaching:** glue the point first (`has_glue`; it survives a
  failed hold). Then drag the piece over the point. Grabbing it
  turns it to the point's rotation. Letting go on the bench can
  turn it again through the bench physics.
- **The hold:** while the piece is held near its glued point, a
  ring shows. The dot is the piece's offset from the point
  (`broken_hold_dot_scale`) plus a drift that changes direction
  every `broken_hold_drift_retarget_sec`. Fully inside the inner
  circle banks time. Straddling the wide band warns (amber) and
  pauses the timer. Past the band fails: the piece drops, the glue
  stays. `hold_sec` on the point (default 5) is the still time.

## Glue smears

- Squeezing where no crack or broken point takes the glue, over a
  surface, leaves a `GlueSmear` point (optional, not required).
- The rag wipes a smear off like grime. A cleaned smear costs
  nothing. An item that finishes with a smear still on it pays one
  glue blob defect (-5) per smear, charged as it finishes.

## Uses

- A cracked case: one that came cracked, or (Later) one the hammer
  cracked.
- A snapped plastic clip: drag the broken piece back into place (it
  sits there loosely), then glue the short seam.
- A label peeling at the corner.

## Feedback

A squelch while squeezing, a soft hiss while it dries, a ding when it
is done.

## Building it

- `Glue extends Tool`, an effect tool that calls
  `on_glued(global_position, radius, amount)` on the cracks and
  broken points under the nozzle.
- Blob checks run per sample, so penalties stay local and easy to read.
- The hold game lives in `BrokenPoint._physics_process`. The hand
  drags the piece like a loose part (`Hand.get_loose_broken_piece`),
  and `Level` bench returns fly dropped and detached pieces.
- Probe: `tests/broken_glue/` plays the test box's fallen pair end
  to end and wipes a smear.

## Later

- Touching wet glue smears it (a smear decal and a defect).
- Glue your own hammer cracks to win back half their penalty. Each
  crack decal texture would need a matching path.
- Duct tape as a fast hack: quick, ugly, lower quality.
