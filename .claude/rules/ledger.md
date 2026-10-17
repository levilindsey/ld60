---
paths:
  - "LEDGER.md"
---

# Ledger: where unfinished work is recorded

`LEDGER.md` lists only the work that is not done yet. History and lore
stay in `CLAUDE.md`, commits and `docs/design/`. Keep secrets and private
data out: the repo may be public.

- **Add an item the moment it happens:** deferred work, a follow-up or
  idea, a bug or shortcut you leave in, a decision that waits on Levi.
- **Sections, in this order:** `Urgent` (only when something needs it;
  delete the heading when empty), `Waiting on Levi`, `In progress`,
  `Next`, `Residuals (known, not fixed)`, `Ideas (not scheduled)`, `Done`.
- **Item format**, one to three lines:
  `- **LX12** · terse description (pointer: file, design doc, commit)`.
  An ID is `LX` plus the highest number ever used plus one, counting
  `docs/ledger_done.md` and `docs/ledger_notes.md`; never reuse one.
- **Claim an item** before you start: move it to `In progress` and add
  indented lines, with no blank line inside the item: `owner:` who is on
  it (and their Claude Code agent, if one works for them); `branch:` (or
  `mainline`) and `last commit:`; `next:` the next concrete step;
  `brief:` the design doc to restart from; `evidence:` repo paths of
  probes and logs. A fresh session must be able to resume from the entry
  alone. Update it in the same commit as the change it records.
- **Close an item** by moving it to the top of `Done` as one line, with
  the commit that resolved it:
  `- **LX12** · ... Done in abc1234 (2026-10-17).` If it is dropped, say
  why: `Dropped: superseded by LX30.`
- **Merges.** `LEDGER.md` merges with `merge=union` (`.gitattributes`), so
  two people's edits combine instead of conflicting. The cost: when one
  side moves or deletes an item while the other edits nearby lines, the
  old copy can come back and an ID appears twice. The bottom-most copy is
  the current one: delete the stale copy.
- **Upkeep.** A nightly job on Levi's desktop archives Done entries older
  than a week to `docs/ledger_done.md` and commits them as `LEDGER:
  nightly upkeep`. Do not archive by hand.
