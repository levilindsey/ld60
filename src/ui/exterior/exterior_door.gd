class_name ExteriorDoor
extends Node2D
## The shop door on the title screen (docs/design in hud.md flow).
## Drawn like the manual's leaf: a strip of vertical slices hinged
## at the right edge, each rotated in fake 3D as the door opens
## inward, so a flat sprite swings without new art. The free edge
## grows a slab side as it turns, so the door has thickness.
##
## `open_amount` 0 is shut; 1 is fully open.


const _SLICE_COUNT := 14
## How far the door swings, in radians. Short of a quarter turn,
## so the front face always shows.
const _MAX_OPEN_RAD := 1.35
## Slab thickness at the free edge when fully open, in pixels.
const _EDGE_PX := 14.0
## How much the receding free edge shrinks vertically.
const _RECESS_SHRINK := 0.16
## How much the face darkens as it turns away.
const _MAX_SHADE := 0.35
const _SLAB_COLOR := Color(0.32, 0.21, 0.12)
const _DOORWAY_COLOR := Color(0.04, 0.03, 0.02)

## The door texture and the region of it the door fills (the
## texture is a full-canvas overlay; only part of it is door).
var texture: Texture2D
var source_rect := Rect2()
## The door's size on screen, in pixels.
var door_size := Vector2.ZERO

var _open_amount := 0.0


## 0 is shut, 1 is fully open.
func set_open_amount(amount: float) -> void:
	_open_amount = clampf(amount, 0.0, 1.0)
	queue_redraw()


func get_open_amount() -> float:
	return _open_amount


## The swing angle the current amount draws at, in radians.
func get_open_angle_rad() -> float:
	return _MAX_OPEN_RAD * _open_amount


func _draw() -> void:
	if not is_instance_valid(texture) or door_size.x <= 0.0:
		return
	# The dark inside, behind wherever the door has swung away.
	draw_rect(Rect2(Vector2.ZERO, door_size), _DOORWAY_COLOR)

	var angle := _MAX_OPEN_RAD * _open_amount
	var hinge_x := door_size.x
	var center_y := door_size.y * 0.5
	var brightness := 1.0 - _MAX_SHADE * sin(angle)

	# Slice edge positions, from the hinge to the free edge. x is
	# compressed by the swing; the receding edge also shrinks a
	# little, which sells the depth.
	var xs := PackedFloat32Array()
	var half_heights := PackedFloat32Array()
	for i in _SLICE_COUNT + 1:
		var share := float(i) / _SLICE_COUNT
		var depth := door_size.x * share
		xs.append(hinge_x - depth * cos(angle))
		var recede := 1.0 - _RECESS_SHRINK * sin(angle) * share
		half_heights.append(center_y * recede)

	var texture_size := texture.get_size()
	for i in _SLICE_COUNT:
		var points := PackedVector2Array([
			Vector2(xs[i], center_y - half_heights[i]),
			Vector2(xs[i + 1], center_y - half_heights[i + 1]),
			Vector2(xs[i + 1], center_y + half_heights[i + 1]),
			Vector2(xs[i], center_y + half_heights[i]),
		])
		# The hinge is the door's right edge in the image; slices
		# run from there to the free (knob) edge on the left.
		var u_hinge := (
			(source_rect.position.x + source_rect.size.x)
			/ texture_size.x
		)
		var u_span := source_rect.size.x / texture_size.x
		var u_start := u_hinge - u_span * float(i) / _SLICE_COUNT
		var u_end := u_hinge - u_span * float(i + 1) / _SLICE_COUNT
		var v_top := source_rect.position.y / texture_size.y
		var v_bottom := (
			(source_rect.position.y + source_rect.size.y)
			/ texture_size.y
		)
		var uvs := PackedVector2Array([
			Vector2(u_start, v_top),
			Vector2(u_end, v_top),
			Vector2(u_end, v_bottom),
			Vector2(u_start, v_bottom),
		])
		draw_polygon(
			points,
			PackedColorArray([
				Color(brightness, brightness, brightness)
			]),
			uvs,
			texture,
		)

	# The slab side at the free edge: a dark strip that widens as
	# the door turns, so the slab reads as thick, not paper.
	if angle > 0.02:
		var free_x := xs[_SLICE_COUNT]
		var free_half := half_heights[_SLICE_COUNT]
		var edge := _EDGE_PX * sin(angle)
		var slab := PackedVector2Array([
			Vector2(free_x, center_y - free_half),
			Vector2(free_x, center_y + free_half),
			Vector2(free_x + edge, center_y + free_half * 0.98),
			Vector2(free_x + edge, center_y - free_half * 0.98),
		])
		draw_polygon(
			slab,
			PackedColorArray([_SLAB_COLOR * brightness]),
		)
