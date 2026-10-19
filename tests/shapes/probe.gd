extends "res://tests/probe_base.gd"
## Authored Shape outlines for parts and layers. Boots the
## game, then checks every dedicated part scene and every
## repairable layer: the Shape is assigned, stripped of live
## physics at ready, tested by hand, and its world polygon
## gives the part's radius. The shared `part.tscn` still
## sets its kind and art by hand.
##
## Run it with `tests/run.ps1 -Name shapes`, or from the
## repo root (PowerShell):
##   godot --headless --path . res://tests/shapes/probe.tscn


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

const _PART_SCENE_PATHS := {
	Part.Type.GEAR: "res://src/parts/gear_part.tscn",
	Part.Type.TUBE: "res://src/parts/tube_part.tscn",
	Part.Type.TV_CONTROLS: "res://src/parts/tv_controls_part.tscn",
	Part.Type.LETTER_KEY: "res://src/parts/letter_key_part.tscn",
	Part.Type.SPACEBAR: "res://src/parts/spacebar_part.tscn",
	Part.Type.LED: "res://src/parts/led_part.tscn",
	Part.Type.JOYSTICK: "res://src/parts/joystick_part.tscn",
	Part.Type.CIRCUIT: "res://src/parts/circuit_part.tscn",
	Part.Type.CRYSTAL: "res://src/parts/crystal_part.tscn",
	Part.Type.BOLT: "res://src/parts/bolt_part.tscn",
	Part.Type.NUT: "res://src/parts/nut_part.tscn",
}

const _REPAIRABLE_SCENE_PATHS: Array[String] = [
	"res://src/repairables/atari_repairable.tscn",
	"res://src/repairables/game_n_watch_repairable.tscn",
	"res://src/repairables/keyboard_repairable.tscn",
	"res://src/repairables/piano_repairable.tscn",
	"res://src/repairables/radio_repairable.tscn",
	"res://src/repairables/shrink_ray_repairable.tscn",
	"res://src/repairables/test_flat_head_screw_repairable.tscn",
	"res://src/repairables/test_phillips_repairable.tscn",
	"res://src/repairables/toaster.tscn",
	"res://src/repairables/tv_repairable.tscn",
]

var _level: Level


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
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_level = G.level
	_hand = _level.hand
	await _check_dedicated_parts()
	_check_settings_map()
	_check_live_drawer_parts()
	await _check_shared_part()
	await _check_layers()
	await _check_authored_shapes()


func _check_dedicated_parts() -> void:
	for part_type_value in Part.Type.values():
		var part_type := part_type_value as Part.Type
		var name := Part.get_display_name(part_type)
		var scene := load(
			_PART_SCENE_PATHS[part_type]
		) as PackedScene
		if not _expect(
			is_instance_valid(scene), "the %s scene loads" % name
		):
			continue
		var part := scene.instantiate() as Part
		if not _expect(
			is_instance_valid(part), "the %s scene is a part" % name
		):
			continue
		_level.add_child(part)
		part.global_position = Vector2(0.0, 120.0)
		await _physics_frames(2)
		_expect(part.type == part_type, "the %s scene sets its kind" % name)
		_check_part_shape(part, name)
		part.queue_free()
		await _physics_frames(1)


func _check_settings_map() -> void:
	for part_type_value in Part.Type.values():
		var part_type := part_type_value as Part.Type
		var name := Part.get_display_name(part_type)
		var scene := G.settings.get_part_scene_from_type(part_type)
		_expect(
			is_instance_valid(scene)
			and scene.resource_path == _PART_SCENE_PATHS[part_type],
			"settings maps %s to its dedicated scene" % name,
		)


func _check_live_drawer_parts() -> void:
	var parts := _level.get_drawer_parts()
	_expect(not parts.is_empty(), "the drawers are stocked")
	for part in parts:
		_check_part_shape(
			part, Part.get_display_name(part.type)
		)


func _check_shared_part() -> void:
	var part := (
		load("res://src/parts/part.tscn") as PackedScene
	).instantiate() as Part
	if not _expect(is_instance_valid(part), "the shared part scene loads"):
		return
	_level.add_child(part)
	part.setup(Part.Type.TV_CONTROLS)
	part.global_position = Vector2(120.0, 120.0)
	await _physics_frames(2)
	_expect(
		part.type == Part.Type.TV_CONTROLS,
		"the shared part still takes its kind from setup",
	)
	var sprite := part.get_node("%Sprite") as Sprite2D
	_expect(
		sprite.visible and part.get_radius_px() > 0.0,
		"the shared part still shows art and has a radius",
	)
	part.queue_free()
	await _physics_frames(1)


