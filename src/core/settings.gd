class_name Settings
extends Resource


enum PhysicsLayer {
	NONE = 0,
	TOOLS = 1 << 0,
	REPAIRABLES = 1 << 1,
	INTERACTION_POINTS = 1 << 2,
	TABLE = 1 << 3,
	TOOL_HOLDERS = 1 << 4,
}

# --- General configuration ---

@export var dev_mode := true
@export var show_debug_console := false

@export var start_in_game := true
@export var full_screen := false
@export var move_preview_windows_to_other_display := true
@export var mute_music := false
@export var pauses_on_focus_out := true
@export var is_screenshot_hotkey_enabled := true

@export var show_hud := true

# --- Game configuration ---

@export var default_gravity_acceleration := 1400.0

@export var default_level_scene: PackedScene


@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#ScaffolderLog.CATEGORY_DEFAULT,
	#ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
	#ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	#ScaffolderLog.CATEGORY_INTERACTION,
	#ScaffolderLog.CATEGORY_BEHAVIORS,
	#ScaffolderLog.CATEGORY_GAME_STATE,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var verbosity := ScaffolderLog.Verbosity.NORMAL
@export_group("")

@export_group("Repairables")
@export var flat_head_screw_repairable_scene: PackedScene
@export_group("")

@export_group("Tools")
@export var flat_head_screw_driver_scene: PackedScene
@export_group("")


func get_repairable_scene_from_type(type: Repairable.Type) -> PackedScene:
	match type:
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE:
			return flat_head_screw_repairable_scene
		_:
			G.fatal()
			return null


func get_tool_scene_from_type(type: Tool.Type) -> PackedScene:
	match type:
		Tool.Type.FLAT_HEAD_SCREW_DRIVER:
			return flat_head_screw_driver_scene
		_:
			G.fatal()
			return null
