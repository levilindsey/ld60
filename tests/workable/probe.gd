extends "res://tests/probe_base.gd"
## The workable area. Boots the game and plays drops with pushed
## drags: a loose part and a resting screw may be carried outside
## the level's `%WorkableArea`, and a drop out there comes back
## under gravity. Above the area it falls straight down, from
## below or the side it arcs in, and it bounces and skids as it
## lands, less so for the big finished item. A fast drag throws
## the part with the cursor's motion: it may pass the top of
## the viewport and fall back, it bounces off the sides, and a
## throw that would fall past the workable area is guided back
## to a rest inside it. A finished item dropped outside both
## the workable area and the outbox flies home, and one dropped
## on the outbox still leaves through it.
##
## Run it with `tests/run.ps1 -Name workable`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/workable/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _level: Level
var _item: Repairable
var _part: Part
var _screw: Screw


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
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
	_level = G.level
	_hand = _level.hand
	_item = _level.active_repairable
	_check_area_queries()
	_place_part_on_bench()
	await _check_part_drops()
	await _check_part_throws()
	await _check_screw_drops()
	await _check_item_drops()


func _check_area_queries() -> void:
	_expect(
		_level.get_workable_polygon().size() >= 3,
		"the level reads its workable area polygon",
	)
	_expect(
		_level.is_inside_workable_area(Vector2(0.0, 220.0)),
		"the bench middle is inside the workable area",
	)
	_expect(
		not _level.is_inside_workable_area(Vector2(0.0, -100.0)),
		"above the bench is outside the workable area",
	)
	_expect(
		not _level.is_inside_workable_area(Vector2(0.0, 520.0)),
		"below the bench is outside the workable area",
	)
	_expect(
		not _level.is_inside_workable_area(Vector2(-900.0, 220.0)),
		"beside the bench is outside the workable area",
	)
	var margin_px := 28.0
	var target := _level.get_workable_area_target(
		Vector2(0.0, -140.0),
		margin_px,
	)
	_expect(
		_level.is_inside_workable_area(target, margin_px),
		"the landing point for a drop above sits inside with"
		+ " the whole piece to spare (at %s)" % target,
	)
	_expect(
		_item.get_bench_radius_px() > _part_radius()
		and _part_radius() > 0.0,
		"the finished item is the biggest piece on the bench",
	)
	var fall := _level._solve_return_flight(
		Vector2(0.0, -140.0),
		Vector2(0.0, 160.0),
	)
	var fall_sec := fall[1] as float
	_expect(
		fall_sec > 0.38 and fall_sec < 0.46,
		"a fall is timed by the bumped gravity, slowed a"
		+ " little by wind drag (%.2f s)" % fall_sec,
	)


func _part_radius() -> float:
	var parts := _level.get_drawer_parts()
	if parts.is_empty():
		return 0.0
	return parts[0].get_radius_px()


## Takes one stocked part out of its drawer on paper: it rests
## loose on the bench where the drag cases can pick it up.
func _place_part_on_bench() -> void:
	var parts := _level.get_drawer_parts()
	if not _expect(not parts.is_empty(), "a part is stocked"):
		return
	_part = parts[0]
	_part.is_stored = false
	_part.drawer_index = -1
	_part.global_position = Vector2(0.0, 220.0)
	_part.z_index = 10
	_part.show()


## Drags a loose piece from where it rests to a world point
## and lets go there.
func _drag_piece(from_point: Vector2, to_point: Vector2) -> void:
	await _press_down(from_point)
	await _move_to(to_point)
	await _release_at(to_point)


## Records a returning piece once per physics frame until it
## rests, and returns the positions it passed through.
func _track_return(
	is_returning: Callable,
	get_position: Callable,
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for frame in 480:
		points.append(get_position.call() as Vector2)
		if not (is_returning.call() as bool):
			break
		await get_tree().physics_frame
	return points


func _check_part_drops() -> void:
	if not is_instance_valid(_part):
		return
	var margin_px := (
		_part.get_radius_px() + G.settings.workable_edge_padding_px
	)
	# Above: it falls straight down, bounces and skids.
	await _drag_piece(_part.global_position, Vector2(0.0, -140.0))
	_expect(_part.is_returning, "a part dropped above is falling back")
	var points := await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the part that fell from above rests inside (at %s)"
		% _part.global_position,
	)
	var landing_index := -1
	for index in points.size():
		if _level.is_inside_workable_area(points[index], margin_px):
			landing_index = index
			break
	var bounced := false
	var skidded := false
	var rise_px := 0.0
	var skid_px := 0.0
	if landing_index >= 0:
		var landing := points[landing_index]
		for index in range(landing_index + 1, points.size()):
			rise_px = maxf(rise_px, landing.y - points[index].y)
			if points[index].y < landing.y - 4.0:
				bounced = true
		skid_px = points[points.size() - 1].distance_to(landing)
		skidded = skid_px > 0.5
	_expect(
		bounced,
		"the falling part bounces as it lands (rose %.0f px)" % rise_px,
	)
	_expect(
		skidded,
		"the falling part skids as it lands (skidded %.0f px)" % skid_px,
	)
	# Below: it is flicked up in an arc and falls in.
	await _drag_piece(_part.global_position, Vector2(0.0, 520.0))
	points = await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	var highest := 520.0
	for point in points:
		highest = minf(highest, point.y)
	_expect(
		highest < 490.0,
		"a part dropped below arcs up before it lands"
		+ " (rose to y %.0f)" % highest,
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the part flicked from below rests inside (at %s)"
		% _part.global_position,
	)
	# From the side: the same arc, sideways.
	await _drag_piece(_part.global_position, Vector2(-920.0, 230.0))
	points = await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	highest = 230.0
	for point in points:
		highest = minf(highest, point.y)
	_expect(
		highest < 215.0,
		"a part dropped beside the bench arcs up as it comes in"
		+ " (rose to y %.0f)" % highest,
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the part flicked from the side rests inside (at %s)"
		% _part.global_position,
	)


