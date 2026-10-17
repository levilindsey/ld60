# Quality and stars

Ledger: **LX12** (M1). Depends on [repairables.md](repairables.md)
(LX8). Every tool records its mistakes here.

## The score

- Each item starts at 100 points. Defects subtract from it, down to 0.
- Stars: 85 or more is 3 stars, 60 or more is 2, and anything lower is
  1. A finished item always gets at least 1 star.
- Time counts from the moment the item lands (UNDER_REPAIR) until it is
  finished. Pausing stops the clock.

## Defects

Defaults, tuned in settings (a "Quality" export group):

| Defect | Points | Comes from |
|---|---|---|
| Screw damage, per level | -2 | A flathead unseat, a Phillips cam-out |
| Screw stripped, on top of its damage | -10 | The third slip |
| Pliers scratch | -3 | Every pliers removal |
| Small dent | -8 | The hammer, a bit over the band |
| Large dent | -12 | The hammer, far over the band |
| Crack | -15 | The hammer on plastic or glass |
| Yanked part | -8 | Pulling a part out too hard (the socket gets a scratch) |
| Smear on a sensitive surface, minor | -3 | The rag, about 30% wiped |
| Smear, ruined (replaces the minor one) | -10 | The rag, fully wiped |
| Oil drip or stain | -4 | Over-oiling, a drop off target |
| Glue blob | -5 | Too much glue in one spot |
| Over par time | -1 per 2 s, at most -30 | A slow repair |
| Wrong tool or wrong part | 0 | It just bounces off |

A stripped screw pulled with the pliers costs 6 + 10 + 3 = 19 points,
enough to drop an otherwise clean repair from 3 stars to 2. A single
slip (2 points) doesn't.

## During play

- There is no live score on screen; the decals are the feedback.
- Each defect shows a small floating number ("-8") at its spot for
  about a second, so players learn what cost them.

## Receipt

When the item goes into the outbox, a receipt card slides in. It lists
the item's name, each defect with its count and points, the time, the
total and the stars. The stars pop in one at a time with a ding, and 3
stars add a sparkle. It goes away on a click or after 3 s, and the next
item drops in behind it.

## Building it

```gdscript
class_name RepairQuality
extends RefCounted

enum Defect {
	SCREW_DAMAGE,
	SCREW_STRIPPED,
	PLIERS_SCRATCH,
	DENT_SMALL,
	DENT_LARGE,
	CRACK,
	YANKED_PART,
	SMEAR_MINOR,
	SMEAR_RUINED,
	OIL_DRIP,
	GLUE_BLOB,
}
```

- Methods: `add_defect(defect, global_position)`, `get_score()`,
  `get_stars()`, plus the defect list for the receipt.
- Each `Repairable` owns one (`repairable.quality`). The points come
  from settings through a `match`, like `get_tool_scene_from_type()`.
- Time over par is worked out at the end from `par_time_sec`; it is not
  stored as a defect.
- A surface's `SMEAR_RUINED` replaces its `SMEAR_MINOR`.

## Later

- A day summary: stars per item and the day's total.
- A corkboard of customer reviews ("Works great! Bit of a dent.").
- Bonuses for perfect work (a Phillips screw that never drained), up to
  the cap of 100.
