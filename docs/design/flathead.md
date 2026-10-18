# Flathead screwdriver

Ledger: **LX11** (M1). Depends on [tools.md](tools.md) (LX7) and
[screws.md](screws.md) (LX10). The tool exists:
`src/tools/flat_head_screw_driver.gd`.

## What the player does

Hold the tip over a flathead screw and press. The driver turns the
screw by itself in slow twists, and with each twist the tip drifts
along the slot. The player moves the cursor along the slot to keep the
tip centered. If it drifts off the end of the slot, the tip pops out.

## Rules

- **Start:** press with the tip over the screw. On touch, tap the screw
  ([tools.md](tools.md) "Routing a press"). The tool goes IN_USE.
- **Twist cycle:** a twist turns the screw, and the tool with it, by
  `twist_angle_deg` (90) over `twist_duration_sec` (0.85) with
  ease-in-out. Then comes a pause of `pause_sec` (0.35) with no drift,
  which is the window to recenter.
- **Drift:** the tip sits at `screw_center + slot_axis * offset`.
  `slot_axis` turns with the screw, and `offset` is a distance along
  the slot. Each twist picks a drift and eases it in over the whole
  twist, so it is never sudden:

  ```
  drift = sign * randf_range(0.35, 0.85) * seat_tolerance_px
  ```

  - Each screw picks its drift direction at random. `sign` follows
    that direction with probability `slip_bias` (0.9), else it goes
    the other way.
  - `seat_tolerance_px` is how far the tip can move from the center
    before it leaves the slot, about half the slot's length.
- **One twist can never unseat it.** The largest drift is 0.85 of the
  tolerance, so it takes at least two twists the same way. A player who
  never corrects should still usually lose the tip before the screw is
  out, which is why drifts mostly keep going one way ("Tuning").
- **Correcting:** mouse motion along the slot moves the tip,
  `offset += event.relative.dot(slot_axis)`. At rest (the pause) it
  stops at the slot's ends (`-seat_tolerance_px` to
  `seat_tolerance_px`). While the screw is turning it may be pushed
  past the end. Motion across the slot is ignored. On touch, the
  player drags a finger, and the motion is multiplied by
  `flathead_touch_gain` (2.0), so a finger travels half as far as
  the tip. The mouse stays 1 to 1 (LX47, Levi 2026-10-17).
- **Unseat:** only during a twist, when the drift or the player's
  push takes `abs(offset) > seat_tolerance_px`, the tip skids out.
  At rest the player's push stops at the end and can never skid it
  (LX47, Levi 2026-10-17). The screw takes 1 damage, a skid
  scratch decal appears where the tip left, and the tool returns to
  HELD, with the follow offset easing it back under the cursor.
  Twists done so far are kept. Press again to re-engage.
- **Done:** after `twists_needed` (default 4) twists the screw is out,
  and the tool returns to HELD.
- **Install mode:** `install_twists` (2), turning the other way.

Making the screw start over instead (Levi's first idea) is a one-line
change: reset the twist count on unseat. LX6 kept the default.

## Feedback

- **Telegraph:** about 150 ms before each twist, a creak, and the
  handle tenses (a small squash). Recentering becomes rhythm instead of
  reaction.
- **Danger:** as `abs(offset)` nears the tolerance, a scraping sound
  rises in pitch and the tip shakes a little.
- **Turning:** a ratchet tick per twist, and the screw turns with the
  tool. It rotates and never scales, and it slides up the screen as it
  turns out ([screws.md](screws.md) "Removal").
- **Unseat:** a skid sound, sparks at the tip, and the tool hops.
- **Done:** a pop, then the screw pulls itself out of its hole and slides
  to its rest spot on the bench ([screws.md](screws.md) "Removal").

## Building it

- `FlatHeadScrew` ([screws.md](screws.md)) runs the cycle in
  `_physics_process` and places the tool every frame. The tool only
  supplies its tip (`cursor_position`).
- Showing the twist: rotate the whole tool around its tip by the twist
  angle. That is simple and matches "the screw rotates to match the
  screwdriver". If it looks odd with the side-on art, keep the tool's
  angle and animate only the handle.
- `FlatHeadScrewDriver.in_use_angle_deg` (125) becomes the starting
  angle, and each twist adds to it.
- Mouse deltas: with no camera zoom, `event.relative` is already in
  world units. Check on a phone that touch drags give sensible
  `relative` values.

## Tuning

| Setting | Default | Where |
|---|---|---|
| `twist_duration_sec` | 0.85 | settings, "Flathead" group |
| `twist_angle_deg` | 90 | settings |
| `pause_sec` | 0.35 | settings |
| `telegraph_sec` | 0.15 | settings |
| `slip_min`, `slip_max` | 0.35, 0.85 (keep `slip_max` under 1) | settings |
| `flathead_touch_gain` | 2.0 | settings, "Flathead" group |
| `seat_tolerance_px` | 9 | per screw |
| `slip_bias` | 0.9 | per screw |
| `twists_needed` | 4 | per screw |
| `difficulty` | 1 (0.5 to 2, tightens the slot) | per screw |
| `resume_delay_sec` | 0.12 (first twist after a re-engage with kept twists) | settings |
| `install_twists` | 2 | per screw |
| slide height | about 6 px | first key of `RemoveScrew`, in the screw scene |
| `screw_travel_sec` | 0.4 | settings, "Screw rest" group |

What `slip_bias` does to a player who never corrects, from a million
simulated screws using the drift formula above:

| `slip_bias` | Median twists to unseat | Unseats on twist 2 | Unseats within 4 twists |
|---|---|---|---|
| 0.5 | 4 | 40.9% | 66.3% |
| 0.8 | 2 | 55.7% | 82.6% |
| 0.9 | 2 | 67.2% | 92.1% |
| 1.0 | 2 | 82.2% | 100% |

At 0.5 two of every three 4-twist screws still unseat under an idle player, so
the default is 0.9, where nine in ten do. Use 1.0 on the pet egg (the
tutorial), where one steady direction makes the lesson clear. For a
screw that should change direction more often, lower `slip_bias` and
raise `twists_needed`.

If correcting along a turning axis feels bad, try a smaller twist
angle (45) first.

## Later

- The handle leans a few degrees with motion across the slot (juice).
- A grippier flathead as an upgrade: a lower `slip_max`.
