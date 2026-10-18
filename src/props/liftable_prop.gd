class_name LiftableProp
extends Node2D
## A prop that rests flat on the desk and lifts into view to be read.
##
## At rest it sits at `desk_spot`, with `warped_sprite` drawn onto
## `desk_corners` so it looks like it's lying flat in perspective. Lifting
## eases it to its open pose, which is wherever the level placed it, while
## the corners ease back to the flat sprite.
##
## Presses are routed through `_handle_press()` from `_unhandled_input`
## rather than through Area2D picking. A prop placed after the level's Hand
## sees presses first, and keeps presses that land on it from reaching
## items behind it.


## Duration of the move between the desk and the open pose.
const _LIFT_DURATION_SEC := 0.3


## Where the prop rests. Its position, rotation, scale and skew place the
## resting prop on the desk. Without one, the prop stays put.
@export var desk_spot: Node2D
## The warped sprite's corners while resting on the desk: top left, top
## right, bottom right, bottom left, in the sprite's local space. They ease
## back to the flat sprite as the prop lifts.
@export var desk_corners := PackedVector2Array()
## The sprite drawn in perspective while resting. It needs the
## perspective_quad shader as its material.
@export var warped_sprite: Sprite2D
@export var close_button: PropCloseButton
## Optional. While resting, the prop moves to just before this sibling and
## drops to z_index 0, so this sibling and everything after it draw over
## the prop and see presses first. Lifting moves it back to its own place
## and z_index.
@export var resting_draw_before: Node


var _open_position := Vector2.ZERO
var _open_rotation := 0.0
var _open_scale := Vector2.ONE
var _open_skew := 0.0
var _warped_corners := PackedVector2Array()
var _lift_tween_id := -1
var _lifted_z_index := 0
## The sibling the prop follows while lifted.
var _lifted_after: Node


func _ready() -> void:
	_open_position = global_position
	_open_rotation = global_rotation
	_open_scale = global_scale
	_open_skew = global_skew
	_set_warped_corners(_get_flat_corners())
	_lifted_z_index = z_index
	var index := get_index()
	if index > 0:
		_lifted_after = get_parent().get_child(index - 1)
	if is_instance_valid(desk_spot):
		_set_lift(0.0)
		reset_physics_interpolation()
	# Deferred: the parent is still setting up its children.
	_set_resting_order.call_deferred(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_left_mouse_event(event, true):
		return
	if _handle_press(event as InputEventMouseButton):
		get_viewport().set_input_as_handled()


## Handles a left press. Returns whether it landed on the prop, which keeps
## it from reaching anything behind.
func _handle_press(_event: InputEventMouseButton) -> bool:
	return false


func _tween_lift(
	from_lift: float,
	to_lift: float,
	on_completed: Callable,
) -> void:
	_stop_lift()
	if not is_instance_valid(desk_spot):
		on_completed.call()
		return
	_lift_tween_id = G.time.tween_method(
		self,
		"_set_lift",
		from_lift,
		to_lift,
		_LIFT_DURATION_SEC,
		"ease_in_out",
		0.0,
		TimeType.APP_PHYSICS,
		on_completed,
	)


func _stop_lift() -> void:
	G.time.clear_tween(_lift_tween_id)
	_lift_tween_id = -1


## Switches between the resting place in the tree (see
## `resting_draw_before`) and the prop's own lifted place.
func _set_resting_order(is_resting: bool) -> void:
	if not is_instance_valid(resting_draw_before):
		return
	var parent := get_parent()
	var target_index: int
	if is_resting:
		z_index = 0
		target_index = resting_draw_before.get_index()
		if get_index() < target_index:
			target_index -= 1
	else:
		z_index = _lifted_z_index
		target_index = 0
		if is_instance_valid(_lifted_after):
			target_index = _lifted_after.get_index()
			if get_index() > target_index:
				target_index += 1
	parent.move_child(self, target_index)


## 0 rests at `desk_spot`; 1 is the open pose.
func _set_lift(lift: float) -> void:
	global_position = desk_spot.global_position.lerp(_open_position, lift)
	global_rotation = lerp_angle(
		desk_spot.global_rotation,
		_open_rotation,
		lift,
	)
	global_scale = desk_spot.global_scale.lerp(_open_scale, lift)
	global_skew = lerpf(desk_spot.global_skew, _open_skew, lift)

	var flat_corners := _get_flat_corners()
	if desk_corners.size() != flat_corners.size():
		_set_warped_corners(flat_corners)
		return
	var corners := PackedVector2Array()
	for i in flat_corners.size():
		corners.append(desk_corners[i].lerp(flat_corners[i], lift))
	_set_warped_corners(corners)


## Whether a press lands on the warped sprite as it's currently drawn.
func _is_on_warped_sprite(event: InputEventMouse) -> bool:
	var point := (
		(warped_sprite.make_input_local(event) as InputEventMouse).position
	)
	return Geometry2D.is_point_in_polygon(point, _warped_corners)


## The warped sprite's corners when it isn't warped: top left, top right,
## bottom right, bottom left, in the sprite's local space.
func _get_flat_corners() -> PackedVector2Array:
	var half_size := warped_sprite.texture.get_size() / 2.0
	return PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	])


func _set_warped_corners(corners: PackedVector2Array) -> void:
	_warped_corners = corners
	var material := warped_sprite.material as ShaderMaterial
	material.set_shader_parameter("top_left", corners[0])
	material.set_shader_parameter("top_right", corners[1])
	material.set_shader_parameter("bottom_right", corners[2])
	material.set_shader_parameter("bottom_left", corners[3])


func _play_sound(sound_name: StringName, force_restart := false) -> void:
	# A prop can be run on its own, before AudioMain exists.
	if is_instance_valid(G.audio):
		G.audio.play_sound(sound_name, force_restart)


func _is_on_shape(
	shape_node: CollisionShape2D,
	event: InputEventMouse,
) -> bool:
	var point := (shape_node.make_input_local(event) as InputEventMouse).position
	var size := (shape_node.shape as RectangleShape2D).size
	return Rect2(-size / 2.0, size).has_point(point)


func _is_left_mouse_event(event: InputEvent, is_pressed: bool) -> bool:
	# Touch input arrives as emulated mouse events.
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed == is_pressed
	)
