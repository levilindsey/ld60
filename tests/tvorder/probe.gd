extends "res://tests/probe_base.gd"
## The TV, repaired out of order: whack it first and blow
## the spewed bench dust away before touching the other
## bits, straighten the antenna, swap the controls, and
## only then land the final whack — then blow the last
## dust away after the item has finished. Every stage must
## work in this order.
##
## Run it with `tests/run.ps1 -Name tvorder`, or from the
## repo root (PowerShell):
##   godot --headless --path . res://tests/tvorder/probe.tscn
## Exit code 0 means every check passed.

const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _antenna: BentPart
var _controls: PartSocket
var _whack: StuckPart


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	var main := (
		(load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
		as Main
	)
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _seconds(0.3)
	var probe_queue: Array[Repairable.Type] = [Repairable.Type.TV]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the TV lands"):
		_finish(1)
		return
	_hand = G.level.hand
	_item = G.level.active_repairable
	for layer in _item.layers:
		for point in layer.get_points():
			if point is BentPart:
				_antenna = point as BentPart
			elif point is PartSocket:
				_controls = point as PartSocket
			elif point is StuckPart:
				_whack = point as StuckPart
	if not _expect(
		is_instance_valid(_antenna)
		and is_instance_valid(_controls)
		and is_instance_valid(_whack),
		"the TV has an antenna, a controls socket and a final whack",
	):
		_finish(1)
		return
	await _whack_first_and_blow()
	await _straighten_and_blow()
	await _swap_controls()
	await _final_whack_and_blow()
	_finish(0 if _failures.is_empty() else 1)


## Where the pointer must sit for the tool's working end to
## land on `target`, once the tool settles into the hand.
func _tool_pointer(tool: Tool, target: Vector2) -> Vector2:
	var settle_frames := 0
	while settle_frames < 90 and (
		tool.follow_offset.length() > 0.5
		or (
			is_instance_valid(tool.rotation_tween)
			and tool.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		settle_frames += 1
	var offset := (
		tool.get_work_end_position() - tool.get_tip_position()
	)
	return target - offset


## One hammer strike on `target`, wound into the band.
func _strike(tool: Tool, target: Vector2) -> void:
	var pointer := await _tool_pointer(tool, target)
	await _press_down(pointer)
	await _seconds(0.65)
	await _release_at(pointer)
	await _seconds(0.4)


func _wait_for_settled_dust() -> void:
	await _wait_until(
		func() -> bool:
			for dust in G.level.get_bench_dust():
				if not (dust as BenchDust).is_settled:
					return false
			return true,
		300,
	)


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for frame in max_frames:
		if condition.call():
			return true
		await _physics_frames(1)
	return condition.call()


## Blows every bench dust clump away, one puff at a time.
func _blow_all_dust(label: String) -> void:
	var blower := G.level.tools_by_type[Tool.Type.AIR_BLOWER] as Tool
	if _hand.held != blower:
		# The rack's grab areas overlap, so the shared
		# holder-shape press can take a driver instead:
		# press the middle of the blower's own grab area
		# (the bench dust probe's grab).
		var shape := (blower as AirBlower).grab_area.get_child(0) as CollisionPolygon2D
		var centroid := Vector2.ZERO
		for vertex in shape.polygon:
			centroid += vertex
		centroid /= float(shape.polygon.size())
		await _press_at(shape.to_global(centroid))
		await _seconds(0.3)
	if not _expect(
		_hand.held == blower, "the hand holds the air blower"
	):
		return
	await _wait_for_settled_dust()
	var air_blower := blower as AirBlower
	var puffs := 0
	while G.level.count_bench_dust_left() > 0 and puffs < 80:
		var dust: BenchDust = null
		for candidate in G.level.get_bench_dust():
			if candidate.mode != InteractionPoint.Mode.FINISHED:
				dust = candidate as BenchDust
				break
		if not is_instance_valid(dust):
			break
		# The press that puts the nozzle 60 px up the puff
		# direction from the clump (the bench dust probe's aim).
		var nozzle_offset: Vector2 = (
			air_blower.get_nozzle_position()
			- air_blower.get_tip_position()
		)
		var press_point: Vector2 = (
			dust.global_position
			- air_blower.get_nozzle_direction() * 60.0
			- nozzle_offset
		)
		await _press_at(press_point)
		await _seconds(0.3)
		puffs += 1
	_expect(
		G.level.count_bench_dust_left() == 0,
		label + " (%d puffs)" % puffs,
	)
	await _put_tool_away(blower)
	await _seconds(0.3)


func _whack_first_and_blow() -> void:
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Tool
	await _grab_tool(hammer)
	await _seconds(0.3)
	await _strike(hammer, _item.global_position + Vector2(30, 0))
	await _put_tool_away(hammer)
	await _wait_for_settled_dust()
	_expect(
		G.level.count_bench_dust_left() > 0,
		"whacking the TV first spews bench dust",
	)
	await _blow_all_dust(
		"the spewed dust blows away before any other bit is fixed"
	)


func _straighten_and_blow() -> void:
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Tool
	await _grab_tool(hammer)
	await _seconds(0.3)
	for hit in 4:
		if _antenna.mode == InteractionPoint.Mode.FINISHED:
			break
		await _strike(hammer, _antenna.global_position)
	_expect(
		_antenna.mode == InteractionPoint.Mode.FINISHED,
		"the antenna straightens after the dust is gone",
	)
	await _put_tool_away(hammer)
	await _blow_all_dust("the antenna's dust blows away too")


func _swap_controls() -> void:
	await _press_down(_controls.global_position)
	for swing in 10:
		var offset := 30.0 if swing % 2 == 0 else -30.0
		await _move_to(
			_controls.global_position + Vector2(offset, 0)
		)
	await _release_at(_controls.global_position)
	_expect(
		await _wait_until(
			func() -> bool: return not _controls.has_broken_part,
			300,
		),
		"the busted controls wiggle out",
	)
	var fitting: Part = null
	for part in G.level.get_drawer_parts():
		if part.type == _controls.accepted_part and part.is_stored:
			fitting = part
	if not _expect(
		is_instance_valid(fitting), "a new controls part is stocked"
	):
		return
	var drawer := G.level.get_drawers()[fitting.drawer_index]
	await _press_at(drawer.global_position)
	await _wait_until(
		func() -> bool: return drawer.state == Drawer.State.OPEN,
		300,
	)
	await _seconds(0.4)
	await _press_down(fitting.global_position)
	await _seconds(0.3)
	var from := fitting.global_position
	var to := _controls.global_position
	for step in range(1, 7):
		await _move_to(from.lerp(to, float(step) / 6.0))
	await _release_at(to)
	_expect(
		await _wait_until(
			func() -> bool:
				return _controls.mode == InteractionPoint.Mode.FINISHED,
			300,
		),
		"the new controls fit",
	)


func _final_whack_and_blow() -> void:
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Tool
	await _grab_tool(hammer)
	await _seconds(0.3)
	for hit in _whack.hits_needed + 2:
		if _whack.mode == InteractionPoint.Mode.FINISHED:
			break
		await _strike(hammer, _item.global_position + Vector2(-20, 10))
	await _put_tool_away(hammer)
	_expect(
		await _wait_until(
			func() -> bool: return _item.has_finished, 300
		),
		"the final whack finishes the TV last",
	)
	await _blow_all_dust(
		"the last dust still blows away after the TV is finished"
	)
