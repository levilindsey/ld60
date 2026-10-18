extends "res://tests/probe_base.gd"
## The Phillips circular drag (LX17). Boots the game, swaps the
## test box for the Phillips box, and circles the driver around
## its screws too slowly, too fast, and then tracking the sliding
## green zone.
##
## Run it with `tests/run.ps1 -Name phillips`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/phillips/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 150.0
const _CIRCLE_RADIUS := 26.0
const _STEP_SEC := 0.05
## A tracked drag's measured speed lands at about three
## quarters of its nominal speed (each step spans four physics
## frames), so aim this much past the zone center to put the
## needle on it, the way a player watching the needle would.
const _TRACKED_SPEED_GAIN := 4.0 / 3.0

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
	_check_zone_continuity()
	_check_gauge_tint()
	_check_gauge_needle_wrap()
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
	_driver = G.level.tools_by_type[
		Tool.Type.PHILLIPS_SCREW_DRIVER
	] as PhillipsScrewDriver
	await _grab_tool(_driver)
	_expect(_hand.held == _driver, "the hand holds the phillips driver")


## The zone never reverses: at the fast end it wraps back to the
## slow end and keeps climbing the same way.
## The gauge face stays plain while the strip-out meter has room
## and only reddens in its low end: progress never greens it.
func _check_gauge_tint() -> void:
	_left.grip_meter = 1.0
	_left._turned_rad = _left._get_total_rad() * 0.9
	var success_color := _left.gauge._get_background_color(_left)
	_expect(
		absf(success_color.r - success_color.g) < 0.01,
		"the gauge face does not green as the screw nears done",
	)
	_left.grip_meter = 0.8
	var calm_color := _left.gauge._get_background_color(_left)
	_expect(
		absf(calm_color.r - calm_color.g) < 0.01,
		"the gauge face stays plain above the meter's low end",
	)
	_left.grip_meter = 0.02
	_left._turned_rad = 0.0
	var failure_color := _left.gauge._get_background_color(_left)
	_expect(
		failure_color.r > failure_color.g,
		"the gauge face reddens in the meter's low end",
	)
	_left._turned_rad = 0.0
	_left.grip_meter = G.settings.phillips_meter_start


## The needle must keep moving past the dial's downward seam
## instead of pinning there once the speed passes the top.
func _check_gauge_needle_wrap() -> void:
	var gauge_max := G.settings.phillips_gauge_max_rad_per_sec
	var seam_angle := _left.gauge._speed_to_angle(gauge_max)
	var past_seam_angle := _left.gauge._speed_to_angle(gauge_max + 1.0)
	var past_step := wrapf(past_seam_angle - seam_angle, -PI, PI)
	_expect(
		past_step < -0.1,
		"the gauge needle continues past the downward seam",
	)


func _check_zone_continuity() -> void:
	var screw := _left
	var high_center := (
		G.settings.phillips_gauge_max_rad_per_sec
		- screw._get_zone_width() / 2.0
	)
	screw._zone_center_rad_per_sec = high_center - 0.05
	screw._zone_climb_rad_per_sec = 2.0
	screw._zone_target_climb_rad_per_sec = 2.0
	screw._zone_retarget_left_sec = 10.0
	var did_wrap := false
	for step in 60:
		var before := screw._zone_center_rad_per_sec
		screw._update_zone(1.0 / 60.0)
		if screw._zone_center_rad_per_sec < before - 1.0:
			did_wrap = true
	_expect(
		did_wrap
		and screw._zone_climb_rad_per_sec > 0.0
		and screw._zone_center_rad_per_sec < high_center,
		"the green zone wraps at the fast end and keeps climbing"
		+ " the same way (ends at %.2f of %.2f, climb %.2f)"
		% [
			screw._zone_center_rad_per_sec,
			high_center,
			screw._zone_climb_rad_per_sec,
		],
	)
	# Put the zone back where an engaged screw starts with it.
	screw._zone_center_rad_per_sec = (
		(
			G.settings.phillips_speed_min_rad_per_sec
			+ G.settings.phillips_speed_max_rad_per_sec
		)
		/ 2.0
	)
	screw._zone_climb_rad_per_sec = 0.0
	screw._pick_zone_target()


