# LD60 plan

We're making a repair shop game for the theme "old tech". Broken
gadgets arrive on the bench, each tool is a small microgame, and each
repair earns 1 to 3 stars.

- **Design:** `docs/design/`. Start with
  [overview.md](docs/design/overview.md); there is one doc per piece of
  work.
- **Open work, and who's on it:** [LEDGER.md](LEDGER.md).
- **This file:** the order to build in, and how we work together.

## How we work

1. **Pull first.** Run `git pull --rebase` before you start and again
   before you push.
2. **Claim it.** Before starting an item, move it to "In progress" in
   `LEDGER.md` with your name, then commit and push that. Or ask in chat
   and someone will do it for you.
3. **Small, working commits.** Push each piece as soon as it works.
   Don't push broken work to `main`.
4. **One person per scene.** `.tscn` files merge badly. Say in chat
   before you edit a shared scene (`level.tscn`, `main.tscn`, an item
   scene), and push as soon as you're done with it.
5. **Close it.** Move the item to "Done" in the same commit that
   finishes it. If its doc has "Later" ideas you still want, add them to
   the "Ideas" section of the ledger.
6. **Numbers go in settings.** Tuning values go in `settings.tres`
   (export groups in `src/core/settings.gd`) or on the scene, so anyone
   can tune them without touching code.

## Milestones

Build in order. When time runs short, cut from the bottom of a
milestone, never the top.

### M1: one item, start to finish

| ID | What | Doc |
|---|---|---|
| LX7 | The hand: cursor, held thing, press routing, touch | [tools.md](docs/design/tools.md) |
| LX8 | Layers, points, reassembly, finishing | [repairables.md](docs/design/repairables.md) |
| LX9 | Item arrival, the outbox, the item queue | [outbox.md](docs/design/outbox.md) |
| LX10 | Screw health and stripping | [screws.md](docs/design/screws.md) |
| LX11 | Flathead twist and slip | [flathead.md](docs/design/flathead.md) |
| LX12 | Quality score, stars, receipt | [quality.md](docs/design/quality.md) |
| LX13 | Decal spawner (check clipping in a web build first) | [decals.md](docs/design/decals.md) |
| LX14 | Canned air | [canned_air.md](docs/design/canned_air.md) |
| LX15 | Parts bin and wiggling parts out | [parts_bin.md](docs/design/parts_bin.md) |
| LX16 | The virtual pet egg, end to end | [items.md](docs/design/items.md) |

LX7 and LX8 come first, because almost everything sits on them. After
those, the rest can run in parallel: they touch different files.

### M2: the tool set

| ID | What | Doc |
|---|---|---|
| LX17 | Phillips pressure gauge | [phillips.md](docs/design/phillips.md) |
| LX18 | Hammer | [hammer.md](docs/design/hammer.md) |
| LX19 | Pliers | [pliers.md](docs/design/pliers.md) |
| LX20 | Rag and solvent | [solvent.md](docs/design/solvent.md) |
| LX21 | Oil can | [oil_can.md](docs/design/oil_can.md) |
| LX22 | Glue | [glue.md](docs/design/glue.md) |

### M3: content and juice

| ID | What | Doc |
|---|---|---|
| LX23 | Items 2 to 5: rotary phone, Walkman, CRT TV, ray gun | [items.md](docs/design/items.md) |
| LX24 | Art: screw states, decals, part states, effects, UI | [decals.md](docs/design/decals.md) |
| LX25 | Sounds | Each doc's "Feedback" section |

Art (LX24) and sounds (LX25) can start any time; they don't wait for
M3.

### M4: ship

| ID | What | Doc |
|---|---|---|
| LX27 | Shrink the oversized source art | [decals.md](docs/design/decals.md) "Texture size" |
| LX26 | Web export and itch.io upload | `CLAUDE.md` "Web + Windows Builds" |

## Not scheduled

Stretch goals and ideas live in the "Ideas" section of `LEDGER.md`: the
booklet (LX28), tweezers (LX29), the soldering iron (LX30), belts
(LX31), part orientation (LX32), a test switch (LX33), more depth
(LX34) and more items (LX35).
