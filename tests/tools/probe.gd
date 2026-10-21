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
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
	]
	G.settings.item_queue = probe_queue
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
	await _check_holder_shadows()
	_check_driver_art()
	await _check_touch_tap_uses_cursor()
	await _check_tap_keeps_hover()
	await _check_holder_return()
	await _check_rag()
	await _check_air_blower()
	await _check_hammer()


## Both drivers draw something at rest. The flathead's frames
## once shared their filenames with the bird's, and a bird
## export overwrote them with a transparent frame: the driver
## was on the rack with its outline showing and no art.
func _check_driver_art() -> void:
	for type in [
		Tool.Type.FLAT_HEAD_SCREW_DRIVER,
		Tool.Type.PHILLIPS_SCREW_DRIVER,
	]:
		var driver := G.level.tools_by_type[type] as Tool
		var sprite := driver.find_child(
			"AnimatedSprite2D",
			true,
			false,
		) as AnimatedSprite2D
		var is_drawn := false
		if is_instance_valid(sprite):
			var texture := sprite.sprite_frames.get_frame_texture(
				sprite.animation,
				sprite.frame,
			)
			if is_instance_valid(texture):
				var image := texture.get_image()
				is_drawn = (
					is_instance_valid(image)
					and not image.is_empty()
					and image.get_used_rect().has_area()
				)
		_expect(
			is_drawn,
			"the %s driver draws its art at rest"
			% Tool.Type.keys()[type].to_lower(),
		)


