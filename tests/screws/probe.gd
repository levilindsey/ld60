extends "res://tests/probe_base.gd"
## The screws (LX10, LX11). Boots the game and checks screw health and the
## flathead twist cycle with pushed pointer input: a player who corrects,
## one who never does, yanks that strip a screw, the stand-in pry, a
## seized screw, how a screw slides up as it turns out and back down as it
## turns in (screws.md "Removal"), and the `slip_bias` table in flathead.md.
##
## Run it with `tests/run.ps1 -Name screws`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/screws/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 120.0
## How long a player who never corrects waits for the tip to skid out.
const _UNSEAT_TIMEOUT_FRAMES := 600
## Screws per row of the drift table check, and the cap on their twists.
const _SIMULATED_SCREWS := 100000
const _SIMULATED_MAX_TWISTS := 1000
const _DRIFT_TABLE_SEED := 6060
## flathead.md "Tuning": slip_bias, the median twists to unseat, the
## percent that unseat on twist 2, the percent that unseat within 4.
const _BIAS_TABLE := [
	[0.5, 6, 6.3, 32.5],
	[0.8, 4, 8.5, 57.7],
	[0.9, 3, 10.2, 76.5],
	[1.0, 3, 12.5, 99.7],
]
## The table rounds to a tenth of a percent, and the probe samples fewer
## screws than the table did.
const _TABLE_TOLERANCE_PERCENT := 0.5
## How far a yank moves the pointer along the slot: past the tolerance.
const _YANK_PX := 20.0
## The player who never corrects gets a drift seed that skids the tip out
## on this twist.
const _UNSEAT_TWIST := 3
## That seed's drifts clear the tolerance by this much either way.
const _SEED_MARGIN_PX := 0.5
## ScrewLeft's node is turned this far while it comes out, to check that up
## stays up the screen.
const _TILTED_SCREW_DEG := 33.0
## Records and checks a screw's slide (no `class_name`, so loaded by path).
const SlideRecorder := preload("res://tests/screws/slide_recorder.gd")
## Records and checks a screw's pull-out to the bench and back (LX54).
const PullOutRecorder := preload("res://tests/screws/pull_out_recorder.gd")
const _WATCHED_SOUNDS: Array[String] = [
	"creak",
	"ratchet",
	"pop",
	"click",
	"scrape",
	"skid",
	"grind",
	"clunk",
]

var _defects: Array[int] = []
var _sound_counts := {}
var _largest_scale_change := 0.0
var _scale_samples := 0

# Samples from the latest _drive().
var _drive_max_offset_px := 0.0
var _drive_correction_px := 0.0
var _drive_min_art_scale := 1.0
var _drive_twist_samples := 0
var _drive_untwisted_frames := 0
var _slide := SlideRecorder.new()
## One record for the screw on its trip, and one for a screw that rests
## meanwhile.
var _pull_out := PullOutRecorder.new()
var _rest_watch := PullOutRecorder.new()

var _level: Level
var _tool: FlatHeadScrewDriver
var _item: Repairable
var _cover: RepairLayer
var _screw_left: FlatHeadScrew
var _screw_right: FlatHeadScrew
var _holder_position := Vector2.ZERO
## Where each screw sits at home, in world pixels, from when its item landed.
var _homes := {}


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	# The probe runs ALWAYS so it can step through the pause. The game
	# must pause the way it does under the root window.
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	# Only pushed input reaches the game (LX44).
	var blocker := _RealInputBlocker.new()
	blocker.probe = self
	add_child(blocker)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	_expect(G.state.state == StateMain.State.TITLE, "boot shows the title")
	for sound_name in G.audio.STREAM_PLAYERS_BY_NAME:
		if sound_name.ends_with("_theme"):
			continue
		var player: AudioStreamPlayer = (
			G.audio.STREAM_PLAYERS_BY_NAME[sound_name]
		)
		_expect(
			is_instance_valid(player.stream),
			"LX25: the %s sound has a stream" % sound_name,
		)
	_check_drift_table()
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	if not _watch_sounds():
		return
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_collect_nodes()
	get_tree().physics_frame.connect(_track_scale)

	_check_hole_positions()
	await _check_correcting()
	await _check_never_correcting()
	await _check_install()
	if not await _start_fresh_level():
		return
	await _check_yanks()
	await _check_stripped_press()
	await _check_pry()
	await _check_seized()
	await _check_install_after_strip()

	get_tree().physics_frame.disconnect(_track_scale)
	_expect(
		_scale_samples > 1000 and _largest_scale_change < 0.0001,
		"Levi: a turning screw rotates and never scales (largest change"
		+ " %.5f in %d frames)" % [_largest_scale_change, _scale_samples],
	)


