# Rag and solvent

Ledger: **LX20** (M2). Depends on [tools.md](tools.md) (LX7),
[repairables.md](repairables.md) (LX8, for surfaces) and
[decals.md](decals.md) (LX13).

## What the player does

Drag the rag back and forth over grime to wipe it off. Some
surfaces must not be wiped. As built for LX20 there is no solvent
yet, so the rag wipes dry. Soaking below is the later version,
kept for when a solvent bottle lands.

## Soaking (later, not built)

- The rag is the held tool. The bottle is a fixed prop on the desk
  (`SolventBottle`, an Area2D).
- Press with the rag over the bottle: the bottle tips (about 100
  degrees over 0.3 s) and pours onto the rag for as long as the press
  is held. The rag's `wetness` rises at 0.8/s up to 1.0, and the rag
  darkens.
- **Over-soaking:** holding past full keeps raising the wetness, up to
  1.5. Above 1.0 the rag drips for a few seconds. MVP: that only wastes
  time. Later: drips that land on the item leave stain decals.

## Wiping

- Press and drag over the item. Each frame, every grime point under
  the rag loses
  `wipe_rate * wetness_factor * min(speed, speed_cap) * delta` HP.
- **Back and forth:** each reversal of the drag direction adds a small
  burst, so scrubbing beats one long stroke.
- **Drying out:** wetness drops with the distance wiped. Below 0.15 the
  rag cleans at 20% speed; time to soak it again.
- **Grime** (`GrimeSpot` points, role REPAIR) has HP, and its alpha
  fades with it. A spot counts as clean with 10% HP left; the rest
  clears with a sparkle sweep and a ding, so nobody hunts the last
  speck.
- The rag gets dirtier (tinted brown) as it cleans.
- What it cleans: grime, battery crust, oil smears, fingerprints, tape
  heads, sticky keys, contacts.

## Sensitive surfaces

`Surface` areas ([repairables.md](repairables.md)) with these materials
must not be wiped:

| Material | Example | What wiping does |
|---|---|---|
| PAPER_LABEL | The label inside a Walkman, a model plate | The ink smears |
| PAINTED | Dial numbers, printed markings | The paint rubs off |
| GREASED | A greased gear | The shine fades; the gear now squeaks and needs oil |
| FELT | Foam pads, light seals | It pills and fuzzes |
| STICKER | "Warranty void if removed" | It peels |

How the player knows:
- **Before:** the art. Paper looks like paper with ink on it, greased
  parts are glossy, felt is fuzzy. Delicate things should look
  delicate.
- **While wiping:** the moment the rag touches one, it drags (it lags
  behind the cursor), a different sound plays (paper scrubbing), and a
  damage overlay starts to show, growing with the distance wiped.
- **The cost is staged:** at about 30% wiped it is a minor defect (-3),
  and at 100% it is ruined (-10 in total). A player who notices and
  stops loses very little.
- **Optional:** after the first offense of the game, show a soft red
  outline on sensitive surfaces whenever the rag is held (with
  `sprite_outline.gdshader`). LX6 kept the default, no warning before
  the first wipe, so this stays optional.
- **Later:** the booklet warns about them ("Do not clean the label").

Wiping a GREASED part also adds a dry pivot to the item (a new required
point), so the order of steps matters.

## Feedback

A glug while pouring, wet squeaks while wiping (the pitch follows the
speed), a ding per clean spot, and the paper-scrub sound on sensitive
surfaces.

## Building it

- `Rag extends Tool`, an effect tool with a footprint area about 40 px
  across. While pressed and moving, it calls `on_wiped(amount, delta)`
  on the grime points and sensitive surfaces under it. Built: the
  hanging sprite shows on the rack, the bunched sprite in the hand.
- `SolventBottle` sits on the desk with its own tipping animation.
  Not built yet. There is no bottle and no wetness for now.

## Later

- **Two solvents:** rubbing alcohol (safe) and acetone (twice as fast,
  but it fogs clear plastic and lifts paint).
- **Ultrasonic bath:** drop a small part in and pull it out inside a
  timing window; too long and its labels peel off.
- A fresh rag from the parts bin when this one is filthy.
