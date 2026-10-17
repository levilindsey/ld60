extends "res://tests/probe_base.gd"
## The item flow (LX9). Boots the game with a two-item queue and plays the
## item flow with pushed presses: the arrival, the ticket, an unfinished
## item that won't drag, finishing, dragging and the ease back, the outbox,
## the receipt, the next item, a defect popup, the credits and a restart.
##
## Run it with `tests/run.ps1 -Name item_flow`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/item_flow/probe.tscn
## Add `-- --screenshots` (windowed, a few seconds) to save PNGs to
## `build/tests/item_flow/`. Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0
## Where a dragged item is dropped when it must not reach the outbox,
## relative to the bench.
const _AWAY_OFFSET := Vector2(220.0, -150.0)
## A spot inside the outbox, relative to its origin.
const _OUTBOX_INSIDE_OFFSET := Vector2(10.0, 0.0)
const _POPUP_GROUP := "defect_popups"

var _level: Level
var _item: Repairable
var _spawn_ticks: Array[int] = []
var _departed_tick := 0
var _landed_msec := 0
var _landed_position := Vector2.ZERO
var _landed_rotation := 0.0
var _landed_mode := -1
var _departed_msec := 0
var _largest_shake_px := 0.0
var _largest_shake_before_landing_px := 0.0
var _popup: DefectPopup
var _is_popup_alive_at_departure := false


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has("--screenshots")
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	# The probe runs ALWAYS so it can step through the pause. The game
	# must pause the way it does under the root window.
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	if _is_taking_screenshots:
		var blocker := _RealInputBlocker.new()
		blocker.probe = self
		add_child(blocker)
	get_tree().physics_frame.connect(_on_physics_frame)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	_expect(G.state.state == StateMain.State.TITLE, "boot shows the title")
	_check_configuration()
	G.state.transition(StateMain.State.GAME)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	_bind_level()
	await _check_arrival()
	if not is_instance_valid(_item):
		return
	await _check_unfinished_press()
	await _check_finish()
	await _check_drag_and_return()
	await _check_pause_while_dragging()
	await _check_outbox()
	await _check_next_item()
	await _check_second_item()
	await _check_credits()
	await _check_restart()


func _check_configuration() -> void:
	var queue_text := str(G.settings.item_queue)
	_expect(
		G.settings.item_queue.size() == 3
		and G.settings.item_queue[0]
		== Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
		"settings.tres loads the three-item queue (got %s)" % queue_text,
	)
	_expect(
		G.settings.finished_outline_material is ShaderMaterial,
		"settings.tres loads the outline material",
	)
	_expect(
		is_instance_valid(G.settings.finish_sparkle_scene),
		"settings.tres loads the sparkle scene",
	)
	# The probe plays a queue of two.
	var queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
	]
	G.settings.item_queue = queue


