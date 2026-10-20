extends "res://tests/probe_base.gd"
## The radio's dial knob glues on first thing. The dial
## piece falls on arrival like every fallen piece, and its
## point sits on the front layer, exposed from the start:
## nothing makes the player unscrew the front, swap the
## bulb or whack the case before the knob goes on. Glue the
## point, hold the piece, and it must attach while every
## other radio point is still untouched.
##
## Run it with `tests/run.ps1 -Name radioknob`.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

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
	if not _expect(
		await _wait_for_landing(), "the first item lands"
	):
		return
	_hand = G.level.hand
	# The radio item arrives by its own staging (the shelf
	# radio wonks, falls silent, flies down), so spawn it
	# directly with a short wonk, the way the radio probe does.
	G.settings.shop_radio_wonk_sec = 0.5
	var current := G.level.active_repairable
	G.level.active_repairable = null
	current.queue_free()
	await _physics_frames(4)
	G.level.spawn_repairable(Repairable.Type.RADIO)
	if not _expect(
		await _wait_for_landing(), "the radio lands"
	):
		return
	_item = G.level.active_repairable
	for piece in G.level.get_broken_pieces():
		if piece.starts_detached:
			_piece = piece
	if not _expect(
		is_instance_valid(_piece), "the dial piece fell on arrival"
	):
		return
	_point = _piece.target_point
	if not _expect(
		is_instance_valid(_point), "the dial point exists"
	):
		return
	_point.hold_sec = 0.6
	# Nothing else on the radio has been touched.
	var untouched := true
	for layer in _item.layers:
		for point in layer.get_points():
			if point != _point and point.needs_work():
				continue
			if point != _point and (
				point.mode != InteractionPoint.Mode.UNSTARTED
			):
				untouched = false
	_expect(
		untouched,
		"every other radio point is still untouched",
	)
	# Glue the dial point with the bottle's working end.
	var glue := G.level.tools_by_type[Tool.Type.GLUE]
	await _press_at(glue.global_position)
	_expect(_hand.held == glue, "the hand holds the glue bottle")
	await _squeeze_glue_at(glue, _point.global_position, 0.6)
	_expect(_point.has_glue, "the dial point takes glue first thing")
	await _put_tool_away(glue)
	# Hold the fallen dial onto its point until it sticks.
	await _press_down(_piece.global_position)
	_expect(
		_hand.get_loose_broken_piece() == _piece,
		"a press grabs the fallen dial",
	)
	var is_done := false
	for frame in 360:
		if _point.mode == InteractionPoint.Mode.FINISHED:
			is_done = true
			break
		var drift := _point.get_dot_drift() / (
			G.settings.broken_hold_dot_scale
		)
		await _move_to(_point.global_position - drift)
	_expect(
		is_done,
		"the dial glues on before any other radio work",
	)
	_expect(
		_piece.is_installed,
		"the dial stays on its point",
	)


func _squeeze_glue_at(
	tool: Tool, target: Vector2, seconds: float
) -> void:
	var pointer := await _glue_pointer_for(tool, target)
	await _press_down(pointer)
	await _seconds(seconds)
	await _release_at(pointer)


func _glue_pointer_for(tool: Tool, target: Vector2) -> Vector2:
	var settle_frames := 0
	while settle_frames < 90 and (
		tool.follow_offset.length() > 0.5
		or (
			is_instance_valid(tool.rotation_tween)
			and tool.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		settle_frames += 1
	var offset := (
		tool.get_work_end_position() - tool.get_tip_position()
	)
	return target - offset
