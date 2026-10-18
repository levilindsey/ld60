class_name ManualLeaf
extends Node2D
## The page being turned, hinged at the spine (this node's origin). Drawn as
## a strip of vertical slices that bend as the page turns, so it looks like
## it flops over.
##
## Progress 0 lies flat over the right page; 1 lies flat over the left page.
## Each slice faces up or down depending on its angle, and shows the front or
## back face accordingly. Lifted parts draw slightly taller, and slices darken
## as they tilt edge-on.
##
## Each face's ManualPage renders into its own SubViewport, so the whole page
## (outline and content) can be drawn as one bent texture.
# TODO: Remove the SubViewports once the page outline is a sprite. Draw the
# outline texture and the content texture directly onto the bent strip.


const _PAGE_SIZE := Vector2(240.0, 320.0)
const _SLICE_COUNT := 16
## How far the free edge trails the spine mid-turn, in radians.
const _MAX_BEND_RADIANS := 0.9
## Extra height of a point lifted one page width, as a fraction of height.
const _LIFT_FLARE := 0.15
## Darkening of a slice seen fully edge-on.
const _MAX_SHADE := 0.45


## How far each resting page is shifted toward the spine.
var spine_overlap := 0.0


var _progress := 0.0
var _bend_direction := 1.0


func _draw() -> void:
	var slice_width := _PAGE_SIZE.x / _SLICE_COUNT
	var base_angle := _progress * PI
	var bend := (
		_MAX_BEND_RADIANS * sin(_progress * PI) * _bend_direction
	)

	# Accumulate the bent strip's edge positions. x runs along the table
	# (positive is right of the spine) and z is height above it. The hinge
	# slides across the spine so each face lines up with its resting page.
	var hinge_x := lerpf(-spine_overlap, spine_overlap, _progress)
	var xs := PackedFloat32Array([hinge_x])
	var zs := PackedFloat32Array([0.0])
	for i in _SLICE_COUNT:
		var u := (i + 0.5) / _SLICE_COUNT
		var angle := clampf(base_angle + bend * u, 0.0, PI)
		xs.append(xs[i] + slice_width * cos(angle))
		zs.append(zs[i] + slice_width * sin(angle))

	# Draw lower slices first so curled-over parts layer correctly.
	var slice_order := range(_SLICE_COUNT)
	slice_order.sort_custom(
		func(a: int, b: int) -> bool:
			return zs[a] + zs[a + 1] < zs[b] + zs[b + 1]
	)
	for i: int in slice_order:
		_draw_slice(i, xs, zs, slice_width)


func set_contents(front: Texture2D, back: Texture2D) -> void:
	%LeafFrontPage.set_content(front)
	%LeafBackPage.set_content(back)


## `bend_direction` is +1 to bend the free edge toward the left page, or -1
## to bend it toward the right page.
func set_progress(progress: float, bend_direction: float) -> void:
	_progress = progress
	_bend_direction = bend_direction
	queue_redraw()


func _draw_slice(
	i: int,
	xs: PackedFloat32Array,
	zs: PackedFloat32Array,
	slice_width: float,
) -> void:
	var dx := xs[i + 1] - xs[i]
	var is_front := dx >= 0.0
	var start_half_height := _get_half_height(zs[i])
	var end_half_height := _get_half_height(zs[i + 1])
	var points := PackedVector2Array([
		Vector2(xs[i], -start_half_height),
		Vector2(xs[i + 1], -end_half_height),
		Vector2(xs[i + 1], end_half_height),
		Vector2(xs[i], start_half_height),
	])

	# The front's spine is its left edge; the back's spine is its right edge.
	var u_start := float(i) / _SLICE_COUNT
	var u_end := float(i + 1) / _SLICE_COUNT
	if not is_front:
		u_start = 1.0 - u_start
		u_end = 1.0 - u_end
	var uvs := PackedVector2Array([
		Vector2(u_start, 0.0),
		Vector2(u_end, 0.0),
		Vector2(u_end, 1.0),
		Vector2(u_start, 1.0),
	])

	var flatness := absf(dx) / slice_width
	var brightness := 1.0 - _MAX_SHADE * (1.0 - flatness)
	var viewport: SubViewport = %FrontViewport if is_front else %BackViewport
	draw_polygon(
		points,
		PackedColorArray([Color(brightness, brightness, brightness)]),
		uvs,
		viewport.get_texture(),
	)


func _get_half_height(z: float) -> float:
	return _PAGE_SIZE.y * 0.5 * (1.0 + _LIFT_FLARE * z / _PAGE_SIZE.x)
