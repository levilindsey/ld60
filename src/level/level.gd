class_name Level
extends Node2D


const _GAME_OVER_RESTART_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2.ZERO


var has_started := false
var has_won := false

var tools_by_type: Dictionary[Tool.Type, Tool] = {}
var active_repairable: Repairable


func _enter_tree() -> void:
	G.level = self


func _exit_tree() -> void:
	if G.level == self:
		G.level = null


func _ready() -> void:
	# Center the camera's anchor on its position. In Godot 4.5+ the
	# Camera2D default changed to FIXED_TOP_LEFT, which would make
	# the player render at the top-left of the screen given our
	# follow logic in _physics_process.
	%Camera2D.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER

	# TODO: Add some level and spawn configs to control when what things spawn.
	spawn_tool(Tool.Type.FLAT_HEAD_SCREW_DRIVER)
	spawn_repairable(Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE)


func _unhandled_input(event: InputEvent) -> void:
	pass


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
	add_child(tool)
	tool.global_position = %ActiveItemPosition.global_position
	tools_by_type[type] = tool

	# TODO: Start from an off-angle.
	tool.put_away()


func spawn_repairable(type: Repairable.Type) -> void:
	G.check(not is_instance_valid(active_repairable))

	var item_scene := G.settings.get_repairable_scene_from_type(type)
	G.check(is_instance_valid(item_scene))
	var item: Repairable = item_scene.instantiate()
	add_child(item)
	item.global_position = %ItemSpawnPosition.global_position
	active_repairable = item

	var target_position: Vector2 = %ActiveItemPosition.global_position
	# TODO(levilindsey): Tween repairable position to the target position. Also tween rotation from an off-angle start.


func get_tool_holder_position(type: Tool.Type) -> Vector2:
	match type:
		Tool.Type.FLAT_HEAD_SCREW_DRIVER:
			return %FlatHeadScrewDriverHolder.global_position
		_:
			G.error()
			return Vector2.INF