## Each stored tool's shadow follows its holder treatment: the
## glue's ellipse sits at its holder contact, and the hanging
## tools (the rag, the drivers) cast no shadow at all.
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
		rag.holder_shadow == Tool.HolderShadow.NONE,
		"the hanging rag asks for no shadow",
	)
	await _physics_frames(30)
	_expect(
		not rag._drop_shadow.visible,
		"the stored rag casts no shadow on its holder",
	)
	_expect(
		driver.holder_shadow == Tool.HolderShadow.NONE
		and not driver._drop_shadow.visible,
		"the stored driver casts no shadow below its shoulders",
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
## A tap away from the point the driver already hovers over
## still engages that point: the press must not snap the
## tool to the tap first (touch taps land where they land).
func _check_tap_keeps_hover() -> void:
	# The test box's own flathead starts under grime, so
	# stand a clean one on the cover for this.
	var screw := _spawn_point(
		"res://src/interaction_points/flat_head_screw.tscn",
		Vector2(60, 120),
	) as FlatHeadScrew
	if not _expect(
		is_instance_valid(screw) and screw.can_engage(),
		"a flathead screw waits on the item",
	):
		return
	var driver := await _grab(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	# Hover the driver's working end over the screw: walk
	# the pointer by however far the working end sits from
	# the screw until it lands on it.
	await _move_to(screw.global_position)
	for attempt in 4:
		await _physics_frames(20)
		var miss: Vector2 = (
			screw.global_position - driver.get_work_end_position()
		)
		if miss.length() < 2.0:
			break
		await _move_to(_hand.pointer_position + miss)
	await _physics_frames(10)
	var hovered := (
		_hand.find_point_for_tool(driver) as FlatHeadScrew
	)
	if not _expect(
		is_instance_valid(hovered),
		"the hovering driver overlaps a screw",
	):
		await _put_tool_away(driver)
		return
	# Tap well away from the screw. The press engages the
	# screw at the hover instead of snapping over there.
	var tap_point := hovered.global_position + Vector2(-220, -150)
	# A finger tap: the press lands with no pointer motion
	# before it, so the tool is still at its hover when the
	# press is routed.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_push_mouse(press, tap_point)
	await _physics_frames(2)
	_expect(
		hovered.mode == InteractionPoint.Mode.ACTIVE,
		"a tap away still engages the hovered screw",
	)
	await _release_at(tap_point)
	await _put_tool_away(driver)
	screw.queue_free()


## A touch tap on a screw the driver is not hovering over
## still engages it: the finger is on the screw, so the
## driver works there. The same tap with a mouse (the
## hover check below, and the hammer's cursor miss) keeps
## the old working end rules.
func _check_touch_tap_uses_cursor() -> void:
	var screw := _spawn_point(
		"res://src/interaction_points/flat_head_screw.tscn",
		Vector2(-60, -100),
	) as FlatHeadScrew
	if not _expect(
		is_instance_valid(screw) and screw.can_engage(),
		"a flathead screw waits for the touch tap",
	):
		return
	var driver := await _grab(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	for frame in 30:
		if driver.mode == Tool.Mode.HELD:
			break
		await _physics_frames(1)
	_expect(
		driver.mode == Tool.Mode.HELD,
		"the driver is in hand for the touch tap",
	)
	# Park the driver well away, so its working end is
	# nowhere near the screw when the tap lands.
	await _move_to(Vector2(220, 160))
	await _physics_frames(10)
	_expect(
		driver.mode == Tool.Mode.HELD
		and not is_instance_valid(_hand.find_point_for_tool(driver)),
		"the parked driver overlaps no screw",
	)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.device = InputEvent.DEVICE_ID_EMULATION
	_push_mouse(press, screw.global_position)
	await _physics_frames(2)
	_expect(
		screw.mode == InteractionPoint.Mode.ACTIVE,
		"a touch tap on the screw engages it",
	)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.device = InputEvent.DEVICE_ID_EMULATION
	_push_mouse(release, screw.global_position)
	await _physics_frames(2)
	# The engaged screw holds the driver until its twists
	# run out; wait for the put-away to land before the
	# screw goes, so nothing keeps a freed point.
	await _put_tool_away(driver)
	for frame in 600:
		if driver.mode == Tool.Mode.STORED:
			break
		await _physics_frames(1)
	if driver.mode == Tool.Mode.STORED:
		screw.queue_free()


func _check_holder_return() -> void:
	var driver := await _grab(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	# Wait out the pickup glide (see _check_seized_screw):
	# until it lands, the driver is still ENTERING.
	for frame in 30:
		if driver.mode == Tool.Mode.HELD:
			break
		await _physics_frames(1)
	# Off the rack and away from the holders first.
	await _move_to(Vector2(-100.0, 100.0))
	await _physics_frames(4)
	_expect(
		driver.mode == Tool.Mode.HELD,
		"the flathead driver is in hand off the rack",
	)
	# The far holder, so neither the tip's path nor the tool's
	# neck can reach the flathead's own holder on the way.
	await _move_to(
		G.level.get_tool_holder_position(Tool.Type.RAG)
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
	var is_circle := is_instance_valid(rag_holder)
	if is_circle:
		for point in rag_holder.outline_polygon:
			if absf(point.length() - rag_holder.outline_radius_px) > 1.0:
				is_circle = false
	_expect(
		is_circle and rag_holder.outline_polygon.size() >= 12,
		"the rag holder's outline is a circle",
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

	# The smack lands where the hammer's working end is, not where
	# the cursor is: a strike aimed by the cursor alone misses.
	await _press_down(stuck.global_position)
	await _seconds(0.6)
	await _release_at(stuck.global_position)
	await _seconds(0.5)
	_expect(
		stuck.hits_done == 0,
		"a strike aimed by the cursor alone does not smack the part",
	)
	var reticle := hammer.get_node("Reticle") as HammerReticle
	_expect(
		reticle.to_global(reticle.get_center()).distance_to(
			hammer.get_work_end_position()
		) < 1.0,
		"the hammer reticle sits on the working end, not the origin",
	)

	# A tap is too weak to jog the stuck part, but even a hit
	# that does nothing still squishes the piece a little.
	var stuck_layer := stuck.get_layer()
	var stuck_rest_scale := stuck_layer.scale
	await _strike(hammer, stuck.global_position, 0.05, 0.10)
	_expect(stuck.hits_done == 0, "a tap below the band does nothing")
	_expect(
		stuck_layer.scale.y < stuck_rest_scale.y * 0.995
		and stuck_layer.scale.y > stuck_rest_scale.y * 0.93,
		"a tap squishes the piece a little (scale y %.3f)"
		% stuck_layer.scale.y,
	)
	await _seconds(0.6)
	await _strike(hammer, stuck.global_position, 0.6)
	_expect(stuck.hits_done == 1, "a hit in the band jogs the part")
	await _strike(hammer, stuck.global_position, 0.6)
	_expect(
		stuck.mode == InteractionPoint.Mode.FINISHED,
		"enough hits free the stuck part",
	)

	# The face only has to overlap the point's area: a strike
	# whose face centre lands beside the point still smacks it
	# when the two areas cross.
	var edge := _spawn_point(
		_STUCK_SCENE_PATH, Vector2(44, 62)
	) as StuckPart
	await _physics_frames(2)
	var face_radius := (
		hammer.get_interaction_shape().shape as CircleShape2D
	).radius * hammer.get_interaction_shape().global_scale.x
	var edge_offset := Vector2(face_radius + 8.0, 0.0)
	await _strike(hammer, edge.global_position + edge_offset, 0.6)
	_expect(
		edge.hits_done == 1,
		"a strike whose face overlaps the point off-centre jogs it"
		+ " (face radius %.0f px, offset %.0f px)"
		% [face_radius, edge_offset.x],
	)

	var error_before := bent.current_error_deg
	await _strike(hammer, bent.global_position, 0.6)
	_expect(
		bent.current_error_deg < error_before
		and bent.mode != InteractionPoint.Mode.FINISHED,
		"a hit in the band bends the part back a share",
	)
	var defects_before := _item.quality.get_defect_count()
	var bent_layer := bent.get_layer()
	var rest_scale := bent_layer.scale
	await _strike(hammer, bent.global_position, 1.3, 0.12)
	_expect(
		bent.current_error_deg < 0.0,
		"a hit over the band flips the bend",
	)
	_expect(
		_item.quality.get_defect_count() > defects_before,
		"a hit over the band costs a dent",
	)
	_expect(
		bent_layer.scale.y < rest_scale.y * 0.95,
		"a denting hit squishes the piece",
	)
	await _seconds(0.6)
	_expect(
		bent_layer.scale.distance_to(rest_scale) < 0.01,
		"the piece springs back to rest after the squish",
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

	# Held at full charge, the hammer trembles hard.
	var offset := (
		hammer.get_work_end_position() - hammer.get_tip_position()
	)
	var press_point := seat.global_position - offset
	await _press_down(press_point)
	await _seconds(G.settings.hammer_charge_sec + 0.2)
	var biggest_tremble := 0.0
	for frame in 30:
		biggest_tremble = maxf(
			biggest_tremble, hammer.art.position.length()
		)
		await _physics_frames(1)
	await _release_at(press_point)
	await _seconds(0.5)
	_expect(
		biggest_tremble > 2.5,
		"the hammer shakes hard held at max (%.1f px)"
		% biggest_tremble,
	)


## Holds a swing for `hold_sec` with the hammer's working end on
## a point, then lets it go and waits out the swing, the hit stop
## and the recoil (or `settle_sec`, when a check wants to look
## sooner).
func _strike(
	hammer: Hammer,
	at_position: Vector2,
	hold_sec: float,
	settle_sec := 0.5,
) -> void:
	var offset := (
		hammer.get_work_end_position() - hammer.get_tip_position()
	)
	var press_point := at_position - offset
	await _press_down(press_point)
	await _seconds(hold_sec)
	await _release_at(press_point)
	await _seconds(settle_sec)
