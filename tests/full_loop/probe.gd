extends "res://tests/probe_base.gd"
## The full loop (LX7, LX8). Boots the game, plays the repair loop with
## pushed presses and checks the hand, the driver, the layers and the
## cursor at each step.
##
## Run it with `tests/run.ps1 -Name full_loop`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/full_loop/probe.tscn
## Add `-- --booklet` to check that the booklet in the demo level still
## gets its presses instead. Exit code 0 means every check passed.
## Add `-- --screenshots` (windowed, with `--debug-collisions`) to save
## PNGs of the bench at a few steps to `build/tests/full_loop/`.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _DEMO_LEVEL_PATH := "res://src/level/zaven_demo/zaven_demo_level.tscn"
# m1-screws: 45 s was enough for the stand-in. The real twists take about
# 16 s more.
const _TIMEOUT_SEC := 120.0
## A spot on the bench with nothing to take.
const _AWAY_POSITION := Vector2(-560.0, -300.0)
## On the closed booklet's right half, clear of the item.
const _BOOKLET_POSITION := Vector2(120.0, -100.0)

var _exit_mouse_mode := -1
var _exit_cursor_shape := -1
var _largest_head_scale_change := 0.0
var _head_scale_samples := 0

var _level: Level
var _tool: Tool
var _item: Repairable
var _inside: RepairLayer
var _cover: RepairLayer
var _screw_left: Screw
var _screw_right: Screw
var _holder_position := Vector2.ZERO


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	var is_booklet := OS.get_cmdline_user_args().has("--booklet")
	_is_taking_screenshots = OS.get_cmdline_user_args().has("--screenshots")
	if is_booklet:
		G.level_scene_override_path = _DEMO_LEVEL_PATH
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
	if is_booklet:
		await _run_booklet()
	else:
		await _run_loop()
	_finish(0 if _failures.is_empty() else 1)


func _run_loop() -> void:
	await _seconds(0.3)
	_expect(G.state.state == StateMain.State.TITLE, "boot shows the title")
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	# LX9: the item arrives by tween and takes presses once it lands.
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_collect_nodes()
	get_tree().process_frame.connect(_track_head_scale)

	await _shot("1_start")
	await _check_start()
	await _check_empty_hand_presses()
	await _check_take_driver()
	await _check_nope()
	await _check_take_cover_off()
	await _shot("3_set_aside")
	await _check_put_driver_back()
	await _check_put_cover_back()
	await _shot("4_reassembled")
	await _check_pause()
	await _check_drive_screws_in()
	await _check_finished_item()
	# Before the restart frees these screws.
	get_tree().process_frame.disconnect(_track_head_scale)
	_expect(
		_head_scale_samples > 100 and _largest_head_scale_change < 0.0001,
		"Levi: a screw head never scales (largest change %.4f in %d frames)"
		% [_largest_head_scale_change, _head_scale_samples],
	)
	await _check_level_exit()


func _run_booklet() -> void:
	await _seconds(1.0)
	if not _expect(is_instance_valid(G.level), "the demo level is running"):
		return
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_collect_nodes()
	var manual: InstructionManual = _level.get_node("InstructionManual")
	_expect(manual.state == InstructionManual.State.CLOSED, "booklet starts closed")
	await _press_at(_BOOKLET_POSITION)
	_expect(
		manual.state != InstructionManual.State.CLOSED,
		"a press on the booklet reaches it past the hand",
	)
	await _seconds(1.0)
	_expect(manual.state == InstructionManual.State.IDLE, "the booklet opens")
	# A press on the item under the booklet goes to the item.
	await _press_at(_item.global_position)
	_expect(
		(_item.get_node("Layers") as Node2D).position != Vector2.ZERO,
		"a press on the item over the booklet shakes the item",
	)


func _collect_nodes() -> void:
	_level = G.level
	_hand = _level.hand
	_tool = _level.tools_by_type[Tool.Type.FLAT_HEAD_SCREW_DRIVER]
	_item = _level.active_repairable
	_inside = _item.get_node("Layers/Inside")
	_cover = _item.get_node("Layers/Cover")
	_screw_left = _cover.get_node("ScrewLeft")
	_screw_right = _cover.get_node("ScrewRight")
	_holder_position = _level.get_tool_holder_position(
		Tool.Type.FLAT_HEAD_SCREW_DRIVER
	)
	_item.layer_removed.connect(
		func(layer: RepairLayer) -> void:
			_events.append("layer_removed:%s" % layer.name)
	)
	_item.layer_installed.connect(
		func(layer: RepairLayer) -> void:
			_events.append("layer_installed:%s" % layer.name)
	)
	_item.point_finished.connect(
		func(point: InteractionPoint) -> void:
			_events.append("point_finished:%s" % point.name)
	)
	_item.finished.connect(func() -> void: _events.append("finished"))


