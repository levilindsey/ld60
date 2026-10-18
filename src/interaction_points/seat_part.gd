class_name SeatPart
extends StrikablePoint
## A half out part the hammer seats (docs/design/hammer.md).
## Each working hit pushes it halfway home. A hit that is too
## hard seats it at once and cracks the board.


## The art that slides home.
@export var art: Node2D
## How far out the part starts, in pixels.
@export var seat_distance_px := 24.0
## Working hits that seat the part.
@export var hits_to_seat := 2
## The way out of the slot. The part starts this way from home.
@export var seat_axis := Vector2(0.0, -1.0)

## How far home the part is, from 0 to 1.
var seat_progress := 0.0

var _home_position := Vector2.ZERO


func _ready() -> void:
	super._ready()
	type = Type.SEAT_PART
	role = Role.REPAIR
	G.check(is_instance_valid(art))
	_home_position = art.position
	_apply_progress()


func apply_hit(_strength: float, is_over: bool) -> void:
	if is_over:
		seat_progress = 1.0
	else:
		seat_progress = minf(
			seat_progress + 1.0 / maxf(float(hits_to_seat), 1.0), 1.0
		)
	_apply_progress()
	if seat_progress >= 1.0:
		finish()


## A hard seating cracks the board instead of denting the part.
func get_over_defect(_is_far: bool) -> RepairQuality.Defect:
	return RepairQuality.Defect.CRACK


func _apply_progress() -> void:
	if is_instance_valid(art):
		art.position = (
			_home_position
			+ seat_axis * seat_distance_px * (1.0 - seat_progress)
		)
