extends "res://tests/probe_base.gd"
## Bench dust. Boots the game, spews dust onto the bench with
## `Level.spawn_bench_dust()`, cleans one clump with the real
## air blower, then charges the item for what is left and
## clears the bench.
##
## Run it with `tests/run.ps1 -Name bench_dust` once the run
## has a row there, or from the repo root (PowerShell):
##   godot --headless --path . res://tests/bench_dust/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _item: Repairable


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
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_hand = G.level.hand
	_item = G.level.active_repairable

	_expect(
		G.level.count_bench_dust_left() == 0
		and G.level.get_bench_dust().is_empty(),
		"the bench starts with no dust",
	)
	_expect(
		RepairQuality.get_defect_name(
			RepairQuality.Defect.BENCH_DUST_LEFT
		) == "Dust on the bench"
		and G.settings.get_defect_points(
			RepairQuality.Defect.BENCH_DUST_LEFT
		) == G.settings.bench_dust_points,
		"bench dust left has a receipt name and a points cost",
	)

	# Three spews far apart, so the puff cone aimed at the
	# first cannot reach the other two.
	var spew_point := _item.global_position + Vector2(70.0, 30.0)
	var spawned: Array[BenchDust] = []
	spawned.append_array(G.level.spawn_bench_dust(spew_point, 1))
	spawned.append_array(
		G.level.spawn_bench_dust(
			_item.global_position + Vector2(-160.0, -70.0), 1
		)
	)
	spawned.append_array(
		G.level.spawn_bench_dust(
			_item.global_position + Vector2(-160.0, 100.0), 1
		)
	)
	_expect(spawned.size() == 3, "the spews spawn three clumps")
	_expect(
		G.level.get_bench_dust().size() == 3
		and G.level.count_bench_dust_left() == 3,
		"three clumps are on the bench and left to clean",
	)
	var is_on_bench := not spawned.is_empty()
	for dust in spawned:
		is_on_bench = (
			is_on_bench and G.level.is_inside_bench(dust.global_position)
		)
	_expect(is_on_bench, "the clumps land on the bench")

	await _check_blower_cleans(spawned[0])
	_expect(
		G.level.count_bench_dust_left() == 2,
		"two clumps are left after one is blown away",
	)

	var points_before := _item.quality.get_defect_points_total()
	var charged := G.level.charge_bench_dust(_item)
	_expect(charged == 2, "the charge takes both leftovers")
	_expect(
		_item.quality.get_defect_points_total()
		== points_before + 2 * G.settings.bench_dust_points,
		"each leftover costs its bench dust points",
	)
	var summary_count := 0
	for line in _item.quality.get_summary():
		if line.defect == RepairQuality.Defect.BENCH_DUST_LEFT:
			summary_count = line.count
	_expect(
		summary_count == 2,
		"the receipt lists the bench dust left",
	)
	_expect(
		G.level.charge_bench_dust(_item) == 0,
		"a second charge costs nothing more",
	)

	G.level.clear_bench_dust()
	await _physics_frames(2)
	_expect(
		G.level.get_bench_dust().is_empty()
		and G.level.count_bench_dust_left() == 0,
		"clearing empties the bench",
	)
	G.level.spawn_bench_dust(spew_point, 1)
	_expect(
		G.level.count_bench_dust_left() == 1,
		"a fresh spew counts again",
	)
	G.level.clear_bench_dust()
	await _physics_frames(2)


## Takes the blower off the rack and puffs at one clump until
## the puff blows it off the bench.
func _check_blower_cleans(dust: BenchDust) -> void:
	var blower := await _grab_blower()
	_expect(_hand.held == blower, "the hand holds the air blower")
	await _seconds(0.5)
	for puff in 8:
		if dust.mode == InteractionPoint.Mode.FINISHED:
			break
		await _press_at(_aim_press(blower, dust.global_position))
		await _seconds(0.3)
	await _seconds(0.6)
	_expect(
		dust.mode == InteractionPoint.Mode.FINISHED,
		"puffs blow the bench dust away",
	)
	await _put_tool_away(blower)


## Takes the blower off the rack by pressing the middle of
## its grab area. The shared holder-shape press sits where
## the rack's grab areas overlap, so it can take a driver
## instead; the middle of the blower's own area cannot.
func _grab_blower() -> AirBlower:
	var blower := G.level.tools_by_type[
		Tool.Type.AIR_BLOWER
	] as AirBlower
	var shape := blower.grab_area.get_child(0) as CollisionPolygon2D
	var centroid := Vector2.ZERO
	for point in shape.polygon:
		centroid += point
	centroid /= float(shape.polygon.size())
	await _press_at(shape.to_global(centroid))
	return blower


## The press point that puts the blower's nozzle 60 px from a
## target, up the puff direction from it.
func _aim_press(blower: AirBlower, target: Vector2) -> Vector2:
	var nozzle_offset: Vector2 = (
		blower.get_nozzle_position() - blower.get_tip_position()
	)
	return target - blower.get_nozzle_direction() * 60.0 - nozzle_offset
