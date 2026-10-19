extends "res://tests/probe_base.gd"
## The desk radio's glitch. Checks it never glitches before an item is
## fixed, glitches once one is, and that a hammer hit on it fixes the
## glitch, restores the music and starts the cooldown.
##
## Run it with `tests/run.ps1 -Name radio`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/radio/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0
## Short enough that a glitch is all but certain within a few seconds.
const _FAST_CHANCE_WINDOW_SEC := 0.2

var _radio: Radio


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_hand = G.level.hand
	_radio = G.level.get_node("Radio") as Radio
	if not _expect(is_instance_valid(_radio), "the level has a radio"):
		return

	G.settings.radio_glitch_chance_window_sec = _FAST_CHANCE_WINDOW_SEC
	await _seconds(1.0)
	_expect(
		not _radio.is_glitching,
		"the radio does not glitch before an item is fixed",
	)

	G.session.fixed_item_count = 1
	await _seconds(2.0)
	if not _expect(
		_radio.is_glitching,
		"the radio glitches once an item is fixed",
	):
		return
	await _seconds(2.5)
	_expect(
		G.audio.current_theme.pitch_scale < 0.9,
		"the glitch slows the music",
	)
	_expect(
		(_radio.get_node("Static") as AudioStreamPlayer).playing,
		"the glitch plays static",
	)

	# Left alone, the wonky radio highlights itself. The
	# probe shortens the delay so it does not wait it out.
	_radio.glitch_highlight_delay_sec = 1.0
	await _seconds(0.3)
	_expect(
		_radio.is_highlight_shown(),
		"a glitch left alone highlights the radio",
	)

	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Tool
	await _grab_tool(hammer)
	var radio_point: Vector2 = (
		_radio.get_node("Art") as Sprite2D
	).global_position + Vector2(0.0, -40.0)
	_expect(_radio.is_struck_at(radio_point), "the press lands on the radio")
	await _press_down(radio_point)
	var hammer_tool := hammer as Hammer
	_expect(
		is_instance_valid(hammer_tool)
		and hammer_tool.get_locked_prop() == _radio
		and hammer_tool.is_locked_prop_green(),
		"winding up on the wonky radio locks it with the green band",
	)
	await _seconds(0.2)
	await _release_at(radio_point)
	await _seconds(0.5)
	_expect(not _radio.is_glitching, "a hammer hit fixes the radio")
	_expect(
		not _radio.is_highlight_shown(),
		"bonking the radio clears the highlight",
	)

	await _seconds(3.0)
	_expect(
		is_equal_approx(G.audio.current_theme.pitch_scale, 1.0),
		"the music is back to normal speed",
	)
	_expect(
		not (_radio.get_node("Static") as AudioStreamPlayer).playing,
		"the static stops",
	)
	_expect(
		not _radio.is_glitching,
		"the cooldown keeps the radio from glitching again right away",
	)
