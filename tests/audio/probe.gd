extends "res://tests/probe_base.gd"
## The intro humming (foley round 2). Boots the game on the title,
## closes it into a run and checks the humming plays once, stops, and
## does not come back on a pause resume or after the credits. The
## credits are terminal, so they never start another run in the
## same session. It also checks a recorded defect answers with one
## of the frustrated takes (foley round 3).
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

	# A mistake answers with a frustrated hmm from the pooled takes.
	var frustrated := (
		G.audio.STREAM_PLAYERS_BY_NAME.get(&"hmm_frustrated")
		as AudioStreamPlayer
	)
	var randomizer := (
		frustrated.stream as AudioStreamRandomizer
		if is_instance_valid(frustrated) else null
	)
	_expect(
		is_instance_valid(randomizer)
		and randomizer.get_streams_count() > 1,
		"the frustrated sound pools several takes",
	)
	if (
		_expect(await _wait_for_landing(), "the first item lands")
		and is_instance_valid(frustrated)
	):
		G.level.active_repairable.quality.add_defect(
			RepairQuality.Defect.DENT_SMALL, Vector2.ZERO
		)
		await get_tree().process_frame
		_expect(
			frustrated.playing or frustrated.has_stream_playback(),
			"a defect plays a frustrated hmm",
		)
		frustrated.stop()

	# The toaster's scoot rolls on the pooled wheels takes.
	var skid := (
		G.audio.STREAM_PLAYERS_BY_NAME.get(&"skid")
		as AudioStreamPlayer
	)
	var skid_randomizer := (
		skid.stream as AudioStreamRandomizer
		if is_instance_valid(skid) else null
	)
	_expect(
		is_instance_valid(skid_randomizer)
		and skid_randomizer.get_streams_count() == 4,
		"the toaster scoot pools the four wheels takes",
	)

	_check_foley_direction()

	# A pause resume is not a new run. No second humming.
	G.state.transition(StateMain.State.PAUSE)
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.4)
	_expect(not _humming.playing, "a pause resume does not replay it")

	# The credits are terminal. Neither a play-again input nor a
	# direct request for a new run may start one in this session.
	G.state.transition(StateMain.State.CREDITS)
	for action in [&"jump", &"ability"]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		get_viewport().push_input(event)
		await _physics_frames(2)
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.4)
	_expect(
		G.state.state == StateMain.State.CREDITS and not _humming.playing,
		"the credits never start another run in the same session",
	)


