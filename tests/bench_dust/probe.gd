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
	_check_receipt_tags()

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
	# Spewed dust is the level's, not the item's: no layer
	# Shape mask may clip it, wherever it settles.
	var is_unclipped := not spawned.is_empty()
	for dust in spawned:
		is_unclipped = (
			is_unclipped
			and not is_instance_valid(dust._shape_mask)
			and dust.art.get_parent() == dust
		)
	_expect(
		is_unclipped,
		"spewed bench dust is not clipped to any repairable shape",
	)

	# Fresh spew is still flying: it carries a velocity away
	# from the knock and is not a cleanable point yet.
	var spew_origin := spawned[0].global_position
	_expect(
		not spawned[0].is_settled
		and spawned[0].velocity.length() > 1.0,
		"fresh bench dust is flying with a velocity",
	)
	_expect(
		not spawned[0].is_exposed(),
		"flying bench dust is not a cleanable point yet",
	)
	await _seconds(0.2)
	_expect(
		spawned[0].global_position.distance_to(spew_origin) > 4.0,
		"flying bench dust moves from where it spewed"
		+ " (moved %.0f px)"
		% spawned[0].global_position.distance_to(spew_origin),
	)
	var all_settled := false
	for frame in 360:
		all_settled = true
		for dust in spawned:
			all_settled = all_settled and dust.is_settled
		if all_settled:
			break
		await get_tree().physics_frame
	_expect(
		all_settled and spawned[0].is_exposed(),
		"spewed dust settles into cleanable points on the bench",
	)
	_expect(
		spawned[0].global_position.distance_to(spew_origin) > 4.0
		and G.level.is_inside_bench(spawned[0].global_position),
		"the settled dust rests on the bench where it stopped"
		+ " (at %s)" % spawned[0].global_position,
	)

	# Clean the settled clump that sits clearest of the
	# others. The cone may still catch a neighbour that
	# drifted close; that is the game working, so the charge
	# checks below count whatever is actually left.
	var target_dust := spawned[0]
	var best_clearance := -1.0
	for dust in spawned:
		var clearance := INF
		for other in spawned:
			if other != dust:
				clearance = minf(
					clearance,
					dust.global_position.distance_to(
						other.global_position
					),
				)
		if clearance > best_clearance:
			best_clearance = clearance
			target_dust = dust
	await _check_blower_cleans(target_dust)
	var leftovers := G.level.count_bench_dust_left()
	_expect(
		target_dust.mode == InteractionPoint.Mode.FINISHED
		and leftovers < spawned.size(),
		"one clump is blown away and %d are left" % leftovers,
	)

	var points_before := _item.quality.get_defect_points_total()
	var charged := G.level.charge_bench_dust(_item)
	_expect(
		charged == leftovers,
		"the charge takes every leftover (%d)" % leftovers,
	)
	_expect(
		_item.quality.get_defect_points_total()
		== points_before + leftovers * G.settings.bench_dust_points,
		"each leftover costs its bench dust points",
	)
	var summary_count := 0
	for line in _item.quality.get_summary():
		if line.defect == RepairQuality.Defect.BENCH_DUST_LEFT:
			summary_count = line.count
	_expect(
		summary_count == leftovers,
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

	# A drawer part left out on the bench costs the item
	# when it ships; parts put away cost nothing.
	var drawer_parts := G.level.get_drawer_parts()
	if _expect(
		not drawer_parts.is_empty(), "the drawers stocked parts"
	):
		var left_out := drawer_parts[0]
		left_out.is_stored = false
		var mess_points := _item.quality.get_defect_points_total()
		_expect(
			G.level.charge_messy_desk(_item) == 1,
			"one part left out is charged",
		)
		_expect(
			_item.quality.get_defect_points_total()
			== mess_points + G.settings.messy_desk_points,
			"the left-out part costs its messy desk points",
		)
		_expect(
			G.level.charge_messy_desk(_item) == 0,
			"a second messy charge costs nothing more",
		)
		left_out.is_stored = true


## The receipt's clerk notes (RepairQuality.get_receipt_tags):
## short tags, biggest cost first, counts as ×N, capped at
## four, nothing for a clean on-time repair.
func _check_receipt_tags() -> void:
	var clean := RepairQuality.new()
	_expect(
		clean.get_receipt_tags().is_empty(),
		"a clean repair has no receipt tags",
	)
	var quality := RepairQuality.new()
	quality.par_time_sec = 90.0
	quality.repair_time_sec = 400.0
	quality.add_defect(RepairQuality.Defect.CRACK, Vector2.ZERO, null)
	quality.add_defect(
		RepairQuality.Defect.GLUE_BLOB, Vector2.ZERO, null
	)
	quality.add_defect(
		RepairQuality.Defect.GLUE_BLOB, Vector2.ZERO, null
	)
	quality.add_defect(
		RepairQuality.Defect.LEFTOVER_DUST, Vector2.ZERO, null
	)
	quality.add_defect(
		RepairQuality.Defect.SCREW_DAMAGE, Vector2.ZERO, null
	)
	# Costs: slow 30 (capped), cracked 15, glue mess 10,
	# dust 3, slipped screws 2: the cap drops the last.
	_expect(
		quality.get_receipt_tags()
		== ["slow", "cracked", "glue mess ×2", "dust"],
		"the tags name what cost points, biggest first (%s)"
		% [quality.get_receipt_tags()],
	)


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
