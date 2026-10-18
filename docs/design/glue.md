# Glue

Ledger: **LX22** (M2). Depends on [tools.md](tools.md) (LX7) and
[decals.md](decals.md) (LX13).

Planned ahead (2026-10-17): `Tool.Type.GLUE`,
`InteractionPoint.Type.CRACK` and the "Glue" tuning group in
`settings.gd` are registered, with no scene assigned. The tool
and the `Crack` point land when the glue bottle sprite and the
crack art arrive. `GrimeSpot` and `DustClump` already work the
same way, with placeholder blobs until their sprites land.

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
- **Off target:** squeezing over a plain surface leaves a blob too.

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
  `on_glued(global_position, radius, amount)` on the cracks under the
  nozzle.
- Blob checks run per sample, so penalties stay local and easy to read.

## Later

- Touching wet glue smears it (a smear decal and a defect).
- Glue your own hammer cracks to win back half their penalty. Each
  crack decal texture would need a matching path.
- Duct tape as a fast hack: quick, ugly, lower quality.
