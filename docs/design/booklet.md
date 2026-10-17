# Instruction booklet

Ledger: **LX28**, not scheduled. Zaven will probably own this. These
are the ideas so far, kept for when that work starts.

The page turning exists already: `src/manual/` (`InstructionManual`,
`ManualPage`, the bending `ManualLeaf`, flinging to flip), with
placeholder pages in `src/level/zaven_demo/zaven_demo_level.tscn`.
What's still open is what goes on the pages and what they are for.

## The core idea

A complete booklet turns a repair into a checklist, and no booklet
turns it into guessing. Missing and unclear pages sit between the two,
so how much of an item's booklet survives can set its difficulty.
Three rules keep that fun:

1. **Never make the controls unclear, only the item.** How each tool
   works goes somewhere reliable: a card on each tool holder, or the
   booklet's front pages. Unclear controls feel like bad UI; an unclear
   item feels like a puzzle.
2. **Whatever a page leaves out, the item can also show:** a visual
   clue, a test, a failure. A missing page slows the player down but
   never blocks them.
3. **A wrong guess costs a little** (a scratch, a dent, fewer stars),
   so reading is worth the time. Those costs already exist
   ([quality.md](quality.md)).

## What a page tells you, and the fallback

| The page tells you | Without it, the item shows it by | A wrong guess costs |
|---|---|---|
| Which tool | The wrong tool doesn't fit: a clunk, it bounces off | A second |
| Where the fasteners are | Looking: the fifth screw is under the rubber foot or the "warranty void" sticker | Time |
| How hard or how long | The hammer's bands, the rag drying out | A dent |
| What order | Consequences: oil on dust makes gunk | An extra step |
| What's broken | Visible clues: the bulging capacitor, the squeak | Wasted parts |
| Which replacement part | The old part's markings, unless they're burnt off | The wrong part bounces off |
| An unlock code | The car radio shows CODE. The code is on a card in its booklet, written inside the case, or the customer can be called | Wrong tries lock it for a while |

Real car radios locked like this, and the code often came on a card
with the owner's manual.

## What the booklet could be for

1. **Tutorial.** The first item's booklet is complete and clear, and it
   teaches how to read a page. The cheapest role.
2. **Recipe.** Each item's pages show an exploded view with numbered
   steps: which tool, where, and in what order. This is where "figure
   out which tool, where and how" lives.
3. **Diagnosis.** A troubleshooting table leads from the ticket's
   symptom to the likely part and its page. It comes almost free if
   each recipe opens with a symptom line.
