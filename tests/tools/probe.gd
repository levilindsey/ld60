extends "res://tests/probe_base.gd"
## The effect tools (LX14, LX18, LX20). Boots the game, takes the
## rag, the air blower and the hammer off the rack, and works test
## points spawned onto the test item's cover with pushed input.
##
## Run it with `tests/run.ps1 -Name tools`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/tools/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _GRIME_SCENE_PATH := "res://src/interaction_points/grime_spot.tscn"
const _DUST_SCENE_PATH := "res://src/interaction_points/dust_clump.tscn"
const _FAN_SCENE_PATH := "res://src/interaction_points/fan.tscn"
const _STUCK_SCENE_PATH := "res://src/interaction_points/stuck_part.tscn"
const _BENT_SCENE_PATH := "res://src/interaction_points/bent_part.tscn"
const _SEAT_SCENE_PATH := "res://src/interaction_points/seat_part.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _cover: RepairLayer


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
	_item = G.level.active_repairable
	_cover = _item.layers[_item.layers.size() - 1]
	_hand = G.level.hand

	_expect(
		G.level.tools_by_type.has(Tool.Type.RAG)
		and G.level.tools_by_type.has(Tool.Type.AIR_BLOWER)
		and G.level.tools_by_type.has(Tool.Type.HAMMER),
		"rag, air blower and hammer are on the rack",
	)
	_check_holder_shadows()
	await _check_holder_return()
	await _check_rag()
	await _check_air_blower()
	await _check_hammer()


## Each stored tool's shadow follows its holder treatment: the
## glue's ellipse sits at its holder contact, the rag casts its
## full shape, and the drivers cast only below their necks.
func _check_holder_shadows() -> void:
	var glue := G.level.tools_by_type[Tool.Type.GLUE] as Tool
	var rag := G.level.tools_by_type[Tool.Type.RAG] as Tool
	var driver := G.level.tools_by_type[
		Tool.Type.FLAT_HEAD_SCREW_DRIVER
	] as Tool
	_expect(
		glue.holder_shadow == Tool.HolderShadow.ELLIPSE_AT_HOLDER
		and glue._drop_shadow.kind == DropShadow.Kind.ELLIPSE
		and glue._drop_shadow.anchor == glue.holder_area,
		"the stored glue casts an ellipse at its holder contact",
	)
	_expect(
		rag.holder_shadow == Tool.HolderShadow.SILHOUETTE
		and rag._drop_shadow.kind == DropShadow.Kind.SILHOUETTE
		and not is_instance_valid(rag._drop_shadow.clip_holder)
		and rag._drop_shadow.get_copy_count() > 0,
		"the hanging rag casts its full shape (%d copies)"
		% rag._drop_shadow.get_copy_count(),
	)
	_expect(
		driver.holder_shadow
		== Tool.HolderShadow.SILHOUETTE_BELOW_HOLDER
		and driver._drop_shadow.kind == DropShadow.Kind.SILHOUETTE
		and driver._drop_shadow.clip_holder
		== driver._get_holder_shape()
		and driver._drop_shadow.get_copy_count() > 0,
		"the stored driver casts only below its neck (%d copies)"
		% driver._drop_shadow.get_copy_count(),
	)
	var art_rect := _union_canvas_rect(driver)
	var shadow_rect := Rect2()
	var shadow_found := false
	for pair in driver._drop_shadow._copies:
		var copy_rect := _canvas_world_rect(pair[0] as CanvasItem)
		shadow_rect = (
			copy_rect if not shadow_found else shadow_rect.merge(copy_rect)
		)
		shadow_found = true
	_expect(
		shadow_found
		and shadow_rect.position.x < art_rect.position.x - 1.0
		and shadow_rect.end.x > art_rect.end.x + 1.0,
		"the stored driver's shadow peeks out on both sides"
		+ " (art %s, shadow %s)" % [art_rect, shadow_rect],
	)


## Narrows a sprite's full-canvas rect to its used
## (non-transparent) part, where the art actually is.
func _used_rect(texture: Texture2D, canvas_rect: Rect2) -> Rect2:
	var image := texture.get_image()
	if is_instance_valid(image) and not image.is_empty():
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			return Rect2(
				canvas_rect.position + Vector2(used.position),
				Vector2(used.size),
			)
	return canvas_rect


