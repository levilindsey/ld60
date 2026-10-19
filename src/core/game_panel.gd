class_name GamePanel
extends Node2D


var level: Level

## True while `level` is a warmed-up instance waiting behind
## the title screen, not a game in progress.
var _is_level_preloaded := false


func _enter_tree() -> void:
	G.game_panel = self
	G.session = Session.new()


func start_game() -> void:
	G.session.reset()
	G.session.is_game_over = false

	if _is_level_preloaded:
		# The level is already built behind the title; just
		# reveal it, unless the schedule changed after the
		# warm-up (a probe retuning the queue), which needs a
		# fresh build.
		_is_level_preloaded = false
		if is_instance_valid(level) and not level.is_schedule_stale():
			level.show_with_camera()
		else:
			_rebuild_level_now()
	elif is_instance_valid(level):
		# A level already exists, so reload it and reset all
		# transient state together.
		restart_level()
	else:
		start_level()


## Builds the level while the title screen shows, hidden, so
## starting the game has no load hitch. The tree is paused on
## the title, so the level waits frozen until the game starts.
## Skipped for a run-current-scene level, which loads its own.
func preload_level() -> void:
	if is_instance_valid(level):
		return
	if not G.level_scene_override_path.is_empty():
		return
	start_level()
	if is_instance_valid(level):
		level.hide()
		_is_level_preloaded = true


## Shows the warmed-up level. The title's enter animation calls
## this as the exterior starts to fade, so the shop is already
## showing underneath the last of the fade.
func reveal_preloaded_level() -> void:
	if _is_level_preloaded and is_instance_valid(level):
		level.show_with_camera()


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


## Tears the warmed-up level down and builds a fresh one in the
## same frame. `restart_level` defers its spawn, but a game start
## has no level callback on the stack, and its caller expects
## `G.level` to be the new level when it returns.
func _rebuild_level_now() -> void:
	var stale := level
	level = null
	remove_child(stale)
	stale.free()
	start_level()


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