4. **Journal.** Steps the player completes ink themselves into the page
   in pencil. The first mistake on a step adds a margin note ("NOT the
   hammer"). Missing pages become pages the player writes.
5. **Collectible.** Pages turn up across the run and complete a binder,
   with a secret on the last page. Tunic did this with an in-game
   manual styled after NES-era ones. It only pays off if item types
   repeat.

Suggested: the recipe as the main role, plus the tutorial and the
journal. Add diagnosis if tickets carry symptoms.

## The booklet's condition as the difficulty curve

Each item arrives with its own booklet in a set condition:

| Item | Its booklet | What it teaches |
|---|---|---|
| Virtual pet egg | Complete and clear | How to read a page |
| Walkman | Page 6 is torn out, but the contents page still lists "6. Belt" | Gaps carry information |
| Rotary phone | Covers three models; the model plate on the phone says which steps apply | Matching the page to the item |
| Handheld console | Machine-translated, with the owner's pencil notes | Which voice to trust |
| Tube radio | No booklet, only the customer's sticky note: "just static" | Diagnosing from symptoms |
| CRT TV | Water-damaged; the warning survives only as "...DISCHARGE...BEFORE..." | Danger steps |

The inside cover is a free place for the item's story: a dedication, a
receipt, a kid's name in marker.

## Ways a page can be unclear

Keep each one a small, specific question (which tool? how many? which
way?), not a wall of mush.

- **Wordless diagrams,** IKEA-style: a tool silhouette, an arrow and a
  count. They are vague in a fun way, and readable on a phone, where
  small text isn't. The help-hotline page can be our own version of
  IKEA's confused little man on the phone.
- **Wrong angle or model:** drawn from the back, mirrored, or covering
  several models at once.
- **Vague words:** "several screws", "firmly", "remove the
  escutcheon", with the glossary page missing.
- **Cross-references:** "See page 47", and page 47 is the torn one. Or
  the classic line "Reassembly is the reverse of removal".
- **Translation:** "Before open, please to release the electricity".
  Credit the translation to a 1980s translation program, so the joke is
  on the machine, not on people.
- **Damage:** a coffee ring, water ripples, a burnt corner, crayon over
  the diagram. Each one hides one specific thing.
- **Margin notes from a previous owner:** helpful ("5th screw under
  foot!"), wrong (crossed out in a second pen), or right in a way that
  sounds wrong ("just smack it" on the CRT). TIS-100 does this: a note
  with its manual says the machine came from the player's late uncle,
  and the marked passages are clues. Printed text against pencil also
  makes room for a joke: the cover says NO USER-SERVICEABLE PARTS
  INSIDE, and the pencil says "liar".

## How missing pages come back

- **Readable gaps:** page numbers drawn into the page art skip (5, then
  7), the contents page still names the missing page, and a torn stub
  sits at the spine.
- **Found pages:** folded into the battery compartment, or blown out
  with the dust by the canned air. Drag one onto the open booklet and it
  slots in at its page number.
- **Faxed pages:** call the manufacturer on the shop phone (a rotary
  dial, hold music), and the page prints slowly on curling thermal
  paper. A hint system that costs time.
- **Written pages:** the journal's inking. It's the cheapest of these
  and the most satisfying.
- **A free, slow hint:** the shop cat wanders over and sits next to the
  right spot.

## On the desk

- **Read, then do, or keep it beside the bench.** If the open booklet
  covers part of the bench, the player reads, remembers, closes it and
  works; Papers, Please gets its tension from that kind of desk-space
  squeeze. If it sits beside the bench, it's just a reference. Pick one
  on purpose.
- **Physical gags:** canned air near the open booklet flips its pages
  (a scripted leaf turn); a solvent drip smears the page under it; the
  cat sits on the booklet.
- **Clear overlay sheet:** a transparent sheet in the booklet that you
  drag over the circuit board. Once it's lined up, it marks the test
  points or the bad part. It needs one translucent sprite and a snap
  tolerance.

## Fitting it to the existing manual

- **Pages that change without touching the turning code:**
  `page_contents` is an `Array[Texture2D]`, and a `SubViewport`'s
  texture is a `Texture2D`. Render each page scene in its own off-screen
  `SubViewport`, and `ManualPage` and `ManualLeaf` keep working
  unchanged. Keep each one on `UPDATE_ONCE`, switching to
  `UPDATE_ALWAYS` only while something on it animates, so 20 pages
  don't redraw every frame in the web build.
- **Blank pages work today:** a null entry shows as a blank page.
- **Step data:** each `InteractionPoint` gets a `step_id` and a
  starting clarity (`MISSING`, `VAGUE` or `CLEAR`). Page scenes hold one
  marker per step with the same id. When a point finishes, its marker
  inks in; when it breaks, its note appears.
- **One booklet per item:** put an `InstructionManual` in each
  Repairable scene so the booklet arrives and leaves with its item. It
  registers in a `G.manual` slot in `_enter_tree`, the way `Hud` does.
- **Generated drawings:** a copy of
  `assets/shaders/sprite_outline.gdshader` that drops the fill turns an
  item layer's own sprite into an IKEA-style line drawing. Place the
  step markers at that layer's point positions. "Drawn from the back"
  is just `flip_h`.
- **Input:** while a microgame owns input, the booklet has to ignore
  presses ([tools.md](tools.md) "The hand").

## A jam-sized version, if it gets picked up

- Controls on cards at the tool holders.
- One booklet per item, with its condition set in data.
- Wordless numbered steps, plus two or three of the unclear types.
- The torn page that the contents page still names.
- Steps that ink in when done, and a note on the first mistake.
- If there's time: found pages and the fax hint, then the gusts and
  smears.

Sources on TIS-100: diabolicalplots.com/tag/tis-100 and
mobygames.com/game/79879.
