class_name PhillipsScrew
extends Screw
## A Phillips screw (docs/design/phillips.md). The player drags
## in circles. The circle speed comes from how fast the drag's
## direction turns, never from where the screw sits, so shaky
## little circles count the same as neat big ones. Circling at a
## speed inside the target band turns the screw. Too slow or too
## fast does not turn it, and the grip drains. An empty grip
## cams the bit out and the screw takes 1 damage.


## Seconds of turning the speed is averaged over.
const _TURN_WINDOW_SEC := 0.45

## Sparks at the head when the bit cams out.
@export var sparks: CPUParticles2D
## The speed gauge beside the screw.
@export var gauge: PhillipsGauge
## Full turns that take the screw out.
@export var turns_needed := 2.0
## The first Phillips screw of the game need never cam out.
@export var never_drains := false

## Grip left, from 0 to 1. An empty grip cams out.
var grip_meter := 0.3
## Circle speed in the turning direction, in radians per second.
var pressure_rad_per_sec := 0.0
## Grace seconds left at the start of an engage.
var intro_left := 0.0

var _turned_rad := 0.0
var _last_pointer_position := Vector2.ZERO
var _has_last_pointer_position := false
var _last_heading := 0.0
var _has_last_heading := false
var _active_sec := 0.0
var _turn_samples: Array[Vector2] = []
var _frame_correct_turn := 0.0
var _is_in_band := false
var _range_share := 0.0
var _is_cam_out_paused := false
var _pause_tween: Tween


func _ready() -> void:
	super._ready()
	type = Type.PHILLIPS_SCREW
	G.check(is_instance_valid(sparks))
	G.check(is_instance_valid(gauge))


func _physics_process(delta: float) -> void:
	if mode == Mode.ACTIVE and is_instance_valid(engaged_tool):
		_advance(delta)
	super._physics_process(delta)


## The driver's tip sits on the head while it turns.
func place_engaged_tool() -> void:
	engaged_tool.place_tip(head.global_position)


## Lets go of the driver and gives the pointer back to the hand.
func release_tool() -> void:
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)
	super.release_tool()


func can_engage() -> bool:
	return not _is_cam_out_paused and super.can_engage()


func set_install_mode() -> void:
	super.set_install_mode()
	_turned_rad = 0.0
	pressure_rad_per_sec = 0.0


## True while the circle speed counts as in the target band.
## The band is sticky: once in, the speed may stray a grace
## past either end before it counts as out.
func is_in_range() -> bool:
	return _is_in_band


## True while the gauge should draw itself.
func is_gauge_shown() -> bool:
	return mode == Mode.ACTIVE


## A finger can land anywhere, so circling counts from the press.
func on_pointer_pressed(_global_position: Vector2) -> void:
	_has_last_pointer_position = false
	_has_last_heading = false


func _start_microgame() -> void:
	_turned_rad = 0.0
	_turn_samples.clear()
	_active_sec = 0.0
	pressure_rad_per_sec = 0.0
	_has_last_pointer_position = false
	_has_last_heading = false
	_is_in_band = false
	_range_share = 0.0
	intro_left = G.settings.phillips_intro_sec
	grip_meter = (
		G.settings.phillips_install_meter_start
		if is_install_mode
		else G.settings.phillips_meter_start
	)
	G.level.hand.set_input_owner(self)


func _advance(delta: float) -> void:
	_active_sec += delta
	_update_circle_speed(delta)

	if intro_left > 0.0:
		intro_left -= delta
		return

	_update_band()
	# The grip swings between filling and draining over a few
	# tenths of a second, so a brief stray costs almost nothing.
	var meter_blend := 1.0 - exp(
		-delta / maxf(G.settings.phillips_meter_smoothing_sec, 0.01)
	)
	_range_share += (
		(1.0 if _is_in_band else 0.0) - _range_share
	) * meter_blend
	if never_drains:
		grip_meter = minf(
			grip_meter
			+ G.settings.phillips_fill_rate * _range_share * delta,
			1.0,
		)
	else:
		grip_meter += (
			G.settings.phillips_fill_rate * _range_share
			- G.settings.phillips_drain_rate * (1.0 - _range_share)
		) * delta
		grip_meter = clampf(grip_meter, 0.0, 1.0)

	if _is_in_band and _frame_correct_turn > 0.0:
		_turned_rad += _frame_correct_turn
		_apply_turn()
		if _turned_rad >= _get_total_rad():
			_complete()
			return
	if not never_drains and grip_meter <= 0.0:
		_cam_out()


