extends "res://tests/probe_base.gd"
## Tool misuse on the game & watch: bespoke grab shapes on its
## screws, chip and dpad, a hard hammer hit on the bare front,
## glue squeezed in the wrong spot and wiped up, and dragging
## the whole item around by its main body.
##
## Run it with `tests/run.ps1 -Name misuse`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/misuse/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 150.0

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
		Repairable.Type.GAME_N_WATCH,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the game & watch lands"):
		return
	_hand = G.level.hand
	_item = G.level.active_repairable
	var inside := _item.layers[0]
	var front := _item.layers[_item.layers.size() - 1]
	_check_shapes(inside, front)
	var pieces := G.level.get_broken_pieces()
	if _expect(not pieces.is_empty(), "the item has a broken piece"):
		await _check_piece_grab(pieces[0])
	await _check_hammer(front)
	await _check_glue(front)
	await _check_body_drag(inside, front)


## The screws' hit circles match their heads, and the chip and
## dpad point take presses across their bespoke shapes.
func _check_shapes(inside: RepairLayer, front: RepairLayer) -> void:
	for screw_name in ["ScrewLeft", "ScrewRight"]:
		var screw := front.get_node(screw_name) as Screw
		var hit_radius := (
			(screw.hit_shape.shape as CircleShape2D).radius
			* screw.hit_shape.global_transform.get_scale().x
		)
		_expect(
			hit_radius >= 24.0,
			"the %s hit circle matches its head (%.0f px)"
			% [screw_name, hit_radius],
		)
	var chip := inside.get_node("Chip") as PartSocket
	var chip_spot := chip.global_position + Vector2(25, -30)
	_expect(
		chip.is_point_in_bad_part_shape(chip_spot),
		"the chip's broken part can be grabbed across its art",
	)
	_expect(
		chip.is_point_in_good_part_shape(chip_spot),
		"a new chip can be fitted across the chip's art",
	)
	var dpad_point := front.get_node("DpadPoint") as InteractionPoint
	# (15, 15) in the point's own space, out along the cross's
	# arm: the front layer is scaled down on the bench, so a
	# world (15, 15) would overshoot the art entirely.
	_expect(
		dpad_point.is_point_in_shape(
			dpad_point.global_transform * Vector2(15, 15)
		),
		"the dpad point takes a press across the dpad art",
	)


## The fallen dpad piece can be grabbed near its art's corner,
## past the old middle reach, by its bespoke shape.
func _check_piece_grab(piece: BrokenPiece) -> void:
	for frame in 360:
		if piece.has_detached() and not piece.is_returning:
			break
		await get_tree().physics_frame
	var polygon := piece.get_shape_world_polygon()
	if not _expect(polygon.size() >= 3, "the dpad piece has a shape"):
		return
	var corner := piece.global_position.lerp(polygon[0], 0.95)
	_expect(
		G.level.get_loose_broken_piece_at(corner) == piece,
		"the dpad piece can be grabbed out at its corner",
	)


## A full hammer swing at the bare front (no point, no authored
## surface there) cracks it and records the defect to match.
func _check_hammer(front: RepairLayer) -> void:
	var spot := _find_bare_spot(front, Vector2.INF, 0.0)
	if not _expect(spot != Vector2.INF, "a bare spot on the front"):
		return
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Hammer
	await _press_at(hammer.global_position)
	if not _expect(_hand.held == hammer, "the hand holds the hammer"):
		return
	var pointer := await _tool_pointer_for(hammer, spot)
	var defects_before := _item.quality.get_defect_count()
	var decals_before := _crack_decal_count(front.art)
	await _press_down(pointer)
	await _physics_frames(4)
	_expect(
		hammer.get_locked_layer() == front,
		"the hammer locks onto the front layer's art",
	)
	for frame in 300:
		if hammer.charge >= 0.95:
			break
		await get_tree().physics_frame
	await _release_at(pointer)
	await _seconds(0.8)
	_expect(
		_item.quality.get_defect_count() == defects_before + 1,
		"a full hammer hit on the bare front costs a defect",
	)
	var has_crack := false
	for line in _item.quality.get_summary():
		if line.defect == RepairQuality.Defect.CRACK:
			has_crack = true
	_expect(has_crack, "the bare front cracks under the hammer")
	_expect(
		_crack_decal_count(front.art) == decals_before + 1,
		"the crack shows as a decal",
	)
	await _put_tool_away(hammer)


