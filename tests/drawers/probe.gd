extends "res://tests/probe_base.gd"
## Drawer spots: when an item is stocked, every drawer part's
## resting spot and turn inside its drawer are chosen up front,
## spaced apart. Boots the game, checks the stocked parts carry
## their spots, then opens a drawer, closes it and opens it
## again: every part must be exactly where it was, at the same
## turn.
##
## Run it with `tests/run.ps1 -Name drawers`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/drawers/probe.tscn


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _level: Level


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_level = G.level
	_hand = _level.hand
	_check_stocked_spots()
	await _check_spot_spacing()
	await _check_reopen_persists()


## Every stocked part carries a spot inside its drawer's
## interior and the turn chosen for it, and the drawers hold
## about as many parts as each other.
func _check_stocked_spots() -> void:
	var drawers := _level.get_drawers()
	var counts: Array[int] = []
	for drawer in drawers:
		var parts := _level.get_parts_in_drawer(drawer)
		counts.append(parts.size())
		var interior := drawer.get_interior_local_rect()
		for part in parts:
			var name := Part.get_display_name(part.type)
			if not _expect(
				part.has_drawer_spot(),
				"the stocked %s has a drawer spot" % name,
			):
				continue
			_expect(
				interior.has_point(part.drawer_spot_local),
				"the stocked %s rests inside its drawer" % name,
			)
			_expect(
				absf(
					wrapf(
						part.rotation - part.drawer_spot_rotation,
						-PI,
						PI,
					)
				) < 0.001,
				"the stocked %s rests at its chosen turn" % name,
			)
	_expect(
		counts.max() - counts.min() <= 1,
		"the drawers hold about as many parts as each other %s"
		% [counts],
	)
	_check_stock_composition(counts)


## The stock's makeup: every kind the item needs appears
## exactly once across all the drawers, and the total is the
## old set (one of each kind, a copy per socket, the decoy
## setting) scaled by the stock scale, in decoys.
func _check_stock_composition(counts: Array[int]) -> void:
	var item := _level.active_repairable
	var needed_types: Array[Part.Type] = []
	var socket_count := 0
	for layer in item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				socket_count += 1
				var needed := (point as PartSocket).accepted_part
				if not needed_types.has(needed):
					needed_types.append(needed)
	var stocked_by_type := {}
	for drawer in _level.get_drawers():
		for part in _level.get_parts_in_drawer(drawer):
			stocked_by_type[part.type] = (
				int(stocked_by_type.get(part.type, 0)) + 1
			)
	for needed in needed_types:
		_expect(
			int(stocked_by_type.get(needed, 0)) == 1,
			"the needed %s is stocked exactly once"
			% Part.get_display_name(needed),
		)
	var total := 0
	for count in counts:
		total += count
	var previous_total := (
		Part.Type.values().size()
		+ socket_count
		+ maxi(G.settings.decoy_part_count, 0)
	)
	_expect(
		total == roundi(previous_total * 1.4),
		"the drawers hold 1.4x the old stock (%d of %d)"
		% [total, roundi(previous_total * 1.4)],
	)


## Drawer-mates' spots keep most of their reaches apart: no two
## spots in a drawer sit closer than half the smaller part's
## reach, which the layout's best-of-tries should always find
## room for in these drawers.
func _check_spot_spacing() -> void:
	for drawer in _level.get_drawers():
		var parts := _level.get_parts_in_drawer(drawer)
		var world_per_local := (
			drawer.get_open_interior_world_per_local()
		)
		for first_index in parts.size():
			for second_index in range(first_index + 1, parts.size()):
				var first := parts[first_index]
				var second := parts[second_index]
				var apart := (
					(first.drawer_spot_local - second.drawer_spot_local)
					* world_per_local
				).length()
				var wanted := (
					minf(first.get_radius_px(), second.get_radius_px())
					* 0.5
				)
				_expect(
					apart >= wanted,
					(
						"drawer-mates %s and %s are spaced apart"
						+ " (%.0f px apart, want %.0f)"
					)
					% [
						Part.get_display_name(first.type),
						Part.get_display_name(second.type),
						apart,
						wanted,
					],
				)


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false


## Opens the fullest drawer, notes every part's world position
## and turn, closes the drawer and opens it again: everything
## must come back exactly as it was.
func _check_reopen_persists() -> void:
	var drawer: Drawer = null
	var most := -1
	for candidate in _level.get_drawers():
		var count := _level.get_parts_in_drawer(candidate).size()
		if count > most:
			most = count
			drawer = candidate
	if not _expect(
		is_instance_valid(drawer) and most > 0,
		"a stocked drawer to reopen",
	):
		return
	await _press_at(drawer.global_position)
	if not _expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.OPEN
		),
		"the drawer opens",
	):
		return
	await _seconds(0.4)
	var poses := {}
	for part in _level.get_parts_in_drawer(drawer):
		poses[part] = [part.global_position, part.rotation]
		_expect(part.visible, "an open drawer shows its parts")
	await _press_at(Vector2(460.0, 290.0))
	if not _expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.CLOSED
		),
		"the drawer closes",
	):
		return
	await _press_at(drawer.global_position)
	if not _expect(
		await _wait_until(
			func() -> bool: return drawer.state == Drawer.State.OPEN
		),
		"the drawer reopens",
	):
		return
	await _seconds(0.4)
	for part in _level.get_parts_in_drawer(drawer):
		var pose: Array = poses.get(part, [])
		if not _expect(
			pose.size() == 2, "the part was there on the first open"
		):
			continue
		var name := Part.get_display_name(part.type)
		_expect(
			part.global_position.distance_to(pose[0] as Vector2) < 0.5,
			"the %s is back at its spot on reopen" % name,
		)
		_expect(
			absf(wrapf(part.rotation - (pose[1] as float), -PI, PI))
			< 0.001,
			"the %s keeps its turn on reopen" % name,
		)
