extends "res://tests/probe_base.gd"
## The diegetic parts drawers. Boots the game and plays the swap
## loop with pushed presses and drags: the drawers are stocked for
## the item, an outside press closes an open drawer, pressing
## another drawer switches to it (even mid-opening), the broken
## gear wiggles out, a part dragged out of a drawer shuts it behind
## itself, the wrong part will not fit, the right one will, a part
## dragged back over a drawer is put away, and a part left out is
## cleaned up into a drawer.
##
## Run it with `tests/run.ps1 -Name parts`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/parts/probe.tscn
## Add `-- --screenshots` (windowed) to save PNGs of the bench to
## `build/tests/parts/`.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _level: Level
var _item: Repairable
var _socket: PartSocket


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
	_check_stocked()

	# Open the cover by finishing its screws directly. The screw
	# microgame has its own probe (tests/screws). The loose cover
	# then has to be dragged off by hand: nothing moves by itself.
	for layer in _item.layers:
		for point in layer.get_points():
			if point is Screw:
				point.finish()
	await _drag_cover_off()
	if not _expect(
		await _wait_until(func() -> bool: return _socket.is_exposed()),
		"the socket is exposed with the cover off",
	):
		return

	await _check_outside_press_closes()
	await _check_drawer_switch()
	await _check_wiggle_out()
	await _check_grab_right_part()
	await _check_right_part_fits()
	await _check_wrong_part()
	await _check_cleanup()


## The drawers hold one part per socket the item needs, plus the
## decoys from settings, all stored and hidden.
func _check_stocked() -> void:
	var stored := _stored_parts()
	_expect(
		stored.size() == 1 + G.settings.decoy_part_count,
		"the drawers hold the needed part plus decoys",
	)
	var needed := 0
	for part in stored:
		if part.type == _socket.accepted_part:
			needed += 1
		_expect(
			part.is_stored and not part.visible,
			"a stocked part starts stored and hidden",
		)
	_expect(needed == 1, "exactly one stocked part fits the socket")


## Drags the item's loose cover off to a clear bench spot.
func _drag_cover_off() -> void:
	var cover := _socket.get_layer()
	for x_offset in range(-80, 81, 20):
		for y_offset in range(-60, 61, 20):
			var point := (
				cover.global_position
				+ Vector2(float(x_offset), float(y_offset))
			)
			if (
				cover.has_point(point)
				and not is_instance_valid(_hand.find_point(point))
			):
				await _press_down(point)
				await _move_to(Vector2(360.0, 60.0))
				await _release_at(Vector2(360.0, 60.0))
				return


func _check_outside_press_closes() -> void:
	var drawer := _level.get_drawers()[0]
	var clipping_space := drawer.get_node(
		"Mover/Scaler/Offset/ClippingSpace"
	) as CanvasItem
	var unclipped := drawer.get_node(
		"Mover/Scaler/Offset/VisualUnclipped"
	) as CanvasItem
	_expect(
		clipping_space.visible and not unclipped.visible,
		"a shut drawer shows its clipped sprite group",
	)
	var rest_top := clipping_space.get_node(
		"Visual/TopPivot"
	) as Node2D
	_expect(
		absf(rest_top.scale.y - 0.16) < 0.01
		and rest_top.position.is_equal_approx(
			Vector2(-811.5, -124.0)
		),
		"at rest the top view is scaled down above the front",
	)
	await _press_at(drawer.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.OPEN
		),
		"a press on a shut drawer opens it in the center",
	)
	_expect(
		not clipping_space.visible and unclipped.visible,
		"an open drawer shows its unclipped sprite group",
	)
	var open_top := unclipped.get_node("TopPivot") as Node2D
	var open_front := unclipped.get_node("FrontPivot") as Node2D
	var open_side := unclipped.get_node("SidePivot") as Node2D
	_expect(
		open_top.scale.is_equal_approx(Vector2.ONE)
		and open_top.position.is_equal_approx(
			Vector2(-907.0, -587.0)
		),
		"an open drawer shows the top view at full size",
	)
	_expect(
		absf(open_front.scale.y - 0.16) < 0.01
		and absf(open_front.skew - (-0.5236)) < 0.01
		and open_side.scale.is_equal_approx(Vector2(0.14, 1.0))
		and absf(open_side.rotation - 1.0472) < 0.01,
		"an open drawer keeps thin front and side strips, turned in",
	)
	await _shot("2_drawer_open")
	for part in _level.get_parts_in_drawer(drawer):
		_expect(part.visible, "an open drawer shows its parts")
	_expect(
		await _wait_until(
			func() -> bool: return _drawer_parts_opaque(drawer)
		),
		"an open drawer's parts fade in",
	)
	var contents_rect := _contents_global_rect(drawer)
	for part in _level.get_parts_in_drawer(drawer):
		_expect(
			contents_rect.has_point(part.global_position),
			"an open drawer's parts rest inside its contents area",
		)
	if not _level.get_parts_in_drawer(drawer).is_empty():
		var part := _level.get_parts_in_drawer(drawer)[0]
		await _move_to(part.global_position)
		_expect_cursor(
			Input.MOUSE_MODE_VISIBLE,
			Input.CURSOR_POINTING_HAND,
			"over a part in the open drawer",
		)
	await _press_at(Vector2(460.0, 290.0))
	_expect(
		await _wait_until(
			func() -> bool: return _drawer_parts_hidden(drawer), 9
		),
		"a closing drawer's parts fade out twice as fast as in",
	)
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.CLOSED
		),
		"a press outside the open drawer closes it",
	)
	_expect(
		clipping_space.visible and not unclipped.visible,
		"a closed drawer shows its clipped sprite group again",
	)
	for part in _level.get_parts_in_drawer(drawer):
		_expect(not part.visible, "a closed drawer hides its parts")


