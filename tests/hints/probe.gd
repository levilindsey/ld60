extends "res://tests/probe_base.gd"
## Idle hint assistance (LX62). Boots the game, checks the repair
## sequence derived from the test box, then stalls on purpose at
## each kind of step: the target lights after the short delay,
## the tool or socket after the longer one, every drawer for a
## fetch, and a correct interaction or a finished step restarts
## the count. The screw microgames have their own probes, so
## screws are finished directly here.
##
## Run it with `tests/run.ps1 -Name hints`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/hints/probe.tscn


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _level: Level
var _item: Repairable
var _socket: PartSocket
var _tracker: HintTracker


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has(
		"--screenshots"
	)
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
	G.settings.hint_delay_sec = 0.25
	G.settings.hint_tool_delay_sec = 0.55
	await _seconds(0.3)
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_level = G.level
	_hand = _level.hand
	_item = _level.active_repairable
	_tracker = _level.hint_tracker
	_socket = _find_socket()
	if not _expect(is_instance_valid(_socket), "the item has a socket"):
		return
	if not _expect(
		is_instance_valid(_tracker), "the level has a hint tracker",
	):
		return
	await _check_sequence()
	await _check_screw_hints()
	await _check_layer_hint()
	await _check_socket_hint()
	await _check_fetch_hints()
	await _check_install_hints()
	await _check_reassembly_hints()
	await _check_ship_hint()


func _check_sequence() -> void:
	var sequence := _item.get_repair_sequence()
	_expect(
		is_instance_valid(sequence), "the item derives a sequence",
	)
	var kinds: Array[int] = []
	for step in sequence.steps:
		kinds.append(step.kind)
	var expected_kinds: Array[int] = [
		RepairStep.Kind.UNSCREW,
		RepairStep.Kind.REMOVE_LAYER,
		RepairStep.Kind.EXTRACT_PART,
		RepairStep.Kind.FETCH_PART,
		RepairStep.Kind.INSTALL_PART,
		RepairStep.Kind.REPLACE_LAYER,
		RepairStep.Kind.RETURN_SCREW,
		RepairStep.Kind.SCREW_IN,
		RepairStep.Kind.SHIP,
	]
	_expect(
		kinds == expected_kinds,
		"the sequence is derived from the layers and the socket",
	)
	_expect(
		sequence.steps[0].points.size() == 2,
		"one unscrew step groups both cover screws",
	)
	_expect(
		sequence.steps[2].socket == _socket,
		"the extraction step names the item's socket",
	)
	await _check_phillips_sequence()
	_expect(
		_tracker.get_current_step().kind == RepairStep.Kind.UNSCREW,
		"the bench starts on the unscrew step",
	)


## A second item, configured another way, derives another
## sequence: no socket, and a REPAIR step only because this probe
## marks its dust and grime required before it enters the tree.
func _check_phillips_sequence() -> void:
	var scene := load(
		"res://src/repairables/test_phillips_repairable.tscn",
	) as PackedScene
	var other := scene.instantiate() as Repairable
	var dust := other.get_node(
		"Layers/Inside/Dust",
	) as InteractionPoint
	dust.is_required = true
	var grime := other.get_node(
		"Layers/Inside/Grime",
	) as InteractionPoint
	grime.is_required = true
	add_child(other)
	var kinds: Array[int] = []
	var repair_step: RepairStep = null
	for step in other.get_repair_sequence().steps:
		kinds.append(step.kind)
		if step.kind == RepairStep.Kind.REPAIR:
			repair_step = step
	var expected_kinds: Array[int] = [
		RepairStep.Kind.UNSCREW,
		RepairStep.Kind.REMOVE_LAYER,
		RepairStep.Kind.REPAIR,
		RepairStep.Kind.REPLACE_LAYER,
		RepairStep.Kind.RETURN_SCREW,
		RepairStep.Kind.SCREW_IN,
		RepairStep.Kind.SHIP,
	]
	_expect(
		kinds == expected_kinds,
		"another item config derives its own sequence",
	)
	_expect(
		is_instance_valid(repair_step)
		and repair_step.points.size() == 2,
		"one repair step groups the dust and the grime",
	)
	# Its drop shadows move themselves a frame after entering.
	await _physics_frames(2)
	remove_child(other)
	other.free()