## Drags a piece fast through the last stretch, so the pointer
## is still moving at that speed when it is let go: a flick.
## The piece is picked up where it rests, carried to the
## approach point in even steps, then on to the release point
## in more even steps, one per physics frame, so the smoothed
## cursor speed at the release is the last stretch's speed.
func _flick_piece(
	from_point: Vector2,
	approach_point: Vector2,
	release_point: Vector2,
	release_steps := 12,
) -> void:
	await _press_down(from_point)
	await _step_pointer_to(from_point, approach_point, 8)
	await _step_pointer_to(approach_point, release_point, release_steps)
	await _release_at(release_point)


## Moves the pointer from one point to another in even steps,
## one per physics frame.
func _step_pointer_to(
	from_point: Vector2,
	to_point: Vector2,
	steps: int,
) -> void:
	for step in range(1, steps + 1):
		var point := from_point.lerp(
			to_point,
			float(step) / float(steps),
		)
		var motion := InputEventMouseMotion.new()
		_push_mouse(motion, point)
		await get_tree().physics_frame


func _check_part_throws() -> void:
	if not is_instance_valid(_part):
		return
	var margin_px := (
		_part.get_radius_px() + G.settings.workable_edge_padding_px
	)
	# Thrown up hard: it passes the top of the viewport and
	# falls back. The release leg is quick, a genuinely hard
	# flick, which the heavier gravity now demands.
	await _flick_piece(
		_part.global_position,
		Vector2(0.0, 220.0),
		Vector2(0.0, -60.0),
		6,
	)
	_expect(_part.is_returning, "a flicked part is thrown, not set down")
	var points := await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	var highest := 0.0
	for point in points:
		highest = minf(highest, point.y)
	_expect(
		highest < -360.0,
		"a part thrown up passes the top of the viewport"
		+ " (rose to y %.0f)" % highest,
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the part thrown up falls back and rests inside (at %s)"
		% _part.global_position,
	)
	# Thrown at the side: it bounces off the viewport wall.
	await _flick_piece(
		_part.global_position,
		Vector2(-160.0, 230.0),
		Vector2(-520.0, 230.0),
	)
	points = await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	var wall_index := -1
	var leftmost := 0.0
	for index in points.size():
		if points[index].x < leftmost:
			leftmost = points[index].x
			wall_index = index
	var bounced_off_wall := false
	if wall_index >= 0:
		for index in range(wall_index + 1, points.size()):
			if points[index].x > leftmost + 40.0:
				bounced_off_wall = true
	_expect(
		leftmost < -590.0 and bounced_off_wall,
		"a part thrown at the side bounces off the viewport wall"
		+ " (reached x %.0f)" % leftmost,
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the part bounced off the wall rests inside (at %s)"
		% _part.global_position,
	)
	# Thrown down past the bench: it falls below the workable
	# area's bottom edge and is guided back to a rest inside.
	await _flick_piece(
		_part.global_position,
		Vector2(690.0, 20.0),
		Vector2(700.0, 140.0),
	)
	points = await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	var fell_past := false
	for point in points:
		if point.y > 306.0:
			fell_past = true
	_expect(
		fell_past,
		"a part thrown down beside the bench falls past its bottom",
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the part that fell past is guided back and rests inside"
		+ " (at %s)" % _part.global_position,
	)
	# Thrown down hard from high above: gravity speeds it up,
	# but never past the fastest speed, drag included.
	await _flick_piece(
		_part.global_position,
		Vector2(0.0, -620.0),
		Vector2(0.0, -260.0),
	)
	points = await _track_return(
		func() -> bool: return _part.is_returning,
		func() -> Vector2: return _part.global_position,
	)
	var max_speed := 0.0
	for index in range(1, points.size()):
		var frame_speed := (
			points[index].distance_to(points[index - 1])
			* float(Engine.physics_ticks_per_second)
		)
		max_speed = maxf(max_speed, frame_speed)
	_expect(
		max_speed > 1100.0
		and max_speed
		<= G.settings.workable_max_speed_px_per_sec + 90.0,
		"a hard downward throw stays under the fastest speed"
		+ " (peaked at %.0f px/s)" % max_speed,
	)
	_expect(
		_level.is_inside_workable_area(_part.global_position, margin_px),
		"the hard downward throw rests inside (at %s)"
		% _part.global_position,
	)