func _check_start() -> void:
	_expect(_tool.mode == Tool.Mode.STORED, "the driver starts stored")
	_expect(_hand.is_empty(), "the hand starts empty")
	_expect(
		_tool._get_holder_shape().global_position.distance_to(
			_holder_position
		) < 1.0,
		"LX4: the stored driver's holder shape sits on the holder",
	)
	await _move_to(_AWAY_POSITION)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_ARROW,
		"empty hand over nothing",
	)
	await _move_to(_holder_position)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_POINTING_HAND,
		"empty hand over the rack tool",
	)
	await _move_to(_item.global_position)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_ARROW,
		"empty hand over the unfinished item",
	)


func _check_empty_hand_presses() -> void:
	await _press_at(_screw_left.global_position)
	_expect(
		_screw_left.mode == InteractionPoint.Mode.UNSTARTED
		and absf(_screw_left.rotation) > 0.001,
		"rule 6: the empty hand pokes a screw",
	)
	await _seconds(0.5)
	await _press_at(_item.global_position)
	var layers_node: Node2D = _item.get_node("Layers")
	_expect(
		layers_node.position != Vector2.ZERO,
		"rule 7: the unfinished item shakes",
	)
	_expect(
		_screw_left.scale.x > 1.0 and _screw_right.scale.x > 1.0,
		"rule 7: the remaining screws pulse",
	)
	_expect(
		_hand.is_empty() and not _item.has_finished,
		"rule 7: nothing else changes",
	)
	await _seconds(0.5)
	_expect(
		layers_node.position == Vector2.ZERO
		and _screw_left.scale.is_equal_approx(Vector2.ONE),
		"rule 7: the shake and the pulse settle",
	)


func _check_take_driver() -> void:
	await _press_at(_holder_position)
	_expect(
		_hand.held == _tool and _tool.mode == Tool.Mode.HELD,
		"1. take the driver from its holder",
	)
	_expect(
		_tool.get_tip_position().distance_to(_holder_position) > 10.0,
		"LX5: the driver glides into the hand instead of jumping",
	)
	_expect_cursor(
		Input.MOUSE_MODE_HIDDEN,
		Input.CURSOR_ARROW,
		"holding a tool",
	)
	await _seconds(0.4)
	_expect(
		_tool.get_tip_position().distance_to(_holder_position) < 1.0,
		"the driver's tip follows the pointer",
	)


func _check_nope() -> void:
	var saved_tools := _screw_left.accepted_tools
	var no_tools: Array[Tool.Type] = []
	_screw_left.accepted_tools = no_tools
	await _press_at(_screw_left.global_position)
	var nope_icon: Node2D = _level.get_node("%NopeIcon")
	_expect(nope_icon.visible, "a wrong tool shows the nope icon")
	_expect(_tool._shake_offset != Vector2.ZERO, "a wrong tool shakes")
	_expect(
		_hand.held == _tool and _tool.mode == Tool.Mode.HELD,
		"a wrong tool stays in the hand",
	)
	_expect(
		_screw_left.mode == InteractionPoint.Mode.UNSTARTED,
		"a wrong tool leaves the point unstarted",
	)
	_screw_left.accepted_tools = saved_tools
	await _shot("2_nope")
	_expect(
		_screw_right.accepted_tools.has(Tool.Type.FLAT_HEAD_SCREW_DRIVER),
		"the other screw kept its own accepted tools",
	)
	await _seconds(0.8)
	_expect(not nope_icon.visible, "the nope icon hides again")
	_expect(
		_tool._shake_offset == Vector2.ZERO,
		"the nope shake settles",
	)


