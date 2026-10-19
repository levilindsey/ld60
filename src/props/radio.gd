class_name Radio
extends Node2D
## The desk radio that the music plays from. While a theme plays, it
## squashes and stretches on each beat, synced to the music's playback
## position. When the music stops, it eases back to rest.
##
## The art is drawn above the node's origin, so the radio squashes and
## stretches about its base.
##
## The radio can glitch: the music slows and warbles, skips and hisses
## with static. Each effect has its own toggle so they can be
## auditioned on their own. It goes wonky during the items listed in
## `settings.radio_glitch_item_indices`, 8-16 seconds into the item
## (the "Radio" group in `settings.gd`). A hammer hit fixes it and
## starts a cooldown. In dev mode, R toggles the glitch.
##
## When the radio is the item on the bench, it breaks on the shelf (static,
## a jolt, the music cuts out) and hides while the item is repaired.


## How far the radio squashes and stretches on each beat, as a fraction of
## its size.
@export var stretch_amount: float = 0.025
## How quickly the motion fades in when the music starts and out when it
## stops. 2 takes half a second to go from still to full motion.
@export var fade_per_sec: float = 2.0
@export var beats_per_minute: float = 120.0

@export_group("Glitch")
## How quickly the glitch fades in and out, as a fraction of full glitch
## per second.
@export var glitch_fade_per_sec: float = 0.5

@export var is_slowdown_enabled: bool = true
## The music's pitch and speed at full glitch. 1 is normal.
@export var slowdown_pitch_scale: float = 0.75
## How far the pitch wobbles around the slowed pitch.
@export var warble_depth: float = 0.05
@export var warble_hz: float = 0.6

@export var is_skip_enabled: bool = true
## Average skips per second at full glitch.
@export var skips_per_sec: float = 0.3
## The furthest a skip jumps, backward or forward.
@export var skip_max_sec: float = 0.5

@export var is_static_enabled: bool = true
## The static's volume at full glitch.
@export var static_volume_db: float = -30.0

## The bounce's speed at full glitch, on top of the music's slowdown. 1 is
## the music's own speed.
@export var glitch_bounce_speed_scale: float = 0.4
## How far the radio sinks at full glitch, as a fraction of its height. It
## spreads sideways by half as much, like it's deflated.
@export var deflate_amount: float = 0.12

## Seconds a glitch runs before the radio highlights itself,
## when the player has not bonked it since the glitch started.
@export var glitch_highlight_delay_sec := 5.0

@export_group("Hit")
## How far a hammer hit squashes the radio, as a fraction of its height.
@export var hit_squash_amount: float = 0.15
## How quickly the radio springs back from a hit. 4 takes a quarter of a
## second.
@export var hit_recover_per_sec: float = 4.0

@export_group("Break")
## The static's volume as the radio breaks.
@export var break_static_volume_db: float = -12.0


var is_glitching := false
## True from the radio breaking until it is back on the shelf.
var is_away := false

var _motion_amount := 0.0
## Holds its last value while the music is stopped, so the motion eases
## out from where it was.
var _beat_angle := 0.0
## 0 plays normally; 1 is fully glitched.
var _glitch_amount := 0.0
var _warble_time := 0.0
var _cooldown_remaining_sec := 0.0
## Queue index of the item the trigger last armed for, and the
## seconds left before that item's glitch (-1: not armed).
var _trigger_item_index := -1
var _glitch_wait_remaining_sec := -1.0
## 1 right after a hammer hit; eases back to 0.
var _hit_amount := 0.0
## Seconds the current glitch has run, for the highlight.
var _glitch_elapsed_sec := 0.0
## True once the player bonks the radio during this glitch.
var _interacted_this_glitch := false
var _is_highlight_shown := false
var _art_material_before_highlight: Material


