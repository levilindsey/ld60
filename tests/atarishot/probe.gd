extends "res://tests/probe_base.gd"


func _ready() -> void:
	_is_taking_screenshots = OS.get_cmdline_user_args().has("--screenshots")
	_start_timeout(60.0)
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://src/core/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _physics_frames(4)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	var item := (load("res://src/repairables/atari_repairable.tscn") as PackedScene).instantiate() as Repairable
	G.level.add_child(item)
	item.mode = Repairable.Mode.UNDER_REPAIR
	item.global_position = Vector2(0, 120)
	await _physics_frames(4)
	var socket: PartSocket = null
	for layer in item.layers:
		for p in layer.get_points():
			if p is PartSocket:
				socket = p as PartSocket
	if not _expect(is_instance_valid(socket), "the atari has a socket"):
		_finish(1)
		return
	await _shot("atari_start")
	socket._pop_out()
	await _physics_frames(40)
	await _shot("atari_empty")
	_finish(0 if _failures.is_empty() else 1)
