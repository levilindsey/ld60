extends "res://tests/probe_base.gd"
## Audits every highlight surface on every shipped item.
##
## The idle hint (what the hint tracker lights after a stall)
## must appear for every interaction type and every authored
## instance, at the thing it marks, in a readable world size:
## - every point on every layer of every shipped repairable:
##   hint turns on, draws, and turns off;
## - every layer: its hint shows (sprite outline and/or the
##   carried rim), and no layer's texture is so tight that
##   neither can draw;
## - every socket: the ghost outline shows exactly when the
##   socket is empty and opts in, and a starts-broken socket
##   has a sprite for the mid-yank highlight;
## - every tool in the rack, and one runtime BenchDust the
##   way a TV whack makes it.
##
## Run it with `tests/run.ps1 -Name highlight_audit`, or from
## the repo root (PowerShell):
##   godot --headless --path . res://tests/highlight_audit/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

const _ITEM_TYPES: Array[Repairable.Type] = [
	Repairable.Type.TOASTER,
	Repairable.Type.ATARI_JOYSTICK,
	Repairable.Type.KEYBOARD,
	Repairable.Type.TV,
	Repairable.Type.PIANO,
	Repairable.Type.GAME_N_WATCH,
	Repairable.Type.RADIO,
	Repairable.Type.SHRINK_RAY,
]

## A hint smaller than this in both world dimensions cannot
## be seen, whatever it traces.
const _MIN_HINT_PX := 8.0
## A hint bigger than this in either world dimension is
## drawing around the wrong thing (or twice-scaled).
const _MAX_HINT_PX := 900.0
## How far the hint's middle may sit from what it marks, in
## world pixels. A part shape legitimately stands off its
## socket's origin, so this is loose; it catches hints drawn
## in the wrong place entirely (wrong parent, wrong scale).
const _MAX_CENTER_OFFSET_PX := 320.0