## The `slip_bias` table in flathead.md "Tuning", from the same drift
## function the screws use.
func _check_drift_table() -> void:
	var started_msec := Time.get_ticks_msec()
	var random := RandomNumberGenerator.new()
	random.seed = _DRIFT_TABLE_SEED
	for row: Array in _BIAS_TABLE:
		var bias: float = row[0]
		var counts := PackedInt32Array()
		counts.resize(_SIMULATED_MAX_TWISTS + 2)
		for screw_index in _SIMULATED_SCREWS:
			var offset := 0.0
			var twist := 0
			while twist <= _SIMULATED_MAX_TWISTS:
				twist += 1
				offset += FlatHeadScrew.pick_drift_px(
					random,
					1.0,
					bias,
					1.0,
					G.settings.flathead_slip_min,
					G.settings.flathead_slip_max,
				)
				if absf(offset) > 1.0:
					break
			counts[twist] += 1
		var median := 0
		var total := 0
		for twist in range(1, counts.size()):
			total += counts[twist]
			if total * 2 >= _SIMULATED_SCREWS:
				median = twist
				break
		var on_twist_2 := 100.0 * counts[2] / _SIMULATED_SCREWS
		var within_4 := (
			100.0
			* (counts[1] + counts[2] + counts[3] + counts[4])
			/ _SIMULATED_SCREWS
		)
		var want_median: int = row[1]
		var want_on_twist_2: float = row[2]
		var want_within_4: float = row[3]
		_expect(
			counts[1] == 0
			and median == want_median
			and absf(on_twist_2 - want_on_twist_2) < _TABLE_TOLERANCE_PERCENT
			and absf(within_4 - want_within_4) < _TABLE_TOLERANCE_PERCENT,
			(
				"flathead.md table, slip_bias %.1f: median %d (want %d), on"
				+ " twist 2 %.1f%% (want %.1f), within 4 %.1f%% (want %.1f),"
				+ " on twist 1 %d"
			) % [
				bias,
				median,
				want_median,
				on_twist_2,
				want_on_twist_2,
				within_4,
				want_within_4,
				counts[1],
			],
		)
	print(
		"PROBE NOTE: drift table, %d screws per row in %d ms"
		% [_SIMULATED_SCREWS, Time.get_ticks_msec() - started_msec]
	)


## The sound players ship without streams, so play_sound() does nothing.
## Gives the watched ones a silent stream, then counts each play and
## stops it again every physics frame.
func _watch_sounds() -> bool:
	for sound_name in _WATCHED_SOUNDS:
		var player: AudioStreamPlayer = (
			G.audio.STREAM_PLAYERS_BY_NAME[sound_name]
		)
		player.stream = AudioStreamGenerator.new()
		_sound_counts[sound_name] = 0
	G.audio.play_sound("creak")
	var is_counted := _is_sound_playing("creak")
	_poll_sounds()
	G.audio.stop_sound("creak")
	_reset_sounds()
	get_tree().physics_frame.connect(_poll_sounds)
	return _expect(is_counted, "the probe can count a played sound")


func _is_sound_playing(sound_name: String) -> bool:
	var player: AudioStreamPlayer = G.audio.STREAM_PLAYERS_BY_NAME[sound_name]
	return player.playing or player.has_stream_playback()


func _poll_sounds() -> void:
	for sound_name in _WATCHED_SOUNDS:
		if _is_sound_playing(sound_name):
			_sound_counts[sound_name] += 1
			var player: AudioStreamPlayer = (
				G.audio.STREAM_PLAYERS_BY_NAME[sound_name]
			)
			player.stop()


func _count(sound_name: String) -> int:
	_poll_sounds()
	return _sound_counts[sound_name]


func _reset_sounds() -> void:
	_poll_sounds()
	for sound_name in _WATCHED_SOUNDS:
		_sound_counts[sound_name] = 0


func _sounds_text() -> String:
	_poll_sounds()
	var parts: Array[String] = []
	for sound_name in _WATCHED_SOUNDS:
		if _sound_counts[sound_name] > 0:
			parts.append("%s %d" % [sound_name, _sound_counts[sound_name]])
	return ", ".join(parts)


func _collect_nodes() -> void:
	_level = G.level
	_hand = _level.hand
	_tool = (
		_level.tools_by_type[Tool.Type.FLAT_HEAD_SCREW_DRIVER]
		as FlatHeadScrewDriver
	)
	_item = _level.active_repairable
	_cover = _item.get_node("Layers/Cover")
	_screw_left = _cover.get_node("ScrewLeft")
	_screw_right = _cover.get_node("ScrewRight")
	_holder_position = _level.get_tool_holder_position(
		Tool.Type.FLAT_HEAD_SCREW_DRIVER
	)
	_events.clear()
	_defects.clear()
	_homes.clear()
	_item.finished.connect(func() -> void: _events.append("finished"))
	_item.quality.defect_added.connect(_on_defect_added)
	for screw: FlatHeadScrew in [_screw_left, _screw_right]:
		_homes[screw] = screw.head.global_position
		var prefix := String(screw.name)
		screw.damaged.connect(
			func(health: int) -> void:
				_events.append("%s:damaged:%d" % [prefix, health])
		)
		screw.stripped.connect(
			func() -> void: _events.append("%s:stripped" % prefix)
		)
		screw.removed.connect(
			func() -> void: _events.append("%s:removed" % prefix)
		)
		screw.installed.connect(
			func() -> void: _events.append("%s:installed" % prefix)
		)


