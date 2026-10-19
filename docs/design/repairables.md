# Items, layers and points

Ledger: **LX8** (M1). Depends on [tools.md](tools.md) (LX7). Every tool
doc and [items.md](items.md) build on this one.

## What exists

- `Repairable` (`src/repairables/repairable.gd`): a `Type` per item and
  modes ENTERING, LEAVING and UNDER_REPAIR.
- `InteractionPoint` (`src/interaction_points/interaction_point.gd`):
  an Area2D with a `Type` and modes UNSTARTED, ACTIVE and FINISHED.
  Tools call `on_tool_entered()` and `on_tool_exited()` on it.
- `Screw` (declared in `flat_head_screw.gd`) extends it and is empty so
  far.
- `Settings.get_repairable_scene_from_type()` maps item types to
  scenes.

## Structure of an item

An item is a stack of layers. Children of `Layers` are ordered
innermost first, so the outer layers draw on top.

```
RotaryPhone (Repairable)           item_name, ticket, par_time_sec
  Layers (Node2D)
    Mechanism (RepairLayer)        innermost, never removed
      Sprite2D
      DialDust (DustClump)         REPAIR
      DialPivot (OilPivot)         REPAIR
      BellClapper (BentPart)       REPAIR
    Shell (RepairLayer)            no fasteners
      Sprite2D
      CaseSurface (Surface)        PLASTIC
    BasePlate (RepairLayer)        outermost, removed first
      Sprite2D
      ScrewLeft (FlatHeadScrew)    FASTENER
      ScrewRight (FlatHeadScrew)   FASTENER
```

## Points

- Every point has a `role`. A FASTENER (a screw, a clip) holds its
  layer on. A REPAIR point is a fault that must be fixed.
- A point only reacts while its layer is **exposed**: the outermost
  layer still on the item. Points on covered layers ignore tools and
  pokes.
- `is_required` (default true). Optional points are extras, such as a
  coin hidden under the dust.
- `accepted_tools: Array[Tool.Type]` ([tools.md](tools.md) "Wrong
  tool").

## Taking it apart

- When every FASTENER on the exposed layer is out, the layer is loose.
  It stays where it is. The player drags it off the item; coming off,
  it turns by a slight random angle. Like a loose part, it can be
  carried anywhere and set down on the bench, and a drop outside the
  workable area flies back in under gravity and comes to rest inside
  it — but a drawer never takes it. Grabbed again once it can go back
  on, it first turns back to its original rotation. Nothing on the
  item moves by itself.
- A layer with no fasteners is loose as soon as it is exposed, and
  likewise waits to be dragged off.
- The innermost layer is never removed.

## Fixing

- REPAIR points on exposed layers can be done in any order.
- Some mistakes add new required points while playing. Oil on the
  contacts adds an oil smear to wipe ([oil_can.md](oil_can.md));
  wiping the grease off a gear adds a dry pivot ([solvent.md](solvent.md)).

## Putting it back

- A set-aside layer gets the gradient outline once every required
  point on the layers under it is FINISHED. Drag it back and drop it
  within `layer_seat_snap_px` of its home; it tweens into place.
- Its screws come back loose in their holes, turned back a little, in
  INSTALL mode. Driving them in uses the same microgame, shorter
  ([screws.md](screws.md)).
- A screw that was pulled with pliers is scrap. Its hole stays empty
  until a new screw from the parts bin is dropped in.

## Finishing

The item is finished when every required point is FINISHED and every
layer is back on with its fasteners installed. It then plays its
payoff (the phone rings, the egg hatches), gets the gradient outline,
and can be dragged to the outbox ([outbox.md](outbox.md)).

## Breaking

- A point can break into a different point:
  `@export var broken_scene: PackedScene` on `InteractionPoint`, where
  null means it can't break. Breaking swaps the point for an instance
  of that scene with the same transform. For example, a snapped plastic
  clip becomes a crack that needs glue. That way each point type keeps
  one tool and one microgame.
- Screws don't use this; they track their own health
  ([screws.md](screws.md)).

## Surfaces

- `Surface` (an Area2D on the SURFACES physics layer) marks a region
  of a part with a material, `Surface.Type` (Godot already has a
  `Material` class): PLASTIC, METAL, GLASS, CIRCUIT_BOARD, CONTACTS,
  RUBBER, PAPER_LABEL, PAINTED, GREASED, FELT or STICKER.
- Tools ask what is under them. The hammer dents METAL and cracks
  PLASTIC and GLASS, unless the layer's `hammer_decal` overrules
  its set (`DENT` or `CRACK` per piece; `DEFAULT` keeps the
  material's choice), the rag smears a PAPER_LABEL, and oil contaminates
  CONTACTS and RUBBER.
- A surface is a child of its layer, so it comes off with it, and it is
  only active while that layer is exposed.

## Data on the item

```gdscript
@export var item_name := ""
## The customer's complaint, shown on the ticket.
@export_multiline var ticket := ""
@export var par_time_sec := 90.0
```

- Signals: `layer_removed(layer)`, `layer_installed(layer)`,
  `point_finished(point)`, `finished`.
- `quality: RepairQuality` records every defect
  ([quality.md](quality.md)).
- The order of items comes from the item queue ([outbox.md](outbox.md)).

## Later

- **Test switch (LX33):** a switch on the item runs it at any time.
  Symptoms show what is still wrong (static, a squeak, a flicker)
  before opening it, and the payoff plays once it works. It makes
  diagnosis a real step.
- Lift layers off and put them back by dragging.
- A magnetic dish that collects removed screws, needed for the screw
  map idea ([overview.md](overview.md) "Depth").
- The leftover-screw gag: one screw still in the dish after shipping.
