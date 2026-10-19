extends "res://tests/probe_base.gd"
## The Game n Watch's glue target (its D-pad point) has to
## show the glue dab on its pale faceplate: the dab spawns on
## the layer art, clipped to the layer Shape, at a world size
## and amber tint that read at a glance. The piece falls aside
## first, the way it does when the item lands in real play.


func _ready() -> void:
	_is_taking_screenshots = OS.get_cmdline_user_args().has(
		"--screenshots"
	)
	_start_timeout(60.0)
	_run.call_deferred()


func _run() -> void:
	var main := (
		(load("res://src/core/main.tscn") as PackedScene)
		.instantiate()
	)
	add_child(main)
	await _physics_frames(4)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	var item := (
		(load(
			"res://src/repairables/game_n_watch_repairable.tscn"
		) as PackedScene).instantiate() as Repairable
	)
	G.level.add_child(item)
	item.mode = Repairable.Mode.UNDER_REPAIR
	item.global_position = Vector2(0, 180)
	await _physics_frames(4)
	var broken: BrokenPoint = null
	for layer in item.layers:
		for point in layer.get_points():
			if point is BrokenPoint:
				broken = point as BrokenPoint
	if not _expect(
		is_instance_valid(broken), "the Game n Watch has a glue target"
	):
		_finish(1)
		return
	if is_instance_valid(broken.piece):
		broken.piece.detach_for_fall(
			item.global_position + broken.piece.fall_target_offset
		)
		await _physics_frames(30)
	_expect(
		broken.on_glued(broken.global_position, 30.0, 1.0)
		and broken.has_glue,
		"glue lands on the Game n Watch D-pad point",
	)
	await _physics_frames(4)
	await _shot("glued")
	var decal: Sprite2D = broken.glue_decal
	if not _expect(
		is_instance_valid(decal)
		and is_instance_valid(decal.texture)
		and decal.is_visible_in_tree(),
		"the glue dab shows on the faceplate",
	):
		_finish(1)
		return
	var world_size := Vector2(
		absf(decal.global_transform.get_scale().x)
		* decal.region_rect.size.x,
		absf(decal.global_transform.get_scale().y)
		* decal.region_rect.size.y,
	)
	_expect(
		world_size.x >= 64.0 and world_size.y >= 64.0,
		"the glue dab is a readable size (%.0fx%.0f world px)"
		% [world_size.x, world_size.y],
	)
	_expect(
		decal.global_position.distance_to(broken.global_position)
		< 1.0,
		"the glue dab sits on the point",
	)
	var shape_polygon := broken.get_layer().get_shape_world_polygon()
	_expect(
		shape_polygon.size() < 3
		or Geometry2D.is_point_in_polygon(
			decal.global_position, shape_polygon
		),
		"the glue dab lands inside the layer Shape",
	)
	_finish(0 if _failures.is_empty() else 1)
