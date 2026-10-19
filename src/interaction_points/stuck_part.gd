class_name StuckPart
extends StrikablePoint
## A stuck part the hammer jogs loose (docs/design/hammer.md).
## A few hits inside the band free it.


## Working hits that free the part.
@export var hits_needed := 3

## Working hits so far.
var hits_done := 0

## How wide the cross draws, in world pixels, on every item:
## the polygon is authored in the item's own units, so
## without this the cross came out a few pixels across on a
## scaled item (the radio at 0.12) and tens on another.
const _CROSS_SPAN_PX := 30.0

## The cross the scene draws for the part (its placeholder
## art). It only shows once the whack is the item's only
## step left; see `_is_only_step_left()`.
var _art: CanvasItem


func _ready() -> void:
	super._ready()
	type = Type.STUCK_PART
	role = Role.REPAIR
	_art = get_node_or_null("Art") as CanvasItem
	_size_cross()
	_update_art_visibility()


## Sizes the cross to `_CROSS_SPAN_PX` in the world, whatever
## scale the item gives this point.
func _size_cross() -> void:
	var polygon_art := _art as Polygon2D
	if not is_instance_valid(polygon_art):
		return
	if polygon_art.polygon.is_empty():
		return
	var bounds := Rect2(polygon_art.polygon[0], Vector2.ZERO)
	for point in polygon_art.polygon:
		bounds = bounds.expand(point)
	var span := maxf(bounds.size.x, bounds.size.y)
	var global_scale := absf(global_transform.get_scale().x)
	if span <= 0.0 or global_scale <= 0.0001:
		return
	polygon_art.scale = (
		Vector2.ONE * (_CROSS_SPAN_PX / span) / global_scale
	)


func _process(_delta: float) -> void:
	_update_art_visibility()


func _update_art_visibility() -> void:
	if is_instance_valid(_art):
		_art.visible = _is_only_step_left()


## True when this whack is the only work the item's sequence
## still offers: every other actionable step is done or out
## of reach, so hammering here is the last thing to do. The
## cross only shows then, instead of sitting on the item
## from the start.
func _is_only_step_left() -> bool:
	if mode == Mode.FINISHED:
		return false
	if not is_instance_valid(G.level):
		return false
	var item := get_item()
	if not is_instance_valid(item):
		return false
	if G.level.active_repairable != item:
		return false
	var sequence := item.get_repair_sequence()
	if not is_instance_valid(sequence):
		return false
	var is_up := false
	for step in sequence.steps:
		if step.kind == RepairStep.Kind.SHIP:
			continue
		if not step.is_actionable(G.level):
			continue
		if step.points.is_empty():
			# Layer or drawer work that is not a point.
			return false
		for point in step.get_candidate_points():
			if point != self:
				return false
		is_up = true
	return is_up


func apply_hit(_strength: float, _is_over: bool) -> void:
	hits_done += 1
	pulse()
	if hits_done >= hits_needed:
		G.audio.play_sound(&"lid_pop")
		finish()
