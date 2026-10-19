extends "res://tests/probe_base.gd"
## The Atari joystick repair, played end to end with real
## inputs: grab the flathead driver, drive its shell screw
## out, drag the shell off, wiggle the dead joystick out of
## its socket, fetch a new joystick from its drawer and fit
## it, put the shell back, bring the screw back and drive
## it in. The item finishes.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _inside: RepairLayer
var _cover: RepairLayer
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
	_inside = _item.layers[0]
	_cover = _item.layers[_item.layers.size() - 1]
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
		"the Atari has a shell screw and a joystick socket",
	)
	_expect(
		not _socket.is_exposed(),
		"the socket is covered until the shell comes off",
	)
	await _unscrew_shell()
	await _take_shell_off()
	await _yank_and_refit()
	await _rescrew_shell()
	_finish(0 if _failures.is_empty() else 1)


func _unscrew_shell() -> void:
	await _grab_tool(_driver)
	_expect(_hand.held == _driver, "take the flathead driver")
	await _press_tool_at(_driver, _screw.global_position)
	_expect(
		_driver.mode == Tool.Mode.IN_USE
		and _screw.mode == InteractionPoint.Mode.ACTIVE,
		"the driver engages the shell screw",
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
		_cover.is_loose(),
		"with its screw out, the shell is loose",
	)
	await _put_tool_away(_driver)


func _take_shell_off() -> void:
	var grab_point := _cover.global_position + Vector2(-50, 30)
	await _press_down(grab_point)
	await _move_to(Vector2(340, 60))
	await _release_at(Vector2(340, 60))
	await _physics_frames(4)
	_expect(not _cover.is_on, "the shell drags off")
	_expect(
		_socket.is_exposed(),
		"the joystick socket is exposed with the shell off",
	)


func _yank_and_refit() -> void:
	var broken_part := _socket.get_node("BrokenPart") as Node2D
	await _press_down(_socket.global_position)
	await _move_to(_socket.global_position + Vector2(25, 0))
	_expect(
		absf(broken_part.rotation) > 0.01,
		"the dead joystick rocks with the drag",
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
	var part_position := part.global_position
	await _press_down(part_position)
	await _move_to(_socket.global_position)
	await _release_at(_socket.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return _socket.mode == InteractionPoint.Mode.FINISHED
		),
		"the new joystick fits the socket",
	)


func _rescrew_shell() -> void:
	await _wait_until(
		func() -> bool: return not G.level.are_drawers_busy()
	)
	await _press_down(_cover.global_position)
	await _move_to(_item.global_position)
	await _release_at(_item.global_position)
	await _seconds(0.6)
	_expect(
		_cover.is_on and not _cover.is_moving,
		"the shell goes back on",
	)
	_expect(
		_screw.can_come_back(),
		"the screw waits on the bench to come back",
	)
	await _press_resting_screw(_screw)
	_expect(
		await _wait_for_travel(_screw, Screw.Travel.HOME),
		"the screw comes back into the shell",
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
