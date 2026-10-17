class_name StarIcon
extends Control
## A star drawn with polygons. A lit star is filled, and an unlit one is only
## a faint outline.
##
## It is drawn instead of using a texture because the star art isn't made yet
## (LX24). With four points and a small inner ratio, it doubles as a sparkle.


@export var is_lit := false:
	set(value):
		is_lit = value
		queue_redraw()
@export var point_count := 5:
	set(value):
		point_count = value
		queue_redraw()
## The depth of the notches between the points, as a fraction of the radius
## of the points.
@export_range(0.1, 0.9) var inner_ratio := 0.5:
	set(value):
		inner_ratio = value
		queue_redraw()
@export var lit_color := Color(1.0, 0.8, 0.2)
@export var unlit_color := Color(0.25, 0.18, 0.12, 0.18)
@export var outline_color := Color(0.3, 0.18, 0.05)
@export var unlit_outline_color := Color(0.25, 0.18, 0.12, 0.4)
## Zero draws no outline.
@export var outline_width := 3.0


func _init() -> void:
	# A star is only for looking at, so it never takes clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()


func _draw() -> void:
	var center := size / 2.0
	var outer_radius := minf(size.x, size.y) / 2.0 - outline_width
	var points := PackedVector2Array()
	for index in point_count * 2:
		var angle := -PI / 2.0 + index * PI / point_count
		var radius := outer_radius
		if index % 2 == 1:
			radius *= inner_ratio
		points.append(center + Vector2.from_angle(angle) * radius)

	if is_lit:
		draw_colored_polygon(points, lit_color)
	else:
		draw_colored_polygon(points, unlit_color)

	if outline_width > 0.0:
		var outline := points.duplicate()
		outline.append(points[0])
		var color := outline_color if is_lit else unlit_outline_color
		draw_polyline(outline, color, outline_width, true)


func _on_resized() -> void:
	# Scale and rotate around the middle.
	pivot_offset = size / 2.0
	queue_redraw()