func _check_take_cover_off() -> void:
	await _press_at(_screw_left.global_position)
	_expect(
		_tool.mode == Tool.Mode.IN_USE
		and _screw_left.mode == InteractionPoint.Mode.ACTIVE,
		"2. the driver engages the first screw",
	)
	# A rack press while a point has the tool does nothing, and the point
	# keeps the tool where it is.
	# m1-screws: a tap, not a move and a press. The screw owns the pointer
	# now, and motion along its slot moves the tip.
	await _tap_at(_holder_position)
	_expect(
		_tool.mode == Tool.Mode.IN_USE and _hand.held == _tool,
		"a rack press waits while the driver is in use",
	)
	_expect(
		_tool.get_tip_position().distance_to(_screw_left.global_position)
		< 1.0,
		"IN_USE: the point holds the driver, not the pointer",
	)
	# m1-screws: tap back over the screw, then keep the tip centered
	# instead of waiting out the stand-in.
	await _tap_at(_screw_left.global_position)
	await _drive(_screw_left, 0.8)
	_expect(
		_screw_left.head.rotation < -0.01,
		"the twists turn the screw counter-clockwise",
	)
	await _drive(_screw_left, 10.0)
	# The hop off.
	await _seconds(0.3)
	_expect(
		_screw_left.mode == InteractionPoint.Mode.FINISHED
		and not _screw_left.visible,
		"2. the first screw comes out",
	)
	_expect(
		is_equal_approx(
			_screw_left.head.rotation,
			-deg_to_rad(G.settings.flathead_twist_angle_deg)
			* (_screw_left as FlatHeadScrew).twists_needed,
		),
		"it turned counter-clockwise by all its twists before it came out",
	)
	_expect(
		_tool.mode == Tool.Mode.HELD and _hand.held == _tool,
		"the driver comes back to the hand",
	)
	_expect(
		_cover.is_on and not _cover.is_moving,
		"the cover stays on while a screw holds it",
	)

	await _press_at(_screw_right.global_position)
	# m1-screws: was `await _seconds(0.5)`.
	await _drive(_screw_right, 10.0)
	_expect(
		_screw_right.mode == InteractionPoint.Mode.FINISHED,
		"2. the second screw comes out",
	)
	_expect(_cover.is_moving, "3. the loose cover starts to lift")
	await _seconds(0.9)
	var spot := _level.get_set_aside_spot()
	_expect(
		_cover.get_parent() == spot,
		"3. the cover moves to the set-aside spot",
	)
	_expect(
		not _cover.is_on and not _cover.is_moving,
		"3. the cover is off and resting",
	)
	_expect(
		_cover.global_position.distance_to(spot.global_position) < 1.0
		and _cover.scale.is_equal_approx(
			Vector2.ONE * G.settings.set_aside_scale
		),
		"the cover rests on the spot, shrunk",
	)
	_expect(
		_events.has("layer_removed:Cover"),
		"the item emits layer_removed",
	)
	_expect(
		_item.get_exposed_layer() == _inside,
		"the inside is exposed",
	)
	_expect(
		_cover.is_ready_to_go_back() and is_instance_valid(_cover._glow_tween),
		"the cover glows, ready to go back",
	)


func _check_put_driver_back() -> void:
	await _press_at(_holder_position)
	_expect(
		_tool.mode == Tool.Mode.STORED and _hand.is_empty(),
		"the driver goes back to its holder",
	)
	await _seconds(0.4)
	_expect(
		_tool._get_holder_shape().global_position.distance_to(
			_holder_position
		) < 1.0,
		"the driver sits on its holder again",
	)
	await _move_to(_cover.global_position)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_POINTING_HAND,
		"empty hand over the ready cover",
	)


func _check_put_cover_back() -> void:
	await _press_at(_cover.global_position)
	_expect(
		_cover.is_on and _cover.is_moving,
		"4. pressing the ready cover puts it back",
	)
	await _seconds(0.6)
	var layers_node := _item.get_node("Layers")
	_expect(
		_cover.get_parent() == layers_node
		and _cover.get_index() == _inside.get_index() + 1,
		"4. the cover is back on the item, over the inside",
	)
	_expect(
		not _cover.is_moving
		and _cover.position.is_zero_approx()
		and is_zero_approx(_cover.rotation)
		and _cover.scale.is_equal_approx(Vector2.ONE),
		"the cover rests where it started",
	)
	_expect(
		_events.has("layer_installed:Cover"),
		"the item emits layer_installed",
	)
	for screw: Screw in [_screw_left, _screw_right]:
		_expect(
			screw.is_install_mode
			and screw.visible
			and screw.mode == InteractionPoint.Mode.UNSTARTED
			and is_equal_approx(screw.head.rotation, -Screw.LOOSE_TURN_RAD),
			"4. %s comes back loose and turned back, in install mode"
			% screw.name,
		)
	_expect(
		not _item.has_finished,
		"the item isn't finished with loose screws",
	)
	_expect(
		not is_instance_valid(_cover._glow_tween)
		and _cover.modulate == Color.WHITE,
		"the glow stops",
	)


