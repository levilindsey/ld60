class_name Level
extends Node2D


const _GAME_OVER_RESTART_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2.ZERO


var has_started := false
var has_won := false

var tools_by_type: Dictionary[Tool.Type, Tool] = {}
## The item on the bench, or null while the next one is on its way.
var active_repairable: Repairable
## How many items of `Settings.item_queue` have been spawned.
var next_item_index := 0

## The player's hand: what is held, the cursor and press routing.
var hand: Hand:
	get:
		return %Hand

## The screws resting on the bench, by rest spot (docs/design/
## screw_pullout.md). A free spot holds null or a freed screw. It is
## untyped so a freed screw never lands in a typed variable.
var _resting_screws: Array = []

var _outbox_outline_hint: OutlineHint

## Every loose part spawned for the item on the bench: stored in a
## drawer, resting on the bench, or on its way back into a drawer.
## Installed parts leave the list by flag, not by removal. It is
## untyped so a freed part never lands in a typed variable.
var _drawer_parts: Array = []

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

	var drawers := get_drawers()
	for index in drawers.size():
		var drawer := drawers[index]
		drawer.drawer_index = index
		drawer.opened.connect(_on_drawer_opened.bind(drawer))
		drawer.close_started.connect(_on_drawer_close_started.bind(drawer))

	%Receipt.closed.connect(_on_receipt_closed)

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

	# TODO: Start from an off-angle.
	tool.put_away()


## Drops an item of a type onto the bench and returns it. The camera
## shakes and the ticket appears when it lands.
func spawn_repairable(type: Repairable.Type) -> Repairable:
	G.check(not is_instance_valid(active_repairable))

	var item_scene := G.settings.get_repairable_scene_from_type(type)
	G.check(is_instance_valid(item_scene))
	var item: Repairable = item_scene.instantiate()
	%Repairables.add_child(item)
	item.global_position = %ItemSpawnPosition.global_position
	item.reset_physics_interpolation()
	active_repairable = item

	item.quality.defect_added.connect(_on_defect_added)
	item.landed.connect(_on_item_landed.bind(item))
	item.arrive(%ActiveItemPosition.global_position)
	return item


## Shakes the camera. See `CameraShaker`.
func shake_camera(amplitude_px: float, duration_sec: float) -> void:
	%CameraShaker.shake_camera(amplitude_px, duration_sec)


## The hand let go of an item. A finished item over the outbox goes into
## it. Any other drop eases the item back to the bench.
func drop_item(item: Repairable) -> void:
	if not is_instance_valid(item):
		return
	if item.has_finished and %Outbox.overlaps_area(item.drop_area):
		_send_to_outbox(item)
	else:
		return_item(item)


## Shows or hides the outline around the outbox. A finished item
## turns it on, so the bench says where the item goes next.
func set_outbox_outline_shown(is_shown: bool) -> void:
	if is_shown:
		if not is_instance_valid(_outbox_outline_hint):
			var placeholder := (
				%Outbox.get_node("Placeholder") as Polygon2D
			)
			var points := OutlineHint.get_art_polygon(placeholder)
			if points.is_empty():
				return
			_outbox_outline_hint = OutlineHint.new()
			placeholder.add_child(_outbox_outline_hint)
			_outbox_outline_hint.polygon = points
		_outbox_outline_hint.set_active(true)
	elif is_instance_valid(_outbox_outline_hint):
		_outbox_outline_hint.set_active(false)


## True while the outbox shows its outline.
func is_outbox_outline_shown() -> bool:
	return (
		is_instance_valid(_outbox_outline_hint)
		and _outbox_outline_hint.is_active()
	)


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


## Restocks the drawers for an item that just landed: the old loose
## parts go away, and a fresh set is hidden at random across the
## drawers. The set holds one part per socket the item needs, plus
## decoys, shuffled so hunting takes opening more than one drawer.
func restock_parts(item: Repairable) -> void:
	for drawer in get_drawers():
		drawer.reset_closed()
	for entry: Variant in _drawer_parts:
		if is_instance_valid(entry):
			(entry as Part).queue_free()
	_drawer_parts.clear()
	if not is_instance_valid(item):
		return
	G.check(is_instance_valid(part_scene))

	var part_types: Array[Part.Type] = []
	for layer in item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				part_types.append(
					(point as PartSocket).accepted_part
				)
	# Decoys are kinds the item does not need, when it leaves any.
	var decoy_types: Array[Part.Type] = []
	for part_type in [
		Part.Type.GEAR,
		Part.Type.TUBE,
		Part.Type.SPRING,
	]:
		if not part_types.has(part_type):
			decoy_types.append(part_type)
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


## True once every item of the day's order has been spawned.
func _is_queue_finished() -> bool:
	return next_item_index >= G.settings.item_queue.size()


func _spawn_next_item() -> void:
	if _is_queue_finished():
		return
	var type: Repairable.Type = G.settings.item_queue[next_item_index]
	next_item_index += 1
	spawn_repairable(type)


## The item leaves through the outbox. The bench is empty from here until
## the next item arrives.
func _send_to_outbox(item: Repairable) -> void:
	set_outbox_outline_shown(false)
	cleanup_loose_parts()
	active_repairable = null
	%TicketCard.hide_card()
	item.departed.connect(_on_item_departed.bind(item), CONNECT_ONE_SHOT)
	item.leave(
		%Outbox.global_position,
		%OutboxExitPosition.global_position,
	)


func _on_item_landed(item: Repairable) -> void:
	restock_parts(item)
	shake_camera(
		G.settings.item_landing_shake_px,
		G.settings.item_landing_shake_sec,
	)
	%TicketCard.show_item(item.ticket)
	G.audio.play_sound_delayed(&"hmm_curious", 0.45)


## The item slid off the screen: its receipt opens and, unless that was
## the last item, the next one arrives a moment later. The game is won
## when the last receipt closes.
func _on_item_departed(item: Repairable) -> void:
	G.session.fixed_item_count += 1
	%Receipt.open(item.item_name, item.quality)
	if _is_queue_finished():
		return
	var tween := create_tween()
	tween.tween_interval(G.settings.next_item_delay_sec)
	tween.tween_callback(_spawn_next_item)


## A drawer finished opening in the center: its stored parts
## appear at random spots inside it.
func _on_drawer_opened(drawer: Drawer) -> void:
	for part in get_parts_in_drawer(drawer):
		part.global_position = (
			drawer.get_random_interior_global_position()
		)
		part.z_index = 16
		part.show()


## A drawer started to close: its stored parts disappear before
## the wrapper slides back and the animation reverses.
func _on_drawer_close_started(drawer: Drawer) -> void:
	for part in get_parts_in_drawer(drawer):
		part.hide()


func _on_defect_added(
	_defect: RepairQuality.Defect,
	points: int,
	world_position: Vector2,
) -> void:
	G.audio.play_sound(&"hmm_frustrated")
	DefectPopup.spawn(self, points, world_position)


func _on_receipt_closed() -> void:
	# Only the last item's receipt ends the game.
	if _is_queue_finished() and not is_instance_valid(active_repairable):
		win()
