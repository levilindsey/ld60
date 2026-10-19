class_name BentPart
extends StrikablePoint
## A bent part the hammer knocks back into line (docs/design/
## hammer.md). Each working hit removes a share of the error. A
## hit that is too hard flips the error to the other side.


## The art that sits bent. It turns straight as hits land.
@export var art: Node2D
## Optional straight art swapped in when the part is fixed,
## for a piece whose straight shape is its own sprite (the
## TV antenna). Hidden until the part finishes.
@export var straight_art: Node2D
## How far the part starts bent, in degrees.
@export var error_deg := 18.0
## Working hits that straighten the part.
@export var hits_to_straighten := 3
## At this error or less, the part counts as straight.
@export var done_threshold_deg := 2.0

## The bend left, in degrees. It can go negative on a flip.
var current_error_deg := 0.0

var _home_rotation := 0.0


func _ready() -> void:
	super._ready()
	type = Type.BENT_PART
	role = Role.REPAIR
	G.check(is_instance_valid(art))
	_home_rotation = art.rotation
	current_error_deg = error_deg
	if is_instance_valid(straight_art):
		straight_art.hide()
	_set_art_pivot_to_bottom_right()
	_apply_error()


## Turns the art around its bottom right corner instead of
## its centre: the bend swings from where the part meets
## what it sticks out of (the TV antenna's base), not from
## the middle of the sprite. The corner becomes the art's
## origin; the drawing itself does not move.
func _set_art_pivot_to_bottom_right() -> void:
	if not (art is Sprite2D):
		return
	var sprite := art as Sprite2D
	if not is_instance_valid(sprite.texture):
		return
	var size := Vector2(sprite.texture.get_size())
	if sprite.region_enabled:
		size = sprite.region_rect.size
	var corner := size if not sprite.centered else size * 0.5
	var corner_world := sprite.to_global(corner)
	sprite.offset -= corner
	art.global_position = corner_world
	# Anything riding on the art (its authored Shape) stays
	# where it was in the world.
	for child in art.get_children():
		if child is Node2D:
			(child as Node2D).position -= corner


func apply_hit(_strength: float, is_over: bool) -> void:
	current_error_deg *= _get_error_left_share()
	if is_over:
		current_error_deg = -current_error_deg
	if absf(current_error_deg) <= done_threshold_deg:
		current_error_deg = 0.0
		_apply_error()
		if is_instance_valid(straight_art):
			art.hide()
			straight_art.show()
		finish()
	else:
		_apply_error()


func _apply_error() -> void:
	if is_instance_valid(art):
		art.rotation = _home_rotation + deg_to_rad(current_error_deg)


## The share of the error one hit leaves, spread so that
## `hits_to_straighten` hits land on the done threshold.
func _get_error_left_share() -> float:
	var start := maxf(absf(error_deg), done_threshold_deg + 0.01)
	var ratio := clampf(done_threshold_deg / start, 0.0, 1.0)
	return pow(ratio, 1.0 / maxf(float(hits_to_straighten), 1.0))
