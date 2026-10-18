# Tools and the hand

Ledger: **LX7** (M1). Folds in LX1 to LX5. Every tool doc depends on
this one.

## What exists

- `Tool` (`src/tools/tool.gd`) has modes ENTERING, STORED, HELD and
  IN_USE. While HELD it follows the mouse so that its
  `cursor_position` marker stays under the cursor.
- Each tool has three areas: `grab_area` (click to pick it up),
  `interaction_area` (touches InteractionPoints) and `holder_area`
  (touching its own `ToolHolder` puts the tool away).
- Picking a tool up hides the mouse; putting it away shows it again.

## The hand

Add one `Hand` node to `level.tscn` (`%Hand`, reached as
`G.level.hand`). It owns the things that are global today but set by
each tool:

- **What is held:** nothing, one tool, one part, or the item (while it
  is dragged to the outbox). Only one at a time.
- **The cursor:** a pointing hand by default everywhere in the
  app, an open hand when the hand is empty and over something it
  can grab (a stored tool, the parts drawer and its menu slots, a
  broken part that wiggles out, a ready set-aside layer, a resting
  screw, a finished item), and hidden while anything is held.
  Godot has no pointing or open hand shapes of its own here, so
  the arrow shape carries `assets/images/cursors/cursor_point.png`
  and the pointing-hand shape carries
  `assets/images/cursors/cursor_grab.png` (both set in
  `settings.tres` and registered by `Main`). The hand also resets
  the cursor when the level restarts or a held thing is freed
  (LX2).
- **Presses:** one `_unhandled_input` takes left-button presses and
  releases for the whole bench and ignores the other buttons (LX3).
- **Input owner:** while a microgame runs (the Phillips gauge, a hammer
  swing), it registers as the owner. The hand then sends it every
  press, drag and release and marks them handled, so nothing else (a
  booklet page, the parts bin) reacts. Check how `src/manual/` takes
  input; if it uses `_input`, it needs a guard.

```
Hand (Node2D, %Hand in level.tscn)
  held: Node2D           the tool, part or item in the hand, or null
  input_owner: Object    a running microgame, or null
  grab(thing), release(), is_empty()
  set_input_owner(owner), clear_input_owner(owner)
```

## Routing a press

On a left press, the hand converts the press position to world space
(`get_canvas_transform().affine_inverse() * event.position`), looks at
what is under it (`PhysicsDirectSpaceState2D.intersect_point()` with
areas on), and takes the first rule that matches:

1. **A microgame owns input:** send it the press.
2. **Over a screw resting on the bench:** once its layer is back on,
   send it back to its hole, whatever the hand holds. Before that the
   press does nothing ([screw_pullout.md](screw_pullout.md)).
3. **Over a set-aside layer that is ready to go back:** put it back.
4. **Over the parts drawer:** holding a part returns it. Holding a
   tool puts it away first. Empty-handed, the parts menu opens
   ([parts_bin.md](parts_bin.md)).
5. **Over the tool rack:** take that tool. A held tool goes back to
   its holder first.
6. **Holding a tool:** move the tool so its tip is at the press point,
   then let the tool act there (engage the point under the tip, or
   start its effect). The press also cancels any follow offset still
   easing out.
7. **Holding a part:** a press over a socket tries to fit it. Any
   other press nopes and keeps the part. Releasing drops nothing.
8. **Empty hand, over a point:** poke it (`on_poked()`). A dry pivot
   squeaks, a loose part rattles, a stuck lever jerks. This is the
   "inspect" action.
9. **Empty hand, over the item:** drag it if it is finished. Otherwise
   shake it and pulse its remaining points, which is a free hint.

Rule 6 is what makes touch work. A finger has no hover, so the tip has
to reach the target in the same event that presses. It also means the
tool asks what is under the tip directly, instead of waiting for the
next physics frame's area overlaps. With a mouse the tip is already
there, so nothing changes.

## Two kinds of tools

| Tool | Kind | Press | Hold or drag | Release |
|---|---|---|---|---|
| Flathead | Engage | Engage a flathead screw | Move along the slot to recenter | Nothing |
| Phillips | Engage | Engage a Phillips screw; the gauge opens | Hold to push | The needle eases off |
| Pliers | Engage | Clamp a stripped screw | Drag side to side | Nothing |
| Hammer | Effect | Lock the strike point, wind up | Strength builds | Swing |
| Canned air | Effect | Spray | Keep spraying | Stop |
| Rag | Effect | Soak (over the bottle) or wipe | Drag to wipe | Stop |
| Oil can | Effect | One drop | More drops, faster | Stop |
| Glue | Effect | Squeeze | Drag along the crack | Stop |

- **Engage tools** go IN_USE on one point. The point runs the microgame
  and moves the tool, which is a puppet while IN_USE. When the point
  finishes or ejects the tool, the tool returns to HELD.
- **Effect tools** stay HELD and push an effect into an area every
  physics frame while pressed: a spray cone, a rag footprint, a drop
  landing, a strike. Targets under the effect react through methods
  such as `on_sprayed(strength, direction, delta)`,
  `on_wiped(amount, delta)`, `on_oiled(global_position)`,
  `on_glued(global_position, radius, amount)` and
  `on_struck(global_position, strength)`. A target implements only the
  ones it cares about.

## Wrong tool

A point has `accepted_tools: Array[Tool.Type]`. A press on a point that
does not accept the held tool plays a clunk, shakes the tool for 0.2 s
and shows a small "nope" icon. No penalty.

## Follow offset (LX5)

The held tool follows the cursor plus an offset that eases to zero
over about 0.2 s. Set the offset whenever the tool would otherwise
jump:

- on pick-up, so the tool glides into the hand instead of teleporting;
- when a point releases it (the flathead tip has drifted away from the
  hidden cursor);
- after the hammer's recoil.

Never warp the mouse (`Input.warp_mouse()`). It fights the player and
does nothing useful on touch or in some browsers.

## Reticle

Tools whose head hides the target (hammer, oil can, glue) draw a small
crosshair at the cursor point, above everything else. It follows the
cursor and locks while the tool is mid-action. After touch input, draw
it bigger, since a finger covers the target. Mouse events made from
touch have `device == InputEvent.DEVICE_ID_EMULATION`.

## Fixes to fold in

- **LX1:** scale the GrabArea and HolderArea shapes to the 0.2 visual.
- **LX4:** take the holder offset from the HolderArea's shape, not from
  the HolderArea node.
- `ToolHolder.Type` duplicates `Tool.Type` and is compared to it as a
  plain int. Give `ToolHolder` an `@export var type: Tool.Type`
  instead.
- `Level.get_tool_holder_position()` only knows the flathead holder.
  Look the holder up by type among the `ToolHolders` children.
- Test with a real mouse: held-tool follow and put-away were only
  checked headless when they landed (929db18).

## Adding a tool

1. Add the value to `Tool.Type`.
2. Make the scene: the art in a child `Node2D`, a `Marker2D` at the tip
   for `cursor_position`, and the three areas, with the layers and
   masks that `Tool._ready()` checks.
3. Add `@export var <tool>_scene: PackedScene` to the "Tools" group in
   `src/core/settings.gd`, a case in `get_tool_scene_from_type()`, and
   assign the scene in `settings.tres`.
4. Add a `ToolHolder` for it under `ToolHolders` in `level.tscn`.
5. Spawn it in `Level._ready()`.
