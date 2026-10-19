extends "res://tests/probe_base.gd"
## Loose pieces on the bench: a screw comes out twice as far, rests
## where it lands instead of sliding to a row, and screws and the
## cover are dragged around the bench by hand. Nothing moves by
## itself. A screw may be dragged outside the workable area, and
## a drop out there flies back in and rests inside it. The cover
## is dragged the same way (but a drawer never takes it), it turns
## by a slight angle as it comes off and straightens when grabbed
## to go back on, and a piece dropped close to home at the right
## step seats itself.
##
## Run it with `tests/run.ps1 -Name bench_drag`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/bench_drag/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0

var _level: Level
var _tool: FlatHeadScrewDriver
var _item: Repairable
var _cover: RepairLayer
var _screw: FlatHeadScrew


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
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
	_collect_nodes()
	await _grab_tool(_tool)
	await _seconds(0.4)
	if not _expect(_hand.held == _tool, "take the flathead driver"):
		return
	_expect(
		is_instance_valid(_find_shadow(_item))
		and _find_shadow(_item).visible,
		"the item on the bench has a drop shadow",
	)
	_expect(
		is_instance_valid(_find_shadow(_tool))
		and not _find_shadow(_tool).visible,
		"a held tool has no drop shadow",
	)
	_expect(
		_screw.get_slide_height_px() > 10.0
		and _screw.get_slide_height_px() < 14.0,
		"the unscrewed head rises about 12 px, twice as far as before"
		+ " (%.2f px)" % _screw.get_slide_height_px(),
	)
	await _drive_screw_out()
	await _check_screw_rest_and_drag()
	await _check_off_bench_drop()
	await _check_cover_drag()


func _collect_nodes() -> void:
	_level = G.level
	_hand = _level.hand
	_tool = (
		_level.tools_by_type[Tool.Type.FLAT_HEAD_SCREW_DRIVER]
		as FlatHeadScrewDriver
	)
	_item = _level.active_repairable
	_cover = _item.get_node("Layers/Cover")
	_screw = _cover.get_node("ScrewLeft")
	# ScrewLeft starts under grime; this probe starts cleaned
	# (the grime_screw probe covers working it).
	if _screw.is_covered():
		_screw.covering_grime.finish()


## Turns the flathead screw out, recentering the tip every frame.
## The press goes by the driver's working end, the way a press
## engages a point, not by the cursor tip.
func _drive_screw_out() -> void:
	await _press_tool_at(_tool, _screw.global_position)
	_expect(
		_screw.mode == InteractionPoint.Mode.ACTIVE,
		"the driver engages the screw",
	)
	for frame in 1200:
		if _screw.travel == Screw.Travel.RESTING:
			return
		var motion := InputEventMouseMotion.new()
		_push_mouse(
			motion,
			_hand.pointer_position
			- _screw.get_slot_axis() * _screw.tip_offset_px,
		)
		await get_tree().physics_frame
	_expect(false, "the screw comes out and rests on the bench")


