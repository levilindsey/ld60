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


func _enter_tree() -> void:
	if not is_instance_valid(G.main):
		# This level scene was run directly. Boot the full game into it.
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

	%Receipt.closed.connect(_on_receipt_closed)

	# TODO: Add some level and spawn configs to control when what things spawn.
	spawn_tool(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
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
	G.state.transition(StateMain.State.CREDITS)


func spawn_tool(type: Tool.Type) -> void:
	G.check(not tools_by_type.has(type))

	var tool_scene := G.settings.get_tool_scene_from_type(type)
	G.check(is_instance_valid(tool_scene))
	var tool: Tool = tool_scene.instantiate()
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


## Where layers wait while they are off the item.
func get_set_aside_spot() -> Node2D:
	return %SetAsideSpot


## The layers at the set-aside spot, bottom of the stack first.
func get_set_aside_layers() -> Array[RepairLayer]:
	var layers: Array[RepairLayer] = []
	for child in %SetAsideSpot.get_children():
		if child is RepairLayer:
			layers.append(child as RepairLayer)
	return layers


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
	active_repairable = null
	%TicketCard.hide_card()
	item.departed.connect(_on_item_departed.bind(item), CONNECT_ONE_SHOT)
	item.leave(
		%Outbox.global_position,
		%OutboxExitPosition.global_position,
	)


func _on_item_landed(item: Repairable) -> void:
	shake_camera(
		G.settings.item_landing_shake_px,
		G.settings.item_landing_shake_sec,
	)
	%TicketCard.show_item(item.item_name, item.ticket)


## The item slid off the screen: its receipt opens and, unless that was
## the last item, the next one arrives a moment later. The game is won
## when the last receipt closes.
func _on_item_departed(item: Repairable) -> void:
	%Receipt.open(item.item_name, item.quality)
	if _is_queue_finished():
		return
	var tween := create_tween()
	tween.tween_interval(G.settings.next_item_delay_sec)
	tween.tween_callback(_spawn_next_item)


func _on_defect_added(
	_defect: RepairQuality.Defect,
	points: int,
	world_position: Vector2,
) -> void:
	DefectPopup.spawn(self, points, world_position)


func _on_receipt_closed() -> void:
	# Only the last item's receipt ends the game.
	if _is_queue_finished() and not is_instance_valid(active_repairable):
		win()
