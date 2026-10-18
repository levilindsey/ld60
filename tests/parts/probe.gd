extends "res://tests/probe_base.gd"
## The parts drawer (LX15). Boots the game and plays the swap loop
## with pushed presses: open and cancel the menu, wiggle the broken
## gear out, try the wrong part, return it, then fit the right one.
##
## Run it with `tests/run.ps1 -Name parts`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/parts/probe.tscn
## Add `-- --screenshots` (windowed) to save PNGs of the bench to
## `build/tests/parts/`.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0

var _level: Level
var _item: Repairable
var _socket: PartSocket
## The drawer's center, in world pixels.
var _drawer_position := Vector2(-444.0, -58.0)


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has("--screenshots")
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
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
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_level = G.level
	_hand = _level.hand
	_item = _level.active_repairable
	_socket = _find_socket()
	if not _expect(is_instance_valid(_socket), "the item has a socket"):
		return
	_expect(_socket.has_broken_part, "the socket starts broken")
	await _shot("1_bench")

	# Open the cover by finishing its screws directly. The screw
	# microgame has its own probe (tests/screws).
	for layer in _item.layers:
		for point in layer.get_points():
			if point is FlatHeadScrew:
				point.finish()
	if not _expect(
		await _wait_until(func() -> bool: return _socket.is_exposed()),
		"the socket is exposed with the cover off",
	):
		return

	await _check_cancel()
	await _check_wiggle_out()
	await _check_wrong_part()
	await _check_right_part()


func _check_cancel() -> void:
	await _press_at(_drawer_position)
	_expect(
		await _wait_until(
			func() -> bool: return _level.get_parts_menu().is_open()
		),
		"a press on the drawer opens the menu",
	)
	await _seconds(0.6)
	await _shot("2_menu")
	var slots := _level.get_parts_menu().get_node("%Slots")
	_expect(
		slots.get_child_count() > 0
		and (slots.get_child(0) as Control).mouse_default_cursor_shape
		== Control.CURSOR_POINTING_HAND,
		"the drawer part slots show the open hand",
	)
	_expect(
		is_instance_valid(G.settings.grab_cursor_texture),
		"the grab cursor texture is set",
	)
	await _press_at(Vector2(460.0, 290.0))
	_expect(
		await _wait_until(
			func() -> bool: return not _level.get_parts_menu().is_open()
		),
		"a press outside the slots cancels the menu",
	)
	_expect(_hand.is_empty(), "the hand is empty after cancelling")


func _check_wiggle_out() -> void:
	await _move_to(_socket.global_position)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_POINTING_HAND,
		"empty hand over the broken part to tug out",
	)
	var broken_part := _socket.get_node("BrokenPart") as Node2D
	await _press_down(_socket.global_position)
	await _move_to(_socket.global_position + Vector2(25.0, 0.0))
	_expect(
		absf(broken_part.rotation) > 0.01
		and absf(broken_part.position.x) > 0.1,
		"the broken part rocks and shifts with the drag",
	)
	await _move_to(_socket.global_position + Vector2(-25.0, 0.0))
	_expect(
		broken_part.position.y < -0.5,
		"the broken part slides a tiny bit out per swing",
	)
	_expect(
		_socket.has_broken_part,
		"one swing does not free the broken part",
	)
	for swing in 6:
		var offset := 25.0 if swing % 2 == 0 else -25.0
		await _move_to(_socket.global_position + Vector2(offset, 0.0))
	await _release_at(_socket.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return not _socket.has_broken_part
		),
		"dragging side to side wiggles the broken part out",
	)
	_expect(
		_socket.mode == InteractionPoint.Mode.UNSTARTED,
		"the socket is empty after the wiggle-out",
	)


func _check_wrong_part() -> void:
	await _take_from_menu(Part.Type.TUBE)
	_expect(
		_hand.held is Part
		and (_hand.held as Part).type == Part.Type.TUBE,
		"the tube is in the hand after its slot",
	)
	await _press_at(_socket.global_position)
	_expect(_hand.held is Part, "the wrong part stays in the hand")
	_expect(
		_socket.mode != InteractionPoint.Mode.FINISHED,
		"the wrong part does not finish the socket",
	)
	await _press_at(_drawer_position)
	_expect(
		await _wait_until(func() -> bool: return _hand.is_empty()),
		"a press on the drawer returns the held part",
	)


func _check_right_part() -> void:
	await _take_from_menu(Part.Type.GEAR)
	_expect(
		_hand.held is Part
		and (_hand.held as Part).type == Part.Type.GEAR,
		"the gear is in the hand after its slot",
	)
	await _shot("3_gear_held")
	await _press_at(_socket.global_position)
	var is_socket_finished := func() -> bool:
		return _socket.mode == InteractionPoint.Mode.FINISHED
	_expect(
		await _wait_until(is_socket_finished),
		"the gear finishes the socket",
	)
	_expect(_hand.is_empty(), "the hand is empty after fitting")
	_expect(not _item.has_finished, "the item still waits for its cover")


## Opens the menu and presses the slot for a part kind. Slots sit in a
## row at the screen's center: gear, tube, spring.
func _take_from_menu(part_type: Part.Type) -> void:
	await _press_at(_drawer_position)
	await _wait_until(
		func() -> bool: return _level.get_parts_menu().is_open()
	)
	await _seconds(0.6)
	var slot_screen := Vector2(504.0 + 136.0 * part_type, 360.0)
	var slot_world := (
		_hand.get_canvas_transform().affine_inverse() * slot_screen
	)
	await _press_at(slot_world)
	await _wait_until(func() -> bool: return _hand.held is Part)


func _find_socket() -> PartSocket:
	for layer in _item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				return point as PartSocket
	return null


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false
