class_name GamePanel
extends Node2D


var level: Level


func _enter_tree() -> void:
	G.game_panel = self
	G.session = Session.new()


func start_game() -> void:
	G.session.reset()
	G.session.is_game_over = false

	if is_instance_valid(level):
		# A level already exists, so reload it and reset all
		# transient state together.
		restart_level()
	else:
		start_level()


func end_game() -> void:
	G.session.is_game_over = true


func start_level() -> void:
	if is_instance_valid(level):
		return
	var level_scene := G.settings.default_level_scene
	if not G.level_scene_override_path.is_empty():
		# The path is only known at runtime, so it can't be an export.
		level_scene = load(G.level_scene_override_path)
	level = level_scene.instantiate()
	add_child(level)


## Tears down the current Level node and spawns a fresh instance, so
## any damage, dropped items, and other transient state all reset
## together.
func restart_level() -> void:
	if is_instance_valid(level):
		level.queue_free()
		level = null
	# Deferred so the old Level is fully out of the tree (and its
	# signal connections torn down) before the new one enters.
	call_deferred("start_level")