func _check_arrival() -> void:
	_item = _level.active_repairable
	if not _expect(is_instance_valid(_item), "1. the first item is spawned"):
		return
	var spawn: Vector2 = _level.get_node("%ItemSpawnPosition").global_position
	var home := _home()
	var ticket: TicketCard = _level.get_node("%TicketCard")
	_expect(
		_item.mode == Repairable.Mode.ENTERING
		and _item.global_position.is_equal_approx(spawn),
		"1. the item starts at the spawn point, arriving",
	)
	_expect(
		absf(_item.rotation)
		<= deg_to_rad(G.settings.item_arrival_angle_max_deg) + 0.001,
		"it starts turned by no more than the arrival angle (%.3f rad)"
		% _item.rotation,
	)
	await _seconds(0.25)
	_expect(
		_item.mode == Repairable.Mode.ENTERING
		and _item.global_position.y > spawn.y + 100.0,
		"1. the item is on its way down (y %.0f)" % _item.global_position.y,
	)
	_expect(not ticket.visible, "the ticket waits for the landing")
	# An arriving item takes no presses.
	await _press_at(home)
	_expect(
		not is_instance_valid(_item._shake_tween) and _hand.is_empty(),
		"an arriving item takes no press",
	)
	var has_landed := await _wait_until(
		func() -> bool: return _landed_msec > 0,
		2.0,
	)
	if not _expect(has_landed, "1. the item lands"):
		return
	_expect(
		_landed_position.distance_to(home) < 0.5
		and is_zero_approx(_landed_rotation)
		and _landed_mode == Repairable.Mode.UNDER_REPAIR,
		"1. it lands at the active position, straight, under repair "
		+ "(at %s, turned %.4f, mode %d)"
		% [_landed_position, _landed_rotation, _landed_mode],
	)
	_expect(
		_largest_shake_before_landing_px == 0.0,
		"the camera is still until the item lands",
	)
	await _shot("1_landed")
	await _seconds(0.45)
	var camera: Camera2D = _level.get_node("%Camera2D")
	_expect(
		_largest_shake_px > 0.5,
		"1. the landing shakes the camera (peak %.1f px)" % _largest_shake_px,
	)
	_expect(camera.offset == Vector2.ZERO, "the shake settles")
	_expect(
		_item.quality.repair_time_sec > 0.3
		and _item.quality.repair_time_sec < 0.9,
		"the repair clock starts at the landing (%.2f s)"
		% _item.quality.repair_time_sec,
	)
	var name_label: Label = ticket.get_node("%NameLabel")
	var complaint_label: Label = ticket.get_node("%ComplaintLabel")
	var slide: Control = ticket.get_node("%Slide")
	_expect(
		ticket.visible
		and name_label.text == _item.item_name
		and complaint_label.text == _item.ticket
		and is_zero_approx(slide.position.x),
		"1. the ticket slides in with the name and the complaint",
	)


func _check_unfinished_press() -> void:
	var home := _home()
	var away := home + _AWAY_OFFSET
	await _press_down(home)
	_expect(_hand.is_empty(), "2. pressing an unfinished item picks nothing up")
	_expect(
		is_instance_valid(_item._shake_tween),
		"2. an unfinished item shakes when pressed",
	)
	await _move_to(away)
	_expect(
		_item.global_position.distance_to(home) < 0.5,
		"2. an unfinished item doesn't follow the pointer",
	)
	await _release_at(away)
	_expect(
		_hand.is_empty()
		and _level.active_repairable == _item
		and _item.mode == Repairable.Mode.UNDER_REPAIR
		and _item.global_position.distance_to(home) < 0.5,
		"2. releasing away from the item changes nothing",
	)
	await _seconds(0.4)


func _check_finish() -> void:
	var is_finished := await _finish_item(_item)
	_expect(
		is_finished
		and _item.is_finished()
		and _events.count("finished") == 1,
		"3. finishing its points finishes the item, once",
	)
	_expect(
		_has_sparkle(_item),
		"3. a sparkle bursts from the finished item",
	)
	var stopped_sec := _item.quality.repair_time_sec
	await _seconds(0.5)
	_expect(
		is_instance_valid(_item._glow_tween)
		and _item.modulate != Color.WHITE,
		"3. the finished item glows",
	)
	_expect(
		is_equal_approx(_item.quality.repair_time_sec, stopped_sec),
		"the repair clock stops at the finish (%.2f s)" % stopped_sec,
	)
	await _move_to(_item.global_position)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_POINTING_HAND,
		"empty hand over the finished item",
	)
	await _shot("2_finished")
	await _seconds(0.8)
	_expect(not _has_sparkle(_item), "the sparkle frees itself")


