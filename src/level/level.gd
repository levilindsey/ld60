class_name Level
extends Node2D


const _GAME_OVER_RESTART_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2.ZERO

## A bench return is flying in under gravity toward its
## landing point inside the workable area.
const _RETURN_FLYING := 0
## A bench return has landed and is bouncing and skidding
## on the bench until it comes to rest.
const _RETURN_SETTLING := 1
## A bench return was thrown with the cursor's motion. It
## flies under gravity, bounces off the sides of the
## viewport, may pass out of the top and falls back, and
## lands when it falls into the workable area.
const _RETURN_THROWN := 2
## A thrown return that would fall past the workable area
## is guided the rest of the way: its path starts along the
## speed it was thrown with and eases into its rest point.
const _RETURN_GUIDED := 3
## How much speed a throw keeps when it bounces off a side
## of the viewport.
const _RETURN_WALL_RESTITUTION := 0.55
## Longest a throw may fly before it is guided in anyway,
## in seconds.
const _RETURN_THROW_MAX_SEC := 4.0
## The least bounce a returned piece keeps, whatever its
## size, and the most any piece keeps.
const _RETURN_MIN_RESTITUTION := 0.08
const _RETURN_MAX_RESTITUTION := 0.5
## How much of a landing's downward speed becomes a skid
## across the bench, and how much of its sideways speed the
## skid keeps. The downward share is small: most of a fall
## becomes the bounce, so the skid cannot swallow it.
const _RETURN_SKID_DOWN_SHARE := 0.08
const _RETURN_SKID_SIDE_SHARE := 0.7

## The bench dust a hard knock spews across the bench. It is
## loaded here because the level owns the dust; the scene is
## not a per-level configuration.
const _BENCH_DUST_SCENE: PackedScene = preload(
	"res://src/interaction_points/bench_dust.tscn"
)
## How far from the spew point a bench dust clump may land,
## in world pixels.
const _BENCH_DUST_SPREAD_PX := 44.0


var has_started := false
var has_won := false

## Times the current repair step and lights its target, then
## its tool, when the player stalls. See HintTracker.
var hint_tracker: HintTracker

var tools_by_type: Dictionary[Tool.Type, Tool] = {}
## The item on the bench, or null while the next one is on its way.
var active_repairable: Repairable
## How many items of `Settings.item_queue` have been spawned.
var next_item_index := 0
## The day's order as played: `Settings.item_queue`, with
## the settings' first-repairable override (if any) moved
## to the front. Built once when the level starts.
var _effective_queue: Array[Repairable.Type] = []

## The player's hand: what is held, the cursor and press routing.
var hand: Hand:
	get:
		return %Hand

## The screws resting on the bench, by rest spot (docs/design/
## screw_pullout.md). A free spot holds null or a freed screw. It is
## untyped so a freed screw never lands in a typed variable.
var _resting_screws: Array = []

## Each spot's outline, by its placeholder.
var _spot_outline_hints := {}
## Each spot's label fade, by its label.
var _spot_label_tweens := {}
## Where the shop radio item lines up with the radio on the shelf.
var _shop_radio_pose := Transform2D.IDENTITY

## Every loose part spawned for the item on the bench: stored in a
## drawer, resting on the bench, or on its way back into a drawer.
## Installed parts leave the list by flag, not by removal. It is
## untyped so a freed part never lands in a typed variable.
var _drawer_parts: Array = []

## Every broken piece of the item on the bench, on the item,
## loose on the bench or glued back on. Installed pieces stay
## in the list by flag. Untyped, like the drawer parts.
var _broken_pieces: Array = []

## Every bench dust clump spewed onto the bench, cleaned ones
## included until they are cleared. Bench dust lives here, not
## on the item. Untyped, like the drawer parts.
var _bench_dust: Array = []

## The fade tween currently running on each drawer's stored
## parts, keyed by the drawer, so a new fade kills the old one.
var _part_fade_tweens: Dictionary = {}

## Pieces on their way back to the workable area after a
## drop outside it, one dictionary per piece. See
## `start_bench_return()`. Untyped so a freed piece never
## lands in a typed variable.
var _bench_returns: Array = []

## The `%WorkableArea` and `%Outbox` polygons in world
## pixels, read from their collision polygons once.
var _workable_polygon_global: PackedVector2Array = []
var _outbox_polygon_global: PackedVector2Array = []

## The scene a drawer part comes from.
@export var part_scene: PackedScene

## The workbench surface, in this level's local coordinates: loose
## pieces (screws, lids, parts) may be placed anywhere inside it and
## nowhere else. A drag that leaves it drops the piece at the edge.
@export var bench_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-620.0, -90.0),
	Vector2(620.0, -90.0),
	Vector2(620.0, 340.0),
	Vector2(-620.0, 340.0),
])


func _enter_tree() -> void:
	if not is_instance_valid(G.main):
		# This level scene was run directly. Drop its children before
		# they enter the tree, since they expect a booted game. Then
		# boot the full game into this level.
		for child in get_children():
			remove_child(child)
			child.free()
		G.boot_from_level(self)
		return
	G.level = self


func _exit_tree() -> void:
	if G.level == self:
		G.level = null


