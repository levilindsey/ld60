class_name Scaffolder
extends Node


const _REQUIRED_INPUT_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"jump",
	&"ability",
	&"pause",
]


static func set_up() -> void:
	_validate_project_settings_input_actions()


## Catches project.godot edits that drop an input action the code
## expects. Fails loudly at boot instead of silently at first use.
static func _validate_project_settings_input_actions() -> void:
	for action in _REQUIRED_INPUT_ACTIONS:
		if not InputMap.has_action(action):
			G.error("Missing project.godot input action: %s" % action)
