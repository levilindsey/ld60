class_name AudioMain
extends Node2D


@export var theme_fade_duration_sec := 0.2

@export var mute_volume := -80.0

## Stream players, one per sound name. Their streams are the cleaned
## foley in `assets/audio/foley_cleaned/`, assigned on the nodes in
## `audio_main.tscn`. Sounds with several good takes use an
## AudioStreamRandomizer on the node, so each play picks a take. The
## humming is a one-off intro. StateMain plays it once when the game
## starts, after the title screen closes. It is not a theme and it
## never loops. The menu and main themes are in `assets/audio/music/`
## (the menu theme's BeepBox source is beside it); the end theme stays
## empty. Add new named entries here as needed.
##
## Foley direction (2026-10-19): `screw_drop` pools part drop 1/2
## with screw drop 1/3/5 for a screw hitting the bench;
## `part_drop_large` is part drop 4 for larger drawer parts landing;
## `drawer_rustle` pools parts rustle 1/2/3 for hovering an open
## drawer; `screw_pickup` pools parts separate 1/2 for picking a
## screw up; `screw_seated` pools parts together 2_b, pliers pinch
## 1/2 and screw drop into screws 2 for a screw placed in its hole;
## `snap`/`rattle_snap` pool rattle snap on 2/3/_a for a part or
## piece put back in place; `screw_twist_loop` loops screw twists
## while a screw is actively turning; `tool_set_down` pools the
## set-down-hammer takes for a tool landing in its holder;
## `tap_metal` is the tap when a screwdriver slides out;
## `hammer_whack` pools tap metal light/_a for hammer hits;
## `tool_pickup` pools tool pickup 3_a/4/5 for taking a tool.
##
## Refinement (same direction, repeated): `hammer_whack` is the
## light pool (tap metal light/_a) for light whacks on a part,
## piece or layer; `hammer_whack_heavy` pools every Hammer
## *metal* take in `tools/` for heavier whacks on the same;
## `hammer_wood` pools Hammer - wood 1/2 for a hammer that
## misses every part, piece and layer; `glug` pools glug small
## and glug small 2_a for squeezing glue; `rag_wipe` pools
## wipe 2/3/_a for the rag; `lid_pop` (also `pop`) pools lid
## pop 2_b, lid pop off 3/_a and lid pop_b for a part yanked
## or lifted out of its installed spot; `sigh` is the
## sigh-of-relief pool Level.win() plays at the end. `skid`
## pools the four wheels takes (foley round 5) for the
## toaster scooting around the bench.
@onready var STREAM_PLAYERS_BY_NAME := {
	"menu_theme" = %MenuTheme,
	"main_theme" = %MainTheme,
	"end_theme" = %EndTheme,
	"click" = %Click,
	"clunk" = %Clunk,
	"thud" = %Thud,
	"ding" = %Ding,
	"hmm" = %Hmm,
	"humming" = %Humming,
	"hmm_curious" = %HmmCurious,
	"hmm_appreciative" = %HmmAppreciative,
	"hmm_grumpy" = %HmmGrumpy,
	"hmm_frustrated" = %HmmFrustrated,
	"sigh_relief" = %SighRelief,
	"page_flip" = %PageFlip,
	"pages_flip" = %PagesFlip,
	"card_land" = %CardLand,
	"card_pickup" = %CardPickup,
	"scrawling" = %Scrawling,
	"creak" = %Creak,
	"ratchet" = %Ratchet,
	"scrape" = %Scrape,
	"skid" = %Skid,
	"pop" = %Pop,
	"zap" = %Zap,
	"blast" = %Blast,
	"grind" = %Grind,
	"whoosh" = %Whoosh,
	"snap" = %Snap,
	"drawer_open" = %DrawerOpen,
	"drawer_close" = %DrawerClose,
	"caw" = %Caw,
	"window_smack" = %WindowSmack,
	"screw_drop" = %ScrewDrop,
	"part_drop_large" = %Thud,
	"drawer_rustle" = %DrawerRustle,
	"screw_pickup" = %ScrewPickup,
	"screw_seated" = %ScrewSeated,
	"rattle_snap" = %Snap,
	"screw_twist_loop" = %ScrewTwistLoop,
	"screw_twists" = %ScrewTwistLoop,
	"tool_set_down" = %ToolSetDown,
	"tap_metal" = %TapMetal,
	"screwdriver_slide" = %TapMetal,
	"hammer_whack" = %HammerWhack,
	"hammer_whack_light" = %HammerWhack,
	"hammer_whack_heavy" = %HammerWhackHeavy,
	"hammer_wood" = %HammerWood,
	"hammer_miss" = %HammerWood,
	"tool_pickup" = %ToolPickup,
	"glug" = %GlueGlug,
	"glue_glug" = %GlueGlug,
	"rag_wipe" = %RagWipe,
	"wipe" = %RagWipe,
	"lid_pop" = %Pop,
	"sigh" = %SighRelief,
}

var initial_volumes := {}

var current_theme: AudioStreamPlayer
## The pitch of sounds started now. The tiny hammer raises it around its
## hits.
var sound_pitch_scale := 1.0
## True while the shop radio is broken: the main theme stays silent, even
## through a pause and resume.
var is_main_theme_cut_out := false
## True while a screw is actively turning. The screw-twists player
## loops for as long as this holds (see `start_screw_twist_loop()`).
var _is_screw_twist_looping := false