func _ready() -> void:
	if not is_instance_valid(G.main):
		return

	# Center the camera's anchor on its position. In Godot 4.5+ the
	# Camera2D default changed to FIXED_TOP_LEFT, which would make
	# the player render at the top-left of the screen given our
	# follow logic in _physics_process.
	%Camera2D.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER

	_cache_area_polygons()

	var drawers := get_drawers()
	for index in drawers.size():
		var drawer := drawers[index]
		drawer.drawer_index = index
		drawer.opened.connect(_on_drawer_opened.bind(drawer))
		drawer.close_started.connect(_on_drawer_close_started.bind(drawer))

	_build_effective_queue()
	%TicketCard.done_closed.connect(_on_ticket_done_closed)

	hint_tracker = HintTracker.new()
	hint_tracker.name = "HintTracker"
	add_child(hint_tracker)

	# TODO: Add some level and spawn configs to control when what things spawn.
	spawn_tool(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	spawn_tool(Tool.Type.RAG)
	spawn_tool(Tool.Type.AIR_BLOWER)
	spawn_tool(Tool.Type.HAMMER)
	spawn_tool(Tool.Type.PHILLIPS_SCREW_DRIVER)
	spawn_tool(Tool.Type.GLUE)
	if G.ensure(
		not G.settings.item_queue.is_empty(),
		"The item queue is empty.",
	):
		_spawn_next_item()


func _physics_process(delta: float) -> void:
	_step_bench_returns(delta)
	_bounce_shop_radio()


func start_game() -> void:
	G.print("Starting level", ScaffolderLog.CATEGORY_GAME_STATE)

	has_started = true
	has_won = false


## Call when the player wins. Shows the credits overlay; pressing
## jump/ability there starts a fresh run.
func win() -> void:
	if has_won:
		return
	G.print("Game won", ScaffolderLog.CATEGORY_GAME_STATE)
	has_won = true
	G.audio.play_sound(&"sigh_relief")
	G.state.transition(StateMain.State.CREDITS)


func spawn_tool(type: Tool.Type) -> void:
	G.check(not tools_by_type.has(type))

	var tool_scene := G.settings.get_tool_scene_from_type(type)
	G.check(is_instance_valid(tool_scene))
	var tool: Tool = tool_scene.instantiate()
	# Tools are their own draw group, above every loose piece.
	tool.z_index = 20
	%Tools.add_child(tool)
	tool.global_position = %ItemSpawnPosition.global_position
	tools_by_type[type] = tool
	tool.snap_to_holder()


## Dev only: swaps the item on the bench for the next one in the queue,
## starting over after the last. Does nothing between items.
func swap_item_for_dev() -> void:
	if not is_instance_valid(active_repairable):
		return
	if is_instance_valid(hand.held) and not hand.held is Tool:
		hand.release()
	var item := active_repairable
	active_repairable = null
	cleanup_broken_pieces(item)
	cleanup_loose_parts()
	set_outbox_outline_shown(false)
	if item.is_shop_radio:
		%Radio.return_to_shelf()
		G.audio.restore_main_theme()
	item.queue_free()
	if _is_queue_finished():
		next_item_index = 0
	_spawn_next_item()


## Drops an item of a type onto the bench and returns it. The camera
## shakes on each bounce, and the ticket appears when it lands.
func spawn_repairable(type: Repairable.Type) -> Repairable:
	G.check(not is_instance_valid(active_repairable))

	var item_scene := G.settings.get_repairable_scene_from_type(type)
	G.check(is_instance_valid(item_scene))
	var item: Repairable = item_scene.instantiate()
	%Repairables.add_child(item)
	item.global_position = %ItemSpawnPosition.global_position
	item.reset_physics_interpolation()
	active_repairable = item
	for piece in item.get_broken_pieces():
		register_broken_piece(piece)

	item.quality.defect_added.connect(_on_defect_added)
	item.impacted.connect(_on_item_impacted)
	item.landed.connect(_on_item_landed.bind(item))
	if item.is_shop_radio:
		_break_shop_radio(item)
	else:
		item.arrive(%ActiveItemPosition.global_position)
	return item


## Shakes the camera. See `CameraShaker`.
func shake_camera(amplitude_px: float, duration_sec: float) -> void:
	%CameraShaker.shake_camera(amplitude_px, duration_sec)


## The hand let go of an item. A finished item over the outbox goes into
## it. A drop inside the workable area eases back to where the bench
## keeps the item. A drop outside both the workable area and the
## outbox flies back in under gravity and comes to rest inside the
## workable area, bouncing and skidding as it lands. A fast drag
## throws it with the cursor's motion instead, the way it throws
## a part or a screw.
func drop_item(
	item: Repairable,
	release_velocity := Vector2.ZERO,
) -> void:
	if not is_instance_valid(item):
		return
	if _is_at_ship_spot(item):
		_ship(item)
		return
	if try_return_repairable(item, release_velocity):
		return
	var margin_px := (
		item.get_bench_radius_px()
		+ G.settings.workable_edge_padding_px
	)
	if (
		is_inside_workable_area(item.global_position, margin_px)
		or is_inside_outbox_area(item.global_position, margin_px)
	):
		return_item(item)
		return
	return_item(item)


## Shows or hides the outline around the outbox. A finished item
## turns it on, so the bench says where the item goes next. The shop
## radio goes back to its shelf, so it marks the radio's spot instead.
func set_outbox_outline_shown(is_shown: bool) -> void:
	if (
		is_instance_valid(active_repairable)
		and active_repairable.is_shop_radio
	):
		_set_spot_shown(%RadioSpotPlaceholder, %RadioSpotLabel, is_shown)
		return
	_set_spot_shown(
		%Outbox.get_node("Placeholder") as Polygon2D,
		%OutboxLabel,
		is_shown,
	)


## True while the outbox shows its outline.
func is_outbox_outline_shown() -> bool:
	var hint := _spot_outline_hints.get(
		%Outbox.get_node("Placeholder")
	) as OutlineHint
	return is_instance_valid(hint) and hint.is_active()


## Turns a spot's outline on or off and fades its label with it.
func _set_spot_shown(
	placeholder: Polygon2D,
	label: Label,
	is_shown: bool,
) -> void:
	var hint := _spot_outline_hints.get(placeholder) as OutlineHint
	if is_shown and not is_instance_valid(hint):
		var points := OutlineHint.get_art_polygon(placeholder)
		if points.is_empty():
			return
		hint = OutlineHint.new()
		placeholder.add_child(hint)
		hint.polygon = points
		_spot_outline_hints[placeholder] = hint
	if is_instance_valid(hint):
		hint.set_active(is_shown)
	var old_tween := _spot_label_tweens.get(label) as Tween
	if is_instance_valid(old_tween):
		old_tween.kill()
	var tween := create_tween()
	tween.tween_property(
		label,
		"modulate:a",
		1.0 if is_shown else 0.0,
		G.settings.outbox_label_fade_sec,
	)
	_spot_label_tweens[label] = tween


## Eases an item back to where the bench keeps the item being repaired.
func return_item(item: Repairable) -> void:
	if is_instance_valid(item):
		item.return_to(%ActiveItemPosition.global_position)


## The holder in the rack for a tool type, or null.
func get_tool_holder(type: Tool.Type) -> ToolHolder:
	for child in %ToolHolders.get_children():
		if child is ToolHolder and (child as ToolHolder).type == type:
			return child as ToolHolder
	return null


## Where a stored tool's holder shape sits: the center of the shape of
## the holder for its type.
func get_tool_holder_position(type: Tool.Type) -> Vector2:
	var holder := get_tool_holder(type)
	if not is_instance_valid(holder):
		G.error("No tool holder for %s" % Tool.Type.keys()[type])
		return Vector2.INF
	return holder.get_shape_position()


## The parts drawers stacked on the left side, top first.
func get_drawers() -> Array[Drawer]:
	var drawers: Array[Drawer] = []
	for child in %Drawers.get_children():
		if child is Drawer:
			drawers.append(child as Drawer)
	return drawers


## The drawer open in the center or on its way there, or null.
## A press while one is still opening already counts as a press
## with a drawer open.
func get_open_or_opening_drawer() -> Drawer:
	for drawer in get_drawers():
		if (
			drawer.state == Drawer.State.OPEN
			or drawer.state == Drawer.State.OPENING
		):
			return drawer
	return null


## The drawer sitting open in the center, or null.
func get_open_drawer() -> Drawer:
	for drawer in get_drawers():
		if drawer.state == Drawer.State.OPEN:
			return drawer
	return null


## True while any drawer is between poses.
func are_drawers_busy() -> bool:
	for drawer in get_drawers():
		if drawer.is_busy():
			return true
	return false


## The drawer a world position lands on, open or shut, or null.
func get_drawer_at(global_point: Vector2) -> Drawer:
	for drawer in get_drawers():
		if drawer.has_global_point(global_point):
			return drawer
	return null


## The stored part showing in an open drawer at a world position,
## or null. Parts are small, so a press near the center counts.
func get_drawer_part_at(drawer: Drawer, global_point: Vector2) -> Part:
	var part := _get_part_at(global_point)
	if (
		is_instance_valid(part)
		and part.is_stored
		and part.drawer_index == drawer.drawer_index
	):
		return part
	return null


## The loose part resting on the bench at a world position, or
## null. A part being put away cannot be grabbed again.
func get_loose_part_at(global_point: Vector2) -> Part:
	var part := _get_part_at(global_point)
	if (
		is_instance_valid(part)
		and not part.is_stored
		and not part.is_installed
		and not part.is_returning
	):
		return part
	return null


## The parts stored in a drawer, visible or not.
func get_parts_in_drawer(drawer: Drawer) -> Array[Part]:
	var parts: Array[Part] = []
	for entry: Variant in _drawer_parts:
		if not is_instance_valid(entry):
			continue
		var part := entry as Part
		if part.is_stored and part.drawer_index == drawer.drawer_index:
			parts.append(part)
	return parts


## Every part spawned for the item on the bench, stored, loose
## or returning. Installed parts stay in the list by flag.
func get_drawer_parts() -> Array[Part]:
	var parts: Array[Part] = []
	for entry: Variant in _drawer_parts:
		if is_instance_valid(entry):
			parts.append(entry as Part)
	return parts


## The loose part of a kind that is out on the bench, or null. A
## part being dragged counts, and sorts first, so a step that
## needs the part sees the one already in motion.
func get_loose_part_of_type(part_type: Part.Type) -> Part:
	var dragged: Part = null
	if is_instance_valid(hand):
		dragged = hand.get_loose_part()
	if (
		is_instance_valid(dragged)
		and dragged.type == part_type
		and not dragged.is_installed
	):
		return dragged
	for part in get_drawer_parts():
		if part.type != part_type:
			continue
		if part.is_stored or part.is_installed or part.is_returning:
			continue
		return part
	return null


## Notes a broken piece so presses and returns can find it.
func register_broken_piece(piece: BrokenPiece) -> void:
	if is_instance_valid(piece) and not _broken_pieces.has(piece):
		_broken_pieces.append(piece)


## Every broken piece noted for the bench, freed ones skipped.
func get_broken_pieces() -> Array[BrokenPiece]:
	var pieces: Array[BrokenPiece] = []
	for entry: Variant in _broken_pieces:
		if is_instance_valid(entry):
			pieces.append(entry as BrokenPiece)
	return pieces


## The grabbable broken piece nearest a world position, or
## null. A press near its middle counts, like a loose part.
func get_loose_broken_piece_at(
	global_point: Vector2,
) -> BrokenPiece:
	var best: BrokenPiece = null
	var best_distance := INF
	for piece in get_broken_pieces():
		if piece.is_installed or not piece.can_grab():
			continue
		var distance := piece.global_position.distance_to(
			global_point
		)
		if distance <= piece.grab_radius_px and distance < (
			best_distance
		):
			best_distance = distance
			best = piece
	return best


## Starts a detached piece's own fall to its landing spot,
## with the loose pieces' flight, bounce, skid and spin.
func start_broken_piece_fall(
	piece: BrokenPiece, target_global_position: Vector2
) -> void:
	if not is_instance_valid(piece):
		return
	if not _start_bench_return(
		piece,
		piece,
		piece.global_position,
		piece.get_radius_px(),
		target_global_position,
		Vector2.ZERO,
	):
		piece.finish_bench_return()


## Brings a dropped broken piece back to the workable area,
## the way try_return_part() does for a drawer part.
func try_return_broken_piece(
	piece: BrokenPiece,
	release_velocity := Vector2.ZERO,
) -> bool:
	if not is_instance_valid(piece):
		return false
	return _start_bench_return(
		piece,
		piece,
		piece.global_position,
		piece.get_radius_px(),
		Vector2.INF,
		release_velocity,
	)


## Frees the loose broken pieces of an item that shipped.
func cleanup_broken_pieces(item: Repairable) -> void:
	for piece in get_broken_pieces():
		if piece.item == item and not piece.is_installed:
			_broken_pieces.erase(piece)
			piece.queue_free()


## The stored part of a kind inside a drawer, visible or not, or
## null.
func get_part_of_type_in_drawer(
	drawer: Drawer,
	part_type: Part.Type,
) -> Part:
	for part in get_parts_in_drawer(drawer):
		if part.type == part_type:
			return part
	return null


## Restocks the drawers for an item that just landed: the old loose
## parts go away, and a fresh set is hidden at random across the
## drawers. The set holds one of every part kind in the game, plus
## extra copies per socket the item needs, plus decoys, shuffled
## so hunting takes opening more than one drawer. It resets for
## each repairable.
func restock_parts(item: Repairable) -> void:
	for drawer in get_drawers():
		drawer.reset_closed()
		var fade := _part_fade_tweens.get(drawer) as Tween
		if is_instance_valid(fade):
			fade.kill()
	_part_fade_tweens.clear()
	for entry: Variant in _drawer_parts:
		if is_instance_valid(entry):
			(entry as Part).queue_free()
	_drawer_parts.clear()
	if not is_instance_valid(item):
		return
	G.check(is_instance_valid(part_scene))

	# One of every part kind in the game, so the full set is
	# on show across the drawers for every repairable.
	var part_types: Array[Part.Type] = []
	for part_type in Part.Type.values():
		part_types.append(part_type as Part.Type)
	# Extra copies of what this item's sockets need, beyond
	# the one of each kind above.
	for layer in item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				part_types.append(
					(point as PartSocket).accepted_part
				)
	# Decoys are kinds the item does not need, when it leaves any.
	var needed_types: Array[Part.Type] = []
	for layer in item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				needed_types.append(
					(point as PartSocket).accepted_part
				)
	var decoy_types: Array[Part.Type] = []
	for part_type in Part.Type.values():
		if not needed_types.has(part_type):
			decoy_types.append(part_type as Part.Type)
	if decoy_types.is_empty():
		decoy_types = part_types.duplicate()
	for _decoy in maxi(G.settings.decoy_part_count, 0):
		if not decoy_types.is_empty():
			part_types.append(
				decoy_types[randi_range(0, decoy_types.size() - 1)]
			)
	part_types.shuffle()

	var drawers := get_drawers()
	if drawers.is_empty():
		return
	for part_type in part_types:
		var part := part_scene.instantiate() as Part
		G.check(is_instance_valid(part))
		add_child(part)
		part.setup(part_type)
		part.is_stored = true
		part.drawer_index = randi_range(0, drawers.size() - 1)
		part.hide()
		_drawer_parts.append(part)


## Puts every part left out on the bench away into one drawer,
## picked at random. The level calls this when an item goes into
## the outbox, so the bench is tidy for the next one.
func cleanup_loose_parts() -> void:
	var loose: Array[Part] = []
	for entry: Variant in _drawer_parts:
		if not is_instance_valid(entry):
			continue
		var part := entry as Part
		if (
			not part.is_stored
			and not part.is_installed
			and not part.is_returning
		):
			loose.append(part)
	if loose.is_empty():
		return
	var drawers := get_drawers()
	if drawers.is_empty():
		return
	drawers[randi_range(0, drawers.size() - 1)].store_parts(loose)


## The loose part nearest a world position within grab range, or
## null.
func _get_part_at(global_point: Vector2) -> Part:
	var best: Part = null
	var best_distance := G.settings.part_grab_radius_px
	for entry: Variant in _drawer_parts:
		if not is_instance_valid(entry):
			continue
		var part := entry as Part
		if part.is_installed or not part.is_visible_in_tree():
			continue
		var distance := part.global_position.distance_to(global_point)
		if distance <= best_distance:
			best_distance = distance
			best = part
	return best


## Where layers wait while they are off the item.
func get_set_aside_spot() -> Node2D:
	return %PartSetAsideSpot


## The layers at the set-aside spot, bottom of the stack first.
func get_set_aside_layers() -> Array[RepairLayer]:
	var layers: Array[RepairLayer] = []
	for child in %PartSetAsideSpot.get_children():
		if child is RepairLayer:
			layers.append(child as RepairLayer)
	return layers


## True when a world position is on the workbench surface where
## loose pieces may be placed.
func is_inside_bench(global_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(
		to_local(global_point),
		bench_polygon,
	)


## The closest point inside the workbench to a world position, for
## dropping a piece that was dragged beyond the bench.
func clamp_to_bench(global_point: Vector2) -> Vector2:
	var local_point := to_local(global_point)
	if Geometry2D.is_point_in_polygon(local_point, bench_polygon):
		return global_point
	var closest := local_point
	var closest_distance := INF
	for index in bench_polygon.size():
		var from_point := bench_polygon[index]
		var to_point := bench_polygon[
			(index + 1) % bench_polygon.size()
		]
		var candidate := Geometry2D.get_closest_point_to_segment(
			local_point,
			from_point,
			to_point,
		)
		var distance := local_point.distance_squared_to(candidate)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
	return to_global(closest)


## The `%WorkableArea` polygon in world pixels. Loose parts
## and screws may be dragged anywhere, but they only come to
## rest inside this polygon. A finished item may also come
## to rest in the outbox.
func get_workable_polygon() -> PackedVector2Array:
	if _workable_polygon_global.is_empty():
		_cache_area_polygons()
	return _workable_polygon_global


## The `%Outbox` polygon in world pixels.
func get_outbox_polygon() -> PackedVector2Array:
	if _outbox_polygon_global.is_empty():
		_cache_area_polygons()
	return _outbox_polygon_global


## True when a world position is inside the workable area,
## at least `margin_px` clear of every edge. The margin is
## the piece's radius plus the edge padding, so the whole
## piece is inside when its middle passes.
func is_inside_workable_area(
	global_point: Vector2,
	margin_px := 0.0,
) -> bool:
	return _is_inside_area_polygon(
		global_point,
		get_workable_polygon(),
		margin_px,
	)


## True when a world position is inside the outbox area, at
## least `margin_px` clear of every edge.
func is_inside_outbox_area(
	global_point: Vector2,
	margin_px := 0.0,
) -> bool:
	return _is_inside_area_polygon(
		global_point,
		get_outbox_polygon(),
		margin_px,
	)


## The point inside the workable area that a piece dropped
## at a world position should land on: the position itself
## when it is already inside with `margin_px` to spare, else
## the nearest edge point pushed that far toward the middle.
func get_workable_area_target(
	global_point: Vector2,
	margin_px := 0.0,
) -> Vector2:
	return _get_area_target(
		global_point,
		get_workable_polygon(),
		margin_px,
	)


## Starts bringing a loose part back to the workable area
## after it was dropped outside it. It falls straight down
## when it is above the area and is flicked in an arc under
## gravity from below or from the side, then bounces and
## skids as it lands. The amount of bounce and skid follows
## the landing speed and the part's size. A release faster
## than the throw threshold in `Settings` throws it with
## the cursor's motion instead. Returns true when a return
## started, and false when the part already rests inside
## and was let go slowly.
func try_return_part(
	part: Part,
	release_velocity := Vector2.ZERO,
) -> bool:
	if not is_instance_valid(part):
		return false
	return _start_bench_return(
		part,
		part,
		part.global_position,
		part.get_radius_px(),
		Vector2.INF,
		release_velocity,
	)


## Starts bringing a resting screw back to the workable
## area after it was dropped outside it, the way
## `try_return_part()` does for a part. The screw's middle
## is its bench art plus `rest_hit_offset`, where presses
## find it.
func try_return_screw(
	screw: Screw,
	release_velocity := Vector2.ZERO,
) -> bool:
	if not is_instance_valid(screw):
		return false
	if not is_instance_valid(screw.bench_art):
		return false
	var middle := (
		screw.bench_art.global_position + screw.rest_hit_offset
	)
	return _start_bench_return(
		screw,
		screw.bench_art,
		middle,
		screw.get_rest_radius_px(),
		Vector2.INF,
		release_velocity,
	)


## Starts bringing a set-aside layer back to the workable
## area after it was dropped outside it, the way
## `try_return_part()` does for a part. A layer never goes
## into a drawer: this and resting on the bench are its only
## drop outcomes besides seating back on its item.
func try_return_layer(
	layer: RepairLayer,
	release_velocity := Vector2.ZERO,
) -> bool:
	if not is_instance_valid(layer):
		return false
	return _start_bench_return(
		layer,
		layer,
		layer.global_position,
		layer.get_radius_px(),
		Vector2.INF,
		release_velocity,
	)


## Starts bringing a finished item back after it was
## dropped outside both the workable area and the outbox.
## It flies to where the bench keeps the item being
## repaired instead of to the nearest edge, the way
## `return_item()` eases it there.
func try_return_repairable(
	item: Repairable,
	release_velocity := Vector2.ZERO,
) -> bool:
	if not is_instance_valid(item):
		return false
	return _start_bench_return(
		item,
		item,
		item.global_position,
		item.get_bench_radius_px(),
		%ActiveItemPosition.global_position,
		release_velocity,
	)


## True while a piece is on its way back to the workable
## area and has not come to rest yet.
func is_bench_returning(owner: Object) -> bool:
	for entry: Variant in _bench_returns:
		if (entry as Dictionary).get("owner") == owner:
			return true
	return false


## Stops a piece's trip back where it is. The hand calls
## this through `Repairable.on_grabbed()` when the player
## catches a finished item in the air. The piece's own
## return flag is cleared by its grab, not here.
func cancel_bench_return(owner: Object) -> void:
	for index in range(_bench_returns.size() - 1, -1, -1):
		var entry := _bench_returns[index] as Dictionary
		if entry.get("owner") == owner:
			_bench_returns.remove_at(index)


func _cache_area_polygons() -> void:
	_workable_polygon_global = _get_area_polygon_global(
		%WorkableArea,
	)
	_outbox_polygon_global = _get_area_polygon_global(%Outbox)


## One area's collision polygon in world pixels, or an empty
## polygon when the area has none.
func _get_area_polygon_global(area: Area2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(area):
		return points
	for child in area.get_children():
		if child is CollisionPolygon2D:
			var polygon_node := child as CollisionPolygon2D
			for point in polygon_node.polygon:
				points.append(polygon_node.to_global(point))
			return points
	return points


## The visible viewport as a world rectangle. Its sides
## are the walls a thrown piece bounces off. The top is
## open: a throw may pass it and fall back down.
func _get_viewport_world_rect() -> Rect2:
	var visible := get_viewport().get_visible_rect()
	var transform := get_canvas_transform().affine_inverse()
	var top_left := transform * visible.position
	var bottom_right := transform * visible.end
	return Rect2(top_left, bottom_right - top_left)


func _is_inside_area_polygon(
	global_point: Vector2,
	polygon: PackedVector2Array,
	margin_px: float,
) -> bool:
	if polygon.size() < 3:
		return false
	if not Geometry2D.is_point_in_polygon(global_point, polygon):
		return false
	if margin_px <= 0.0:
		return true
	for index in polygon.size():
		var from_point := polygon[index]
		var to_point := polygon[(index + 1) % polygon.size()]
		var closest := Geometry2D.get_closest_point_to_segment(
			global_point,
			from_point,
			to_point,
		)
		if global_point.distance_to(closest) < margin_px:
			return false
	return true


func _get_area_target(
	global_point: Vector2,
	polygon: PackedVector2Array,
	margin_px: float,
) -> Vector2:
	if polygon.size() < 3:
		return global_point
	if _is_inside_area_polygon(global_point, polygon, margin_px):
		return global_point
	var closest := global_point
	var closest_distance := INF
	for index in polygon.size():
		var from_point := polygon[index]
		var to_point := polygon[(index + 1) % polygon.size()]
		var candidate := Geometry2D.get_closest_point_to_segment(
			global_point,
			from_point,
			to_point,
		)
		var distance := global_point.distance_squared_to(candidate)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= float(polygon.size())
	# Push in along the closest edge's own inward normal,
	# not toward the middle of the area: along a long edge
	# the middle is mostly sideways, so a push that way
	# barely gains any clearance from the edge. Near a
	# corner the nearest edge changes as the point moves
	# in, so push again from the new nearest edge until
	# the whole piece fits.
	var target := global_point
	if not Geometry2D.is_point_in_polygon(global_point, polygon):
		target = closest
	for push in 16:
		if _is_inside_area_polygon(target, polygon, margin_px):
			return target
		var edge := _get_closest_edge(polygon, target)
		var edge_point := edge[0] as Vector2
		var edge_distance := edge[1] as float
		var inward := edge[2] as Vector2
		if inward.length() < 0.001:
			inward = centroid - edge_point
			if inward.length() < 0.001:
				return target
			inward = inward.normalized()
		target += inward * (margin_px - edge_distance + 1.0)
	return target


## The closest point on a polygon's edge to a world point,
## how far it is, and the edge's inward normal: the way
## from the edge toward the polygon's middle.
func _get_closest_edge(
	polygon: PackedVector2Array,
	global_point: Vector2,
) -> Array:
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= float(polygon.size())
	var closest := global_point
	var closest_distance := INF
	var inward := Vector2.ZERO
	for index in polygon.size():
		var from_point := polygon[index]
		var to_point := polygon[(index + 1) % polygon.size()]
		var candidate := Geometry2D.get_closest_point_to_segment(
			global_point,
			from_point,
			to_point,
		)
		var distance := global_point.distance_to(candidate)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
			var edge_direction := (to_point - from_point).normalized()
			inward = Vector2(
				-edge_direction.y,
				edge_direction.x,
			)
			if inward.dot(centroid - candidate) < 0.0:
				inward = -inward
	return [closest, closest_distance, inward]


## Starts one piece's trip back. `middle` is where the
## piece is judged against the area: its own position, or
## a resting screw's bench art plus its hit offset. A
## `forced_target` other than `Vector2.INF` lands there
## instead of at the nearest point inside. A release speed
## past the throw threshold throws the piece with that
## speed, even from inside the area, instead of solving a
## fall or a flick for it. Returns false when the middle
## already rests inside and the release was slow.
func _start_bench_return(
	owner: Object,
	moving_node: Node2D,
	middle: Vector2,
	radius_px: float,
	forced_target: Vector2,
	release_velocity: Vector2,
) -> bool:
	if not is_instance_valid(owner):
		return false
	if not is_instance_valid(moving_node):
		return false
	if is_bench_returning(owner):
		return true
	var margin_px := (
		radius_px + G.settings.workable_edge_padding_px
	)
	var is_thrown := (
		release_velocity.length()
		>= G.settings.workable_throw_min_speed_px_per_sec
	)
	if is_inside_workable_area(middle, margin_px) and not is_thrown:
		return false
	var target := forced_target
	if target == Vector2.INF:
		target = get_workable_area_target(middle, margin_px)
	var velocity := Vector2.ZERO
	var duration_sec := 0.0
	var phase := _RETURN_FLYING
	if is_thrown:
		velocity = release_velocity.limit_length(
			G.settings.workable_throw_max_speed_px_per_sec,
		)
		phase = _RETURN_THROWN
	else:
		var flight := _solve_return_flight(middle, target)
		velocity = flight[0] as Vector2
		duration_sec = flight[1] as float
	var restitution := clampf(
		G.settings.workable_bounce_restitution
		- radius_px * G.settings.workable_bounce_size_falloff,
		_RETURN_MIN_RESTITUTION,
		_RETURN_MAX_RESTITUTION,
	)
	var skid_deceleration := (
		G.settings.workable_skid_deceleration
		* sqrt(maxf(radius_px, 1.0) / 20.0)
	)
	var viewport_rect := _get_viewport_world_rect()
	var workable_bottom := -INF
	for point in get_workable_polygon():
		workable_bottom = maxf(workable_bottom, point.y)
	_bench_returns.append(
		{
			"owner": owner,
			"node": moving_node,
			"offset": middle - moving_node.global_position,
			"middle": middle,
			"ground": target,
			"target": target,
			"rest_target": forced_target,
			"velocity": velocity,
			"flight_left_sec": duration_sec,
			"flight_elapsed_sec": 0.0,
			"phase": phase,
			"radius_px": radius_px,
			"margin_px": margin_px,
			"restitution": restitution,
			"skid_deceleration": skid_deceleration,
			"ground_velocity": Vector2.ZERO,
			"bounce_height_px": 0.0,
			"bounce_velocity": 0.0,
			"has_landed": false,
			"angular_velocity": clampf(
				velocity.x / maxf(radius_px, 8.0),
				-4.0,
				4.0,
			)
			* 0.4,
			"does_spin": not owner is Repairable,
			"wall_left": viewport_rect.position.x + radius_px,
			"wall_right": viewport_rect.end.x - radius_px,
			"workable_bottom": workable_bottom,
			"guided_from": middle,
			"guided_velocity": Vector2.ZERO,
			"guided_elapsed_sec": 0.0,
			"guided_duration_sec": 1.0,
		},
	)
	if owner is Part:
		(owner as Part).start_bench_return()
	elif owner is BrokenPiece:
		(owner as BrokenPiece).start_bench_return()
	elif owner is Screw:
		(owner as Screw).start_bench_return()
	elif owner is RepairLayer:
		(owner as RepairLayer).start_bench_return()
	elif owner is Repairable:
		(owner as Repairable).start_bench_return()
	return true


## One step of air for a piece in flight: gravity pulls it
## down, wind drag slows it a little, and it never moves
## faster than the fastest speed in `Settings`.
func _apply_air(velocity: Vector2, delta: float) -> Vector2:
	var gravity := maxf(
		G.settings.default_gravity_acceleration,
		1.0,
	)
	velocity.y += gravity * delta
	var drag := maxf(G.settings.workable_wind_drag_per_sec, 0.0)
	if drag > 0.0:
		velocity *= exp(-drag * delta)
	return velocity.limit_length(
		maxf(G.settings.workable_max_speed_px_per_sec, 1.0),
	)


## How far a speed carries in `duration_sec` under wind
## drag: the time the drag leaves of it. With no drag it is
## the duration itself.
func _drag_reach(duration_sec: float, drag: float) -> float:
	if drag < 0.001:
		return duration_sec
	return (1.0 - exp(-drag * duration_sec)) / drag


## The first velocity and the flight time of a trip from
## `from_point` to `to_point` under the game's gravity. A
## drop from above falls straight down: it starts with no
## downward speed and only drifts sideways as fast as the
## tuning allows, stretching the fall when the gap is wide.
## A drop from below or from the side is flicked up in an
## arc whose peak grows with the distance, high enough to
## clear the landing point and fall onto it. Wind drag is
## solved for, so the trip still lands on its point: a fall
## takes a little longer than free fall, and a flick
## starts a little harder.
func _solve_return_flight(
	from_point: Vector2,
	to_point: Vector2,
) -> Array:
	var gravity := maxf(
		G.settings.default_gravity_acceleration,
		1.0,
	)
	var displacement := to_point - from_point
	var drag := maxf(G.settings.workable_wind_drag_per_sec, 0.0)
	var has_drag := drag >= 0.001
	if displacement.y > 1.0:
		var max_drift := maxf(
			G.settings.workable_fall_max_drift_px_per_sec,
			1.0,
		)
		if has_drag:
			return _solve_dragged_fall(
				displacement,
				gravity,
				drag,
				max_drift,
			)
		var duration_sec := sqrt(
			2.0 * displacement.y / gravity,
		)
		var velocity := Vector2(
			displacement.x / maxf(duration_sec, 0.001),
			0.0,
		)
		if absf(velocity.x) > max_drift:
			duration_sec = absf(displacement.x) / max_drift
			velocity = Vector2(
				signf(displacement.x) * max_drift,
				(
					displacement.y
					- 0.5 * gravity * duration_sec * duration_sec
				)
				/ maxf(duration_sec, 0.001),
			)
		return [velocity, duration_sec]
	var distance := displacement.length()
	var peak_px := clampf(
		distance * 0.35,
		G.settings.workable_flick_peak_min_px,
		G.settings.workable_flick_peak_max_px,
	)
	var apex_y := to_point.y - peak_px
	var rise_px := maxf(from_point.y - apex_y, 1.0)
	var up_velocity := -sqrt(2.0 * gravity * rise_px)
	var up_sec := absf(up_velocity) / gravity
	var down_sec := sqrt(2.0 * peak_px / gravity)
	var flick_duration_sec := up_sec + down_sec
	if has_drag:
		var terminal := gravity / drag
		var reach := _drag_reach(flick_duration_sec, drag)
		return [
			Vector2(
				displacement.x / reach,
				terminal
				+ (displacement.y - terminal * flick_duration_sec)
				/ reach,
			),
			flick_duration_sec,
		]
	return [
		Vector2(
			displacement.x / maxf(flick_duration_sec, 0.001),
			up_velocity,
		),
		flick_duration_sec,
	]


## A fall from rest under wind drag, solved the same way:
## the time a dropped piece takes to fall the gap, found a
## step at a time from the drag's own fall curve, and the
## sideways speed that covers the sideways gap in it.
func _solve_dragged_fall(
	displacement: Vector2,
	gravity: float,
	drag: float,
	max_drift: float,
) -> Array:
	var terminal := gravity / drag
	var duration_sec := sqrt(
		2.0 * displacement.y / gravity,
	)
	for step in 16:
		var reach := _drag_reach(duration_sec, drag)
		var fallen := terminal * (duration_sec - reach)
		var fall_speed := terminal * (
			1.0 - exp(-drag * duration_sec)
		)
		var error := fallen - displacement.y
		if absf(error) < 0.01:
			break
		duration_sec -= error / maxf(fall_speed, 1.0)
		duration_sec = maxf(duration_sec, 0.01)
	var reach := _drag_reach(duration_sec, drag)
	var velocity := Vector2(displacement.x / reach, 0.0)
	if absf(velocity.x) > max_drift:
		velocity.x = signf(displacement.x) * max_drift
		var ratio := displacement.x * drag / velocity.x
		if ratio < 0.999:
			duration_sec = -log(1.0 - ratio) / drag
			reach = _drag_reach(duration_sec, drag)
		velocity.y = (
			terminal
			+ (displacement.y - terminal * duration_sec) / reach
		)
	return [velocity, duration_sec]


## Moves every piece on its way back by one physics step:
## gravity in the air, then a bounce whose height follows
## the landing speed and a skid that friction slows, both
## smaller for a bigger piece, until the piece rests.
func _step_bench_returns(delta: float) -> void:
	if _bench_returns.is_empty() or delta <= 0.0:
		return
	for index in range(_bench_returns.size() - 1, -1, -1):
		var entry := _bench_returns[index] as Dictionary
		# Checked before the casts: a freed owner can't be cast.
		if (
			not is_instance_valid(entry.get("owner"))
			or not is_instance_valid(entry.get("node"))
		):
			_bench_returns.remove_at(index)
			continue
		var owner := entry.get("owner") as Object
		match entry.get("phase") as int:
			_RETURN_FLYING:
				_step_return_flight(entry, delta)
			_RETURN_THROWN:
				_step_return_thrown(entry, delta)
			_RETURN_GUIDED:
				_step_return_guided(entry, delta)
			_:
				_step_return_settling(entry, delta)
		if (entry.get("phase") as int) == -1:
			_bench_returns.remove_at(index)
		elif _is_at_ship_spot(owner as Repairable):
			_bench_returns.remove_at(index)
			var item := owner as Repairable
			item.is_returning = false
			_ship(item)


## True when a finished item is over where it leaves from: the outbox, or
## the shelf for the shop radio. A thrown item that touches it on its way
## back to the bench goes as if it were dropped there.
func _is_at_ship_spot(item: Repairable) -> bool:
	if not is_instance_valid(item) or not item.has_finished:
		return false
	if item.is_shop_radio:
		return %Radio.is_over_spot(_get_outer_art_center(item))
	return %Outbox.overlaps_area(item.drop_area)


func _ship(item: Repairable) -> void:
	if item.is_shop_radio:
		_return_shop_radio(item)
	else:
		_send_to_outbox(item)


func _step_return_flight(entry: Dictionary, delta: float) -> void:
	var velocity := _apply_air(
		entry.get("velocity") as Vector2,
		delta,
	)
	entry["velocity"] = velocity
	var middle := entry.get("middle") as Vector2
	middle += velocity * delta
	var flight_left_sec := (
		entry.get("flight_left_sec") as float
	)
	flight_left_sec -= delta
	entry["flight_left_sec"] = flight_left_sec
	var moving_node := entry.get("node") as Node2D
	var offset := entry.get("offset") as Vector2
	var does_spin := entry.get("does_spin") as bool
	if does_spin:
		moving_node.rotation += (
			entry.get("angular_velocity") as float
		) * delta
	elif moving_node is Repairable:
		# A finished item tilts with its sideways speed in
		# the air and straightens as it lands.
		moving_node.rotation = clampf(
			velocity.x * 0.0004,
			-deg_to_rad(8.0),
			deg_to_rad(8.0),
		)
	if flight_left_sec > 0.0:
		entry["middle"] = middle
		moving_node.global_position = middle - offset
		return
	# The solved flight ends on its landing point. Any step
	# past it is the landing itself, not more travel.
	middle = entry.get("target") as Vector2
	entry["middle"] = middle
	_land_bench_return(entry, velocity)
	moving_node.global_position = middle - offset


## One step of a throw. Gravity pulls it down, the sides
## of the viewport bounce it back in, and the top is open.
## Falling into the workable area lands it there. Falling
## past the bottom of the workable area, or flying for too
## long, hands it to the guided slide instead, so it still
## comes to rest inside.
func _step_return_thrown(entry: Dictionary, delta: float) -> void:
	var velocity := _apply_air(
		entry.get("velocity") as Vector2,
		delta,
	)
	var middle := entry.get("middle") as Vector2
	middle += velocity * delta
	var wall_left := entry.get("wall_left") as float
	var wall_right := entry.get("wall_right") as float
	if middle.x < wall_left:
		middle.x = wall_left
		velocity.x = absf(velocity.x) * _RETURN_WALL_RESTITUTION
	elif middle.x > wall_right:
		middle.x = wall_right
		velocity.x = -absf(velocity.x) * _RETURN_WALL_RESTITUTION
	entry["velocity"] = velocity
	entry["middle"] = middle
	var elapsed := (entry.get("flight_elapsed_sec") as float) + delta
	entry["flight_elapsed_sec"] = elapsed
	var moving_node := entry.get("node") as Node2D
	var offset := entry.get("offset") as Vector2
	var radius_px := entry.get("radius_px") as float
	if entry.get("does_spin") as bool:
		entry["angular_velocity"] = clampf(
			velocity.x / maxf(radius_px, 8.0),
			-6.0,
			6.0,
		) * 0.4
		moving_node.rotation += (
			entry.get("angular_velocity") as float
		) * delta
	elif moving_node is Repairable:
		moving_node.rotation = clampf(
			velocity.x * 0.0004,
			-deg_to_rad(8.0),
			deg_to_rad(8.0),
		)
	moving_node.global_position = middle - offset
	var margin_px := entry.get("margin_px") as float
	if (
		velocity.y > 0.0
		and is_inside_workable_area(middle, margin_px)
	):
		entry["middle"] = middle
		entry["target"] = middle
		_land_bench_return(entry, velocity)
		moving_node.global_position = middle - offset
		return
	if (
		velocity.y > 0.0
		and (
			middle.y > (entry.get("workable_bottom") as float)
			or elapsed > _RETURN_THROW_MAX_SEC
		)
	):
		_start_return_guided(entry)


## Starts the guided slide: a smooth path that leaves along
## the speed the piece has now and eases into its rest
## point inside the workable area, where it lands with the
## speed it was guided in at.
func _start_return_guided(entry: Dictionary) -> void:
	var middle := entry.get("middle") as Vector2
	var velocity := entry.get("velocity") as Vector2
	var rest_target := entry.get("rest_target") as Vector2
	if rest_target == Vector2.INF:
		rest_target = get_workable_area_target(
			middle,
			entry.get("margin_px") as float,
		)
	entry["target"] = rest_target
	entry["guided_from"] = middle
	entry["guided_velocity"] = velocity
	entry["guided_elapsed_sec"] = 0.0
	var distance := middle.distance_to(rest_target)
	var speed := maxf(velocity.length(), 400.0)
	entry["guided_duration_sec"] = clampf(
		distance / speed,
		0.35,
		0.9,
	)
	entry["phase"] = _RETURN_GUIDED


## One step of the guided slide. The path is a cubic that
## starts along the thrown speed and arrives at the rest
## point with no speed left, so the turn back toward the
## bench never snaps.
func _step_return_guided(entry: Dictionary, delta: float) -> void:
	var elapsed := (
		(entry.get("guided_elapsed_sec") as float) + delta
	)
	entry["guided_elapsed_sec"] = elapsed
	var duration := entry.get("guided_duration_sec") as float
	var weight := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var from_point := entry.get("guided_from") as Vector2
	var from_velocity := entry.get("guided_velocity") as Vector2
	var target := entry.get("target") as Vector2
	var weight_squared := weight * weight
	var weight_cubed := weight_squared * weight
	var middle := (
		(2.0 * weight_cubed - 3.0 * weight_squared + 1.0)
		* from_point
		+ (weight_cubed - 2.0 * weight_squared + weight)
		* duration
		* from_velocity
		+ (-2.0 * weight_cubed + 3.0 * weight_squared) * target
	)
	entry["middle"] = middle
	var moving_node := entry.get("node") as Node2D
	var offset := entry.get("offset") as Vector2
	moving_node.global_position = middle - offset
	if entry.get("does_spin") as bool:
		moving_node.rotation += (
			entry.get("angular_velocity") as float
		) * delta
	if weight < 1.0:
		return
	var guided_velocity := entry.get("guided_velocity") as Vector2
	var impact := Vector2(
		guided_velocity.x * 0.5,
		clampf(absf(guided_velocity.y), 250.0, 900.0),
	)
	entry["middle"] = target
	_land_bench_return(entry, impact)
	moving_node.global_position = target - offset


## The landing: the downward speed becomes a bounce up and
## a skid across the bench. A slow landing only skids. A
## bigger piece keeps less of both. The owner's landing
## sound plays here, at the first impact, not when the
## piece finally comes to rest after its bounce and skid.
func _land_bench_return(
	entry: Dictionary,
	impact_velocity: Vector2,
) -> void:
	if not (entry.get("has_landed") as bool):
		entry["has_landed"] = true
		var owner := entry.get("owner") as Object
		if owner is Part:
			(owner as Part).play_landing_sound()
		elif owner is BrokenPiece:
			(owner as BrokenPiece).play_landing_sound()
		elif owner is Screw:
			(owner as Screw).play_landing_sound()
	var target := entry.get("target") as Vector2
	entry["ground"] = target
	entry["phase"] = _RETURN_SETTLING
	var downward_speed := maxf(impact_velocity.y, 0.0)
	var bounce_velocity := 0.0
	if (
		downward_speed
		>= G.settings.workable_bounce_min_speed_px_per_sec
	):
		bounce_velocity = (
			downward_speed * (entry.get("restitution") as float)
		)
	entry["bounce_velocity"] = bounce_velocity
	entry["bounce_height_px"] = 0.0
	var ground_velocity := Vector2(
		impact_velocity.x * _RETURN_SKID_SIDE_SHARE,
		downward_speed * _RETURN_SKID_DOWN_SHARE,
	)
	entry["ground_velocity"] = ground_velocity
	var radius_px := entry.get("radius_px") as float
	entry["angular_velocity"] = (
		clampf(
			ground_velocity.x / maxf(radius_px, 8.0),
			-6.0,
			6.0,
		)
		* G.settings.workable_spin_factor
	)


func _step_return_settling(
	entry: Dictionary,
	delta: float,
) -> void:
	var gravity := maxf(
		G.settings.default_gravity_acceleration,
		1.0,
	)
	var bounce_height_px := entry.get("bounce_height_px") as float
	var bounce_velocity := entry.get("bounce_velocity") as float
	if bounce_height_px > 0.0 or bounce_velocity > 0.0:
		bounce_velocity -= gravity * delta
		var drag := maxf(G.settings.workable_wind_drag_per_sec, 0.0)
		if drag > 0.0:
			bounce_velocity *= exp(-drag * delta)
		bounce_height_px += bounce_velocity * delta
		if bounce_height_px <= 0.0:
			bounce_height_px = 0.0
			var impact_speed := absf(bounce_velocity)
			if (
				impact_speed
				< G.settings.workable_bounce_min_speed_px_per_sec
			):
				bounce_velocity = 0.0
			else:
				bounce_velocity = (
					impact_speed
					* (entry.get("restitution") as float)
				)
		entry["bounce_height_px"] = bounce_height_px
		entry["bounce_velocity"] = bounce_velocity
	var ground := entry.get("ground") as Vector2
	var ground_velocity := entry.get("ground_velocity") as Vector2
	var moving_node := entry.get("node") as Node2D
	var does_spin := entry.get("does_spin") as bool
	if ground_velocity.length() > 0.5:
		ground += ground_velocity * delta
		var deceleration := entry.get("skid_deceleration") as float
		ground_velocity = ground_velocity.move_toward(
			Vector2.ZERO,
			deceleration * delta,
		)
		entry["ground_velocity"] = ground_velocity
		if does_spin:
			# The spin follows the skid as it slows, so a
			# smaller piece turns faster and stops with it.
			var radius_px := entry.get("radius_px") as float
			entry["angular_velocity"] = (
				clampf(
					ground_velocity.x / maxf(radius_px, 8.0),
					-6.0,
					6.0,
				)
				* G.settings.workable_spin_factor
			)
			moving_node.rotation += (
				entry.get("angular_velocity") as float
			) * delta
		# The skid never carries the piece back out. It
		# stops at the edge instead.
		var clamped := get_workable_area_target(
			ground,
			entry.get("margin_px") as float,
		)
		if clamped != ground:
			ground = clamped
			entry["ground_velocity"] = Vector2.ZERO
			ground_velocity = Vector2.ZERO
		entry["ground"] = ground
	elif does_spin:
		entry["angular_velocity"] = 0.0
	var offset := entry.get("offset") as Vector2
	moving_node.global_position = (
		ground - offset + Vector2(0.0, -bounce_height_px)
	)
	if (
		bounce_height_px <= 0.0
		and bounce_velocity <= 0.0
		and ground_velocity.length() <= 0.5
	):
		_finish_bench_return(entry)


## The piece has come to rest inside the workable area.
## Its own finish clears its return flag and settles its
## turn, and the entry is dropped by the caller.
func _finish_bench_return(entry: Dictionary) -> void:
	var ground := entry.get("ground") as Vector2
	var offset := entry.get("offset") as Vector2
	var moving_node := entry.get("node") as Node2D
	if is_instance_valid(moving_node):
		moving_node.global_position = ground - offset
		moving_node.reset_physics_interpolation()
	var owner := entry.get("owner") as Object
	if owner is Part:
		(owner as Part).finish_bench_return()
	elif owner is BrokenPiece:
		(owner as BrokenPiece).finish_bench_return()
	elif owner is Screw:
		(owner as Screw).finish_bench_return()
	elif owner is RepairLayer:
		(owner as RepairLayer).finish_bench_return()
	elif owner is Repairable:
		(owner as Repairable).finish_bench_return()
	entry["phase"] = -1


## Notes a screw as resting loose on the bench, wherever the player
## left it, so presses can find it.
func register_resting_screw(screw: Screw) -> void:
	if not _resting_screws.has(screw):
		_resting_screws.append(screw)


## Gives `screw` the first free rest spot on the bench, or the one it
## already has, and returns that spot's world position.
func take_screw_rest_spot(screw: Screw) -> Vector2:
	var index := _resting_screws.find(screw)
	if index < 0:
		index = 0
		while (
			index < _resting_screws.size()
			and is_instance_valid(_resting_screws[index])
		):
			index += 1
		if index == _resting_screws.size():
			_resting_screws.append(screw)
		else:
			_resting_screws[index] = screw
	return get_screw_rest_position(index)


## Frees the rest spot of `screw`, if it has one.
func free_screw_rest_spot(screw: Screw) -> void:
	var index := _resting_screws.find(screw)
	if index >= 0:
		_resting_screws[index] = null


## The world position of rest spot number `index`, counting from 0.
## The row starts at the `%ScrewSetAsideSpot` marker.
func get_screw_rest_position(index: int) -> Vector2:
	var row_size := maxi(G.settings.screw_rest_row_size, 1)
	return (
		(%ScrewSetAsideSpot as Node2D).global_position
		+ G.settings.screw_rest_step * (index % row_size)
		+ G.settings.screw_rest_row_step * floori(float(index) / row_size)
	)


## The resting screw that a press at a world position would bring back,
## or null.
func get_resting_screw_at(global_point: Vector2) -> Screw:
	for entry: Variant in _resting_screws:
		if not is_instance_valid(entry):
			continue
		var screw := entry as Screw
		if screw.has_rest_point(global_point):
			return screw
	return null


## Adds a decal of `kind` to `part` and returns it, or null if it can't.
## The arguments are those of `DecalSpawner.spawn()`.
func spawn_decal(
	kind: DecalSpawner.Kind,
	part: CanvasItem,
	world_position: Vector2,
	size: float,
	direction := Vector2.RIGHT,
) -> Sprite2D:
	return (%Decals as DecalSpawner).spawn(
		kind,
		part,
		world_position,
		size,
		direction,
	)


## Spews `count` bench dust clumps around a world position
## and returns them. A hard knock on an item (a hammer whack
## on the TV) calls this. The clumps live on the bench, not on
## the item, until the air blower cleans them or the item
## finishes and `charge_bench_dust()` pays for what is left.
func spawn_bench_dust(
	global_pos: Vector2, count: int
) -> Array[BenchDust]:
	var spawned: Array[BenchDust] = []
	_prune_bench_dust()
	for index in maxi(count, 0):
		var dust := _BENCH_DUST_SCENE.instantiate() as BenchDust
		if not G.check(is_instance_valid(dust)):
			continue
		dust.amount = randf_range(0.8, 1.0)
		_get_bench_dust_holder().add_child(dust)
		var target := global_pos
		if count > 1:
			var angle := TAU * float(index) / float(count)
			angle += randf_range(-0.35, 0.35)
			var radius := randf_range(14.0, _BENCH_DUST_SPREAD_PX)
			target += Vector2.from_angle(angle) * radius
		dust.global_position = clamp_to_bench(target)
		dust.reset_physics_interpolation()
		_bench_dust.append(dust)
		spawned.append(dust)
	return spawned


## Every bench dust clump still tracked, cleaned ones
## included until they are cleared or freed.
func get_bench_dust() -> Array[BenchDust]:
	_prune_bench_dust()
	var dusts: Array[BenchDust] = []
	for entry: Variant in _bench_dust:
		dusts.append(entry as BenchDust)
	return dusts


## How many bench dust clumps still need cleaning.
func count_bench_dust_left() -> int:
	var left := 0
	for dust in get_bench_dust():
		if dust.mode != InteractionPoint.Mode.FINISHED:
			left += 1
	return left


## Frees every bench dust clump, cleaned or not.
func clear_bench_dust() -> void:
	for entry: Variant in _bench_dust:
		if is_instance_valid(entry):
			(entry as Node).queue_free()
	_bench_dust.clear()


## Charges an item for each bench dust clump left uncleaned
## and returns how many were charged. Each clump costs
## `Settings.bench_dust_points` as a `BENCH_DUST_LEFT`
## defect. A clump is charged at most once, and cleaned
## clumps cost nothing. Call `clear_bench_dust()` when the
## bench resets for the next item.
func charge_bench_dust(item: Repairable) -> int:
	if not is_instance_valid(item):
		return 0
	var charged := 0
	for dust in get_bench_dust():
		if dust.mode == InteractionPoint.Mode.FINISHED:
			continue
		if dust.is_charged:
			continue
		dust.is_charged = true
		item.quality.add_defect(
			RepairQuality.Defect.BENCH_DUST_LEFT,
			dust.global_position,
			dust,
		)
		charged += 1
	return charged


## The node bench dust lives under, made on first use. It
## draws the dust over the bench and under the tools.
func _get_bench_dust_holder() -> Node2D:
	var holder := get_node_or_null("BenchDust") as Node2D
	if not is_instance_valid(holder):
		holder = Node2D.new()
		holder.name = "BenchDust"
		holder.z_index = 2
		add_child(holder)
	return holder


## Drops freed clumps from the bench dust list.
func _prune_bench_dust() -> void:
	for index in range(_bench_dust.size() - 1, -1, -1):
		if not is_instance_valid(_bench_dust[index]):
			_bench_dust.remove_at(index)


## Builds the played order from the authored queue and the
## first-repairable override: the override (if any) goes
## first, and its authored slot is skipped.
func _build_effective_queue() -> void:
	_effective_queue.clear()
	var override := G.settings.get_first_repairable_override()
	var has_override := override >= 0
	var override_type: Repairable.Type = Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE
	if has_override:
		override_type = override
		_effective_queue.append(override_type)
	for type in G.settings.item_queue:
		if has_override and type == override_type:
			continue
		_effective_queue.append(type)


## True once every item of the day's order has been spawned.
func _is_queue_finished() -> bool:
	return next_item_index >= _effective_queue.size()


func _spawn_next_item() -> void:
	if _is_queue_finished():
		return
	var type: Repairable.Type = _effective_queue[next_item_index]
	next_item_index += 1
	spawn_repairable(type)


## The item leaves through the outbox. The bench is empty from here until
## the next item arrives.
func _send_to_outbox(item: Repairable) -> void:
	set_outbox_outline_shown(false)
	cleanup_loose_parts()
	cleanup_broken_pieces(item)
	active_repairable = null
	item.departed.connect(_on_item_departed.bind(item), CONNECT_ONE_SHOT)
	item.leave(
		%Outbox.global_position,
		%OutboxExitPosition.global_position,
	)


## The shop radio breaks on the shelf. After a beat it flies down to the
## bench as the item, which starts out lined up with it.
func _break_shop_radio(item: Repairable) -> void:
	var bench_scale := item.scale
	_shop_radio_pose = _get_shop_radio_pose(item)
	item.scale = _shop_radio_pose.get_scale()
	item.global_position = _shop_radio_pose.origin
	item.visible = false
	item.finished.connect(G.audio.restore_main_theme)
	%Radio.break_away()
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_interval(G.settings.shop_radio_break_sec)
	tween.tween_callback(_fly_in_shop_radio.bind(bench_scale))


func _fly_in_shop_radio(bench_scale: Vector2) -> void:
	var item := active_repairable
	if not is_instance_valid(item) or not item.is_shop_radio:
		return
	%Radio.leave_shelf()
	item.visible = true
	item.fly_in(%ActiveItemPosition.global_position, bench_scale)


## The fixed shop radio flies back up to its shelf.
func _return_shop_radio(item: Repairable) -> void:
	set_outbox_outline_shown(false)
	item.set_art_scale(Vector2.ONE)
	cleanup_loose_parts()
	cleanup_broken_pieces(item)
	active_repairable = null
	item.departed.connect(%Radio.return_to_shelf, CONNECT_ONE_SHOT)
	item.departed.connect(_on_item_departed.bind(item), CONNECT_ONE_SHOT)
	item.fly_out(_shop_radio_pose.origin, _shop_radio_pose.get_scale())


## Once the music is back, the radio on the bench bounces to it like the
## one on the shelf does.
func _bounce_shop_radio() -> void:
	var item := active_repairable
	if (
		is_instance_valid(item)
		and item.is_shop_radio
		and item.has_finished
	):
		item.set_art_scale(%Radio.get_beat_scale())


## The item's position and scale that line its outermost art up with the
## shop radio's art on the shelf.
func _get_shop_radio_pose(item: Repairable) -> Transform2D:
	var art := item.layers.back().art as Node2D
	var ratio: float = %Radio.get_art_scale() / art.global_scale.x
	var art_offset := _get_outer_art_center(item) - item.global_position
	return Transform2D(
		0.0,
		item.scale * ratio,
		0.0,
		%Radio.get_art_center() - art_offset * ratio,
	)


func _get_outer_art_center(item: Repairable) -> Vector2:
	var art := item.layers.back().art as Node2D
	if art is Sprite2D:
		return art.to_global((art as Sprite2D).offset)
	return art.global_position


func _on_item_impacted(strength: float) -> void:
	shake_camera(
		G.settings.item_landing_shake_px * strength,
		G.settings.item_landing_shake_sec,
	)


func _on_item_landed(item: Repairable) -> void:
	restock_parts(item)
	%TicketCard.show_item(item.ticket, item.is_shop_radio)
	G.audio.play_sound_delayed(&"hmm_curious", 0.45)


## The item slid off the screen: its ticket comes up as the receipt,
## with the repair time and the rating stamp.
func _on_item_departed(item: Repairable) -> void:
	G.session.fixed_item_count += 1
	%TicketCard.show_done(
		item.quality.repair_time_sec,
		item.quality.get_stars(),
	)


## A drawer finished opening in the center: its stored parts
## fade in at random spots inside it.
func _on_drawer_opened(drawer: Drawer) -> void:
	for part in get_parts_in_drawer(drawer):
		part.global_position = (
			drawer.get_random_interior_global_position()
		)
		part.z_index = 16
	_fade_drawer_parts(drawer, true)


## A drawer started to close: its stored parts fade out before
## the wrapper slides back and the animation reverses.
func _on_drawer_close_started(drawer: Drawer) -> void:
	_fade_drawer_parts(drawer, false)


## Fades a drawer's stored parts in, or out and then hidden.
## The fade that ends hidden restores full opacity, so a part
## taken out or put away never keeps a leftover fade.
func _fade_drawer_parts(drawer: Drawer, is_fading_in: bool) -> void:
	var parts := get_parts_in_drawer(drawer)
	var old := _part_fade_tweens.get(drawer) as Tween
	if is_instance_valid(old):
		old.kill()
	_part_fade_tweens.erase(drawer)
	if parts.is_empty():
		return
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_parallel()
	_part_fade_tweens[drawer] = tween
	var fade_sec := G.settings.part_fade_sec
	if not is_fading_in:
		fade_sec *= 0.5
	for part in parts:
		if is_fading_in:
			part.modulate.a = 0.0
			part.show()
		tween.tween_property(
			part,
			"modulate:a",
			1.0 if is_fading_in else 0.0,
			fade_sec,
		)
	if is_fading_in:
		return
	tween.chain().tween_callback(
		func() -> void:
			for part in parts:
				if is_instance_valid(part):
					part.hide()
					part.modulate.a = 1.0
	)


func _on_defect_added(
	_defect: RepairQuality.Defect,
	points: int,
	world_position: Vector2,
) -> void:
	G.audio.play_sound(&"hmm_frustrated")
	DefectPopup.spawn(self, points, world_position)


## The receipt left. The next item arrives a moment later, or, after the
## last item, the game is won.
func _on_ticket_done_closed() -> void:
	if _is_queue_finished():
		if not is_instance_valid(active_repairable):
			win()
		return
	var tween := create_tween()
	tween.tween_interval(G.settings.next_item_delay_sec)
	tween.tween_callback(_spawn_next_item)
