class_name StuckPart
extends StrikablePoint
## A stuck part the hammer jogs loose (docs/design/hammer.md).
## A few hits inside the band free it.


## Working hits that free the part.
@export var hits_needed := 3

## Working hits so far.
var hits_done := 0


func _ready() -> void:
	super._ready()
	type = Type.STUCK_PART
	role = Role.REPAIR


func apply_hit(_strength: float, _is_over: bool) -> void:
	hits_done += 1
	pulse()
	if hits_done >= hits_needed:
		G.audio.play_sound(&"lid_pop")
		finish()