## Reads the drag's turning from recent pointer steps and
## smooths it into `pressure_rad_per_sec`. A step only counts
## once it is long enough to have a trustworthy direction.
## Turning the wrong way reads as a negative speed.
func _update_circle_speed(delta: float) -> void:
	_frame_correct_turn = 0.0
	if not is_instance_valid(G.level):
		return
	var pointer := G.level.hand.pointer_position
	if not _has_last_pointer_position:
		_last_pointer_position = pointer
		_has_last_pointer_position = true
	else:
		var step := pointer - _last_pointer_position
		if step.length() >= G.settings.phillips_min_segment_px:
			var heading := step.angle()
			if _has_last_heading:
				var turn := wrapf(heading - _last_heading, -PI, PI)
				_turn_samples.append(Vector2(_active_sec, turn))
				_frame_correct_turn = (
					turn if is_install_mode else -turn
				)
			_last_heading = heading
			_has_last_heading = true
			_last_pointer_position = pointer
	while (
		not _turn_samples.is_empty()
		and _turn_samples[0].x < _active_sec - _TURN_WINDOW_SEC
	):
		_turn_samples.pop_front()
	var window_turn := 0.0
	for sample in _turn_samples:
		window_turn += sample.y
	var raw_rate := window_turn / _TURN_WINDOW_SEC
	var correct_rate := raw_rate if is_install_mode else -raw_rate
	var blend := 1.0 - exp(
		-delta / maxf(G.settings.phillips_speed_smoothing_sec, 0.01)
	)
	pressure_rad_per_sec += (correct_rate - pressure_rad_per_sec) * blend


## Enters the band at its edges and only leaves it a grace past
## them, so hovering on an edge does not flicker.
func _update_band() -> void:
	var low := G.settings.phillips_speed_min_rad_per_sec
	var high := G.settings.phillips_speed_max_rad_per_sec
	if _is_in_band:
		var grace := G.settings.phillips_band_grace_rad_per_sec
		_is_in_band = (
			pressure_rad_per_sec >= low - grace
			and pressure_rad_per_sec <= high + grace
		)
	else:
		_is_in_band = (
			pressure_rad_per_sec >= low
			and pressure_rad_per_sec <= high
		)


## Turns the head and feeds the slide from how far it has turned.
func _apply_turn() -> void:
	var total := _get_total_rad()
	var share := clampf(_turned_rad / total, 0.0, 1.0)
	if is_install_mode:
		head.rotation = (
			_home_head_rotation - LOOSE_TURN_RAD + _turned_rad
		)
		slide = 1.0 - share
	else:
		head.rotation = _home_head_rotation - _turned_rad
		slide = share


func _complete() -> void:
	if is_install_mode:
		head.rotation = _home_head_rotation
		install()
	else:
		remove()


## The bit cams out: a scrape, sparks, and the driver hops back
## to the hand. The turns so far are kept, like a flathead unseat.
func _cam_out() -> void:
	G.audio.play_sound(&"scrape", true)
	sparks.global_position = head.global_position
	sparks.restart()
	var driver := engaged_tool
	mode = Mode.UNSTARTED
	release_tool()
	if is_instance_valid(driver):
		driver.ease_follow_offset_from(
			driver.follow_offset + Vector2(0.0, -14.0)
		)
	grip_meter = G.settings.phillips_meter_start
	pressure_rad_per_sec = 0.0
	_is_cam_out_paused = true
	if is_instance_valid(_pause_tween):
		_pause_tween.kill()
	_pause_tween = create_tween()
	_pause_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pause_tween.tween_interval(G.settings.phillips_cam_out_pause_sec)
	_pause_tween.tween_callback(_end_cam_out_pause)
	take_damage(1)


func _end_cam_out_pause() -> void:
	_is_cam_out_paused = false


## Radians to turn in total: out by full turns, in by the loose
## turn the screw sits back by.
func _get_total_rad() -> float:
	if is_install_mode:
		return LOOSE_TURN_RAD
	return turns_needed * TAU
