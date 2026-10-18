# Phillips screwdriver: circling at speed

Ledger: **LX17** (M2). Depends on [tools.md](tools.md) (LX7) and
[screws.md](screws.md) (LX10).

Revised 2026-10-17 (Levi): the pressure is the circle speed, not
a hold and release needle. The grip meter and the cam-out stay.

## What the player does

Engage a Phillips screw and drag in circles around its head. A
gauge beside the screw shows the circle speed as a needle, the
target band in green, and the grip as a ring. Circle at a speed
inside the band and the screw turns. Too slow or too fast and it
does not turn, and the grip drains. An empty grip cams the bit
out.

## Rules

- **Circling:** the speed is how fast the drag's direction
  turns, read from recent pointer steps and never from where
  the screw sits. Any circle, neat or shaky, anywhere, turns
  its heading at the circle's own rate. Steps under 4 px do
  not count. The turning is averaged over 0.45 s and then
  smoothed over 0.5 s, so the needle has some weight.
  Dragging the wrong way reads as a negative speed.
- **The band:** 2.5 to 10 radians per second, about half a turn to
  one turn per second. Inside it the screw and the driver turn
  with the drag and the slide follows the turn, like the
  flathead. Outside it nothing turns. The band is sticky: once
  in, the speed may stray 0.8 rad/s past either end before it
  counts as out, so hovering on an edge does not flicker.
- **Grip meter:** starts at 0.4. It fills at 0.35/s while the
  speed is in the band and drains at 0.28/s while it is out,
  swinging between the two over 0.4 s, so a brief stray costs
  almost nothing. At 0 the bit cams out: the screw takes 1
  damage, the driver hops, input pauses for 0.5 s, the meter
  restarts at 0.4, and the turns so far are kept.
- **Fair start:** nothing drains for the first 0.33 s while the
  gauge scales in.
- **Done:** two full turns take the screw out. It then pulls
  out to the bench like a flathead.
- **Tutorial:** the first Phillips screw of the game never
  drains (`never_drains` on the screw).
- **Install mode:** circle the other way. The grip starts at
  0.6, and the loose turn (`LOOSE_TURN_RAD`) drives it home.

## Screw styles (later)

The band is fixed for now. A later pass can move it per screw:
a clean screw gets a wide still band, a chewed one a band that
jumps, a seized one a band that sinks as it frees up.

## Feedback

- The screw turns while the speed is in the band and stops
  while it is out.
- The needle is green in the band and red out of it. The grip
  ring around the hub shifts from red to green as it fills.
- Done: a pop from `Screw.remove()`. Cam-out: a scrape and
  sparks. Turning and creak loops wait for LX25.

## Building it

- `PhillipsScrew` ([screws.md](screws.md)) owns the microgame and
  registers as the hand's input owner, so every drag goes to it
  alone. It feeds `Screw.slide` from its turns like the flathead.
- The gauge (`PhillipsGauge`, a child of the screw scene) draws
  itself in `_draw()`: the band with `draw_arc()`, the grip ring,
  and the speed needle with `draw_line()`.
- The driver borrows the flathead driver's art for now. The
  screw's top-down head is `screwin around.png` and its
  perspective view is `screwwwzzzzzz.png`.
- When done, the tool returns to HELD. When stripped (the third
  cam-out), the tool is ejected and the screw needs the pliers.

## Tuning

In the "Phillips" group in `settings.gd`: the band is 2.5 to 10
  radians per second, the gauge tops out at 14, fill is 0.35/s,
  drain is 0.28/s, the meter starts at 0.4 (0.65 to install), the
cam-out pause is 0.5 s and the intro is 0.33 s. The smoothing
is `phillips_speed_smoothing_sec` (0.5) for the needle and
`phillips_meter_smoothing_sec` (0.4) for the grip, the sticky
band grace is `phillips_band_grace_rad_per_sec` (0.8), and steps
under `phillips_min_segment_px` (4) do not count. Turns out is
`turns_needed` on the screw (3). Each screw also has a
`difficulty` (0.5 to 2): higher narrows its band and drains
its grip faster.

## Later

- Perfect bonus: a sparkle and +2 quality when the meter never
  drained.
- A gauge built into the screwdriver's handle, like a torque
  driver.
- Upgrades: a magnetic tip widens the band.
