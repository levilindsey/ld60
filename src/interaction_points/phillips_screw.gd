class_name PhillipsScrew
extends Screw
## A Phillips screw (docs/design/phillips.md). The player drags
## in circles. The circle speed comes from how fast the drag's
## direction turns, never from where the screw sits, so shaky
## little circles count the same as neat big ones. The green zone
## on the gauge keeps sliding the one way at an ever changing
## pace, wrapping at the end of the sweep, so the player must
## keep speeding up and slowing down to stay in it. Circling at a
## speed inside the zone turns
## the screw. Too slow or too fast does not turn it, and the grip
## drains. An empty grip cams the bit out and the screw takes 1
## damage.


## Seconds of turning the speed is averaged over.
const _TURN_WINDOW_SEC := 0.45

## Sparks at the head when the bit cams out.
@export var sparks: CPUParticles2D
## The speed gauge beside the screw.
@export var gauge: PhillipsGauge
## Full turns that take the screw out.
@export var turns_needed := 4.8
## Scales how hard the screw is: 1 is normal. Higher narrows the
## green zone, slides it faster and drains the grip faster.
@export_range(0.5, 2.0, 0.05) var difficulty := 1.0
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
## Turning dragged so far this engage, either way, in radians.
## The microgame only starts once it passes the start threshold:
## before that the grip and the screw hold still.
var _drag_total_rad := 0.0
var _has_started_dragging := false
## Where the green zone sits and how fast it is climbing, in
## radians per second. The climb rate eases toward a fresh random
## target every second or two. The zone only ever climbs: at the
## fast end it wraps back to the slow end and keeps climbing, so
## it never reverses direction mid-game.
var _zone_center_rad_per_sec := 0.0
var _zone_climb_rad_per_sec := 0.0
var _zone_target_climb_rad_per_sec := 0.0
var _zone_retarget_left_sec := 0.0
var _zone_random := RandomNumberGenerator.new()
var _is_in_band := false
var _range_share := 0.0
var _is_cam_out_paused := false
var _pause_tween: Tween


func _ready() -> void:
	super._ready()
	type = Type.PHILLIPS_SCREW
	G.check(is_instance_valid(sparks))
	G.check(is_instance_valid(gauge))
	_zone_random.randomize()
	# The zone starts where the fixed band used to sit.
	_zone_center_rad_per_sec = (
		(
			G.settings.phillips_speed_min_rad_per_sec
			+ G.settings.phillips_speed_max_rad_per_sec
		)
		/ 2.0
	)
	_pick_zone_target()


func _physics_process(delta: float) -> void:
	if mode == Mode.ACTIVE and is_instance_valid(engaged_tool):
		_advance(delta)
	super._physics_process(delta)


## The driver's working end sits on the head while it turns.
func place_engaged_tool() -> void:
	engaged_tool.place_work_end(head.global_position)


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


## True once the player has dragged around past the start
## threshold this engage, so the grip and the screw may move.
func has_started_dragging() -> bool:
	return _has_started_dragging


## How far the screw has turned toward done, from 0 to 1.
func get_success_share() -> float:
	return clampf(_turned_rad / _get_total_rad(), 0.0, 1.0)


## How close the grip is to empty, from 0 (at its starting fill)
## to 1 (about to cam out).
func get_failure_share() -> float:
	var start := (
		G.settings.phillips_install_meter_start
		if is_install_mode
		else G.settings.phillips_meter_start
	)
	return clampf((start - grip_meter) / maxf(start, 0.01), 0.0, 1.0)


## True while the circle speed counts as in the target band.
## The band is sticky: once in, the speed may stray a grace
## past either end before it counts as out.
func is_in_range() -> bool:
	return _is_in_band


## The circle speed at the middle of the green zone. The zone is
## cyclic: it can straddle the dial's seam, where the fast end
## wraps into the slow end.
func get_zone_center_rad_per_sec() -> float:
	return _zone_center_rad_per_sec


## The green zone's width for this screw, in radians per second.
func get_zone_width_rad_per_sec() -> float:
	return _get_zone_width()


## The zone width for this screw: the setting, narrowed by
## difficulty.
func _get_zone_width() -> float:
	return maxf(
		G.settings.phillips_zone_width_rad_per_sec / difficulty, 1.2
	)


## True while the gauge should draw itself.
func is_gauge_shown() -> bool:
	return mode == Mode.ACTIVE


