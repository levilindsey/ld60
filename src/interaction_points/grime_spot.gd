class_name GrimeSpot
extends InteractionPoint
## A patch of grime the rag wipes off (docs/design/solvent.md).
##
## It has hit points. The rag removes them while it drags over the
## spot, and the art fades with them. At a tenth left the rest clears
## at once, so nobody hunts the last speck. The grime sprite lands
## with LX24. Until then the scene draws a placeholder blob.


## The dirt art. It fades as the spot cleans.
@export var art: CanvasItem
## Hit points the spot starts with.
@export var hit_points := 1.0

## Hit points left.
var hit_points_left := 0.0


func _ready() -> void:
	super._ready()
	type = Type.GRIME_SPOT
	role = Role.REPAIR
	G.check(is_instance_valid(art))
	hit_points_left = hit_points
	_update_alpha()


## The rag wiped over the spot. `amount` is hit points removed.
func on_wiped(amount: float, _delta: float) -> void:
	if mode == Mode.FINISHED or amount <= 0.0:
		return
	mode = Mode.ACTIVE
	hit_points_left = maxf(hit_points_left - amount, 0.0)
	if hit_points_left <= hit_points * 0.1:
		_clean()
	else:
		_update_alpha()


func _clean() -> void:
	hit_points_left = 0.0
	_update_alpha()
	G.audio.play_sound(&"ding")
	finish()


func _update_alpha() -> void:
	if not is_instance_valid(art):
		return
	var fraction := 0.0
	if hit_points > 0.0:
		fraction = clampf(hit_points_left / hit_points, 0.0, 1.0)
	art.modulate.a = fraction
