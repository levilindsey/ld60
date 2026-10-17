# Pliers

Ledger: **LX19** (M2). Depends on [screws.md](screws.md) (LX10) and
[decals.md](decals.md) (LX13). Shares the wiggle helper with
[parts_bin.md](parts_bin.md).

## What the player does

When a screw strips, its screwdriver is useless. Grab the pliers,
clamp the screw head and wiggle it out. It always works, and it always
leaves scratches.

## Rules

- The pliers accept only stripped screws (health 0). On any other
  screw: the "nope" shake. Open question: allow the pliers on any screw
  as a costly shortcut.
- **Clamp:** press with the jaws over the head. The jaws close with a
  crunch and the tool goes IN_USE.
- **Wiggle:** drag side to side. A swing counts when the drag reverses
  after moving at least 12 px. After 4 swings the screw pops out. The
  pliers and the screw rock about 10 degrees with each swing.
- **Damage:** every pliers removal spawns 2 or 3 gouge decals around
  the hole and records a pliers scratch defect
  ([quality.md](quality.md)).
- The screw is scrap and drops off the bench. Reassembly needs a new
  screw from the parts bin ([screws.md](screws.md) "Install mode").

## Feedback

A metal creak per swing, a rising squeal, then a pop and a clatter as
the screw comes out.

## Building it

- `Pliers extends Tool`, an engage tool. `Screw` accepts
  `Tool.Type.PLIERS` only while it is stripped, and runs the clamp and
  the wiggle itself.
- `Wiggle`, a small `RefCounted` shared with the parts bin: feed it the
  drag deltas, and it counts reversals over a minimum distance and
  reports the rocking angle.

## Later

- Straighten bent pins one at a time (a console's cartridge slot).
- Pull out a seized part that the hand can't wiggle loose.