## The hole and the clip space sit 7 px above where they used to,
## and the screw art sits on its hole, not displaced above it.
func _check_hole_positions() -> void:
	for screw: FlatHeadScrew in [_screw_left, _screw_right]:
		var hole := screw.get_node("Hole") as Node2D
		_expect(
			hole.position.is_equal_approx(Vector2(0.0, -1.0)),
			"%s: the hole sits at (0, -1), got %s"
			% [screw.name, hole.position],
		)
		var clip_position := (screw.clip_space as Node2D).position
		_expect(
			clip_position.is_equal_approx(Vector2(0.0, -40.2)),
			"%s: the clip space sits at (0, -40.2), got %s"
			% [screw.name, clip_position],
		)
		var head_gap := screw.head.global_position.distance_to(
			hole.global_position
		)
		_expect(
			head_gap < 2.0,
			"%s: the screw sits on its hole (%.2f px off)"
			% [screw.name, head_gap],
		)


## A player who corrects every frame: the tip stays seated and the screw
## comes out in its four twists.
func _check_correcting() -> void:
	await _press_at(_holder_position)
	await _seconds(0.4)
	_expect(
		_hand.held == _tool and _tool.mode == Tool.Mode.HELD,
		"take the driver",
	)
	_reset_sounds()
	# Turn the screw's node as a scene would: the turn moves onto the head,
	# so up must still be up the screen.
	var tilt := deg_to_rad(_TILTED_SCREW_DEG)
	_screw_left.rotation = tilt
	_screw_left.make_upright()
	await _press_at(_screw_left.global_position)
	_expect(
		_tool.mode == Tool.Mode.IN_USE
		and _screw_left.mode == InteractionPoint.Mode.ACTIVE
		and _hand.input_owner == _screw_left,
		"LX11: the driver engages ScrewLeft, which takes the pointer",
	)
	_pull_out.watch(_screw_left)
	await _drive(_screw_left, 10.0)
	_slide.check(
		_expect,
		"ScrewLeft out, its node turned %.0f deg" % _TILTED_SCREW_DEG,
		0.0,
	)
	var turned_deg := rad_to_deg(
		_screw_left.head.rotation - _screw_left._home_head_rotation
	)
	_expect(
		_screw_left.travel == Screw.Travel.PULLING_OUT
		and is_equal_approx(turned_deg, -360.0),
		"correcting: four twists of 90 degrees take ScrewLeft out (head"
		+ " turned %.1f deg)" % turned_deg,
	)
	_expect(
		_drive_max_offset_px < 1.0 and _drive_correction_px > 9.0,
		"correcting keeps the tip seated (largest offset %.2f px, %.1f px"
		% [_drive_max_offset_px, _drive_correction_px]
		+ " of drift corrected)",
	)
	_expect(
		_drive_twist_samples > 100 and _drive_untwisted_frames == 0,
		"LX51: the driver plays twisting while in use (%d of %d frames did not)"
		% [_drive_untwisted_frames, _drive_twist_samples],
	)
	_expect(
		_tool.mode == Tool.Mode.HELD and _is_driver_resting(),
		"LX51: the driver shows default once it is back in the hand",
	)
	_expect(
		_drive_min_art_scale < 0.95
		and _tool.art.scale.is_equal_approx(Vector2.ONE),
		"the handle tenses before each twist and relaxes (narrowest %.3f)"
		% _drive_min_art_scale,
	)
	_expect(
		_screw_left.health == _screw_left.max_health
		and _item.quality.get_defect_points_total() == 0,
		"no damage and no defects for a seated tip",
	)
	_expect(
		_tool.mode == Tool.Mode.HELD
		and _hand.held == _tool
		and not is_instance_valid(_hand.input_owner)
		and _events.count("ScrewLeft:removed") == 1,
		"the screw emits removed once and gives the driver and the pointer"
		+ " back",
	)
	_expect(
		_count("creak") == 4
		and _count("ratchet") == 3
		and _count("pop") == 1
		and _count("skid") == 0
		and _count("scrape") == 0,
		"sounds: a creak per twist, a ratchet between twists, a pop (%s)"
		% _sounds_text(),
	)
	var lowest_deg := INF
	var highest_deg := -INF
	for frame in roundi(0.4 * Engine.physics_ticks_per_second):
		var degrees := rad_to_deg(_tool.rotation)
		lowest_deg = minf(lowest_deg, degrees)
		highest_deg = maxf(highest_deg, degrees)
		await get_tree().physics_frame
	_expect(
		lowest_deg > _tool.held_rotation_deg - 0.5
		and highest_deg < _tool.in_use_angle_deg + 0.5
		and absf(rad_to_deg(_tool.rotation) - _tool.held_rotation_deg) < 0.5,
		"the driver eases back to the hand the short way (%.1f to %.1f deg,"
		% [lowest_deg, highest_deg]
		+ " ends at %.1f)" % rad_to_deg(_tool.rotation),
	)
	await _wait_for_travel(_screw_left, Screw.Travel.RESTING)
	_pull_out.stop()
	_pull_out.check_pull_out(_expect, "ScrewLeft", 0)
	# Put the slot back upright for the checks after this one.
	_screw_left.head.rotation -= tilt
	_screw_left._home_head_rotation -= tilt


