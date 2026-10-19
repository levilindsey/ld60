class_name GlueSmear
extends InteractionPoint
## A blob of glue squeezed where no point wanted it (docs/
## design/glue.md). The rag wipes it off like grime. It is
## optional work: an item can finish with one still on it,
## and the item then charges a glue blob defect for each
## smear left. Cleaned smears cost nothing.

## How much glue there is. The wiping it needs scales it.
@export var amount := 1.0
## The blob art. It fades as the rag wipes.
@export var art: Polygon2D

## Wipe hit points left.
var hit_points_left := 0.0

var _total_hit_points := 1.0
var _base_alpha := 1.0


func _ready() -> void:
	super._ready()
	type = Type.GLUE_SMEAR
	role = Role.REPAIR
	is_required = false
	accepted_tools = [Tool.Type.RAG]
	G.check(is_instance_valid(art))
	_base_alpha = art.modulate.a
	_total_hit_points = maxf(amount, 0.01)
	hit_points_left = _total_hit_points


## The rag wiped over the smear. `damage` is hit points gone.
func on_wiped(damage: float, _delta: float) -> void:
	if mode == Mode.FINISHED or damage <= 0.0:
		return
	mode = Mode.ACTIVE
	hit_points_left = maxf(hit_points_left - damage, 0.0)
	if hit_points_left <= _total_hit_points * 0.1:
		_clean()
	elif is_instance_valid(art):
		art.modulate.a = (
			_base_alpha
			* clampf(hit_points_left / _total_hit_points, 0.0, 1.0)
		)


func _clean() -> void:
	hit_points_left = 0.0
	G.audio.play_sound(&"ding")
	finish()
	hide()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
