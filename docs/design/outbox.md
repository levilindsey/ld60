# Item flow and the outbox

Ledger: **LX9** (M1). Depends on [repairables.md](repairables.md)
(LX8) and [tools.md](tools.md) (LX7). Hands off to
[quality.md](quality.md) for the receipt.

## Arrival

- `Level.spawn_repairable()` creates the next item at
  `%ItemSpawnPosition` (0, -549), turned a little (a random angle from
  -8 to 8 degrees).
- It tweens down to `%ActiveItemPosition` (0, 62) over about 0.6 s with
  a slight overshoot (TRANS_BACK, EASE_OUT), straightening as it lands.
  This is the TODO in `spawn_repairable()`.
- On landing: a thud, `G.level.shake_camera(3, 0.15)`, the mode becomes
  UNDER_REPAIR, and the quality timer starts. `Level` has no
  `shake_camera` yet: add one that calls `%CameraShaker.shake_camera()`
  (mark the `CameraShaker` node in `level.tscn` as a unique name).
- The ticket appears, as a paper tag on the item or a HUD card:
  "Rotary phone: the dial sticks and it never rings."

## Finishing

When the item reports `finished`: a ding, a sparkle, an outline glow
(`assets/shaders/sprite_outline.gdshader`), and it can now be dragged.

## Dragging

- Only a finished item can be dragged, and only with an empty hand.
  Press it and the hand holds it at the grab offset, so it doesn't
  jump.
- While dragged it tilts a little with the drag speed (up to about 8
  degrees), which sells its weight.
- Pressing an unfinished item gives a small shake and a "hmm" sound,
  and its remaining required points pulse once. That's a free hint,
  not an error.

## The outbox

- An `Outbox` Area2D on the left desk segment (`%Outbox` in
  `level.tscn`, with its mask on REPAIRABLES). It only detects overlap;
  the art gives it a tray or a box.
- **Released over the outbox:** the item's mode becomes LEAVING. It
  drops into the tray and slides off the left edge (0.4 s). The receipt
  pops up ([quality.md](quality.md)), and the next item arrives 0.5 s
  later.
- **Released anywhere else:** it eases back to `%ActiveItemPosition`
  (0.3 s).

## The item queue

- The day's order lives in settings:
  `@export var item_queue: Array[Repairable.Type]` in the
  "Repairables" group, each resolved by
  `get_repairable_scene_from_type()` as today.
- `Level` keeps the index. After the last item, MVP calls
  `G.level.win()` (the CREDITS screen). Later, a day summary comes
  first.

## MVP

The arrival tween, dragging only finished items, the outbox area, the
hand-off to the receipt, and the queue.

## Later

- **Flick:** the item keeps the drag's release speed and slides into
  the box with friction. The booklet code already measures fling speed
  (`src/manual/`).
- **FRAGILE items** (the CRT, a camera) must be carried below a speed
  limit. They rattle as a warning; too fast is a crunch and a crack
  defect.
- **Trash basketball:** flick old parts into a bin; a swish earns a
  tiny bonus.
- **Pneumatic tube** for small items.
- **Day summary** before CREDITS: stars per item and the total.
