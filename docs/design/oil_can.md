# Oil can

Ledger: **LX21** (M2). Depends on [tools.md](tools.md) (LX7),
[repairables.md](repairables.md) (LX8) and [decals.md](decals.md)
(LX13). Works with [screws.md](screws.md) (seized screws) and
[canned_air.md](canned_air.md) (fans).

## How the player knows oil is needed

- **A squeak:** a dry mechanism squeaks and moves in jerks whenever it
  moves: when poked with an empty hand, blown on with canned air, or
  run during a test. Small motion lines at the joint help.
- **A look:** a dry, rusty bloom at the pivot.
- **A seized screw:** rust on its head, and it won't turn.
- **The ticket:** "the dial sticks".

## Applying it

- The spout's tip is the cursor point, and a crosshair marks where a
  drop will land.
- **Press:** one drop. **Hold:** more drops, faster and faster (every
  0.4 s at first, down to every 0.15 s). Tapping is precise; holding is
  easy to overdo.
- A drop falls in a short arc (about 0.25 s) and lands just below the
  spout.
- **On a pivot** (`OilPivot` point, role REPAIR, about 24 px radius):
  it counts. The pivot needs `drops_needed` (2 or 3). Then it works
  itself in: a few jerky moves that get smoother while the squeak
  fades, and it is done.
- **On a seized screw:** 2 drops, then 2 s of fizzing, and then it
  turns ([screws.md](screws.md)).

## Misapplying it

| Mistake | Result | Cost |
|---|---|---|
| More than `drops_needed` + 1 on a pivot | Oil runs down: a drip decal | An oil drip defect (-4), once per pivot |
| A drop off target, on the case or a board | A stain decal | An oil drip defect (-4) |
| A drop on CONTACTS, a CIRCUIT_BOARD or RUBBER (a belt, a pinch roller) | A sheen decal, plus a new required point: wipe it off with the rag | An oil drip defect (-4), plus the time |
| Oil on a dusty pivot (Later) | The dust turns to gunk that needs the rag first | Time |

## Feedback

A squelch per squeeze, a plop as a drop lands, and the squeak fading as
the oil works in.

## Building it

- `OilCan extends Tool`, an effect tool. Each drop is a small node that
  falls, then asks what is under its landing point: an `OilPivot` or a
  seized `Screw` first, then a `Surface` (a stain, or contamination for
  the sensitive materials), and otherwise a plain stain.
- `OilPivot` implements `on_poked()` (it squeaks and jerks while dry),
  `on_sprayed()` (a dry fan squeaks) and `on_oiled()`.

## Later

- Work the oil in by hand: wiggle the mechanism ([parts_bin.md](parts_bin.md)
  "Getting the old part out: wiggle").
- Two cans: penetrating oil for rust, light oil for pivots.