## A player who never corrects: the drifts walk the tip off the end of the
## slot on twist 3. The screw takes 1 damage and keeps its 2 twists.
func _check_never_correcting() -> void:
	var screw := _screw_right
	var drift_seed := _find_unseat_seed(screw, _UNSEAT_TWIST)
	if not _expect(
		drift_seed >= 0,
		"found a drift seed that skids out on twist %d" % _UNSEAT_TWIST,
	):
		return
	screw._random.seed = drift_seed
	var decal_count := _get_decals().size()
	var points := _item.quality.get_defect_points_total()
	_defects.clear()
	_reset_sounds()
	await _press_at(screw.global_position)
	_expect(
		screw.mode == InteractionPoint.Mode.ACTIVE
		and _tool.mode == Tool.Mode.IN_USE,
		"the driver engages ScrewRight",
	)
	var frames := 0
	while (
		screw.mode == InteractionPoint.Mode.ACTIVE
		and frames < _UNSEAT_TIMEOUT_FRAMES
	):
		frames += 1
		await get_tree().physics_frame
	var twist_deg := G.settings.flathead_twist_angle_deg
	var degrees := rad_to_deg(screw.head.rotation)
	_expect(
		screw.mode == InteractionPoint.Mode.UNSTARTED
		and screw._twists_done == _UNSEAT_TWIST - 1
		and degrees > -twist_deg * _UNSEAT_TWIST - 0.01
		and degrees < -twist_deg * (_UNSEAT_TWIST - 1),
		"never correcting: the tip skids out during twist %d, and the"
		% _UNSEAT_TWIST
		+ " screw keeps %d twists (head at %.1f deg, after %d frames)"
		% [screw._twists_done, degrees, frames],
	)
	_expect(
		screw.health == screw.max_health - 1
		and _events.has("ScrewRight:damaged:%d" % (screw.max_health - 1))
		and _item.quality.get_defect_points_total() - points == 2
		and _defects.size() == 1
		and _defects[0] == RepairQuality.Defect.SCREW_DAMAGE,
		"the skid costs 1 health and one SCREW_DAMAGE (health %d, %d"
		% [screw.health, _item.quality.get_defect_points_total() - points]
		+ " points, defects %s)" % [_defects],
	)
	var decals := _get_decals()
	var decal_distance := -1.0
	if decals.size() > decal_count:
		decal_distance = decals.back().global_position.distance_to(
			screw.head.global_position
		)
	_expect(
		decals.size() == decal_count + 1
		and absf(decal_distance - 21.0) < 0.5,
		"a skid decal on the cover past the end of the slot (%d new, %.1f"
		% [decals.size() - decal_count, decal_distance]
		+ " px from the head)",
	)
	var sparks_distance := screw.sparks.global_position.distance_to(
		screw.head.global_position
	)
	_expect(
		screw.sparks.emitting and absf(sparks_distance - 12.0) < 0.5,
		"sparks at the end of the slot (%.1f px from the head)"
		% sparks_distance,
	)
	_expect(
		_tool.mode == Tool.Mode.HELD
		and _hand.held == _tool
		and not is_instance_valid(_hand.input_owner),
		"the driver hops back to the hand and the pointer is free",
	)
	_expect(
		_count("skid") == 1
		and _count("scrape") >= 1
		and _count("creak") == _UNSEAT_TWIST
		and _count("ratchet") == _UNSEAT_TWIST - 1
		and _count("pop") == 0,
		"sounds: a scrape near the end, then one skid (%s)" % _sounds_text(),
	)
	var px := screw.get_slide_height_px()
	var kept_slide := screw.slide
	var kept_rise := _get_rise(screw)
	var turned := absf(screw.head.rotation - screw._home_head_rotation) / TAU
	_expect(
		kept_rise > SlideRecorder.MIN_SLIDE_PX
		and absf(kept_rise - px * turned) < SlideRecorder.TOLERANCE_PX
		and kept_slide > 0.5
		and kept_slide < 0.75,
		"an unseat leaves the screw where it is, %.2f px up and in step with"
		% kept_rise
		+ " its head (slide %.3f, turned %.3f)" % [kept_slide, turned],
	)
	await _physics_frames(30)
	var held_px := absf(_get_rise(screw) - kept_rise)
	_expect(
		screw.slide == kept_slide and held_px < SlideRecorder.HOLD_TOLERANCE_PX,
		"the unseated screw holds its height while the player waits (moved"
		+ " %.5f px)" % held_px,
	)

	_reset_sounds()
	# A press at the top of the raised hit shape misses the shape at home.
	var edge_point := _get_top_edge_point(screw)
	await _press_at(edge_point)
	_expect(
		screw.mode == InteractionPoint.Mode.ACTIVE
		and _tool.mode == Tool.Mode.IN_USE,
		"the driver engages ScrewRight again, by a press %.1f px from the"
		% edge_point.distance_to(_get_home(screw))
		+ " center of its home hit shape (radius 12): the shape slid too",
	)
	_pull_out.watch(screw)
	_rest_watch.watch(_screw_left)
	await _drive(screw, 10.0)
	_slide.check(
		_expect,
		"ScrewRight's last twists after the unseat",
		kept_slide,
	)
	var out_rotation := screw._home_head_rotation - TAU
	_expect(
		screw.travel == Screw.Travel.PULLING_OUT
		and is_equal_approx(screw.head.rotation, out_rotation)
		and screw.health == screw.max_health - 1,
		"the kept twists count: two more take ScrewRight out (head at %.1f"
		% rad_to_deg(screw.head.rotation)
		+ " deg, health %d)" % screw.health,
	)
	_expect(
		_count("creak") == 2 and _count("ratchet") == 1 and _count("pop") == 1,
		"sounds for the last two twists (%s)" % _sounds_text(),
	)
	_expect(
		_cover.is_on and not _cover.is_moving,
		"the cover waits while ScrewRight pulls out",
	)
	await _wait_for_travel(screw, Screw.Travel.RESTING)
	_expect(
		screw.mode == InteractionPoint.Mode.FINISHED and _cover.is_moving,
		"both screws out: the cover lifts once ScrewRight has left its hole",
	)
	_pull_out.check_pull_out(_expect, "ScrewRight", 1)


