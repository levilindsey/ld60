# Phillips screwdriver: the pressure gauge

Ledger: **LX17** (M2). Depends on [tools.md](tools.md) (LX7) and
[screws.md](screws.md) (LX10). Based on Stardew Valley's fishing bar;
its real numbers are at the bottom.

## What the player does

Engage a Phillips screw and a round pressure gauge pops up beside it.
The needle is how hard you are pushing. Hold anywhere to push harder;
let go and the needle falls back. Keep the needle inside the green arc,
which wanders, and the grip meter fills. Fill it and the screw is out.
Let it empty and the bit cams out.

## Rules

- **Dial:** a 240 degree sweep with a stop pin at each end. The needle
  starts resting on the bottom pin.
- **Needle physics:** holding accelerates the needle up at 380
  degrees/s², and letting go accelerates it down at the same rate. Both
  are multiplied by 0.6 while the needle is inside the arc, so it calms
  down exactly when the player is succeeding. That is Stardew's hidden
  trick.
- **Pins:** the needle bounces off a pin, keeping 2/3 of its speed,
  with a clink. A press while it rests on a pin zeroes its speed, so a
  press from rest always starts clean.
- **Green arc:** 40 to 75 degrees wide. Its center moves toward random
  targets with a smoothed speed, in the screw's style (below). Cap its
  speed at about 150 degrees/s so the needle can always follow.
- **Grip meter:** starts at 0.3. It fills at 0.25/s while the needle is
  inside the arc and drains at 0.375/s while it is outside. At 1.0 the
  screw is out. At 0 the bit cams out: the screw takes 1 damage, the
  driver hops, input pauses for 0.5 s while the needle drops, and the
  meter restarts at 0.3.
- **Fair start:** the arc starts around the resting needle, and nothing
  moves for the first 0.33 s while the gauge scales in.
- **Tutorial:** the first Phillips screw of the game never drains. That
  rule teaches "hold, don't tap".
- **Install mode:** the meter starts at 0.6.

## Screw styles

| Style | How the arc moves | Used for |
|---|---|---|
| SMOOTH | A slow, steady drift between targets | A clean screw |
| MIXED | The default | A scratched screw |
| DART | Adds sudden big jumps | A chewed screw |
| SINKER | Starts high and drifts lower as it frees up | A seized screw after oiling |
| FLOATER | Drifts higher over time | A long screw |

## Feedback

- Two sound loops: a turning ratchet while inside the arc and a
  strained creak while outside. A sting the moment the needle leaves
  the arc, and a creak on every press.
- The screw turns while the needle is inside and stops while it is
  outside.
- The needle is green inside and red outside. Inside, the needle
  jitters about 1 degree ("you've got it"); outside, the arc pulses.
- The meter is a ring around the gauge's hub that shifts from red to
  green as it fills.
- Done: a pop, then the gauge shakes for 0.3 s and scales out.
  Cam-out: a scrape and sparks.

## Building it

- `PhillipsScrew` ([screws.md](screws.md)) owns the minigame and
  registers as the hand's input owner, so every press goes to it alone.
- The gauge is a `Node2D` that draws itself in `_draw()`: the dial and
  the green arc with `draw_arc()`, the meter ring, and the needle with
  `draw_line()`. Call `queue_redraw()` every frame.
- Place it about 120 px from the screw, on the side away from the tool
  body, and keep it on screen.
- Each `_physics_process`, in this order: move the arc, move the needle
  (thrust or gravity, the 0.6 factor, the pins), update the meter, then
  check for done or cam-out.
- When done, the tool returns to HELD. When stripped (the third
  cam-out), the tool is ejected and the screw needs the pliers. No
  cancel is needed.

## Tuning

| Setting | Default |
|---|---|
| `sweep_deg` | 240 |
| `needle_acceleration` | 380 degrees/s² |
| `in_arc_factor` | 0.6 |
| `pin_restitution` | 0.667 |
| `arc_width_deg` | 40 to 75, per screw |
| `arc_max_speed` | 150 degrees/s |
| `meter_start` | 0.3 |
| `fill_rate` | 0.25/s |
| `drain_rate` | 0.375/s (keep it 1.5 times the fill rate) |
| `cam_out_pause_sec` | 0.5 |
| `intro_sec` | 0.33 |

A screw with the needle held in the arc throughout takes about 2.8 s.
Stardew's rates would take 5.8 s, too slow with four or more screws
per item.

## Stardew's numbers, for reference

From the decompiled `BobberBar.cs`, at 60 ticks per second:
- thrust and gravity are both 0.25 px/tick² on a 568 px track (about
  1.6 track heights per second²), with no speed cap;
- both are multiplied by 0.6 while on target, and the walls bounce at
  2/3 of the speed;
- the meter starts at 0.3, fills 0.002 per tick (0.12/s) and drains
  0.003 per tick (0.18/s);
- the bar is 17% of the track, growing to 31% with upgrades;
- the first fish ever starts at 0.1 and never drains.

Sources: the decompiled BobberBar.cs (github.com/veywrn/StardewValley)
and wiki.stardewvalley.net/Fishing.

## Later

- Perfect bonus: a sparkle and +2 quality when the meter never drained.
- A gauge built into the screwdriver's handle, like a torque driver.
- Upgrades: a magnetic tip widens the arc.
- A side goal: a glint on the dial to hold the needle on for a bonus.