func _check_cam_outs() -> void:
	# The cursor on the screw is not enough: the driver's working
	# end sits well away from its cursor marker, so this press
	# lines the marker up and the working end misses.
	await _press_at(_left.global_position)
	_expect(
		_left.mode == InteractionPoint.Mode.UNSTARTED,
		"pressing with the cursor on the screw does not engage it",
	)
	await _press_tool_at(_driver, _left.global_position)
	_expect(
		_left.mode == InteractionPoint.Mode.ACTIVE,
		"the driver engages the left screw",
	)
	var driver_sprite := (
		_driver.get_node("%AnimatedSprite2D") as AnimatedSprite2D
	)
	_expect(
		driver_sprite.animation == &"default",
		"the driver animation waits until the screw makes progress",
	)
	await _seconds(1.2)
	_expect(
		not _left.has_started_dragging()
		and is_equal_approx(
			_left.grip_meter, G.settings.phillips_meter_start
		),
		"idling with the driver seated costs no grip",
	)
	var zone_start := _left.get_zone_center_rad_per_sec()
	await _drag_circle(_left.global_position, 1.2, 1.0, -1.0)
	_expect(
		_left.get_zone_center_rad_per_sec() > zone_start + 0.2,
		"the green zone slides while the screw is engaged",
	)
	_expect(
		_left.gauge._speed_to_angle(8.0)
		< _left.gauge._speed_to_angle(2.0),
		"coming out, the gauge sweeps counter-clockwise",
	)
	# Pin the zone high so the slow drag stays below it: too
	# slow only means anything against the zone's current spot.
	_left._zone_center_rad_per_sec = 10.0
	_left._zone_climb_rad_per_sec = 0.0
	_left._zone_target_climb_rad_per_sec = 0.0
	_left._zone_retarget_left_sec = 30.0
	await _drag_circle(_left.global_position, 1.2, 5.0, -1.0)
	_expect(
		_left.health == _left.max_health - 1,
		"circling too slowly cams the bit out",
	)
	_expect(
		_hand.held == _driver,
		"the driver stays in the hand after a cam-out",
	)
	await _seconds(0.7)
	await _press_tool_at(_driver, _left.global_position)
	# Pin the zone low so the fast drag is past it wherever it
	# would otherwise be: too fast only means anything against
	# the zone's current spot on the dial.
	_left._zone_center_rad_per_sec = 2.0
	_left._zone_climb_rad_per_sec = 0.0
	_left._zone_target_climb_rad_per_sec = 0.0
	_left._zone_retarget_left_sec = 10.0
	await _drag_circle(_left.global_position, 16.0, 5.0, -1.0)
	_expect(
		_left.health == _left.max_health - 2,
		"circling too fast cams the bit out",
	)
	await _seconds(0.7)


func _check_removals() -> void:
	# The cam-out checks above spent two of this screw's health.
	# The removal check is about turning, not health.
	_left.health = _left.max_health
	await _press_tool_at(_driver, _left.global_position)
	await _drag_circle(_left.global_position, 5.0, 2.0, -1.0, _left)
	var driver_sprite := (
		_driver.get_node("%AnimatedSprite2D") as AnimatedSprite2D
	)
	_expect(
		driver_sprite.animation == &"twisting",
		"the driver animation plays while the screw makes progress",
	)
	await _drag_to_resting(_left)
	_expect(
		await _wait_for_travel(_left, Screw.Travel.RESTING),
		"tracking the sliding zone removes the left screw",
	)
	await _press_tool_at(_driver, _right.global_position)
	# Progress counts only inside the green window itself: a
	# settled speed just past its edge must leave the slide put.
	_right._zone_center_rad_per_sec = 5.0
	_right._zone_climb_rad_per_sec = 0.0
	_right._zone_target_climb_rad_per_sec = 0.0
	_right._zone_retarget_left_sec = 30.0
	await _drag_circle(_right.global_position, 6.7, 1.5, -1.0)
	await _drag_circle(_right.global_position, 9.5, 1.5, -1.0)
	var settled_slide := _right.slide
	await _drag_circle(_right.global_position, 9.5, 1.5, -1.0)
	_expect(
		absf(_right.slide - settled_slide) < 0.01,
		"progress stops outside the green window (slide %.2f kept)"
		% settled_slide,
	)
	# Circling around empty bench, away from the screw, still
	# turns it. Only the drag's turning counts, not its center.
	# Circle until it is clearly turning and stop there: the
	# zone's pace sets the turning rate, so a fixed-length drag
	# could take the screw all the way out here.
	await _drag_until_turned(_right, 0.3, 16.0)
	_expect(
		_right.slide > 0.25,
		"circling off-center still turns the screw",
	)
	# Fail on purpose and retry: the turns so far must survive.
	# Circling the wrong way is out of the zone wherever it sits.
	await _drag_circle(_right.global_position, 5.0, 7.0, 1.0)
	_expect(
		_right.mode == InteractionPoint.Mode.UNSTARTED
		and _hand.held == _driver,
		"circling the wrong way cams the bit out mid-removal",
	)
	var kept_slide := _right.slide
	await _seconds(0.7)
	await _press_tool_at(_driver, _right.global_position)
	_expect(
		absf(_right.slide - kept_slide) < 0.01,
		"retrying keeps the screw's progress (slide %.2f kept)"
		% kept_slide,
	)
	await _drag_to_resting(_right)
	_expect(
		await _wait_for_travel(_right, Screw.Travel.RESTING),
		"tracking the sliding zone removes the right screw",
	)
	# The loose cover waits to be dragged off, empty handed.
	await _put_tool_away(_driver)
	await _seconds(0.4)
	await _drag_cover_to(Vector2(360.0, 60.0))
	_expect(not _cover.is_on, "the loose cover is dragged off")