func _check_drag_and_return() -> void:
	var home := _home()
	var away := home + _AWAY_OFFSET
	# A press over a finished screw still picks the item up.
	var screw: Node2D = _item.get_node("Layers/Cover/ScrewLeft")
	await _press_down(screw.global_position)
	_expect(
		_hand.held == _item,
		"4. a press on a finished item's screw picks the item up",
	)
	await _release_at(screw.global_position)
	await _seconds(0.5)
	# Pick it up by its middle.
	await _press_down(home)
	_expect(_hand.held == _item, "4. pressing the finished item picks it up")
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_DRAG,
		"dragging the item",
	)
	await _move_to(away)
	_expect(
		_item.global_position.distance_to(away) < 1.0,
		"4. the item follows the pointer",
	)
	_expect(
		_item.rotation > 0.01,
		"4. a drag to the right tilts it clockwise (%.3f rad)" % _item.rotation,
	)
	await _physics_frames(60)
	_expect(
		absf(_item.rotation) < 0.005,
		"the tilt settles when the pointer rests (%.4f rad)" % _item.rotation,
	)
	var drop_point := away + Vector2(-100.0, 0.0)
	await _move_to(drop_point)
	_expect(
		_item.rotation < -0.01,
		"4. a drag to the left tilts it counterclockwise (%.3f rad)"
		% _item.rotation,
	)
	await _shot("3_drag")
	await _release_at(drop_point)
	_expect(
		_hand.is_empty()
		and _level.active_repairable == _item
		and _item.mode == Repairable.Mode.UNDER_REPAIR,
		"4. dropping it away from the outbox keeps it on the bench",
	)
	var start_distance := _item.global_position.distance_to(home)
	await _seconds(0.1)
	var middle_distance := _item.global_position.distance_to(home)
	_expect(
		middle_distance > 1.0 and middle_distance < start_distance,
		"4. it eases back (%.0f px, then %.0f px)"
		% [start_distance, middle_distance],
	)
	await _seconds(0.45)
	_expect(
		_item.global_position.distance_to(home) < 0.5
		and is_zero_approx(_item.rotation),
		"4. it rests at the active position, straight",
	)
	_expect(_item.has_finished, "and it is still finished")


func _check_pause_while_dragging() -> void:
	var home := _home()
	var away := home + _AWAY_OFFSET
	await _press_down(home)
	await _move_to(away)
	_expect(_hand.held == _item, "dragging again")
	G.state.transition(StateMain.State.PAUSE)
	await _physics_frames(2)
	_expect(_hand.is_empty(), "4. pausing while dragging lets go of the item")
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.6)
	_expect(
		_item.global_position.distance_to(home) < 0.5,
		"and it eases back to the bench after the pause",
	)
	# The mouse button comes up after all that.
	await _release_at(away)
	_expect(
		_hand.is_empty() and _level.active_repairable == _item,
		"a late release does nothing",
	)


func _check_outbox() -> void:
	var home := _home()
	var outbox: Area2D = _level.get_node("%Outbox")
	var inside := outbox.global_position + _OUTBOX_INSIDE_OFFSET
	var ticket: TicketCard = _level.get_node("%TicketCard")
	var receipt: Receipt = _level.get_node("%Receipt")
	var leaving_item := _item
	var item_name := _item.item_name
	var score := _item.quality.get_score()
	_departed_msec = 0
	await _press_down(home)
	await _move_to(inside)
	# The overlap shows up a few physics frames after the item moves.
	await _physics_frames(4)
	_expect(
		_hand.held == leaving_item
		and outbox.overlaps_area(leaving_item.drop_area),
		"5. the dragged item overlaps the outbox",
	)
	await _shot("4_outbox")
	await _release_at(inside)
	_expect(
		leaving_item.mode == Repairable.Mode.LEAVING
		and _level.active_repairable == null
		and _hand.is_empty(),
		"5. dropping it on the outbox sends it off",
	)
	var has_hidden := await _wait_until(
		func() -> bool: return not ticket.visible,
		1.0,
	)
	_expect(has_hidden, "5. the ticket goes away with the item")
	var has_departed := await _wait_until(
		func() -> bool: return _departed_msec > 0,
		2.0,
	)
	_expect(has_departed, "5. the item slides off the screen")
	_expect(not is_instance_valid(leaving_item), "5. and is freed")
	var name_label: Label = receipt.get_node("%NameLabel")
	var total_label: Label = receipt.get_node("%TotalLabel")
	_expect(
		receipt.visible
		and name_label.text == item_name
		and total_label.text == str(score),
		"5. the receipt opens with the item's score (%d, shows %s)"
		% [score, total_label.text],
	)
	_expect(
		receipt.mouse_filter == Control.MOUSE_FILTER_STOP,
		"the open receipt takes the clicks",
	)


