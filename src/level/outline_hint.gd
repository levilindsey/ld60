class_name OutlineHint
extends Node2D
## Draws a gradient rim around `polygon`, in this node's local points.
##
## This is the half of the outline hint that the sprite shader in
## `assets/shaders/sprite_outline_gradient.gdshader` cannot do. The
## shader reads the texture's alpha, so it only works on a `Sprite2D`.
## Placeholder art has no texture to read: a `ColorRect` or a
## `Polygon2D`. This node draws the same rim instead, as concentric
## outlines that fade from the shape's edge outwards, pulsing at the
## shader's rhythm. Colors and width come from the shared material in
## `Settings.outline_hint_material`, so both halves match.


const _RING_COUNT := 6
const _DEFAULT_COLOR_INNER := Color(1.0, 0.92, 0.4, 1.0)
const _DEFAULT_COLOR_OUTER := Color(1.0, 0.92, 0.4, 0.0)
const _DEFAULT_WIDTH := 8.0
const _DEFAULT_GRADIENT_POWER := 1.0
const _DEFAULT_PULSE_SPEED := 0.9

## The closed shape to outline, in this node's local points.
var polygon := PackedVector2Array():
	set(value):
		polygon = value
		queue_redraw()

var _is_active := false


## Applies the shared outline material to a sprite. Returns the
## material the sprite had, so `remove_from_sprite()` can restore it.
static func apply_to_sprite(art: Sprite2D) -> Material:
	var previous := art.material
	if is_instance_valid(G.settings.outline_hint_material):
		art.material = G.settings.outline_hint_material
	return previous


## Restores a sprite's material after `apply_to_sprite()`.
static func remove_from_sprite(art: Sprite2D, previous: Material) -> void:
	if is_instance_valid(art):
		art.material = previous


## The outline shape of art that the shader cannot reach, in the
## art's local points. Empty when the art has no shape to outline.
static func get_art_polygon(art: CanvasItem) -> PackedVector2Array:
	if art is Polygon2D:
		var polygon_art := art as Polygon2D
		var points := PackedVector2Array()
		for point in polygon_art.polygon:
			points.append(point + polygon_art.offset)
		return points
	if art is Control:
		var size := (art as Control).size
		return PackedVector2Array([
			Vector2.ZERO,
			Vector2(size.x, 0.0),
			size,
			Vector2(0.0, size.y),
		])
	return PackedVector2Array()


func _ready() -> void:
	z_index = 10
	visible = false
	set_process(false)


func _process(_delta: float) -> void:
	queue_redraw()


## Shows or hides the rim. While shown it pulses like the shader.
func set_active(is_active: bool) -> void:
	_is_active = is_active
	visible = is_active
	set_process(is_active)
	queue_redraw()


func is_active() -> bool:
	return _is_active


func _draw() -> void:
	if not _is_active or polygon.size() < 3:
		return
	var material := G.settings.outline_hint_material
	var color_inner := _get_color_parameter(
		material,
		&"outline_color_inner",
		_DEFAULT_COLOR_INNER,
	)
	var color_outer := _get_color_parameter(
		material,
		&"outline_color_outer",
		_DEFAULT_COLOR_OUTER,
	)
	var width := _get_float_parameter(
		material,
		&"outline_width",
		_DEFAULT_WIDTH,
	)
	var gradient_power := _get_float_parameter(
		material,
		&"gradient_power",
		_DEFAULT_GRADIENT_POWER,
	)
	var pulse_speed := _get_float_parameter(
		material,
		&"pulse_speed",
		_DEFAULT_PULSE_SPEED,
	)
	var strength := 1.0
	if pulse_speed > 0.0:
		var wave := (
			0.5
			+ 0.5
			* sin(
				Time.get_ticks_msec() / 1000.0 * TAU * pulse_speed,
			)
		)
		strength = lerpf(0.65, 1.0, wave)
	var line_width := maxf(width / _RING_COUNT + 1.0, 1.5)
	for ring in range(_RING_COUNT, 0, -1):
		var depth := float(ring) / _RING_COUNT
		var color := color_inner.lerp(
			color_outer,
			pow(depth, gradient_power),
		)
		color.a *= strength
		if color.a <= 0.001:
			continue
		var points := _expanded_polygon(depth * width)
		points.append(points[0])
		draw_polyline(points, color, line_width, true)


## `polygon` pushed outwards by `distance`, for convex shapes. Each
## vertex moves along the average of its two edge normals.
func _expanded_polygon(distance: float) -> PackedVector2Array:
	var expanded := PackedVector2Array()
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= polygon.size()
	for index in polygon.size():
		var count := polygon.size()
		var previous := polygon[(index - 1 + count) % count]
		var current := polygon[index]
		var next := polygon[(index + 1) % count]
		var normal_previous := _get_outward_normal(
			previous,
			current,
			centroid,
		)
		var normal_next := _get_outward_normal(current, next, centroid)
		var direction := normal_previous + normal_next
		if direction.length_squared() < 0.0001:
			direction = normal_next
		direction = direction.normalized()
		var alignment := maxf(direction.dot(normal_next), 0.25)
		expanded.append(current + direction * (distance / alignment))
	return expanded


func _get_outward_normal(
	from_point: Vector2,
	to_point: Vector2,
	centroid: Vector2,
) -> Vector2:
	var edge := to_point - from_point
	if edge.length_squared() < 0.0001:
		return Vector2.ZERO
	var normal := Vector2(edge.y, -edge.x).normalized()
	var midpoint := (from_point + to_point) * 0.5
	if normal.dot(midpoint - centroid) < 0.0:
		normal = -normal
	return normal


func _get_color_parameter(
	material: ShaderMaterial,
	parameter: StringName,
	fallback: Color,
) -> Color:
	if not is_instance_valid(material):
		return fallback
	var value: Variant = material.get_shader_parameter(parameter)
	return value if value is Color else fallback


func _get_float_parameter(
	material: ShaderMaterial,
	parameter: StringName,
	fallback: float,
) -> float:
	if not is_instance_valid(material):
		return fallback
	var value: Variant = material.get_shader_parameter(parameter)
	if value is float:
		return value
	if value is int:
		return float(value)
	return fallback
