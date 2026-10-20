extends "res://tests/probe_base.gd"
## Trailer driver: boots the real game and plays one short beat
## per run, for capture with Godot's movie writer:
##
##   godot --path . res://trailer/trailer.tscn \
##     --write-movie build/trailer/clips/blast.avi \
##     --fixed-fps 30 --quit-after 180 --resolution 1280x720 \
##     -- --clip=blast
##
## `trailer/record.ps1` runs every clip and cuts the trailer.
## This is a recording tool, not a test: it never fails loudly,
## it just plays. The frame budget (--quit-after) ends the take.

const _MAIN_SCENE_PATH := "res://src/core/main.tscn"

var _clip := ""
var _item: Repairable


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="):
			_clip = arg.trim_prefix("--clip=")
	var main: Node = (
		load(_MAIN_SCENE_PATH) as PackedScene
	).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	var blocker := _RealInputBlocker.new()
	blocker.probe = self
	add_child(blocker)
	_run.call_deferred()


func _run() -> void:
	match _clip:
		"exterior":
			await _clip_exterior()
		"atari_open":
			await _clip_atari_open()
		"tv_whack":
			await _clip_tv_whack()
		"yank_fit":
			await _clip_yank_fit()
		"glue":
			await _clip_glue()
		"blast":
			await _clip_blast()
		"radio":
			await _clip_radio()
		"receipt":
			await _clip_receipt()
		_:
			await _clip_exterior()
	# Hold the last pose until --quit-after ends the take.
	await _seconds(120.0)


## Queues a single item, enters the game and waits for it to
## land. False when the bench never filled.
func _boot(item_type: Repairable.Type) -> bool:
	await _seconds(0.3)
	G.settings.pauses_on_focus_out = false
	G.settings.radio_glitch_item_indices = []
	var queue: Array[Repairable.Type] = [item_type]
	G.settings.item_queue = queue
	G.settings.first_repairable_override = (
		Settings.FirstRepairable.NONE
	)
	G.state.transition(StateMain.State.GAME)
	if not await _wait_for_landing():
		return false
	_hand = G.level.hand
	_item = G.level.active_repairable
	return true


## Polls `condition` once a physics frame, up to `max_frames`.
func _wait_until(condition: Callable, max_frames := 600) -> bool:
	for frame in max_frames:
		if condition.call():
			return true
		await _physics_frames(1)
	return condition.call()


## Where the pointer must sit for the tool's working end to
## land on `target`, once the tool has settled into the hand.
func _tool_pointer(tool: Tool, target: Vector2) -> Vector2:
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


## Holds the tool's working end on `target` for `hold_sec`.
func _hold_tool_at(
	tool: Tool, target: Vector2, hold_sec: float
) -> void:
	var pointer := await _tool_pointer(tool, target)
	await _press_down(pointer)
	await _seconds(hold_sec)
	await _release_at(pointer)


func _first_point(wanted: Script) -> InteractionPoint:
	for layer in _item.layers:
		for point in layer.get_points():
			if is_instance_of(point, wanted) and point.is_exposed():
				return point
	return null


## The door, the sign, then in through the door to the bench.
func _clip_exterior() -> void:
	await _seconds(2.4)
	var door_press := InputEventKey.new()
	door_press.physical_keycode = KEY_SPACE
	door_press.pressed = true
	get_viewport().push_input(door_press, true)
	await _physics_frames(2)
	door_press = InputEventKey.new()
	door_press.physical_keycode = KEY_SPACE
	door_press.pressed = false
	get_viewport().push_input(door_press, true)


## Drive the Atari stick's tab screw out with the flathead
## driver, the way the Atari probe plays it.
func _clip_atari_open() -> void:
	if not await _boot(Repairable.Type.ATARI_JOYSTICK):
		return
	await _seconds(0.8)
	var screw: FlatHeadScrew = null
	for layer in _item.layers:
		for point in layer.get_points():
			if point is FlatHeadScrew:
				screw = point as FlatHeadScrew
	var driver := (
		G.level.tools_by_type[Tool.Type.FLAT_HEAD_SCREW_DRIVER]
		as Tool
	)
	await _grab_tool(driver)
	await _seconds(0.4)
	if is_instance_valid(screw):
		await _press_tool_at(driver, screw.global_position)
		await _drive_flathead(screw, 6.0)
	await _put_tool_away(driver)


## Feeds the engaged flathead screw the small correcting
## motions that keep its tip in the slot while it turns.
func _drive_flathead(screw: FlatHeadScrew, max_sec: float) -> void:
	var frames := roundi(
		max_sec * Engine.physics_ticks_per_second
	)
	for frame in frames:
		if (
			screw.mode != InteractionPoint.Mode.ACTIVE
			or screw.travel != Screw.Travel.HOME
		):
			return
		var motion := InputEventMouseMotion.new()
		_push_mouse(
			motion,
			_hand.pointer_position
			- screw.get_slot_axis() * screw.tip_offset_px,
		)
		await get_tree().physics_frame