func _check_next_item() -> void:
	var receipt: Receipt = _level.get_node("%Receipt")
	_landed_msec = 0
	var has_spawned := await _wait_until(
		func() -> bool: return is_instance_valid(_level.active_repairable),
		2.0,
	)
	if not _expect(has_spawned, "5. the next item arrives"):
		return
	_item = _level.active_repairable
	# Counted in physics ticks, so a screenshot's stall doesn't count.
	var delay_ticks: int = _spawn_ticks.back() - _departed_tick
	var delay_sec := float(delay_ticks) / Engine.physics_ticks_per_second
	_expect(
		delay_sec >= 0.45 and delay_sec <= 0.65,
		"5. it starts 0.5 s after the receipt opens (%.2f s)" % delay_sec,
	)
	_expect(
		_item.mode == Repairable.Mode.ENTERING
		and _level.next_item_index == 2,
		"it is the second item of the queue",
	)
	var has_landed := await _wait_until(
		func() -> bool: return _landed_msec > 0,
		2.0,
	)
	_expect(has_landed, "the second item lands")
	_expect(
		receipt.visible,
		"the receipt is still open when the next item lands",
	)
	await _shot("5_receipt")
	# The click that closes the receipt doesn't reach the bench.
	await _press_at(_home())
	_expect(
		not is_instance_valid(_item._shake_tween),
		"6. the click that closes the receipt doesn't reach the bench",
	)
	await _seconds(0.6)
	_expect(not receipt.visible, "6. the click closed the receipt")
	_expect(
		not _level.has_won and G.state.state == StateMain.State.GAME,
		"6. the first receipt closing doesn't end the game",
	)


func _check_second_item() -> void:
	var receipt: Receipt = _level.get_node("%Receipt")
	var outbox: Area2D = _level.get_node("%Outbox")
	var inside := outbox.global_position + _OUTBOX_INSIDE_OFFSET
	var item := _level.active_repairable
	_expect(await _finish_item(item), "the second item finishes")
	await _seconds(0.3)
	var defect_position := item.global_position + Vector2(20.0, -20.0)
	var popup_count := get_tree().get_nodes_in_group(_POPUP_GROUP).size()
	var points := item.quality.add_defect(
		RepairQuality.Defect.DENT_SMALL,
		defect_position,
	)
	var popups := get_tree().get_nodes_in_group(_POPUP_GROUP)
	var popup: DefectPopup = null
	if popups.size() == popup_count + 1:
		popup = popups.back() as DefectPopup
	var popup_label: Label = null
	if popup != null:
		popup_label = popup.get_node("%Label")
	_expect(
		popup != null
		and popup.get_parent() == _level
		and popup_label.text == "-%d" % points
		and popup.global_position.distance_to(defect_position) < 1.0,
		"7. a defect spawns a popup with its points, at the defect (-%d)"
		% points,
	)
	await _shot("6_defect")
	var score := item.quality.get_score()
	_expect(score == 100 - points, "the defect costs its points (%d)" % score)
	# Send the item off before the popup is gone.
	_popup = popup
	_departed_msec = 0
	await _press_down(_home())
	await _move_to(inside)
	await _physics_frames(4)
	await _release_at(inside)
	var has_departed := await _wait_until(
		func() -> bool: return _departed_msec > 0,
		2.0,
	)
	_expect(has_departed, "the second item leaves through the outbox")
	_expect(
		_is_popup_alive_at_departure,
		"7. the popup outlives the item that left",
	)
	var total_label: Label = receipt.get_node("%TotalLabel")
	_expect(
		receipt.visible and total_label.text == str(score),
		"the second receipt shows the score with the defect (%d, shows %s)"
		% [score, total_label.text],
	)
	var has_defect_row := false
	var lines: Node = receipt.get_node("%Lines")
	for row in lines.get_children():
		var first_label := row.get_child(0) as Label
		if first_label != null and first_label.text.begins_with("Small dent"):
			has_defect_row = true
	_expect(has_defect_row, "7. the receipt lists the defect")
	await _seconds(1.0)
	_expect(
		_level.active_repairable == null
		and _level.next_item_index == 2
		and not _level.has_won
		and receipt.visible,
		"the queue is done: no third item, and the game waits for the receipt",
	)


