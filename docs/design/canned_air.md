# Canned air

Ledger: **LX14** (M1). Depends on [tools.md](tools.md) (LX7) and
[repairables.md](repairables.md) (LX8). Kept simple on purpose.

## What the player does

Hold to spray. Dust in the spray blows away, and fans spin when blown
on.

## Rules

- **Spray:** while pressed, a cone comes out of the nozzle: about 200
  px long and 30 degrees wide, pointing the way the can faces (it is
  held at a fixed angle).
- **Dust clumps** (`DustClump` points, role REPAIR) have 1.0 HP. Inside
  the cone they lose `blow_rate` (1.5/s) times a falloff with distance
  (full strength near the nozzle, a third at the far end), and they
  wobble. At 0 they fly off along the spray, shrinking and fading, with
  a dust puff.
- **Fans** (`Fan`): the spray turns a fan by its torque around the hub,
  `torque = r.cross(direction) * strength`, where `r` runs from the hub
  to the point where the cone's center line passes closest. Friction
  slows it: `angular_velocity *= exp(-friction * delta)`.
  - A healthy fan spins up fast and coasts for seconds.
  - A dry fan (high friction) barely turns, stops at once and squeaks.
    That's the hint that it needs oil ([oil_can.md](oil_can.md)). After
    oiling, its friction drops.
- No penalties. The worst case is wasted time.

## Feedback

A hiss loop while spraying, air streaks in the cone, dust puffs, and a
whir that follows the fan's speed.

## Building it

- `CannedAir extends Tool`, an effect tool. While pressed, it collects
  the areas overlapping its cone (an `Area2D` with a
  `CollisionPolygon2D`) and calls `on_sprayed(strength, direction,
  delta)` on each.
- `DustClump` and `Fan` implement `on_sprayed()`.

## Later

- **Cold can:** spraying too long chills the can. The spray sputters
  and frost creeps over the can; letting go recovers it.
- **Direction puzzle:** dust blown deeper stays inside; it has to leave
  through an opening.
- **Hidden finds** under the dust: a lost ring, a note from the last
  repairer, a torn booklet page ([booklet.md](booklet.md)).
- **Over-spin:** a fan blasted past a speed limit wrecks its bearing.
- **Cartridge gag:** blowing into a game cartridge does nothing; the
  contacts need the rag.
- **Oil before air:** oiling a dusty pivot turns the dust into gunk
  that needs the rag first.
