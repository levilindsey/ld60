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
## `Settings.outline_hint_material`, so both halves match. The width
## is in world pixels: the rim compensates for this node's global
## scale, so it is the same size whatever scale the art sits at.


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

## Scales the shared colors' alpha. Below 1 draws a fainter rim than
## the usual hint (the tool holders use this).
var alpha_scale := 1.0:
	set(value):
		alpha_scale = value
		queue_redraw()

## Scales the shared band width. Above 1 draws a bolder rim
## than the usual hint (the finished item uses this).
var width_scale := 1.0:
	set(value):
		width_scale = value
		queue_redraw()

var _is_active := false


## Applies the outline material to a sprite (the shared one,
## unless another is given). Returns the material the sprite
## had, so `remove_from_sprite()` can restore it.
static func apply_to_sprite(
	art: Sprite2D, material: Material = null
) -> Material:
	var previous := art.material
	var chosen := material
	if not is_instance_valid(chosen):
		chosen = G.settings.outline_hint_material
	if is_instance_valid(chosen):
		art.material = chosen
	return previous


## The shared outline's band width in world pixels.
static func get_shared_width() -> float:
	var material := G.settings.outline_hint_material
	if not is_instance_valid(material):
		return _DEFAULT_WIDTH
	var value: Variant = material.get_shader_parameter(
		&"outline_width_px"
	)
	if value is float:
		return value
	if value is int:
		return float(value)
	return _DEFAULT_WIDTH


## A world polygon in an art node's local points, for drawing
## a rim on the art with an `OutlineHint` child.
static func world_polygon_to_local(
	art: CanvasItem, world_points: PackedVector2Array
) -> PackedVector2Array:
	var inverse := art.get_global_transform().affine_inverse()
	var local_points := PackedVector2Array()
	for point in world_points:
		local_points.append(inverse * point)
	return local_points


## Restores a sprite's material after `apply_to_sprite()`.
static func remove_from_sprite(art: Sprite2D, previous: Material) -> void:
	if is_instance_valid(art):
		art.material = previous


## How wide a rim the outline shader can actually paint on
## this sprite, in world pixels: the shader only draws inside
## the texture, so the transparent margin around the used art
## caps it. Audit (Oct 2026): most layer art fits the full
## width, but the piano Keys texture touches its top and
## bottom edges (no rim there at all), the piano Bottom fits
## ~6 px and the shrink ray SwitchBody ~6 px.
static func get_sprite_rim_world(art: Sprite2D) -> float:
	if not is_instance_valid(art) or not art.texture:
		return 0.0
	var used := DecalSpawner.get_visible_rect(art.texture)
	var tex_size := Vector2(art.texture.get_size())
	var scale := art.get_global_transform().get_scale()
	var margin := Vector2(
		minf(used.position.x, tex_size.x - used.end.x)
		* absf(scale.x),
		minf(used.position.y, tex_size.y - used.end.y)
		* absf(scale.y),
	)
	return minf(margin.x, margin.y)


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


## The outline shape of a collision shape, in the shape node's
## local points. Circles become a twenty sided polygon, rectangles
## their corners and capsules their bounding box. Empty when the
## shape has no flat outline.
static func get_shape_polygon(
	shape_node: CollisionShape2D,
) -> PackedVector2Array:
	if not is_instance_valid(shape_node):
		return PackedVector2Array()
	if not is_instance_valid(shape_node.shape):
		return PackedVector2Array()
	var center := shape_node.position
	if shape_node.shape is CircleShape2D:
		var radius := (shape_node.shape as CircleShape2D).radius
		var points := PackedVector2Array()
		for index in 20:
			var angle := TAU * float(index) / 20.0
			points.append(center + Vector2.from_angle(angle) * radius)
		return points
	if shape_node.shape is RectangleShape2D:
		var half := (shape_node.shape as RectangleShape2D).size * 0.5
		return PackedVector2Array([
			center + Vector2(-half.x, -half.y),
			center + Vector2(half.x, -half.y),
			center + half,
			center + Vector2(-half.x, half.y),
		])
	if shape_node.shape is CapsuleShape2D:
		var capsule := shape_node.shape as CapsuleShape2D
		var half := Vector2(
			capsule.radius,
			capsule.height * 0.5,
		)
		return PackedVector2Array([
			center + Vector2(-half.x, -half.y),
			center + Vector2(half.x, -half.y),
			center + half,
			center + Vector2(-half.x, half.y),
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
		&"outline_width_px",
		_DEFAULT_WIDTH,
	) * width_scale
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
		strength = lerpf(0.75, 1.0, wave)
	# Expand in pre-rotation world units (the shape scaled by this
	# node's global scale), then convert back, so `width` is world
	# pixels at any scale.
	var world_scale := _get_world_scale()
	var average_scale := maxf(
		(world_scale.x + world_scale.y) * 0.5,
		0.0001,
	)
	var line_width := (
		maxf(width / _RING_COUNT + 1.0, 1.5) / average_scale
	)
	var scaled_polygon := PackedVector2Array()
	for point in polygon:
		scaled_polygon.append(point * world_scale)
	for ring in range(_RING_COUNT, 0, -1):
		var depth := float(ring) / _RING_COUNT
		var color := color_inner.lerp(
			color_outer,
			pow(depth, gradient_power),
		)
		color.a *= strength * alpha_scale
		if color.a <= 0.001:
			continue
		var scaled_points := _expanded_polygon(
			scaled_polygon,
			depth * width,
		)
		var points := PackedVector2Array()
		for point in scaled_points:
			points.append(point / world_scale)
		points.append(points[0])
		draw_polyline(points, color, line_width, true)


## World pixels per local unit on each axis, from the global scale.
## Rotation does not change these lengths.
func _get_world_scale() -> Vector2:
	var basis := get_global_transform()
	return Vector2(
		maxf(basis.basis_xform(Vector2(1.0, 0.0)).length(), 0.0001),
		maxf(basis.basis_xform(Vector2(0.0, 1.0)).length(), 0.0001),
	)


## `points` pushed outwards by `distance`, for convex shapes. Each
## vertex moves along the average of its two edge normals.
func _expanded_polygon(
	points: PackedVector2Array,
	distance: float,
) -> PackedVector2Array:
	var expanded := PackedVector2Array()
	var centroid := Vector2.ZERO
	for point in points:
		centroid += point
	centroid /= points.size()
	for index in points.size():
		var count := points.size()
		var previous := points[(index - 1 + count) % count]
		var current := points[index]
		var next := points[(index + 1) % count]
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