func _check_pause() -> void:
	await _press_at(_holder_position)
	_expect(_hand.held == _tool, "take the driver again")
	await _move_to(_item.global_position)
	_expect_cursor(
		Input.MOUSE_MODE_HIDDEN,
		Input.CURSOR_ARROW,
		"holding, before the pause",
	)
	G.state.transition(StateMain.State.PAUSE)
	await _physics_frames(2)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_ARROW,
		"paused while holding",
	)
	G.state.transition(StateMain.State.GAME)
	await _physics_frames(2)
	_expect_cursor(
		Input.MOUSE_MODE_HIDDEN,
		Input.CURSOR_ARROW,
		"holding, after the pause",
	)


func _check_drive_screws_in() -> void:
	await _press_at(_screw_left.global_position)
	_expect(
		_tool.mode == Tool.Mode.IN_USE,
		"5. the driver engages the loose screw",
	)
	# m1-screws: keep the tip centered instead of waiting out the stand-in.
	await _drive(_screw_left, 0.8)
	_expect(
		_screw_left.head.rotation > -Screw.LOOSE_TURN_RAD + 0.01,
		"the twists turn the screw clockwise",
	)
	await _drive(_screw_left, 10.0)
	_expect(
		_screw_left.mode == InteractionPoint.Mode.FINISHED
		and _screw_left.visible
		and is_zero_approx(_screw_left.head.rotation),
		"5. the first screw turns home and goes in",
	)
	_expect(
		_cover.is_on and not _cover.is_moving,
		"the cover stays on as the screws go in",
	)
	_expect(
		not _events.has("finished"),
		"not finished with one screw in",
	)
	await _press_at(_screw_right.global_position)
	# m1-screws: was `await _seconds(0.5)`.
	await _drive(_screw_right, 10.0)
	_expect(
		_screw_right.mode == InteractionPoint.Mode.FINISHED,
		"5. the second screw goes in",
	)
	_expect(_events.has("finished"), "6. the item emits finished")
	_expect(
		_item.has_finished and _item.is_finished(),
		"6. the item is finished",
	)
	_expect(_events.count("finished") == 1, "finished fires once")


func _check_finished_item() -> void:
	await _press_at(_holder_position)
	_expect(
		_tool.mode == Tool.Mode.STORED and _hand.is_empty(),
		"the driver goes back after the job",
	)
	await _move_to(_item.global_position)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_POINTING_HAND,
		"empty hand over the finished item",
	)
	await _press_at(_item.global_position)
	var layers_node: Node2D = _item.get_node("Layers")
	_expect(
		layers_node.position == Vector2.ZERO,
		"rule 7: a finished item doesn't shake",
	)


func _check_level_exit() -> void:
	await _press_at(_holder_position)
	_expect_cursor(
		Input.MOUSE_MODE_HIDDEN,
		Input.CURSOR_ARROW,
		"holding, before the restart",
	)
	var hand := _hand
	hand.tree_exited.connect(
		func() -> void:
			_exit_mouse_mode = hand.mouse_mode
			_exit_cursor_shape = hand.cursor_shape
	)
	var old_level_id := _level.get_instance_id()
	G.game_panel.restart_level()
	await _seconds(0.8)
	_expect(
		_exit_mouse_mode == Input.MOUSE_MODE_VISIBLE
		and _exit_cursor_shape == Input.CURSOR_ARROW,
		"LX2: the cursor resets when the level exits",
	)
	_expect(
		is_instance_valid(G.level)
		and G.level.get_instance_id() != old_level_id,
		"a fresh level starts",
	)
	if not is_instance_valid(G.level):
		return
	_expect(
		G.level.hand.is_empty()
		and G.level.hand.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"the fresh level's hand is empty, with a visible cursor",
	)


func _track_head_scale() -> void:
	_head_scale_samples += 1
	for screw: Screw in [_screw_left, _screw_right]:
		var change := (screw.head.scale - Vector2.ONE).abs()
		_largest_head_scale_change = maxf(
			_largest_head_scale_change,
			maxf(change.x, change.y),
		)


## m1-screws: plays the flathead microgame well. Every physics frame it
## moves the pointer along the slot to put the tip back in the middle.
## Returns once the screw is no longer ACTIVE, or after `max_sec`.
func _drive(screw: Screw, max_sec: float) -> void:
	var flathead := screw as FlatHeadScrew
	var frames := roundi(max_sec * Engine.physics_ticks_per_second)
	for frame in frames:
		if screw.mode != InteractionPoint.Mode.ACTIVE:
			return
		var motion := InputEventMouseMotion.new()
		_push_mouse(
			motion,
			_hand.pointer_position
			- flathead.get_slot_axis() * flathead.tip_offset_px,
		)
		await get_tree().physics_frame
