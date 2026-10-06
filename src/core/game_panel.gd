class_name GamePanel
extends Node2D


var level: Level


func _enter_tree() -> void:
	G.game_panel = self
	G.session = Session.new()


func start_game() -> void:
	G.session.reset()
	G.session.is_game_ended = false

	if is_instance_valid(level):
		# Replay after a finished run: reload the level so all
		# transient state resets together.
		restart_level()
	else:
		start_level()


func end_game() -> void:
	G.session.is_game_ended = true


func start_level() -> void:
	if is_instance_valid(level):
		return
	level = G.settings.default_level_scene.instantiate()
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