var _level: Level


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	var main := (
		(load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
		as Main
	)
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	_level = G.level
	_hand = G.level.hand
	for item_type in _ITEM_TYPES:
		await _check_item(item_type)
	_check_tools()
	await _check_bench_dust()
	_finish(0 if _failures.is_empty() else 1)


func _check_item(item_type: Repairable.Type) -> void:
	var scene := G.settings.get_repairable_scene_from_type(item_type)
	var item := scene.instantiate() as Repairable
	_level.add_child(item)
	item.mode = Repairable.Mode.UNDER_REPAIR
	item.global_position = Vector2(0, 120)
	await _physics_frames(4)
	var item_name := item.item_name
	for layer in item.layers:
		_check_layer(item_name, layer)
		for point in layer.get_points():
			_check_point(item_name, point)
			if point is PartSocket:
				_check_socket(item_name, point as PartSocket)
	item.queue_free()
	await _physics_frames(2)


## The point's world footprint, as its hint would trace it:
## center and size in world pixels.
func _world_footprint(
	hint: OutlineHint,
) -> Dictionary:
	var transform := hint.get_global_transform()
	var rect := Rect2(transform * hint.polygon[0], Vector2.ZERO)
	for index in range(1, hint.polygon.size()):
		rect = rect.expand(transform * hint.polygon[index])
	return {"center": rect.get_center(), "size": rect.size}


func _check_hint_render(
	label: String,
	owner: CanvasItem,
	is_on: bool,
) -> void:
	if not _expect(is_on, "%s: the hint turns on" % label):
		return
	var hint := owner.get("_hint_hint") as OutlineHint
	if is_instance_valid(hint) and hint.is_active():
		var footprint := _world_footprint(hint)
		var size := footprint["size"] as Vector2
		_expect(
			maxf(size.x, size.y) >= _MIN_HINT_PX
			and size.x <= _MAX_HINT_PX
			and size.y <= _MAX_HINT_PX,
			"%s: the hint draws at a readable world size (%s)"
			% [label, str(size)],
		)
		var offset := (
			(footprint["center"] as Vector2)
			.distance_to(owner.global_position)
		)
		_expect(
			offset <= _MAX_CENTER_OFFSET_PX,
			"%s: the hint draws at its point (%.0f px off)" % [
				label, offset,
			],
		)


func _check_point(item_name: String, point: InteractionPoint) -> void:
	var label := "%s %s" % [item_name, point.name]
	point.set_hint_active(true)
	_check_hint_render(
		label, point, point.is_hint_active(),
	)
	point.set_hint_active(false)
	_expect(
		not point.is_hint_active(),
		"%s: the hint turns off" % label,
	)


func _check_layer(item_name: String, layer: RepairLayer) -> void:
	var label := "%s layer %s" % [item_name, layer.name]
	layer.set_hint_active(true)
	_expect(
		layer.is_showing_outline(),
		"%s: the layer hint shows" % label,
	)
	# The shader outline only paints inside the texture's
	# transparent margin. A tight texture must carry the
	# authored-shape rim instead, or the hint is clipped
	# away on some edges.
	if layer.art is Sprite2D:
		var art := layer.art as Sprite2D
		if is_instance_valid(art.texture):
			var rim := OutlineHint.get_sprite_rim_world(art)
			var shape_rim := layer.get("_outline_hint") as OutlineHint
			_expect(
				rim >= OutlineHint.get_shared_width()
				or (is_instance_valid(shape_rim)
				and shape_rim.is_active()),
				"%s: tight art (%.0f px rim) carries a shape rim"
				% [label, rim],
			)
	layer.set_hint_active(false)
	_expect(
		not layer.is_hint_active(),
		"%s: the layer hint turns off" % label,
	)


func _check_socket(item_name: String, socket: PartSocket) -> void:
	var label := "%s %s" % [item_name, socket.name]
	# The ghost of the good part shows exactly when the
	# socket is empty and the socket opts in.
	var ghost := socket.get_node("Outline") as Polygon2D
	_expect(
		ghost.visible
		== (not socket.has_broken_part and socket.shows_ghost_outline),
		"%s: the ghost outline matches the socket's state" % label,
	)
	# And it must trace the part, not fall back to the fitted
	# sprite's bounding rectangle: a filled rect reads as a
	# phantom slab where the part should be (the radio's
	# bulb). A traced silhouette has more than a rect's
	# corners to say it with. A part whose art really is a
	# rectangle (a key cap, the piano's LED strip) fills its
	# region, and for it the rect is the true silhouette.
	if socket.shows_ghost_outline:
		_expect(
			is_instance_valid(socket.good_part_shape)
			or ghost.polygon.size() > 4
			or _art_fills_its_region(socket),
			"%s: the ghost traces a part shape (%d points)"
			% [label, ghost.polygon.size()],
		)
	# The mid-yank highlight paints on the broken part's
	# sprite. A starts-broken socket with no sprite has
	# nothing to light while it is pulled.
	if socket.starts_with_broken_part:
		_expect(
			is_instance_valid(socket._get_broken_sprite()),
			"%s: the broken part has a sprite to highlight" % label,
		)


## True when the socket's fitted sprite fills the corners
## of its own region: its bounding rectangle is then the
## part's true silhouette, not a phantom slab over empty
## corners (the radio's bulb again). Samples a coarse grid
## of the region's alpha; a shaped part leaves at least one
## corner sample empty.
func _art_fills_its_region(socket: PartSocket) -> bool:
	var fitted := socket.installed_art as Sprite2D
	if not is_instance_valid(fitted):
		return false
	if not is_instance_valid(fitted.texture):
		return false
	var image := fitted.texture.get_image()
	if not is_instance_valid(image):
		return false
	# The sampled area, in texture pixels: the region when
	# the sprite draws one, the whole texture otherwise.
	var area := Rect2(Vector2.ZERO, image.get_size())
	if fitted.region_enabled:
		area = fitted.region_rect
	var grid := 6
	var empty := 0
	var total := 0
	for gx in grid:
		for gy in grid:
			var point := area.position + Vector2(
				area.size.x * (float(gx) + 0.5) / grid,
				area.size.y * (float(gy) + 0.5) / grid,
			)
			total += 1
			var pixel := Vector2i(
				clampi(int(point.x), 0, image.get_width() - 1),
				clampi(int(point.y), 0, image.get_height() - 1),
			)
			if image.get_pixelv(pixel).a < 0.25:
				empty += 1
	return total > 0 and float(empty) / float(total) < 0.2


func _check_tools() -> void:
	for tool_type in _level.tools_by_type:
		var tool := _level.tools_by_type[tool_type] as Tool
		tool.set_hint_active(true)
		_check_hint_render(
			"tool %s" % tool.name, tool, tool.is_hint_active(),
		)
		tool.set_hint_active(false)
		_expect(
			not tool.is_hint_active(),
			"tool %s: the hint turns off" % tool.name,
		)


func _check_bench_dust() -> void:
	# Bench dust is made at runtime, by whacking the TV; it
	# still answers to the same hint call as any point.
	var spawned := _level.spawn_bench_dust(Vector2(0, 120), 1)
	if not _expect(not spawned.is_empty(), "bench dust spawns"):
		return
	var dust := spawned[0]
	await _physics_frames(2)
	_check_point("runtime", dust)
	for leftover in spawned:
		leftover.queue_free()