## The 2026-10-19 foley direction: each new name pools the takes
## Levi named, and the screw-twists loop starts and stops.
func _check_foley_direction() -> void:
	_expect_pool(&"screw_drop", [
		"part drop.wav", "part drop 2.wav", "screw drop.wav",
		"screw drop 3.wav", "screw drop 5.wav",
	], "screw_drop pools part/screw drops for screws")
	_expect_pool(&"drawer_rustle", [
		"parts rustle.wav", "parts rustle 2.wav",
		"parts rustle 3.wav",
	], "drawer_rustle pools parts rustle 1/2/3")
	_expect_pool(&"screw_pickup", [
		"parts separate.wav", "parts separate 2.wav",
	], "screw_pickup pools parts separate 1/2")
	_expect_pool(&"screw_seated", [
		"parts together 2_b.wav", "pliers pinch.wav",
		"pliers pinch 2.wav", "screw drop into screws 2.wav",
	], "screw_seated pools together/pinch/screw-into-screws")
	_expect_pool(&"rattle_snap", [
		"rattle snap on 2.wav", "rattle snap on 3.wav",
		"rattle snap on_a.wav",
	], "rattle_snap pools rattle snap on 2/3/_a")
	_expect_pool(&"snap", [
		"rattle snap on 2.wav", "rattle snap on 3.wav",
		"rattle snap on_a.wav",
	], "snap is the rattle-snap pool for put-back")
	_expect_pool(&"tool_set_down", [
		"Set down hammer (1)_b.wav", "Set down hammer_b.wav",
	], "tool_set_down pools the set-down-hammer takes")
	_expect_pool(&"hammer_whack", [
		"tap metal light.wav", "Tap metal_a.wav",
	], "hammer_whack pools tap metal light/_a")
	_expect_pool(&"tool_pickup", [
		"tool pickup 3_a.wav", "tool pickup 4.wav",
		"tool pickup 5.wav",
	], "tool_pickup pools tool pickup 3_a/4/5")
	_expect_pool(&"hammer_whack_light", [
		"tap metal light.wav", "Tap metal_a.wav",
	], "hammer_whack_light is the light tap-metal pool")
	_expect_pool(&"hammer_whack_heavy", [
		"Hammer light metal.wav", "Hammer light metal 2_a.wav",
		"Hammer metal 2.wav", "Hammer metal 3.wav",
		"Hammer metal 4_b.wav", "Hammer metal_b.wav",
	], "hammer_whack_heavy pools every Hammer metal take in tools/")
	_expect_pool(&"hammer_wood", [
		"Hammer - wood.wav", "Hammer - wood 2.wav",
	], "hammer_wood pools Hammer - wood 1/2 for a miss")
	_expect_pool(&"hammer_miss", [
		"Hammer - wood.wav", "Hammer - wood 2.wav",
	], "hammer_miss is the hammer_wood pool")
	_expect_pool(&"glug", [
		"glug small.wav", "glug small 2_a.wav",
	], "glug pools glug small and glug small 2_a for glue")
	_expect_pool(&"rag_wipe", [
		"wipe 2.wav", "wipe 3.wav", "wipe_a.wav",
	], "rag_wipe pools wipe 2/3/_a for the rag")
	_expect_pool(&"lid_pop", [
		"lid pop 2_b.wav", "lid pop off 3.wav",
		"lid pop off_a.wav", "lid pop_b.wav",
	], "lid_pop pools the lid takes for yanked/lifted parts")
	_expect_pool(&"pop", [
		"lid pop 2_b.wav", "lid pop off 3.wav",
		"lid pop off_a.wav", "lid pop_b.wav",
	], "pop is the lid_pop pool")
	_expect_pool(&"sigh", [
		"sigh of relief.wav", "sigh 2.wav",
	], "sigh is the sigh pool played at the end of the game")
	var large := (
		G.audio.STREAM_PLAYERS_BY_NAME.get(&"part_drop_large")
		as AudioStreamPlayer
	)
	_expect(
		is_instance_valid(large)
		and is_instance_valid(large.stream)
		and large.stream.resource_path.ends_with("part drop 4.wav"),
		"part_drop_large is part drop 4",
	)
	var tap := (
		G.audio.STREAM_PLAYERS_BY_NAME.get(&"tap_metal")
		as AudioStreamPlayer
	)
	_expect(
		is_instance_valid(tap)
		and is_instance_valid(tap.stream)
		and tap.stream.resource_path.ends_with("Tap metal (1).wav"),
		"tap_metal is Tap metal (1) for a driver sliding out",
	)
	var loop_player := (
		G.audio.STREAM_PLAYERS_BY_NAME.get(&"screw_twist_loop")
		as AudioStreamPlayer
	)
	_expect(
		is_instance_valid(loop_player)
		and is_instance_valid(loop_player.stream)
		and loop_player.stream.resource_path.ends_with(
			"screw twists.wav"
		),
		"screw_twist_loop is screw twists",
	)
	G.audio.start_screw_twist_loop()
	_expect(
		G.audio.is_screw_twist_looping()
		and is_instance_valid(loop_player)
		and loop_player.playing,
		"the screw-twists loop plays while a screw turns",
	)
	G.audio.stop_screw_twist_loop()
	_expect(
		not G.audio.is_screw_twist_looping()
		and not loop_player.playing,
		"the screw-twists loop stops when turning stops",
	)


func _expect_pool(
	sound_name: StringName,
	expected_suffixes: Array,
	label: String,
) -> void:
	var player := (
		G.audio.STREAM_PLAYERS_BY_NAME.get(sound_name)
		as AudioStreamPlayer
	)
	if not _expect(is_instance_valid(player), label + ": player exists"):
		return
	var paths := _stream_paths(player)
	_expect(
		paths.size() == expected_suffixes.size(),
		label + ": take count",
	)
	for suffix in expected_suffixes:
		var found := false
		for path in paths:
			if path.ends_with(suffix):
				found = true
		_expect(found, label + ": has " + suffix)


func _stream_paths(player: AudioStreamPlayer) -> Array:
	var paths: Array = []
	if not is_instance_valid(player) or not is_instance_valid(player.stream):
		return paths
	var randomizer := player.stream as AudioStreamRandomizer
	if is_instance_valid(randomizer):
		for index in randomizer.get_streams_count():
			var entry := randomizer.get_stream(index)
			if is_instance_valid(entry):
				paths.append(entry.resource_path)
	else:
		paths.append(player.stream.resource_path)
	return paths
