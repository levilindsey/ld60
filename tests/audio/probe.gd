extends "res://tests/probe_base.gd"
## The intro humming (foley round 2). Boots the game on the title,
## closes it into a run and checks the humming plays once, stops, and
## does not come back on a pause resume. A fresh run from the credits
## plays it again.
##
## Run it with `tests/run.ps1 -Name audio`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/audio/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0

var _humming: AudioStreamPlayer
var _main_theme: AudioStreamPlayer


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.5)
	_expect(G.state.state == StateMain.State.TITLE, "boot shows the title")
	_humming = (
		G.audio.STREAM_PLAYERS_BY_NAME.get(&"humming") as AudioStreamPlayer
	)
	_main_theme = (
		G.audio.STREAM_PLAYERS_BY_NAME[&"main_theme"] as AudioStreamPlayer
	)
	if not _expect(
		is_instance_valid(_humming) and is_instance_valid(_humming.stream),
		"the humming sound has a stream",
	):
		return
	_expect(
		_humming.stream.resource_path.ends_with("humming.wav"),
		"the humming stream is humming.wav",
	)
	_expect(
		not is_instance_valid(_main_theme.stream)
		or _main_theme.stream != _humming.stream,
		"the main theme does not carry the humming",
	)
	_expect(not _humming.playing, "the humming is silent on the title")

	# Close the title. The humming starts, once.
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.4)
	_expect(_humming.playing, "the humming plays when the title closes")

	var take_sec := _humming.stream.get_length()
	var waited_sec := 0.0
	while _humming.playing and waited_sec < take_sec + 3.0:
		await _seconds(0.25)
		waited_sec += 0.25
	_expect(
		not _humming.playing,
		"the humming stops after one take and does not loop",
	)
	await _seconds(take_sec)
	_expect(not _humming.playing, "the humming does not restart")

	# A pause resume is not a new run. No second humming.
	G.state.transition(StateMain.State.PAUSE)
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.4)
	_expect(not _humming.playing, "a pause resume does not replay it")

	# A fresh run from the credits starts with it again.
	G.state.transition(StateMain.State.CREDITS)
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.4)
	_expect(_humming.playing, "a fresh run plays the humming again")
