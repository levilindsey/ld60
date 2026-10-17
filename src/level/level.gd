class_name Level
extends Node2D


const _GAME_OVER_RESTART_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2.ZERO


var has_started := false
var has_won := false

var tools_by_type: Dictionary[Tool.Type, Tool] = {}
var active_repairable: Repairable

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

	# TODO: Add some level and spawn configs to control when what things spawn.
	spawn_tool(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	spawn_repairable(Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE)


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


func spawn_repairable(type: Repairable.Type) -> void:
	G.check(not is_instance_valid(active_repairable))

	var item_scene := G.settings.get_repairable_scene_from_type(type)
	G.check(is_instance_valid(item_scene))
	var item: Repairable = item_scene.instantiate()
	%Repairables.add_child(item)
	item.global_position = %ItemSpawnPosition.global_position
	active_repairable = item

	var initial_rotation := randf() * TAU
	item.rotation = initial_rotation

	# Give repairables a slight rotation offset.
	var target_rotation := randf_range(
		-Repairable.ROTATION_OFFSET_MAX,
		Repairable.ROTATION_OFFSET_MAX,
	)

	var target_position: Vector2 = %ActiveItemPosition.global_position

	item.tween_rotation(target_rotation, Tween.EASE_IN)
	item.tween_position(target_position, Tween.EASE_IN)

	await get_tree().create_timer(Repairable.POSITION_DURATION_SEC).timeout

	%CameraShaker.shake_camera(7.0, 0.15)


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