## Both screws go back in. Driving in plays a click, not a pop.
func _check_install() -> void:
	await _seconds(0.9)
	_pull_out.stop()
	_rest_watch.stop()
	_rest_watch.check_rest_kept(_expect, "ScrewLeft", 0)
	_pull_out.check_rest_kept(_expect, "ScrewRight", 1)
	# Before the cover is back on, a press on a resting screw does nothing.
	var held := _hand.held
	_pull_out.watch(_screw_left)
	await _press_resting_screw(_screw_left)
	await _physics_frames(10)
	_pull_out.stop()
	_pull_out.check_press_ignored(_expect, "ScrewLeft", 0)
	_expect(_hand.held == held, "the press leaves the hand as it was")
	await _put_cover_back()
	for screw: FlatHeadScrew in [_screw_left, _screw_right]:
		_reset_sounds()
		await _drive_install(screw)
		_expect(
			screw.mode == InteractionPoint.Mode.FINISHED
			and is_zero_approx(screw.head.rotation)
			and _events.count("%s:installed" % screw.name) == 1
			and _drive_max_offset_px < 1.0,
			"%s goes back in, turned home (%.1f deg)"
			% [screw.name, rad_to_deg(screw.head.rotation)],
		)
		_expect(
			_count("creak") == screw.install_twists
			and _count("ratchet") == screw.install_twists - 1
			and _count("click") == 1
			and _count("pop") == 0,
			"%s install sounds (%s)" % [screw.name, _sounds_text()],
		)
	_expect(_item.has_finished, "the item is finished")


## Restarts the level, waits for its item and takes the driver.
func _start_fresh_level() -> bool:
	var old_level_id := _level.get_instance_id()
	G.game_panel.restart_level()
	await _seconds(0.8)
	if not _expect(
		is_instance_valid(G.level)
		and G.level.get_instance_id() != old_level_id,
		"a fresh level starts",
	):
		return false
	if not _expect(await _wait_for_landing(), "the fresh item lands"):
		return false
	_collect_nodes()
	await _press_at(_holder_position)
	await _seconds(0.4)
	return _expect(_hand.held == _tool, "take the driver in the fresh level")


