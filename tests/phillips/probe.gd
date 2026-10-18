extends "res://tests/probe_base.gd"
## The Phillips circular drag (LX17). Boots the game, swaps the
## test box for the Phillips box, and circles the driver around
## its screws too slowly, too fast, and then at a good speed.
##
## Run it with `tests/run.ps1 -Name phillips`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/phillips/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 150.0
const _CIRCLE_RADIUS := 26.0
const _STEP_SEC := 0.05

var _item: Repairable
var _cover: RepairLayer
var _left: PhillipsScrew
var _right: PhillipsScrew
var _driver: PhillipsScrewDriver


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
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_hand = G.level.hand
	_expect(
		G.level.tools_by_type.has(Tool.Type.PHILLIPS_SCREW_DRIVER),
		"the phillips driver is on the rack",
	)
	await _swap_to_phillips_item()
	if not is_instance_valid(_left):
		return
	await _grab_driver()
	await _check_cam_outs()
	await _check_removals()
	await _check_install()


## Puts the Phillips test box on the bench in place of the day's
## first item, which never gets repaired here.
func _swap_to_phillips_item() -> void:
	var old := G.level.active_repairable
	G.level.active_repairable = null
	old.queue_free()
	await _physics_frames(2)
	_item = G.level.spawn_repairable(
		Repairable.Type.TEST_PHILLIPS_REPAIRABLE
	)
	if not _expect(await _wait_for_landing(), "the phillips box lands"):
		return
	_cover = _item.layers[_item.layers.size() - 1]
	_left = _cover.get_node("ScrewLeft") as PhillipsScrew
	_right = _cover.get_node("ScrewRight") as PhillipsScrew
	_expect(
		is_instance_valid(_left) and is_instance_valid(_right),
		"the phillips box has two phillips screws",
	)


func _grab_driver() -> void:
	await _press_at(
		G.level.get_tool_holder_position(Tool.Type.PHILLIPS_SCREW_DRIVER)
	)
	_driver = G.level.tools_by_type[
		Tool.Type.PHILLIPS_SCREW_DRIVER
	] as PhillipsScrewDriver
	_expect(_hand.held == _driver, "the hand holds the phillips driver")


func _check_cam_outs() -> void:
	await _press_at(_left.global_position)
	_expect(
		_left.mode == InteractionPoint.Mode.ACTIVE,
		"the driver engages the left screw",
	)
	await _drag_circle(_left.global_position, 1.2, 1.6, -1.0)
	_expect(
		_left.health == _left.max_health - 1,
		"circling too slowly cams the bit out",
	)
	_expect(
		_hand.held == _driver,
		"the driver stays in the hand after a cam-out",
	)
	await _seconds(0.7)
	await _press_at(_left.global_position)
	await _drag_circle(_left.global_position, 11.0, 1.6, -1.0)
	_expect(
		_left.health == _left.max_health - 2,
		"circling too fast cams the bit out",
	)
	await _seconds(0.7)


func _check_removals() -> void:
	await _press_at(_left.global_position)
	await _drag_circle(_left.global_position, 5.0, 4.0, -1.0)
	_expect(
		await _wait_for_travel(_left, Screw.Travel.RESTING),
		"a good circle speed removes the left screw",
	)
	await _press_at(_right.global_position)
	await _drag_circle(_right.global_position, 5.0, 4.0, -1.0)
	_expect(
		await _wait_for_travel(_right, Screw.Travel.RESTING),
		"a good circle speed removes the right screw",
	)
	for frame in 180:
		if not _cover.is_on:
			break
		await get_tree().physics_frame
	_expect(not _cover.is_on, "the cover lifts off")


func _check_install() -> void:
	await _press_at(_cover.global_position)
	for frame in 180:
		if _cover.is_on and not _cover.is_moving:
			break
		await get_tree().physics_frame
	_expect(_cover.is_on, "the cover goes back on")
	await _press_resting_screw(_left)
	_expect(
		await _wait_for_travel(_left, Screw.Travel.HOME),
		"the left screw sinks back in",
	)
	# Pressing the cover back can brush the driver's own holder
	# and put it away. Take it again if the hand is empty.
	if _hand.held != _driver:
		await _grab_driver()
	await _press_at(_left.global_position)
	await _drag_circle(_left.global_position, 5.0, 2.0, 1.0)
	_expect(
		_left.mode == InteractionPoint.Mode.FINISHED
		and _left.slide < 0.01,
		"circling the other way drives the screw in",
	)


## Drags the pointer in circles around a center. `direction` is
## -1 to take a screw out and 1 to drive it in.
func _drag_circle(
	center: Vector2,
	speed_rad_per_sec: float,
	duration_sec: float,
	direction: float,
) -> void:
	await _move_to(center + Vector2(_CIRCLE_RADIUS, 0))
	var angle := 0.0
	var steps := int(duration_sec / _STEP_SEC)
	for step in steps:
		angle += direction * speed_rad_per_sec * _STEP_SEC
		var point := (
			center + Vector2(cos(angle), sin(angle)) * _CIRCLE_RADIUS
		)
		var motion := InputEventMouseMotion.new()
		_push_mouse(motion, point)
		await _physics_frames(3)
