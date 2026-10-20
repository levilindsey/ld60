# Phillips screwdriver: circling at speed

Ledger: **LX17** (M2). Depends on [tools.md](tools.md) (LX7) and
[screws.md](screws.md) (LX10).

Revised 2026-10-17 (Levi): the pressure is the circle speed, not
a hold and release needle. The grip meter and the cam-out stay.

## What the player does

Engage a Phillips screw and drag in circles around its head. A
gauge beside the screw shows the circle speed as a needle, the
target zone in green, and the grip as a ring. The green zone
keeps sliding counter-clockwise around the gauge at an ever
changing pace, like tracking the fish in Stardew Valley's
fishing game: keep speeding the drag up and slowing it down so
the needle stays in the green. Circle at a speed inside the
zone and the screw turns. Too slow or too fast and it does not
turn, and the grip drains. An empty grip cams the bit out.

## Rules

- **Circling:** the speed is how fast the drag's direction
  turns, read from recent pointer steps and never from where
  the screw sits. Any circle, neat or shaky, anywhere, turns
  its heading at the circle's own rate. Steps under 4 px do
  not count. The turning is averaged over 0.45 s and then
  smoothed over 0.65 s, so the needle has some weight.
  Dragging the wrong way reads as a negative speed.
- **The zone:** 3.5 radians per second wide. It starts centered on
  6.25 rad/s, where the old fixed band sat, then its center
  climbs at a pace that eases toward a fresh random target
  between 0.8 and 2.2 rad/s per second, picked every 1.2 to
  2.6 s. On the gauge, climbing speed reads as the green arc
  sliding counter-clockwise around the dial's full circle:
  zero sits at the bottom seam, and the arc travels up the
  right side, over the top, down the left and through the seam
  without ever jumping. It never reverses direction mid-game.
  (Tightening mirrors the whole gauge, so there it slides
  clockwise.) Inside the zone the screw and
  the driver turn with the drag and the slide follows the turn,
  like the flathead. Progress counts only at the window's own
  edges: there is no grace past them, and outside it nothing
  turns. The check is the dial itself: the needle draws wrapped
  past the top of the sweep, and a speed is in the zone when
  where its needle sits is in the green, one wrap or not. The
  drawn green never covers speeds below the slowest turning
  speed (2.5 rad/s): sitting or creeping there turns nothing,
  and the green no longer claims otherwise.
- **Getting started:** the microgame only starts once the
  drags add up to 1.5 radians of turning. Before that the grip
  and the screw hold still: sitting with the driver seated,
  lining up the first circle, costs nothing.
- **Grip meter:** starts full. It is only the time left before
  the bit strips or slips out, never progress toward done. It
  refills at 0.35/s while the speed is in the zone and drains
  at 0.28/s while it is out. The needle carries the gauge's
  only momentum: the frame the needle enters the green, the
  grip starts refilling, and the frame it leaves, the grip
  starts draining. At 0 the bit
  cams out: the screw takes 1 damage, the driver hops, input
  pauses for 0.5 s, the meter restarts full, and the turns so
  far are kept.
- **Fair start:** nothing drains for the first 0.33 s while the
  gauge scales in.
- **Done:** 4.8 full turns take the screw out (1.6x the old three). It then pulls
  out to the bench like a flathead.
- **Tutorial:** the first Phillips screw of the game never
  drains (`never_drains` on the screw).
- **Install mode:** circle the other way. The grip starts
  full, and the loose turn (`LOOSE_TURN_RAD`) drives it home.

## Screw styles (later)

Every screw's zone slides the same way for now. A later pass can
vary the motion per screw: a clean screw gets a wide slow zone, a
chewed one a zone that jumps, a seized one a zone that slows as
it frees up.

## Feedback

- The screw turns while the speed is in the zone and stops
  while it is out.
- The needle is green in the zone and red out of it. Coming out,
  the gauge sweep runs the full circle counter-clockwise from
  the seam at the bottom, so faster circling swings the needle
  up the right side and over the top. Tightening mirrors it:
  the drag circles clockwise, the screw turns clockwise, and the
  gauge sweeps clockwise to match. The grip
  ring around the hub shifts from red to green as it fills.
- The gauge's face never tints for progress. It stays plain
  until the grip falls below 0.55, then reddens, reaching its
  fullest red at 0.15, a little before the bit slips out.
- The driver's twisting animation plays only while the screw
  is actually making progress: not while seated idle, and not
  while circling outside the window.
- Done: a pop from `Screw.remove()`. Cam-out: a scrape and
  sparks. Turning and creak loops wait for LX25.

## Building it

- `PhillipsScrew` ([screws.md](screws.md)) owns the microgame and
  registers as the hand's input owner, so every drag goes to it
  alone. It feeds `Screw.slide` from its turns like the flathead.
- The gauge (`PhillipsGauge`, a child of the screw scene) draws
  itself in `_draw()`: the zone with `draw_arc()`, the grip ring,
  and the speed needle with `draw_line()`. The screw moves the
  zone in `_update_zone()`; the gauge only reads its center,
  width and grip.
- The driver borrows the flathead driver's art for now. The
  screw's top-down head is `screwin around.png` and its
  perspective view is `screwwwzzzzzz.png`.
- When done, the tool returns to HELD. When stripped (the third
  cam-out), the tool is ejected and the screw needs the pliers.

## Tuning

In the "Phillips" group in `settings.gd`: the zone starts
centered between `phillips_speed_min_rad_per_sec` (2.5) and
`phillips_speed_max_rad_per_sec` (10), is
`phillips_zone_width_rad_per_sec` (3.5) wide, and climbs at a pace
easing between `phillips_zone_move_min_rad_per_sec` (0.8) and
`phillips_zone_move_max_rad_per_sec` (2.2), retargeted every
`phillips_zone_retarget_min_sec` to `phillips_zone_retarget_max_sec`
(1.2 to 2.6 s). The gauge tops out at 14, fill is 0.35/s, drain
is 0.28/s, the meter starts full for removal and install, and
the face starts reddening below `phillips_failure_tint_start`
(0.55) and is fully red by `phillips_failure_tint_full` (0.15). The cam-out pause is 0.5 s and the intro is 0.33 s; the
microgame starts after `phillips_start_drag_rad` (1.5) of
dragged turning. The smoothing
is `phillips_speed_smoothing_sec` (0.65), for the needle alone,
and steps
under `phillips_min_segment_px` (4) do not count. Turns out is
`turns_needed` on the screw (4.8). Each screw also has a
`difficulty` (0.5 to 2): higher narrows its zone, slides it
faster and drains its grip faster.

## Later

- Perfect bonus: a sparkle and +2 quality when the meter never
  drained.
- A gauge built into the screwdriver's handle, like a torque
  driver.
- Upgrades: a magnetic tip widens the zone.