## Three yanks along the slot: each skids out, costs 1 health and shows
## the next head frame. The third strips the screw.
func _check_yanks() -> void:
	var screw := _screw_left
	var decal_count := _get_decals().size()
	var tints: Array[Color] = [screw.head.modulate]
	var healths: Array[int] = []
	var frames: Array[int] = []
	var points: Array[int] = []
	var is_frame_tinted := true
	var skids := 0
	for yank in 3:
		_reset_sounds()
		await _press_at(screw.global_position)
		await _move_to(
			_hand.pointer_position + screw.get_slot_axis() * _YANK_PX
		)
		await _physics_frames(1)
		healths.append(screw.health)
		frames.append(screw.get_head_frame())
		points.append(_item.quality.get_defect_points_total())
		is_frame_tinted = (
			is_frame_tinted
			and screw.head.modulate
			== Screw._PLACEHOLDER_FRAME_TINTS[screw.get_head_frame()]
		)
		tints.append(screw.head.modulate)
		skids += _count("skid")
	_expect(
		str(healths) == "[2, 1, 0]" and str(frames) == "[1, 2, 3]",
		"LX10: each yank costs 1 health and shows the next frame (health %s,"
		% str(healths)
		+ " frames %s)" % str(frames),
	)
	_expect(
		is_frame_tinted
		and tints[0] != tints[1]
		and tints[1] != tints[2]
		and tints[2] != tints[3]
		and tints[0] != tints[3],
		"the placeholder tints stand in for the four frames",
	)
	_expect(
		str(points) == "[2, 4, 16]",
		"2 points a damage, 10 more for the strip (totals %s)" % str(points),
	)
	_expect(
		_defects.count(RepairQuality.Defect.SCREW_DAMAGE) == 3
		and _defects.count(RepairQuality.Defect.SCREW_STRIPPED) == 1
		and _defects.size() == 4,
		"three SCREW_DAMAGE and one SCREW_STRIPPED (%s)" % [_defects],
	)
	_expect(
		_events.count("ScrewLeft:stripped") == 1
		and _events.has("ScrewLeft:damaged:0")
		and screw.is_stripped(),
		"the third yank strips the screw, once",
	)
	_expect(
		skids == 3 and _get_decals().size() == decal_count + 3,
		"a skid and a decal for each yank (%d skids, %d decals)"
		% [skids, _get_decals().size() - decal_count],
	)


## A stripped screw grinds and nopes the first time, and the driver stays
## in the hand.
func _check_stripped_press() -> void:
	_reset_sounds()
	await _press_at(_screw_left.global_position)
	var nope_icon: Node2D = _level.get_node("%NopeIcon")
	_expect(
		_count("grind") == 1 and _count("clunk") == 1 and nope_icon.visible,
		"a press on the stripped screw grinds and nopes (%s)" % _sounds_text(),
	)
	_expect(
		_tool.mode == Tool.Mode.HELD
		and _hand.held == _tool
		and _screw_left.mode == InteractionPoint.Mode.UNSTARTED
		and not is_instance_valid(_hand.input_owner),
		"the stripped screw doesn't take the driver",
	)


## Stand-in until LX19: the press after the warning pries the stripped
## screw out.
func _check_pry() -> void:
	await _seconds(0.8)
	_reset_sounds()
	# Where the head stands when the screw emits removed, before the pull-out
	# moves its art.
	var removed_rises: Array[float] = []
	_screw_left.removed.connect(
		func() -> void: removed_rises.append(_get_rise(_screw_left)),
		CONNECT_ONE_SHOT,
	)
	_pull_out.watch(_screw_left)
	await _press_at(_screw_left.global_position)
	_expect(
		_screw_left.mode == InteractionPoint.Mode.ACTIVE
		and _tool.mode == Tool.Mode.HELD
		and _count("grind") == 1
		and _count("clunk") == 0,
		"the next press grinds and starts the stand-in pry (%s)"
		% _sounds_text(),
	)
	await _wait_for_travel(_screw_left, Screw.Travel.RESTING)
	_pull_out.stop()
	_expect(
		_screw_left.mode == InteractionPoint.Mode.FINISHED
		and _screw_left.travel == Screw.Travel.RESTING
		and _count("pop") == 1
		and _events.count("ScrewLeft:removed") == 1,
		"the stand-in pry takes the stripped screw out to the bench (%s)"
		% _sounds_text(),
	)
	var rise := -1.0 if removed_rises.is_empty() else removed_rises[0]
	_expect(
		absf(rise - _screw_left.get_slide_height_px())
		< SlideRecorder.TOLERANCE_PX
		and rise > SlideRecorder.MIN_SLIDE_PX,
		"the pry leaves the stripped screw all the way out (%.2f px up)" % rise,
	)
	_pull_out.check_pull_out(_expect, "ScrewLeft pried", 0)


