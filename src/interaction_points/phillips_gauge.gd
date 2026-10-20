class_name PhillipsGauge
extends Node2D
## The Phillips speed gauge (docs/design/phillips.md). It draws
## the circle speed as a needle on a sweep, the target band in
## green, and the grip as a ring around the hub.


const _RADIUS := 34.0
## The sweep runs the full circle counter-clockwise while a screw
## comes out: zero speed sits at the bottom, and faster speeds
## swing the needle up the right side, over the top and down the
## left, back to the bottom where the fast end meets the slow
## end. While a screw is driven in (tightening), the sweep mirrors
## and runs clockwise instead, so the gauge turns the way the
## screw does.
const _SWEEP_DEG := -360.0
const _START_DEG := 90.0
## The mirrored sweep's start: the same seam at the bottom.
const _START_TIGHTENING_DEG := 90.0
## The gauge's face: plain while the strip-out meter has room,
## reddening only in its low end.
const _BACKGROUND := Color(0.1, 0.1, 0.12, 0.85)
const _FAILURE_BACKGROUND := Color(0.34, 0.09, 0.08, 0.92)
const _ZONE_COLOR := Color(0.4, 1.0, 0.45)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var screw := get_parent() as PhillipsScrew
	if not is_instance_valid(screw) or not screw.is_gauge_shown():
		return
	var center := Vector2.ZERO
	draw_circle(center, _RADIUS + 6.0, _get_background_color(screw))
	draw_arc(
		center, _RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true
	)
	_draw_zone(center, screw)
	if not screw.has_started_dragging():
		_draw_drag_hint(center, screw)
	# The grip ring around the hub.
	var grip_color := Color(1.0, 0.3, 0.25).lerp(
		Color(0.4, 1.0, 0.45), clampf(screw.grip_meter, 0.0, 1.0)
	)
	draw_arc(
		center,
		12.0,
		-PI * 0.5,
		-PI * 0.5 + clampf(screw.grip_meter, 0.0, 1.0) * TAU,
		32,
		grip_color,
		4.0,
		true,
	)
	# The needle is the circle speed right now.
	var needle_color := (
		Color(0.4, 1.0, 0.45)
		if screw.is_in_range()
		else Color(1.0, 0.35, 0.3)
	)
	var needle_angle := _speed_to_angle(
		maxf(screw.pressure_rad_per_sec, 0.0)
	)
	var needle_end := center + Vector2(
		cos(needle_angle), sin(needle_angle)
	) * (_RADIUS - 4.0)
	draw_line(center, needle_end, needle_color, 3.0, true)
	draw_circle(center, 4.0, Color.WHITE)


## Until the player starts circling, three chevrons chase
## each other around the dial in the turning direction:
## drag in circles, this way. They vanish the moment the
## drag starts, so they only teach, never decorate.
func _draw_drag_hint(center: Vector2, screw: PhillipsScrew) -> void:
	var direction := 1.0 if screw.is_install_mode else -1.0
	var spin := (
		Time.get_ticks_msec() / 1000.0 * 1.6 * direction
	)
	var pulse := 0.55 + 0.35 * sin(
		Time.get_ticks_msec() / 1000.0 * 4.0
	)
	var color := Color(1.0, 0.95, 0.6, pulse)
	var hint_radius := _RADIUS + 15.0
	for chevron in 3:
		var angle := spin + chevron * TAU / 3.0
		var tip := center + Vector2(cos(angle), sin(angle)) * hint_radius
		var tangent := Vector2(-sin(angle), cos(angle)) * direction
		var radial := Vector2(cos(angle), sin(angle))
		draw_line(
			tip - tangent * 7.0 - radial * 5.0, tip, color, 3.0, true
		)
		draw_line(
			tip - tangent * 7.0 + radial * 5.0, tip, color, 3.0, true
		)


## The face color right now: plain until the strip-out meter
## reaches its low end, then redder as empty approaches.
func _get_background_color(screw: PhillipsScrew) -> Color:
	return _BACKGROUND.lerp(
		_FAILURE_BACKGROUND, screw.get_failure_share()
	)


## Draws the green zone, in two arcs when it straddles the seam
## at the bottom of the dial.
func _draw_zone(center: Vector2, screw: PhillipsScrew) -> void:
	var cycle := maxf(G.settings.phillips_gauge_max_rad_per_sec, 0.01)
	var half_width := screw.get_zone_width_rad_per_sec() / 2.0
	var zone_center := screw.get_zone_center_rad_per_sec()
	var low := zone_center - half_width
	var high := zone_center + half_width
	if low < 0.0:
		_draw_zone_segment(center, 0.0, high)
		_draw_zone_segment(center, cycle + low, cycle)
	elif high > cycle:
		_draw_zone_segment(center, low, cycle)
		_draw_zone_segment(center, 0.0, high - cycle)
	else:
		_draw_zone_segment(center, low, high)


## One arc of the zone, between two speeds inside the dial's
## cycle. The sweep maps the faster speed to the smaller angle,
## so the ends are ordered before drawing.
func _draw_zone_segment(
	center: Vector2,
	from_speed: float,
	to_speed: float,
) -> void:
	if to_speed - from_speed < 0.01:
		return
	draw_arc(
		center,
		_RADIUS,
		minf(_speed_to_angle(from_speed), _speed_to_angle(to_speed)),
		maxf(_speed_to_angle(from_speed), _speed_to_angle(to_speed)),
		24,
		_ZONE_COLOR,
		7.0,
		true,
	)


## Maps a speed to its dial angle. Speeds past the top are not
## clamped: the needle keeps wrapping around the seam instead of
## pinning at the bottom while the zone travels on without it.
func _speed_to_angle(speed_rad_per_sec: float) -> float:
	var share := (
		maxf(speed_rad_per_sec, 0.0)
		/ maxf(G.settings.phillips_gauge_max_rad_per_sec, 0.01)
	)
	var screw := get_parent() as PhillipsScrew
	if is_instance_valid(screw) and screw.is_install_mode:
		# Tightening: drag clockwise, turn clockwise, and the
		# gauge sweeps clockwise to match.
		return deg_to_rad(
			_START_TIGHTENING_DEG - _SWEEP_DEG * share,
		)
	return deg_to_rad(_START_DEG + _SWEEP_DEG * share)