func _check_layers() -> void:
	var layer_count := 0
	for scene_path in _REPAIRABLE_SCENE_PATHS:
		var item := (
			load(scene_path) as PackedScene
		).instantiate() as Repairable
		if not _expect(
			is_instance_valid(item), "layer item loads: " + scene_path
		):
			continue
		_level.add_child(item)
		item.mode = Repairable.Mode.UNDER_REPAIR
		item.global_position = Vector2(0.0, 180.0)
		await _physics_frames(2)
		for layer in item.layers:
			layer_count += 1
			var label := "%s %s" % [
				scene_path.get_file(), layer.name,
			]
			_expect(
				is_instance_valid(layer.shape),
				"the layer has a Shape: " + label,
			)
			if not is_instance_valid(layer.shape):
				continue
			_expect(
				layer.shape.collision_layer == 0
				and layer.shape.collision_mask == 0
				and not layer.shape.monitoring
				and not layer.shape.monitorable,
				"the layer Shape carries no live physics: " + label,
			)
			var points := layer.get_shape_world_polygon()
			_expect(
				points.size() >= 3,
				"the layer Shape has a polygon: " + label,
			)
			if points.size() < 3:
				continue
			var centre := _polygon_centre(points)
			_expect(
				layer.is_point_in_shape(centre),
				"the layer Shape holds its middle: " + label,
			)
			_expect(
				layer.has_point(centre),
				"the layer press test uses its Shape: " + label,
			)
			_expect(
				not layer.is_point_in_shape(
					centre + Vector2(10000.0, 0.0)
				),
				"far from the layer is off its Shape: " + label,
			)
		item.queue_free()
		await _physics_frames(1)
	_expect(layer_count == 14, "every repairable layer was checked")


## The authored Shapes beyond parts and layers: the TV
## antenna's BentPart shape, the piano key's BrokenPiece shape
## and the Atari socket's good and bad part shapes.
func _check_authored_shapes() -> void:
	var tv := _spawn_item("res://src/repairables/tv_repairable.tscn")
	if is_instance_valid(tv):
		var antenna: BentPart
		for layer in tv.layers:
			for point in layer.get_points():
				if point is BentPart:
					antenna = point as BentPart
		if _expect(
			is_instance_valid(antenna), "the TV has an antenna point"
		):
			_check_point_shape(antenna, "antenna")
			var far_point := _farthest_point(
				antenna.get_shape_world_polygon(),
				antenna.global_position,
			)
			_expect(
				far_point.distance_to(antenna.global_position) > 8.0,
				"the antenna Shape reaches past its small circle",
			)
		var controls: PartSocket
		for layer in tv.layers:
			for point in layer.get_points():
				if point is PartSocket:
					controls = point as PartSocket
		if _expect(
			is_instance_valid(controls),
			"the TV has a controls socket",
		):
			var bad_points := controls.get_bad_part_world_polygon()
			_expect(
				bad_points.size() >= 3
				and controls.get_good_part_world_polygon().size()
				>= 3,
				"the controls socket carries good and bad shapes",
			)
			if bad_points.size() >= 3:
				var far_point := _farthest_point(
					bad_points, controls.global_position
				)
				_expect(
					controls.is_point_in_bad_part_shape(far_point)
					and far_point.distance_to(
						controls.global_position
					) > 10.0,
					"the bad controls grab past the socket's circle",
				)
		tv.queue_free()
		await _physics_frames(1)
	var piano := _spawn_item(
		"res://src/repairables/piano_repairable.tscn"
	)
	if is_instance_valid(piano):
		var key: BrokenPiece
		for piece in piano.get_broken_pieces():
			if is_instance_valid(piece.shape):
				key = piece
		if _expect(
			is_instance_valid(key), "the piano key has a Shape"
		):
			_expect(
				key.shape.collision_layer == 0
				and key.shape.collision_mask == 0
				and not key.shape.monitoring
				and not key.shape.monitorable,
				"the key Shape carries no live physics",
			)
			var points := key.get_shape_world_polygon()
			_expect(
				points.size() >= 3, "the key Shape has a polygon"
			)
			if points.size() >= 3:
				_expect(
					key.is_point_in_shape(_polygon_centre(points)),
					"the key Shape holds its middle",
				)
				var expected_radius := 0.0
				for point in points:
					expected_radius = maxf(
						expected_radius,
						point.distance_to(key.global_position),
					)
				_expect(
					absf(key.get_radius_px() - expected_radius) < 0.5,
					"the key's radius comes from its Shape",
				)
		piano.queue_free()
		await _physics_frames(1)
	var atari := _spawn_item(
		"res://src/repairables/atari_repairable.tscn"
	)
	if is_instance_valid(atari):
		var socket: PartSocket
		for layer in atari.layers:
			for point in layer.get_points():
				if point is PartSocket:
					socket = point as PartSocket
		if _expect(
			is_instance_valid(socket), "the Atari has a socket"
		):
			var bad_points := socket.get_bad_part_world_polygon()
			var good_points := socket.get_good_part_world_polygon()
			_expect(
				bad_points.size() >= 3,
				"the socket has a bad part shape",
			)
			_expect(
				good_points.size() >= 3,
				"the socket has a good part shape",
			)
			if bad_points.size() >= 3:
				var far_point := _farthest_point(
					bad_points, socket.global_position
				)
				_expect(
					socket.is_point_in_bad_part_shape(far_point)
					and far_point.distance_to(
						socket.global_position
					) > 22.0,
					"the broken stick is grabbable past the circle",
				)
				_expect(
					not socket.is_point_in_bad_part_shape(
						socket.global_position + Vector2(0.0, 500.0)
					),
					"below the stick is off its bad part shape",
				)
		atari.queue_free()
		await _physics_frames(1)


