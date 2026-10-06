class_name Settings
extends Resource


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

## Instantiated by `Level.spawn_player()` at %PlayerSpawnPoint. Leave
## unset until the jam's player scene exists; `Level` skips spawning
## while this is null.
@export var player_scene: PackedScene
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
