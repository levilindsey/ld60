# Hammer

Ledger: **LX18** (M2). Depends on [tools.md](tools.md) (LX7, for the
reticle and the hand's cursor), [decals.md](decals.md) (LX13) and
[quality.md](quality.md) (LX12). Art exists in `assets/images/`:
`hammertime.png` (a claw hammer) and `bestrongandhitstuff.png` (a
mallet).

There are no nails. The hammer is for percussive maintenance and for
knocking things back into place.

## What it is for

1. **Jog or unstick.** A stuck relay, a jammed toaster lever, a frozen
   clock, a flickering CRT. Hit near the problem with the right
   strength, a few times. Each good hit reduces the symptom (the
   flicker slows, the lever twitches) until it frees up. This is a
   `StuckPart` point, with `hits_needed` of 2 or 3 and a generous
   radius of about 60 px.
2. **Realign a bent part.** A bell clapper, a typebar, a fin, a bent
   bracket: the same sprite, rotated or shifted out of place. Each good
   hit removes 30% to 60% of the error, more for harder hits within
   the band. Too hard overshoots: the error flips to the other side
   (now hit it from there) and the part gets a dent. This is a
   `BentPart` point with `error_deg` or `error_px`, done when the error
   is under a small threshold.
3. **Reseat.** A half-out card, a tube or a chip: each good hit pushes
   it about halfway home along its slot. Too hard seats it fully but
   cracks the board. This is a `SeatPart` point.

## Strength bands

Each target sets a band (`band_min` and `band_max`, as a charge from 0
to 1):
- **Below the band:** a "tink". Harmless, but no progress.
- **In the band:** progress, a thunk, a 60 ms freeze of the hammer and
  the target (hit-stop), and `G.level.shake_camera(4, 0.15)` (LX9 adds
  that method; [outbox.md](outbox.md) "Arrival").
- **Above the band:** progress, plus a dent or crack decal at the
  strike point and a defect.
- **Far above** (a full swing at a delicate target): a large crack and
  a big defect. Still never unwinnable: the item still works.

A strike that lands on no target hits whatever `Surface` is there.
Light hits are harmless. Hits above the surface's threshold dent METAL
and crack PLASTIC or GLASS.

## Input

- **Hover:** the hammer's head follows the cursor. Put
  `cursor_position` on the striking face, which is how HELD already
  works. A small crosshair is drawn at the strike point above
  everything, because the head covers the target.
- **Press:** locks the strike point and starts the wind-up. The
  strike point is the hammer's `InteractionArea` position when the
  press triggers, not the cursor, and the smack lands where the
  working end is as the swing lands. A strength
  ring around the crosshair fills over `charge_sec` (1.2) with
  ease-in-out. Over a target, the ring shows the target's band in
  green. Over a bare surface, it shows in red where damage starts. The
  controls are never the puzzle.
- **Holding at full:** the ring trembles and stays at maximum.
- **Release:** swing with the current charge.
- **Touch:** the same events, since touching down is the press. Draw a
  bigger ring (about 64 px across instead of 40) so it shows around the
  finger.

Ease-in-out moves slowly near the ends and fast through the middle, so
a gentle tap and a full swing are easy, and a medium band is hard. Use
that on purpose: early targets get wide bands or bands at the ends,
later ones get narrow middle bands.

## Animation

- The hammer pivots around a point near the end of its handle.
- **Wind-up:** rotate back by up to about 70 degrees times the charge.
  The head scales up to 1.15 as if lifting toward the camera, and a
  shadow under it grows and fades.
- **Swing:** a fast ease-in (about 0.08 s) down to the strike point.
- **Impact:** the hit-stop, sparks or a dust puff, and the target's
  reaction. Every hit squishes the piece, dent or not: a quick
  squash that springs back over `hammer_squish_recover_sec` (0.3),
  like the radio's bonk. The charge scales the squash from a
  small share of `hammer_squish_amount` (0.12 of its height,
  spreading half as much sideways) for a tap up to the full
  amount for a denting hit.
- **Recoil:** bounce up about 10 degrees and settle (0.2 s). Then the
  follow offset eases the hammer back under the cursor.

## Building it

- `Hammer extends Tool`, an effect tool. It registers as the hand's
  input owner from the press until the recoil ends. Built for
  LX18 with `StuckPart`, `BentPart` and `SeatPart` on one
  `StrikablePoint` base. Dent and crack decals landed in LX58:
  an over hard hit stamps a fitted dent or crack on the part
  (see [decals.md](decals.md) "Fitted spawns").
- On impact it calls `on_struck(global_position, charge)` on the
  topmost target under the strike point: a point if there is one, else
  a surface.
- The ring can reuse the Phillips gauge's drawing code (`draw_arc()`).

## Tuning

| Setting | Default |
|---|---|
| `charge_sec` | 1.2 |
| `max_windup_deg` | 70 |
| `swing_sec` | 0.08 |
| `hit_stop_sec` | 0.06 |
| `reticle_radius_px` | 40, or 64 after touch input |
| Band per target | For example 0.45 to 0.75 for a stuck relay, 0.15 to 0.35 for a CRT |

## Later

- **A charge that sweeps back:** on later items, the charge falls again
  after reaching full, like a golf power meter.
- **The mallet** (art exists): a second hammer that never dents but
  can't reach high bands.
- **Bent parts care where you hit:** a hit only pushes the right way if
  it lands on the high side of the bend.
- **Thumb gag:** a big miss hits your own thumb, with a red flash and
  an "OW".
