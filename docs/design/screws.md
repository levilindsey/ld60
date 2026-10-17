# Screws

Ledger: **LX10** (M1). Depends on [repairables.md](repairables.md)
(LX8). Used by [flathead.md](flathead.md), [phillips.md](phillips.md),
[pliers.md](pliers.md) and [oil_can.md](oil_can.md).

## Health

- Every screw has `max_health` (default 3) and loses 1 per slip: a
  flathead unseat or a Phillips cam-out.
- The head art shows its health, with four frames per screw type:

| Health | State | Look |
|---|---|---|
| 3 | Clean | A crisp slot or cross |
| 2 | Scratched | Bright scratches on the head |
| 1 | Chewed | The edges of the slot or cross rounded and torn |
| 0 | Stripped | The head chewed out; the slot is barely there |

- **Stripped:** its screwdriver no longer bites. Trying plays a
  grinding slip and the "nope" shake. Only the pliers work now
  ([pliers.md](pliers.md)).
- Each damage point, and the strip itself, is a defect
  ([quality.md](quality.md)).
- Damage also makes the Phillips gauge harder ([phillips.md](phillips.md)
  "Screw styles").

## Seized (rusted) screws

- `is_seized = true` adds a rust overlay on the head and a rust streak
  running down from the hole, so it can be seen before trying.
- A seized screw won't turn. The first try only grinds as a warning:
  the driver judders, the flathead twist stalls, the Phillips needle
  hits the stop. Each stalled try after that costs 1 damage.
- **Fix:** 2 drops from the oil can, then about 2 s of fizzing
  ([oil_can.md](oil_can.md)). After that it turns normally.

## Removal

- A turning screw rotates with its driver. It never scales: not as it
  comes loose, and not when it sits loose (Levi, 2026-10-17).
- **It slides as it turns.** The screw also slides up the screen out of
  its hole as it turns out, and back down as it turns in (Levi,
  2026-10-17). `Screw.slide` is the fraction, 0 at home and 1 all the
  way out, and the whole screw (head, slot, damage frames, rust and hit
  shape) sits `screw_slide_px` (6, "Screw slide" in settings) times that
  far up from home. It is always up the screen, even if a screw node is
  turned in its scene. A screw type feeds `slide` from its own turn:
  the flathead raises it by an even share per twist, eased like the
  head's turn, so it is fully out at the end of its last twist and never
  moves in the pause between twists. An unseat leaves it where it is,
  with its twists. The Phillips screw feeds it the same way.
- When a screw finishes, it backs out: it turns loose, then hops off
  and disappears (MVP) or flies into a screw dish (Later).
- The hole stays, as part of the layer art or as a hole decal.

## Install mode (putting it back)

- When a layer goes back on, its screws reappear loose in their holes,
  in INSTALL mode, turned back and slid all the way out (`slide` 1).
  Driving one in slides it back down, to exactly home on its last
  twist.
- The same microgame, shorter: the flathead needs `install_twists` (2),
  and the Phillips meter starts at 0.6. Damage can still happen.
- A screw that was pulled with pliers is scrap. Its hole shows empty;
  drag a new screw from the parts bin onto it, then drive it in.

## Building it

- Today `flat_head_screw.gd` declares `class_name Screw`. Split it into
  `screw.gd` (`Screw`, the shared base) and `flat_head_screw.gd`
  (`FlatHeadScrew extends Screw`). Add `phillips_screw.gd`
  (`PhillipsScrew extends Screw`) in M2.
- `Screw` holds `max_health`, `health`, `is_seized`, `is_install_mode`
  and the head `AnimatedSprite2D` (one animation frame per state, set
  up in the scene), plus `take_damage()`, `remove()` and `install()`.
- Signals: `damaged(health: int)`, `stripped`, `removed`, `installed`.
- Every screw is a FASTENER ([repairables.md](repairables.md)).

## Later

- **Security screws** (the handheld console): an odd head that needs a
  special bit from the parts bin.
- **Screw map:** screws of different lengths have to go back into their
  own holes ([overview.md](overview.md) "Depth").
- **Magnetic dish** for removed screws.
