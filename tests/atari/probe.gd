extends "res://tests/probe_base.gd"
## The Atari joystick repair, played end to end with real
## inputs: grab the flathead driver, drive the screw out of
## the dead stick's base tab (that screw locks the socket),
## wiggle the dead joystick out, fetch a new joystick from
## its drawer and fit it, bring the screw back and drive
## it in over the new stick. The item finishes.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _screw: FlatHeadScrew
var _socket: PartSocket
var _driver: Tool


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = (
		"--screenshots" in OS.get_cmdline_args()
	)
	var main := (
		(load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
		as Main
	)
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _seconds(0.3)
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.ATARI_JOYSTICK,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the Atari lands"):
		_finish(1)
		return
	_hand = G.level.hand
	_item = G.level.active_repairable
	for layer in _item.layers:
		for point in layer.get_points():
			if point is FlatHeadScrew:
				_screw = point as FlatHeadScrew
			if point is PartSocket:
				_socket = point as PartSocket
	_driver = G.level.tools_by_type[
		Tool.Type.FLAT_HEAD_SCREW_DRIVER
	]
	_expect(
		is_instance_valid(_screw) and is_instance_valid(_socket),
		"the Atari has a tab screw and a joystick socket",
	)
	_expect(
		_socket.is_locked() and not _socket.has_tuggable_part(),
		"the screwed-down stick cannot be tugged yet",
	)
	_expect(
		not _socket.is_yank_indicator_visible(),
		"the yank arrows stay hidden while the stick is screwed down",
	)
	_expect(
		Part.has_art(Part.Type.JOYSTICK),
		"the drawer joystick shows its real art",
	)
	await _unscrew_stick()
	await _yank_and_refit()
	await _rescrew_stick()
	_finish(0 if _failures.is_empty() else 1)


func _unscrew_stick() -> void:
	await _grab_tool(_driver)
	_expect(_hand.held == _driver, "take the flathead driver")
	await _press_tool_at(_driver, _screw.global_position)
	_expect(
		_driver.mode == Tool.Mode.IN_USE
		and _screw.mode == InteractionPoint.Mode.ACTIVE,
		"the driver engages the tab screw",
	)
	var start_rotation := _screw.head.rotation
	await _drive(0.6)
	_expect(
		absf(_screw.head.rotation - start_rotation) > 0.05
		and _screw.mode == InteractionPoint.Mode.ACTIVE,
		"the screw turns a little at a time over many frames",
	)
	await _drive(15.0)
	_expect(
		await _wait_until(
			func() -> bool: return _screw.mode == InteractionPoint.Mode.FINISHED
		),
		"driving the screw out finishes it",
	)
	_expect(
		not _socket.is_locked() and _socket.has_tuggable_part(),
		"with its screw out, the stick can be tugged",
	)
	_expect(
		not _socket.is_yank_indicator_visible(),
		"the yank arrows stay hidden until the stick is tugged",
	)
	await _put_tool_away(_driver)


func _yank_and_refit() -> void:
	var broken_part := _socket.get_node("BrokenPart") as Node2D
	await _press_down(_socket.global_position)
	await _move_to(_socket.global_position + Vector2(25, 0))
	_expect(
		absf(broken_part.rotation) > 0.01,
		"the dead joystick rocks with the drag",
	)
	_expect(
		_socket.is_yank_indicator_visible(),
		"the yank arrows show while the stick is being tugged",
	)
	for swing in 7:
		var offset := 25.0 if swing % 2 == 0 else -25.0
		await _move_to(_socket.global_position + Vector2(offset, 0))
	await _release_at(_socket.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return not _socket.has_broken_part
		),
		"wiggling back and forth yanks the dead joystick out",
	)
	var part := _find_stored_part(Part.Type.JOYSTICK)
	if not _expect(is_instance_valid(part), "a new joystick is stocked"):
		return
	var drawer := G.level.get_drawers()[part.drawer_index]
	await _open_drawer(drawer)
	if not _expect(part.visible, "the new joystick shows in its drawer"):
		return
	# Grab the part on its authored shape, not its centre: the
	# stick's centre is the ring gap, off the shape.
	var part_position := part.global_position
	var shape_points := part.get_shape_world_polygon()
	if not shape_points.is_empty():
		var centroid := Vector2.ZERO
		for point in shape_points:
			centroid += point
		part_position = centroid / shape_points.size()
	await _press_down(part_position)
	await _move_to(_socket.global_position)
	await _release_at(_socket.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return _socket.mode == InteractionPoint.Mode.FINISHED
		),
		"the new joystick fits the socket",
	)
	var good_stick := _socket.get_node("GoodStick") as CanvasItem
	_expect(
		good_stick.visible and not part.visible,
		"only the fitted stick shows once the new joystick lands"
		+ " (the drawer part hides behind its fitted sprite)",
	)


func _rescrew_stick() -> void:
	await _wait_until(
		func() -> bool: return not G.level.are_drawers_busy()
	)
	_expect(
		_screw.can_come_back(),
		"the screw waits on the bench to come back",
	)
	_expect(
		not _item.has_finished,
		"the item is not finished until the screw is back in",
	)
	await _press_resting_screw(_screw)
	_expect(
		await _wait_for_travel(_screw, Screw.Travel.HOME),
		"the screw comes back into the new stick's tab",
	)
	await _grab_tool(_driver)
	await _press_tool_at(_driver, _screw.global_position)
	_expect(
		_screw.mode == InteractionPoint.Mode.ACTIVE,
		"the driver engages the screw again",
	)
	await _drive(15.0)
	_expect(
		await _wait_until(
			func() -> bool: return _screw.mode == InteractionPoint.Mode.FINISHED
		),
		"driving the screw in finishes it",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _item.has_finished
		),
		"rescrewed, the Atari is finished",
	)
	await _put_tool_away(_driver)


## Drives an engaged flathead screw, correcting the tip the
## way the screws probe does, for at most `max_sec`.
func _drive(max_sec: float) -> void:
	var frames := roundi(max_sec * Engine.physics_ticks_per_second)
	for frame in frames:
		if (
			_screw.mode != InteractionPoint.Mode.ACTIVE
			or _screw.travel != Screw.Travel.HOME
		):
			return
		var motion := InputEventMouseMotion.new()
		_push_mouse(
			motion,
			_hand.pointer_position
			- _screw.get_slot_axis() * _screw.tip_offset_px,
		)
		await get_tree().physics_frame


func _find_stored_part(part_type: Part.Type) -> Part:
	for drawer in G.level.get_drawers():
		for part in G.level.get_parts_in_drawer(drawer):
			if part.type == part_type:
				return part
	return null


func _open_drawer(drawer: Drawer) -> void:
	await _wait_until(
		func() -> bool: return not drawer.is_busy()
	)
	await _press_at(drawer.global_position)
	await _wait_until(
		func() -> bool: return drawer.state == Drawer.State.OPEN
	)


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()