## Glue squeezed on the bare front leaves a smear, and the rag
## wipes it off for free.
func _check_glue(front: RepairLayer) -> void:
	var spot := _find_bare_spot(front, Vector2.INF, 0.0)
	if not _expect(spot != Vector2.INF, "a second bare spot"):
		return
	var glue := G.level.tools_by_type[Tool.Type.GLUE] as Tool
	await _press_at(glue.global_position)
	if not _expect(_hand.held == glue, "the hand holds the glue"):
		return
	var pointer := await _tool_pointer_for(glue, spot)
	var defects_before := _item.quality.get_defect_count()
	await _press_down(pointer)
	await _seconds(1.1)
	await _release_at(pointer)
	await _physics_frames(5)
	var smear: GlueSmear = null
	for point in front.get_points():
		if point is GlueSmear:
			smear = point as GlueSmear
	if not _expect(
		is_instance_valid(smear), "glue in the wrong spot smears"
	):
		await _put_tool_away(glue)
		return
	_expect(
		is_instance_valid(smear.glue_decal),
		"the smear shows as a glue decal",
	)
	await _put_tool_away(glue)
	var rag := G.level.tools_by_type[Tool.Type.RAG] as Tool
	await _press_at(rag.global_position)
	if not _expect(_hand.held == rag, "the hand holds the rag"):
		return
	await _press_down(smear.global_position)
	for step in 40:
		if smear.mode == InteractionPoint.Mode.FINISHED:
			break
		var sway := 16.0 if step % 2 == 0 else -16.0
		await _move_to(smear.global_position + Vector2(sway, 0))
	await _release_at(smear.global_position)
	_expect(
		smear.mode == InteractionPoint.Mode.FINISHED,
		"the rag wipes the smear off",
	)
	_expect(
		_item.quality.get_defect_count() == defects_before,
		"a wiped smear costs nothing",
	)
	await _put_tool_away(rag)


## With the front layer dragged off, the main body drags the
## whole item to a new spot on the bench and rests there. A
## press on the chip then starts tugging it out.
func _check_body_drag(inside: RepairLayer, front: RepairLayer) -> void:
	for point_name in ["GrimeLeft", "GrimeRight", "ScrewLeft", "ScrewRight"]:
		(front.get_node(point_name) as InteractionPoint).finish()
	await _physics_frames(5)
	var front_spot := _find_bare_spot(front, Vector2.INF, 0.0)
	await _press_down(front_spot)
	await _move_to(front_spot + Vector2(-170, 130))
	await _release_at(front_spot + Vector2(-170, 130))
	for frame in 240:
		if not front.is_on and not front.is_moving:
			break
		await get_tree().physics_frame
	if not _expect(not front.is_on, "the front layer drags off"):
		return
	_expect(
		_item.get_exposed_layer() == inside,
		"the main body is exposed once the front is off",
	)
	var spot := _find_bare_spot(inside, Vector2.INF, 0.0)
	if not _expect(spot != Vector2.INF, "a bare spot on the body"):
		return
	var before := _item.global_position
	var delta := Vector2(110, -20)
	await _press_down(spot)
	_expect(_hand.held == _item, "a press on the body picks the item up")
	await _move_to(spot + delta)
	await _release_at(spot + delta)
	await _seconds(1.0)
	var rest_offset := _item.global_position.distance_to(before + delta)
	_expect(
		rest_offset < 5.0,
		"the item rests where its body was dragged (off by %.1f px)"
		% rest_offset,
	)
	_expect(
		absf(_item.rotation) < 0.02,
		"the dragged item straightens up",
	)
	var chip := inside.get_node("Chip") as PartSocket
	await _press_down(chip.global_position + Vector2(20, 20))
	_expect(
		chip.is_tugging(),
		"a press anywhere on the chip starts tugging it out",
	)
	await _release_at(chip.global_position + Vector2(20, 20))


## A spot on a layer's art with no point on it, optionally kept
## away from another spot.
func _find_bare_spot(
	layer: RepairLayer, avoid: Vector2, avoid_radius: float
) -> Vector2:
	for offset in [
		Vector2(0, -70),
		Vector2(55, -35),
		Vector2(-55, -35),
		Vector2(0, 55),
		Vector2(70, 25),
		Vector2(-70, 25),
		Vector2(30, -60),
	]:
		var spot: Vector2 = _item.global_position + offset
		if not layer.has_point(spot):
			continue
		if avoid != Vector2.INF and spot.distance_to(avoid) < avoid_radius:
			continue
		if is_instance_valid(_hand.find_point(spot)):
			continue
		return spot
	return Vector2.INF


## Crack decals stamped on a layer's art so far.
func _crack_decal_count(art: CanvasItem) -> int:
	var count := 0
	var pending: Array[Node] = [art]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var sprite := node as Sprite2D
		if (
			is_instance_valid(sprite)
			and is_instance_valid(sprite.texture)
			and sprite.texture.resource_path.contains("decals/cracks")
		):
			count += 1
	return count


## The pointer position that puts a held tool's working end on
## a target, once the tool's held turn has settled.
func _tool_pointer_for(tool: Tool, target: Vector2) -> Vector2:
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
	return target - (
		tool.get_work_end_position() - tool.get_tip_position()
	)
