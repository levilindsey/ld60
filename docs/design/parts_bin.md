# Parts bin and replacing parts

Ledger: **LX15** (M1). Depends on [tools.md](tools.md) (LX7) and
[repairables.md](repairables.md) (LX8). Stretch goals in this doc:
belts (LX31) and part orientation (LX32).

## What the player does

Wiggle the broken part loose and toss it. Open a parts drawer,
drag out a replacement and fit it into the empty spot.

## The diegetic drawers (current)

Decision (Levi, 2026-10-18): the parts menu below is gone. Three
diegetic drawers (`src/level/Drawer.tscn`, `Drawer`) stack
vertically on the left side of the level, each a full-frame art
canvas like the room, so the front face can align with the
background art. Each drawer has an `AnimationPlayer` "open"
animation that flips the front face to a top-down view, and a
`%Mover` wrapper: the animation drives the sprites, so the slide
to the center of the level tweens the wrapper.

- A press on a shut drawer plays the open animation, then slides
  the drawer to the center. Its stored parts appear at random
  spots inside it. A press outside the open drawer hides the
  parts, slides the drawer back and reverses the animation.
- At the start of each repairable, the drawers are restocked: one
  part per socket the item needs, plus decoys
  (`Settings.decoy_part_count`), shuffled across the three
  drawers, so the player hunts.
- Parts are dragged, not held. Pressing a part in an open drawer
  takes it out and the drawer shuts behind it. A loose part is
  dragged around the bench, set down anywhere on it, and picked
  up again. Releasing it over a socket fits the right part and
  nopes the wrong one. Releasing it over a shut (or open) drawer
  puts it away: the drawer opens halfway while the part rises
  over its top edge, sinks down inside, and shuts again. A drawer
  that is still shutting takes nothing; the part is set down.
- When an item goes into the outbox, parts left out on the bench
  are cleaned up into one drawer picked at random, with the same
  rise-and-sink put-away.

The menu description below is kept for the record.

## Where the bin lives

Decision (Levi, 2026-10-17, superseding the LX6 bottom-drawer and
pan plans below): the drawer space sits in the upper-left of the
screen. The ticket sits in the top-right, so it never covers the
drawer. The left edge holds the drawer, then the outbox.

Earlier plans, kept for the record:

- **Bottom drawer (was LX6).** A shallow drawer peeks up from the
  bottom edge of the screen, under the desk front. Pressing it slides
  it up (one tween), drawn above the item.
- **Pan.** The bin sits at the right edge, partly off screen.
  Pressing it pans the camera about 300 px to the right. This needs
  the background art extended about 300 px to the right.

## The drawer and the menu

- The drawer space is a fixed rectangle in the upper-left. The
  ticket sits in the top-right, so the drawer never moves to make
  room for it. It is an Area2D in the world, on a new PARTS physics layer,
  like the outbox and the tool holders, so the hand finds it with
  the same point query as the rack.
- Pressing the drawer with an empty hand opens the parts menu. The
  menu is a Control overlay in the level's CanvasLayer. Its backdrop
  stays translucent, so the item remains visible underneath.
- On open, a copy of each available part animates out of the drawer
  space into its menu slot (about 0.3 s, lightly staggered). The
  copies are UI controls, not live parts. Pressing one animates the
  others back into the drawer, fades the menu out, and spawns the
  real part in the hand at the cursor.
- Pressing the drawer again, or pressing outside the slots, cancels
  with no part taken. The menu never pauses the game.
- The drawer is dual-use. Holding a part, pressing the drawer
  returns the part instead of opening the menu. Holding a tool,
  pressing it puts the tool away first, like the rack. While a
  microgame owns input, pressing it does nothing. The drawer's look
  changes while a part is held, so the second meaning is visible.

## Taking a part

- The menu shows every available part type, labelled, plus new
  screws for reassembly. Slots are finger-sized, which is the main
  reason for the menu over tapping parts inside the drawer art.
- Taking a part never depletes the menu. The supply does not run
  out.
- Any part can be taken. Only the right one fits.

## Getting the old part out: wiggle

- Press the old part with an empty hand and drag side to side. The
  part rocks up to about 10 degrees with the drag, shifts sideways
  with the rock, and slides a tiny bit out with each counted swing
  (up to 8 px in all). Letting go settles it back into place.
- A swing counts when the drag reverses after moving at least 12 px.
  After `swings_needed` (6 by default) the part pops out and flies
  off into the trash with a spin.
- **Yank:** dragging further than 60 px from the press point pulls
  it out at once: a yanked part defect (-8). (A fast-drag yank, at
  about 2500 px/s, is not built yet.)
- Code: a `Wiggle` helper (a `RefCounted`, shared with the pliers).
  Feed it the drag deltas; it reports swings, the rocking angle and
  yanks.

## Putting the new part in

- A `PartSocket` is a point (role REPAIR) with an `accepted_part`
  (`Part.Type`) and the states BROKEN, EMPTY and INSTALLED. The broken
  part starts in it.
- Parts are tap-driven, like tools. The held part follows the
  cursor, and a press tries to use it. Releasing the button does
  nothing, so lifting a finger never drops the part.
- **A press over an empty socket:**
  - the right part snaps in (a 0.15 s tween and a click) and the
    socket is done. A powered part lights up (a tube glows).
  - a wrong part bounces off 30 px with a "nope" and stays in the
    hand. No penalty.
- **A press over the drawer** returns the part. **A press anywhere
  else** nopes and keeps the part in the hand. This replaces the
  earlier "released anywhere else flies back into the bin" rule.

## Building it

- `Part` (Node2D): a `type`, a sprite and an area. The hand holds it
  like a tool.
- `PartsBin`: the drawer art and its Area2D in the level, plus the
  menu overlay scene in the level's CanvasLayer. Menu slots are
  Controls showing each part's art and name. Selecting a slot spawns
  the part's scene in the hand.
- The hand gains a press rule for the drawer and for a held part,
  next to the rack rule in tools.md "Routing a press".
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
