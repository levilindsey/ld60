# ld60 ledger

Open work for ld60 (the Ludum Dare 60 game): follow-ups, known
residuals, decisions waiting on Levi, and ideas. Convention:
claude-config `rules/ledger.md`. IDs (`LX<n>`) are stable and never
reused.

## Waiting on Levi

- **LX6** · Pick from the 2026-10-17 tool/item brainstorm: shop theme,
  tool cut, first items, Phillips control scheme. Offered to save it
  under `docs/design/` for the teammate (it is only in chat so far).

## In progress

<!-- Each item is a resume handle: owner, branch + last commit, evidence,
next, brief, env (claude-config rules/ledger.md). -->

## Next

- **LX1** · Tool collision shapes were never scaled to the 0.2 visual:
  the grab area is 5x the tool, the put-away drop is off-screen
  (`src/tools/flat_head_screw_driver.tscn`, `docs/ledger_notes.md`).

## Residuals (known, not fixed)

- **LX2** · Cursor shape and mouse mode are global but set per tool: not
  reset when a held tool is freed, and tools would fight over them
  (`src/tools/tool.gd` `_update_cursor`, `docs/ledger_notes.md`).
- **LX3** · Any mouse button, including the wheel, picks a tool up:
  `_on_grab_area_input_event` has no MOUSE_BUTTON_LEFT check. Pointer:
  `src/tools/tool.gd`.
- **LX4** · `Tool._set_mode` (STORED) takes `holder_area_offset` from the
  HolderArea node (always zero), not its shape offset (0,-600), so the
  tool origin lines up with the holder (`src/tools/tool.gd`).

## Ideas (not scheduled)

- **LX5** · Pick-up teleports the tool so its cursor point jumps under
  the cursor: tween a pick-up offset that `_physics_process` applies
  (a TODO from Levi in `src/tools/tool.gd` `pick_up_tool`).

## Done
