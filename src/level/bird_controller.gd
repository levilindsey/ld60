class_name BirdController
extends Node
## Bread the bird. When the repairable at `SMACK_ITEM_INDEX`
## in the played order lands, the bird smacks into the window
## `SMACK_DELAY_SEC` seconds into it. From then on it peeks
## out of the tree every so often for the rest of the session;
## it never peeks before the smack. The two animations are the
## `%BirdSmack` and `%BirdPeak` scene instances outside the
## window.


## The played-order index of the repairable the smack is
## scheduled for (0 is the first item, so 2 is the third).
const SMACK_ITEM_INDEX := 2
const SMACK_DELAY_SEC := 17.0
## Seconds into the smack animation when the bird reaches the
## glass. It grows until frame 15 of the art (the 15th frame
## shown; the splat near the end is the aftermath), so at
## 15 fps the smack and caw sounds, and the window shake,
## land 14 frames in.
const SMACK_HIT_SEC := 0.93
const PEAK_INTERVAL_MIN_SEC := 20.0
const PEAK_INTERVAL_MAX_SEC := 45.0
## Seconds the peek takes to fade out once its animation ends.
const PEAK_FADE_SEC := 0.5
## How hard the window jumps when the bird hits it, in pixels.
## Each hop of the shake is shorter and weaker.
const WINDOW_SHAKE_PX := 9.0

var _has_smacked := false
var _start_slam_checked := false
var _item: Repairable
var _window_home := Vector2.ZERO
var _window_tween: Tween
var _peak_fade_tween: Tween


func _ready() -> void:
	(%BirdPeak as Node2D).hide()
	_window_home = (%Window as Sprite2D).position
	(%BirdSmack as BirdSmack).finished.connect(_on_smack_done)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(G.level):
		return
	# The level is built behind the title screen, so the
	# at-start flag is read on the first frame of actual play,
	# not in `_ready()` (which fires while the title is up).
	if not _start_slam_checked:
		_start_slam_checked = true
		if G.settings.show_bird_slam_at_start:
			G.time.set_timeout(_play_smack, SMACK_DELAY_SEC)
	var item := G.level.active_repairable
	if item == _item:
		return
	_item = item
	if not is_instance_valid(item):
		return
	item.landed.connect(_on_item_landed, CONNECT_ONE_SHOT)


func _on_item_landed() -> void:
	if _has_smacked:
		return
	if not is_instance_valid(G.level):
		return
	if G.level.get_active_item_index() != SMACK_ITEM_INDEX:
		return
	G.time.set_timeout(_play_smack, SMACK_DELAY_SEC)


func _play_smack() -> void:
	if _has_smacked:
		return
	_has_smacked = true
	(%BirdSmack as BirdSmack).play_smack()
	G.time.set_timeout(_play_smack_hit, SMACK_HIT_SEC)


func _play_smack_hit() -> void:
	G.audio.play_sound(&"window_smack")
	_shake_window()

	await get_tree().create_timer(0.15).timeout
	G.audio.play_sound(&"caw")


## Kicks the window sprite around its home spot for a few
## quickly weakening hops, then puts it back.
func _shake_window() -> void:
	var window := %Window as Sprite2D
	if is_instance_valid(_window_tween):
		_window_tween.kill()
	_window_tween = create_tween()
	_window_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var strength := WINDOW_SHAKE_PX
	for hop in 6:
		var offset := Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength) * 0.6,
		)
		_window_tween.tween_property(
			window, "position", _window_home + offset, 0.045
		)
		strength *= 0.62
	_window_tween.tween_property(
		window, "position", _window_home, 0.05
	)


## The smack (flight, fall and cleanup) is over: the peeks may
## start.
func _on_smack_done() -> void:
	_roll_next_peak()


## Waits a fresh random interval, then peeks. Re-rolled after
## every peek, so no two gaps are alike.
func _roll_next_peak() -> void:
	G.time.set_timeout(
		_play_peak,
		randf_range(PEAK_INTERVAL_MIN_SEC, PEAK_INTERVAL_MAX_SEC),
	)


func _play_peak() -> void:
	var root := %BirdPeak as Node2D
	var sprite := root.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(_peak_fade_tween):
		_peak_fade_tween.kill()
	# Always back to full strength for the new peek.
	root.modulate.a = 1.0
	root.show()
	sprite.play(&"peak")
	# The peek lasts one pass through its frames, loop or not,
	# then fades out.
	var frames := sprite.sprite_frames
	var cycle_sec := (
		float(frames.get_frame_count(&"peak"))
		/ frames.get_animation_speed(&"peak")
	)
	G.time.set_timeout(_fade_peak_out, cycle_sec)


func _fade_peak_out() -> void:
	var root := %BirdPeak as Node2D
	_peak_fade_tween = create_tween()
	_peak_fade_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_peak_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	_peak_fade_tween.tween_property(
		root, "modulate:a", 0.0, PEAK_FADE_SEC
	)
	_peak_fade_tween.tween_callback(_finish_peak)


func _finish_peak() -> void:
	var root := %BirdPeak as Node2D
	(root.get_node("AnimatedSprite2D") as AnimatedSprite2D).stop()
	root.hide()
	_roll_next_peak()