func _check_point_shape(point: InteractionPoint, name: String) -> void:
	_expect(
		is_instance_valid(point.shape),
		"the %s point has a Shape" % name,
	)
	if not is_instance_valid(point.shape):
		return
	_expect(
		point.shape.collision_layer == 0
		and point.shape.collision_mask == 0
		and not point.shape.monitoring
		and not point.shape.monitorable,
		"the %s Shape carries no live physics" % name,
	)
	var points := point.get_shape_world_polygon()
	_expect(
		points.size() >= 3, "the %s Shape has a polygon" % name
	)
	if points.size() < 3:
		return
	_expect(
		point.is_point_in_shape(_polygon_centre(points)),
		"the %s Shape holds its middle" % name,
	)
	_expect(
		not point.is_point_in_shape(
			point.global_position + Vector2(10000.0, 0.0)
		),
		"far from the %s is off its Shape" % name,
	)


func _spawn_item(scene_path: String) -> Repairable:
	var item := (
		(load(scene_path) as PackedScene).instantiate() as Repairable
	)
	if not is_instance_valid(item):
		_expect(false, "authored-shape item loads: " + scene_path)
		return null
	_level.add_child(item)
	item.mode = Repairable.Mode.UNDER_REPAIR
	item.global_position = Vector2(0.0, 180.0)
	return item


func _farthest_point(
	points: PackedVector2Array, from_point: Vector2
) -> Vector2:
	var farthest := from_point
	for point in points:
		if (
			point.distance_squared_to(from_point)
			> farthest.distance_squared_to(from_point)
		):
			farthest = point
	return farthest


func _check_part_shape(part: Part, name: String) -> void:
	_expect(
		is_instance_valid(part.shape),
		"the %s part has a Shape" % name,
	)
	if not is_instance_valid(part.shape):
		return
	_expect(
		part.shape.collision_layer == 0
		and part.shape.collision_mask == 0
		and not part.shape.monitoring
		and not part.shape.monitorable,
		"the %s Shape carries no live physics" % name,
	)
	var points := part.get_shape_world_polygon()
	_expect(
		points.size() >= 3, "the %s Shape has a polygon" % name
	)
	if points.size() < 3:
		return
	_expect(
		part.is_point_in_shape(_polygon_centre(points)),
		"the %s Shape holds its middle" % name,
	)
	_expect(
		not part.is_point_in_shape(
			part.global_position + Vector2(10000.0, 0.0)
		),
		"far from the %s part is off its Shape" % name,
	)
	var expected_radius := 0.0
	for point in points:
		expected_radius = maxf(
			expected_radius,
			point.distance_to(part.global_position),
		)
	_expect(
		absf(part.get_radius_px() - expected_radius) < 0.5,
		"the %s radius comes from its Shape" % name,
	)


func _polygon_centre(points: PackedVector2Array) -> Vector2:
	var centre := Vector2.ZERO
	for point in points:
		centre += point
	return centre / points.size()