## Pressing another shut drawer while one is open shuts the open
## one and opens the pressed one. The same switch works while the
## first drawer is still opening: it reverses shut first.
func _check_drawer_switch() -> void:
	var drawers := _level.get_drawers()
	var first := drawers[0]
	var second := drawers[1]
	var third := drawers[2]
	await _open_drawer(first)
	await _press_at(second.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return first.state == Drawer.State.CLOSED
		),
		"pressing another drawer shuts the open one",
	)
	_expect(
		await _wait_until(
			func() -> bool: return second.state == Drawer.State.OPEN
		),
		"the pressed drawer opens in its place",
	)
	for part in _level.get_parts_in_drawer(second):
		_expect(part.visible, "the switched-to drawer shows its parts")
	await _press_at(Vector2(460.0, 290.0))
	_expect(
		await _wait_until(
			func() -> bool: return second.state == Drawer.State.CLOSED
		),
		"the switched drawer still closes on an outside press",
	)
	await _press_at(first.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return first.state == Drawer.State.OPENING,
			30,
		),
		"the first drawer starts opening again",
	)
	await _press_at(third.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return first.state == Drawer.State.CLOSED
		),
		"pressing a third drawer reverses the opening one shut",
	)
	_expect(
		await _wait_until(
			func() -> bool: return third.state == Drawer.State.OPEN
		),
		"the third drawer opens after the reversal",
	)
	await _press_at(Vector2(460.0, 290.0))
	_expect(
		await _wait_until(
			func() -> bool: return third.state == Drawer.State.CLOSED
		),
		"the last drawer closes on an outside press",
	)


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
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_DRAG,
		"mid-tug on the broken part",
	)
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


## Finds the stocked part that fits the socket, drags it out of its
## drawer and lets go at once. The drawer is still shutting, so the
## part may not go back in: it is set down on the bench instead.
func _check_grab_right_part() -> void:
	var part := _find_stored_part(_socket.accepted_part)
	if not _expect(is_instance_valid(part), "the fitting part is stocked"):
		return
	var drawer := _level.get_drawers()[part.drawer_index]
	await _open_drawer(drawer)
	if not _expect(part.visible, "the fitting part shows in its drawer"):
		return
	var part_position := part.global_position
	await _press_down(part_position)
	_expect(
		await _wait_until(
			func() -> bool: return not part.is_stored
		),
		"pressing a part in the drawer takes it out",
	)
	await _release_at(part_position)
	_expect(
		not part.is_stored and not part.is_installed and part.visible,
		"a part let go while its drawer shuts stays out on the bench",
	)
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.CLOSED
		),
		"taking a part out shuts the drawer behind it",
	)
	_expect(
		await _wait_until(func() -> bool: return not part.is_returning),
		"a part let go by the drawer comes to rest on the bench",
	)
	_expect(
		not part.z_as_relative and part.z_index > drawer.z_index,
		"a part out of a drawer renders in front of the drawers",
	)
	await _shot("3_part_out")


