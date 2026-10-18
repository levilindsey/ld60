class_name PhillipsScrew
extends Screw
## A Phillips screw (docs/design/phillips.md). The player drags
## in circles around the head. Circling at a speed inside the
## target band turns the screw. Too slow or too fast does not
## turn it, and the grip drains. An empty grip cams the bit out
## and the screw takes 1 damage.


## Seconds of circling the speed is averaged over.
const _SPEED_WINDOW_SEC := 0.3

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
var _pending_angle := 0.0
var _last_pointer_angle := 0.0
var _has_last_pointer_angle := false
var _active_sec := 0.0
var _samples: Array[Vector2] = []
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


## True while the circle speed sits in the target band.
func is_in_range() -> bool:
	return (
		pressure_rad_per_sec >= G.settings.phillips_speed_min_rad_per_sec
		and pressure_rad_per_sec
		<= G.settings.phillips_speed_max_rad_per_sec
	)


## True while the gauge should draw itself.
func is_gauge_shown() -> bool:
	return mode == Mode.ACTIVE


## The hand calls this on every pointer motion while this screw
## owns the pointer. Motion around the head builds the circle
## speed. Motion in the wrong direction counts against it.
func on_pointer_moved(_global_position: Vector2) -> void:
	if not is_instance_valid(G.level):
		return
	var pointer := G.level.hand.pointer_position
	var offset := pointer - head.global_position
	if offset.length() < 4.0:
		_has_last_pointer_angle = false
		return
	var angle := offset.angle()
	if _has_last_pointer_angle:
		_pending_angle += wrapf(
			angle - _last_pointer_angle, -PI, PI
		)
	_last_pointer_angle = angle
	_has_last_pointer_angle = true


## A finger can land anywhere, so circling counts from the press.
func on_pointer_pressed(_global_position: Vector2) -> void:
	_has_last_pointer_angle = false


func _start_microgame() -> void:
	_turned_rad = 0.0
	_pending_angle = 0.0
	_samples.clear()
	_active_sec = 0.0
	pressure_rad_per_sec = 0.0
	_has_last_pointer_angle = false
	intro_left = G.settings.phillips_intro_sec
	grip_meter = (
		G.settings.phillips_install_meter_start
		if is_install_mode
		else G.settings.phillips_meter_start
	)
	G.level.hand.set_input_owner(self)


func _advance(delta: float) -> void:
	_active_sec += delta
	# The dragged angle this frame, signed for the turning way.
	var correct_angle := (
		-_pending_angle if not is_install_mode else _pending_angle
	)
	_pending_angle = 0.0
	_samples.append(Vector2(_active_sec, correct_angle))
	while (
		not _samples.is_empty()
		and _samples[0].x < _active_sec - _SPEED_WINDOW_SEC
	):
		_samples.pop_front()
	var window_angle := 0.0
	for sample in _samples:
		window_angle += sample.y
	pressure_rad_per_sec = window_angle / _SPEED_WINDOW_SEC

	if intro_left > 0.0:
		intro_left -= delta
		return

	if is_in_range():
		grip_meter = minf(
			grip_meter + G.settings.phillips_fill_rate * delta, 1.0
		)
		if correct_angle > 0.0:
			_turned_rad += correct_angle
			_apply_turn()
			if _turned_rad >= _get_total_rad():
				_complete()
				return
	elif not never_drains:
		grip_meter -= G.settings.phillips_drain_rate * delta
		if grip_meter <= 0.0:
			_cam_out()


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
