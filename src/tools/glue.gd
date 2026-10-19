class_name Glue
extends Tool
## The glue bottle (docs/design/glue.md). Press and hold to
## squeeze, then trace a crack to cover it, or dab a broken
## point so its piece can be held back on. Flooding a crack
## leaves a blob. Squeezing over a plain surface leaves a
## smear for the rag.


## How often an off-target squeeze smears, in seconds.
const _OFF_TARGET_BLOB_SEC := 0.5

## The bottle art. It squashes a little while squeezing.
@export var art: Node2D

var _is_squeezing := false
var _off_target_sec := 0.0


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(art))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _is_squeezing or delta <= 0.0:
		return
	var nozzle := get_tip_position()
	var amount := G.settings.glue_flow_rate * delta
	var hit := false
	if is_instance_valid(G.level) and is_instance_valid(
		G.level.active_repairable
	):
		for layer in G.level.active_repairable.layers:
			for point in layer.get_points():
				if not point.is_exposed():
					continue
				if not point.is_visible_in_tree():
					continue
				if point is Crack:
					if (point as Crack).on_glued(
						nozzle,
						G.settings.glue_radius_px,
						amount,
					):
						hit = true
				elif point is BrokenPoint:
					if (point as BrokenPoint).on_glued(
						nozzle,
						G.settings.glue_radius_px,
						amount,
					):
						hit = true
	if hit:
		_off_target_sec = 0.0
		return
	_off_target_sec += delta
	if _off_target_sec >= _OFF_TARGET_BLOB_SEC:
		_off_target_sec = 0.0
		_smear_on_surface(nozzle)


func is_effect_tool() -> bool:
	return true


## A press starts the squeeze where the nozzle lands.
func on_effect_pressed(_global_point: Vector2) -> void:
	_is_squeezing = true
	_off_target_sec = 0.0
	art.scale = Vector2(1.0, 0.9)
	if is_instance_valid(G.level):
		G.level.hand.set_input_owner(self)
	G.audio.play_sound(&"scrape")


func on_pointer_released(_global_point: Vector2) -> void:
	_stop_squeezing()


func put_away() -> void:
	_stop_squeezing()
	super.put_away()


func _stop_squeezing() -> void:
	_is_squeezing = false
	if is_instance_valid(art):
		art.scale = Vector2.ONE
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)


## Glue on a plain surface: a smear the rag can wipe off.
## It costs nothing while it can still be cleaned. An item
## that finishes with a smear on it pays for it then (see
## Repairable). A spot already smeared does not smear again.
func _smear_on_surface(at_position: Vector2) -> void:
	if not is_instance_valid(G.level):
		return
	if not is_instance_valid(G.settings.glue_smear_scene):
		return
	var surface := G.level.hand.find_surface(at_position)
	if not is_instance_valid(surface) or not surface.is_active():
		return
	var layer := surface.get_layer()
	if not is_instance_valid(layer) or not is_instance_valid(layer.art):
		return
	for point in layer.get_points():
		var smear := point as GlueSmear
		if not is_instance_valid(smear):
			continue
		if smear.mode == InteractionPoint.Mode.FINISHED:
			continue
		if smear.global_position.distance_to(at_position) < 30.0:
			return
	var smear := G.settings.glue_smear_scene.instantiate() as GlueSmear
	if not is_instance_valid(smear):
		return
	layer.add_child(smear)
	smear.global_position = at_position
	smear.rotation = randf() * TAU
	smear.reset_physics_interpolation()
