extends "res://tests/probe_base.gd"
## The desk radio's glitch. Checks it glitches only during the items
## listed in `radio_glitch_item_indices` (after the scheduled delay),
## that a hammer hit fixes it and restores the music, and that it
## glitches again on the next scheduled item.
##
## Run it with `tests/run.ps1 -Name radio`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/radio/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0

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

	# The probe schedules glitches on items 1 and 2 with a short
	# delay and cooldown; the day's real schedule (items 2, 3, 4,
	# 8-16 seconds in) lives in settings.
	G.settings.radio_glitch_item_indices = [1, 2]
	G.settings.radio_glitch_delay_min_sec = 0.2
	G.settings.radio_glitch_delay_max_sec = 0.3
	G.settings.radio_glitch_cooldown_sec = 0.5
	await _seconds(1.0)
	_expect(
		not _radio.is_glitching,
		"the radio does not glitch during an unscheduled item",
	)

	G.session.fixed_item_count = 1
	await _seconds(1.0)
	if not _expect(
		_radio.is_glitching,
		"the radio glitches into a scheduled item",
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
	# Aim the face, not the tip: the hammer acts where its
	# working end lands, well away from the cursor marker.
	# (Pressing the tip onto the radio leaves the face over
	# empty air, which is how this probe used to miss.)
	var hammer_tool := hammer as Hammer
	var target := _radio.get_art_center()
	_expect(_radio.is_struck_at(target), "the press lands on the radio")
	var settle_frames := 0
	while settle_frames < 90 and (
		hammer_tool.follow_offset.length() > 0.5
		or (
			is_instance_valid(hammer_tool.rotation_tween)
			and hammer_tool.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		settle_frames += 1
	var offset := (
		hammer_tool.get_work_end_position()
		- hammer_tool.get_tip_position()
	)
	await _press_down(target - offset)
	_expect(
		is_instance_valid(hammer_tool)
		and hammer_tool.get_locked_prop() == _radio
		and hammer_tool.is_locked_prop_green(),
		"winding up on the wonky radio locks it with the green band",
	)
	await _seconds(0.2)
	await _release_at(target - offset)
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
		"the radio stays fixed until the next scheduled item",
	)
	G.session.fixed_item_count = 2
	await _seconds(1.5)
	_expect(
		_radio.is_glitching,
		"the radio glitches again on the next scheduled item",
	)
	await _check_radio_item_arrival()


## The radio as the item: its sound goes wonky on the shelf,
## holds for the wonk's length, falls silent, and only then
## flies down to the bench.
func _check_radio_item_arrival() -> void:
	_radio.set_glitching(false)
	G.settings.shop_radio_wonk_sec = 1.2
	var current := G.level.active_repairable
	G.level.active_repairable = null
	current.queue_free()
	await _physics_frames(4)
	G.level.spawn_repairable(Repairable.Type.RADIO)
	_expect(
		_radio.is_glitching,
		"the shelf radio goes wonky when its turn comes",
	)
	_expect(
		not _radio.is_away and _radio.visible,
		"the radio is still on the shelf while it wonks",
	)
	await _seconds(2.0)
	_expect(
		_radio.is_away and not _radio.is_glitching,
		"the wonk ends in silence before the radio leaves",
	)
	_expect(
		await _wait_for_landing(),
		"the silent radio flies down to the bench",
	)
	_expect(
		not _radio.visible,
		"the shelf is empty once the radio is the item",
	)