func _check_screw_rest_and_drag() -> void:
	_expect(
		_screw.travel == Screw.Travel.RESTING,
		"the screw rests on the bench once it is out",
	)
	var landed_position := _screw.bench_art.global_position
	await _seconds(0.7)
	_expect(
		_screw.bench_art.global_position.distance_to(landed_position)
		< 1.0,
		"the screw does not roll when the unscrew microgame finishes"
		+ " (moved %.1f px)"
		% _screw.bench_art.global_position.distance_to(
			landed_position,
		),
	)
	# Loose pieces are dragged empty handed: the driver goes back.
	await _put_tool_away(_tool)
	await _seconds(0.4)
	_expect(_hand.is_empty(), "the driver goes back on its rack")
	await _move_to(
		_screw.bench_art.global_position + _screw.rest_hit_offset
	)
	_expect_cursor(
		Input.MOUSE_MODE_VISIBLE,
		Input.CURSOR_POINTING_HAND,
		"the open hand shows over a resting screw",
	)
	var rest_position := _screw.bench_art.global_position
	_expect(
		rest_position.distance_to(_screw.global_position) < 90.0,
		"the screw rests where it landed, by its hole (%.0f px away)"
		% rest_position.distance_to(_screw.global_position),
	)
	_expect(
		rest_position.distance_to(_level.get_screw_rest_position(0))
		> 40.0,
		"the screw did not slide off to the rest row by itself",
	)
	var screw_shadow := _find_shadow(_screw.bench_art)
	_expect(
		is_instance_valid(screw_shadow)
		and screw_shadow.visible
		and screw_shadow._fade > 0.9
		and screw_shadow.get_copy_count() > 0,
		"a resting screw's silhouette shadow has faded in"
		+ " (%d copies)" % screw_shadow.get_copy_count(),
	)
	_expect(
		is_instance_valid(screw_shadow)
		and screw_shadow.size_scale < 1.0,
		"a resting screw's shadow is drawn smaller than the screw"
		+ " (%.0f%%)" % (screw_shadow.size_scale * 100.0),
	)
	_expect(
		is_instance_valid(screw_shadow)
		and screw_shadow.get_copy_count() == 1,
		"a resting screw casts a single shadow, not two",
	)
	await _check_shadow_turns_with(
		screw_shadow,
		_screw.bench_art,
		"a resting screw",
	)
	# Drag it across the bench and let go.
	var middle := rest_position + _screw.rest_hit_offset
	var rotation_before := _screw.bench_art.rotation
	await _press_down(middle)
	var out_fades := await _sample_shadow_fades(
		screw_shadow,
		func() -> bool: return screw_shadow._fade <= 0.01,
	)
	_expect(
		not screw_shadow.visible and _is_smooth_fade(out_fades, false),
		"a carried screw's drop shadow fades out smoothly"
		+ " (%d frames)" % out_fades.size(),
	)
	_expect(
		absf(
			wrapf(
				_screw.bench_art.rotation - rotation_before,
				-PI,
				PI,
			),
		) <= PI / 4.0 + 0.02,
		"picking the screw up turns it within 45 degrees"
		+ " (turned %.1f deg)"
		% rad_to_deg(_screw.bench_art.rotation - rotation_before),
	)
	await _move_to(Vector2(200.0, 260.0))
	await _release_at(Vector2(200.0, 260.0))
	_expect(
		_screw.bench_art.global_position.distance_to(
			Vector2(200.0, 250.0),
		) < 16.0,
		"the dragged screw stays where it was dropped (at %s)"
		% _screw.bench_art.global_position,
	)
	_expect(
		_screw.travel == Screw.Travel.RESTING,
		"the dropped screw is still resting, not seated",
	)
	var dropped_position := _screw.bench_art.global_position
	var head_start := _screw.bench_art.to_global(Screw._HEAD_LOCAL)
	var tip_start := _screw.bench_art.to_global(Screw._TIP_LOCAL)
	var in_fades := await _sample_shadow_fades(
		screw_shadow,
		func() -> bool: return screw_shadow._fade >= 0.99,
	)
	_expect(
		screw_shadow.visible and _is_smooth_fade(in_fades, true),
		"a set-down screw's drop shadow fades in smoothly"
		+ " (%d frames)" % in_fades.size(),
	)
	await _seconds(0.7)
	_expect(
		_screw.bench_art.global_position.distance_to(dropped_position)
		> 2.0
		and _screw.travel == Screw.Travel.RESTING,
		"set down after a drag, the screw rolls a little"
		+ " (moved %.1f px)"
		% _screw.bench_art.global_position.distance_to(
			dropped_position,
		),
	)
	var head_travel := head_start.distance_to(
		_screw.bench_art.to_global(Screw._HEAD_LOCAL)
	)
	var tip_travel := tip_start.distance_to(
		_screw.bench_art.to_global(Screw._TIP_LOCAL)
	)
	_expect(
		head_travel > 6.0 and head_travel > tip_travel * 1.4,
		"the roll turns about the cone's apex past the tip"
		+ " (head %.1f px, tip %.1f px)" % [head_travel, tip_travel],
	)