func _check_install() -> void:
	await _drag_cover_to(_cover.get_home_global_position())
	for frame in 180:
		if _cover.is_on and not _cover.is_moving:
			break
		await get_tree().physics_frame
	_expect(_cover.is_on, "the cover goes back on")
	# Drag the left screw to its hole: it arcs down and sinks in.
	await _press_down(
		_left.bench_art.global_position + _left.rest_hit_offset
	)
	await _move_to(_left.global_position)
	await _release_at(_left.global_position)
	_expect(
		await _wait_for_travel(_left, Screw.Travel.HOME),
		"the left screw sinks back in",
	)
	# Pressing the cover back can brush the driver's own holder
	# and put it away. Take it again if the hand is empty.
	if _hand.held != _driver:
		await _grab_driver()
	_expect(
		_left.gauge._speed_to_angle(8.0)
		> _left.gauge._speed_to_angle(2.0),
		"tightening, the gauge sweeps clockwise, the way the drag"
		+ " has to circle",
	)
	# The seated screw sits raised: press its slid-up hit shape.
	# Drive it in tracked bursts, re-engaging after a cam-out:
	# progress is kept between tries.
	for attempt in 3:
		if _left.mode == InteractionPoint.Mode.FINISHED:
			break
		if _left.mode != InteractionPoint.Mode.ACTIVE:
			await _press_tool_at(
				_driver, _left.hit_shape.global_position
			)
		await _drag_circle(
			_left.global_position, 5.0, 3.0, 1.0, _left
		)
		await _seconds(0.7)
	_expect(
		_left.mode == InteractionPoint.Mode.FINISHED
		and _left.slide < 0.01,
		"circling the other way drives the screw in",
	)


## Drags the cover by a clear patch of its art to a bench point.
func _drag_cover_to(target: Vector2) -> void:
	for x_offset in range(-160, 161, 20):
		for y_offset in range(-120, 121, 20):
			var point := (
				_cover.global_position
				+ Vector2(float(x_offset), float(y_offset))
			)
			if (
				_cover.has_point(point)
				and not is_instance_valid(_hand.find_point(point))
				and point.distance_to(_left.bench_art.global_position)
				> 34.0
				and point.distance_to(_right.bench_art.global_position)
				> 34.0
			):
				await _press_down(point)
				await _move_to(target)
				await _release_at(target)
				return


## Circles around empty bench tracking the zone, like
## _drag_circle, until the screw passes a slide or time runs
## out. One unbroken drag: restarting it would corrupt the
## screw's heading measurement.
func _drag_until_turned(
	screw: PhillipsScrew,
	target_slide: float,
	max_sec: float,
) -> void:
	var center := screw.global_position + Vector2(70, 40)
	await _move_to(center + Vector2(_CIRCLE_RADIUS, 0))
	var angle := 0.0
	var steps := int(max_sec / _STEP_SEC)
	for step in steps:
		if screw.slide > target_slide:
			break
		angle += (
			-1.0
			* screw.get_zone_center_rad_per_sec()
			* _TRACKED_SPEED_GAIN
			* _STEP_SEC
		)
		var point := (
			center + Vector2(cos(angle), sin(angle)) * _CIRCLE_RADIUS
		)
		var motion := InputEventMouseMotion.new()
		_push_mouse(motion, point)
		await _physics_frames(3)


## Drags in circles tracking the zone until the screw comes
## out, re-engaging after a cam-out the way a player would.
func _drag_to_resting(screw: PhillipsScrew) -> void:
	for attempt in 4:
		if screw.travel == Screw.Travel.RESTING:
			return
		if screw.mode != InteractionPoint.Mode.ACTIVE:
			await _press_tool_at(_driver, screw.global_position)
		await _drag_circle(screw.global_position, 5.0, 8.0, -1.0, screw)
		await _seconds(0.7)


## Drags the pointer in circles around a center. `direction` is
## -1 to take a screw out and 1 to drive it in. With a tracked
## screw, the drag speed follows the middle of its sliding green
## zone, the way a player chasing the zone would.
func _drag_circle(
	center: Vector2,
	speed_rad_per_sec: float,
	duration_sec: float,
	direction: float,
	tracked_screw: PhillipsScrew = null,
) -> void:
	await _move_to(center + Vector2(_CIRCLE_RADIUS, 0))
	var angle := 0.0
	var steps := int(duration_sec / _STEP_SEC)
	for step in steps:
		if is_instance_valid(tracked_screw):
			speed_rad_per_sec = (
				tracked_screw.get_zone_center_rad_per_sec()
				* _TRACKED_SPEED_GAIN
			)
		angle += direction * speed_rad_per_sec * _STEP_SEC
		var point := (
			center + Vector2(cos(angle), sin(angle)) * _CIRCLE_RADIUS
		)
		var motion := InputEventMouseMotion.new()
		_push_mouse(motion, point)
		await _physics_frames(3)
