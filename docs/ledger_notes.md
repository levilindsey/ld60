# Ledger notes

Text moved out of `LEDGER.md`: the full text of items that were
shortened, under their ID. New entries go at the bottom.

## LX1

Tool collision shapes were never scaled to the 0.2 visual: the grab area
is about 5x the visible tool (hand cursor far from it), and the holder
circle (r=200, 600 px up the tool) puts the put-away drop off-screen
(held at 40 deg, the cursor must be at world (111,634); visible y tops
out at 360). Pointer: `src/tools/flat_head_screw_driver.tscn` (GrabArea,
HolderArea).

Measured 2026-10-16: the visual `Node2D` is rotated -90 deg and scaled
0.2, so the visible tool is about 215 px long, about 8 px wide at the
shaft and about 25 px wide at the handle. The GrabArea polygon is
unscaled: about 40 px wide at the shaft, 128 px at the handle, and 1075
px long. The HolderArea circle (r=200) is centered 600 px up the tool.
Either scale the shapes by 0.2 or drop the 0.2 visual scale.

## LX2

Cursor shape and mouse mode are global but each tool sets them: nothing
resets them when a held or hovered tool is freed (restart_level on game
over leaves the cursor hidden), and two tools would fight over the
shape. Needs one owner, which also covers the "another tool is grabbed"
TODO. Pointer: `src/tools/tool.gd` (`_update_cursor`, `pick_up_tool`,
`put_away`).