## Whack the TV until bench dust bursts out, then blow a
## settled clump away with the air can.
func _clip_tv_whack() -> void:
	if not await _boot(Repairable.Type.TV):
		return
	await _seconds(0.8)
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Tool
	await _grab_tool(hammer)
	await _seconds(0.4)
	for whack in 3:
		var spot := (
			_item.global_position
			+ Vector2(50.0 - 40.0 * whack, -10.0)
		)
		await _hold_tool_at(hammer, spot, 0.3)
		await _seconds(0.5)
	await _put_tool_away(hammer)
	await _seconds(1.2)
	var blower := (
		G.level.tools_by_type[Tool.Type.AIR_BLOWER] as Tool
	)
	await _grab_tool(blower)
	await _seconds(0.4)
	var dusts := G.level.get_bench_dust()
	if not dusts.is_empty():
		await _hold_tool_at(
			blower, (dusts[0] as Node2D).global_position, 1.6
		)
	await _put_tool_away(blower)


## Wiggle a busted key out of the keyboard, fetch the new
## key from its drawer and fit it.
func _clip_yank_fit() -> void:
	if not await _boot(Repairable.Type.KEYBOARD):
		return
	await _seconds(0.8)
	var socket: PartSocket = null
	for layer in _item.layers:
		for point in layer.get_points():
			if (
				point is PartSocket
				and (point as PartSocket).has_tuggable_part()
			):
				socket = point as PartSocket
	if not is_instance_valid(socket):
		return
	# Wiggle the broken key out.
	await _press_down(socket.global_position)
	for swing in 10:
		var offset := 34.0 if swing % 2 == 0 else -34.0
		await _move_to(
			socket.global_position + Vector2(offset, 0.0)
		)
	await _release_at(socket.global_position)
	await _seconds(1.0)
	# Fetch the fitting part from its drawer and fit it.
	var fitting: Part = null
	for part in G.level.get_drawer_parts():
		if part.type == socket.accepted_part and part.is_stored:
			fitting = part
	if not is_instance_valid(fitting):
		return
	var drawer := G.level.get_drawers()[fitting.drawer_index]
	await _press_at(drawer.global_position)
	await _wait_until(
		func() -> bool: return drawer.state == Drawer.State.OPEN
	)
	await _seconds(0.5)
	await _press_down(fitting.global_position)
	await _seconds(0.3)
	var from := fitting.global_position
	var to := socket.global_position
	for step in range(1, 7):
		await _move_to(from.lerp(to, float(step) / 6.0))
	await _release_at(to)
	await _seconds(1.2)


## Squeeze glue onto the Game & Watch's fallen d-pad point,
## then hold the piece on it until it sticks back on.
func _clip_glue() -> void:
	if not await _boot(Repairable.Type.GAME_N_WATCH):
		return
	var piece: BrokenPiece = null
	for candidate in G.level.get_broken_pieces():
		if candidate.starts_detached:
			piece = candidate
	if not is_instance_valid(piece):
		return
	await _wait_until(
		func() -> bool:
			return piece.has_detached() and not piece.is_returning,
	)
	await _seconds(0.4)
	var point := piece.target_point as BrokenPoint
	var glue := G.level.tools_by_type[Tool.Type.GLUE] as Tool
	await _grab_tool(glue)
	await _seconds(0.4)
	await _hold_tool_at(glue, point.global_position, 0.9)
	await _put_tool_away(glue)
	await _seconds(0.4)
	await _press_down(piece.global_position)
	await _seconds(0.3)
	var from := piece.global_position
	var to := point.global_position
	for step in range(1, 7):
		await _move_to(from.lerp(to, float(step) / 6.0))
	await _seconds(3.4)
	await _release_at(to)
	await _seconds(0.8)


## The first hammer hit sets the shrink ray off and shrinks
## the hammer; one tiny hit lands for good measure.
func _clip_blast() -> void:
	if not await _boot(Repairable.Type.SHRINK_RAY):
		return
	await _seconds(0.8)
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Hammer
	await _grab_tool(hammer)
	await _seconds(0.4)
	await _hold_tool_at(
		hammer, _item.global_position + Vector2(30, -30), 0.3
	)
	await _seconds(2.2)
	await _hold_tool_at(
		hammer, _item.global_position + Vector2(-20, 10), 0.25
	)
	await _seconds(0.8)
	await _put_tool_away(hammer)


## The desk radio goes wonky; a hammer bonk fixes it.
func _clip_radio() -> void:
	if not await _boot(Repairable.Type.TV):
		return
	await _seconds(0.6)
	var radio := G.level.get_node("Radio") as Radio
	radio.glitch_highlight_delay_sec = 1.4
	radio.set_glitching(true)
	await _seconds(2.0)
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Tool
	await _grab_tool(hammer)
	await _seconds(0.4)
	await _hold_tool_at(hammer, radio.get_art_center(), 0.3)
	await _seconds(1.2)
	await _put_tool_away(hammer)


## Finish the TV and send it off: the receipt card rates it.
func _clip_receipt() -> void:
	if not await _boot(Repairable.Type.TV):
		return
	await _seconds(0.8)
	_item.complete_for_dev()
	await _seconds(1.2)
	# Out through the real outbox path: that is what connects
	# the departure to the receipt card.
	G.level._send_to_outbox(_item)
	# Hold on the lifted receipt once it is up.
	var card := G.level.get_node("TicketCard") as TicketCard
	await _wait_until(
		func() -> bool:
			return card.state == TicketCard.State.SHOWING_DONE,
		300,
	)
	await _seconds(2.0)