func _check_right_part_fits() -> void:
	var part := _find_loose_part(_socket.accepted_part)
	if not _expect(is_instance_valid(part), "the fitting part is out"):
		return
	_expect(
		part.z_index > 0 and not part.z_as_relative,
		"a loose part renders over the top of repairables",
	)
	var rotation_before_pickup := part.rotation
	await _press_down(part.global_position)
	await _seconds(0.35)
	var pickup_turn := absf(
		wrapf(part.rotation - rotation_before_pickup, -PI, PI)
	)
	_expect(
		pickup_turn >= Part._TURN_MIN_RAD * 0.9
		and pickup_turn <= Part._TURN_MAX_RAD * 1.1,
		"picking a part up turns it a bit (%.1f deg)"
		% rad_to_deg(pickup_turn),
	)
	var bench_spot := Vector2(-180.0, 80.0)
	var drag_start := part.global_position
	for step in range(1, 7):
		await _move_to(
			drag_start.lerp(bench_spot, float(step) / 6.0)
		)
	var rotation_before_drop := part.rotation
	await _release_at(bench_spot)
	await _seconds(0.35)
	var drop_turn := absf(
		wrapf(part.rotation - rotation_before_drop, -PI, PI)
	)
	_expect(
		not part.is_installed
		and drop_turn >= Part._TURN_MIN_RAD * 0.9
		and drop_turn <= Part._TURN_MAX_RAD * 1.1,
		"setting a part down turns it a bit (%.1f deg)"
		% rad_to_deg(drop_turn),
	)
	await _drag(part.global_position, _socket.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return _socket.mode == InteractionPoint.Mode.FINISHED
		),
		"the right part dragged to the socket finishes it",
	)
	_expect(part.is_installed, "the fitted part is installed")
	_expect(
		absf(wrapf(part.rotation, -PI, PI)) < 0.01,
		"a part fitted into its socket takes its orientation"
		+ " instead of a set-down turn (%.1f deg)"
		% rad_to_deg(part.rotation),
	)
	_expect(
		part.z_index == 0 and part.z_as_relative,
		"an installed part layers with its item again",
	)
	_expect(not _item.has_finished, "the item still waits for its cover")


func _check_wrong_part() -> void:
	var part := _find_wrong_stored_part()
	if not _expect(is_instance_valid(part), "a decoy part is stocked"):
		return
	var drawer := _level.get_drawers()[part.drawer_index]
	await _open_drawer(drawer)
	await _drag(part.global_position, Vector2(-100.0, 40.0))
	_expect(
		not part.is_stored and not part.is_installed,
		"the decoy rests on the bench after its drag",
	)
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.CLOSED
		),
		"the decoy's drawer shut behind it",
	)
	_expect(
		await _wait_until(func() -> bool: return not part.is_returning),
		"the decoy dropped above the bench comes to rest inside it",
	)
	await _drag(part.global_position, _socket.global_position)
	_expect(
		_socket.mode == InteractionPoint.Mode.FINISHED,
		"the socket stays finished under the wrong part",
	)
	_expect(
		not part.is_installed,
		"the wrong part does not install",
	)
	# Drag it back over a shut drawer: it is put away.
	var target := _level.get_drawers()[0]
	await _drag(part.global_position, target.global_position)
	_expect(
		part.is_returning
		and not part.z_as_relative
		and part.z_index < target.z_index,
		"a part going back into a drawer renders behind it",
	)
	_expect(
		await _wait_until(func() -> bool: return part.is_stored),
		"a part dragged over a shut drawer is put away",
	)
	_expect(not part.visible, "a put-away part is hidden again")
	_expect(
		target.state == Drawer.State.CLOSED,
		"the drawer is shut again after the put-away",
	)


func _check_cleanup() -> void:
	var part := _find_any_stored_part()
	if not _expect(is_instance_valid(part), "a part is left to clean up"):
		return
	var drawer := _level.get_drawers()[part.drawer_index]
	await _open_drawer(drawer)
	await _drag(part.global_position, Vector2(-100.0, 40.0))
	_expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.CLOSED
		),
		"the cleanup part's drawer shut behind it",
	)
	_expect(not part.is_stored, "the cleanup part is out on the bench")
	_expect(
		await _wait_until(func() -> bool: return not part.is_returning),
		"the cleanup part comes to rest before it can be tidied",
	)
	var shadow: DropShadow = null
	for sibling in part.get_parent().get_children():
		if sibling is DropShadow and (sibling as DropShadow)._host == part:
			shadow = sibling as DropShadow
	_expect(
		is_instance_valid(shadow) and shadow.size_scale < 1.0,
		"a loose part's shadow is drawn smaller than the part",
	)
	await _check_shadow_turns_with(shadow, part)
	_level.cleanup_loose_parts()
	_expect(
		await _wait_until(func() -> bool: return part.is_stored),
		"cleanup puts a part left out away into a drawer",
	)
	_expect(not part.visible, "a cleaned-up part is hidden again")


