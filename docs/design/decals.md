# Decals and the art list

Ledger: **LX13** (M1, the decal system) and **LX24** (M3, the art).
Used by every tool that damages or cleans.

Damage and dirt are small sprites on top of the part art, not separate
versions of each part. One part image then covers every state, and a
new kind of damage costs one decal instead of one drawing per item.
Textures use linear filtering, so decals can be rotated, scaled and
tinted freely.

## The system (LX13)

- **Runtime decals** (dents, cracks, scratches, smears, drips, blobs)
  spawn where the damage happens, as a child of the part they land on,
  so they move with it when its layer lifts off.
- **Placed decals** (dust, grime, rust, crust) are part of the item
  scene and are also points. They have HP, fade as they are cleaned,
  and disappear at 0.
- **Variety:** each spawn picks a random texture from its set, a random
  rotation, a scale from a range, a random flip and an optional tint.
- **Clipping:** set the part sprite's `clip_children` to
  `CLIP_CHILDREN_AND_DRAW` so that decals only draw where the part is
  opaque. **Check this first in a web export** (the Compatibility
  renderer). If it doesn't work there, read the part texture's alpha at
  the spawn point before spawning (`Texture2D.get_image()`, cached,
  then `get_pixelv()`), and move or skip the decal.
- **Blending:** try multiply (a `CanvasItemMaterial` with
  `BLEND_MODE_MUL`) for dust, grime and rust, so they darken what is
  under them. Otherwise use normal blending with semi-transparent art.
- **Code sketch:** a `DecalSpawner` node (`%Decals` in `level.tscn`)
  with `spawn(kind, part, global_position, size, direction)`. Each kind
  has a `DecalSet` resource: `@export var textures: Array[Texture2D]`,
  a scale range, and whether the rotation is random or follows
  `direction`. Don't name a class `Decal`: Godot already has a 3D node
  with that name.
- **Texture size:** decals are small on screen, so keep their source
  images small too (64 to 256 px). The current source art is 3508x2480
  and drawn at about 0.2 scale (LX27).

## The art list (LX24)

P1 means needed for the first items; P2 is for later.

### Screws (animation frames, not decals)

| Art | Count | Priority |
|---|---|---|
| Flathead head: clean, scratched, chewed, stripped | 4 frames | P1 |
| Phillips head: clean, scratched, chewed, stripped | 4 frames | P1 |
| Rust overlay for a screw head | 1 | P1 |
| Empty screw hole | 1 | P1 |
| Pliers gouges around a hole | 2 | P1 |
| Security screw head | 1 | P2 |

### Damage (runtime decals)

| Art | Count | Priority |
|---|---|---|
| Dent: round and creased (scaled for small and large) | 2 | P1 |
| Crack: hairline and branching | 2 | P1 |
| Crack: spiderweb (glass) and edge chip | 2 | P2 |
| Glued crack seam (a crack filled with shiny glue) | 1 | P2 |
| Scratch: single line and cluster | 2 | P1 |
| Screwdriver skid (a flathead unseat) | 1 | P1 |
| Scuff and paint chip | 2 | P2 |
| Burn mark and melted plastic | 2 | P2 |
| Smeared label ink and rubbed-off paint | 2 | P2 |
| Fogged plastic haze | 1 | P2 |

### Dirt and wear (placed in item scenes, removable)

| Art | Count | Priority | Cleaned by |
|---|---|---|---|
| Dust clump or dust bunny | 3 | P1 | Canned air |
| Dust layer, light and heavy, tiling | 2 | P2 | Canned air |
| Grime blob | 3 | P1 | Rag |
| Grease gunk (oil plus dust) | 2 | P2 | Rag |
| Battery crust, white and green | 2 | P1 | Rag |
| Verdigris on contacts | 1 | P2 | Rag |
| Rust bloom and a rust streak below a screw | 2 | P1 | Stays; on a screw it means seized |
| Rust pitting | 1 | P2 | Stays |
| Fingerprints and smudges | 2 | P2 | Rag |
| Cobweb, dead bug, lint, crumbs | 4 | P2 | Canned air |
| Water ring, tape residue, mold spots | 3 | P2 | Rag |

Some wear needs no art: nicotine yellowing and sun fade are a
`modulate` tint on the part.

### Left behind by tools (runtime decals)

| Art | Count | Priority |
|---|---|---|
| Oil drip (small, medium) and an oil puddle | 3 | P1 |
| Oil sheen on rubber | 1 | P2 |
| Glue blob (small, medium) and a glue string | 3 | P1 |
| Solvent stain (a wet ring) | 1 | P2 |
| Grime streak from a dry rag | 1 | P2 |

### Part states (a swap of one small part sprite)

Some states can't be a decal:

| Part | States | Priority |
|---|---|---|
| Coin cell or battery | new, dead, leaking | P1 |
| Capacitor | good, bulging | P1 |
| Belt | good, snapped (slack is P2) | P1 |
| Plastic clip | intact, snapped | P1 |
| Vacuum tube | dead, glowing (an additive glow sprite that flickers when loose) | P2 |
| Fuse | good, blown | P2 |
| Resistor | good, burnt | P2 |
| Bulb | dead, lit | P2 |
| Gear | clean, gunked, missing a tooth | P2 |
| Knob or wire | present or missing, connected or loose | P2 |
| Spring | normal, stretched | P2 |

A bent part needs no new art: it is the same sprite, rotated or moved.

### Effects

- P1: dust puff, sparks, impact flash, smoke wisp, oil drop, solvent
  drip, clean sparkle, squeak motion lines.
- P2: zap arc, radiation glow, steam.
- The glue bead is a `Line2D` and needs no art.

### UI

- P1: star (empty and full), receipt card, a "nope" icon, a grab-hand
  cursor (32 to 64 px).
- The gauge, the strength ring and the crosshair can be drawn in code;
  art for them is P2.
