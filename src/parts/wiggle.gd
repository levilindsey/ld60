class_name Wiggle
extends RefCounted
## Counts side-to-side swings of a drag, and how far the dragged
## thing should rock. Shared by the parts bin and the pliers
## (docs/design/parts_bin.md "Getting the old part out: wiggle").


## A swing counts when the drag reverses after moving at least this
## far, in screen pixels.
const _MIN_TRAVEL_PX := 12.0
## Dragging further than this from the press point, in screen pixels,
## yanks the part out at once.
const _YANK_DISTANCE_PX := 60.0
## The rock at a full drag, in radians: about 10 degrees.
const _MAX_ROCK_RAD := 0.174533

## Swings counted since `reset()`.
var swings := 0
## The angle the dragged thing should sit at now.
var rock_angle_rad := 0.0
## True once a drag went past the yank distance.
var is_yanked := false

var _swings_needed := 4
var _start_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _direction := 0.0
var _travelled_px := 0.0


## Starts a fresh wiggle at a press. `swings_needed` of these pop the
## part out.
func reset(press_position: Vector2, swings_needed: int) -> void:
	swings = 0
	rock_angle_rad = 0.0
	is_yanked = false
	_swings_needed = swings_needed
	_start_position = press_position
	_last_position = press_position
	_direction = 0.0
	_travelled_px = 0.0


## Feeds one pointer position. True when the last swing pops out.
func feed(pointer_position: Vector2) -> bool:
	var delta_x := pointer_position.x - _last_position.x
	_last_position = pointer_position
	rock_angle_rad = (
		clampf(
			(pointer_position.x - _start_position.x) / _YANK_DISTANCE_PX,
			-1.0,
			1.0,
		)
		* _MAX_ROCK_RAD
	)
	if pointer_position.distance_to(_start_position) > _YANK_DISTANCE_PX:
		is_yanked = true
		return true
	if delta_x == 0.0:
		return false
	var direction := signf(delta_x)
	if _direction == 0.0:
		_direction = direction
	elif direction != _direction:
		if _travelled_px >= _MIN_TRAVEL_PX:
			swings += 1
			if swings >= _swings_needed:
				return true
		_direction = direction
		_travelled_px = 0.0
	_travelled_px += absf(delta_x)
	return false
