# Idle hints and the repair sequence

Ledger: **LX62**. Depends on [repairables.md](repairables.md)
(LX8), [tools.md](tools.md) (LX7), [parts_bin.md](parts_bin.md)
(LX15) and [outbox.md](outbox.md) (LX9).

## Why

At every moment of a repair the game knows what the player should
do next, but saying so at once would make the game too easy. So
the bench waits. After a delay with no correct interaction on the
current step it outlines the thing to touch. After a longer delay
it outlines the tool for that thing too. Any correct interaction
restarts both counts.

## The sequence is autodetermined

No item author writes a step list. When an item enters the tree,
`Repairable` builds a `RepairSequence` (`src/repairables/
repair_sequence.gd`) from the item as authored: its layers, the
fasteners and faults on each layer, and which sockets start with
a broken part in them. `RepairStep` (`repair_step.gd`) is one step
of it.

Derivation, in intended order:

1. Taking it apart, outermost layer first. A layer with fasteners
   derives an UNSCREW step grouping all of them. Faults on the
   layer derive their steps (below). A layer above the innermost
   derives a REMOVE_LAYER step.
2. The innermost layer's faults.
3. Putting it back, innermost cover first: REPLACE_LAYER, then
   RETURN_SCREW when the layer's fasteners are screws (they rest
   on the bench), then SCREW_IN grouping them again.
4. SHIP.

Fault steps on one layer:

- One REPAIR step groups every required tool fault on the layer
  (dust, grime, cracks, bent and stuck parts), because they can
  be fixed in any order. Optional points derive nothing, and a
  fan derives nothing either, since it never finishes in the jam
  build.
- Each required socket in authored order derives EXTRACT_PART
  when it starts with a broken part, then FETCH_PART, then
  INSTALL_PART. A socket that starts empty skips the extraction.

So the test box (two cover screws, one gear socket, optional dirt)
derives nine steps with no REPAIR step, and the Phillips box
derives no socket steps at all. Mark its dust and grime required
and a REPAIR step grouping both appears. The probe in
`tests/hints/` checks both derivations.

## Steps rejudge the bench

The built list is the intended order, not a pointer the player
advances. Every physics frame `RepairStep.is_actionable()` and
`is_complete()` read live state: which layer is exposed, whether
it is loose or ready to go back, whether a socket still holds
its broken part, whether the right part is loose yet, and whether
a screw rests on the bench or sits in its hole. A layer knows it
`has_been_removed`, which tells driving its screws out from
driving them back in. `get_current_steps()` returns the
actionable steps in the best tier. Work on the exposed layer
shares one tier, so any of its points counts. Taking a loose
layer off sorts after fixing that layer's own faults, because
they become unreachable once it is set aside.

## The tracker

`HintTracker` (`src/level/hint_tracker.gd`) is a child of the
level. Each frame it takes the sequence's current steps, picks
one candidate, first step first and authored order inside it,
and times the bench.

- A correct interaction is progress on a candidate: it turns
  ACTIVE or FINISHED, its dirt, coverage or hit count moves, a
  broken part pops out, a drawer state changes during a fetch,
  the stored flags of the needed part change, a layer comes off
  or goes back, or the player is hands on with one, mid microgame,
  wiggling a socket, or dragging the right screw, layer, part or
  finished item. Progress and step changes restart the count and
  clear any lit hint.
- After `Settings.hint_delay_sec` (7 s) the target lights with
  the shared gradient outline: the point at its collision shape
  (`InteractionPoint.set_hint_active()`), a resting screw at its
  bench art, the layer, or the loose part in its kind's shape.
- After `Settings.hint_tool_delay_sec` (16 s) the stored tool
  the lit point accepts lights too, at its grab shape. A tool
  already in the hand never lights. Steps that take no tool light
  nothing more, except INSTALL_PART, which lights its socket as
  the destination at the longer stage.

Two targets are special:

- **Fetch.** While the needed part is still shut away, every
  drawer lights at once, since the part could be in any of them.
  Once a drawer is open, the target becomes the part inside it
  when that drawer holds the right kind.
- **Ship.** A finished item lights itself and the outbox on its
  own (LX9), so the tracker adds nothing. Its delays still run,
  and the outline simply stands.

Clearing a hint never clears an outline the game shows on its
own: a ready layer keeps its outline, and a resting screw that
can come back keeps its return outline.

## Probes and tuning

`tests/hints/` plays the test box start to finish with the two
delays shortened, stalling at each kind of step. Both delays are
the "Hints" group in `settings.gd` and `settings.tres`. Feel on
a real mouse and touch is Levi's to judge (LX41): whether 7 s
and 16 s are patient enough, and whether one lit candidate is
clear enough among its unlit siblings.

## Later

- A point that breaks into another point swaps itself after the
  sequence is built, so the new point is in no step. Rebuild the
  sequence when a point breaks, if a jam item ever uses it.
- Resting screws could light their hole as the longer stage's
  destination, the way INSTALL_PART lights its socket.