## A seized screw grinds without turning. The first try is a warning, and
## each try after it costs 1 health. unseize() frees it.
func _check_seized() -> void:
	var screw := _screw_right
	screw.is_seized = true
	_expect(
		screw.rust_overlay.visible and screw.rust_streak.visible,
		"a seized screw shows its rust",
	)
	var healths: Array[int] = []
	var point_steps: Array[int] = []
	var is_each_grind := true
	for attempt in 3:
		_reset_sounds()
		var points := _item.quality.get_defect_points_total()
		await _press_at(screw.global_position)
		healths.append(screw.health)
		point_steps.append(_item.quality.get_defect_points_total() - points)
		is_each_grind = (
			is_each_grind
			and _count("grind") == 1
			and _count("clunk") == 1
			and screw.mode == InteractionPoint.Mode.UNSTARTED
			and _tool.mode == Tool.Mode.HELD
		)
		await _seconds(0.5)
	_expect(
		str(healths) == "[3, 2, 1]" and str(point_steps) == "[0, 2, 2]",
		"seized: a free warning, then 1 damage a try (health %s, points %s)"
		% [str(healths), str(point_steps)],
	)
	_expect(
		is_each_grind,
		"each try grinds and nopes, and the driver stays in the hand",
	)
	screw.unseize()
	_expect(
		not screw.is_seized
		and not screw.rust_overlay.visible
		and not screw.rust_streak.visible,
		"unseize() frees the screw and hides the rust",
	)
	await _press_at(screw.global_position)
	_expect(
		screw.mode == InteractionPoint.Mode.ACTIVE
		and _tool.mode == Tool.Mode.IN_USE,
		"the freed screw takes the driver",
	)
	await _drive(screw, 10.0)
	await _wait_for_travel(screw, Screw.Travel.RESTING)
	_expect(
		screw.mode == InteractionPoint.Mode.FINISHED
		and screw.travel == Screw.Travel.RESTING
		and screw.health == 1
		and screw.get_head_frame() == Screw.HeadFrame.CHEWED,
		"the freed screw comes out to the bench, still chewed",
	)


## The pried screw comes back as new (stand-in until LX19). The chewed one
## keeps its damage. Both go back in.
func _check_install_after_strip() -> void:
	await _seconds(0.9)
	await _put_cover_back()
	_expect(
		_screw_left.is_install_mode
		and _screw_left.health == _screw_left.max_health
		and _screw_left.get_head_frame() == Screw.HeadFrame.CLEAN
		and _screw_left.head.modulate == Color.WHITE
		and not _screw_left._is_strip_warned
		and _screw_left.travel == Screw.Travel.HOME
		and _screw_left.clip_space.visible
		and _screw_left.mode == InteractionPoint.Mode.UNSTARTED,
		"stand-in until LX19: the pried screw comes back as new",
	)
	_expect(
		_screw_right.is_install_mode
		and _screw_right.health == 1
		and _screw_right.get_head_frame() == Screw.HeadFrame.CHEWED,
		"the chewed screw keeps its damage",
	)
	for screw: FlatHeadScrew in [_screw_left, _screw_right]:
		await _drive_install(screw)
		_expect(
			screw.mode == InteractionPoint.Mode.FINISHED
			and is_zero_approx(screw.head.rotation),
			"%s goes back in" % screw.name,
		)
	_expect(_item.has_finished, "the item is finished again")


## Puts the driver back, puts the set-aside cover back on and takes the
## driver again. Then a press on each screw resting on the bench brings it
## back to its hole, loose and raised.
func _put_cover_back() -> void:
	# LX15: the gear swap under the cover has to happen first, or the
	# cover will not go back and the item cannot finish. The drawer
	# flow itself is checked by tests/parts.
	_finish_socket()
	await _press_at(_holder_position)
	await _press_at(_cover.global_position)
	await _seconds(0.6)
	_expect(
		_cover.is_on
		and not _cover.is_moving
		and _screw_left.can_come_back()
		and _screw_right.can_come_back(),
		"the cover goes back on, and its screws wait on the bench to come back",
	)
	await _press_at(_holder_position)
	await _seconds(0.4)
	_expect(_hand.held == _tool, "take the driver again")
	for screw: FlatHeadScrew in [_screw_left, _screw_right]:
		_pull_out.watch(screw)
		await _press_resting_screw(screw)
		await _wait_for_travel(screw, Screw.Travel.HOME)
		_pull_out.stop()
		_pull_out.check_come_back(_expect, screw.name)
	_expect(_hand.held == _tool, "the driver stays in the hand meanwhile")


## Finishes the test item's part socket directly, once.
func _finish_socket() -> void:
	for layer in _item.layers:
		for point in layer.get_points():
			if point is PartSocket and point.mode != InteractionPoint.Mode.FINISHED:
				point.finish()


## Where the screw sits at home, in world pixels.
func _get_home(screw: FlatHeadScrew) -> Vector2:
	return _homes[screw]


## How far up the screen the screw sits from home, in world pixels.
func _get_rise(screw: FlatHeadScrew) -> float:
	return SlideRecorder.get_rise(screw, _get_home(screw))


## A point just inside the top of the screw's hit shape, where the shape
## sits now. It is out of the shape at home once the screw has slid up more
## than a pixel.
func _get_top_edge_point(screw: FlatHeadScrew) -> Vector2:
	var shape_node := screw.get_node("CollisionShape2D") as CollisionShape2D
	var radius := (shape_node.shape as CircleShape2D).radius
	return shape_node.global_position + Vector2.UP * (radius - 1.0)


