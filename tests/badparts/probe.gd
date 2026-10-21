extends "res://tests/probe_base.gd"
## Every real repairable's broken parts must show authored
## bad art, not the socket's fallback clone of the good part
## (darkened good art still reads as the good part, so the
## player yanks out a part that looks brand new). Boots the
## game, spawns each shipped item on the bench and inspects
## every socket that starts with a broken part.
##
## Run it with `tests/run.ps1 -Name badparts`, or from the
## repo root (PowerShell):
##   godot --headless --path . res://tests/badparts/probe.tscn
## Exit code 0 means every check passed.

const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

const _ITEM_TYPES: Array[Repairable.Type] = [
	Repairable.Type.TOASTER,
	Repairable.Type.ATARI_JOYSTICK,
	Repairable.Type.KEYBOARD,
	Repairable.Type.TV,
	Repairable.Type.PIANO,
	Repairable.Type.GAME_N_WATCH,
	Repairable.Type.RADIO,
	Repairable.Type.SHRINK_RAY,
]

var _level: Level


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	var main := (
		(load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
		as Main
	)
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	_level = G.level
	_hand = G.level.hand
	for item_type in _ITEM_TYPES:
		await _check_item(item_type)
	_finish(0 if _failures.is_empty() else 1)


func _check_item(item_type: Repairable.Type) -> void:
	var scene := G.settings.get_repairable_scene_from_type(item_type)
	var item := scene.instantiate() as Repairable
	_level.add_child(item)
	item.mode = Repairable.Mode.UNDER_REPAIR
	item.global_position = Vector2(0, 180)
	await _physics_frames(2)
	var item_name := item.item_name
	for layer in item.layers:
		for point in layer.get_points():
			if point is PartSocket:
				_check_socket(item_name, point as PartSocket)
	item.queue_free()
	await _physics_frames(2)


func _check_socket(item_name: String, socket: PartSocket) -> void:
	if not socket.starts_with_broken_part:
		return
	var label := "%s %s" % [item_name, socket.name]
	var broken_part := socket.get_node("BrokenPart")
	var sprites: Array[Sprite2D] = []
	for child in broken_part.get_children():
		if child is Sprite2D:
			sprites.append(child as Sprite2D)
	if not _expect(
		not sprites.is_empty(),
		"%s: the broken part has authored bad art" % label,
	):
		return
	# What the player sees at spawn is the bad part, never
	# the good one: the broken art is on show, and the fitted
	# art stays hidden until a new part lands.
	var is_bad_shown := false
	for sprite in sprites:
		if sprite.is_visible_in_tree():
			is_bad_shown = true
	_expect(
		is_bad_shown,
		"%s: the bad part shows at spawn" % label,
	)
	var fitted := socket.installed_art as Sprite2D
	if is_instance_valid(fitted):
		_expect(
			not fitted.is_visible_in_tree(),
			"%s: the good part stays hidden at spawn" % label,
		)
		# The runtime fallback adds exactly one sprite: the
		# good part's art, darkened. That (or an authored
		# copy of it) is what must never be the display.
		var first := sprites[0]
		_expect(
			first.texture != fitted.texture
			or first.region_rect != fitted.region_rect,
			"%s: the broken part is not just the good part's art"
			% label,
		)
