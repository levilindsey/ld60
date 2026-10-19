extends "res://tests/probe_base.gd"
## Broken points, their pieces, glue and the rag (glue.md).
## Boots the game and plays the test item's authored pair:
## the fallen piece lands apart from the item, the hidden
## piece cannot be grabbed under its cover, glue arms the
## fallen point, an off target squeeze smears and the rag
## cleans it, a hold that leaves the ring fails with the
## glue still on, and a held still piece glues back on.
##
## Run it with `tests/run.ps1 -Name broken_glue`.
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _point: BrokenPoint
var _piece: BrokenPiece


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has(
		"--screenshots"
	)
	await get_tree().process_frame
	var main: Node = (
		load(_MAIN_SCENE_PATH) as PackedScene
	).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	if _is_taking_screenshots:
		var blocker := _RealInputBlocker.new()
		blocker.probe = self
		add_child(blocker)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_hand = G.level.hand
	_item = G.level.active_repairable

	# The authored pair: one piece fell on arrival, one hides.
	for piece in G.level.get_broken_pieces():
		if piece.starts_detached:
			_piece = piece
		else:
			_expect(
				not piece.can_grab(),
				"the hidden piece cannot be grabbed yet",
			)
	if not _expect(
		is_instance_valid(_piece), "the fallen piece exists"
	):
		return
	_point = _piece.target_point
	if not _expect(
		is_instance_valid(_point), "the fallen point exists"
	):
		return
	_point.hold_sec = 0.6
	_expect(
		await _wait_for_piece_rest(),
		"the fallen piece comes to rest",
	)
	_expect(
		_piece.has_detached()
		and _piece.get_parent() == G.level,
		"the fallen piece left the item on arrival",
	)
	var fall_target := (
		_item.global_position + _piece.fall_target_offset
	)
	_expect(
		_piece.global_position.distance_to(fall_target) < 90.0,
		"the fallen piece lands near its own target",
	)
	_expect(_piece.can_grab(), "the fallen piece can be grabbed")

	# Without glue, holding the piece on the point does nothing.
	await _press_down(_piece.global_position)
	await _move_to(_point.global_position)
	await _physics_frames(12)
	_expect(
		not _point.is_holding,
		"no hold starts before glue is applied",
	)
	await _release_at(_point.global_position)

	# Glue first. Without it the hold never starts.
	var glue := G.level.tools_by_type[Tool.Type.GLUE]
	await _grab_tool_inside(glue)
	_expect(
		_hand.held == glue, "the hand holds the glue bottle"
	)
	_expect(_point.is_exposed(), "the fallen point is exposed")
	await _press_down(_point.global_position)
	await _seconds(0.6)
	await _release_at(_point.global_position)
	_expect(_point.has_glue, "glue sticks to the broken point")

	# Glue off the point smears, free until the item finishes.
	var cover := _item.layers[_item.layers.size() - 1]
	var smear_spot := cover.to_global(Vector2(-38, 0))
	var defects_before := _item.quality.get_defect_count()
	await _press_down(smear_spot)
	await _seconds(0.9)
	await _release_at(smear_spot)
	var smear := _find_smear(cover)
	if _expect(
		is_instance_valid(smear), "off target glue leaves a smear"
	):
		_expect(
			_item.quality.get_defect_count() == defects_before,
			"a fresh smear costs nothing yet",
		)
		await _put_tool_away(glue)
		var rag := G.level.tools_by_type[Tool.Type.RAG]
		await _grab_tool_inside(rag)
		await _press_down(smear.global_position)
		for step in 12:
			var sway := 16.0 if step % 2 == 0 else -16.0
			await _move_to(
				smear.global_position + Vector2(sway, 0)
			)
		await _release_at(smear.global_position)
		_expect(
			smear.mode == InteractionPoint.Mode.FINISHED,
			"the rag wipes the smear off",
		)
		_expect(
			_item.quality.get_defect_count() == defects_before,
			"a cleaned smear never costs points",
		)
		await _put_tool_away(rag)
	else:
		await _put_tool_away(glue)

	# A hold that leaves the ring fails, and the glue stays.
	await _press_down(_piece.global_position)
	_expect(
		_hand.get_loose_broken_piece() == _piece,
		"a press grabs the fallen piece",
	)
	await _seconds(0.4)
	var turn_error := absf(
		wrapf(
			_piece.rotation - _point.global_rotation,
			-PI,
			PI,
		)
	)
	_expect(
		turn_error < 0.15,
		"the grabbed piece turns to its target rotation",
	)
	await _move_to(_point.global_position)
	_expect(
		await _wait_for_hold_start(),
		"holding the piece on the point starts the hold",
	)
	await _move_to(_point.global_position + Vector2(230, 0))
	await _physics_frames(4)
	_expect(
		not _point.is_holding
		and _hand.get_loose_broken_piece() == null,
		"leaving the ring fails the hold and drops the piece",
	)
	_expect(
		_point.has_glue
		and _point.mode != InteractionPoint.Mode.FINISHED,
		"a failed hold leaves the glue on the point",
	)

	# Holding still, countering the drift, glues it back on.
	await _press_down(_piece.global_position)
	await _move_to(_point.global_position)
	var is_done := false
	for frame in 360:
		if _point.mode == InteractionPoint.Mode.FINISHED:
			is_done = true
			break
		var drift := _point.get_dot_drift() / (
			G.settings.broken_hold_dot_scale
		)
		await _move_to(_point.global_position - drift)
	_expect(is_done, "holding still glues the piece back on")
	_expect(
		_piece.is_installed,
		"the held piece stays on its point",
	)

	# A smear left when the repair ends is charged then.
	await _grab_tool_inside(glue)
	var late_spot := cover.to_global(Vector2(-38, 24))
	await _press_down(late_spot)
	await _seconds(0.9)
	await _release_at(late_spot)
	await _put_tool_away(glue)
	var late_smear := _find_smear(cover)
	if _expect(
		is_instance_valid(late_smear), "a second smear lands"
	):
		var before_charge := _item.quality.get_defect_count()
		_item._charge_remaining_smears()
		_expect(
			_item.quality.get_defect_count() == before_charge + 1,
			"a smear left at the end costs a glue blob",
		)


## Takes a stored tool by pressing its root, safely inside
## its grab shape. The shared helper presses the holder
## shape's centre, which sits on the glue bottle's grab
## polygon edge and misses (the glue probe's known miss).
func _grab_tool_inside(tool: Tool) -> void:
	await _press_at(tool.global_position)


func _find_smear(layer: RepairLayer) -> GlueSmear:
	for point in layer.get_points():
		var smear := point as GlueSmear
		if (
			is_instance_valid(smear)
			and smear.mode != InteractionPoint.Mode.FINISHED
		):
			return smear
	return null


func _wait_for_piece_rest() -> bool:
	for frame in 360:
		if not _piece.is_returning:
			return true
		await get_tree().physics_frame
	return false


func _wait_for_hold_start() -> bool:
	for frame in 90:
		if _point.is_holding:
			return true
		await get_tree().physics_frame
	return false
