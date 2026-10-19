# New items: TV, keyboard, piano, and the line-up

The three real items below share one authoring pattern. Each piece
of art arrives as a full-canvas overlay (3508x2480) aligned with
the main body image, so a piece is drawn in its scene as a
`Sprite2D` with `region_enabled` set to the piece's bounding box
on its overlay, sitting at that box's centre in layer space
(canvas centre is the layer origin). `"with gaps"` is the main
body without the swapped or moved pieces. The item root carries
the scale (TV and keyboard 0.13, piano 0.11), and each point's
hit shape is sized in canvas pixels to match its piece.

## TV (`tv_repairable.tscn`)

- **Bent antenna:** a `BentPart`. Hammer hits in the band
  straighten it; when it finishes, the bent sprite swaps to the
  straight antenna sprite (`BentPart.straight_art`).
- **Bad controls:** a `PartSocket` (`TV_CONTROLS`). Wiggle the
  bad controls out, fetch good controls from the drawers, fit
  them; the good controls sprite shows on install
  (`PartSocket.installed_art`).
- **Final whack:** a `StuckPart` needing one working hit. The
  screen art does not change; the whack is the finish.
- **Dust spew:** the antenna and the final whack set
  `bench_dust_spew_count` on their strikable points. A working
  hit shakes that many dust clumps loose onto the workbench.
  Bench dust is cleaned with the blower; what is still on the
  bench when the item finishes costs a bench dust defect, and
  the level clears what is left after scoring. Other bespoke
  items set the same export on their own points to spew.

## Computer keyboard (`keyboard_repairable.tscn`)

- **Letter key** and **spacebar:** `PartSocket`s (`LETTER_KEY`,
  `SPACEBAR`) with bad and good sprites from the overlays.
- **Blow-out:** three dust clumps on the body (optional, as
  authored dirt always is, but see left-dirty scoring).

## Pianoman (`piano_repairable.tscn`)

- **Middle key:** a `BrokenPoint`/`BrokenPiece` glue hold; the
  broken key starts fallen beside the piano.
- **Wipe well:** two required grime spots.
- **Top-left LED:** a `PartSocket` (`LED`) with busted and good
  sprites.

## The line-up (`settings.tres` `item_queue`)

In order: Atari joystick, Computer keyboard, TV, Pianoman,
Game n Watch, Radio (bespoke), Atompunk Toaster, Shrink ray.
Atari, Game n Watch, Radio, Toaster and Shrink ray have
placeholder scenes (`*_repairable.tscn`): a coloured body and
one whack to finish, so the schedule runs end to end before
their real interactions land. Their intended repairs:

- **Atari joystick:** one flathead screw, replace the stick
  (yoink).
- **Game n Watch:** wipe grime off two Phillips screws (grime
  now covers a screw on the test box too; a covered screw
  cannot be worked until the grime is off), open the faceplate,
  blow dirt x2, replace the circuit (yoink), glue the fallen
  button back on.
- **Radio:** see below.
- **Toaster:** glue a wheel back on; it then wanders, loses
  another wheel, gets wiped and hammered.
- **Shrink ray:** it accidentally shrinks the hammer for the
  rest of the game (higher tink, no more damage), then hammer
  and part work.

## Drawers

Every restock (which already happens per repairable as it
lands) now stocks one of every `Part.Type` in the game across
the drawers, plus extra copies of what the item's sockets
need, plus the usual decoys. Hunting a part can mean opening
any drawer, and the set resets for each repairable.

## Yank indicator and tap

A stuck socket part that can be tugged shows a back-and-forth
wiggle indicator. Dragging back and forth loosens it, and a
single tap now counts as one swing in alternating directions,
so a series of taps works it out too.

## Radio (`radio_repairable.tscn`)

The bench scene is wired with its real art: the front comes
off on two flathead screws, inside is a bulb `PartSocket`
(the drawers' Tube) with bad and good bulb sprites, dust to
blow out, a final whack on the front, and a fallen dial to
glue (piece art is still the placeholder shape). The bespoke
sequence below is still design only.

## Radio arc (design only this pass)

- The radio stays a persistent level prop. Its glitch is
  scripted during repairs 2, 3 and 4 (queue order), X seconds
  into the repair; a hammer hit fixes it as today.
- After the item on the bench is finished following the third
  radio fix, a special card flicks up from the bottom of the
  screen, spinning onto the bench. The radio then becomes the
  bench repairable (two flathead screws, replace a tube,
  blow it out, a final whack, glue the dial that fell off
  outside). It gets a reward card but no outbox trip, then
  the next item arrives.

Open values: the glitch delay X, the reward card's art, and
whether the radio repair interrupts or follows the queue.

## Dragging the main body (design only this pass)

Not built yet. Intended: the empty hand drags the main
repairable body to reposition it on the bench at any time,
finished or not; the body never rotates. Layers, points and
the drop shadow follow as children. Needs care around taps
that open drawers, press points, or grab loose pieces, and
around the finished item's outbox drag, which this would
generalise.