## The world-space bounds of one drawn sprite or polygon.
func _canvas_world_rect(item: CanvasItem) -> Rect2:
	var local_points: Array[Vector2] = []
	if item is Sprite2D:
		var sprite := item as Sprite2D
		var rect := sprite.get_rect()
		if is_instance_valid(sprite.texture) and not sprite.region_enabled:
			rect = _used_rect(sprite.texture, rect)
		local_points = [
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
	elif item is AnimatedSprite2D:
		var animated := item as AnimatedSprite2D
		var rect := Rect2()
		if is_instance_valid(animated.sprite_frames):
			var texture := animated.sprite_frames.get_frame_texture(
				animated.animation,
				animated.frame,
			)
			if is_instance_valid(texture):
				var size := texture.get_size()
				rect = (
					Rect2(animated.offset - size * 0.5, size)
					if animated.centered
					else Rect2(animated.offset, size)
				)
				rect = _used_rect(texture, rect)
		local_points = [
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
	elif item is Polygon2D:
		var polygon := item as Polygon2D
		for point in polygon.polygon:
			local_points.append(point + polygon.offset)
	if local_points.is_empty():
		return Rect2()
	var transform := item.get_global_transform()
	var result := Rect2(transform * local_points[0], Vector2.ZERO)
	for index in range(1, local_points.size()):
		result = result.expand(transform * local_points[index])
	return result


## The union of the world bounds of every visible sprite and
## polygon under `root`.
func _union_canvas_rect(root: Node) -> Rect2:
	var result := Rect2()
	var found := false
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if (
			node is Sprite2D
			or node is AnimatedSprite2D
			or node is Polygon2D
		):
			var item := node as CanvasItem
			if not item.is_visible_in_tree():
				continue
			var rect := _canvas_world_rect(item)
			result = rect if not found else result.merge(rect)
			found = true
	return result


## Dragging a held tool's tip over another tool's holder does
## nothing; over its own holder it puts the tool away.
func _check_holder_return() -> void:
	var driver := await _grab(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	# Off the rack and away from the holders first.
	await _move_to(Vector2(-100.0, 100.0))
	await _physics_frames(4)
	_expect(
		driver.mode == Tool.Mode.HELD,
		"the flathead driver is in hand off the rack",
	)
	await _move_to(
		G.level.get_tool_holder_position(Tool.Type.PHILLIPS_SCREW_DRIVER)
	)
	await _physics_frames(4)
	_expect(
		driver.mode == Tool.Mode.HELD,
		"another tool's holder does not take the driver",
	)
	await _move_to(
		G.level.get_tool_holder_position(
			Tool.Type.FLAT_HEAD_SCREW_DRIVER
		)
	)
	var is_stored := false
	for frame in 90:
		await _physics_frames(1)
		if driver.mode == Tool.Mode.STORED:
			is_stored = true
			break
	_expect(
		is_stored and _hand.is_empty(),
		"the tip entering its own holder puts the driver away",
	)


## Takes a tool off the rack by pressing the tool itself.
func _grab(type: Tool.Type) -> Tool:
	var tool := G.level.tools_by_type[type] as Tool
	await _grab_tool(tool)
	return tool


func _spawn_point(
	scene_path: String, at_position: Vector2
) -> InteractionPoint:
	var scene := load(scene_path) as PackedScene
	var point := scene.instantiate() as InteractionPoint
	_cover.add_child(point)
	point.position = at_position
	return point


func _check_rag() -> void:
	var grime := _spawn_point(
		_GRIME_SCENE_PATH, Vector2(-30, -25)
	) as GrimeSpot
	await _physics_frames(2)
	var rag_tool := await _grab(Tool.Type.RAG)
	var rag := rag_tool as Rag
	_expect(_hand.held == rag, "the hand holds the rag")
	var rag_holder := G.level.get_tool_holder(Tool.Type.RAG)
	_expect(
		is_instance_valid(rag_holder) and rag_holder.is_outline_shown(),
		"the rag holder outline shows while the rag is held",
	)
	_expect(
		is_instance_valid(rag_holder)
		and rag_holder.outline_polygon.size() >= 3,
		"the rag holder carries an outline polygon",
	)
	_expect(
		rag.held_sprite.visible and not rag.hanging_sprite.visible,
		"held rag shows the bunched sprite",
	)
	var spot_position := grime.global_position
	await _press_down(spot_position)
	for swing in 8:
		await _move_to(spot_position + Vector2(28, 0))
		await _move_to(spot_position + Vector2(-28, 0))
	await _release_at(spot_position)
	_expect(
		grime.mode == InteractionPoint.Mode.FINISHED,
		"dragging the rag cleans the grime",
	)

	# A sensitive surface smears in stages when wiped.
	var surface := Surface.new()
	surface.collision_layer = Settings.PhysicsLayer.SURFACES
	surface.type = Surface.Type.PAPER_LABEL
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(70, 40)
	shape_node.shape = rectangle
	surface.add_child(shape_node)
	_cover.add_child(surface)
	surface.position = Vector2(0, 32)
	await _physics_frames(2)
	var points_before := _item.quality.get_defect_points_total()
	var surface_position := surface.global_position
	await _press_down(surface_position)
	for swing in 8:
		await _move_to(surface_position + Vector2(30, 0))
		await _move_to(surface_position + Vector2(-30, 0))
	await _release_at(surface_position)
	_expect(
		_item.quality.get_defect_points_total() == points_before + 10,
		"wiping a paper label costs a ruined smear",
	)
	await _put_tool_away(rag)
	await _physics_frames(2)
	_expect(
		rag.mode == Tool.Mode.STORED and rag.hanging_sprite.visible,
		"stored rag shows the hanging sprite",
	)
	_expect(
		is_instance_valid(rag_holder) and not rag_holder.is_outline_shown(),
		"the rag holder outline hides once the rag is stored",
	)


## The press point that puts the blower's nozzle 60 px from a
## target, up the puff direction from it.
func _aim_press(blower: AirBlower, target: Vector2) -> Vector2:
	var nozzle_offset: Vector2 = (
		blower.get_nozzle_position() - blower.get_tip_position()
	)
	return target - blower.get_nozzle_direction() * 60.0 - nozzle_offset


func _check_air_blower() -> void:
	var dust := _spawn_point(
		_DUST_SCENE_PATH, Vector2(30, -25)
	) as DustClump
	var fan := _spawn_point(_FAN_SCENE_PATH, Vector2(-30, 25)) as Fan
	await _physics_frames(2)
	var blower_tool := await _grab(Tool.Type.AIR_BLOWER)
	var blower := blower_tool as AirBlower
	_expect(_hand.held == blower, "the hand holds the air blower")
	_expect(blower.plump_sprite.visible, "the bulb starts plump")
	# Let the held turn settle, so the aim uses the final direction.
	await _seconds(0.5)
	var aim := _aim_press(blower, dust.global_position)
	await _press_down(aim)
	_expect(blower.squeezed_sprite.visible, "a tap squeezes the bulb")
	await _release_at(aim)
	for puff in 4:
		await _seconds(0.25)
		await _press_at(aim)
	await _seconds(0.6)
	_expect(
		dust.mode == InteractionPoint.Mode.FINISHED,
		"puffs blow the dust away",
	)
	var fan_aim := _aim_press(blower, fan.global_position)
	for puff in 3:
		await _press_at(fan_aim)
		await _seconds(0.25)
	await _seconds(0.3)
	_expect(
		not is_zero_approx(fan.art.rotation),
		"puffs spin the fan",
	)
	# Gliding onto its holder puts a held tool away on its own.
	# Pressing there would only take it again.
	await _move_to(
		G.level.get_tool_holder_position(Tool.Type.AIR_BLOWER)
	)
	for frame in 60:
		if blower.mode == Tool.Mode.STORED:
			break
		await get_tree().physics_frame
	_expect(
		blower.mode == Tool.Mode.STORED,
		"the air blower goes back on the rack",
	)


func _check_hammer() -> void:
	var stuck := _spawn_point(
		_STUCK_SCENE_PATH, Vector2(12, 30)
	) as StuckPart
	stuck.hits_needed = 2
	var bent := _spawn_point(_BENT_SCENE_PATH, Vector2(0, -32)) as BentPart
	var seat := _spawn_point(_SEAT_SCENE_PATH, Vector2(-15, -5)) as SeatPart
	await _physics_frames(2)
	var hammer_tool := await _grab(Tool.Type.HAMMER)
	var hammer := hammer_tool as Hammer
	_expect(_hand.held == hammer, "the hand holds the hammer")

	# A tap is too weak to jog the stuck part.
	await _strike(hammer, stuck.global_position, 0.05)
	_expect(stuck.hits_done == 0, "a tap below the band does nothing")
	await _strike(hammer, stuck.global_position, 0.6)
	_expect(stuck.hits_done == 1, "a hit in the band jogs the part")
	await _strike(hammer, stuck.global_position, 0.6)
	_expect(
		stuck.mode == InteractionPoint.Mode.FINISHED,
		"enough hits free the stuck part",
	)

	var error_before := bent.current_error_deg
	await _strike(hammer, bent.global_position, 0.6)
	_expect(
		bent.current_error_deg < error_before
		and bent.mode != InteractionPoint.Mode.FINISHED,
		"a hit in the band bends the part back a share",
	)
	var defects_before := _item.quality.get_defect_count()
	await _strike(hammer, bent.global_position, 1.3)
	_expect(
		bent.current_error_deg < 0.0,
		"a hit over the band flips the bend",
	)
	_expect(
		_item.quality.get_defect_count() > defects_before,
		"a hit over the band costs a dent",
	)

	await _strike(hammer, seat.global_position, 0.6)
	_expect(
		is_equal_approx(seat.seat_progress, 0.5),
		"a hit in the band seats the part halfway",
	)
	await _strike(hammer, seat.global_position, 1.3)
	_expect(
		seat.mode == InteractionPoint.Mode.FINISHED,
		"a hard hit seats the part and finishes it",
	)


## Holds a swing for `hold_sec` at a point, then lets it go and
## waits out the swing, the hit stop and the recoil.
func _strike(_hammer: Hammer, at_position: Vector2, hold_sec: float) -> void:
	await _press_down(at_position)
	await _seconds(hold_sec)
	await _release_at(at_position)
	await _seconds(0.5)