func _check_screw_drops() -> void:
	_screw = (
		_item.get_node("Layers/Cover/ScrewLeft") as Screw
	)
	if not _expect(is_instance_valid(_screw), "the item has a screw"):
		return
	_screw.remove()
	var is_out := await _wait_for_travel(
		_screw,
		Screw.Travel.RESTING,
		3.0,
	)
	if not _expect(is_out, "the screw comes out onto the bench"):
		return
	var margin_px := (
		_screw.get_rest_radius_px()
		+ G.settings.workable_edge_padding_px
	)
	# Above the area, then below it.
	for drop_point in [Vector2(0.0, -140.0), Vector2(0.0, 520.0)]:
		var middle := (
			_screw.bench_art.global_position + _screw.rest_hit_offset
		)
		await _drag_piece(middle, drop_point)
		_expect(
			_screw.is_returning,
			"a screw dropped outside is on its way back (%s)"
			% drop_point,
		)
		await _track_return(
			func() -> bool: return _screw.is_returning,
			func() -> Vector2: return _screw.bench_art.global_position,
		)
		var rested := (
			_screw.bench_art.global_position + _screw.rest_hit_offset
		)
		_expect(
			_level.is_inside_workable_area(rested, margin_px),
			"the returned screw rests inside (at %s)" % rested,
		)


func _check_item_drops() -> void:
	if not await _finish_item():
		return
	var home := (
		_level.get_node("%ActiveItemPosition") as Node2D
	).global_position
	var margin_px := (
		_item.get_bench_radius_px()
		+ G.settings.workable_edge_padding_px
	)
	# A drop inside the workable area eases home as it always has.
	await _drag_piece(_item.global_position, Vector2(100.0, 240.0))
	_expect(
		not _item.is_returning,
		"an item dropped inside the workable area does not fly",
	)
	await _seconds(0.6)
	_expect(
		_item.global_position.distance_to(home) < 1.0
		and is_zero_approx(_item.rotation),
		"the item dropped inside eases back home, straight",
	)
	# A drop below both areas flies home in an arc instead.
	await _drag_piece(_item.global_position, Vector2(0.0, 560.0))
	_expect(
		_item.is_returning,
		"an item dropped below both areas is on its way back",
	)
	var points := await _track_return(
		func() -> bool: return _item.is_returning,
		func() -> Vector2: return _item.global_position,
	)
	var highest := 560.0
	for point in points:
		highest = minf(highest, point.y)
	_expect(
		highest < 530.0,
		"the dropped item arcs up before it lands"
		+ " (rose to y %.0f)" % highest,
	)
	_expect(
		_level.is_inside_workable_area(_item.global_position, margin_px),
		"the returned item rests inside the workable area"
		+ " (at %s)" % _item.global_position,
	)
	_expect(
		_item.global_position.distance_to(home) < 48.0
		and is_zero_approx(_item.rotation),
		"the returned item rests by its home, straight"
		+ " (%.0f px away)" % _item.global_position.distance_to(home),
	)
	# The outbox is the one other place it may rest.
	var outbox := _level.get_node("%Outbox") as Area2D
	var inside := outbox.global_position + Vector2(10.0, 0.0)
	await _press_down(_item.global_position)
	await _move_to(inside)
	await _physics_frames(4)
	await _release_at(inside)
	_expect(
		_item.mode == Repairable.Mode.LEAVING
		and _level.active_repairable == null,
		"an item dropped on the outbox still leaves through it",
	)


## Finishes the item the way the item flow probe does: every
## point directly, the cover off by a drag and back by a drag,
## then every point again.
func _finish_item() -> bool:
	for point in _item.get_remaining_points():
		point.finish()
	var exposed := _item.get_exposed_layer()
	if is_instance_valid(exposed) and not exposed.is_innermost():
		await _drag_layer(exposed, Vector2(360.0, 60.0))
	var is_ready := false
	for frame in 180:
		var next := _item.get_next_layer_to_put_back()
		if is_instance_valid(next) and next.is_ready_to_go_back():
			is_ready = true
			break
		await get_tree().physics_frame
	if not _expect(is_ready, "the cover is ready to go back on"):
		return false
	var layer := _item.get_next_layer_to_put_back()
	await _drag_layer(layer, layer.get_home_global_position())
	var is_back := false
	for frame in 180:
		if layer.is_on and not layer.is_moving:
			is_back = true
			break
		await get_tree().physics_frame
	if not _expect(is_back, "the cover goes back on"):
		return false
	for point in _item.get_remaining_points():
		point.finish()
	return _expect(_item.has_finished, "the item is finished")


## Drags a loose layer by a clear patch of its art so its
## middle lands on a bench point.
func _drag_layer(layer: RepairLayer, target: Vector2) -> void:
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
				var grab_offset := point - layer.global_position
				await _press_down(point)
				await _move_to(target + grab_offset)
				await _release_at(target + grab_offset)
				return
