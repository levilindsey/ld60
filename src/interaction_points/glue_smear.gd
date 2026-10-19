class_name GlueSmear
extends InteractionPoint
## A blob of glue squeezed where no point wanted it (docs/
## design/glue.md). It shows as a glue decal on the layer's
## art, and the rag wipes it off like grime. It is optional
## work: an item can finish with one still on it, and the
## item then charges a glue blob defect for each smear left.
## Cleaned smears cost nothing.

## How much glue there is. The wiping it needs scales it.
@export var amount := 1.0

## Wipe hit points left.
var hit_points_left := 0.0
## The glue decal that shows this smear, once placed.
var glue_decal: Sprite2D

var _total_hit_points := 1.0
var _base_alpha := 1.0


func _ready() -> void:
	super._ready()
	type = Type.GLUE_SMEAR
	role = Role.REPAIR
	is_required = false
	accepted_tools = [Tool.Type.RAG]
	_total_hit_points = maxf(amount, 0.01)
	hit_points_left = _total_hit_points


## Shows the smear as a glue decal on its layer's art. The
## glue tool calls this once it has placed the smear.
func setup_decal() -> void:
	if is_instance_valid(glue_decal):
		return
	var layer := get_layer()
	if not is_instance_valid(layer):
		return
	if not is_instance_valid(layer.art):
		return
	if not is_instance_valid(G.level):
		return
	glue_decal = G.level.spawn_decal(
		DecalSpawner.Kind.GLUE_BLOB,
		layer.art,
		global_position,
		52.0,
	)
	if is_instance_valid(glue_decal):
		_base_alpha = glue_decal.modulate.a


## The rag wiped over the smear. `damage` is hit points gone.
func on_wiped(damage: float, _delta: float) -> void:
	if mode == Mode.FINISHED or damage <= 0.0:
		return
	mode = Mode.ACTIVE
	hit_points_left = maxf(hit_points_left - damage, 0.0)
	if hit_points_left <= _total_hit_points * 0.1:
		_clean()
	elif is_instance_valid(glue_decal):
		glue_decal.modulate.a = (
			_base_alpha
			* clampf(hit_points_left / _total_hit_points, 0.0, 1.0)
		)


func _clean() -> void:
	hit_points_left = 0.0
	G.audio.play_sound(&"ding")
	finish()
	if is_instance_valid(glue_decal):
		glue_decal.queue_free()
	hide()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