func _physics_process(delta: float) -> void:
	var target_amount := 1.0 if _is_music_playing() else 0.0
	_motion_amount = move_toward(
		_motion_amount,
		target_amount,
		fade_per_sec * delta,
	)
	_update_beat_angle(delta)
	# One beat per half turn.
	var stretch := stretch_amount * absf(sin(_beat_angle)) * _motion_amount
	_hit_amount = move_toward(_hit_amount, 0.0, hit_recover_per_sec * delta)
	var deflate := (
		deflate_amount * _glitch_amount
		+ hit_squash_amount * _hit_amount
	)
	%Art.scale = Vector2(
		(1.0 - stretch) * (1.0 + deflate / 2.0),
		(1.0 + stretch) * (1.0 - deflate),
	)

	_update_highlight(delta)
	_update_trigger(delta)
	_update_glitch(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not G.settings.dev_mode or is_away:
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		set_glitching(not is_glitching)


func set_glitching(value: bool) -> void:
	if is_glitching and not value:
		_cooldown_remaining_sec = G.settings.radio_glitch_cooldown_sec
	is_glitching = value
	if value:
		_glitch_elapsed_sec = 0.0
		_interacted_this_glitch = false
	else:
		_set_highlight_shown(false)
	G.print("Radio glitching: %s" % is_glitching)


## Counts a glitch the player has left alone. Past the delay
## the radio highlights itself until the glitch ends.
func _update_highlight(delta: float) -> void:
	if not is_glitching:
		_glitch_elapsed_sec = 0.0
		return
	if _interacted_this_glitch or _is_highlight_shown:
		return
	_glitch_elapsed_sec += delta
	if _glitch_elapsed_sec >= glitch_highlight_delay_sec:
		_set_highlight_shown(true)


## True while the ignored-glitch highlight is on the art.
func is_highlight_shown() -> bool:
	return _is_highlight_shown


func _set_highlight_shown(is_shown: bool) -> void:
	if _is_highlight_shown == is_shown:
		return
	_is_highlight_shown = is_shown
	if is_shown:
		_art_material_before_highlight = OutlineHint.apply_to_sprite(
			%Art
		)
	else:
		OutlineHint.remove_from_sprite(
			%Art, _art_material_before_highlight
		)
		_art_material_before_highlight = null


## Whether a hammer press at this point lands on the radio.
func is_struck_at(global_point: Vector2) -> bool:
	return (
		not is_away
		and %Art.get_rect().has_point(%Art.to_local(global_point))
	)


## Whether a point is over the radio's spot on the shelf, with some slack.
func is_over_spot(global_point: Vector2) -> bool:
	return (
		%Art.get_rect()
		.grow(%Art.get_rect().size.x * 0.25)
		.has_point(%Art.to_local(global_point))
	)


## The middle of the art at rest, in world pixels.
func get_art_center() -> Vector2:
	return to_global(%Art.offset)


## The art's scale at rest, in world terms.
func get_art_scale() -> float:
	return global_scale.x


## The radio crackles, jolts and goes quiet: the music cuts out.
func break_away() -> void:
	is_away = true
	is_glitching = false
	_set_highlight_shown(false)
	_glitch_amount = 0.0
	_hit_amount = 1.0
	if is_instance_valid(G.audio.current_theme):
		G.audio.current_theme.pitch_scale = 1.0
	G.audio.cut_out_main_theme()
	%Static.volume_db = break_static_volume_db
	%Static.play()


## The squash and stretch of the current beat, for the radio item on the
## bench to bounce along with the music.
func get_beat_scale() -> Vector2:
	var stretch := stretch_amount * absf(sin(_beat_angle)) * _motion_amount
	return Vector2(1.0 - stretch, 1.0 + stretch)


## The radio leaves the shelf to be the item on the bench.
func leave_shelf() -> void:
	%Static.stop()
	visible = false


## The fixed radio is back on the shelf, with a little squash.
func return_to_shelf() -> void:
	%Static.stop()
	is_away = false
	visible = true
	_hit_amount = 1.0


## A hammer hit at any strength bonks the radio and fixes a glitch.
func on_struck(_charge: float) -> void:
	_interacted_this_glitch = true
	_set_highlight_shown(false)
	G.audio.play_sound(&"thud", true)
	G.level.shake_camera(5.0, 0.15)
	_hit_amount = 1.0
	if is_glitching:
		set_glitching(false)


## Starts a glitch 8-16 seconds into each item listed in
## `radio_glitch_item_indices`. The fixed-item count is the current
## item's queue index: it ticks up as the previous item departs.
## Each listed item glitches once, and the wait is rolled when the
## item starts.
func _update_trigger(delta: float) -> void:
	if is_glitching or is_away:
		return
	if _cooldown_remaining_sec > 0.0:
		_cooldown_remaining_sec -= delta
		return
	if not is_instance_valid(G.session):
		return
	var item_index := G.session.fixed_item_count
	if item_index != _trigger_item_index:
		_trigger_item_index = item_index
		_glitch_wait_remaining_sec = -1.0
		if item_index in G.settings.radio_glitch_item_indices:
			_glitch_wait_remaining_sec = randf_range(
				G.settings.radio_glitch_delay_min_sec,
				G.settings.radio_glitch_delay_max_sec,
			)
	if _glitch_wait_remaining_sec < 0.0:
		return
	_glitch_wait_remaining_sec -= delta
	if _glitch_wait_remaining_sec <= 0.0:
		_glitch_wait_remaining_sec = -1.0
		set_glitching(true)


## Follows the music's playback position, so the bounce lands on the beat.
## While glitching, it runs on its own clock instead, slowed further by
## `glitch_bounce_speed_scale`, and syncs back once the glitch fades out.
func _update_beat_angle(delta: float) -> void:
	if not _is_music_playing():
		return
	if is_zero_approx(_glitch_amount):
		_beat_angle = (
			G.audio.current_theme.get_playback_position()
			* beats_per_minute / 60.0
			* PI
		)
		return
	_beat_angle += (
		delta
		* beats_per_minute / 60.0
		* PI
		* G.audio.current_theme.pitch_scale
		* lerpf(1.0, glitch_bounce_speed_scale, _glitch_amount)
	)


func _update_glitch(delta: float) -> void:
	var target_amount := 1.0 if is_glitching else 0.0
	if is_zero_approx(_glitch_amount) and is_zero_approx(target_amount):
		return
	_glitch_amount = move_toward(
		_glitch_amount,
		target_amount,
		glitch_fade_per_sec * delta,
	)
	_warble_time += delta

	if _is_music_playing():
		_update_slowdown()
		_update_skip(delta)
	_update_static()


func _update_slowdown() -> void:
	if not is_slowdown_enabled:
		G.audio.current_theme.pitch_scale = 1.0
		return
	# Two sines at unrelated rates, so the warble doesn't sound regular.
	var warble := (
		0.7 * sin(TAU * warble_hz * _warble_time)
		+ 0.3 * sin(TAU * warble_hz * 2.3 * _warble_time)
	)
	G.audio.current_theme.pitch_scale = (
		lerpf(1.0, slowdown_pitch_scale, _glitch_amount)
		+ warble_depth * warble * _glitch_amount
	)


func _update_skip(delta: float) -> void:
	if not is_skip_enabled:
		return
	if randf() >= skips_per_sec * _glitch_amount * delta:
		return
	var target_sec := (
		G.audio.current_theme.get_playback_position()
		+ randf_range(-skip_max_sec, skip_max_sec)
	)
	G.audio.current_theme.seek(clampf(
		target_sec,
		0.0,
		G.audio.current_theme.stream.get_length(),
	))


func _update_static() -> void:
	if not is_static_enabled or is_zero_approx(_glitch_amount):
		%Static.stop()
		return
	%Static.volume_db = static_volume_db + linear_to_db(_glitch_amount)
	if not %Static.playing:
		%Static.play()


func _is_music_playing() -> bool:
	return (
		is_instance_valid(G.audio)
		and is_instance_valid(G.audio.current_theme)
		and G.audio.current_theme.playing
		and not G.audio.current_theme.stream_paused
	)
