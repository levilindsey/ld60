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
## The sign lettering, rendered to a texture (a SubViewport, the
## way the manual renders its pages), and where its plate sits
## in door space. Drawn slice by slice with the face, so the
## words skew the way the sign does.
var sign_texture: Texture2D
var sign_rect := Rect2()

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
	var brightness := 1.0 - _MAX_SHADE * sin(angle)
	var face_color := Color(brightness, brightness, brightness)

	# Slice the face from the hinge (the door's right edge in the
	# image) to the free (knob) edge on the left.
	var texture_size := texture.get_size()
	var u_hinge := (
		(source_rect.position.x + source_rect.size.x) / texture_size.x
	)
	var u_span := source_rect.size.x / texture_size.x
	var v_top := source_rect.position.y / texture_size.y
	var v_bottom := (
		(source_rect.position.y + source_rect.size.y) / texture_size.y
	)
	for i in _SLICE_COUNT:
		var local_left := door_size.x * (1.0 - float(i + 1) / _SLICE_COUNT)
		var local_right := door_size.x * (1.0 - float(i) / _SLICE_COUNT)
		var points := PackedVector2Array([
			_face_point(local_right, 0.0, angle),
			_face_point(local_left, 0.0, angle),
			_face_point(local_left, door_size.y, angle),
			_face_point(local_right, door_size.y, angle),
		])
		var u_start := u_hinge - u_span * float(i) / _SLICE_COUNT
		var u_end := u_hinge - u_span * float(i + 1) / _SLICE_COUNT
		var uvs := PackedVector2Array([
			Vector2(u_start, v_top),
			Vector2(u_end, v_top),
			Vector2(u_end, v_bottom),
			Vector2(u_start, v_bottom),
		])
		draw_polygon(points, PackedColorArray([face_color]), uvs, texture)

	_draw_sign(angle, face_color)

	# The slab side at the free edge: a dark strip that widens as
	# the door turns, so the slab reads as thick, not paper.
	if angle > 0.02:
		var free_top := _face_point(0.0, 0.0, angle)
		var free_bottom := _face_point(0.0, door_size.y, angle)
		var edge := Vector2(_EDGE_PX * sin(angle), 0.0)
		var center_y := door_size.y * 0.5
		var slab := PackedVector2Array([
			free_top,
			free_bottom,
			free_bottom + edge + Vector2(0.0, -0.02 * center_y),
			free_top + edge + Vector2(0.0, 0.02 * center_y),
		])
		draw_polygon(
			slab,
			PackedColorArray([_SLAB_COLOR * brightness]),
		)


## Where a point of the shut door (in door space) lands with the
## door swung by `angle`: compressed toward the hinge, and
## shrunk a little toward the middle as it recedes.
func _face_point(local_x: float, local_y: float, angle: float) -> Vector2:
	var depth := door_size.x - local_x
	var center_y := door_size.y * 0.5
	var recede := (
		1.0 - _RECESS_SHRINK * sin(angle) * depth / door_size.x
	)
	return Vector2(
		door_size.x - depth * cos(angle),
		center_y + (local_y - center_y) * recede,
	)


## The sign lettering, in the same slices as the face, clipped
## to the plate. The words skew exactly the way the sign does.
func _draw_sign(angle: float, face_color: Color) -> void:
	if not is_instance_valid(sign_texture) or sign_rect.size.x <= 0.0:
		return
	for i in _SLICE_COUNT:
		var local_left := door_size.x * (1.0 - float(i + 1) / _SLICE_COUNT)
		var local_right := door_size.x * (1.0 - float(i) / _SLICE_COUNT)
		var sign_left := maxf(local_left, sign_rect.position.x)
		var sign_right := minf(local_right, sign_rect.end.x)
		if sign_right - sign_left < 0.5:
			continue
		var points := PackedVector2Array([
			_face_point(sign_right, sign_rect.position.y, angle),
			_face_point(sign_left, sign_rect.position.y, angle),
			_face_point(sign_left, sign_rect.end.y, angle),
			_face_point(sign_right, sign_rect.end.y, angle),
		])
		var u_start := (
			(sign_left - sign_rect.position.x) / sign_rect.size.x
		)
		var u_end := (
			(sign_right - sign_rect.position.x) / sign_rect.size.x
		)
		var uvs := PackedVector2Array([
			Vector2(u_end, 0.0),
			Vector2(u_start, 0.0),
			Vector2(u_start, 1.0),
			Vector2(u_end, 1.0),
		])
		draw_polygon(points, PackedColorArray([face_color]), uvs, sign_texture)