func _enter_tree() -> void:
	G.audio = self


func _ready() -> void:
	for player_name in STREAM_PLAYERS_BY_NAME:
		var player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[player_name]
		initial_volumes[player_name] = player.volume_db
	# Looping fallback: Godot 4's web AudioStreamWAV loop_mode is
	# unreliable on the AudioWorklet backend (loops fine on desktop,
	# doesn't loop on Chrome/Firefox web). Manually re-trigger play
	# on `finished`. Gated by `current_theme` so a stream that was
	# faded-out + paused doesn't auto-restart.
	%MenuTheme.finished.connect(_on_theme_finished.bind(%MenuTheme))
	%MainTheme.finished.connect(_on_theme_finished.bind(%MainTheme))
	%EndTheme.finished.connect(_on_theme_finished.bind(%EndTheme))
	%ScrewTwistLoop.finished.connect(_on_screw_twist_finished)


func _on_theme_finished(stream_player: AudioStreamPlayer) -> void:
	if current_theme != stream_player:
		return
	stream_player.play()


func _on_screw_twist_finished() -> void:
	if _is_screw_twist_looping:
		%ScrewTwistLoop.play()


## Starts the screw-twists loop. It plays until
## `stop_screw_twist_loop()`; the `finished` handler above
## re-triggers it so it loops on the web backend too.
func start_screw_twist_loop() -> void:
	_is_screw_twist_looping = true
	if %ScrewTwistLoop.stream == null:
		return
	if not %ScrewTwistLoop.playing:
		%ScrewTwistLoop.pitch_scale = sound_pitch_scale
		%ScrewTwistLoop.play()


## Stops the screw-twists loop at once.
func stop_screw_twist_loop() -> void:
	_is_screw_twist_looping = false
	if %ScrewTwistLoop.playing:
		%ScrewTwistLoop.stop()


## True while the screw-twists loop is meant to be playing.
func is_screw_twist_looping() -> bool:
	return _is_screw_twist_looping


func play_sound(sound_name: StringName, force_restart := false) -> void:
	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return
	if sound_name == &"screw_twist_loop" or sound_name == &"screw_twists":
		start_screw_twist_loop()
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if stream_player.stream == null:
		# Placeholder player with no stream assigned yet.
		return
	if not stream_player.playing or force_restart:
		stream_player.pitch_scale = sound_pitch_scale
		stream_player.play.call()


func stop_sound(sound_name: StringName) -> void:
	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return
	if sound_name == &"screw_twist_loop" or sound_name == &"screw_twists":
		stop_screw_twist_loop()
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if stream_player.playing:
		stream_player.stop()


func fade_to_theme(theme_name: String) -> void:
	var next_theme: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[theme_name]
	if is_instance_valid(current_theme) and current_theme != next_theme:
		fade_out(current_theme)
	current_theme = next_theme
	fade_in(current_theme, initial_volumes[theme_name])


func fade_to_menu_theme() -> void:
	fade_to_theme("menu_theme")


func fade_to_main_theme() -> void:
	fade_to_theme("main_theme")


func fade_to_end_theme() -> void:
	fade_to_theme("end_theme")


## Immediately fades out the current theme, waits `delay_sec`
## seconds, then fades in the end theme. Useful on game-win so
## there's a beat of silence between the main theme stopping
## and the end theme starting.
func fade_to_end_theme_after(delay_sec: float) -> void:
	if is_instance_valid(current_theme):
		fade_out(current_theme)
		current_theme = null
	if delay_sec > 0.0:
		await get_tree().create_timer(delay_sec, true).timeout
	current_theme = STREAM_PLAYERS_BY_NAME["end_theme"]
	fade_in(current_theme, initial_volumes["end_theme"])


func fade_in(stream_player: AudioStreamPlayer, volume: float) -> void:
	if stream_player.stream == null:
		# Placeholder player with no stream assigned yet.
		return
	if is_main_theme_cut_out and stream_player == %MainTheme:
		return

	if G.settings.mute_music:
		volume = mute_volume

	if not stream_player.playing:
		stream_player.volume_db = mute_volume
		stream_player.play.call()

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		stream_player,
		"volume_db",
		volume,
		theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with
	# overlapping tweens (the latest tween should end up winning).
	stream_player.stream_paused = false


func fade_out(stream_player: AudioStreamPlayer) -> void:
	if not stream_player.playing:
		return

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		stream_player,
		"volume_db",
		mute_volume,
		theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with
	# overlapping tweens (the latest tween should end up winning).
	stream_player.stream_paused = true


## Stops the main theme dead, until `restore_main_theme()`.
func cut_out_main_theme() -> void:
	is_main_theme_cut_out = true
	%MainTheme.stop()


## Starts the main theme again from the top, if it is the one playing.
func restore_main_theme() -> void:
	if not is_main_theme_cut_out:
		return
	is_main_theme_cut_out = false
	if current_theme == %MainTheme:
		%MainTheme.stream_paused = false
		%MainTheme.play()


## Plays a sound after a delay, running the timer on AudioMain itself
## so the sound fires even if the originating node (e.g. an entity on
## death) has been queue_freed in the interim. The delay holds while the
## game is paused.
func play_sound_delayed(
		sound_name: StringName,
		delay_sec: float,
		force_restart := true) -> void:
	if delay_sec > 0.0:
		await get_tree().create_timer(delay_sec, false).timeout
	play_sound(sound_name, force_restart)
