extends Node
## The shared half of every probe in `tests/`. A probe extends this by path
## (`extends "res://tests/probe_base.gd"`), has no `class_name`, and runs
## through its own `probe.tscn`. See `.claude/rules/tests.md`.
##
## It holds the check counter and the summary, and the helpers that drive
## the game like a player: mouse events pushed into the viewport (their
## positions are in viewport pixels, and world (0, 0) is (640, 360)), and a
## wait for the first item to land.
##
## `tests/run.ps1` reads these lines from the log:
##   PROBE PASS: <label>, PROBE FAIL: <label>
##   PROBE SUMMARY: <n> passed, <m> failed
##   PROBE FAILED: <label>, one per failed check, after the summary
##   PROBE TIMEOUT after <n> s, then the summary, with exit code 2
## Exit code 0 means every check passed, 1 that some failed and 2 a timeout.
## `-- --screenshots` (windowed only) saves PNGs of the bench, through
## `_shot()`, to `build/tests/<probe folder>/`.


## How long to wait for the first item to land: four seconds of physics.
const _LANDING_TIMEOUT_FRAMES := 240

var _passes := 0
var _failures: Array[String] = []
var _events: Array[String] = []
var _is_taking_screenshots := false
var _is_pushing := false
var _real_motion_count := 0
var _real_buttons: Array[String] = []
var _timeout_sec := 0.0

var _hand: Hand


## Ends the run with `PROBE TIMEOUT` and exit code 2 after `limit_sec`.
func _start_timeout(limit_sec: float) -> void:
	_timeout_sec = limit_sec
	get_tree().create_timer(limit_sec).timeout.connect(_on_timeout)


func _expect(condition: bool, label: String) -> bool:
	if condition:
		_passes += 1
		print("PROBE PASS: %s" % label)
	else:
		_failures.append(label)
		print("PROBE FAIL: %s" % label)
	return condition


func _expect_cursor(
	to_mouse_mode: Input.MouseMode,
	to_cursor_shape: Input.CursorShape,
	label: String,
) -> void:
	_expect(
		_hand.mouse_mode == to_mouse_mode
		and _hand.cursor_shape == to_cursor_shape,
		"cursor, %s: want %d/%d, got %d/%d" % [
			label,
			to_mouse_mode,
			to_cursor_shape,
			_hand.mouse_mode,
			_hand.cursor_shape,
		],
	)


func _to_screen(world_point: Vector2) -> Vector2:
	return _hand.get_canvas_transform() * world_point


func _push_mouse(event: InputEventMouse, world_point: Vector2) -> void:
	event.position = _to_screen(world_point)
	event.global_position = event.position
	_is_pushing = true
	get_viewport().push_input(event, true)
	_is_pushing = false


func _move_to(world_point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	_push_mouse(motion, world_point)
	await _physics_frames(2)


func _press_down(world_point: Vector2) -> void:
	await _move_to(world_point)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_push_mouse(press, world_point)
	await _physics_frames(1)


func _release_at(world_point: Vector2) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_push_mouse(release, world_point)
	await _physics_frames(2)


func _press_at(world_point: Vector2) -> void:
	await _press_down(world_point)
	await _release_at(world_point)


## A press and a release with no motion first, like a finger landing
## somewhere new.
func _tap_at(world_point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_push_mouse(press, world_point)
	await _physics_frames(1)
	await _release_at(world_point)


func _physics_frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


## LX9: items arrive by tween. Waits until the bench holds one that has
## landed (UNDER_REPAIR), which is when it starts taking presses.
func _wait_for_landing() -> bool:
	for frame in _LANDING_TIMEOUT_FRAMES:
		if (
			is_instance_valid(G.level)
			and is_instance_valid(G.level.active_repairable)
			and G.level.active_repairable.mode == Repairable.Mode.UNDER_REPAIR
		):
			return true
		await get_tree().physics_frame
	return false


func _seconds(duration_sec: float) -> void:
	await get_tree().create_timer(duration_sec).timeout


## Saves the viewport to `build/tests/<probe folder>/<shot_name>.png`, in a
## run with `-- --screenshots`. The folder gets a `.gdignore`, so the
## editor doesn't import the PNGs.
func _shot(shot_name: String) -> void:
	if not _is_taking_screenshots:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var script_path: String = (get_script() as Script).resource_path
	var tests_directory := ProjectSettings.globalize_path("res://build/tests")
	var directory := tests_directory.path_join(
		script_path.get_base_dir().get_file()
	)
	DirAccess.make_dir_recursive_absolute(directory)
	var ignore_path := tests_directory.path_join(".gdignore")
	if not FileAccess.file_exists(ignore_path):
		var ignore_file := FileAccess.open(ignore_path, FileAccess.WRITE)
		if ignore_file != null:
			ignore_file.close()
	var path := directory.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("PROBE SHOT: %s" % path)


func _on_real_mouse_event(event: InputEventMouse) -> void:
	if event is InputEventMouseButton:
		_real_buttons.append(
			"%s at %s (t=%d ms)"
			% [event.as_text(), event.position, Time.get_ticks_msec()]
		)
	else:
		_real_motion_count += 1


func _on_timeout() -> void:
	print("PROBE TIMEOUT after %.0f s" % _timeout_sec)
	_finish(2)


func _finish(exit_code: int) -> void:
	print(
		"PROBE SUMMARY: %d passed, %d failed"
		% [_passes, _failures.size()]
	)
	for failure in _failures:
		print("PROBE FAILED: %s" % failure)
	if _is_taking_screenshots:
		print(
			"PROBE REAL INPUT: blocked %d motions and %d buttons %s"
			% [_real_motion_count, _real_buttons.size(), _real_buttons]
		)
	get_tree().quit(exit_code)


## Sits after main in the tree, so it gets `_input` before the game. It
## eats the mouse events the probe didn't push, so a real pointer over the
## window can't move the hand (LX44).
class _RealInputBlocker extends Node:
	var probe: Node

	func _input(event: InputEvent) -> void:
		if not event is InputEventMouse or probe._is_pushing:
			return
		probe._on_real_mouse_event(event as InputEventMouse)
		get_viewport().set_input_as_handled()
