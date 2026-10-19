extends "res://tests/probe_base.gd"
## Screws of a given type are interchangeable (LX64): a resting
## screw seats into any empty hole of its own type on its layer,
## not only the hole it came from, and a screw of another type
## does not seat there. It also checks that a cover put back on
## draws over the layer under it (LX65).
##
## Run it with `tests/run.ps1 -Name screw_swap`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/screw_swap/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _cover: RepairLayer


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
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_PHILLIPS_REPAIRABLE,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_hand = G.level.hand
	_item = G.level.active_repairable
	_cover = _item.layers[_item.layers.size() - 1]
	await _check_mixed_types_do_not_swap()
	await _swap_to_phillips_item()
	if not is_instance_valid(_item):
		return
	await _check_same_type_swaps()


## The test box holds one flathead screw and one Phillips screw.
## Neither seats into the other's hole, and each still seats into
## its own.
func _check_mixed_types_do_not_swap() -> void:
	var flat := _cover.get_node("ScrewLeft") as Screw
	var phillips := _cover.get_node("ScrewRight") as Screw
	if not _expect(
		is_instance_valid(flat) and is_instance_valid(phillips),
		"the test box has a flathead and a Phillips screw",
	):
		return
	var flat_home := flat.global_position
	var phillips_home := phillips.global_position
	await _remove_screw(flat)
	await _remove_screw(phillips)
	await _prepare_cover_for_return()
	await _drag_screw_to(flat, phillips_home)
	await _seconds(1.0)
	_expect(
		flat.travel == Screw.Travel.RESTING
		and phillips.travel == Screw.Travel.RESTING
		and flat.global_position.distance_to(flat_home) < 0.5
		and phillips.global_position.distance_to(phillips_home) < 0.5,
		"a flathead screw dropped on a Phillips hole does not seat",
	)
	# Park the flathead screw clear of the Phillips screw, which
	# rests under it now, so the next press grabs the Phillips.
	await _drag_screw_to(flat, Vector2(-250.0, 240.0))
	await _seconds(0.7)
	await _drag_screw_to(phillips, flat_home)
	await _seconds(1.0)
	_expect(
		flat.travel == Screw.Travel.RESTING
		and phillips.travel == Screw.Travel.RESTING,
		"a Phillips screw dropped on a flathead hole does not seat",
	)
	await _drag_screw_to(flat, flat_home)
	_expect(
		await _wait_for_travel(flat, Screw.Travel.HOME, 3.0),
		"the flathead screw still seats into its own hole",
	)
	await _drag_screw_to(phillips, phillips_home)
	_expect(
		await _wait_for_travel(phillips, Screw.Travel.HOME, 3.0),
		"the Phillips screw still seats into its own hole",
	)


## The Phillips box holds two Phillips screws. The left one seats
## into the right hole, and the right one then seats into the hole
## the left one left behind.
func _check_same_type_swaps() -> void:
	var left := _cover.get_node("ScrewLeft") as Screw
	var right := _cover.get_node("ScrewRight") as Screw
	if not _expect(
		is_instance_valid(left) and is_instance_valid(right),
		"the Phillips box has two Phillips screws",
	):
		return
	var left_home := left.global_position
	var right_home := right.global_position
	await _remove_screw(left)
	await _remove_screw(right)
	await _prepare_cover_for_return()
	await _drag_screw_to(left, right_home)
	_expect(
		await _wait_for_travel(left, Screw.Travel.HOME, 3.0),
		"a Phillips screw dropped on the other Phillips hole seats",
	)
	_expect(
		left.global_position.distance_to(right_home) < 0.5
		and right.global_position.distance_to(left_home) < 0.5
		and right.travel == Screw.Travel.RESTING,
		"the two screws traded holes, and the other still rests",
	)
	await _drag_screw_to(right, left_home)
	_expect(
		await _wait_for_travel(right, Screw.Travel.HOME, 3.0)
		and left.slide == 1.0
		and right.slide == 1.0,
		"the second screw seats into the hole left behind, loose",
	)


## Takes both screws' cover off and puts it back on, with the
## work under it finished, so its screws can come back. Also
## checks the put-back cover draws over the inside (LX65).
func _prepare_cover_for_return() -> void:
	var grab_point := _find_cover_grab_point()
	if not _expect(
		grab_point != Vector2.INF,
		"found a clear patch of cover to grab",
	):
		return
	await _press_down(grab_point)
	await _move_to(Vector2(360.0, 60.0))
	await _release_at(Vector2(360.0, 60.0))
	_expect(not _cover.is_on, "dragging the loose cover takes it off")
	for layer in _item.layers:
		for point in layer.get_points():
			if (
				point.mode != InteractionPoint.Mode.FINISHED
				and point.role != InteractionPoint.Role.FASTENER
			):
				point.finish()
	await _wait_for_cover_rest()
	await _press_down(_cover.global_position)
	await _move_to(_cover.get_home_global_position())
	await _release_at(_cover.get_home_global_position())
	await _seconds(0.8)
	_expect(_cover.is_on, "dropped close, the cover tweens back on")
	var inside := _item.layers[0]
	_expect(
		_cover.get_index() > inside.get_index(),
		"back on, the cover draws over the inside layer"
		+ " (cover at %d, inside at %d)"
		% [_cover.get_index(), inside.get_index()],
	)


## Waits until a dropped cover has come to rest on the bench. A
## drop outside the workable area flies back in first, and a
## press while it flies cannot grab it.
func _wait_for_cover_rest() -> void:
	for frame in 300:
		if not _cover.is_returning and not _cover.is_moving:
			return
		await get_tree().physics_frame


## Puts the Phillips test box on the bench in place of the item
## on it, which this probe has already seated its screws into.
func _swap_to_phillips_item() -> void:
	var old := G.level.active_repairable
	G.level.active_repairable = null
	old.queue_free()
	await _physics_frames(2)
	_item = G.level.spawn_repairable(
		Repairable.Type.TEST_PHILLIPS_REPAIRABLE
	)
	if not _expect(await _wait_for_landing(), "the Phillips box lands"):
		_item = null
		return
	_cover = _item.layers[_item.layers.size() - 1]


func _remove_screw(screw: Screw) -> void:
	screw.remove()
	_expect(
		await _wait_for_travel(screw, Screw.Travel.RESTING, 3.0),
		"%s comes out and rests on the bench" % screw.name,
	)


## Drags a resting screw by its middle and lets go at a world
## position, the way a player drops it on a hole.
func _drag_screw_to(screw: Screw, target: Vector2) -> void:
	var middle := (
		screw.bench_art.global_position + screw.rest_hit_offset
	)
	await _press_down(middle)
	await _move_to(target)
	await _release_at(target)


## A point on the cover's art with no interaction point and no
## resting screw on it. A resting screw there takes the press
## first, and the cover never moves.
func _find_cover_grab_point() -> Vector2:
	for x_offset in range(-80, 81, 20):
		for y_offset in range(-60, 61, 20):
			var point := (
				_cover.global_position
				+ Vector2(float(x_offset), float(y_offset))
			)
			if (
				_cover.has_point(point)
				and not is_instance_valid(_hand.find_point(point))
				and not is_instance_valid(
					G.level.get_resting_screw_at(point)
				)
			):
				return point
	return Vector2.INF
