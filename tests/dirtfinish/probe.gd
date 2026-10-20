extends "res://tests/probe_base.gd"
## Dirt never gates a finish. The toaster's grime and the
## dust a whacked TV spews across the bench are polish, not
## repairs: with every required point done, both items call
## themselves finished with the dirt still on them. (Left
## dirt still costs rating when the item ships; it just
## cannot hold the finish hostage.) Required points are
## finished directly here, as the hints probe does.
##
## Run it with `tests/run.ps1 -Name dirtfinish`.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has(
		"--screenshots"
	)
	await get_tree().process_frame
	var main: Node = (
		load(_MAIN_SCENE_PATH) as PackedScene
	).instantiate()
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
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TOASTER,
		Repairable.Type.TV,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(
		await _wait_for_landing(), "the toaster lands"
	):
		return
	_hand = G.level.hand
	var toaster := G.level.active_repairable
	await _check_item(toaster, "the toaster")
	# The TV lands once the toaster ships.
	var tv: Repairable = null
	for frame in 3600:
		var active := G.level.active_repairable
		if (
			is_instance_valid(active) and active != toaster
			and active.mode == Repairable.Mode.UNDER_REPAIR
		):
			tv = active
			break
		await get_tree().physics_frame
	if not _expect(is_instance_valid(tv), "the TV lands"):
		return
	await _check_item(tv, "the TV")


func _check_item(item: Repairable, label: String) -> void:
	var kind := (
		Repairable.Type.TV
		if item.item_name == "TV"
		else Repairable.Type.TOASTER
	)
	# The TV's dust is the spew a whack throws on the bench.
	if kind == Repairable.Type.TV:
		G.level.spawn_bench_dust(item.global_position, 8)
		await _seconds(1.5)
		_expect(
			not G.level.get_bench_dust().is_empty(),
			"the TV's spewed dust is on the bench",
		)
	# Every required point but the dirt gets done. The dirt
	# is left exactly as it lies.
	for layer in item.layers:
		for point in layer.get_points():
			if point is DirtSpot:
				continue
			if point.needs_work():
				point.finish()
	await _physics_frames(6)
	var dirt_left := 0
	for layer in item.layers:
		for point in layer.get_points():
			if (
				point is DirtSpot
				and point.mode != InteractionPoint.Mode.FINISHED
			):
				dirt_left += 1
	if kind == Repairable.Type.TOASTER:
		_expect(
			dirt_left == 3,
			"the toaster still wears its three grime spots",
		)
	_expect(
		item.has_finished,
		"%s finishes with its dirt uncleaned" % label,
	)
	# Ship it so the next item can land.
	await _drag(item.global_position, Vector2(-587.0, 105.0))
	var shipped := false
	for frame in 300:
		if G.level.active_repairable != item:
			shipped = true
			break
		await get_tree().physics_frame
	_expect(shipped, "%s ships" % label)
	await _physics_frames(10)


func _wait_until(callable: Callable) -> bool:
	for frame in 300:
		if callable.call():
			return true
		await get_tree().physics_frame
	return callable.call()


func _drag(from: Vector2, to: Vector2) -> void:
	await _press_down(from)
	await _move_to(to)
	await _release_at(to)
