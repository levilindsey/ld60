class_name PhillipsGauge
extends Node2D
## The Phillips speed gauge (docs/design/phillips.md). It draws
## the circle speed as a needle on a sweep, the target band in
## green, and the grip as a ring around the hub.


const _RADIUS := 34.0
const _SWEEP_DEG := 240.0
const _START_DEG := 150.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var screw := get_parent() as PhillipsScrew
	if not is_instance_valid(screw) or not screw.is_gauge_shown():
		return
	var center := Vector2.ZERO
	draw_circle(center, _RADIUS + 6.0, Color(0.1, 0.1, 0.12, 0.85))
	draw_arc(
		center, _RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true
	)
	# The target band.
	draw_arc(
		center,
		_RADIUS,
		_speed_to_angle(G.settings.phillips_speed_min_rad_per_sec),
		_speed_to_angle(G.settings.phillips_speed_max_rad_per_sec),
		24,
		Color(0.4, 1.0, 0.45),
		7.0,
		true,
	)
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


func _speed_to_angle(speed_rad_per_sec: float) -> float:
	var share := clampf(
		speed_rad_per_sec
		/ maxf(G.settings.phillips_gauge_max_rad_per_sec, 0.01),
		0.0,
		1.0,
	)
	return deg_to_rad(_START_DEG + _SWEEP_DEG * share)