## A finger can land anywhere, so circling counts from the press.
func on_pointer_pressed(_global_position: Vector2) -> void:
	_has_last_pointer_position = false
	_has_last_heading = false


func _start_microgame() -> void:
	# The turns so far are kept: camming out and re-engaging picks
	# up where the screw left off. A fresh screw starts at 0, and
	# set_install_mode() zeroes it for the drive home.
	_turn_samples.clear()
	_drag_total_rad = 0.0
	_has_started_dragging = false
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
	_update_zone(delta)

	if intro_left > 0.0:
		intro_left -= delta
		return

	if not _has_started_dragging:
		# Not circling yet: the grip and the screw hold still.
		_has_started_dragging = (
			_drag_total_rad >= G.settings.phillips_start_drag_rad
		)
		if not _has_started_dragging:
			return

	_update_band()
	# The grip swings between filling and draining over a few
	# tenths of a second, so a brief stray costs almost nothing.
	# Only the true band fills it. The sticky band above only
	# keeps the screw turning through a stray.
	var meter_blend := 1.0 - exp(
		-delta / maxf(G.settings.phillips_meter_smoothing_sec, 0.01)
	)
	_range_share += (
		(1.0 if _is_in_true_band() else 0.0) - _range_share
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
			- G.settings.phillips_drain_rate
			* difficulty
			* (1.0 - _range_share)
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


## Slides the green zone around the gauge: the center climbs at a
## pace that eases toward a fresh random target every second or
## two, around the dial's full circle and through its seam at the
## bottom. It never turns around, so on the gauge it keeps moving
## the one rotational way the mode calls for (counter-clockwise
## coming out, clockwise tightening, through the gauge's mirror).
func _update_zone(delta: float) -> void:
	_zone_retarget_left_sec -= delta
	if _zone_retarget_left_sec <= 0.0:
		_pick_zone_target()
	var blend := 1.0 - exp(-delta / 0.7)
	_zone_climb_rad_per_sec += (
		(_zone_target_climb_rad_per_sec - _zone_climb_rad_per_sec)
		* blend
	)
	# The speed dial is a full circle, so the center wraps around
	# its seam and the zone travels the whole circumference
	# without ever jumping.
	_zone_center_rad_per_sec = wrapf(
		_zone_center_rad_per_sec + _zone_climb_rad_per_sec * delta,
		0.0,
		maxf(G.settings.phillips_gauge_max_rad_per_sec, 0.01),
	)


## Picks the zone's next pace and how long to keep it.
func _pick_zone_target() -> void:
	_zone_target_climb_rad_per_sec = difficulty * _zone_random.randf_range(
		G.settings.phillips_zone_move_min_rad_per_sec,
		G.settings.phillips_zone_move_max_rad_per_sec,
	)
	_zone_retarget_left_sec = _zone_random.randf_range(
		G.settings.phillips_zone_retarget_min_sec,
		G.settings.phillips_zone_retarget_max_sec,
	)


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
				_drag_total_rad += absf(turn)
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


## Signed distance from the zone's center to a speed, around the
## dial's cycle, where the fast end wraps into the slow end.
func _zone_distance(speed_rad_per_sec: float) -> float:
	var cycle := maxf(G.settings.phillips_gauge_max_rad_per_sec, 0.01)
	return wrapf(
		speed_rad_per_sec - _zone_center_rad_per_sec,
		-cycle / 2.0,
		cycle / 2.0,
	)


## True while a speed sits inside the zone, plus an extra half
## width of slack. Circling the wrong way never counts, and
## neither does circling faster than the dial's top: that is
## past the seam, not around it.
func _is_speed_in_zone(
	speed_rad_per_sec: float,
	extra_half_width: float,
) -> bool:
	if speed_rad_per_sec < 0.0:
		return false
	if speed_rad_per_sec > maxf(
		G.settings.phillips_gauge_max_rad_per_sec, 0.01
	):
		return false
	return (
		absf(_zone_distance(speed_rad_per_sec))
		<= _get_zone_width() / 2.0 + extra_half_width
	)


## True while the speed sits inside the band's own edges.
func _is_in_true_band() -> bool:
	return _is_speed_in_zone(pressure_rad_per_sec, 0.0)


## Enters the band at its edges and only leaves it a grace past
## them, so hovering on an edge does not flicker.
func _update_band() -> void:
	var grace := (
		G.settings.phillips_band_grace_rad_per_sec if _is_in_band else 0.0
	)
	_is_in_band = _is_speed_in_zone(pressure_rad_per_sec, grace)


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