func _check_screw_hints() -> void:
	_expect(
		_tracker.get_hint_level() == 0,
		"no hint before the first delay",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _tracker.get_hint_level() >= 1,
		),
		"the screw lights after the hint delay",
	)
	var screw := _tracker.get_target_point()
	if not _expect(
		is_instance_valid(screw) and screw.is_hint_active(),
		"the highlighted thing is a cover screw",
	):
		return
	for fastener in _cover_fasteners():
		if fastener != screw:
			_expect(
				not fastener.is_hint_active(),
				"only one of the step's screws lights",
			)
	var tool := _level.tools_by_type[screw.accepted_tools[0]]
	_expect(
		not tool.is_hint_active(),
		"the tool does not light with the screw",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _tracker.get_hint_level() >= 2,
		),
		"the tool lights after the longer delay",
	)
	_expect(
		tool.is_hint_active(),
		"the lit tool is the screw's driver",
	)
	for point in _cover_fasteners():
		point.finish()
	await _physics_frames(3)
	_expect(
		_tracker.get_current_step().kind
		== RepairStep.Kind.REMOVE_LAYER,
		"finishing the screws moves to the layer step",
	)
	_expect(
		_tracker.get_hint_level() == 0 and not screw.is_hint_active()
		and not tool.is_hint_active(),
		"progress clears the hint and restarts the count",
	)


func _check_layer_hint() -> void:
	var cover := _item.get_exposed_layer()
	_expect(
		await _wait_until(
			func() -> bool: return cover.is_hint_active(),
		),
		"the loose cover lights after the delay",
	)
	_expect(
		_tracker.get_target_layer() == cover,
		"the layer step targets the cover",
	)
	await _drag_exposed_layer_off()
	_expect(
		await _wait_until(
			func() -> bool: return _socket.is_exposed(),
		),
		"dragging the cover off exposes the socket",
	)
	_expect(
		_tracker.get_current_step().kind
		== RepairStep.Kind.EXTRACT_PART,
		"the bench moves to the extraction step",
	)
	_expect(
		_tracker.get_hint_level() == 0,
		"dragging the cover off restarts the count",
	)


func _check_socket_hint() -> void:
	_expect(
		await _wait_until(
			func() -> bool: return _socket.is_hint_active(),
		),
		"the socket lights after the delay",
	)
	_expect(
		_tracker.get_target_point() == _socket,
		"the extraction step targets the socket",
	)
	await _seconds(0.5)
	_expect(
		_tracker.get_hint_level() == 1,
		"an empty hand step never lights a tool",
	)
	await _wiggle_socket_out()
	_expect(
		await _wait_until(
			func() -> bool: return not _socket.has_broken_part,
		),
		"the broken part wiggles out",
	)
	_expect(
		_tracker.get_current_step().kind == RepairStep.Kind.FETCH_PART
		and _tracker.is_targeting_drawers(),
		"an empty socket asks for the drawers",
	)
	_expect(
		_tracker.get_hint_level() == 0,
		"wiggling the part out restarts the count",
	)


func _check_fetch_hints() -> void:
	_expect(
		await _wait_until(
			func() -> bool:
				for drawer in _level.get_drawers():
					if not drawer.is_hint_active():
						return false
				return true,
		),
		"every drawer lights for a fetch",
	)
	var part := _find_stored_part(_socket.accepted_part)
	if not _expect(
		is_instance_valid(part), "the fitting part is stocked",
	):
		return
	var drawer := _level.get_drawers()[part.drawer_index]
	await _press_at(drawer.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.OPEN,
		),
		"pressing a drawer opens it",
	)
	_expect(
		not drawer.is_hint_active(),
		"opening a drawer clears the drawer hint",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _tracker.get_target_part() == part,
		),
		"the open drawer aims at the part inside it",
	)
	_expect(
		await _wait_until(
			func() -> bool: return part.is_hint_active(),
		),
		"the stocked part lights after the delay",
	)
	var part_position := part.global_position
	await _press_down(part_position)
	_expect(
		await _wait_until(
			func() -> bool: return not part.is_stored,
		),
		"pressing the part takes it out",
	)
	await _release_at(part_position)
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.CLOSED,
		),
		"the drawer shuts behind the part",
	)