func _check_off_bench_drop() -> void:
	var middle := (
		_screw.bench_art.global_position + _screw.rest_hit_offset
	)
	await _press_down(middle)
	await _move_to(Vector2(-700.0, 260.0))
	var carried := _screw.bench_art.global_position
	_expect(
		carried.x < -625.0,
		"a screw may be carried outside the workable area"
		+ " (carried to %s)" % carried,
	)
	await _release_at(Vector2(-700.0, 260.0))
	_expect(
		_screw.is_returning,
		"a screw dropped outside the workable area is on its way back",
	)
	var is_back := false
	for frame in 300:
		if not _screw.is_returning:
			is_back = true
			break
		await get_tree().physics_frame
	_expect(
		is_back,
		"the returned screw comes to rest instead of flying forever",
	)
	var rested := (
		_screw.bench_art.global_position + _screw.rest_hit_offset
	)
	_expect(
		_level.is_inside_workable_area(
			rested,
			_screw.get_rest_radius_px()
			+ G.settings.workable_edge_padding_px,
		),
		"the returned screw rests inside the workable area"
		+ " (at %s)" % rested,
	)
	await _move_to(Vector2(0.0, 200.0))
	_expect(
		_screw.bench_art.global_position.distance_to(
			rested - _screw.rest_hit_offset,
		) < 1.0,
		"the returned screw no longer follows the pointer",
	)


func _check_cover_drag() -> void:
	# The other screw comes out the way its microgame ends it, so
	# the cover is loose. It must still be sitting on the item.
	var right := _cover.get_node("ScrewRight") as Screw
	right.remove()
	for frame in 240:
		if right.travel == Screw.Travel.RESTING:
			break
		await get_tree().physics_frame
	_expect(
		_cover.is_on and _cover.is_loose(),
		"with both screws out the cover is loose but still on",
	)
	await _seconds(0.6)
	_expect(
		_cover.is_on,
		"the loose cover does not lift off by itself",
	)
	# Drag the cover off by a clear patch of its art.
	var grab_point := _find_cover_grab_point()
	if not _expect(
		grab_point != Vector2.INF,
		"found a clear patch of cover to grab",
	):
		return
	var home_rotation := _cover.global_rotation
	await _press_down(grab_point)
	await _move_to(Vector2(360.0, 60.0))
	await _release_at(Vector2(360.0, 60.0))
	_expect(
		not _cover.is_on,
		"dragging the loose cover takes it off the item",
	)
	await _seconds(0.6)
	_expect(
		absf(
			wrapf(
				_cover.global_rotation - home_rotation, -PI, PI
			),
		) <= deg_to_rad(20.0) + 0.01,
		"dragged off, the cover turns by a slight angle"
		+ " (turned %.1f deg)"
		% rad_to_deg(_cover.global_rotation - home_rotation),
	)
	await _check_shadow_turns_with(
		_find_shadow(_cover),
		_cover,
		"a loose cover",
	)
	# Dropping it by its home before the inside is done seats
	# nothing: it just rests there.
	await _press_down(_cover.global_position)
	await _move_to(_cover.get_home_global_position())
	await _release_at(_cover.get_home_global_position())
	await _seconds(0.6)
	_expect(
		not _cover.is_on,
		"the cover stays loose until the work under it is done",
	)
	# A drawer never takes it: carried over one and let go, it
	# flies back to the bench like any drop outside the workable
	# area, instead of going inside.
	var drawer := _level.get_drawers()[1]
	await _press_down(_cover.global_position)
	await _move_to(drawer.global_position)
	_expect(
		_cover.global_position.distance_to(drawer.global_position)
		< 60.0,
		"the cover may be carried over a drawer"
		+ " (carried to %s)" % _cover.global_position,
	)
	await _release_at(drawer.global_position)
	_expect(
		_cover.is_returning and _cover.visible,
		"dropped over a drawer, the cover flies back out of it",
	)
	var is_back := false
	for frame in 300:
		if not _cover.is_returning:
			is_back = true
			break
		await get_tree().physics_frame
	_expect(
		is_back,
		"the cover comes to rest after flying back from the drawer",
	)
	# Too big for any spot to keep its whole art inside, so the
	# guarantee is its middle back on the bench, still loose.
	_expect(
		not _cover.is_on
		and _level.is_inside_workable_area(_cover.global_position),
		"the cover rests loose inside the workable area"
		+ " (at %s)" % _cover.global_position,
	)
	# Finish the inside directly, the way the parts probe finishes
	# its socket, then drop the cover home and the screw in.
	for layer in _item.layers:
		for point in layer.get_points():
			if (
				point != _screw
				and point.mode != InteractionPoint.Mode.FINISHED
				and point.role != InteractionPoint.Role.FASTENER
			):
				point.finish()
	await _press_down(_cover.global_position)
	var is_straight := false
	for frame in 240:
		if (
			absf(
				wrapf(
					_cover.global_rotation - home_rotation,
					-PI,
					PI,
				),
			) < 0.02
		):
			is_straight = true
			break
		await get_tree().physics_frame
	_expect(
		is_straight,
		"grabbed to go back on, the cover turns back to its"
		+ " first rotation",
	)
	await _move_to(_cover.get_home_global_position())
	await _release_at(_cover.get_home_global_position())
	await _seconds(0.8)
	_expect(_cover.is_on, "dropped close, the cover tweens back on")
	var inside := _item.layers[0]
	_expect(
		_cover.get_index() > inside.get_index(),
		"back on, the cover draws over the inside layer"
		+ " (cover at %d, inside at %d)"
		% [_cover.get_index(), inside.get_index()],
	)
	# Drag the first screw to its hole: it arcs down and sinks in.
	var middle := (
		_screw.bench_art.global_position + _screw.rest_hit_offset
	)
	await _press_down(middle)
	await _move_to(_screw.global_position)
	await _release_at(_screw.global_position)
	_expect(
		await _wait_for_travel(_screw, Screw.Travel.HOME, 3.0),
		"dropped close, the screw seats itself in its hole",
	)
	_expect(
		_screw.is_install_mode and _screw.slide == 1.0,
		"the seated screw sits loose, ready to drive in",
	)


