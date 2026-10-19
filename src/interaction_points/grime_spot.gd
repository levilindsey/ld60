class_name GrimeSpot
extends DirtSpot
## A patch of grime the rag wipes off (docs/design/solvent.md).
##
## It has hit points. The rag removes them while it drags over the
## spot, and the art fades with them. At a tenth left the rest clears
## at once, so nobody hunts the last speck. The art, its set and its
## color are configured on the shared `DirtSpot` base.


## How much grime there is. More draws a bigger patch.
@export var amount := 1.0
## How hard the grime is to wipe off. The wiping a spot needs
## is its amount times its toughness.
@export var toughness := 1.0

## Hit points left. It starts at the amount times toughness.
var hit_points_left := 0.0

var _total_hit_points := 1.0


func _ready() -> void:
	super._ready()
	type = Type.GRIME_SPOT
	role = Role.REPAIR
	_set_up_art()
	_art_home_scale *= sqrt(maxf(amount, 0.01))
	art.scale = _art_home_scale
	_total_hit_points = amount * toughness
	hit_points_left = _total_hit_points
	_update_alpha()


## The rag wiped over the spot. `damage` is hit points removed.
func on_wiped(damage: float, _delta: float) -> void:
	if mode == Mode.FINISHED or damage <= 0.0:
		return
	mode = Mode.ACTIVE
	hit_points_left = maxf(hit_points_left - damage, 0.0)
	if hit_points_left <= _total_hit_points * 0.1:
		_clean()
	else:
		_update_alpha()


func _clean() -> void:
	hit_points_left = 0.0
	_update_alpha()
	G.audio.play_sound(&"ding")
	finish()
	# Cleaned off, the patch no longer blocks what was under it.
	# A screw it covered can be worked again.
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(
				"disabled", true
			)


func _update_alpha() -> void:
	var fraction := 0.0
	if _total_hit_points > 0.0:
		fraction = clampf(
			hit_points_left / _total_hit_points, 0.0, 1.0
		)
	_set_art_alpha(fraction)