func _check_install_hints() -> void:
	_expect(
		await _wait_until(
			func() -> bool:
				return is_instance_valid(
					_level.get_loose_part_of_type(
						_socket.accepted_part,
					),
				),
		),
		"the fitting part comes to rest loose on the bench",
	)
	_expect(
		await _wait_until(
			func() -> bool:
				return (
					_tracker.get_current_step().kind
					== RepairStep.Kind.INSTALL_PART
				),
		),
		"a loose fitting part moves to the fitting step",
	)
	var part := _level.get_loose_part_of_type(_socket.accepted_part)
	if not _expect(
		is_instance_valid(part), "the fitting part is loose",
	):
		return
	_expect(
		await _wait_until(
			func() -> bool: return part.is_hint_active(),
		),
		"the loose part lights after the delay",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _socket.is_hint_active(),
		),
		"the socket lights after the longer delay",
	)
	_expect(
		_tracker.is_tool_hint_shown(),
		"the longer stage shows for a fitting step",
	)
	await _drag(part.global_position, _socket.global_position)
	_expect(
		await _wait_until(
			func() -> bool:
				return _socket.mode == InteractionPoint.Mode.FINISHED,
		),
		"dragging the part to the socket fits it",
	)
	_expect(
		await _wait_until(
			func() -> bool:
				var step := _tracker.get_current_step()
				return (
					is_instance_valid(step)
					and step.kind == RepairStep.Kind.REPLACE_LAYER
				),
		),
		"a fitted socket moves to replacing the cover",
	)


func _check_reassembly_hints() -> void:
	var cover := _tracker.get_target_layer()
	if not _expect(
		is_instance_valid(cover), "the cover waits to go back",
	):
		return
	await _drag_layer_back(cover)
	_expect(
		await _wait_until(
			func() -> bool: return cover.is_on and not cover.is_moving,
		),
		"the cover goes back on",
	)
	_expect(
		await _wait_until(
			func() -> bool:
				var step := _tracker.get_current_step()
				return (
					is_instance_valid(step)
					and step.kind == RepairStep.Kind.SCREW_IN
				),
		),
		"screws in their holes move to the drive in step",
	)
	_expect(
		await _wait_until(
			func() -> bool:
				var target := _tracker.get_target_point()
				return (
					is_instance_valid(target)
					and target.is_hint_active()
				),
		),
		"a screw to drive in lights after the delay",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _tracker.is_tool_hint_shown(),
		),
		"its driver lights after the longer delay",
	)
	for point in _cover_fasteners():
		point.finish()
	await _physics_frames(3)
	_expect(_item.has_finished, "the item is finished")


func _check_ship_hint() -> void:
	_expect(
		await _wait_until(
			func() -> bool:
				var step := _tracker.get_current_step()
				return (
					is_instance_valid(step)
					and step.kind == RepairStep.Kind.SHIP
					and _tracker.is_targeting_outbox()
				),
		),
		"a finished item moves to the shipping step",
	)
	_expect(
		_level.is_outbox_outline_shown(),
		"the finished item lights the outbox",
	)
	_expect(
		await _wait_until(
			func() -> bool: return _tracker.is_hint_shown(),
		),
		"the shipping hint stands after the delay",
	)
	await _drag(_item.global_position, Vector2(-587.0, 105.0))
	_expect(
		await _wait_until(
			func() -> bool:
				return _level.active_repairable != _item,
		),
		"dragging the item to the outbox ships it",
	)


func _cover_fasteners() -> Array[InteractionPoint]:
	for layer in _item.layers:
		var fasteners := layer.get_fasteners()
		if not fasteners.is_empty():
			return fasteners
	return []


func _drag_exposed_layer_off() -> void:
	var layer := _item.get_exposed_layer()
	for x_offset in range(-80, 81, 20):
		for y_offset in range(-60, 61, 20):
			var point := (
				layer.global_position
				+ Vector2(float(x_offset), float(y_offset))
			)
			if (
				layer.has_point(point)
				and not is_instance_valid(_hand.find_point(point))
			):
				await _press_down(point)
				await _move_to(Vector2(360.0, 60.0))
				await _release_at(Vector2(360.0, 60.0))
				return


func _drag_layer_back(layer: RepairLayer) -> void:
	for x_offset in range(-80, 81, 20):
		for y_offset in range(-60, 61, 20):
			var point := (
				layer.global_position
				+ Vector2(float(x_offset), float(y_offset))
			)
			if layer.has_point(point):
				await _press_down(point)
				await _move_to(layer.get_home_global_position())
				await _release_at(layer.get_home_global_position())
				return


func _wiggle_socket_out() -> void:
	await _press_down(_socket.global_position)
	for swing in 7:
		var offset := 25.0 if swing % 2 == 0 else -25.0
		await _move_to(
			_socket.global_position + Vector2(offset, 0.0),
		)
	await _release_at(_socket.global_position)


func _drag(from: Vector2, to: Vector2) -> void:
	await _press_down(from)
	await _move_to(to)
	await _release_at(to)


func _find_stored_part(part_type: Part.Type) -> Part:
	for part in _level.get_drawer_parts():
		if part.type == part_type and part.is_stored:
			return part
	return null


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
