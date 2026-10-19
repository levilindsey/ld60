extends "res://tests/probe_base.gd"
## Grime covering a screw. Boots the game on the test box, whose
## ScrewLeft wears a GrimeSpot. The flathead driver cannot engage
## the covered screw. Wiping the grime off with the rag frees it,
## and the same press then engages.
##
## Run it directly from the repo root (PowerShell):
##   godot --headless --path . res://tests/grime_screw/probe.tscn
## It needs a row in tests/run.ps1 to run under that script.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _item: Repairable
var _screw: Screw
var _grime: GrimeSpot


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
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_hand = G.level.hand
	_item = G.level.active_repairable
	_screw = _item.get_node("Layers/Cover/ScrewLeft") as Screw
	_grime = _item.get_node("Layers/Cover/CoverGrime") as GrimeSpot
	if not _expect(
		is_instance_valid(_screw), "the test box has ScrewLeft"
	):
		return
	if not _expect(
		is_instance_valid(_grime), "the test box has CoverGrime"
	):
		return
	_expect(
		_screw.covering_grime == _grime,
		"ScrewLeft names CoverGrime as its covering grime",
	)
	_expect(
		_screw.is_covered()
		and _grime.mode != InteractionPoint.Mode.FINISHED,
		"the screw starts covered",
	)
	_expect(
		not _screw.can_engage(),
		"a covered screw cannot engage",
	)

	var driver := G.level.tools_by_type[
		Tool.Type.FLAT_HEAD_SCREW_DRIVER
	] as Tool
	await _grab_tool(driver)
	_expect(_hand.held == driver, "the hand holds the driver")
	await _press_tool_at(driver, _screw.global_position)
	await _physics_frames(2)
	_expect(
		_screw.mode == InteractionPoint.Mode.UNSTARTED
		and driver.mode == Tool.Mode.HELD,
		"the driver does not engage the covered screw",
	)
	await _put_tool_away(driver)

	var rag := G.level.tools_by_type[Tool.Type.RAG] as Tool
	await _grab_tool(rag)
	_expect(_hand.held == rag, "the hand holds the rag")
	var spot_position := _grime.global_position
	await _press_down(spot_position)
	for swing in 8:
		await _move_to(spot_position + Vector2(28, 0))
		await _move_to(spot_position + Vector2(-28, 0))
	await _release_at(spot_position)
	_expect(
		_grime.mode == InteractionPoint.Mode.FINISHED,
		"dragging the rag cleans the covering grime",
	)
	_expect(
		not _screw.is_covered() and _screw.can_engage(),
		"the wiped screw can engage",
	)
	await _put_tool_away(rag)

	await _grab_tool(driver)
	await _press_tool_at(driver, _screw.global_position)
	await _physics_frames(2)
	_expect(
		_screw.mode == InteractionPoint.Mode.ACTIVE
		and driver.mode == Tool.Mode.IN_USE,
		"the driver engages the screw once the grime is gone",
	)
