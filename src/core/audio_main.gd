class_name AudioMain
extends Node2D


@export var theme_fade_duration_sec := 0.2

@export var mute_volume := -80.0

## Placeholder stream players. Assign actual AudioStream assets on
## the corresponding nodes in `audio_main.tscn` as audio lands during
## the jam, and add new named entries here as needed.
@onready var STREAM_PLAYERS_BY_NAME := {
	"menu_theme" = %MenuTheme,
	"main_theme" = %MainTheme,
	"end_theme" = %EndTheme,
	"click" = %Click,
}

var initial_volumes := {}

var current_theme: AudioStreamPlayer


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


func _on_theme_finished(stream_player: AudioStreamPlayer) -> void:
	if current_theme != stream_player:
		return
	stream_player.play()


func play_sound(sound_name: StringName, force_restart := false) -> void:
	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if stream_player.stream == null:
		# Placeholder player with no stream assigned yet.
		return
	if not stream_player.playing or force_restart:
		stream_player.play.call()


func stop_sound(sound_name: StringName) -> void:
	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if stream_player.playing:
		stream_player.stop()


func fade_to_theme(theme_name: String) -> void:
	if is_instance_valid(current_theme):
		fade_out(current_theme)
	current_theme = STREAM_PLAYERS_BY_NAME[theme_name]
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


## Plays a sound after a delay, running the timer on AudioMain itself
## so the sound fires even if the originating node (e.g. an entity on
## death) has been queue_freed in the interim.
func play_sound_delayed(
		sound_name: StringName,
		delay_sec: float,
		force_restart := true) -> void:
	if delay_sec > 0.0:
		await get_tree().create_timer(delay_sec, true).timeout
	play_sound(sound_name, force_restart)
