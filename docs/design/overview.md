# LD60 design overview

The theme is "old tech". We run a repair shop. Broken gadgets arrive
on the bench one at a time, and each tool is a small microgame. The
player takes the item apart layer by layer, fixes what is wrong, puts
it back together and drags it to the outbox. Every repair earns 1 to 3
stars. The items get stranger as the game goes on: everyday gadgets
from the 1970s to the 1990s first, then atomic-age gadgets from a
future that never happened.

## How to use these docs

- There is one doc per piece of work. Each starts with its ledger ID,
  its milestone and what it depends on, so you can pick it up without
  reading the others.
- [PLAN.md](../../PLAN.md) gives the build order.
  [LEDGER.md](../../LEDGER.md) says what is open and who is on it.
- Every number here is a starting point for tuning. Put tuning values
  in `settings.tres` (one export group per tool in
  `src/core/settings.gd`) or as an `@export` on a scene, never inline
  in code.
- Each doc marks what is **MVP** (needed for the jam build) and what is
  **Later** (only if there is time).
- Class and variable names in the docs are suggestions. Follow the
  style rules in `CLAUDE.md`.

## Docs

| Doc | What it covers | Ledger | Milestone |
|---|---|---|---|
| [tools.md](tools.md) | The hand, the cursor, the tool lifecycle, touch | LX7 | M1 |
| [repairables.md](repairables.md) | Items, layers, points, reassembly | LX8 | M1 |
| [outbox.md](outbox.md) | Item arrival, the outbox, the item queue | LX9 | M1 |
| [screws.md](screws.md) | Screw health, stripping, rust, install | LX10 | M1 |
| [flathead.md](flathead.md) | Flathead twist and slip | LX11 | M1 |
| [quality.md](quality.md) | Quality score, stars, receipt | LX12 | M1 |
| [decals.md](decals.md) | The decal system and the full art list | LX13, LX24 | M1, M3 |
| [canned_air.md](canned_air.md) | Spray, dust, fans | LX14 | M1 |
| [parts_bin.md](parts_bin.md) | Parts bin, swapping parts, belts | LX15 | M1 |
| [items.md](items.md) | Item ideas, the jam cut, escalation | LX16, LX23 | M1, M3 |
| [phillips.md](phillips.md) | Phillips pressure gauge | LX17 | M2 |
| [hammer.md](hammer.md) | Percussive maintenance and realigning | LX18 | M2 |
| [pliers.md](pliers.md) | Pulling stripped screws | LX19 | M2 |
| [solvent.md](solvent.md) | Rag and solvent, sensitive surfaces | LX20 | M2 |
| [oil_can.md](oil_can.md) | Oiling pivots, squeaks, misuse | LX21 | M2 |
| [glue.md](glue.md) | Gluing cracks and clips | LX22 | M2 |
| [stretch_tools.md](stretch_tools.md) | Tweezers, soldering iron, more | LX29, LX30 | Stretch |
| [booklet.md](booklet.md) | Instruction booklet ideas | LX28 | Later |

## The repair loop

1. **Arrive.** The item drops onto the mat from the top of the screen,
   with a ticket in the customer's words ("the dial sticks").
2. **Open.** Remove the fasteners on the outer layer. When they are all
   out, that layer lifts off and is set aside.
3. **Fix.** Inside are the faults: dust, grime, a dry pivot, a stuck
   relay, a bent part, a dead part, a crack.
4. **Close.** Put the layers back and drive the screws back in.
5. **Ship.** The finished item glows. Drag it to the outbox. A receipt
   shows the stars, and the next item drops in.

## Screen layout

The screen is 1280x720 and the camera is centered, so world x runs
from -640 to 640 and y from -360 to 360.

```
+--------------------------------------------------------------+
|                 item arrives from the top                    |
|                    (0, -549), off screen                     |
|                                                              |
|  +-----------+   +--------------------------+  +----------+  |
|  |  OUTBOX   |   |        WORK MAT          |  |  TOOL    |  |
|  |  tray     |   |  item at (0, 62)         |  |  RACK    |  |
|  |  (left    |   |  mat is about            |  |  (right  |  |
|  |  desk)    |   |  x -273..240, y -3..207  |  |  desk)   |  |
|  +-----------+   +--------------------------+  +----------+  |
|           parts drawer peeks up from the bottom edge         |
+--------------------------------------------------------------+
```