## Turns `part` a quarter turn and back, and checks that its
## drop shadow kept the same bearing from it: the shadow's
## offset follows the part's global turn, so the shadow sits
## at the same relative spot however the part itself is turned.
func _check_shadow_turns_with(shadow: DropShadow, part: Part) -> void:
	if not _expect(
		is_instance_valid(shadow),
		"a loose part has a drop shadow to turn with",
	):
		return
	var rest_rotation := part.rotation
	part.rotation = rest_rotation + PI * 0.5
	part.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame
	var expected_offset := shadow.offset_px.rotated(
		part.global_rotation
	)
	var actual_offset := (
		shadow.global_position - part.global_position
	)
	_expect(
		actual_offset.distance_to(expected_offset) < 0.5,
		"a loose part's shadow offset turns with it"
		+ " (offset %s, want %s)" % [actual_offset, expected_offset],
	)
	part.rotation = rest_rotation
	part.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame


func _open_drawer(drawer: Drawer) -> void:
	# A drawer that just put a part away is still shutting its
	# half-open pause. Wait for it to settle before pressing it.
	await _wait_until(
		func() -> bool: return not drawer.is_busy()
	)
	await _press_at(drawer.global_position)
	await _wait_until(
		func() -> bool: return drawer.state == Drawer.State.OPEN
	)


## Presses at `from`, moves to `to` and releases there.
func _drag(from: Vector2, to: Vector2) -> void:
	await _press_down(from)
	await _move_to(to)
	await _release_at(to)


func _stored_parts() -> Array[Part]:
	var parts: Array[Part] = []
	for drawer in _level.get_drawers():
		parts.append_array(_level.get_parts_in_drawer(drawer))
	return parts


func _find_stored_part(part_type: Part.Type) -> Part:
	for part in _stored_parts():
		if part.type == part_type:
			return part
	return null


func _find_wrong_stored_part() -> Part:
	for part in _stored_parts():
		if part.type != _socket.accepted_part:
			return part
	return null


func _find_any_stored_part() -> Part:
	var parts := _stored_parts()
	if parts.is_empty():
		return null
	return parts[0]


func _find_loose_part(part_type: Part.Type) -> Part:
	return _level.get_loose_part_at(_find_loose_position(part_type))


func _find_loose_position(part_type: Part.Type) -> Vector2:
	# The level only answers part lookups by position, so scan the
	# view grid for the loose part of this kind. A part let go in
	# the open drawer can rest above the bench, so scan past it.
	for x in range(-620, 621, 20):
		for y in range(-340, 341, 20):
			var part := _level.get_loose_part_at(
				Vector2(float(x), float(y))
			)
			if is_instance_valid(part) and part.type == part_type:
				return part.global_position
	return Vector2.INF


func _find_socket() -> PartSocket:
	for layer in _item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				return point as PartSocket
	return null


func _drawer_parts_opaque(drawer: Drawer) -> bool:
	for part in _level.get_parts_in_drawer(drawer):
		if part.modulate.a < 0.99:
			return false
	return true


func _drawer_parts_hidden(drawer: Drawer) -> bool:
	for part in _level.get_parts_in_drawer(drawer):
		if part.visible:
			return false
	return true


func _contents_global_rect(drawer: Drawer) -> Rect2:
	var shape_node := (
		(drawer.get_node("%ContentsArea") as Area2D)
		.get_node("CollisionShape2D") as CollisionShape2D
	)
	var shape := shape_node.shape as RectangleShape2D
	var half_size := shape.size * 0.5
	var rect := Rect2(
		shape_node.global_transform * -half_size, Vector2.ZERO
	)
	for corner in [
		half_size,
		Vector2(half_size.x, -half_size.y),
		Vector2(-half_size.x, half_size.y),
	]:
		rect = rect.expand(shape_node.global_transform * corner)
	return rect


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false
