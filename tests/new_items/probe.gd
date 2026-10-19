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
		"the first-repairable override puts the TV first",
	)
	G.settings.first_repairable_override = Settings.FirstRepairable.NONE
	await _check_tv()
	await _check_keyboard()
	await _check_piano()
	await _check_atari()
	await _check_game_n_watch()
	await _check_placeholders()
	_finish(0 if _failures.is_empty() else 1)


func _check_tv() -> void:
	var item := _spawn("res://src/repairables/tv_repairable.tscn")
	if not _expect(is_instance_valid(item), "the TV loads"):
		return
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
	for layer in item.layers:
		for point in layer.get_points():
			if point is PhillipsScrew:
				phillips_count += 1
				var screw := point as PhillipsScrew
				if is_instance_valid(screw.covering_grime):
					covered_count += 1
	_expect(
		phillips_count == 2,
		"the Game n Watch faceplate has two Phillips screws",
	)
	_expect(
		covered_count == 2,
		"both Game n Watch screws start under grime",
	)
	_expect(
		is_instance_valid(_find_socket(item, Part.Type.CIRCUIT)),
		"the Game n Watch has a circuit socket to yank and refit",
	)
	_expect(
		Part.has_art(Part.Type.CIRCUIT),
		"the drawer circuit shows its real art",
	)
	var has_dpad := false
	var dust_count := 0
	for layer in item.layers:
		for point in layer.get_points():
			if point is BrokenPoint:
				has_dpad = true
			if point is DustClump:
				dust_count += 1
	_expect(has_dpad, "the Game n Watch has a D-pad to glue back on")
	_expect(dust_count >= 2, "the Game n Watch has dirt to blow away")
	item.queue_free()
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