- **Tool rack, right.** It exists (`%FlatHeadScrewDriverHolder` at
  (497, 174)). The MVP set is eight tools (flathead, Phillips, hammer,
  pliers, canned air, rag, oil can, glue), so the rack may need a
  second row or a pegboard on the wall above the desk.
- **Outbox, left.** The finished item leaves to the left.
- **Parts bin, bottom.** A drawer; see [parts_bin.md](parts_bin.md)
  (LX6).
- **Solvent bottle.** A fixed prop near the rack.
- **Set-aside spot.** Where removed layers wait, beside the mat.
- Move any of these to fit the art. The code reads positions from
  marker nodes in `level.tscn`.

## Rules every system follows

1. **The controls are never the puzzle; the item is.** A tool always
   works the same way. What changes is which tool, where and how hard.
2. **Mistakes cost quality, not progress.** Every broken state has a
   way forward: a stripped screw comes out with pliers, a crack takes
   glue, a smear just costs points. Nothing makes an item unwinnable.
3. **The wrong tool or part costs nothing but time.** It clunks, the
   tool shakes, and nothing breaks.
4. **Show what is needed.** Symptoms point at the fix: visible dust, a
   squeak when a mechanism moves, a flicker, a bulging part.
5. **Decals over bespoke art.** Damage and dirt are small sprites on
   top of the part art, so one part image covers every state.
6. **Mouse and touch first.** Press, hold, drag and release with the
   left button. No right click, no keyboard, nothing shown only on
   hover.

## Escalation

- **Tier 1, everyday (the first items):** one layer, 2 to 4 steps, one
  or two tools.
- **Tier 2, bigger machines:** two layers, 4 to 6 steps, three or four
  tools, one hazard (heat, high voltage).
- **Tier 3, atompunk:** two or three layers, 5 to 8 steps, and weird
  rules (a boot that floats away, a screw that turns backwards).
- **Finale:** everything at once, plus one rule-breaker.

The list is in [items.md](items.md).

## Depth

Picked: the quality score with stars ([quality.md](quality.md)), and
diagnosis from symptoms (tickets, squeaks, visible faults). The
booklet ([booklet.md](booklet.md)) can add diagnosis by reading later.

Not scheduled (LX34):
- **Workday queue:** a day of 3 to 5 tickets with pickup times.
- **Screw map:** removed screws keep their order in a tray, and each
  must go back in its own hole. A long screw in a short hole punches
  through the board.
- **Hidden second fault:** opening the item reveals another problem,
  worth extra stars.
- **Donor junk:** strip items that can't be saved for parts.
- **Tool upgrades:** a magnetic tip widens the Phillips arc; a
  grippier flathead slips less.
- **Shop cat:** walks across the bench, bats screws off it, sits on the
  booklet, or sits next to the right spot as a slow hint.
- **Stories inside items:** a photo, a letter, a tape with someone's
  voice, and the customer's reaction at pickup.

## Decisions (LX6)

Levi confirmed these defaults on 2026-10-17. The alternatives stay
listed in case one is revisited.

| Decision | Chosen | Alternatives |
|---|---|---|
| Shop theme | "The cloud went down": every smart device died overnight, so everyone digs out their old gadgets, and ours is the only shop that knows how they work. As word spreads the customers get stranger, until people from an atomic-age future bring in ray guns and jetpacks. | Grandparent's shop; time-traveling shop; right-to-repair rebels; alien museum |
| Jam item cut | Pet egg, rotary phone, Walkman, CRT TV, ray gun, cut from the end ([items.md](items.md)) | Three items |
| Parts bin placement | A drawer that slides up from the bottom edge | Pan the camera right to a bin at the screen edge |
| Flathead unseat | Progress is kept and the screw takes 1 damage | The screw starts over (Levi's first idea) |
| Sensitive surfaces | No warning before the first wipe; damage is staged so stopping early is cheap | An outline on sensitive surfaces while the rag is held |

## Glossary

- **Item:** a `Repairable`, the thing on the bench.
- **Layer:** a `RepairLayer`, one removable piece of an item (a back
  cover, a circuit board).
- **Point:** an `InteractionPoint`, one thing a tool acts on (a screw,
  a dust clump, a pivot, a socket).
- **Surface:** an area that can be damaged (the case, a paper label).
- **Hand:** what the player holds: nothing, a tool, a part, or the
  item on its way to the outbox.
- **Part:** a replacement piece from the parts bin. Its **socket** is
  where it goes.
- **Decal:** a small sprite of damage or dirt on a part.
- **Defect:** a recorded mistake that lowers the quality score.
