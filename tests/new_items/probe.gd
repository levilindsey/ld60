extends "res://tests/probe_base.gd"
## The TV, keyboard and piano repairables. Boots the game,
## then loads each new item scene onto the bench and works
## its points directly: the TV antenna straightens and swaps
## sprite, its controls socket takes a TV controls part and
## shows the good controls, its final whack finishes, the
## keyboard has two key sockets and dust, and the piano has
## a glue key, grime and an LED socket. The placeholder
## line-up scenes load with a whack to finish.

const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0

var _level: Level


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = "--screenshots" in OS.get_cmdline_args()
	var main := (
		(load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
		as Main
	)
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _seconds(0.3)
	G.settings.first_repairable_override = Settings.FirstRepairable.TV
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	_level = G.level
	_hand = G.level.hand
	_expect(
		G.level.active_repairable.item_name == "TV",
		"the first-repairable override starts at the TV",
	)
	# Skipping ahead drops everything scheduled before the TV:
	# the played order is the authored queue from the TV on.
	var queue := G.settings.item_queue
	var tv_index := queue.find(Repairable.Type.TV)
	_expect(
		tv_index > 0
		and G.level._effective_queue == queue.slice(tv_index),
		"the schedule skips ahead to the TV (order %s)"
		% [G.level._effective_queue],
	)
	G.settings.first_repairable_override = Settings.FirstRepairable.NONE
	await _check_tv_antenna_shape()
	await _check_tv()
	await _check_keyboard()
	await _check_piano()
	await _check_atari()
	await _check_game_n_watch()
	await _check_placeholders()
	await _check_radio_front_size()
	_finish(0 if _failures.is_empty() else 1)


## On the landed TV, a hammer press on the bent antenna's
## authored Shape, far outside its small circle, must strike
## the antenna, not the final whack that any press on the
## item's Shape would otherwise claim.
func _check_tv_antenna_shape() -> void:
	var item := G.level.active_repairable
	var antenna: BentPart
	var whack: StuckPart
	for layer in item.layers:
		for point in layer.get_points():
			if point is BentPart:
				antenna = point as BentPart
			if point is StuckPart:
				whack = point as StuckPart
	if not _expect(
		is_instance_valid(antenna), "the landed TV has an antenna"
	):
		return
	var far_point := antenna.global_position
	for point in antenna.get_shape_world_polygon():
		if (
			point.distance_squared_to(antenna.global_position)
			> far_point.distance_squared_to(antenna.global_position)
		):
			far_point = point
	far_point = far_point.lerp(antenna.global_position, 0.25)
	_expect(
		_hand.find_point(far_point) == antenna,
		"a press on the antenna's Shape finds the antenna",
	)
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Hammer
	await _grab_tool(hammer)
	_expect(_hand.held == hammer, "the hand holds the hammer")
	var settle_frames := 0
	while settle_frames < 90 and (
		hammer.follow_offset.length() > 0.5
		or (
			is_instance_valid(hammer.rotation_tween)
			and hammer.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		settle_frames += 1
	var offset := (
		hammer.get_work_end_position() - hammer.get_tip_position()
	)
	await _move_to(far_point - offset)
	offset = hammer.get_work_end_position() - hammer.get_tip_position()
	await _press_down(far_point - offset)
	for frame in 300:
		if hammer.charge >= 0.35:
			break
		await get_tree().physics_frame
	await _release_at(far_point - offset)
	await _seconds(0.6)
	_expect(
		antenna.current_error_deg < antenna.error_deg,
		"a hammer hit on the antenna's Shape straightens it"
		+ " (error %.1f of %.1f)"
		% [antenna.current_error_deg, antenna.error_deg],
	)
	if is_instance_valid(whack):
		_expect(
			whack.hits_done == 0
			and whack.mode != InteractionPoint.Mode.FINISHED,
			"the antenna hit did not count as the final whack",
		)
	await _put_tool_away(hammer)


func _check_tv() -> void:
	var item := _spawn("res://src/repairables/tv_repairable.tscn")
	if not _expect(is_instance_valid(item), "the TV loads"):
		return
	var tv := item as TVRepairable
	_expect(is_instance_valid(tv), "the TV has its screen script")
	if is_instance_valid(tv):
		_expect(
			tv.static_frames.has(tv.screen.texture),
			"the screen shows static before the fix",
		)
		var first_frame := tv.screen.texture
		var alternated := false
		for _wait in 40:
			await get_tree().create_timer(0.05).timeout
			if tv.screen.texture != first_frame:
				alternated = tv.static_frames.has(tv.screen.texture)
				break
		_expect(
			alternated,
			"the static frames alternate while unfixed",
		)
	_expect(
		is_instance_valid(item.shape),
		"the TV has a Shape",
	)
	if is_instance_valid(item.shape):
		_expect(
			item.shape.collision_layer == 0
			and item.shape.collision_mask == 0
			and not item.shape.monitoring
			and not item.shape.monitorable,
			"the item strips the Shape's collision state at ready",
		)
		_expect(
			item.is_point_in_shape(item.global_position),
			"the TV's middle lands on its Shape",
		)
		_expect(
			not item.is_point_in_shape(
				item.global_position + Vector2(0, -400)
			),
			"above the TV is off its Shape",
		)
		_expect(
			item.shadow_style == Repairable.ShadowStyle.FOOT_ELLIPSE,
			"the tall TV keeps its ellipse foot shadow",
		)
	var antenna := _find_point(item, BentPart) as BentPart
	_expect(is_instance_valid(antenna), "the TV has a bent antenna")
	if is_instance_valid(antenna):
		for hit in antenna.hits_to_straighten + 2:
			antenna.apply_hit(0.5, false)
		_expect(
			antenna.mode == InteractionPoint.Mode.FINISHED,
			"hammering the antenna straight finishes it",
		)
		var bent_art := antenna.get_node("AntennaBent") as CanvasItem
		var straight_art := (
			antenna.get_node("AntennaStraight") as CanvasItem
		)
		_expect(
			not bent_art.visible and straight_art.visible,
			"the bent antenna swaps to the straight sprite",
		)
		_expect(
			antenna.bench_dust_spew_count > 0,
			"whacking the TV spews bench dust",
		)
	var controls := _find_socket(item, Part.Type.TV_CONTROLS)
	_expect(is_instance_valid(controls), "the TV has a controls socket")
	if is_instance_valid(controls):
		_expect(
			_has_broken_sprite(controls),
			"the TV's bad controls sprite shows before the yank",
		)
		_expect_broken_art_matches(controls, "TV controls")
		controls._pop_out()
		await _seconds(0.6)
		var scene_part := (
			(load("res://src/parts/part.tscn") as PackedScene)
			.instantiate() as Part
		)
		_level.add_child(scene_part)
		scene_part.setup(Part.Type.TV_CONTROLS)
		await _physics_frames(2)
		controls.try_fit(scene_part)
		await _seconds(0.3)
		_expect(
			controls.mode == InteractionPoint.Mode.FINISHED,
			"good controls fit the TV",
		)
		var good := controls.get_node("GoodControls") as CanvasItem
		_expect(good.visible, "the good controls sprite shows")
	var whack := _find_point(item, StuckPart) as StuckPart
	_expect(is_instance_valid(whack), "the TV has a final whack")
	if is_instance_valid(whack):
		whack.apply_hit(0.5, false)
		_expect(
			whack.mode == InteractionPoint.Mode.FINISHED,
			"the final whack finishes its point",
		)
	if is_instance_valid(tv):
		_expect(tv.has_finished, "the worked TV finishes")
		await get_tree().create_timer(0.45).timeout
		_expect(
			tv.fixed_frames.has(tv.screen.texture),
			"the screen shows the fixed channel after the fix",
		)
		var fixed_frame := tv.screen.texture
		var alternated := false
		for _wait in 40:
			await get_tree().create_timer(0.05).timeout
			if tv.screen.texture != fixed_frame:
				alternated = tv.fixed_frames.has(tv.screen.texture)
				break
		_expect(
			alternated,
			"the fixed channel frames keep alternating",
		)
	item.queue_free()
	await _physics_frames(2)


func _check_keyboard() -> void:
	var item := _spawn(
		"res://src/repairables/keyboard_repairable.tscn"
	)
	if not _expect(is_instance_valid(item), "the keyboard loads"):
		return
	_expect(
		is_instance_valid(_find_socket(item, Part.Type.LETTER_KEY))
		and is_instance_valid(_find_socket(item, Part.Type.SPACEBAR)),
		"the keyboard has letter key and spacebar sockets",
	)
	var dust_count := 0
	for layer in item.layers:
		for point in layer.get_points():
			if point is DustClump:
				dust_count += 1
	_expect(dust_count >= 2, "the keyboard has dust to blow")
	item.queue_free()
	await _physics_frames(2)


func _check_piano() -> void:
	var item := _spawn("res://src/repairables/piano_repairable.tscn")
	if not _expect(is_instance_valid(item), "the piano loads"):
		return
	_expect(
		is_instance_valid(_find_socket(item, Part.Type.LED)),
		"the piano has an LED socket",
	)
	var has_broken := false
	var grime_count := 0
	for layer in item.layers:
		for point in layer.get_points():
			if point is BrokenPoint:
				has_broken = true
			if point is GrimeSpot:
				grime_count += 1
	_expect(has_broken, "the piano has a key to glue back on")
	_expect(grime_count >= 2, "the piano has grime to wipe")
	item.queue_free()
	await _physics_frames(2)


func _check_atari() -> void:
	var item := _spawn("res://src/repairables/atari_repairable.tscn")
	if not _expect(is_instance_valid(item), "the Atari loads"):
		return
	var screw: FlatHeadScrew = null
	for layer in item.layers:
		for point in layer.get_points():
			if point is FlatHeadScrew:
				screw = point as FlatHeadScrew
	_expect(
		is_instance_valid(screw),
		"the Atari is screwed on with a flathead screw",
	)
	_expect(
		is_instance_valid(_find_socket(item, Part.Type.JOYSTICK)),
		"the Atari has a joystick socket to yank and refit",
	)
	var socket := _find_socket(item, Part.Type.JOYSTICK)
	_expect(
		is_instance_valid(socket)
		and socket.locking_fastener == screw,
		"the Atari's tab screw locks its joystick socket",
	)
	_expect(
		is_instance_valid(socket) and _has_broken_sprite(socket),
		"the Atari's bent stick sprite shows before the yank",
	)
	item.queue_free()
	await _physics_frames(2)


func _check_game_n_watch() -> void:
	var item := _spawn(
		"res://src/repairables/game_n_watch_repairable.tscn"
	)
	if not _expect(is_instance_valid(item), "the Game n Watch loads"):
		return
	var phillips_count := 0
	var covered_count := 0
	var art_sized_hit_count := 0
	var covered_screw: PhillipsScrew = null
	for layer in item.layers:
		for point in layer.get_points():
			if point is PhillipsScrew:
				phillips_count += 1
				var screw := point as PhillipsScrew
				if not is_instance_valid(covered_screw):
					covered_screw = screw
				if is_instance_valid(screw.covering_grime):
					covered_count += 1
				var hit_radius := (
					(screw.hit_shape.shape as CircleShape2D).radius
					* screw.hit_shape.global_transform.get_scale().x
				)
				if hit_radius >= 24.0:
					art_sized_hit_count += 1
	_expect(
		phillips_count == 2,
		"the Game n Watch faceplate has two Phillips screws",
	)
	_expect(
		art_sized_hit_count == 2,
		"both Game n Watch screw hit circles match their heads",
	)
	_expect(
		covered_count == 2,
		"both Game n Watch screws start under grime",
	)
	var chip := _find_socket(item, Part.Type.CIRCUIT)
	_expect(
		is_instance_valid(chip),
		"the Game n Watch has a circuit socket to yank and refit",
	)
	_expect(
		is_instance_valid(chip) and _has_broken_sprite(chip),
		"the Game n Watch's bad chip sprite shows before the yank",
	)
	if is_instance_valid(chip):
		_expect_broken_art_matches(chip, "chip")
	_expect(
		Part.has_art(Part.Type.CIRCUIT),
		"the drawer circuit shows its real art",
	)
	var has_dpad := false
	var dust_count := 0
	var front_layer: RepairLayer = null
	for layer in item.layers:
		if layer.name == "Front":
			front_layer = layer
		for point in layer.get_points():
			if point is BrokenPoint:
				has_dpad = true
			if point is DustClump:
				dust_count += 1
	_expect(has_dpad, "the Game n Watch has a D-pad to glue back on")
	_expect(dust_count >= 2, "the Game n Watch has dirt to blow away")
	# Clear of the item under repair, so its points cannot
	# shadow this one's in the hand's searches.
	item.global_position = Vector2(380, 110)
	await _physics_frames(2)
	await _check_pulse_keeps_point_size(covered_screw)
	_check_gnw_dirt_is_bench_sized(covered_screw)
	await _check_gnw_phillips_engages(covered_screw)
	await _check_gnw_glue_smears(item, front_layer)
	item.queue_free()
	await _check_extra_dirt_offsets()
	await _physics_frames(2)


## The first dirt spot on a layer keeps its authored place;
## every one after it sits a random nudge away, within the
## nudge range, and the nudge varies from item to item.
func _check_extra_dirt_offsets() -> void:
	var first_positions: Array[Vector2] = []
	var extra_positions: Array[Vector2] = []
	for attempt in 4:
		var item := _spawn(
			"res://src/repairables/game_n_watch_repairable.tscn"
		)
		if not is_instance_valid(item):
			continue
		for layer in item.layers:
			var spots: Array[DirtSpot] = []
			for point in layer.get_points():
				if point is GrimeSpot or point is DustClump:
					spots.append(point as DirtSpot)
			if spots.size() >= 2 and layer.name == "Inside":
				first_positions.append(spots[0].position)
				extra_positions.append(spots[1].position)
		item.queue_free()
		await _physics_frames(2)
	var first_kept := first_positions.size() == 4
	for at in first_positions:
		first_kept = (
			first_kept and at.is_equal_approx(Vector2(-300, -250))
		)
	_expect(
		first_kept,
		"the first dust spot keeps its authored place",
	)
	var range_local := 18.0 / 0.13 + 1.0
	var extras_in_range := extra_positions.size() == 4
	for at in extra_positions:
		extras_in_range = (
			extras_in_range
			and at.distance_to(Vector2(350, 250)) <= range_local
		)
	_expect(
		extras_in_range,
		"extra dust spots sit within the nudge range",
	)
	var all_same := true
	for at in extra_positions:
		if not at.is_equal_approx(extra_positions[0]):
			all_same = false
	_expect(
		not all_same,
		"the extra spots' nudges vary from item to item",
	)


## A hint pulse on a point placed big on a scaled item
## grows it and gives it its authored scale back, instead of
## leaving it shrunk to 1.
func _check_pulse_keeps_point_size(point: InteractionPoint) -> void:
	if not _expect(
		is_instance_valid(point),
		"the Game n Watch point to pulse is there",
	):
		return
	var home_scale := point.scale
	point.pulse()
	await _seconds(0.6)
	_expect(
		point.scale.is_equal_approx(home_scale),
		"a pulse leaves the point at its authored size"
		+ " (scale %s, home %s)" % [point.scale, home_scale],
	)


## The grime on a scaled item still reads at bench size: its
## decal and its hit circle are world sizes, not a few pixels
## shrunk by the item's 0.13 authoring scale.
func _check_gnw_dirt_is_bench_sized(screw: PhillipsScrew) -> void:
	if not _expect(
		is_instance_valid(screw)
		and is_instance_valid(screw.covering_grime),
		"the Game n Watch grime to measure is on its screw",
	):
		return
	var grime := screw.covering_grime
	var world_size := Vector2.ZERO
	if is_instance_valid(grime.art) and grime.art.texture:
		world_size = (
			grime.art.get_global_transform().get_scale()
			* Vector2(grime.art.region_rect.size)
		)
	_expect(
		maxf(world_size.x, world_size.y) >= 20.0,
		"the Game n Watch grime decal is bench-sized"
		+ " (%.0f world px)" % maxf(world_size.x, world_size.y),
	)
	var hit_radius := 0.0
	for child in grime.get_children():
		if child is CollisionShape2D:
			var shape := (child as CollisionShape2D).shape
			if shape is CircleShape2D:
				hit_radius = (
					(shape as CircleShape2D).radius
					* (child as CollisionShape2D)
					.global_transform.get_scale().x
				)
	_expect(
		hit_radius >= 8.0,
		"the Game n Watch grime hit circle is bench-sized"
		+ " (%.0f world px)" % hit_radius,
	)
	_expect(
		grime._decal_sprites.size()
		== maxi(1, int(round(grime.amount))),
		"the Game n Watch grime renders its amount of decals"
		+ " (%d of %d)"
		% [grime._decal_sprites.size(), int(round(grime.amount))],
	)
	_expect(
		is_equal_approx(grime.hit_points_left, grime.toughness),
		"the grime takes its toughness of wiping, amount aside"
		+ " (%.2f of %.2f)"
		% [grime.hit_points_left, grime.toughness],
	)


## Squeezing the glue on blank Game n Watch front art leaves
## a smear point there.
func _check_gnw_glue_smears(
	item: Repairable, front: RepairLayer
) -> void:
	if not _expect(
		is_instance_valid(front), "the Game n Watch front to smear"
	):
		return
	var glue := G.level.tools_by_type[Tool.Type.GLUE] as Tool
	await _press_at(glue.global_position)
	if not _expect(_hand.held == glue, "the hand holds the glue"):
		return
	# Glue only smears on the item under repair, so the
	# spawned item stands in as the active one for the squeeze.
	var previous_item := G.level.active_repairable
	G.level.active_repairable = item
	await _seconds(1.0)
	var nozzle_offset: Vector2 = (
		glue.get_work_end_position() - glue.get_tip_position()
	)
	# Squeeze on blank front art until the squeeze starts;
	# a spot whose cursor lands on something else (a resting
	# screw, the rack) is spent on that instead, so try the
	# next one, the way a player would.
	var squeezed := false
	for blank_offset in [
		Vector2(30, -45),
		Vector2(-90, -30),
		Vector2(-20, 20),
	]:
		var blank: Vector2 = item.global_position + blank_offset
		await _press_down(blank - nozzle_offset)
		if glue._is_squeezing:
			squeezed = true
			await _seconds(0.9)
			await _release_at(blank - nozzle_offset)
			break
		await _release_at(blank - nozzle_offset)
	_expect(squeezed, "the glue squeeze starts on the front")
	await _physics_frames(4)
	var smear: GlueSmear = null
	for point in front.get_points():
		if point is GlueSmear:
			smear = point as GlueSmear
	_expect(
		is_instance_valid(smear),
		"glue smears on the Game n Watch front art",
	)
	G.level.active_repairable = previous_item
	glue.put_away()
	await _physics_frames(2)


## With the grime off, the Phillips driver engages the Game
## n Watch screw it overlaps: dead centre first (where the
## cleaned grime still sits on the screw), then with the
## driver's face beside the head, overlapping its area.
func _check_gnw_phillips_engages(screw: PhillipsScrew) -> void:
	if not _expect(
		is_instance_valid(screw)
		and is_instance_valid(screw.covering_grime),
		"the Game n Watch screw to drive is under grime",
	):
		return
	var driver := G.level.tools_by_type[
		Tool.Type.PHILLIPS_SCREW_DRIVER
	] as PhillipsScrewDriver
	await _grab_tool(driver)
	_expect(_hand.held == driver, "the hand holds the phillips driver")
	screw.covering_grime.finish()
	await _physics_frames(2)
	await _press_tool_at(driver, screw.global_position)
	_expect(
		screw.mode == InteractionPoint.Mode.ACTIVE,
		"a centre press engages the Game n Watch screw"
		+ " under its cleaned grime (mode %d)" % screw.mode,
	)
	if screw.mode == InteractionPoint.Mode.ACTIVE:
		screw.release_tool()
		screw.mode = InteractionPoint.Mode.UNSTARTED
		await _physics_frames(2)
	var hit_radius := (
		(screw.hit_shape.shape as CircleShape2D).radius
		* screw.hit_shape.global_transform.get_scale().x
	)
	var driver_shape := driver.get_interaction_shape()
	var driver_radius := (
		(driver_shape.shape as CircleShape2D).radius
		* driver_shape.global_transform.get_scale().x
	)
	var edge_point := (
		screw.global_position
		+ Vector2(hit_radius + driver_radius - 6.0, 0.0)
	)
	await _press_tool_at(driver, edge_point)
	_expect(
		screw.mode == InteractionPoint.Mode.ACTIVE,
		"an edge press engages the Game n Watch screw"
		+ " (mode %d)" % screw.mode,
	)
	if screw.mode == InteractionPoint.Mode.ACTIVE:
		screw.release_tool()
		screw.mode = InteractionPoint.Mode.UNSTARTED
		await _physics_frames(2)
	driver.put_away()
	await _physics_frames(2)


func _check_placeholders() -> void:
	for scene_path in [
		"res://src/repairables/radio_repairable.tscn",
		"res://src/repairables/toaster.tscn",
		"res://src/repairables/shrink_ray_repairable.tscn",
	]:
		var item := _spawn(scene_path)
		if not _expect(
			is_instance_valid(item), "placeholder loads: " + scene_path
		):
			continue
		_expect(
			is_instance_valid(_find_point(item, StuckPart)),
			"placeholder has a whack: " + scene_path,
		)
		item.queue_free()
		await _physics_frames(2)


## The radio item sits at a small root scale, so its front
## must keep that world size when it leaves the item: it
## reparents to the unscaled set-aside spot.
func _check_radio_front_size() -> void:
	var item := _spawn("res://src/repairables/radio_repairable.tscn")
	if not _expect(is_instance_valid(item), "the radio loads again"):
		return
	var front: RepairLayer
	for layer in item.layers:
		if layer.name == "Front":
			front = layer
	if not _expect(
		is_instance_valid(front), "the radio has a front layer"
	):
		item.queue_free()
		return
	for fastener in front.get_fasteners():
		(fastener as Screw).remove()
	for frame in 600:
		if front.is_loose():
			break
		await get_tree().physics_frame
	_expect(front.is_loose(), "the front's screws come out")
	var size_before := front.global_scale
	front.take_off_for_drag()
	_expect(
		front.global_scale.is_equal_approx(size_before),
		"the radio front keeps its size when taken off (was %s, now %s)"
		% [size_before, front.global_scale],
	)
	front.queue_free()
	item.queue_free()
	await _physics_frames(2)


## The socket's broken part sprite, or null.
func _get_broken_sprite(socket: PartSocket) -> Sprite2D:
	var broken := socket.get_node("BrokenPart")
	for child in broken.get_children():
		if child is Sprite2D and (child as CanvasItem).visible:
			return child as Sprite2D
	return null


## The auto-made broken art must cover the same world
## footprint as the fitted art: on a scaled item it once
## shrank to a postage stamp beside its panel (the TV's bad
## controls, the Game n Watch's bad chip).
func _expect_broken_art_matches(
	socket: PartSocket, name: String
) -> void:
	var broken_sprite := _get_broken_sprite(socket)
	var fitted := socket.installed_art as Sprite2D
	if not _expect(
		is_instance_valid(broken_sprite)
		and is_instance_valid(fitted),
		"the %s has broken and fitted sprites" % name,
	):
		return
	var broken_size := (
		broken_sprite.get_rect().size
		* broken_sprite.global_transform.get_scale().abs()
	)
	var fitted_size := (
		fitted.get_rect().size
		* fitted.global_transform.get_scale().abs()
	)
	_expect(
		absf(broken_size.x - fitted_size.x) < 1.0
		and absf(broken_size.y - fitted_size.y) < 1.0,
		"the %s broken art matches the fitted size"
		% name
		+ " (broken %s, fitted %s)" % [broken_size, fitted_size],
	)


## True when the socket's broken part carries a real sprite
## (not just the placeholder polygon the socket ships with).
func _has_broken_sprite(socket: PartSocket) -> bool:
	var broken := socket.get_node("BrokenPart")
	for child in broken.get_children():
		if child is Sprite2D and (child as CanvasItem).visible:
			return true
	return false


func _spawn(scene_path: String) -> Repairable:
	var item := (
		(load(scene_path) as PackedScene).instantiate() as Repairable
	)
	if not is_instance_valid(item):
		return null
	_level.add_child(item)
	item.mode = Repairable.Mode.UNDER_REPAIR
	item.global_position = Vector2(0, 180)
	return item


func _find_point(item: Repairable, kind: Variant) -> InteractionPoint:
	var wanted := kind as Script
	for layer in item.layers:
		for point in layer.get_points():
			var script := point.get_script() as Script
			while is_instance_valid(script):
				if script == wanted:
					return point
				script = script.get_base_script()
	return null


func _find_socket(
	item: Repairable, part_type: Part.Type
) -> PartSocket:
	for layer in item.layers:
		for point in layer.get_points():
			var socket := point as PartSocket
			if is_instance_valid(socket) and socket.accepted_part == part_type:
				return socket
	return null

