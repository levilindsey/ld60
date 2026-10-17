# Parts bin and replacing parts

Ledger: **LX15** (M1). Depends on [tools.md](tools.md) (LX7) and
[repairables.md](repairables.md) (LX8). Stretch goals in this doc:
belts (LX31) and part orientation (LX32).

## What the player does

Wiggle the broken part loose and toss it. Open the parts bin, pick
out a replacement and drop it into the empty spot.

## Where the bin lives (open: LX6)

- **Proposed: a drawer.** A shallow drawer peeks up from the bottom
  edge of the screen, under the desk front. Pressing it slides it up
  (one tween), drawn above the item. Taking a part closes it again, so
  the item is in view when the part goes in. Nothing else moves.
- **Alternative: pan.** The bin sits at the right edge, partly off
  screen. Pressing it pans the camera about 300 px to the right. The
  item stays in view on the left, so the part can go straight onto it,
  and the camera pans back once the part is placed or dropped. This
  needs the background art extended about 300 px to the right. Held
  things still follow the cursor, since they use world positions.

Either way, the bin is one still picture full of bits.

## Taking a part

- The bin art is one image. Every part drawn on it is a hotspot: an
  Area2D with a polygon roughly around the drawing, on a new PARTS
  physics layer, with a `part_type`.
- Pressing a hotspot spawns that part's scene in the hand, under the
  cursor. The picture doesn't change, so the supply never runs out.
- Any part can be taken. Only the right one fits.

## Getting the old part out: wiggle

- Press the old part with an empty hand and drag side to side. The
  part rocks up to about 10 degrees with the drag.
- A swing counts when the drag reverses after moving at least 12 px.
  After `swings_needed` (4 to 6) the part pops out and flies off into
  the trash with a spin.
- **Yank:** dragging faster than about 2500 px/s, or further than 60
  px, pulls it out at once but scratches or cracks the socket: a decal
  and a yanked part defect (-8).
- Code: a `Wiggle` helper (a `RefCounted`, shared with the pliers).
  Feed it the drag deltas; it reports swings, the rocking angle and
  yanks.

## Putting the new part in

- A `PartSocket` is a point (role REPAIR) with an `accepted_part`
  (`Part.Type`) and the states BROKEN, EMPTY and INSTALLED. The broken
  part starts in it.
- **A part released over an empty socket:**
  - the right part snaps in (a 0.15 s tween and a click) and the socket
    is done. A powered part lights up (a tube glows).
  - a wrong part bounces off 30 px with a "nope" and stays in the hand.
    No penalty.
- **A part released anywhere else** flies back into the bin.

## Building it

- `Part` (Node2D): a `type`, a sprite and an area. The hand holds it
  like a tool.
- `PartsBin`: the art, the hotspots, and the open and close tween.
- New screws for reassembly come from here too ([screws.md](screws.md)).

## Later: orientation (LX32)

Polarity parts (capacitors, batteries, keyed tubes) carry a + mark or a
notch. Tapping a held part flips it 180 degrees. A part put in
backwards seats fine, but pops and smokes at the payoff: a defect, and
it has to be replaced. Skip this for the jam.

## Stretch: belts (LX31)

- **Path:** the belt wraps 2 or 3 pulleys (circles). Build its path
  from the outer tangent lines between the pulleys plus the arcs around
  each one, and draw it as a `Line2D` with `closed = true`, rebuilt each
  frame from the pulley positions.
- **A texture that stays consistent:** use
  `texture_mode = LINE_TEXTURE_STRETCH`, so UV.x runs from 0 to 1 around
  the whole belt, and a shader that repeats the rib texture a fixed
  number of times: `fract(UV.x * rib_count)`, with
  `rib_count = round(rest_length / rib_length)`. When the belt
  stretches, the same ribs stretch with it instead of new ribs sliding
  in. Make it a little thinner and lighter as it stretches past its rest
  length.
- **Running:** scroll the UV offset at the belt's speed.
- **Fitting it:** hook the belt over pulley A, then drag the loop over
  pulley B. The belt follows the cursor and stretches; release near B
  to snap it on. Stretch it past about 1.3 times its rest length and it
  snaps (a defect; take another one).
- **The old belt:** a snapped one lifts out with a press.