## Drives a loose screw in: a press at the top of its raised hit shape,
## then the slide checks for the way down.
func _drive_install(screw: FlatHeadScrew) -> void:
	var rise := _get_rise(screw)
	var px := screw.get_slide_height_px()
	_expect(
		screw.slide == 1.0
		and screw.travel == Screw.Travel.HOME
		and screw.clip_space.visible
		and absf(rise - px) < SlideRecorder.TOLERANCE_PX
		and rise > SlideRecorder.MIN_SLIDE_PX,
		"%s comes back loose and raised (%.2f px up)" % [screw.name, rise],
	)
	await _press_at(_get_top_edge_point(screw))
	await _drive(screw, 10.0)
	await _physics_frames(1)
	_slide.check(_expect, "%s in" % screw.name, 1.0)


## A seed for the screw's drifts that skids the tip out on twist `twist`
## for a player who never corrects. Every drift total clears the
## tolerance by `_SEED_MARGIN_PX`. Returns -1 if none is found.
func _find_unseat_seed(screw: FlatHeadScrew, twist: int) -> int:
	for drift_seed in range(1, 10000):
		var random := RandomNumberGenerator.new()
		random.seed = drift_seed
		var offset := 0.0
		for index in twist:
			offset += FlatHeadScrew.pick_drift_px(
				random,
				screw._drift_sign,
				screw.slip_bias,
				screw.seat_tolerance_px,
				G.settings.flathead_slip_min,
				G.settings.flathead_slip_max,
			)
			if index == twist - 1:
				if absf(offset) > screw.seat_tolerance_px + _SEED_MARGIN_PX:
					return drift_seed
			elif absf(offset) > screw.seat_tolerance_px - _SEED_MARGIN_PX:
				break
	return -1


func _get_decals() -> Array[Sprite2D]:
	var decals: Array[Sprite2D] = []
	for child in _cover.art.get_children():
		if child is Sprite2D:
			decals.append(child as Sprite2D)
	return decals


func _get_driver_sprite() -> AnimatedSprite2D:
	return _tool.get_node_or_null("%AnimatedSprite2D") as AnimatedSprite2D


## True while the driver's sprite is playing `twisting`, which the driver
## does for as long as it is IN_USE (LX51).
func _is_driver_twisting() -> bool:
	var sprite := _get_driver_sprite()
	return (
		is_instance_valid(sprite)
		and sprite.is_playing()
		and sprite.animation == &"twisting"
	)


## True while the driver's sprite shows `default`, which it does once the
## driver leaves IN_USE (LX51).
func _is_driver_resting() -> bool:
	var sprite := _get_driver_sprite()
	return is_instance_valid(sprite) and sprite.animation == &"default"


## Plays the flathead microgame well. Every physics frame it moves the
## pointer along the slot to put the tip back in the middle, and samples
## the tip, the driver's animation and the handle. Returns once the screw
## is no longer ACTIVE or starts to pull out, or after `max_sec`.
func _drive(screw: FlatHeadScrew, max_sec: float) -> void:
	_drive_max_offset_px = 0.0
	_drive_correction_px = 0.0
	_drive_min_art_scale = 1.0
	_drive_twist_samples = 0
	_drive_untwisted_frames = 0
	_slide.begin(screw, _tool, _get_home(screw))
	var frames := roundi(max_sec * Engine.physics_ticks_per_second)
	for frame in frames:
		if (
			screw.mode != InteractionPoint.Mode.ACTIVE
			or screw.travel != Screw.Travel.HOME
		):
			return
		var offset := screw.tip_offset_px
		_drive_max_offset_px = maxf(_drive_max_offset_px, absf(offset))
		_drive_correction_px += absf(offset)
		_drive_min_art_scale = minf(_drive_min_art_scale, _tool.art.scale.x)
		_drive_twist_samples += 1
		if not _is_driver_twisting():
			_drive_untwisted_frames += 1
		_slide.sample()
		var motion := InputEventMouseMotion.new()
		_push_mouse(
			motion,
			_hand.pointer_position - screw.get_slot_axis() * offset,
		)
		await get_tree().physics_frame


func _track_scale() -> void:
	_scale_samples += 1
	for screw in [_screw_left, _screw_right]:
		if not is_instance_valid(screw):
			continue
		_note_scale(screw.head.scale)
		if screw.mode == InteractionPoint.Mode.ACTIVE:
			_note_scale(screw.scale)


func _note_scale(value: Vector2) -> void:
	var change := (value - Vector2.ONE).abs()
	_largest_scale_change = maxf(
		_largest_scale_change,
		maxf(change.x, change.y),
	)


func _on_defect_added(
	defect: RepairQuality.Defect,
	_points: int,
	_global_position: Vector2,
) -> void:
	_defects.append(defect)