## Records a shadow's fade once per idle frame until `done`.
func _sample_shadow_fades(shadow: DropShadow, done: Callable) -> Array:
	var fades: Array = []
	for frame in 240:
		fades.append(snappedf(shadow._fade, 0.01))
		if bool(done.call()):
			return fades
		await get_tree().process_frame
	return fades


## True when the samples move one way with at least three distinct
## values strictly between the ends: a fade, not a snap.
func _is_smooth_fade(fades: Array, is_rising: bool) -> bool:
	var distinct_between := {}
	for index in fades.size():
		var value: float = fades[index]
		if value > 0.02 and value < 0.98:
			distinct_between[value] = true
		if index == 0:
			continue
		var previous: float = fades[index - 1]
		if is_rising and value < previous - 0.001:
			return false
		if not is_rising and value > previous + 0.001:
			return false
	return distinct_between.size() >= 3


## Turns `host` a quarter turn and back, and checks that its
## drop shadow still bears down-screen from it: the offset is
## in the world frame, so the shadow sits at the same world
## offset however the piece itself is turned. The shadow's
## turn still follows the host, so a silhouette's shape
## matches the rotated sprite.
func _check_shadow_turns_with(
	shadow: DropShadow,
	host: Node2D,
	label: String,
) -> void:
	if not _expect(
		is_instance_valid(shadow),
		"%s has a drop shadow to turn with" % label,
	):
		return
	var rest_rotation := host.rotation
	host.rotation = rest_rotation + PI * 0.5
	host.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame
	var expected_offset := shadow.offset_px
	var actual_offset := (
		shadow.global_position - host.global_position
	)
	_expect(
		actual_offset.distance_to(expected_offset) < 0.5,
		(
			"%s's shadow bears down-screen at the same world offset"
			+ " however it is turned (offset %s, want %s)"
		) % [label, actual_offset, expected_offset],
	)
	_expect(
		absf(
			wrapf(
				shadow.global_rotation - host.global_rotation,
				-PI,
				PI,
			),
		) < 0.01,
		"%s's shadow keeps its turn with it" % label,
	)
	host.rotation = rest_rotation
	host.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame


## The drop shadow attached to a host node, or null.
func _find_shadow(host: Node) -> DropShadow:
	var pending: Array[Node] = [_level]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is DropShadow and (node as DropShadow)._host == host:
			return node as DropShadow
		pending.append_array(node.get_children())
	return null


## A point on the cover's art with no interaction point on it.
func _find_cover_grab_point() -> Vector2:
	for x_offset in range(-80, 81, 20):
		for y_offset in range(-60, 61, 20):
			var point := (
				_cover.global_position
				+ Vector2(float(x_offset), float(y_offset))
			)
			if (
				_cover.has_point(point)
				and not is_instance_valid(_hand.find_point(point))
			):
				return point
	return Vector2.INF