func _check_credits() -> void:
	var has_won := await _wait_until(
		func() -> bool: return _level.has_won,
		5.0,
	)
	_expect(has_won, "8. the last receipt closing wins the game")
	_expect(
		G.state.state == StateMain.State.CREDITS,
		"8. the game reaches the credits",
	)
	_expect(
		get_tree().get_nodes_in_group(_POPUP_GROUP).is_empty(),
		"no defect popup is left behind",
	)


func _check_restart() -> void:
	var old_level_id := _level.get_instance_id()
	G.state.transition(StateMain.State.GAME)
	var has_restarted := await _wait_until(
		func() -> bool:
			return (
				is_instance_valid(G.level)
				and G.level.get_instance_id() != old_level_id
			),
		3.0,
	)
	if not _expect(has_restarted, "9. a restart starts a fresh level"):
		return
	_bind_level()
	_item = _level.active_repairable
	_expect(
		is_instance_valid(_item)
		and _level.next_item_index == 1
		and not _level.has_won,
		"9. the fresh level starts the queue over",
	)
	var has_landed := await _wait_until(
		func() -> bool: return _landed_msec > 0,
		2.0,
	)
	_expect(has_landed, "9. and its first item lands")


## Connects the flow signals of the level's items, starting with the one
## that is already on its way.
func _bind_level() -> void:
	_level = G.level
	_hand = _level.hand
	_landed_msec = 0
	(_level.get_node("%Repairables") as Node).child_entered_tree.connect(
		_on_item_added
	)
	if is_instance_valid(_level.active_repairable):
		_on_item_added(_level.active_repairable)


func _on_item_added(node: Node) -> void:
	var item := node as Repairable
	if item == null:
		return
	_spawn_ticks.append(Engine.get_physics_frames())
	item.landed.connect(_on_landed.bind(item))
	item.finished.connect(func() -> void: _events.append("finished"))
	item.departed.connect(_on_departed)


func _on_landed(item: Repairable) -> void:
	_landed_msec = Time.get_ticks_msec()
	_landed_position = item.global_position
	_landed_rotation = item.rotation
	_landed_mode = item.mode
	_largest_shake_before_landing_px = _largest_shake_px


func _on_departed() -> void:
	_departed_msec = Time.get_ticks_msec()
	_departed_tick = Engine.get_physics_frames()
	_is_popup_alive_at_departure = is_instance_valid(_popup)


func _on_physics_frame() -> void:
	if not is_instance_valid(G.level):
		return
	var camera: Camera2D = G.level.get_node("%Camera2D")
	_largest_shake_px = maxf(_largest_shake_px, camera.offset.length())


func _home() -> Vector2:
	return _level.get_node("%ActiveItemPosition").global_position


## Finishes every point that still needs work, without a tool.
func _finish_points(item: Repairable) -> void:
	for point in item.get_remaining_points():
		point.finish()


## Finishes an item without a tool, the way the tools would. Finishing the
## fasteners takes the cover off, a press puts the cover back, and
## finishing the fasteners again drives them in. Returns whether the item
## ended up finished.
func _finish_item(item: Repairable) -> bool:
	_finish_points(item)
	var is_ready := await _wait_until(
		func() -> bool: return _is_next_layer_ready(item),
		3.0,
	)
	if not is_ready:
		return false
	var layer := item.get_next_layer_to_put_back()
	await _press_at(layer.global_position)
	var is_back := await _wait_until(
		func() -> bool: return layer.is_on and not layer.is_moving,
		3.0,
	)
	if not is_back:
		return false
	_finish_points(item)
	return item.has_finished


func _is_next_layer_ready(item: Repairable) -> bool:
	var layer := item.get_next_layer_to_put_back()
	return is_instance_valid(layer) and layer.is_ready_to_go_back()


func _has_sparkle(item: Repairable) -> bool:
	for child in item.get_children():
		if child is CPUParticles2D:
			return true
	return false


## Polls once per physics frame until the condition holds or the limit
## passes. Returns whether it held.
func _wait_until(condition: Callable, limit_sec: float) -> bool:
	var frame_count := int(limit_sec * Engine.physics_ticks_per_second)
	for index in frame_count:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()
